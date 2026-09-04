extends Node
class_name CursorJuice

# Reusable cursor animation component for game feel
# Adds hover, click, and trail animations to custom cursor system

var target_cursor: Control
var base_scale: float = 1.0

# Hover Animation Settings
@export var hover_scale: float = 1.1
@export var hover_duration: float = 0.2
@export var hover_rotation: float = 5.0  # degrees
@export var hover_brightness: float = 1.2  # multiplier

# Click Animation Settings
@export var click_scale: float = 0.8
@export var click_duration: float = 0.1
@export var click_rotation: float = -10.0  # degrees
@export var click_brightness: float = 1.5  # multiplier

# State Transition Settings
@export var transition_duration: float = 0.3
@export var transition_scale_effect: float = 1.3

# General Settings
@export var enable_rotation: bool = true
@export var enable_brightness: bool = true
@export var use_easing: bool = true
@export var easing_type: Tween.EaseType = Tween.EASE_OUT

# Original values for restoration
var original_rotation: float
var original_modulate: Color
var original_position: Vector2

func _ready() -> void:
	# Auto-setup with parent if it's a Control
	var parent = get_parent()
	if parent is Control:
		setup(parent)

func setup(cursor: Control, scale_factor: float = 1.0) -> void:
	target_cursor = cursor
	base_scale = scale_factor
	
	# Ensure pivot is centered for nice scaling without displacement
	if cursor.pivot_offset == Vector2.ZERO and cursor.size != Vector2.ZERO:
		cursor.pivot_offset = cursor.size / 2.0
		
	original_rotation = cursor.rotation_degrees if cursor.has_method("get_rotation_degrees") else 0.0
	var mod = cursor.modulate
	mod.a = 1.0
	original_modulate = mod
	original_position = cursor.position

func animate_hover(intensity: float = 1.0) -> void:
	if not target_cursor:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(easing_type)
	
	# Scale up (relative to base scale)
	var target_hover_scale: Vector2 = Vector2.ONE * base_scale * (hover_scale * intensity)
	tween.tween_property(target_cursor, "scale", target_hover_scale, hover_duration * intensity)
	
	# Rotation
	if enable_rotation and target_cursor.has_method("set_rotation_degrees"):
		var target_rotation: float = original_rotation + (hover_rotation * intensity)
		tween.tween_property(target_cursor, "rotation_degrees", target_rotation, hover_duration * intensity)
	
	# Brightness
	if enable_brightness:
		var bright_modulate: Color = original_modulate * Color(hover_brightness, hover_brightness, hover_brightness, 1.0)
		tween.tween_property(target_cursor, "modulate", bright_modulate, hover_duration * intensity)

func animate_hover_exit(intensity: float = 1.0) -> void:
	if not target_cursor:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(easing_type)
	
	# Scale back to original
	tween.tween_property(target_cursor, "scale", Vector2.ONE * base_scale, hover_duration * intensity)
	
	# Rotation back
	if enable_rotation and target_cursor.has_method("set_rotation_degrees"):
		tween.tween_property(target_cursor, "rotation_degrees", original_rotation, hover_duration * intensity)
	
	# Brightness back
	if enable_brightness:
		tween.tween_property(target_cursor, "modulate", original_modulate, hover_duration * intensity)

func animate_click(intensity: float = 1.0) -> void:
	if not target_cursor:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(Tween.EASE_IN)
	
	# Scale down sharply
	var target_click_scale: Vector2 = Vector2.ONE * base_scale * (click_scale * intensity)
	tween.tween_property(target_cursor, "scale", target_click_scale, click_duration * intensity)
	
	# Rotation snap
	if enable_rotation and target_cursor.has_method("set_rotation_degrees"):
		var target_rotation: float = original_rotation + (click_rotation * intensity)
		tween.tween_property(target_cursor, "rotation_degrees", target_rotation, click_duration * intensity)
	
	# Brightness flash
	if enable_brightness:
		var bright_modulate: Color = original_modulate * Color(click_brightness, click_brightness, click_brightness, 1.0)
		tween.tween_property(target_cursor, "modulate", bright_modulate, click_duration * intensity)

func animate_click_release(intensity: float = 1.0) -> void:
	if not target_cursor:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(Tween.EASE_OUT)
	
	# Bounce back
	var bounce_scale: Vector2 = Vector2.ONE * base_scale * 1.2
	tween.tween_property(target_cursor, "scale", bounce_scale, click_duration * 0.5 * intensity)
	tween.tween_property(target_cursor, "scale", Vector2.ONE * base_scale, click_duration * 0.5 * intensity).set_delay(click_duration * 0.5 * intensity)
	
	# Rotation back
	if enable_rotation and target_cursor.has_method("set_rotation_degrees"):
		tween.tween_property(target_cursor, "rotation_degrees", original_rotation, click_duration * intensity)
	
	# Brightness back
	if enable_brightness:
		tween.tween_property(target_cursor, "modulate", original_modulate, click_duration * intensity)

func animate_state_transition(from_scale: Vector2, to_scale: Vector2, intensity: float = 1.0) -> void:
	if not target_cursor:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(Tween.EASE_IN_OUT)
	
	# Scale transition with bounce (use to_scale as the target)
	var max_scale: Vector2 = to_scale * transition_scale_effect
	tween.tween_property(target_cursor, "scale", max_scale, transition_duration * 0.3 * intensity)
	tween.tween_property(target_cursor, "scale", to_scale, transition_duration * 0.7 * intensity).set_delay(transition_duration * 0.3 * intensity)
	
	# Rotation snap for visual feedback
	if enable_rotation and target_cursor.has_method("set_rotation_degrees"):
		tween.tween_property(target_cursor, "rotation_degrees", original_rotation + 15.0, transition_duration * 0.2 * intensity)
		tween.tween_property(target_cursor, "rotation_degrees", original_rotation, transition_duration * 0.8 * intensity).set_delay(transition_duration * 0.2 * intensity)
	
	# Brightness flash during transition
	if enable_brightness:
		var flash_modulate: Color = original_modulate * Color(1.5, 1.5, 1.5, 1.0)
		tween.tween_property(target_cursor, "modulate", flash_modulate, transition_duration * 0.3 * intensity)
		tween.tween_property(target_cursor, "modulate", original_modulate, transition_duration * 0.7 * intensity).set_delay(transition_duration * 0.3 * intensity)

func reset_to_original() -> void:
	if not target_cursor:
		return
	
	target_cursor.scale = Vector2.ONE * base_scale
	if target_cursor.has_method("set_rotation_degrees"):
		target_cursor.rotation_degrees = original_rotation
	target_cursor.modulate = original_modulate
	target_cursor.position = original_position
