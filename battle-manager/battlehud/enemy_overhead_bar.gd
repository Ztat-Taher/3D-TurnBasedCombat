## EnemyOverheadBar
## A screen-projected overhead health bar attached to an enemy battler.
## Instantiated by BattleHUD for each enemy that enters battle.
extends Control

var enemy_battler: Battler = null
var _camera: Camera3D = null
var _is_dying: bool = false

# Height offset (world units) above the battler's origin
const HEIGHT_OFFSET := 2.4

@onready var hp_bar: ProgressBar = $BG/VBox/HPBarRow/HPBar
@onready var name_label: Label = $BG/VBox/NameLabel
@onready var hp_label: Label = $BG/VBox/HPBarRow/HPLabel

func _ready() -> void:
	# Start invisible until we have a valid battler
	modulate.a = 0.0

func setup(battler: Battler) -> void:
	enemy_battler = battler
	# Connect to health signal
	if not battler.health_changed.is_connected(_on_health_changed):
		battler.health_changed.connect(_on_health_changed)

	# Initialize values
	hp_bar.max_value = battler.max_health
	hp_bar.value = battler.current_health
	name_label.text = battler.character_name
	_update_hp_label(battler.current_health, battler.max_health)

	# Fade in
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, 0.3)

func _process(_delta: float) -> void:
	if not is_instance_valid(enemy_battler) or _is_dying:
		return

	if not _camera:
		_camera = get_viewport().get_camera_3d()
	if not _camera:
		return

	# Project world position to screen
	var world_pos := enemy_battler.global_position + Vector3(0, HEIGHT_OFFSET, 0)
	if _camera.is_position_behind(world_pos):
		modulate.a = 0.0
		return

	modulate.a = 1.0
	var screen_pos := _camera.unproject_position(world_pos)
	# Centre the bar on the projected point
	position = screen_pos - size * 0.5

func _on_health_changed(current: int, maximum: int) -> void:
	if not is_instance_valid(self):
		return
	var previous_value := hp_bar.value
	hp_bar.max_value = maximum
	# Smooth bar tween
	var t := create_tween()
	t.tween_property(hp_bar, "value", float(current), 0.25).set_ease(Tween.EASE_OUT)
	_update_hp_label(current, maximum)

	# Flash red on damage
	if float(current) < previous_value:
		var flash := create_tween()
		flash.tween_property(self, "modulate", Color(1.5, 0.5, 0.5, 1.0), 0.08)
		flash.tween_property(self, "modulate", Color.WHITE, 0.2)

	# Hide when dead
	if current <= 0:
		_is_dying = true
		var out := create_tween()
		out.tween_property(self, "modulate:a", 0.0, 0.4)
		out.tween_callback(queue_free)

func _update_hp_label(current: int, maximum: int) -> void:
	if hp_label:
		hp_label.text = "%d / %d" % [current, maximum]
