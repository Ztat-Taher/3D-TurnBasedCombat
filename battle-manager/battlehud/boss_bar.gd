## BossBar
## Cinematic top-center boss health bar anchored to the HUD.
## Activated when a battler marked as a boss becomes the active enemy.
extends Control

var boss_battler: Battler = null

@onready var boss_name_label: Label = $VBox/BossNameLabel
@onready var boss_hp_bar: TextureProgressBar = $VBox/HPBarContainer/HPBar
@onready var boss_hp_damage_bar: TextureProgressBar = $VBox/HPBarContainer/HPDamageBar
@onready var boss_hp_label: Label = $VBox/HPBarContainer/HPNumLabel
@onready var background_shader: ColorRect = $BackgroundShader

@onready var boss_hp_juice: ProgressBarJuice = $VBox/HPBarContainer/HPJuice

var card_shader: Shader = null

func _ready() -> void:
	visible = false

## Show and bind to a boss battler.
func show_boss(battler: Battler) -> void:
	if boss_battler and boss_battler.health_changed.is_connected(_on_boss_health_changed):
		boss_battler.health_changed.disconnect(_on_boss_health_changed)

	boss_battler = battler
	
	# Create unique shader material for this boss bar
	if background_shader:
		if not card_shader:
			card_shader = load("res://assets/shaders/ui_background_shader.gdshader")
		var unique_material = ShaderMaterial.new()
		unique_material.shader = card_shader
		background_shader.material = unique_material
	
	# Setup juice component if it exists
	if boss_hp_juice:
		boss_hp_juice.setup(boss_hp_bar, boss_hp_damage_bar, boss_hp_label)
		boss_hp_juice.enable_healing_feedback = true
		boss_hp_juice.enable_critical_health = true
		# More dramatic boss effects
		boss_hp_juice.critical_pulse_color = Color(2.5, 0.3, 0.3, 1.0)
		boss_hp_juice.critical_pulse_interval = 0.6
		boss_hp_juice.damage_scale_pulse = Vector2(1.1, 1.2)
	
	boss_name_label.text = battler.character_name.to_upper()
	boss_hp_bar.max_value = battler.max_health
	boss_hp_bar.value = battler.current_health
	if boss_hp_damage_bar:
		boss_hp_damage_bar.max_value = battler.max_health
		boss_hp_damage_bar.value = battler.current_health
	_update_hp_label(battler.current_health, battler.max_health)

	battler.health_changed.connect(_on_boss_health_changed)

	visible = true
	modulate.a = 0.0
	scale = Vector2(0.8, 0.5)
	
	# Dramatic entrance animation
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(self, "scale", Vector2(1.0, 1.0), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	
	# Name label slam effect using position
	var original_pos = boss_name_label.position
	var slam_tween := create_tween()
	slam_tween.tween_property(boss_name_label, "position:y", original_pos.y - 20.0, 0.15).set_ease(Tween.EASE_OUT)
	slam_tween.tween_property(boss_name_label, "position:y", original_pos.y, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)

## Hide and disconnect the boss bar.
func hide_boss() -> void:
	if boss_battler and boss_battler.health_changed.is_connected(_on_boss_health_changed):
		boss_battler.health_changed.disconnect(_on_boss_health_changed)
	boss_battler = null
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.4)
	t.tween_callback(func(): visible = false)

func _on_boss_health_changed(current: int, maximum: int) -> void:
	if not is_instance_valid(self):
		return
	
	if boss_hp_juice:
		boss_hp_juice.update_value(float(current), float(maximum))
	elif boss_hp_bar:
		boss_hp_bar.max_value = maximum
		boss_hp_bar.value = float(current)
		if boss_hp_damage_bar:
			boss_hp_damage_bar.max_value = maximum
			boss_hp_damage_bar.value = float(current)
		_update_hp_label(current, maximum)

	if current <= 0:
		hide_boss()

func _update_hp_label(current: int, maximum: int) -> void:
	if boss_hp_label:
		boss_hp_label.text = "%d / %d" % [current, maximum]
