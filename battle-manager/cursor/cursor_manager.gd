extends Node
class_name CursorManager

# Central controller for cursor state management and global coordination
# Manages cursor state transitions and integration with game systems

signal cursor_state_changed(new_state: String)
signal cursor_hover_target(target: Node)
signal cursor_clicked(position: Vector2)

# Use CursorDisplay's enum for consistency
# CursorState is defined in CursorDisplay and used here

# Current cursor state (using CursorDisplay.CursorState)
var current_state: int = CursorDisplay.CursorState.DEFAULT

# Previous cursor state (for restoring after special states)
var previous_state: int = CursorDisplay.CursorState.DEFAULT

# Reference to cursor display
var cursor_display: CursorDisplay

# Reference to effect manager for coordinated effects
var effect_manager: EffectManager

# Auto-detection settings
var auto_detect_hover: bool = false  # Disabled due to viewport method issues
var auto_detect_targeting: bool = true

# State transition cooldown (prevent rapid state switching)
var state_transition_cooldown: float = 0.1
var last_state_change_time: float = 0.0

# Cache of interactable nodes
var interactable_nodes: Array[Node] = []

# Cache of enemy battlers
var enemy_battlers: Array[Node] = []

# Button hover state tracking
var hovered_button: Control = null
var button_exit_timer: Timer = null

func _ready() -> void:
	# Find or create cursor display
	_setup_cursor_display()
	
	# Get reference to effect manager
	effect_manager = get_tree().get_first_node_in_group("effect_manager")
	
	# Connect to signal bus
	_connect_to_signal_bus()
	
	# Initialize in default state
	set_cursor_state(CursorDisplay.CursorState.DEFAULT)
	
	# Set up process for auto-detection
	set_process(true)
	
	# Connect to all buttons for hover detection
	_connect_to_buttons()
	
	# Create timer for button exit delay
	button_exit_timer = Timer.new()
	button_exit_timer.wait_time = 0.05  # 50ms delay
	button_exit_timer.one_shot = true
	add_child(button_exit_timer)
	button_exit_timer.timeout.connect(_on_button_exit_timeout)

func _setup_cursor_display() -> void:
	# Try to find existing cursor display in the scene first
	cursor_display = get_tree().get_first_node_in_group("cursor_display")
	
	if cursor_display:
		# Found existing, use it
		pass
	else:
		# Only create cursor display if not found in scene
		cursor_display = CursorDisplay.new()
		cursor_display.name = "CursorDisplay"
		add_child(cursor_display)
		cursor_display.add_to_group("cursor_display")
	
	# Connect to cursor display signals
	if cursor_display.has_signal("cursor_clicked"):
		cursor_display.cursor_clicked.connect(_on_cursor_clicked)
	if cursor_display.has_signal("cursor_hover_entered"):
		cursor_display.cursor_hover_entered.connect(_on_cursor_hover_entered)
	if cursor_display.has_signal("cursor_hover_exited"):
		cursor_display.cursor_hover_exited.connect(_on_cursor_hover_exited)

func _connect_to_signal_bus() -> void:
	# Connect to SignalBus autoload
	if not SignalBus:
		return
	
	# Connect to battle signals if they exist
	if SignalBus.has_signal("allow_select_target"):
		SignalBus.allow_select_target.connect(_on_allow_select_target)
	if SignalBus.has_signal("select_target"):
		SignalBus.select_target.connect(_on_select_target)
	if SignalBus.has_signal("hover_target"):
		SignalBus.hover_target.connect(_on_hover_target)
	
	# Forward cursor signals to signal bus for global access
	cursor_state_changed.connect(func(state): SignalBus.cursor_state_changed.emit(state))
	cursor_hover_target.connect(func(target): SignalBus.cursor_hover_target.emit(target))
	cursor_clicked.connect(func(pos): SignalBus.cursor_clicked.emit(pos))

func _process(_delta: float) -> void:
	# Auto-detection of cursor states based on game context
	if auto_detect_hover:
		_detect_interactable_hover()
	
	if auto_detect_targeting:
		_detect_targeting_mode()

func set_cursor_state(new_state: int) -> void:
	# Check cooldown to prevent rapid state switching
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_state_change_time < state_transition_cooldown:
		return
	
	if current_state == new_state:
		return
	
	# Save previous state if entering a special state
	if new_state == CursorDisplay.CursorState.TARGETING or new_state == CursorDisplay.CursorState.ATTACK:
		previous_state = current_state
	
	# Don't allow DEFAULT to override INTERACT when hovering a button, unless forced
	if hovered_button and new_state == CursorDisplay.CursorState.DEFAULT:
		return
	
	current_state = new_state
	last_state_change_time = current_time
	
	# Update cursor display
	if cursor_display:
		cursor_display.set_cursor_state(new_state)
	
	# Emit signal
	var state_name = _get_state_name(new_state)
	cursor_state_changed.emit(state_name)
	
	# Optional: Coordinate with effect manager
	_coordinate_with_effects(new_state)

func get_cursor_state() -> int:
	return current_state

func get_cursor_state_name() -> String:
	return _get_state_name(current_state)

func _get_state_name(state: int) -> String:
	match state:
		CursorDisplay.CursorState.DEFAULT:
			return "default"
		CursorDisplay.CursorState.ATTACK:
			return "attack"
		CursorDisplay.CursorState.INTERACT:
			return "interact"
		CursorDisplay.CursorState.TARGETING:
			return "targeting"
		CursorDisplay.CursorState.PRESS:
			return "press"
		_:
			return "unknown"

func restore_previous_state() -> void:
	# Don't restore if still hovering an interactive element
	if hovered_button:
		return
	set_cursor_state(previous_state)

func _connect_to_buttons() -> void:
	# Wait for scene to be ready before connecting to buttons
	await get_tree().process_frame
	
	var buttons = []
	
	# Recursively find all buttons starting from the root
	var root = get_tree().root
	_find_buttons_recursive(root, buttons)
	
	# Connect to button signals
	for button in buttons:
		if button.has_signal("mouse_entered"):
			if not button.mouse_entered.is_connected(_on_button_mouse_entered):
				button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
		if button.has_signal("mouse_exited"):
			if not button.mouse_exited.is_connected(_on_button_mouse_exited):
				button.mouse_exited.connect(_on_button_mouse_exited.bind(button))
	
	print("CursorManager: Connected to ", buttons.size(), " buttons for hover detection")

func _find_buttons_recursive(node: Node, buttons: Array) -> void:
	# Check if this node is a button
	if node is Button or node is TextureButton:
		if not buttons.has(node):
			buttons.append(node)
	
	# Recursively check children
	for child in node.get_children():
		_find_buttons_recursive(child, buttons)

func _on_button_mouse_entered(button: Control) -> void:
	hovered_button = button
	# Cancel any pending exit timer
	if button_exit_timer:
		button_exit_timer.stop()
	# Button hover takes priority over enemy targeting
	if current_state != CursorDisplay.CursorState.TARGETING:
		set_cursor_state(CursorDisplay.CursorState.INTERACT)

func _on_button_mouse_exited(button: Control) -> void:
	if hovered_button == button:
		hovered_button = null
	# Start timer to allow for quick transitions between buttons
	if button_exit_timer:
		button_exit_timer.start()

func notify_hover_entered(element: Control) -> void:
	_on_button_mouse_entered(element)

func notify_hover_exited(element: Control) -> void:
	_on_button_mouse_exited(element)

func _on_button_exit_timeout() -> void:
	# Only revert if we're not on a button and in INTERACT or PRESS state
	if not hovered_button and (current_state == CursorDisplay.CursorState.INTERACT or current_state == CursorDisplay.CursorState.PRESS):
		restore_previous_state()

func _coordinate_with_effects(new_state: int) -> void:
	if not effect_manager:
		return
	
	# Coordinate cursor effects with combat effects
	match new_state:
		CursorDisplay.CursorState.ATTACK:
			# Could trigger subtle effect when entering attack mode
			pass
		CursorDisplay.CursorState.TARGETING:
			# Could trigger targeting-specific effects
			pass
		CursorDisplay.CursorState.INTERACT:
			# UI interaction feedback
			pass
		CursorDisplay.CursorState.DEFAULT:
			# Return to normal
			pass

# Auto-detection methods

func _detect_interactable_hover() -> void:
	# Disabled automatic hover detection to avoid viewport method issues
	# Cursor state changes are now handled primarily through:
	# - Signal-based events from cursor_display
	# - Manual control via battle systems
	# - Targeting mode detection
	return

func _detect_targeting_mode() -> void:
	# Check if we're in a targeting mode (card targeting, ability targeting, etc.)
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	
	var in_targeting_mode = false
	
	if battle_manager and battle_manager.has_method("get") and battle_manager.get("in_target_selection"):
		in_targeting_mode = battle_manager.in_target_selection
	
	if card_battle_manager and card_battle_manager.has_method("get") and card_battle_manager.get("is_targeting"):
		in_targeting_mode = card_battle_manager.is_targeting
	
	if in_targeting_mode and current_state != CursorDisplay.CursorState.TARGETING:
		set_cursor_state(CursorDisplay.CursorState.TARGETING)
	elif not in_targeting_mode and current_state == CursorDisplay.CursorState.TARGETING:
		restore_previous_state()

func _get_node_under_mouse(mouse_pos: Vector2) -> Node:
	# Get the node under the mouse cursor using simplified approach
	# This is a basic implementation - for more robust detection, you might need
	# to use raycasting or physics queries depending on your game setup
	return null

func _is_interactable(node: Node) -> bool:
	if not node:
		return false
	
	# Check if node is a button or other interactable control
	if node is Button or node is TextureButton:
		return true
	
	# Check for custom interactable group
	if node.is_in_group("interactable"):
		return true
	
	# Check for specific game objects
	if node.is_in_group("players") or node.is_in_group("enemies"):
		return true
	
	return false

# Signal handlers

func _on_cursor_clicked(position: Vector2) -> void:
	cursor_clicked.emit(position)
	
	# Could trigger click effects via effect manager
	if effect_manager:
		# Subtle click feedback
		pass

func _on_cursor_hover_entered(target: Node) -> void:
	cursor_hover_target.emit(target)
	
	# Update hover state based on target type
	# Note: Button hover is handled via direct button signals
	if target and target.is_in_group("enemies"):
		if current_state != CursorDisplay.CursorState.ATTACK and current_state != CursorDisplay.CursorState.TARGETING:
			set_cursor_state(CursorDisplay.CursorState.ATTACK)

func _on_cursor_hover_exited(target: Node) -> void:
	# Restore appropriate state when hovering stops
	# Note: Button hover is handled via direct button signals
	if target and target.is_in_group("enemies"):
		if current_state == CursorDisplay.CursorState.ATTACK:
			if previous_state == CursorDisplay.CursorState.DEFAULT:
				set_cursor_state(CursorDisplay.CursorState.DEFAULT)
			else:
				restore_previous_state()

func _on_allow_select_target(can_target: bool) -> void:
	if can_target:
		set_cursor_state(CursorDisplay.CursorState.TARGETING)
	else:
		restore_previous_state()

func _on_select_target(battler: Battler) -> void:
	# Handle target selection
	if battler and battler.is_in_group("enemies"):
		set_cursor_state(CursorDisplay.CursorState.ATTACK)

func _on_hover_target(battler: Battler) -> void:
	# Handle hover over target
	if battler and battler.is_in_group("enemies"):
		if current_state != CursorDisplay.CursorState.ATTACK and current_state != CursorDisplay.CursorState.TARGETING:
			set_cursor_state(CursorDisplay.CursorState.ATTACK)

# Public methods for game systems to control cursor

func force_cursor_state(state: int) -> void:
	# Force a specific cursor state (bypasses auto-detection and hover guard)
	if state == CursorDisplay.CursorState.DEFAULT:
		hovered_button = null
	current_state = state
	last_state_change_time = Time.get_ticks_msec() / 1000.0
	if cursor_display:
		cursor_display.set_cursor_state(state)
	cursor_state_changed.emit(_get_state_name(state))

func enable_auto_detection(enabled: bool) -> void:
	auto_detect_hover = enabled
	auto_detect_targeting = enabled

func register_interactable(node: Node) -> void:
	if not interactable_nodes.has(node):
		interactable_nodes.append(node)

func unregister_interactable(node: Node) -> void:
	interactable_nodes.erase(node)

func register_enemy_battler(node: Node) -> void:
	if not enemy_battlers.has(node):
		enemy_battlers.append(node)

func unregister_enemy_battler(node: Node) -> void:
	enemy_battlers.erase(node)

func set_custom_cursor_texture(state: int, texture: Texture2D) -> void:
	if cursor_display:
		cursor_display.set_custom_texture(state, texture)

func set_state_color(state: int, color: Color) -> void:
	if cursor_display:
		cursor_display.set_state_color(state, color)
