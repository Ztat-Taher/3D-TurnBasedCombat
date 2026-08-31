class_name CardUI
extends Control
## UI system for displaying and interacting with cards
## Shows the player's hand, handles card selection and targeting

signal card_selected(card: CardData)
signal end_turn_pressed()

@onready var card_container: HBoxContainer = $CardContainer

var card_battle_manager: CardBattleManager
var card_button_scene: PackedScene
var retry_count: int = 0
const MAX_RETRIES: int = 10

# Controller navigation
var selected_card_index: int = 0
var card_buttons: Array[Control] = []

# Stepped navigation
var last_navigation_time: float = 0.0
var navigation_cooldown: float = 0.25  # Time between navigations in seconds
var navigation_threshold: float = 0.6  # Joystick threshold to trigger navigation
var joystick_active_direction: int = 0  # Track which direction joystick is active in

func _ready():
	if card_container:
		card_container.child_order_changed.connect(func(): call_deferred("apply_card_fanning"))
	
	# Load card button scene
	if ResourceLoader.exists("res://battle-manager/card_combat/card_button.tscn"):
		card_button_scene = preload("res://battle-manager/card_combat/card_button.tscn")
	
	# Defer to ensure scene tree is ready
	call_deferred("_deferred_ready")

func _deferred_ready():
	# Find card battle manager
	card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	if not card_battle_manager:
		retry_count += 1
		if retry_count < MAX_RETRIES:
			# Retry in a moment
			call_deferred("_deferred_ready")
		return
	
	# Connect signals
	card_battle_manager.ap_changed.connect(_on_ap_changed)
	card_battle_manager.card_played.connect(_on_card_played)
	
	# Initial UI update
	update_hand_display()
	update_ap_display()

func _unhandled_input(event: InputEvent) -> void:
	# Early return if not visible - don't consume any input
	if not visible:
		return
	
	if not card_battle_manager or card_battle_manager.is_executing_card:
		return
	
	# Check if we're in targeting mode - if so, don't consume navigation events
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.in_target_selection:
		# Don't consume input events when in targeting mode
		# Let them pass through to BattleManager for target navigation
		return
	
	# Only handle card-specific actions, let everything else pass through
	var handled = false
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Controller card navigation - use stepped navigation for joystick, instant for buttons
	if event.is_action_pressed("ui_left"):
		_navigate_cards(-1)
		handled = true
	elif event.is_action_pressed("ui_right"):
		_navigate_cards(1)
		handled = true
	elif event is InputEventJoypadMotion:
		var axis_value = event.axis_value
		if event.axis == 0:  # Left/right axis
			# Determine direction
			var new_direction = 0
			if axis_value > navigation_threshold:
				new_direction = 1
			elif axis_value < -navigation_threshold:
				new_direction = -1
			
			# If direction changed, reset cooldown and navigate immediately
			if new_direction != 0 and new_direction != joystick_active_direction:
				joystick_active_direction = new_direction
				last_navigation_time = current_time
				_navigate_cards(new_direction)
				handled = true
			# If same direction, check cooldown
			elif new_direction != 0 and current_time - last_navigation_time > navigation_cooldown:
				last_navigation_time = current_time
				_navigate_cards(new_direction)
				handled = true
			# Reset if joystick centered
			elif abs(axis_value) < 0.2:
				joystick_active_direction = 0
	elif event.is_action_pressed("select_card"):
		_select_current_card()
		handled = true
	elif event.is_action_pressed("attack"):
		_select_current_card()
		handled = true
	elif event.is_action_pressed("ui_cancel"):
		# Cancel targeting if in targeting mode
		if battle_manager and battle_manager.has_method("exit_targeting_mode"):
			battle_manager.exit_targeting_mode()
		
		# Clear card selection to prevent re-triggering targeting
		if battle_manager and battle_manager.has_meta("pending_card"):
			battle_manager.set_meta("pending_card", null)
		
		# If not in targeting mode and card UI is visible, trigger global back
		if not (battle_manager and battle_manager.in_target_selection) and visible:
			var battlehud = get_tree().get_first_node_in_group("BattleHud")
			if battlehud and battlehud.has_method("_on_global_back_pressed"):
				battlehud._on_global_back_pressed()
		
		handled = true
	
	# Only consume input if we actually handled it
	if handled:
		get_viewport().set_input_as_handled()

func _navigate_cards(direction: int) -> void:
	if card_buttons.is_empty():
		return
	
	# If no card is currently selected, select the first one in the direction
	if selected_card_index < 0:
		if direction > 0:
			selected_card_index = 0
		else:
			selected_card_index = card_buttons.size() - 1
	else:
		selected_card_index = (selected_card_index + direction) % card_buttons.size()
		if selected_card_index < 0:
			selected_card_index = card_buttons.size() - 1
	
	_update_card_selection()

func _select_current_card() -> void:
	if selected_card_index >= 0 and selected_card_index < card_buttons.size():
		var card_button = card_buttons[selected_card_index]
		if card_button:
			# Emit the card_played signal directly (same as mouse click)
			card_button.card_played.emit(card_button.card_data)

func _update_card_selection() -> void:
	for i in range(card_buttons.size()):
		var card_button = card_buttons[i]
		if card_button:
			if i == selected_card_index and selected_card_index >= 0:
				# Use the same hover system as mouse
				if card_button.has_method("set_controller_hover"):
					card_button.set_controller_hover(true)
			else:
				# Unhover the card
				if card_button.has_method("set_controller_hover"):
					card_button.set_controller_hover(false)

func update_hand_display():
	if not card_battle_manager or not card_container:
		return
	
	# Override container separation for fanned card overlapping
	card_container.add_theme_constant_override("separation", -20)
	
	# Clear existing card buttons
	for child in card_container.get_children():
		child.queue_free()
	
	card_buttons.clear()
	selected_card_index = -1  # Don't auto-select first card
	
	# Get current hand
	var hand = card_battle_manager.get_hand()
	
	# Create card buttons for each card
	for i in range(hand.size()):
		var card = hand[i]
		var card_button = create_card_button(card)
		if card_button:
			card_buttons.append(card_button)
			
			# Visual indication for unplayable cards
			if card_battle_manager:
				var ap_info = card_battle_manager.get_ap_info()
				if ap_info.get("current_ap", 0) < card.cost:
					card_button.modulate = Color(0.4, 0.4, 0.4, 0.8) # Grey out
				else:
					card_button.modulate = Color.WHITE
			
			card_container.add_child(card_button)
			# Set initial scale to 0 for staggered pop-in
			card_button.scale = Vector2.ZERO
			# Stagger pop-in animation
			var tween = create_tween()
			tween.set_ease(Tween.EaseType.EASE_OUT)
			tween.set_trans(Tween.TransitionType.TRANS_BACK)
			tween.tween_property(card_button, "scale", Vector2.ONE, 0.3).set_delay(0.05 * i)
	
	apply_card_fanning()
	_update_card_selection()

func apply_card_fanning() -> void:
	if not card_container:
		return
	
	var valid_children: Array = []
	for child in card_container.get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			valid_children.append(child)
	
	var card_count = valid_children.size()
	if card_count == 0:
		return
	
	var max_angle_step: float = 5.0
	var max_arc_factor: float = 4.0
	var mid_index: float = (card_count - 1) / 2.0
	
	for i in range(card_count):
		var child = valid_children[i]
		var offset_from_center: float = i - mid_index
		
		var rotation_deg: float = offset_from_center * max_angle_step
		var y_offset: float = (offset_from_center * offset_from_center) * max_arc_factor
		var z_idx: int = i
		
		if child.has_method("set_fan_parameters"):
			child.set_fan_parameters(rotation_deg, y_offset, z_idx)

func create_card_button(card: CardData) -> Control:
	if not card_button_scene:
		# Create a simple button if scene not available
		var button = Button.new()
		button.text = card.name + " (Cost: " + str(card.cost) + ")"
		button.pressed.connect(func(): _on_card_button_pressed(card))
		return button
	
	var card_button = card_button_scene.instantiate()
	if card_button.has_method("setup"):
		card_button.setup(card)
		card_button.card_played.connect(func(_card_data): _on_card_button_pressed(card))
	
	return card_button

func update_ap_display():
	pass

func _on_card_button_pressed(card: CardData):
	if card_battle_manager:
		if card_battle_manager.is_executing_card:
			return
		var ap_info = card_battle_manager.get_ap_info()
		if ap_info.get("current_ap", 0) < card.cost:
			return
			
	card_selected.emit(card)

func set_end_turn_button_visible(_p_visible: bool) -> void:
	pass

func _on_end_turn_pressed():
	end_turn_pressed.emit()

func _on_ap_changed(_current_ap: int, _max_ap: int):
	update_ap_display()

func _on_card_played(_card = null, _target = null):
	update_hand_display()

func set_card_targeting_mode(_enabled: bool):
	pass
	# Enable/disable card targeting UI
