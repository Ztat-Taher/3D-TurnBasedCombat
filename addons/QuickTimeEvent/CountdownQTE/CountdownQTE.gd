@icon("res://addons/QuickTimeEvent/CountdownQTE/IconCountDown.webp")
extends QTE

## CountdownQTE is a Quick Time Event that requires the player to press an Input before time runs out
class_name CountdownQTE

func _physics_process(delta: float) -> void:
	if started:
		counter_time -= delta * ((100 / max(time_left, 0.001)) * 2)
		counter_time = clamp(counter_time, 0.0, self.max_value)
		self.value = counter_time
		
		var is_pressed = false
		# Check for configured input action
		if selected_input != "" and InputMap.has_action(selected_input) and Input.is_action_just_pressed(selected_input):
			is_pressed = true
		# Check for F key (fallback)
		elif Input.is_key_pressed(KEY_F) or Input.is_physical_key_pressed(KEY_F):
			is_pressed = true
		# Check for confirm actions (keyboard Enter, controller A button)
		elif Input.is_action_just_pressed("Confirm") or Input.is_action_just_pressed("ui_accept"):
			is_pressed = true
		# Check for attack action (controller A button)
		elif Input.is_action_just_pressed("attack"):
			is_pressed = true
			
		if is_pressed:
			succeed()
