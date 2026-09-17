## EnemyOverheadBar
## A screen-projected overhead health bar attached to an enemy battler.
## Instantiated by BattleHUD for each enemy that enters battle.
extends Control

var enemy_battler: Battler = null
var _camera: Camera3D = null
var _viewport_scale: Vector2 = Vector2.ONE
var _is_dying: bool = false

# Height offset (world units) above the battler's origin
const HEIGHT_OFFSET := 2.4

@onready var background: TextureRect = $Background
@onready var name_label: Label = $Background/VBox/NameLabel
@onready var hp_bar: TextureProgressBar = $Background/VBox/HPContainer/HPBar
@onready var hp_damage_bar: TextureProgressBar = $Background/VBox/HPContainer/HPDamageBar
@onready var hp_label: Label = $Background/VBox/HPContainer/HPBar/HPNumLabel
@onready var hp_juice: ProgressBarJuice = $Background/VBox/HPContainer/HPJuice
@onready var portrait_background: TextureRect = $Background/PortraitBackground

func _ready() -> void:
	# Start invisible until we have a valid battler
	modulate.a = 0.0

func setup(battler: Battler) -> void:
	enemy_battler = battler
	# Connect to health signal
	if not battler.health_changed.is_connected(_on_health_changed):
		battler.health_changed.connect(_on_health_changed)

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

	# Ensure pivot is centered for scaling (use custom_minimum_size since
	# the layout may not have been computed yet at setup time)
	pivot_offset = custom_minimum_size / 2.0

	# Dramatic fade in with scale
	modulate.a = 0.0
	scale = Vector2(0.6, 0.8)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2(1.0, 1.0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _process(_delta: float) -> void:
	if not is_instance_valid(enemy_battler) or _is_dying:
		return

	_resolve_camera()
	if not _camera:
		return

	# Project world position to screen
	# We use the battler's character height if available, or a default offset
	var height = HEIGHT_OFFSET
	if "height" in enemy_battler:
		height = enemy_battler.height
	
	var world_pos := enemy_battler.global_position + Vector3(0, height, 0)
	if _camera.is_position_behind(world_pos):
		modulate.a = 0.0
		return

	modulate.a = 1.0
	# The camera renders at the SubViewport's low resolution, so scale the
	# projected point back up into root HUD space.
	var screen_pos := _camera.unproject_position(world_pos) * _viewport_scale
	# Centre the bar on the projected point
	position = screen_pos - size * 0.5

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
		out.tween_callback(queue_free)

func _update_hp_label(current: int, maximum: int) -> void:
	if hp_label:
		hp_label.text = "%d / %d" % [current, maximum]
