class_name BattleCamera
extends Node
## Dynamic 3D Combat Camera Controller
## Manages over-the-shoulder, enemy overview, and target focus camera transitions using instanced scenes.

enum CameraMode {
	DEFAULT,
	OVER_THE_SHOULDER,
	ENEMY_OVERVIEW,
	TARGET_FOCUS
}

var camera: Camera3D
var current_mode: CameraMode = CameraMode.DEFAULT
var tween: Tween

var _default_transform: Transform3D
var default_fov: float  # Public accessor for default FOV
var _fov_tween: Tween
var _target_fov_tween: Tween
var _distance_tween: Tween
var _evasion_distance_offset: float = 0.0

@export var ots_camera_scene: PackedScene = preload("res://scenes/battle/cameras/perspective/over_the_shoulder_camera.tscn")
@export var overview_camera_scene: PackedScene = preload("res://scenes/battle/cameras/overview/enemy_overview_camera.tscn")
@export var focus_camera_scene: PackedScene = preload("res://scenes/battle/cameras/focus/target_focus_camera.tscn")

@export var transition_duration: float = 0.45
@export var fov_padding: float = 1.3 # Multiplier to add some padding around the subject
@export var wide_fov_padding: float = 2.0 # Higher padding for wide shots (overview, over-the-shoulder)

# Cached instances (kept out of tree)
var _ots_instance: Camera3D
var _overview_instance: Camera3D
var _focus_instance: Camera3D

func _ready() -> void:
	call_deferred("_setup_camera")

func _setup_camera() -> void:
	if not camera or not is_instance_valid(camera):
		camera = _find_camera()
	if camera:
		_default_transform = camera.global_transform
		default_fov = camera.fov
		_evasion_distance_offset = 0.0

## Resolves the gameplay Camera3D wherever it lives:
##  - the active camera of this controller's own viewport (legacy layout)
##  - a Camera3D child of the parent node (legacy layout)
##  - a camera in the "battle_camera" group (recommended for SubViewport layouts)
##  - any active camera found inside a SubViewport of the current scene
func _find_camera() -> Camera3D:
	if not is_inside_tree():
		return null
	# 1) Active camera of our own viewport.
	var own_cam := get_viewport().get_camera_3d()
	if own_cam is Camera3D:
		return own_cam
	# 2) A Camera3D child of our parent (legacy battle layout).
	var parent := get_parent()
	if parent:
		var parent_camera = parent.get_node_or_null("Camera3D")
		if parent_camera is Camera3D:
			return parent_camera
	# 3) Explicit group hook (recommended for SubViewport battle layouts).
	var grouped := get_tree().get_first_node_in_group("battle_camera")
	if grouped is Camera3D:
		return grouped
	# 4) Generic fallback: scan SubViewports in the current scene.
	for viewport in _find_sub_viewports(get_tree().current_scene):
		var sub_cam := viewport.get_camera_3d()
		if sub_cam:
			return sub_cam
	return null

func _find_sub_viewports(node: Node) -> Array[SubViewport]:
	var result: Array[SubViewport] = []
	if node == null:
		return result
	if node is SubViewport:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_sub_viewports(child))
	return result

func set_default_camera() -> void:
	current_mode = CameraMode.DEFAULT
	if not camera:
		return
	_animate_camera(_default_transform, default_fov)

## Returns the resolved gameplay camera (re-resolves on demand).
func get_camera() -> Camera3D:
	if not camera or not is_instance_valid(camera):
		camera = _find_camera()
	return camera

## Ratio between the root HUD viewport's coordinate space and the gameplay
## SubViewport's render space (e.g. 2x when a 640x360 viewport fills a 1280x720
## window). Unprojected camera coordinates must be multiplied by this to land in
## root HUD space.
func get_viewport_scale() -> Vector2:
	var cam := get_camera()
	if not cam:
		return Vector2.ONE
	var vp := cam.get_viewport()
	if not vp:
		return Vector2.ONE
	var view_size := Vector2(vp.get_visible_rect().size)
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return Vector2.ONE
	var root_vp := get_viewport()
	if not root_vp:
		return Vector2.ONE
	var root_size := Vector2(root_vp.get_visible_rect().size)
	if root_size.x <= 0.0 or root_size.y <= 0.0:
		return Vector2.ONE
	return Vector2(root_size.x / view_size.x, root_size.y / view_size.y)

## Project a world-space position into root HUD screen coordinates.
func world_to_screen(world_pos: Vector3) -> Vector2:
	var cam := get_camera()
	if not cam:
		return Vector2.ZERO
	return cam.unproject_position(world_pos) * get_viewport_scale()

## Convert a root-HUD screen point to the gameplay camera's viewport space.
func screen_to_viewport(screen_point: Vector2) -> Vector2:
	return screen_point / get_viewport_scale()

## World-space ray origin for a root-HUD mouse position (used for mouse
## targeting while the camera lives inside a low-res SubViewport).
func project_ray_origin(screen_point: Vector2) -> Vector3:
	var cam := get_camera()
	if not cam:
		return Vector3.ZERO
	return cam.project_ray_origin(screen_to_viewport(screen_point))

## World-space ray direction for a root-HUD mouse position.
func project_ray_normal(screen_point: Vector2) -> Vector3:
	var cam := get_camera()
	if not cam:
		return Vector3.ZERO
	return cam.project_ray_normal(screen_to_viewport(screen_point))

## True if a world-space position is behind the gameplay camera.
func is_position_behind(world_pos: Vector3) -> bool:
	var cam := get_camera()
	if not cam:
		return false
	return cam.is_position_behind(world_pos)

func _get_or_create_instance(scene: PackedScene, cached_instance: Camera3D) -> Camera3D:
	if is_instance_valid(cached_instance):
		return cached_instance
	if scene:
		var instance = scene.instantiate() as Camera3D
		if instance:
			return instance
	return null

func _calculate_dynamic_fov(camera_global_pos: Vector3, target_nodes: Array, use_wide_padding: bool = false) -> float:
	var combined_aabb := AABB()
	var has_bounds := false

	for node in target_nodes:
		if not is_instance_valid(node):
			continue

		# If the node is a Battler, use its cached combined AABB method
		if node is Battler and node.has_method("get_combined_aabb"):
			var battler_aabb = node.get_combined_aabb()
			# Transform local AABB to global space
			var global_center = node.global_transform * battler_aabb.get_center()
			var global_size = battler_aabb.size * node.global_transform.basis.get_scale()
			var global_aabb = AABB(global_center - global_size/2.0, global_size)

			if not has_bounds:
				combined_aabb = global_aabb
				has_bounds = true
			else:
				combined_aabb = combined_aabb.merge(global_aabb)
		else:
			# Fallback to finding all VisualInstance3D children
			var visuals = _find_all_visuals(node)
			for vis in visuals:
				if vis is VisualInstance3D:
					var vis_aabb = vis.get_aabb()
					# Approximate global AABB
					var global_center = vis.global_transform * vis_aabb.get_center()
					var global_size = vis_aabb.size * vis.global_transform.basis.get_scale()
					var global_aabb = AABB(global_center - global_size/2.0, global_size)

					if not has_bounds:
						combined_aabb = global_aabb
						has_bounds = true
					else:
						combined_aabb = combined_aabb.merge(global_aabb)

	if not has_bounds or combined_aabb.size == Vector3.ZERO:
		return 75.0 # Fallback default FOV

	var dist = camera_global_pos.distance_to(combined_aabb.get_center())
	if dist < 0.1:
		return 75.0

	# Get the largest dimension of the AABB
	var max_size = max(combined_aabb.size.x, max(combined_aabb.size.y, combined_aabb.size.z))

	# Basic trigonometry: tan(fov/2) = (size/2) / dist
	var needed_fov_rad = 2.0 * atan((max_size / 2.0) / dist)
	var needed_fov_deg = rad_to_deg(needed_fov_rad)

	# Apply padding - use wider padding for overview/OTS shots to fit everything
	var padding = wide_fov_padding if use_wide_padding else fov_padding
	return clamp(needed_fov_deg * padding, 30.0, 120.0)

func _find_all_visuals(node: Node) -> Array[Node]:
	var visuals: Array[Node] = []
	if node is VisualInstance3D:
		visuals.append(node)
	for child in node.get_children():
		visuals.append_array(_find_all_visuals(child))
	return visuals

func set_over_the_shoulder(player_battler: Battler) -> void:
	current_mode = CameraMode.OVER_THE_SHOULDER
	if not camera or not player_battler or not is_instance_valid(player_battler):
		return

	_ots_instance = _get_or_create_instance(ots_camera_scene, _ots_instance)
	if _ots_instance:
		# Calculate global transform by applying prefab's local transform to the battler's global transform
		var target_transform = player_battler.global_transform * _ots_instance.transform

		# Use prefab's default FOV and position (no distance adjustment)
		var target_fov = _ots_instance.fov

		_animate_camera(target_transform, target_fov)

func set_enemy_overview(enemies: Array) -> void:
	current_mode = CameraMode.ENEMY_OVERVIEW
	if not camera or enemies.is_empty():
		return

	var center_pos = Vector3.ZERO
	var count = 0
	var valid_enemies = []
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy is Battler:
			center_pos += enemy.global_position
			count += 1
			valid_enemies.append(enemy)

	if count == 0:
		return
	center_pos /= float(count)

	_overview_instance = _get_or_create_instance(overview_camera_scene, _overview_instance)
	if _overview_instance:
		# Create a basis that looks roughly from the enemies towards the players (assuming players are around Z=0)
		# For now, just use an identity basis at the center position
		var center_transform = Transform3D(Basis(), center_pos)
		var target_transform = center_transform * _overview_instance.transform

		# Keep original FOV, adjust distance instead
		var target_fov = _overview_instance.fov
		var adjusted_transform = _adjust_distance_for_aabb(target_transform, valid_enemies, true)

		_animate_camera(adjusted_transform, target_fov)

func set_target_focus(target_battler: Battler) -> void:
	current_mode = CameraMode.TARGET_FOCUS
	if not camera or not target_battler or not is_instance_valid(target_battler):
		return

	_focus_instance = _get_or_create_instance(focus_camera_scene, _focus_instance)
	if _focus_instance:
		var target_transform = target_battler.global_transform * _focus_instance.transform

		# Keep original FOV, adjust distance instead
		var target_fov = _focus_instance.fov
		var adjusted_transform = _adjust_distance_for_aabb(target_transform, [target_battler], false)

		_animate_camera(adjusted_transform, target_fov)

func _animate_camera(target_transform: Transform3D, target_fov: float) -> void:
	if not camera or not is_instance_valid(camera):
		return
	if tween and tween.is_running():
		tween.kill()

	tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EaseType.EASE_OUT)
	tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	tween.tween_property(camera, "global_transform", target_transform, transition_duration)
	tween.tween_property(camera, "fov", target_fov, transition_duration)

## Adjust camera distance to fit target AABBs without changing FOV
## Returns adjusted transform with camera moved to appropriate distance
func _adjust_distance_for_aabb(target_transform: Transform3D, target_nodes: Array, use_wide_padding: bool = false) -> Transform3D:
	var combined_aabb := AABB()
	var has_bounds := false

	for node in target_nodes:
		if not is_instance_valid(node):
			continue

		# If the node is a Battler, use its cached combined AABB method
		if node is Battler and node.has_method("get_combined_aabb"):
			var battler_aabb = node.get_combined_aabb()
			# Transform local AABB to global space
			var global_center = node.global_transform * battler_aabb.get_center()
			var global_size = battler_aabb.size * node.global_transform.basis.get_scale()
			var global_aabb = AABB(global_center - global_size/2.0, global_size)

			if not has_bounds:
				combined_aabb = global_aabb
				has_bounds = true
			else:
				combined_aabb = combined_aabb.merge(global_aabb)
		else:
			# Fallback to finding all VisualInstance3D children
			var visuals = _find_all_visuals(node)
			for vis in visuals:
				if vis is VisualInstance3D:
					var vis_aabb = vis.get_aabb()
					# Approximate global AABB
					var global_center = vis.global_transform * vis_aabb.get_center()
					var global_size = vis_aabb.size * vis.global_transform.basis.get_scale()
					var global_aabb = AABB(global_center - global_size/2.0, global_size)

					if not has_bounds:
						combined_aabb = global_aabb
						has_bounds = true
					else:
						combined_aabb = combined_aabb.merge(global_aabb)

	if not has_bounds or combined_aabb.size == Vector3.ZERO:
		return target_transform  # No adjustment needed

	var camera_pos = target_transform.origin
	var combined_size = combined_aabb.size
	var max_size = max(combined_size.x, max(combined_size.y, combined_size.z))

	# Calculate required distance to fit AABB in current FOV
	# FOV is in degrees, convert to radians
	var fov_rad = deg_to_rad(camera.fov)
	# tan(fov/2) = (size/2) / distance  =>  distance = (size/2) / tan(fov/2)
	var required_distance = (max_size / 2.0) / tan(fov_rad / 2.0)

	# Apply padding
	var padding = wide_fov_padding if use_wide_padding else fov_padding
	required_distance *= padding

	# Calculate direction from AABB center to camera
	var aabb_center = combined_aabb.get_center()
	var direction = (camera_pos - aabb_center).normalized()

	# Move camera to required distance
	var new_camera_pos = aabb_center + direction * required_distance

	# Preserve camera orientation, only change position
	var adjusted_transform = target_transform
	adjusted_transform.origin = new_camera_pos

	return adjusted_transform

## Adjust camera distance for evasion maneuvers (dodge/jump)
## Moves camera back by specified distance offset
func adjust_camera_distance_for_evasion(distance_offset: float, duration: float) -> void:
	if not camera or not is_instance_valid(camera):
		return

	# Cancel existing distance tween
	if _distance_tween and _distance_tween.is_valid():
		_distance_tween.kill()

	_evasion_distance_offset = distance_offset

	# Move camera BACK (opposite to look direction) to zoom out and fit more in frame
	var camera_forward = -camera.global_transform.basis.z.normalized()
	var target_position = camera.global_position - camera_forward * distance_offset

	_distance_tween = camera.create_tween()
	_distance_tween.set_ease(Tween.EaseType.EASE_OUT)
	_distance_tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	_distance_tween.tween_property(camera, "global_position", target_position, duration)

## Reset camera distance after evasion maneuvers
func reset_camera_distance() -> void:
	if not camera or not is_instance_valid(camera):
		return

	if _evasion_distance_offset == 0.0:
		return  # No offset to reset

	# Cancel existing distance tween
	if _distance_tween and _distance_tween.is_valid():
		_distance_tween.kill()

	# Tween back to original position for smooth reset
	var camera_forward = -camera.global_transform.basis.z.normalized()
	var target_position = camera.global_position + camera_forward * _evasion_distance_offset

	_distance_tween = camera.create_tween()
	_distance_tween.set_ease(Tween.EaseType.EASE_OUT)
	_distance_tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	_distance_tween.tween_property(camera, "global_position", target_position, 0.15)

	_evasion_distance_offset = 0.0
