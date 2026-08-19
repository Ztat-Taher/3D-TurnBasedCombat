class_name QTEOverlay
extends Control

signal qte_completed(success: bool)

var title_label: Label
var key_label: Label
var countdown_ring: ColorRect
var qte_timer: Timer
var input_key: String = ""
var time_limit: float = 0.0

func _ready() -> void:
	title_label = $CenterContainer/QTEContainer/TitleLabel
	key_label = $CenterContainer/QTEContainer/RingContainer/KeyLabel
	countdown_ring = $CenterContainer/QTEContainer/RingContainer/CountdownRing
	
	# Make sure the ColorRect is transparent so the shader shows through
	if countdown_ring:
		countdown_ring.color = Color(0, 0, 0, 0)
	
	# Create and setup the timer
	qte_timer = Timer.new()
	qte_timer.one_shot = true
	add_child(qte_timer)
	qte_timer.timeout.connect(_on_timer_timeout)

func setup(input_key: String, time_limit: float) -> void:
	if not title_label:
		await ready
	
	self.input_key = input_key
	self.time_limit = time_limit
	
	# Set the UI text
	title_label.text = "ATTACK QTE!"
	key_label.text = input_key.to_upper()
	
	# Reset countdown to full circle immediately
	if countdown_ring and countdown_ring.material is ShaderMaterial:
		countdown_ring.material.set_shader_parameter("ring_countdown", 1.0)
	
	# Start the timer
	qte_timer.wait_time = time_limit
	qte_timer.start()
	
	# Connect to input for this key
	_connect_input()

func _process(_delta: float) -> void:
	# Update the radial countdown based on our own timer
	if qte_timer and qte_timer.time_left > 0 and time_limit > 0:
		var progress = qte_timer.time_left / time_limit
		var clamped_progress = clamp(progress, 0.0, 1.0)
		if countdown_ring and countdown_ring.material is ShaderMaterial:
			countdown_ring.material.set_shader_parameter("ring_countdown", clamped_progress)

func _connect_input() -> void:
	# Connect to the appropriate input action
	if input_key.is_empty():
		return
	
	var action_name = "qte_" + input_key.to_lower()
	if not InputMap.has_action(action_name):
		# Create the action if it doesn't exist
		InputMap.add_action(action_name)
		var event = InputEventKey.new()
		match input_key.to_upper():
			"F":
				event.keycode = KEY_F
			"Q":
				event.keycode = KEY_Q
			"E":
				event.keycode = KEY_E
			"SPACE":
				event.keycode = KEY_SPACE
			_:
				# Try to parse as keycode
				event.keycode = OS.find_keycode_from_string(input_key)
		InputMap.action_add_event(action_name, event)
	
	# Connect to the input signal (this will be handled by the parent or we can check in _input)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if not qte_timer or not qte_timer.is_inside_tree():
		return
	
	if event.is_pressed() and not event.is_echo():
		var action_name = "qte_" + input_key.to_lower()
		if InputMap.has_action(action_name) and event.is_action(action_name):
			# QTE succeeded!
			_complete_qte(true)

func _on_timer_timeout() -> void:
	# QTE failed - time ran out
	_complete_qte(false)

func _complete_qte(success: bool) -> void:
	# Stop the timer and input processing
	if qte_timer:
		qte_timer.stop()
	set_process_input(false)
	set_process(false)
	
	# Emit completion signal
	qte_completed.emit(success)
	
	# Queue free after a short delay for visual feedback
	await get_tree().create_timer(0.1).timeout
	queue_free()
