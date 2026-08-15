## BossBar
## Cinematic top-center boss health bar anchored to the HUD.
## Activated when a battler marked as a boss becomes the active enemy.
extends Control

var boss_battler: Battler = null

@onready var boss_name_label: Label = $BG/VBox/HeaderRow/BossNameLabel
@onready var boss_hp_bar: ProgressBar = $BG/VBox/HPBarContainer/HPBar
@onready var boss_hp_label: Label = $BG/VBox/HPBarContainer/HPLabel
@onready var phase_label: Label = $BG/VBox/HeaderRow/PhaseLabel

func _ready() -> void:
	visible = false

## Show and bind to a boss battler.
func show_boss(battler: Battler) -> void:
	if boss_battler and boss_battler.health_changed.is_connected(_on_boss_health_changed):
		boss_battler.health_changed.disconnect(_on_boss_health_changed)

	boss_battler = battler
	boss_name_label.text = battler.character_name.to_upper()
	boss_hp_bar.max_value = battler.max_health
	boss_hp_bar.value = battler.current_health
	_update_hp_label(battler.current_health, battler.max_health)
	_update_phase(battler.current_health, battler.max_health)

	battler.health_changed.connect(_on_boss_health_changed)

	visible = true
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, 0.5)

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
	# Smooth tween
	var t := create_tween()
	t.tween_property(boss_hp_bar, "value", float(current), 0.3).set_ease(Tween.EASE_OUT)
	_update_hp_label(current, maximum)
	_update_phase(current, maximum)

	# Red flash
	var flash := create_tween()
	flash.tween_property(boss_hp_bar, "modulate", Color(1.6, 0.5, 0.5), 0.08)
	flash.tween_property(boss_hp_bar, "modulate", Color.WHITE, 0.25)

	if current <= 0:
		hide_boss()

func _update_hp_label(current: int, maximum: int) -> void:
	if boss_hp_label:
		boss_hp_label.text = "%d / %d" % [current, maximum]

func _update_phase(current: int, maximum: int) -> void:
	if not phase_label:
		return
	var pct := float(current) / float(maximum) if maximum > 0 else 0.0
	if pct > 0.66:
		phase_label.text = "Phase I"
		phase_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	elif pct > 0.33:
		phase_label.text = "Phase II"
		phase_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	else:
		phase_label.text = "ENRAGED"
		phase_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
