extends Node
class_name ButtonJuice

# Reusable button animation component for game feel
# Adds press, release, and hover animations to buttons

var target_button: Control

# Press Animation Settings
@export var press_scale: float = 0.9
@export var press_duration: float = 0.1
@export var press_rotation: float = 5.0  # degrees
@export var press_brightness: float = 1.2  # multiplier
@export var press_slide_offset: Vector2 = Vector2(0, 0)  # slide direction on press
@export var press_slide_enabled: bool = true  # Now safe with container detection

# Release/Bounce Animation Settings
@export var bounce_scale: float = 1.1
@export var bounce_duration: float = 0.15
@export var bounce_rotation: float = -3.0  # degrees (negative for opposite direction)
@export var bounce_slide_offset: Vector2 = Vector2(0, 0)  # slide direction on release
@export var bounce_slide_enabled: bool = true  # Now safe with container detection

# Hover Animation Settings
@export var hover_scale: float = 1.05
@export var hover_duration: float = 0.2
@export var hover_rotation: float = 2.0  # degrees
@export var hover_brightness: float = 1.1  # multiplier
@export var hover_slide_offset: Vector2 = Vector2(-10, 0)  # slide left on hover
@export var hover_slide_enabled: bool = true  # Now safe with container detection

# General Settings
@export var enable_rotation: bool = true
@export var enable_brightness: bool = true
@export var enable_sliding: bool = true
@export var use_easing: bool = true
@export var easing_type: Tween.EaseType = Tween.EASE_OUT

# Original values for restoration
var original_scale: Vector2
var original_rotation: float
var original_modulate: Color
var original_position: Vector2
var is_in_container: bool = false

func _ready() -> void:
	# Auto-setup with parent if it's a Control
	var parent = get_parent()
	if parent is Control:
		setup(parent)

func setup(button: Control) -> void:
	target_button = button
	
	# Check if button is in a container - if so, disable position modifications
	is_in_container = button.get_parent() is Container
	if is_in_container:
		enable_sliding = false  # Force disable sliding for container buttons
	
	# Store original values
	# If button scale was squished or zeroed during pre-appear, fallback to Vector2.ONE
	if button.scale.length_squared() < 0.1:
		original_scale = Vector2.ONE
	else:
		original_scale = button.scale
		
	# Ensure pivot is centered for nice scaling without displacement
	if button.pivot_offset == Vector2.ZERO and button.size != Vector2.ZERO:
		button.pivot_offset = button.size / 2.0
		
	original_rotation = button.rotation_degrees if button.has_method("get_rotation_degrees") else 0.0
	# Ensure original modulate color has alpha 1.0 so hover exit does not restore alpha 0.0
	var mod = button.modulate
	mod.a = 1.0
	original_modulate = mod
	original_position = button.position
	
	# Connect signals
	if button.has_signal("pressed"):
		button.pressed.connect(_on_button_pressed)
	if button.has_signal("button_down"):
		button.button_down.connect(_on_button_down)
	if button.has_signal("button_up"):
		button.button_up.connect(_on_button_up)
	if button.has_signal("mouse_entered"):
		button.mouse_entered.connect(_on_mouse_entered)
	if button.has_signal("mouse_exited"):
		button.mouse_exited.connect(_on_mouse_exited)
	if button.has_signal("focus_entered"):
		button.focus_entered.connect(_on_focus_entered)
	if button.has_signal("focus_exited"):
		button.focus_exited.connect(_on_focus_exited)

func animate_press(intensity: float = 1.0) -> void:
	if not target_button:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(easing_type)
	
	# Scale down
	var target_press_scale: Vector2 = original_scale * (press_scale * intensity)
	tween.tween_property(target_button, "scale", target_press_scale, press_duration * intensity)
	
	# Rotation
	if enable_rotation and target_button.has_method("set_rotation_degrees"):
		var target_rotation: float = original_rotation + (press_rotation * intensity)
		tween.tween_property(target_button, "rotation_degrees", target_rotation, press_duration * intensity)
	
	# Brightness
	if enable_brightness:
		var bright_modulate: Color = original_modulate * Color(press_brightness, press_brightness, press_brightness, 1.0)
		tween.tween_property(target_button, "modulate", bright_modulate, press_duration * intensity)
	
	# Sliding - NEVER modify position for buttons in containers
	if enable_sliding and press_slide_enabled and not is_in_container:
		var target_position: Vector2 = original_position + (press_slide_offset * intensity)
		tween.tween_property(target_button, "position", target_position, press_duration * intensity)

func animate_release(intensity: float = 1.0) -> void:
	if not target_button:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(easing_type)
	
	# Bounce back
	var target_bounce_scale: Vector2 = original_scale * (bounce_scale * intensity)
	tween.tween_property(target_button, "scale", target_bounce_scale, bounce_duration * 0.5 * intensity)
	tween.tween_property(target_button, "scale", original_scale, bounce_duration * 0.5 * intensity).set_delay(bounce_duration * 0.5 * intensity)
	
	# Rotation back with bounce
	if enable_rotation and target_button.has_method("set_rotation_degrees"):
		var bounce_rotation_target: float = original_rotation + (bounce_rotation * intensity)
		tween.tween_property(target_button, "rotation_degrees", bounce_rotation_target, bounce_duration * 0.5 * intensity)
		tween.tween_property(target_button, "rotation_degrees", original_rotation, bounce_duration * 0.5 * intensity).set_delay(bounce_duration * 0.5 * intensity)
	
	# Brightness back
	if enable_brightness:
		tween.tween_property(target_button, "modulate", original_modulate, bounce_duration * intensity)
	
	# Position back with bounce - NEVER modify position for buttons in containers
	if enable_sliding and bounce_slide_enabled and not is_in_container:
		var bounce_position_target: Vector2 = original_position + (bounce_slide_offset * intensity)
		tween.tween_property(target_button, "position", bounce_position_target, bounce_duration * 0.5 * intensity)
		tween.tween_property(target_button, "position", original_position, bounce_duration * 0.5 * intensity).set_delay(bounce_duration * 0.5 * intensity)

func animate_hover(intensity: float = 1.0) -> void:
	if not target_button:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(easing_type)
	
	# Scale up
	var target_hover_scale: Vector2 = original_scale * (hover_scale * intensity)
	tween.tween_property(target_button, "scale", target_hover_scale, hover_duration * intensity)
	
	# Rotation
	if enable_rotation and target_button.has_method("set_rotation_degrees"):
		var target_rotation: float = original_rotation + (hover_rotation * intensity)
		tween.tween_property(target_button, "rotation_degrees", target_rotation, hover_duration * intensity)
	
	# Brightness
	if enable_brightness:
		var bright_modulate: Color = original_modulate * Color(hover_brightness, hover_brightness, hover_brightness, 1.0)
		tween.tween_property(target_button, "modulate", bright_modulate, hover_duration * intensity)
	
	# Sliding - NEVER modify position for buttons in containers
	if enable_sliding and hover_slide_enabled and not is_in_container:
		var target_position: Vector2 = original_position + (hover_slide_offset * intensity)
		tween.tween_property(target_button, "position", target_position, hover_duration * intensity)

func animate_hover_exit(intensity: float = 1.0) -> void:
	if not target_button:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	if use_easing:
		tween.set_ease(easing_type)
	
	# Scale back to original
	tween.tween_property(target_button, "scale", original_scale, hover_duration * intensity)
	
	# Rotation back
	if enable_rotation and target_button.has_method("set_rotation_degrees"):
		tween.tween_property(target_button, "rotation_degrees", original_rotation, hover_duration * intensity)
	
	# Brightness back
	if enable_brightness:
		tween.tween_property(target_button, "modulate", original_modulate, hover_duration * intensity)
	
	# Position back - NEVER modify position for buttons in containers
	if enable_sliding and hover_slide_enabled and not is_in_container:
		tween.tween_property(target_button, "position", original_position, hover_duration * intensity)

# Signal handlers
func _on_button_down() -> void:
	animate_press()

func _on_button_up() -> void:
	animate_release()

func _on_button_pressed() -> void:
	animate_press()
	await get_tree().create_timer(press_duration).timeout
	animate_release()

func _on_mouse_entered() -> void:
	animate_hover()

func _on_mouse_exited() -> void:
	animate_hover_exit()

func _on_focus_entered() -> void:
	animate_hover()

func _on_focus_exited() -> void:
	animate_hover_exit()

# Custom intensity methods for different button types
func animate_light_press() -> void:
	animate_press(0.7)

func animate_light_release() -> void:
	animate_release(0.7)

func animate_heavy_press() -> void:
	animate_press(1.3)

func animate_heavy_release() -> void:
	animate_release(1.3)

# Quick hover animation without delay
func animate_quick_hover() -> void:
	if not target_button:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	
	var target_hover_scale: Vector2 = original_scale * hover_scale
	tween.tween_property(target_button, "scale", target_hover_scale, 0.1)
	
	if enable_brightness:
		var bright_modulate: Color = original_modulate * Color(hover_brightness, hover_brightness, hover_brightness, 1.0)
		tween.tween_property(target_button, "modulate", bright_modulate, 0.1)
	
	# Only slide if enabled and NOT in a container
	if enable_sliding and hover_slide_enabled and not is_in_container:
		var target_position: Vector2 = original_position + hover_slide_offset
		tween.tween_property(target_button, "position", target_position, 0.1)

# Quick hover exit without delay
func animate_quick_hover_exit() -> void:
	if not target_button:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	
	tween.tween_property(target_button, "scale", original_scale, 0.1)
	
	if enable_brightness:
		tween.tween_property(target_button, "modulate", original_modulate, 0.1)
	
	# Only slide back if sliding was enabled and NOT in a container
	if enable_sliding and hover_slide_enabled and not is_in_container:
		tween.tween_property(target_button, "position", original_position, 0.1)

func reset_to_original() -> void:
	if not target_button:
		return
	
	target_button.scale = original_scale
	if target_button.has_method("set_rotation_degrees"):
		target_button.rotation_degrees = original_rotation
	target_button.modulate = original_modulate
	# Only reset position if not in a container
	if not is_in_container:
		target_button.position = original_position
