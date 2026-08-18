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
var camera_shake: CameraShake

var _default_transform: Transform3D
var _default_fov: float

@export var ots_camera_scene: PackedScene = preload("res://battle-manager/cameras/over_the_shoulder_camera.tscn")
@export var overview_camera_scene: PackedScene = preload("res://battle-manager/cameras/enemy_overview_camera.tscn")
@export var focus_camera_scene: PackedScene = preload("res://battle-manager/cameras/target_focus_camera.tscn")

@export var transition_duration: float = 0.45
@export var fov_padding: float = 1.3 # Multiplier to add some padding around the subject

# Cached instances (kept out of tree)
var _ots_instance: Camera3D
var _overview_instance: Camera3D
var _focus_instance: Camera3D

func _ready() -> void:
	call_deferred("_setup_camera")
	_setup_camera_shake()

func _setup_camera() -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()
	if not camera:
		var parent_camera = get_parent().get_node_or_null("Camera3D")
		if parent_camera is Camera3D:
			camera = parent_camera
	if not camera:
		camera = get_tree().get_first_node_in_group("battle_camera") as Camera3D
		
	if camera:
		_default_transform = camera.global_transform
		_default_fov = camera.fov

func _setup_camera_shake() -> void:
	camera_shake = CameraShake.new()
	add_child(camera_shake)
	call_deferred("_connect_camera_shake")

func _connect_camera_shake() -> void:
	if camera_shake and camera:
		camera_shake.set_camera(camera)

func get_camera_shake() -> CameraShake:
	return camera_shake

func set_default_camera() -> void:
	current_mode = CameraMode.DEFAULT
	if not camera:
		return
	_animate_camera(_default_transform, _default_fov)

func _get_or_create_instance(scene: PackedScene, cached_instance: Camera3D) -> Camera3D:
	if is_instance_valid(cached_instance):
		return cached_instance
	if scene:
		var instance = scene.instantiate() as Camera3D
		if instance:
			return instance
	return null

func _calculate_dynamic_fov(camera_global_pos: Vector3, target_nodes: Array) -> float:
	var combined_aabb := AABB()
	var has_bounds := false
	
	for node in target_nodes:
		if not is_instance_valid(node):
			continue
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
	
	# Apply padding and clamp
	return clamp(needed_fov_deg * fov_padding, 30.0, 100.0)

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
		var target_fov = _calculate_dynamic_fov(target_transform.origin, [player_battler])
		
		# Optional: Use prefab's base FOV if dynamic is too small
		target_fov = max(target_fov, _ots_instance.fov)
		
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
		
		var target_fov = _calculate_dynamic_fov(target_transform.origin, valid_enemies)
		target_fov = max(target_fov, _overview_instance.fov)
		
		_animate_camera(target_transform, target_fov)

func set_target_focus(target_battler: Battler) -> void:
	current_mode = CameraMode.TARGET_FOCUS
	if not camera or not target_battler or not is_instance_valid(target_battler):
		return
		
	_focus_instance = _get_or_create_instance(focus_camera_scene, _focus_instance)
	if _focus_instance:
		var target_transform = target_battler.global_transform * _focus_instance.transform
		var target_fov = _calculate_dynamic_fov(target_transform.origin, [target_battler])
		target_fov = max(target_fov, _focus_instance.fov)
		
		_animate_camera(target_transform, target_fov)

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
