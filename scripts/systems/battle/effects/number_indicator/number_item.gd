class_name NumberItem
extends RichTextLabel

enum NumberType {
	DAMAGE,
	HEAL,
	XP,
	SHIELD
}

@export var number_type: NumberType = NumberType.DAMAGE
@export var value: int = 10
@export var is_critical: bool = false
@export var is_weakness: bool = false

# Animation settings
@export var rise_speed: float = -30.0
@export_range(0.1, 20.0, 0.1) var oscillation_frequency: float = 8.0
@export var oscillation_amplitude: float = 2.0
@export var fade_time: float = 1.2
@export var pop_scale: float = 1.3
@export var pop_duration: float = 0.15

# Colors for different types
var type_colors = {
	NumberType.DAMAGE: Color("#FF3333"),
	NumberType.HEAL: Color("#00FF66"),
	NumberType.XP: Color("#FFD700"),
	NumberType.SHIELD: Color("#00AAFF")
}

# Text overlays
var critical_prefix: String = "CRIT!"
var weakness_prefix: String = "WEAK!"
var xp_prefix: String = "+"
var heal_prefix: String = "+"
var shield_text: String = "SHIELD"

var time_alive: float = 0.0
var started_fade: bool = false
var base_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	print("[NumberItem] _ready called, value: ", value, " type: ", number_type)
	# Don't show 0 damage/XP numbers
	if value <= 0 and number_type != NumberType.SHIELD:
		print("[NumberItem] Value is 0, queue_free")
		queue_free()
		return
	
	setup_appearance()
	print("[NumberItem] Appearance set, position: ", position, " size: ", size)
	play_pop_animation()
	
func setup_appearance() -> void:
	# Configure font
	var font = load("res://assets/fonts/tinyRPGFontKit01_v1_2/TinyRPG-BadgeFont.ttf")
	if font:
		add_theme_font_override("normal_font", font)
		add_theme_font_override("bold_font", font)
		add_theme_font_size_override("normal_font_size", 32)
		add_theme_font_size_override("bold_font_size", 32)
	
	# Add outline for readability
	add_theme_constant_override("outline_size", 4)
	add_theme_color_override("outline_color", Color.BLACK)
	
	# Build text based on type
	var display_text = ""
	var color = type_colors[number_type]
	
	match number_type:
		NumberType.DAMAGE:
			if is_critical:
				display_text += "[color=#FFAA00]%s[/color] " % critical_prefix
			if is_weakness:
				display_text += "[color=#FF00FF]%s[/color] " % weakness_prefix
			display_text += "[b][color=#%s]%d[/color][/b]" % [color.to_html(), value]
		
		NumberType.HEAL:
			display_text += "[b][color=#%s]%s%d[/color][/b]" % [color.to_html(), heal_prefix, value]
		
		NumberType.XP:
			display_text += "[b][color=#%s]%s%d[/color][/b]" % [color.to_html(), xp_prefix, value]
		
		NumberType.SHIELD:
			display_text += "[b][color=#%s]%s[/color][/b]" % [color.to_html(), shield_text]
	
	text = display_text
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func play_pop_animation() -> void:
	base_position = position
	scale = Vector2(0.5, 0.5)
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Pop scale animation
	tween.tween_property(self, "scale", Vector2(pop_scale, pop_scale), pop_duration * 0.5)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), pop_duration * 0.5)
	
	# Initial bounce position
	tween.tween_property(self, "position:y", base_position.y - 20, pop_duration * 0.3)
	tween.tween_property(self, "position:y", base_position.y, pop_duration * 0.7)

func _process(delta: float) -> void:
	time_alive += delta
	
	# Rise animation
	position.y += delta * rise_speed
	
	# Oscillation (horizontal wobble)
	position.x = base_position.x + get_oscillation(time_alive)
	
	# Start fade after short delay
	if not started_fade and time_alive > 0.3:
		started_fade = true
		_fade_out()

func _fade_out() -> void:
	var fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, fade_time)
	await fade_tween.finished
	queue_free()

func get_oscillation(time: float) -> float:
	return sin(time * oscillation_frequency) * oscillation_amplitude

func set_stack_offset(offset: Vector2) -> void:
	base_position += offset
	position = base_position

func get_display_text() -> String:
	var display_text = ""
	
	match number_type:
		NumberType.DAMAGE:
			if is_critical:
				display_text += "%s " % critical_prefix
			if is_weakness:
				display_text += "%s " % weakness_prefix
			display_text += "%d" % value
		
		NumberType.HEAL:
			display_text += "%s%d" % [heal_prefix, value]
		
		NumberType.XP:
			display_text += "%s%d" % [xp_prefix, value]
		
		NumberType.SHIELD:
			display_text += shield_text
	
	return display_text

func get_color() -> Color:
	return type_colors[number_type]
