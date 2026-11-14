class_name NumberIndicator3D
extends Node3D

enum NumberType {
	DAMAGE,
	HEAL,
	XP,
	SHIELD
}

var active_numbers: Array = []
var battler_depth: float = 1.0  # Default depth if not set

# Animation settings
@export var rise_speed: float = 3.0
@export var pop_scale: float = 1.5
@export var pop_duration: float = 0.2
@export var random_horizontal_angle: float = 45.0  # Max angle in degrees for random horizontal direction
@export var spin_enabled: bool = true  # Whether to add random spin

# Colors for different types
var type_colors = {
	NumberType.DAMAGE: Color("#FF3333"),
	NumberType.HEAL: Color("#00FF66"),
	NumberType.XP: Color("#FFD700"),
	NumberType.SHIELD: Color("#00AAFF")
}

func set_battler_depth(depth: float) -> void:
	battler_depth = depth

func show_damage(value: int, is_critical: bool = false, is_weakness: bool = false) -> void:
	if value <= 0:
		return
	
	spawn_number_item(NumberType.DAMAGE, value, is_critical, is_weakness)

func show_heal(value: int) -> void:
	if value <= 0:
		return
	
	spawn_number_item(NumberType.HEAL, value, false, false)

func show_xp(value: int) -> void:
	if value <= 0:
		return
	
	spawn_number_item(NumberType.XP, value, false, false)

func show_shield_break() -> void:
	spawn_number_item(NumberType.SHIELD, 0, false, false)

func spawn_number_item(number_type: NumberType, value: int, is_critical: bool, is_weakness: bool) -> void:
	# Build display text based on type (Label3D doesn't support BBCode, use plain text)
	var display_text = ""
	var color = type_colors[number_type]
	
	match number_type:
		NumberType.DAMAGE:
			if is_critical:
				display_text += "CRIT! "
				color = Color("#FFAA00")  # Orange for crit
			if is_weakness:
				display_text += "WEAK! "
				color = Color("#FF00FF")  # Magenta for weakness
			display_text += str(value)
		
		NumberType.HEAL:
			display_text += "+" + str(value)
		
		NumberType.XP:
			display_text += "+" + str(value)
		
		NumberType.SHIELD:
			display_text = "SHIELD"
	
	# Create a Label3D for each number
	var label = Label3D.new()
	label.text = display_text
	var font = load("res://assets/fonts/tinyRPGFontKit01_v1_2/TinyRPG-BadgeFont.ttf")
	if font:
		label.font = font
	label.outline_size = 8
	label.outline_modulate = Color.BLACK
	label.pixel_size = 0.025  # Increased for better visibility
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	
	# Calculate dynamic Z offset based on battler depth (in local space)
	# Small multiplier (10% of depth) for local coordinates
	var z_offset = battler_depth * 0.1
	z_offset = max(z_offset, 0.0)  # Ensure non-negative
	
	# Calculate random horizontal direction (always upward, never downward)
	var random_angle = randf_range(-random_horizontal_angle, random_horizontal_angle)
	var radians = deg_to_rad(random_angle)
	var horizontal_velocity = Vector3(cos(radians), 0, sin(radians)) * rise_speed * 0.3
	
	# Random spin
	var spin_velocity = 0.0
	if spin_enabled and randf() < 0.3:
		spin_velocity = randf_range(-180.0, 180.0)
	
	# Store animation data as metadata for the tween to access
	label.set_meta("horizontal_velocity", horizontal_velocity)
	label.set_meta("spin_velocity", spin_velocity)
	label.set_meta("rise_velocity", Vector3(0, rise_speed, 0))
	
	label.position = Vector3(0, 3.5, z_offset)  # Position above battler with Z offset
	label.scale = Vector3(0.1, 0.1, 0.1)  # Start small for dramatic pop
	
	# Add animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Dramatic pop scale (overshoot then settle)
	tween.tween_property(label, "scale", Vector3(pop_scale, pop_scale, pop_scale), pop_duration * 0.3)
	tween.tween_property(label, "scale", Vector3(0.9, 0.9, 0.9), pop_duration * 0.2)
	tween.tween_property(label, "scale", Vector3.ONE, pop_duration * 0.5)
	
	# Rise animation with horizontal drift
	var final_y = 4.5
	var duration = 1.0
	
	tween.parallel()
	tween.tween_property(label, "position:y", final_y, duration)
	tween.tween_property(label, "modulate:a", 0.0, duration)
	
	# Use a separate tween for custom animation
	var anim_tween = create_tween()
	anim_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	anim_tween.set_ease(Tween.EASE_OUT)
	anim_tween.set_trans(Tween.TRANS_LINEAR)
	
	var start_pos = label.position
	var start_rot = label.rotation_degrees.y
	
	var drift_duration = duration * 0.8
	# Tween horizontal drift
	anim_tween.parallel()
	anim_tween.tween_property(label, "position:x", start_pos.x + horizontal_velocity.x * drift_duration * 0.5, drift_duration)
	anim_tween.tween_property(label, "position:z", start_pos.z + horizontal_velocity.z * drift_duration * 0.5, drift_duration)
	
	# Tween spin if enabled
	if spin_velocity != 0.0:
		anim_tween.tween_property(label, "rotation_degrees:y", start_rot + spin_velocity * drift_duration * 0.5, drift_duration)
	
	tween.chain().tween_callback(func(): label.queue_free())
	
	add_child(label)
