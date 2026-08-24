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
	boss_hp_bar.max_value = maximum
	
	var previous_value = boss_hp_bar.value
	
	# Dual-layer effect: main bar instantly updates, damage bar smoothly catches up
	boss_hp_bar.value = float(current)
	
	if boss_hp_damage_bar:
		boss_hp_damage_bar.max_value = maximum
		var damage_tween := create_tween()
		damage_tween.tween_property(boss_hp_damage_bar, "value", float(current), 0.7).set_ease(Tween.EASE_OUT)
	
	_update_hp_label(current, maximum)

	# Damage feedback with more juice
	if float(current) < previous_value:
		# Red flash
		var flash := create_tween()
		flash.tween_property(boss_hp_bar, "modulate", Color(2.0, 0.2, 0.2, 1.0), 0.05)
		flash.tween_property(boss_hp_bar, "modulate", Color.WHITE, 0.15)
		
		# Scale pulse
		var scale_tween := create_tween()
		scale_tween.tween_property(boss_hp_bar, "scale", Vector2(1.05, 1.1), 0.08).set_ease(Tween.EASE_OUT)
		scale_tween.tween_property(boss_hp_bar, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_IN)
		
		# Brief camera shake on name label using position
		var original_pos = boss_name_label.position
		var shake_tween := create_tween()
		shake_tween.tween_property(boss_name_label, "position:x", original_pos.x + 5.0, 0.04)
		shake_tween.tween_property(boss_name_label, "position:x", original_pos.x - 5.0, 0.04)
		shake_tween.tween_property(boss_name_label, "position:x", original_pos.x, 0.04)

	if current <= 0:
		hide_boss()

func _update_hp_label(current: int, maximum: int) -> void:
	if boss_hp_label:
		boss_hp_label.text = "%d / %d" % [current, maximum]
