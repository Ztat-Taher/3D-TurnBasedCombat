class_name CardUI
extends Control
## UI system for displaying and interacting with cards
## Shows the player's hand, handles card selection and targeting
## Includes Draw Pile (left) and Discard Pile (bottom-right) with animations

signal card_selected(card: CardData)
signal end_turn_pressed()

## Extra margin around the CardContainer that still counts as "in hand" for
## drag-release purposes (the play zone starts outside these bounds).
const HAND_ZONE_MARGIN_LEFT: float = 80.0
const HAND_ZONE_MARGIN_RIGHT: float = 80.0
const HAND_ZONE_MARGIN_TOP: float = 60.0
const HAND_ZONE_MARGIN_BOTTOM: float = 0.0

## Animation durations
const DRAW_ANIM_DURATION: float = 0.35
const DRAW_ANIM_STAGGER: float = 0.08
const DISCARD_ANIM_DURATION: float = 0.30
const DISCARD_STAGGER: float = 0.06

@onready var card_container: HBoxContainer = $CardContainer
@onready var draw_pile: Control = $DrawPile
@onready var draw_pile_count: Label = $DrawPile/DrawPileCountBadge/DrawPileCount
@onready var discard_anchor: Control = $DiscardAnchor

# Card currently under the mouse (drives the same hover visuals as the
# controller navigation). Hover detection follows each card's *highlighted*
# visual form, not its resting fan slot.
var mouse_hovered_card: CardButton = null

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

# Pile animation state
var _is_discarding_hand: bool = false
# The card button currently being played — saved so we can animate it to the discard pile
var _pending_discard_button: CardButton = null
# True when cards are laid out but waiting for the UI to become visible before animating
var _draw_anim_pending: bool = false
# Track the previous hand size to detect newly added cards
var _previous_hand_size: int = 0
# Track the starting index for new card animations
var _new_card_start_index: int = 0

func _ready():
	if card_container:
		card_container.child_order_changed.connect(func(): call_deferred("apply_card_fanning"))
	
	# Load card button scene
	if ResourceLoader.exists("res://scenes/battle/card_combat/card_components/buttons/card_button.tscn"):
		card_button_scene = preload("res://scenes/battle/card_combat/card_components/buttons/card_button.tscn")
	
	# Connect draw pile button press handler
	if draw_pile and draw_pile.has_signal("pressed"):
		draw_pile.pressed.connect(_on_draw_pile_pressed)
	
	# Start the draw pile idle bob animation
	_start_draw_pile_idle_anim()
	
	# Defer to ensure scene tree is ready
	call_deferred("_deferred_ready")

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		# CardUI just became visible (e.g. Attack button pressed in BattleHUD).
		# If a draw animation was queued while we were hidden, play it now.
		if _draw_anim_pending:
			_draw_anim_pending = false
			call_deferred("_start_draw_animations")

func _deferred_ready():
	# Find card battle manager
	card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	if not card_battle_manager:
		retry_count += 1
		if retry_count < MAX_RETRIES:
			call_deferred("_deferred_ready")
		return
	
	# Connect signals
	card_battle_manager.ap_changed.connect(_on_ap_changed)
	card_battle_manager.card_played.connect(_on_card_played)
	
	# Reset hand size tracking for initial load
	_previous_hand_size = 0
	
	# Initial UI update
	update_hand_display()
	update_ap_display()
	update_pile_counts()

func _process(_delta: float) -> void:
	if not visible:
		_set_mouse_hovered_card(null)
		return
	if not card_battle_manager or card_battle_manager.is_executing_card:
		return
	if _is_any_card_dragging():
		return
	_update_mouse_hover()

func _is_any_card_dragging() -> bool:
	for card_button in card_buttons:
		if is_instance_valid(card_button) and card_button.is_dragging:
			return true
	return false

func _update_mouse_hover() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	
	var current: CardButton = mouse_hovered_card
	if is_instance_valid(current) and not current.is_returning \
			and current.is_point_over_visual(mouse_pos):
		return
	
	var candidate: CardButton = null
	for i in range(card_buttons.size() - 1, -1, -1):
		var card_button = card_buttons[i]
		if not is_instance_valid(card_button) or card_button.is_dragging \
				or card_button.is_returning:
			continue
		if card_button.is_point_over_visual(mouse_pos):
			candidate = card_button
			break
	
	_set_mouse_hovered_card(candidate)

func _set_mouse_hovered_card(card_button: CardButton) -> void:
	if mouse_hovered_card == card_button:
		return
	if is_instance_valid(mouse_hovered_card) and mouse_hovered_card.is_hovered:
		mouse_hovered_card.set_controller_hover(false)
	mouse_hovered_card = card_button
	if card_button:
		card_button.set_controller_hover(true)

func get_hand_zone_rect() -> Rect2:
	if not card_container:
		return Rect2()
	return card_container.get_global_rect().grow_individual(
		HAND_ZONE_MARGIN_LEFT, HAND_ZONE_MARGIN_TOP,
		HAND_ZONE_MARGIN_RIGHT, HAND_ZONE_MARGIN_BOTTOM)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	
	if not card_battle_manager or card_battle_manager.is_executing_card:
		return
	
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.in_target_selection:
		return
	
	var handled = false
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if event.is_action_pressed("ui_left"):
		_navigate_cards(-1)
		handled = true
	elif event.is_action_pressed("ui_right"):
		_navigate_cards(1)
		handled = true
	elif event is InputEventJoypadMotion:
		var axis_value = event.axis_value
		if event.axis == 0:
			var new_direction = 0
			if axis_value > navigation_threshold:
				new_direction = 1
			elif axis_value < -navigation_threshold:
				new_direction = -1
			
			if new_direction != 0 and new_direction != joystick_active_direction:
				joystick_active_direction = new_direction
				last_navigation_time = current_time
				_navigate_cards(new_direction)
				handled = true
			elif new_direction != 0 and current_time - last_navigation_time > navigation_cooldown:
				last_navigation_time = current_time
				_navigate_cards(new_direction)
				handled = true
			elif abs(axis_value) < 0.2:
				joystick_active_direction = 0
	elif event.is_action_pressed("select_card"):
		_select_current_card()
		handled = true
	elif event.is_action_pressed("attack"):
		_select_current_card()
		handled = true
	elif event.is_action_pressed("ui_cancel"):
		if battle_manager and battle_manager.has_method("exit_targeting_mode"):
			battle_manager.exit_targeting_mode()
		
		if battle_manager and battle_manager.has_meta("pending_card"):
			battle_manager.set_meta("pending_card", null)
		
		# Return the pending card to hand if targeting was cancelled
		if is_instance_valid(_pending_discard_button):
			return_card_to_hand(_pending_discard_button)
			_pending_discard_button = null
		
		if not (battle_manager and battle_manager.in_target_selection) and visible:
			var battlehud = get_tree().get_first_node_in_group("BattleHud")
			if battlehud and battlehud.has_method("_on_global_back_pressed"):
				battlehud._on_global_back_pressed()
		
		handled = true
	
	if handled:
		get_viewport().set_input_as_handled()

func _navigate_cards(direction: int) -> void:
	if card_buttons.is_empty():
		return
	
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
			card_button.card_played.emit(card_button.card_data)

func _update_card_selection() -> void:
	for i in range(card_buttons.size()):
		var card_button = card_buttons[i]
		if card_button:
			if i == selected_card_index and selected_card_index >= 0:
				if card_button.has_method("set_controller_hover"):
					card_button.set_controller_hover(true)
			else:
				if card_button != mouse_hovered_card \
						and card_button.has_method("set_controller_hover"):
					card_button.set_controller_hover(false)

# ─────────────────────────────────────────────────────────────────────────────
# PILE MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

## Update the draw pile count label and pulse the badge.
func update_pile_counts() -> void:
	if not card_battle_manager or not draw_pile_count:
		return
	var deck = card_battle_manager._get_current_deck()
	if not deck:
		draw_pile_count.text = "0"
		return
	var draw_count: int = 0
	if "_draw_pile" in deck:
		draw_count = deck._draw_pile.size()
	elif "draw_pile" in deck:
		draw_count = deck.draw_pile.size()
	draw_pile_count.text = str(draw_count)
	_pulse_draw_pile_badge()

## Gentle continuous bob on the draw pile stack.
func _start_draw_pile_idle_anim() -> void:
	if not draw_pile:
		return
	var tween := create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(draw_pile, "position:y", draw_pile.position.y - 4.0, 1.2)
	tween.tween_property(draw_pile, "position:y", draw_pile.position.y, 1.2)

## Brief scale-pulse on the draw count badge to draw attention to count changes.
func _pulse_draw_pile_badge() -> void:
	var badge = draw_pile.get_node_or_null("DrawPileCountBadge") if draw_pile else null
	if not badge:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(badge, "scale", Vector2(1.25, 1.25), 0.12)
	tween.tween_property(badge, "scale", Vector2.ONE, 0.15)

func _on_draw_pile_pressed() -> void:
	if not card_battle_manager or card_battle_manager.is_executing_card:
		return
	
	# Check if player has enough AP
	var draw_cost = 1
	if card_battle_manager.card_battle_config:
		draw_cost = card_battle_manager.card_battle_config.draw_card_ap_cost
	
	var ap_info = card_battle_manager.get_ap_info()
	if ap_info.get("current_ap", 0) < draw_cost:
		return
	
	# Check if hand is not full (max_hand_size check)
	var deck = card_battle_manager._get_current_deck()
	if not deck:
		return
	
	var hand = deck.get_hand()
	var max_hand_size = card_battle_manager.card_battle_config.max_hand_size if card_battle_manager.card_battle_config else 5
	if hand.size() >= max_hand_size:
		return
	
	# Spend AP
	if card_battle_manager.current_player_battler:
		card_battle_manager.current_player_battler.spend_ap(draw_cost)
		if card_battle_manager.ap_system:
			card_battle_manager.ap_system.current_ap = card_battle_manager.current_player_battler.current_ap
			card_battle_manager.ap_system.max_ap = card_battle_manager.current_player_battler.max_ap
		card_battle_manager.ap_changed.emit(card_battle_manager.current_player_battler.current_ap, card_battle_manager.current_player_battler.max_ap)
	elif card_battle_manager.ap_system:
		card_battle_manager.ap_system.spend_ap(draw_cost)
	
	# Draw a card from the deck
	var drawn_card = card_battle_manager.draw_card_for_deck(deck)
	if drawn_card:
		# Update the hand display to show the new card
		update_hand_display()
		update_pile_counts()

# ─────────────────────────────────────────────────────────────────────────────
# DRAW ANIMATION  (pile → hand fan position)
# ─────────────────────────────────────────────────────────────────────────────

## Called deferred (or from _notification) after update_hand_display().
## We MUST await one process frame before reading global_position: call_deferred
## fires during the idle phase of the same frame that added children, before
## the HBoxContainer's SORT_CHILDREN pass runs. Without the await every card
## reports global_position == (0,0) and the pile offset is wrong.
func _start_draw_animations() -> void:
	# Let the HBoxContainer finish its layout pass so global positions are valid.
	await get_tree().process_frame
	
	if not draw_pile or not is_inside_tree():
		return
	
	var pile_center := draw_pile.global_position + draw_pile.size * 0.5
	
	# Animate cards starting from _new_card_start_index
	for i in range(_new_card_start_index, card_buttons.size()):
		var cb = card_buttons[i]
		if not is_instance_valid(cb):
			continue
		
		# ── non-CardButton fallback ──
		if not cb is CardButton:
			cb.scale = Vector2.ZERO
			cb.modulate.a = 1.0
			var tw := create_tween()
			tw.set_ease(Tween.EASE_OUT)
			tw.set_trans(Tween.TRANS_BACK)
			tw.tween_property(cb, "scale", Vector2.ONE, DRAW_ANIM_DURATION).set_delay(DRAW_ANIM_STAGGER * (i - _new_card_start_index))
			continue
		
		var card_btn := cb as CardButton
		
		# ── no SubViewportContainer fallback ──
		if not card_btn.card_3d_container:
			card_btn.modulate.a = 1.0
			var tw := create_tween()
			tw.set_ease(Tween.EASE_OUT)
			tw.set_trans(Tween.TRANS_BACK)
			tw.tween_property(card_btn, "modulate:a", 1.0, DRAW_ANIM_DURATION * 0.5).set_delay(DRAW_ANIM_STAGGER * (i - _new_card_start_index))
			continue
		
		# ── main path: slide from pile into fan slot ──
		# card_btn sits in CardContainer at its final fan position.
		# pile_offset (screen-space delta, valid in card_btn local space since
		# CardUI and CardContainer have no rotation/scale) moves card_3d_container
		# so it visually appears at the draw pile. The tween then brings it back
		# to the resting fan position (0, base_y_offset).
		var card_center := card_btn.global_position + card_btn.size * 0.5
		var pile_offset: Vector2 = pile_center - card_center
		
		# Position visual at pile; keep card invisible until its tween fires
		# (prevents staggered cards from flashing at pile position during delay).
		card_btn.card_3d_container.position = pile_offset + Vector2(0.0, card_btn.base_y_offset)
		card_btn.card_3d_container.scale    = Vector2(0.5, 0.5)
		card_btn.card_3d_container.rotation_degrees = card_btn.base_rotation - 15.0
		card_btn.modulate.a = 0.0
		# Block _process from snapping back while the tween owns the transform.
		card_btn.is_draw_animating = true
		
		var delay: float = DRAW_ANIM_STAGGER * (i - _new_card_start_index)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		# Fade in quickly the moment the tween starts (after per-card delay)
		tween.tween_property(card_btn, "modulate:a", 1.0, 0.08).set_delay(delay)
		tween.tween_property(card_btn.card_3d_container, "position",
			Vector2(0.0, card_btn.base_y_offset), DRAW_ANIM_DURATION).set_delay(delay)
		tween.tween_property(card_btn.card_3d_container, "scale",
			Vector2.ONE, DRAW_ANIM_DURATION).set_delay(delay)
		tween.tween_property(card_btn.card_3d_container, "rotation_degrees",
			card_btn.base_rotation, DRAW_ANIM_DURATION * 0.8).set_delay(delay)
		# Release the guard so hover/idle can resume after the animation.
		tween.chain().tween_callback(func():
			if is_instance_valid(card_btn):
				card_btn.is_draw_animating = false
		)

# ─────────────────────────────────────────────────────────────────────────────
# DISCARD ANIMATION  (current position → discard pile / bottom-right)
# ─────────────────────────────────────────────────────────────────────────────

## Returns the CardUI-local destination point for the discard pile (bottom-right).
func _get_discard_dest_local() -> Vector2:
	# Control nodes don't have to_local(); use the canvas transform inverse instead.
	# Because CardUI is a full-screen Control with no rotation/scale, global == local.
	var inv := get_global_transform().affine_inverse()
	if discard_anchor:
		return inv * (discard_anchor.global_position + discard_anchor.size * 0.5)
	return inv * (get_viewport_rect().size - Vector2(60.0, 60.0))

## Animate a single card button FROM its current screen position TO the discard anchor.
## The button is reparented to this (CardUI) node first so it survives container rebuilds.
## on_done is called after the animation finishes.
func animate_discard_card(card_button: CardButton, on_done: Callable = Callable(), delay: float = 0.0) -> void:
	if not is_instance_valid(card_button):
		if on_done.is_valid():
			on_done.call()
		return
	
	# Remove from interactive tracking immediately so hover/input ignore it
	card_buttons.erase(card_button)
	if mouse_hovered_card == card_button:
		mouse_hovered_card = null
	
	# Reparent to CardUI root so the card survives any container layout changes
	# while still being visible on top of everything.
	var saved_global_pos := card_button.global_position
	# Control doesn't expose global_scale; read local scale (CardUI has no parent scaling).
	var saved_scale: Vector2 = card_button.scale
	card_button.reparent(self)
	card_button.position = get_global_transform().affine_inverse() * saved_global_pos
	card_button.scale = saved_scale
	card_button.z_index = 250
	
	var dest := _get_discard_dest_local() - card_button.size * 0.5
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(card_button, "position", dest, DISCARD_ANIM_DURATION).set_delay(delay)
	tween.tween_property(card_button, "scale", Vector2(0.25, 0.25), DISCARD_ANIM_DURATION).set_delay(delay)
	tween.tween_property(card_button, "modulate:a", 0.0,
		DISCARD_ANIM_DURATION * 0.65).set_delay(delay + DISCARD_ANIM_DURATION * 0.35)
	
	tween.chain().tween_callback(func():
		if is_instance_valid(card_button):
			card_button.queue_free()
		if on_done.is_valid():
			on_done.call()
	)

## Discard the entire current visible hand to the discard pile with a staggered animation.
## Awaitable — returns after all animations have finished.
func discard_hand_to_pile() -> void:
	if _is_discarding_hand:
		return
	_is_discarding_hand = true
	
	# Snapshot the buttons to discard (card_buttons gets mutated below)
	var to_discard: Array = card_buttons.duplicate()
	card_buttons.clear()
	mouse_hovered_card = null
	selected_card_index = -1
	
	if to_discard.is_empty():
		_is_discarding_hand = false
		return
	
	var dest := _get_discard_dest_local()
	var total_anim_time := DISCARD_STAGGER * (to_discard.size() - 1) + DISCARD_ANIM_DURATION + 0.05
	
	for i in range(to_discard.size()):
		var cb: Control = to_discard[i]
		if not is_instance_valid(cb):
			continue
		
		# Reparent each card to CardUI root
		var saved_pos := cb.global_position
		var saved_scale: Vector2 = cb.scale
		cb.reparent(self)
		cb.position = get_global_transform().affine_inverse() * saved_pos
		cb.scale = saved_scale
		cb.z_index = 250 - i
		
		var delay := DISCARD_STAGGER * i
		var btn_size := cb.size
		var tween := create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(cb, "position", dest - btn_size * 0.5, DISCARD_ANIM_DURATION).set_delay(delay)
		tween.tween_property(cb, "scale", Vector2(0.25, 0.25), DISCARD_ANIM_DURATION).set_delay(delay)
		tween.tween_property(cb, "modulate:a", 0.0,
			DISCARD_ANIM_DURATION * 0.65).set_delay(delay + DISCARD_ANIM_DURATION * 0.35)
		tween.chain().tween_callback(func():
			if is_instance_valid(cb):
				cb.queue_free()
		)
	
	await get_tree().create_timer(total_anim_time).timeout
	_is_discarding_hand = false

# ─────────────────────────────────────────────────────────────────────────────
# HAND DISPLAY
# ─────────────────────────────────────────────────────────────────────────────

func update_hand_display():
	if not card_battle_manager or not card_container:
		return
	
	card_container.add_theme_constant_override("separation", -20)
	
	var hand = card_battle_manager.get_hand()
	var current_hand_size = hand.size()
	var is_adding_card = current_hand_size > _previous_hand_size
	
	# If we're adding cards (not rebuilding the whole hand), preserve existing cards
	if is_adding_card and _previous_hand_size > 0:
		# Store old positions of existing cards before fanning
		var old_positions = []
		for i in range(_previous_hand_size):
			if i < card_buttons.size() and card_buttons[i] is CardButton:
				var cb = card_buttons[i] as CardButton
				old_positions.append({
					"position": cb.card_3d_container.position if cb.card_3d_container else Vector2.ZERO,
					"rotation": cb.card_3d_container.rotation_degrees if cb.card_3d_container else 0.0
				})
			else:
				old_positions.append({"position": Vector2.ZERO, "rotation": 0.0})
		
		# Only add the new cards
		var new_cards = hand.slice(_previous_hand_size)
		for i in range(new_cards.size()):
			var card = new_cards[i]
			var card_button = create_card_button(card)
			if card_button:
				card_buttons.append(card_button)
				
				# Visual indication for unplayable cards
				if card_battle_manager:
					var ap_info = card_battle_manager.get_ap_info()
					if ap_info.get("current_ap", 0) < card.cost:
						var card_content = card_button.get_node_or_null("Card3DContainer/CardViewport/CardContent")
						if card_content:
							card_content.modulate = Color(0.4, 0.4, 0.4, 0.8)
						else:
							card_button.modulate = Color(0.4, 0.4, 0.4, 0.8)
					else:
						var card_content = card_button.get_node_or_null("Card3DContainer/CardViewport/CardContent")
						if card_content:
							card_content.modulate = Color.WHITE
						else:
							card_button.modulate = Color.WHITE
				
				# Start invisible — _start_draw_animations will reveal + fly in from pile
				card_button.modulate.a = 0.0
				card_container.add_child(card_button)
		
		# Store the start index for animation before updating _previous_hand_size
		_new_card_start_index = _previous_hand_size
		
		# Apply fanning to set new positions for all cards
		apply_card_fanning()
		
		# Smoothly reposition existing cards from old to new positions
		_smoothly_reposition_existing_cards(old_positions)
	else:
		# Full rebuild (turn start, card played, etc.)
		# Remove any old card buttons still in the container
		for child in card_container.get_children():
			child.queue_free()
		
		card_buttons.clear()
		mouse_hovered_card = null
		selected_card_index = -1
		
		for i in range(hand.size()):
			var card = hand[i]
			var card_button = create_card_button(card)
			if card_button:
				card_buttons.append(card_button)
				
				# Visual indication for unplayable cards
				if card_battle_manager:
					var ap_info = card_battle_manager.get_ap_info()
					if ap_info.get("current_ap", 0) < card.cost:
						var card_content = card_button.get_node_or_null("Card3DContainer/CardViewport/CardContent")
						if card_content:
							card_content.modulate = Color(0.4, 0.4, 0.4, 0.8)
						else:
							card_button.modulate = Color(0.4, 0.4, 0.4, 0.8)
					else:
						var card_content = card_button.get_node_or_null("Card3DContainer/CardViewport/CardContent")
						if card_content:
							card_content.modulate = Color.WHITE
						else:
							card_button.modulate = Color.WHITE
				
				# Start invisible — _start_draw_animations will reveal + fly in from pile
				card_button.modulate.a = 0.0
				card_container.add_child(card_button)
		
		# For full rebuild, animate all cards
		_new_card_start_index = 0
		
		# Apply fanning to set positions
		apply_card_fanning()
	
	_update_card_selection()
	update_pile_counts()
	
	# Update previous hand size
	_previous_hand_size = current_hand_size
	
	# Defer draw animations so the HBoxContainer finishes layout first,
	# giving us accurate global positions to calculate the pile → hand offset.
	# If the CardUI is currently hidden (e.g. player hasn't opened the card
	# menu yet this turn), mark the animation as pending so _notification()
	# fires it the moment the node becomes visible.
	if visible:
		call_deferred("_start_draw_animations")
	else:
		_draw_anim_pending = true

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

func _smoothly_reposition_existing_cards(old_positions: Array = []) -> void:
	# Smoothly animate existing cards to their new fan positions
	if not card_container:
		return
	
	# Get the number of existing cards (before new ones were added)
	var existing_count = _previous_hand_size
	
	# Reposition existing cards
	for i in range(existing_count):
		if i >= card_buttons.size():
			break
		
		var card_button = card_buttons[i]
		if is_instance_valid(card_button) and card_button is CardButton:
			var tween = create_tween()
			tween.set_parallel(true)
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			
			if card_button.card_3d_container:
				# If old positions were provided, animate from old to new
				if i < old_positions.size():
					var old_pos = old_positions[i]
					card_button.card_3d_container.position = old_pos.position
					card_button.card_3d_container.rotation_degrees = old_pos.rotation
				
				tween.tween_property(card_button.card_3d_container, "position", 
					Vector2(0.0, card_button.base_y_offset), 0.3)
				tween.tween_property(card_button.card_3d_container, "rotation_degrees", 
					card_button.base_rotation, 0.3)

func create_card_button(card: CardData) -> Control:
	if not card_button_scene:
		var button = Button.new()
		button.text = card.name + " (Cost: " + str(card.cost) + ")"
		button.pressed.connect(func(): _on_card_button_pressed(card))
		return button
	
	var card_button = card_button_scene.instantiate()
	if card_button is CardButton:
		card_button.hand_bounds_provider = Callable(self, "get_hand_zone_rect")
	if card_button.has_method("setup"):
		card_button.setup(card)
		card_button.card_played.connect(func(_card_data): _on_card_button_pressed(card))
		if card_button.has_signal("card_drag_started"):
			card_button.card_drag_started.connect(_on_card_drag_started)
		if card_button.has_signal("card_drag_ended"):
			card_button.card_drag_ended.connect(_on_card_drag_ended)
	
	return card_button

func _on_card_drag_started(card_button: CardButton) -> void:
	card_button.z_index = 200
	if mouse_hovered_card != card_button and is_instance_valid(mouse_hovered_card) \
			and mouse_hovered_card.is_hovered:
		mouse_hovered_card.set_controller_hover(false)
	mouse_hovered_card = null

func _on_card_drag_ended(card_button: CardButton, dropped_in_play_zone: bool) -> void:
	if dropped_in_play_zone:
		if not _on_card_button_pressed(card_button.card_data):
			_slot_card_back_into_hand(card_button)
	else:
		_slot_card_back_into_hand(card_button)

func _slot_card_back_into_hand(card_button: CardButton) -> void:
	if not is_instance_valid(card_button):
		return
	var did_reorder := _reorder_card_to_closest_slot(card_button)
	var panel_global_before: Variant = null
	if did_reorder and card_button.	card_3d_container:
		panel_global_before = card_button.	card_3d_container.global_position
	return_card_to_hand(card_button, panel_global_before)

func _reorder_card_to_closest_slot(card_button: CardButton) -> bool:
	if not is_instance_valid(card_button) or not card_container:
		return false
	if not card_buttons.has(card_button):
		return false
	
	var release_x := _get_release_center_x(card_button)
	var current_index := card_buttons.find(card_button)
	
	var others: Array = []
	var queued_count := 0
	for child in card_container.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			queued_count += 1
			continue
		if child == card_button:
			continue
		others.append(child)
	
	var insert_index := others.size()
	for i in range(others.size()):
		var other = others[i]
		var other_center_x: float = other.global_position.x + other.size.x * 0.5
		if release_x < other_center_x:
			insert_index = i
			break
	
	if insert_index == current_index:
		return false
	
	var panels_before := {}
	for child in card_container.get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion() \
				and child != card_button and child is CardButton and child.	card_3d_container:
			panels_before[child] = child.	card_3d_container.global_position
	
	card_container.move_child(card_button, queued_count + insert_index)
	
	card_buttons.remove_at(current_index)
	card_buttons.insert(insert_index, card_button)
	
	call_deferred("_apply_reorder_compensation", panels_before)
	return true

func _apply_reorder_compensation(panels_before: Dictionary) -> void:
	for card in panels_before:
		if not is_instance_valid(card) or not card.	card_3d_container:
			continue
		var before: Vector2 = panels_before[card]
		card.	card_3d_container.position = before - card.global_position
		var tween := create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(card.	card_3d_container, "position",
			Vector2(0.0, card.base_y_offset), 0.25)
		tween.tween_property(card.	card_3d_container, "rotation_degrees",
			card.base_rotation, 0.25)

func _get_release_center_x(card_button: CardButton) -> float:
	if card_button.	card_3d_container:
		var t = card_button.	card_3d_container.get_global_transform()
		return (t * (card_button.	card_3d_container.size * 0.5)).x
	return card_button.global_position.x + card_button.size.x * 0.5

func return_card_to_hand(card_button: CardButton, panel_global_before_reorder: Variant = null) -> void:
	if not is_instance_valid(card_button):
		return
	
	card_button.is_dragging = false
	card_button.is_returning = true
	card_button.is_out_of_hand = false
	apply_card_fanning()
	card_button.z_index = 150
	
	if panel_global_before_reorder != null:
		call_deferred("_compensate_returned_panel", card_button, panel_global_before_reorder)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EaseType.EASE_OUT)
	tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	
	if card_button.	card_3d_container:
		tween.tween_property(card_button.	card_3d_container, "position", Vector2(0.0, card_button.base_y_offset), 0.25)
		tween.tween_property(card_button.	card_3d_container, "rotation_degrees", card_button.base_rotation, 0.25)
		tween.tween_property(card_button.	card_3d_container, "scale", Vector2.ONE, 0.25)
	
	if card_button.card_shader_material:
		tween.tween_property(card_button.card_shader_material, "shader_parameter/y_rot", 0.0, 0.25)
		tween.tween_property(card_button.card_shader_material, "shader_parameter/x_rot", 0.0, 0.25)
	
	tween.chain().tween_callback(func():
		if is_instance_valid(card_button):
			card_button.z_index = card_button.base_z_index
			card_button.is_hovered = false
			card_button.is_dragging = false
			card_button.is_returning = false
			if card_button.	card_3d_container:
				card_button.	card_3d_container.position = Vector2(0.0, card_button.base_y_offset)
				card_button.	card_3d_container.rotation_degrees = card_button.base_rotation
				card_button.	card_3d_container.scale = Vector2.ONE
			var cm = card_button._get_cursor_manager()
			if cm:
				cm.notify_hover_exited(card_button)
				cm.force_cursor_state(CursorDisplay.CursorState.DEFAULT)
	)

func _compensate_returned_panel(card_button: CardButton, panel_global_before: Vector2) -> void:
	if not is_instance_valid(card_button) or not card_button.	card_3d_container:
		return
	card_button.	card_3d_container.position = panel_global_before - card_button.global_position

# ─────────────────────────────────────────────────────────────────────────────
# AP & SIGNAL HANDLERS
# ─────────────────────────────────────────────────────────────────────────────

func update_ap_display():
	pass

func _on_card_button_pressed(card: CardData) -> bool:
	if card_battle_manager:
		if card_battle_manager.is_executing_card:
			return false
		var ap_info = card_battle_manager.get_ap_info()
		if ap_info.get("current_ap", 0) < card.cost:
			return false
	
	# Track which button is being played so _on_card_played can animate it to the discard pile
	_pending_discard_button = null
	for cb in card_buttons:
		if is_instance_valid(cb) and cb is CardButton and (cb as CardButton).card_data == card:
			_pending_discard_button = cb as CardButton
			break
	
	card_selected.emit(card)
	return true

func set_end_turn_button_visible(_p_visible: bool) -> void:
	pass

func _on_end_turn_pressed():
	end_turn_pressed.emit()

func _on_ap_changed(_current_ap: int, _max_ap: int):
	update_ap_display()
	update_card_playability()

func update_card_playability():
	# Update visual playability of all cards in hand
	if not card_battle_manager:
		return
	
	var ap_info = card_battle_manager.get_ap_info()
	var current_ap = ap_info.get("current_ap", 0)
	
	for card_button in card_buttons:
		if not is_instance_valid(card_button):
			continue
		
		# Get the card data from the card button
		var card_data = card_button.card_data
		if not card_data:
			continue
		
		# Check if card is playable based on AP cost
		var is_playable = current_ap >= card_data.cost
		
		# Update visual indication
		var card_content = card_button.get_node_or_null("Card3DContainer/CardViewport/CardContent")
		if card_content:
			if is_playable:
				card_content.modulate = Color.WHITE
			else:
				card_content.modulate = Color(0.4, 0.4, 0.4, 0.8)
		else:
			if is_playable:
				card_button.modulate = Color.WHITE
			else:
				card_button.modulate = Color(0.4, 0.4, 0.4, 0.8)

func return_pending_card_to_hand():
	# Return the pending card to hand when targeting is cancelled
	if is_instance_valid(_pending_discard_button):
		return_card_to_hand(_pending_discard_button)
		_pending_discard_button = null

func _on_card_played(_card = null, _target = null):
	# ── 1. Animate the played card from its current position to the discard pile ──
	var discard_btn := _pending_discard_button
	_pending_discard_button = null
	
	if is_instance_valid(discard_btn):
		# animate_discard_card handles reparenting and removal from card_buttons
		animate_discard_card(discard_btn)
	
	# ── 2. Rebuild the remaining hand (draw animations play for unchanged cards) ──
	# Reset previous hand size since we're doing a full rebuild
	_previous_hand_size = 0
	update_hand_display()
	update_pile_counts()

func set_card_targeting_mode(_enabled: bool):
	pass
	# Enable/disable card targeting UI
