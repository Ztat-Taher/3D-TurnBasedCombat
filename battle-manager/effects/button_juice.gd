extends Node
class_name ButtonJuice

# Reusable button animation component for game feel
# Adds press, release, and hover animations to buttons

var target_button: Control

# Configurable parameters
var press_scale: float = 0.9
var press_duration: float = 0.1
var bounce_scale: float = 1.1
var bounce_duration: float = 0.15
var hover_scale: float = 1.05
var hover_duration: float = 0.2
var rotation_amount: float = 5.0  # degrees
var enable_rotation: bool = true
var enable_brightness: bool = true

# Original values for restoration
var original_scale: Vector2
var original_rotation: float
var original_modulate: Color

func _ready() -> void:
	# Auto-setup with parent if it's a Control
	var parent = get_parent()
	if parent is Control:
		setup(parent)

func setup(button: Control) -> void:
	target_button = button
	
	# Store original values
	original_scale = button.scale
	original_rotation = button.rotation_degrees if button.has_method("get_rotation_degrees") else 0.0
	original_modulate = button.modulate
	
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
	
	# Scale down
	var target_press_scale: Vector2 = original_scale * (press_scale * intensity)
	tween.tween_property(target_button, "scale", target_press_scale, press_duration * intensity)
	
	# Rotation
	if enable_rotation and target_button.has_method("set_rotation_degrees"):
		var target_rotation: float = original_rotation + (rotation_amount * intensity)
		tween.tween_property(target_button, "rotation_degrees", target_rotation, press_duration * intensity)
	
	# Brightness
	if enable_brightness:
		var bright_modulate: Color = original_modulate * Color(1.2, 1.2, 1.2, 1.0)
		tween.tween_property(target_button, "modulate", bright_modulate, press_duration * intensity)

func animate_release(intensity: float = 1.0) -> void:
	if not target_button:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Bounce back
	var target_bounce_scale: Vector2 = original_scale * (bounce_scale * intensity)
	tween.tween_property(target_button, "scale", target_bounce_scale, bounce_duration * 0.5 * intensity)
	tween.tween_property(target_button, "scale", original_scale, bounce_duration * 0.5 * intensity).set_delay(bounce_duration * 0.5 * intensity)
	
	# Rotation back
	if enable_rotation and target_button.has_method("set_rotation_degrees"):
		tween.tween_property(target_button, "rotation_degrees", original_rotation, bounce_duration * intensity)
	
	# Brightness back
	if enable_brightness:
		tween.tween_property(target_button, "modulate", original_modulate, bounce_duration * intensity)

func animate_hover(intensity: float = 1.0) -> void:
	if not target_button:
		return
	
	var tween = create_tween()
	var target_hover_scale: Vector2 = original_scale * (hover_scale * intensity)
	tween.tween_property(target_button, "scale", target_hover_scale, hover_duration * intensity)

func animate_hover_exit(intensity: float = 1.0) -> void:
	if not target_button:
		return
	
	var tween = create_tween()
	tween.tween_property(target_button, "scale", original_scale, hover_duration * intensity)

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

func reset_to_original() -> void:
	if not target_button:
		return
	
	target_button.scale = original_scale
	if target_button.has_method("set_rotation_degrees"):
		target_button.rotation_degrees = original_rotation
	target_button.modulate = original_modulate
