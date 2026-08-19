class_name ActionButtons
extends BoxContainer

# Animation Settings
@export var roll_in_duration: float = 0.2  # Slower for visibility
@export var roll_out_duration: float = 0.15  # Slower for visibility
@export var roll_delay_between_buttons: float = 0.05  # More stagger for visibility
@export var scale_bounce_amount: float = 1.3  # Bigger bounce for visibility

var tween: Tween
var buttons: Array[Control] = []
var original_button_scales: Dictionary = {}  # Store original scales for each button

# Make tween accessible for parent scripts
func get_tween() -> Tween:
	return tween

func _ready() -> void:
	# Collect all button children and store their original scales
	for child in get_children():
		if child is TextureButton:
			buttons.append(child)
			original_button_scales[child.name] = child.scale  # Store original scale
	
	# Set initial hidden state for animation
	set_buttons_hidden()

func set_buttons_hidden() -> void:
	for button in buttons:
		button.modulate = Color(1, 1, 1, 0)
		# Start at smaller scale for dramatic entrance
		var original_scale = original_button_scales.get(button.name, button.scale)
		button.scale = original_scale * 0.5

func animate_buttons_in() -> void:
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.set_parallel(false)
	
	for i in range(buttons.size()):
		var button = buttons[i]
		var delay = i * roll_delay_between_buttons
		
		# Start from hidden, small state
		button.modulate = Color(1, 1, 1, 0)
		var original_scale = original_button_scales.get(button.name, button.scale)
		button.scale = original_scale * 0.5
		
		# Animate each button fading in with dramatic scale effect
		tween.tween_property(button, "modulate:a", 1.0, roll_in_duration).set_delay(delay)
		
		# Add dramatic scale bounce for visibility
		tween.tween_property(button, "scale", original_scale * scale_bounce_amount, roll_in_duration * 0.4).set_delay(delay)
		tween.tween_property(button, "scale", original_scale, roll_in_duration * 0.6).set_delay(delay + roll_in_duration * 0.4)

func animate_buttons_out() -> void:
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.set_parallel(false)
	
	# Animate buttons out in reverse order
	for i in range(buttons.size() - 1, -1, -1):
		var button = buttons[i]
		var delay = (buttons.size() - 1 - i) * roll_delay_between_buttons
		
		# Animate each button fading out with scale effect
		tween.tween_property(button, "modulate:a", 0.0, roll_out_duration).set_delay(delay)
		
		# Scale down slightly using stored original scale
		var original_scale = original_button_scales.get(button.name, button.scale)
		tween.tween_property(button, "scale", original_scale * 0.85, roll_out_duration).set_delay(delay)

func show_button(button_name: String) -> void:
	var button = get_button_by_name(button_name)
	if button:
		button.visible = true
		# Start from hidden, small state
		button.modulate = Color(1, 1, 1, 0)
		var original_scale = original_button_scales.get(button.name, button.scale)
		button.scale = original_scale * 0.5
		animate_single_button_in(button)

func hide_button(button_name: String) -> void:
	var button = get_button_by_name(button_name)
	if button:
		animate_single_button_out(button)
		await get_tree().create_timer(roll_out_duration).timeout
		button.visible = false
		# Reset to original scale after hiding
		button.scale = original_button_scales.get(button.name, button.scale)

func set_button_visible(button_name: String, visible: bool) -> void:
	if visible:
		show_button(button_name)
	else:
		hide_button(button_name)

func animate_single_button_in(button: Control) -> void:
	var single_tween = create_tween()
	single_tween.set_parallel(true)
	
	button.modulate = Color(1, 1, 1, 0)
	var original_scale = original_button_scales.get(button.name, button.scale)
	if original_scale == null:
		original_scale = button.scale
		original_button_scales[button.name] = original_scale  # Store it for future
	button.scale = original_scale * 0.5
	
	single_tween.tween_property(button, "modulate:a", 1.0, roll_in_duration)
	single_tween.tween_property(button, "scale", original_scale * scale_bounce_amount, roll_in_duration * 0.4)
	single_tween.tween_property(button, "scale", original_scale, roll_in_duration * 0.6).set_delay(roll_in_duration * 0.4)

func animate_single_button_out(button: Control) -> void:
	var single_tween = create_tween()
	single_tween.set_parallel(true)
	
	single_tween.tween_property(button, "modulate:a", 0.0, roll_out_duration)
	
	var original_scale = original_button_scales.get(button.name, button.scale)
	single_tween.tween_property(button, "scale", original_scale * 0.85, roll_out_duration)

func get_button_by_name(button_name: String) -> Control:
	for button in buttons:
		if button.name == button_name:
			return button
	return null

func is_button_visible(button_name: String) -> bool:
	var button = get_button_by_name(button_name)
	if button:
		return button.visible
	return false

func refresh_buttons() -> void:
	# Animate out all buttons, then animate back in
	animate_buttons_out()
	await tween.finished
	set_buttons_hidden()
	animate_buttons_in()
