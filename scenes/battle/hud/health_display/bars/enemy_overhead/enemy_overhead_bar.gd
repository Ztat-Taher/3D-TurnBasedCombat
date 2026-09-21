## EnemyOverheadBar
## A screen-projected overhead health bar attached to an enemy battler.
## Rendered in native CanvasLayer resolution to prevent pixelation from the 3D PSX viewport.
## Includes 3D line-of-sight raycast occlusion and distance-based depth sorting.
extends Control

## Emitted after death fade-out finishes so parent containers can clean up.
signal bar_died

var enemy_battler: Battler = null
var _camera: Camera3D = null
var _viewport_scale: Vector2 = Vector2.ONE
var _is_dying: bool = false
var _target_alpha: float = 0.0

# Height offset (world units) above the battler's origin
const HEIGHT_OFFSET := 2.4

@onready var background: Panel = $Background
@onready var name_label: Label = $Background/VBox/NameLabel
@onready var hp_bar: TextureProgressBar = $Background/VBox/HPContainer/HPBar
@onready var hp_damage_bar: TextureProgressBar = $Background/VBox/HPContainer/HPDamageBar
@onready var hp_label: Label = $Background/VBox/HPContainer/HPBar/HPNumLabel
@onready var hp_juice: ProgressBarJuice = $Background/VBox/HPContainer/HPJuice
@onready var portrait_background: TextureRect = $Background/PortraitBackground
@onready var status_icons_container: StatusIconsContainer = $Background/StatusIconsContainer
@onready var status_icon_template: TextureRect = $Background/StatusIconsContainer/StatusIconTemplate
@onready var shield_container: HBoxContainer = $Background/VBox/HPContainer/HPBar/ShieldContainer
@onready var shield_template: TextureRect = $Background/VBox/HPContainer/HPBar/ShieldContainer/Shield

func _ready() -> void:
	# Start invisible until we have a valid battler and screen position
	modulate.a = 0.0
	_target_alpha = 0.0

func setup(battler: Battler) -> void:
	enemy_battler = battler
	# Connect to health signal
	if not battler.health_changed.is_connected(_on_health_changed):
		battler.health_changed.connect(_on_health_changed)
	
	# Connect to shield changes
	if battler.has_signal("shield_changed") and not battler.shield_changed.is_connected(_on_shield_changed):
		battler.shield_changed.connect(_on_shield_changed)
	
	# Setup status icons container with the reusable component
	if status_icons_container and status_icon_template:
		status_icons_container.setup(battler, status_icon_template)
	
	# Initial shield update
	update_shields()

	# Setup juice component if it exists
	if hp_juice:
		hp_juice.setup(hp_bar, hp_damage_bar, hp_label)
		hp_juice.enable_healing_feedback = true
		hp_juice.enable_critical_health = true

	# Initialize values
	hp_bar.max_value = battler.max_health
	hp_bar.value = battler.current_health
	if hp_damage_bar:
		hp_damage_bar.max_value = battler.max_health
		hp_damage_bar.value = battler.current_health
	name_label.text = battler.character_name
	_update_hp_label(battler.current_health, battler.max_health)
	
	# Set portrait if it exists on battler stats
	if portrait_background and battler.stats and battler.stats.thumbnail:
		portrait_background.texture = battler.stats.thumbnail

	# Ensure pivot is centered for scaling
	pivot_offset = custom_minimum_size / 2.0

	# Dramatic entrance with scale
	modulate.a = 0.0
	_target_alpha = 1.0
	scale = Vector2(1.2, 1.6)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(2.0, 2.0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _process(delta: float) -> void:
	if not is_instance_valid(enemy_battler) or _is_dying:
		return

	_resolve_camera()
	if not _camera or not is_instance_valid(_camera):
		return

	# Determine world-space anchor above enemy
	var height: float = HEIGHT_OFFSET
	if "height" in enemy_battler:
		height = float(enemy_battler.height)
	
	var world_pos := enemy_battler.global_position + Vector3(0.0, height, 0.0)

	# Behind camera check
	if _camera.is_position_behind(world_pos):
		_target_alpha = 0.0
		modulate.a = move_toward(modulate.a, 0.0, delta * 8.0)
		return

	# Depth sorting: closer enemies get higher z_index so their bars draw in front of distant bars.
	# Clamped to 1..50 so they always remain under interactive menus, tooltips, and action buttons.
	var cam_dist := _camera.global_position.distance_to(world_pos)
	z_index = clampi(int(50.0 - cam_dist), 1, 50)

	# 3D Line-of-Sight Occlusion Raycast
	var is_occluded := _is_line_of_sight_occluded(world_pos)
	if is_occluded:
		_target_alpha = 0.0
	else:
		_target_alpha = 1.0

	# Smoothly transition opacity to avoid popping
	modulate.a = move_toward(modulate.a, _target_alpha, delta * 6.0)

	# Project 3D world position to HUD screen space
	var screen_pos := _camera.unproject_position(world_pos) * _viewport_scale
	position = screen_pos - size * 0.5

## Casts a ray from the camera to the enemy's anchor point to verify whether
## another 3D character or obstacle is obstructing the view.
func _is_line_of_sight_occluded(target_world_pos: Vector3) -> bool:
	if not _camera or not is_inside_tree():
		return false

	var world_3d := _camera.get_world_3d()
	if not world_3d:
		return false

	var space_state := world_3d.direct_space_state
	if not space_state:
		return false

	var cam_pos := _camera.global_position
	# Ray from camera towards target point, stopping slightly before the target
	var dir := target_world_pos - cam_pos
	var dist := dir.length()
	if dist <= 0.01:
		return false

	# Exclude the target enemy battler and its collision bodies
	var exclude_rids: Array[RID] = []
	_gather_rids(enemy_battler, exclude_rids)

	var ray_end := cam_pos + dir.normalized() * maxf(0.0, dist - 0.2)
	var query := PhysicsRayQueryParameters3D.create(cam_pos, ray_end)
	query.exclude = exclude_rids
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := space_state.intersect_ray(query)
	return not hit.is_empty()

func _gather_rids(node: Node, rids: Array[RID]) -> void:
	if not node:
		return
	if node is CollisionObject3D:
		rids.append(node.get_rid())
	for child in node.get_children():
		_gather_rids(child, rids)

## Resolve the gameplay camera once through the BattleManager's BattleCamera
## controller (the camera lives inside the low-res SubViewport).
func _resolve_camera() -> void:
	if _camera and is_instance_valid(_camera):
		return
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		return
	var battle_camera = battle_manager.battle_camera
	if not battle_camera:
		return
	var cam: Camera3D = battle_camera.get_camera()
	if cam:
		_camera = cam
		_viewport_scale = battle_camera.get_viewport_scale()

func _on_health_changed(current: int, maximum: int) -> void:
	if not is_instance_valid(self):
		return
	
	if hp_juice:
		hp_juice.update_value(float(current), float(maximum))
	elif hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = float(current)
		if hp_damage_bar:
			hp_damage_bar.max_value = maximum
			hp_damage_bar.value = float(current)
		_update_hp_label(current, maximum)

	# Hide when dead
	if current <= 0:
		_is_dying = true
		var out := create_tween()
		out.tween_property(self, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
		out.tween_callback(func() -> void:
			bar_died.emit()
			queue_free()
		)

func _update_hp_label(current: int, maximum: int) -> void:
	if hp_label:
		hp_label.text = "%d / %d" % [current, maximum]

func update_shields() -> void:
	if not shield_container or not enemy_battler:
		return
	
	# Clear existing shields
	for child in shield_container.get_children():
		if child != shield_template:
			child.queue_free()
	
	# Check for Protected state
	if enemy_battler.active_states.has("Protected"):
		var protected_state = enemy_battler.active_states["Protected"] as ProtectedState
		if protected_state and protected_state.has_shield():
			var shield_count = protected_state.get_remaining_shields()
			# Add shield icons for each remaining shield
			for i in range(shield_count):
				var shield = shield_template.duplicate()
				shield.visible = true
				shield_container.add_child(shield)

func _on_shield_changed(shield_count: int) -> void:
	update_shields()
