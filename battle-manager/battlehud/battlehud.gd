class_name BattleHud
extends CanvasLayer

signal action_selected(action: String, item: Item)
signal menu_opened
signal card_selected(card: CardData)
signal end_turn_pressed

@onready var item_button_scene: PackedScene = preload("res://battle-manager/battlehud/item-button-preset.tscn")
@onready var item_container = $Control/Items/ScrollContainer/BoxContainer
@onready var turn_queue_ui: TurnQueueUI = $Control/TurnQueueUI
@onready var party_status_card_scene: PackedScene = preload("res://battle-manager/battlehud/party_status_card.tscn")
@onready var parry_window_scene: PackedScene = preload("res://battle-manager/battlehud/parry_window.tscn")

@onready var action_buttons: ActionButtons = $Control/ActionButtons
@onready var attack_button: TextureButton = $Control/ActionButtons.get_node("AttackWrapper/Attack")
@onready var items_button: TextureButton = $Control/ActionButtons.get_node("ItemsWrapper/Items")
@onready var run_button: TextureButton = $Control/ActionButtons.get_node("RunWrapper/Run")
@onready var end_turn_button: TextureButton = $Control/ActionButtons.get_node("EndTurnWrapper/EndTurnButton")
@onready var global_back_button: Button = $Control/BackButton
@onready var battle_text_display: RichTextLabel = $Control/BattleTextDisplay/Text
@onready var item_select: Control = $Control/Items
@onready var card_ui: Control = $Control/CardUI
@onready var party_status_panel: HBoxContainer = $Control/PartyStatusPanel
@onready var boss_bar = $Control/BossBar
@onready var enemy_overhead_bars_container: Control = $Control/EnemyOverheadBarsContainer
@onready var move_banner: Control = $Control/MoveBanner
@onready var move_banner_actor: Label = $Control/MoveBanner/Panel/VBox/ActorLabel
@onready var move_banner_label: Label = $Control/MoveBanner/Panel/VBox/MoveLabel
@onready var cursor_system: CursorManager = $CursorSystem

var aoe_confirm_button: Button = null

const ENEMY_OVERHEAD_BAR_SCENE: PackedScene = preload("res://battle-manager/battlehud/EnemyOverheadBar.tscn")

# Maps enemy battler -> overhead bar node
var enemy_overhead_bar_map: Dictionary = {}

var activeBattler: Node = null
var enemy: Node = null

# UI State Management
enum UIState {
	BASE_STATE,        # Default starting state: Attack button visible, CardUI hidden, Items menu hidden
	CARD_SELECT_STATE, # Attack button hidden, CardUI visible, Items menu hidden
	ITEMS_MENU_STATE,  # Attack button visible, CardUI hidden, Items menu visible
	CARD_EXECUTION_STATE, # All UI hidden during card execution
	TARGETING_STATE    # CardUI hidden, action buttons hidden during targeting
}

var current_ui_state: UIState = UIState.BASE_STATE
var previous_ui_state: UIState = UIState.BASE_STATE

# Resolve the active BattleCamera controller for projecting 3D battler
# positions into HUD screen space (handles the low-res SubViewport scaling).
func _get_battle_camera() -> BattleCamera:
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager:
		return battle_manager.battle_camera as BattleCamera
	return null

func set_ui_state(new_state: Variant) -> void:
	# Convert integer to UIState enum if needed
	if typeof(new_state) == TYPE_INT:
		new_state = new_state as UIState
	
	# Save previous state when entering special states (but don't trigger hiding animations)
	if (new_state == UIState.CARD_EXECUTION_STATE or new_state == UIState.TARGETING_STATE) and current_ui_state != new_state:
		previous_ui_state = current_ui_state
	
	current_ui_state = new_state
	
	match new_state:
		UIState.BASE_STATE:
			# Attack button visible, CardUI hidden, Items menu hidden
			if card_ui:
				card_ui.visible = false
			if item_select:
				item_select.visible = false
			# Action buttons handled separately via juice system
		
		UIState.CARD_SELECT_STATE:
			# Attack button hidden, CardUI visible, Items menu hidden
			if card_ui:
				card_ui.visible = true
			if item_select:
				item_select.visible = false
			# Action buttons handled separately via juice system
		
		UIState.ITEMS_MENU_STATE:
			# Attack button visible, CardUI hidden, Items menu visible
			if card_ui:
				card_ui.visible = false
			if item_select:
				item_select.visible = true
			# Action buttons handled separately via juice system
		
		UIState.CARD_EXECUTION_STATE:
			# CardUI hidden, Items hidden (action buttons handled separately via juice system)
			if card_ui:
				card_ui.visible = false
			if item_select:
				item_select.visible = false
		
		UIState.TARGETING_STATE:
			# CardUI hidden, Items hidden (action buttons handled separately via juice system)
			if card_ui:
				card_ui.visible = false
			if item_select:
				item_select.visible = false
	
	_update_back_button_visibility()

var active_allies: Array = []
var active_enemies: Array = []

# Tracks last known AP for each ally: { Battler -> { "current": int, "max": int } }
var last_ap_by_battler: Dictionary = {}
var ally_cards_map: Dictionary = {} # Battler -> PartyStatusCard

func _ready():
	# Connect CardUI signals if it exists
	if card_ui:
		if card_ui.has_signal("card_selected"):
			card_ui.card_selected.connect(func(card): card_selected.emit(card))
		if card_ui.has_signal("end_turn_pressed"):
			card_ui.end_turn_pressed.connect(func(): end_turn_pressed.emit())
	
	# Connect ActionButtons signals
	if action_buttons:
		if attack_button:
			attack_button.pressed.connect(_on_attack_pressed)
		if items_button:
			items_button.pressed.connect(_on_items_pressed)
		if run_button:
			run_button.pressed.connect(_on_run_pressed)
		if end_turn_button:
			end_turn_button.pressed.connect(_on_end_turn_button_pressed)
	
	# Initialize in base state
	set_ui_state(UIState.BASE_STATE)
	hide_action_buttons()
	
	# Listen for card battle manager AP changes
	call_deferred("_connect_card_battle_manager")
	
	# Initialize cursor system
	_initialize_cursor_system()

func _connect_card_battle_manager() -> void:
	var cbm = get_tree().get_first_node_in_group("card_battle_manager")
	if cbm and cbm.has_signal("ap_changed"):
		if not cbm.ap_changed.is_connected(_on_cbm_ap_changed):
			cbm.ap_changed.connect(_on_cbm_ap_changed)
	if cbm and cbm.has_signal("card_played"):
		if not cbm.card_played.is_connected(_on_cbm_card_played):
			cbm.card_played.connect(_on_cbm_card_played)

func _on_cbm_ap_changed(current_ap: int, max_ap: int) -> void:
	if activeBattler and is_instance_valid(activeBattler):
		last_ap_by_battler[activeBattler] = { "current": current_ap, "max": max_ap }
	update_party_status()

func _initialize_cursor_system() -> void:
	if not cursor_system:
		return
	
	# Connect cursor system signals
	if cursor_system.has_signal("cursor_state_changed"):
		cursor_system.cursor_state_changed.connect(_on_cursor_state_changed)
	if cursor_system.has_signal("cursor_hover_target"):
		cursor_system.cursor_hover_target.connect(_on_cursor_hover_target)
	if cursor_system.has_signal("cursor_clicked"):
		cursor_system.cursor_clicked.connect(_on_cursor_clicked)

func _on_cursor_state_changed(new_state: String) -> void:
	# Handle cursor state changes in battle HUD
	match new_state:
		"attack":
			# Could update UI to reflect attack mode
			pass
		"interact":
			# Could update UI to reflect interaction mode
			pass
		"targeting":
			# Could update UI to reflect targeting mode
			pass
		"default":
			# Return to normal UI state
			pass

func _on_cursor_hover_target(target: Node) -> void:
	# Handle cursor hovering over targets
	if target and target.is_in_group("enemies"):
		# Could highlight enemy or show target info
		pass

func _on_cursor_clicked(position: Vector2) -> void:
	# Handle cursor clicks for battle interactions
	pass

func _on_cbm_card_played(_card = null, _target = null) -> void:
	# Always restore state after card execution completes (systematic for all card types)
	var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	if card_battle_manager:
		var hand = card_battle_manager.get_hand()
		if hand.is_empty():
			set_ui_state(UIState.BASE_STATE)
		else:
			# Always restore to CARD_SELECT_STATE if hand not empty
			set_ui_state(UIState.CARD_SELECT_STATE)
	
	# Restore action buttons visibility
	if action_buttons and activeBattler:
		action_buttons.show()
		action_buttons.animate_buttons_in()
		
		# Set button states based on current state
		match current_ui_state:
			UIState.BASE_STATE:
				if attack_button:
					action_buttons.show_button("Attack")
				if items_button:
					action_buttons.show_button("Items")
			UIState.CARD_SELECT_STATE:
				if attack_button:
					action_buttons.hide_button("Attack")
				if items_button:
					action_buttons.show_button("Items")

func _process(_delta: float) -> void:
	# Respect UI state system - hide action buttons during execution/targeting
	if current_ui_state == UIState.CARD_EXECUTION_STATE or current_ui_state == UIState.TARGETING_STATE:
		if action_buttons and action_buttons.visible:
			action_buttons.hide()
		return
	
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and (battle_manager.is_animating or battle_manager.in_target_selection):
		if action_buttons and action_buttons.visible:
			action_buttons.hide()
		return
	
	var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	if card_battle_manager and card_battle_manager.is_executing_card:
		set_ui_state(UIState.CARD_EXECUTION_STATE)
		return
	
	if action_buttons and action_buttons.visible and activeBattler and is_instance_valid(activeBattler):
		var battle_camera = _get_battle_camera()
		if battle_camera:
			# Project 3D position (chest/head height) to 2D screen coordinate
			var world_pos = activeBattler.global_position + Vector3(0, 1.2, 0)
			# Only position if in front of camera
			if not battle_camera.is_position_behind(world_pos):
				var screen_pos = battle_camera.world_to_screen(world_pos)
				# Position action buttons to the RIGHT of the character
				var target_pos = screen_pos + Vector2(70.0, -50.0)
				# Clamp to screen margins
				var vp_size = get_viewport().get_visible_rect().size
				target_pos.x = clamp(target_pos.x, 20.0, vp_size.x - action_buttons.size.x - 20.0)
				target_pos.y = clamp(target_pos.y, 20.0, vp_size.y - action_buttons.size.y - 120.0)
				
				# Smooth follow or direct snap
				action_buttons.position = action_buttons.position.lerp(target_pos, 0.25)

func on_start_combat(enemy_node: Node):
	enemy = enemy_node
	if not active_enemies.has(enemy_node):
		active_enemies.append(enemy_node)
		_spawn_enemy_overhead_bar(enemy_node)
		_check_boss_bar(enemy_node)
		# Register enemy with cursor system
		if cursor_system:
			cursor_system.register_enemy_battler(enemy_node)
	update_health_bars()

func on_add_character(character: Node):
	if character.is_in_group("players"):
		if not active_allies.has(character):
			active_allies.append(character)
			if not last_ap_by_battler.has(character):
				last_ap_by_battler[character] = { "current": 3, "max": 3 }
		_rebuild_party_status_panel()
	else:
		if not active_enemies.has(character):
			active_enemies.append(character)
		_spawn_enemy_overhead_bar(character)
		_check_boss_bar(character)

func _rebuild_party_status_panel() -> void:
	if not party_status_panel:
		return
	
	for child in party_status_panel.get_children():
		child.queue_free()
	ally_cards_map.clear()
	
	for ally in active_allies:
		if not is_instance_valid(ally):
			continue
		var card = _create_ally_status_card(ally)
		party_status_panel.add_child(card)
		ally_cards_map[ally] = card
	
	update_party_status()

func _create_ally_status_card(ally: Battler) -> Control:
	if not party_status_card_scene:
		push_error("Party status card scene not loaded!")
		return null
	
	var card = party_status_card_scene.instantiate()
	if not card:
		push_error("Failed to instantiate party status card!")
		return null
	
	if card is PartyStatusCard:
		card.setup(ally)
		return card
	else:
		push_error("Instantiated node is not a PartyStatusCard!")
		return null

func update_party_status() -> void:
	# The "active" highlight may only appear for the ally that is currently
	# taking their turn. When it's an enemy's turn (or before the first turn),
	# every ally card must be inactive.
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	var is_player_turn := false
	var acting_ally = activeBattler
	if battle_manager and battle_manager.current_character:
		acting_ally = battle_manager.current_character
		is_player_turn = acting_ally in battle_manager.players
	else:
		is_player_turn = activeBattler != null

	for ally in active_allies:
		if not is_instance_valid(ally) or not ally_cards_map.has(ally):
			continue
		
		var card = ally_cards_map[ally] as PartyStatusCard
		if not is_instance_valid(card):
			continue
		
		var is_active = is_player_turn and ally == acting_ally
		card.set_active(is_active)
		
		# Update HP
		card.update_hp(ally.current_health, ally.max_health)
		
		# Update AP (from last_ap_by_battler)
		var ap_data = last_ap_by_battler.get(ally, { "current": 3, "max": 3 })
		var cur_ap = ap_data.get("current", 3)
		var max_ap = ap_data.get("max", 3)
		card.update_ap(cur_ap, max_ap)

func set_activebattler(character: Node):
	activeBattler = character
	update_party_status()

func update_health_bars():
	update_party_status()

## Spawn an overhead health bar for a given enemy (if not already spawned).
func _spawn_enemy_overhead_bar(enemy_node: Node) -> void:
	if not is_instance_valid(enemy_node):
		return
	if enemy_overhead_bar_map.has(enemy_node):
		return
	if not enemy_overhead_bars_container:
		return
	var bar = ENEMY_OVERHEAD_BAR_SCENE.instantiate()
	enemy_overhead_bars_container.add_child(bar)
	bar.setup(enemy_node as Battler)
	enemy_overhead_bar_map[enemy_node] = bar

## Check if enemy_node is a boss and show the boss bar if so.
func _check_boss_bar(enemy_node: Node) -> void:
	if not boss_bar or not is_instance_valid(enemy_node):
		return
	var is_boss_enemy := false
	if "is_boss" in enemy_node:
		is_boss_enemy = enemy_node.is_boss
	elif enemy_node.stats and "is_boss" in enemy_node.stats:
		is_boss_enemy = enemy_node.stats.is_boss
	if is_boss_enemy:
		boss_bar.show_boss(enemy_node as Battler)

func show_action_buttons(character: Node):
	if not action_buttons:
		return
	if not character or not character.is_in_group("players"):
		return
	
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.is_animating:
		return
	
	var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	if card_battle_manager and card_battle_manager.is_executing_card:
		return
	
	activeBattler = character
	update_party_status()
	
	# Initial positioning near the battler
	if activeBattler and is_instance_valid(activeBattler):
		var battle_camera = _get_battle_camera()
		if battle_camera:
			var world_pos = activeBattler.global_position + Vector3(0, 1.2, 0)
			if not battle_camera.is_position_behind(world_pos):
				var screen_pos = battle_camera.world_to_screen(world_pos)
				var target_pos = screen_pos + Vector2(70.0, -50.0)
				action_buttons.position = target_pos
	
	# Always start in BASE_STATE (Attack button visible)
	set_ui_state(UIState.BASE_STATE)
	
	if end_turn_button:
		end_turn_button.disabled = false
	
	# Setup input prompts
	_setup_input_prompts()
	
	# Use juice system to animate action buttons in
	action_buttons.show()
	action_buttons.animate_buttons_in()
	
	# Set button states via juice system (Attack visible, Items visible in BASE_STATE)
	if action_buttons:
		if attack_button:
			action_buttons.show_button("Attack")
		if items_button:
			action_buttons.show_button("Items")
	
	activeBattler = character
	update_party_status()
	
	# Set current player battler in card battle manager
	if card_battle_manager:
		card_battle_manager.current_player_battler = character
	
	# Initial positioning near the battler
	if activeBattler and is_instance_valid(activeBattler):
		var battle_camera = _get_battle_camera()
		if battle_camera:
			var world_pos = activeBattler.global_position + Vector3(0, 1.2, 0)
			if not battle_camera.is_position_behind(world_pos):
				var screen_pos = battle_camera.world_to_screen(world_pos)
				var target_pos = screen_pos + Vector2(70.0, -50.0)
				action_buttons.position = target_pos
	
	# Always start in BASE_STATE (Attack button visible)
	set_ui_state(UIState.BASE_STATE)
	
	if end_turn_button:
		end_turn_button.disabled = false
	
	# Setup input prompts
	_setup_input_prompts()
	
	# Use the new ActionButtons animation system
	action_buttons.animate_buttons_in()

func hide_action_buttons():
	# Handle action buttons via juice system separately
	if action_buttons:
		action_buttons.animate_buttons_out()
		var action_tween = action_buttons.get_tween()
		if action_tween:
			await action_tween.finished
		action_buttons.hide()
	
	# Update state to handle CardUI and Items
	set_ui_state(UIState.CARD_EXECUTION_STATE)

func _update_back_button_visibility():
	# Systematic back button visibility management based on current UI state
	var should_show = false
	
	# Show back button in states that need back navigation
	match current_ui_state:
		UIState.ITEMS_MENU_STATE:
			should_show = true
		UIState.CARD_SELECT_STATE:
			should_show = true
		UIState.TARGETING_STATE:
			should_show = true
	
	if global_back_button:
		global_back_button.visible = should_show

func _setup_input_prompts():
	# Setup input prompts for action buttons
	if attack_button:
		var attack_prompt = attack_button.get_node_or_null("AttackPrompt")
		if attack_prompt:
			attack_prompt.set_meta("action_name", "attack")
	
	if items_button:
		var items_prompt = items_button.get_node_or_null("ItemsPrompt")
		if items_prompt:
			items_prompt.set_meta("action_name", "toggle_items")
	
	if run_button:
		var run_prompt = run_button.get_node_or_null("RunPrompt")
		if run_prompt:
			run_prompt.set_meta("action_name", "toggle_run")
	
	if end_turn_button:
		var end_turn_prompt = end_turn_button.get_node_or_null("EndTurnPrompt")
		if end_turn_prompt:
			end_turn_prompt.set_meta("action_name", "ui_cancel")
	
	if global_back_button:
		var back_prompt = global_back_button.get_node_or_null("BackPrompt")
		if back_prompt:
			back_prompt.set_meta("action_name", "ui_cancel")

func update_character_info():
	update_party_status()

# Action button signals
func setup_item_list(battler: Battler) -> void:
	for child in item_container.get_children():
		child.queue_free()
	
	var has_items = false
	if battler and battler.inventory and !battler.inventory.collection.is_empty():
		for item: Item in battler.inventory.collection.keys():
			if !item.is_battle_item:
				continue
			has_items = true
			var button = item_button_scene.instantiate()
			item_container.add_child(button)
			button.setup(item, battler.inventory.collection.get(item))
			button.item_selected.connect(_on_item_selected)
	
	if not has_items:
		var empty_lbl = Label.new()
		empty_lbl.text = "No usable battle items"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_container.add_child(empty_lbl)
	
	menu_opened.emit()

func _on_item_back_pressed() -> void:
	_close_items_menu()

func _close_items_menu():
	set_ui_state(UIState.BASE_STATE)

func _close_card_menu():
	set_ui_state(UIState.BASE_STATE)

func _on_item_selected(item: Item) -> void:
	set_ui_state(UIState.CARD_SELECT_STATE)
	action_selected.emit("item", item)
	action_selected.emit("item", item)

func _on_attack_pressed() -> void:
	set_ui_state(UIState.CARD_SELECT_STATE)
	
	# Use juice system to handle button visibility transitions
	if action_buttons:
		if attack_button:
			action_buttons.hide_button("Attack")
		if items_button:
			action_buttons.show_button("Items")

func close_card_ui() -> void:
	set_ui_state(UIState.BASE_STATE)

func _on_items_pressed() -> void:
	setup_item_list(activeBattler)
	set_ui_state(UIState.ITEMS_MENU_STATE)
	
	# Use juice system to show Attack button and hide Items button
	if action_buttons:
		if attack_button:
			action_buttons.show_button("Attack")
		if items_button:
			action_buttons.hide_button("Items")

func _unhandled_input(event: InputEvent) -> void:
	var handled = false
	
	# Check if reactive defense is active (B button = dodge, not end turn)
	var qte_manager = get_tree().get_first_node_in_group("qte_manager")
	var qte_active = qte_manager.is_qte_active if qte_manager else false
	var qte_type = qte_manager.current_qte_type if qte_manager else ""
	var reactive_defense_active = qte_active and (qte_type == "REACTIVE_DODGE" or qte_type == "REACTIVE_PARRY")
	
	# Don't handle B button when in reactive defense mode - let QTE manager handle it
	if reactive_defense_active and event.is_action_pressed("ui_cancel"):
		return
	
	# Only process action buttons when action buttons list is visible
	if action_buttons and action_buttons.visible:
		if event.is_action_pressed("attack"):
			if attack_button and action_buttons.is_button_visible("Attack"):
				_on_attack_pressed()
			handled = true
		elif event.is_action_pressed("toggle_items"):
			if items_button and action_buttons.is_button_visible("Items"):
				_on_items_pressed()
			handled = true
		elif event.is_action_pressed("toggle_run"):
			if run_button and action_buttons.is_button_visible("Run"):
				_on_run_pressed()
			handled = true
		elif event.is_action_pressed("ui_cancel"):
			# Contextual: B button works for both end turn and cancel
			if end_turn_button and action_buttons.is_button_visible("EndTurnButton"):
				_on_end_turn_button_pressed()
			else:
				_on_global_back_pressed()
			handled = true
	
	# Handle cancel key for all menus via global back (B button also cancels)
	if not handled and event.is_action_pressed("ui_cancel"):
		_on_global_back_pressed()
		handled = true
	
	# Only consume input if we actually handled it
	if handled:
		get_viewport().set_input_as_handled()

func _on_run_pressed() -> void:
	hide_action_buttons()
	action_selected.emit("run", null)

func _on_end_turn_button_pressed() -> void:
	if end_turn_button:
		end_turn_button.disabled = true
	end_turn_pressed.emit()

func set_targeting_mode(enabled: bool) -> void:
	# Handle targeting mode visibility
	if enabled:
		set_ui_state(UIState.TARGETING_STATE)
		# Update cursor system for targeting
		if cursor_system:
			cursor_system.force_cursor_state(CursorDisplay.CursorState.TARGETING)
	else:
		# Only set CARD_EXECUTION_STATE if we're actually exiting targeting mode
		# Don't interfere with normal card execution flow for self-targeting cards
		if current_ui_state == UIState.TARGETING_STATE:
			set_ui_state(UIState.CARD_EXECUTION_STATE)
		# Restore cursor system state
		if cursor_system:
			cursor_system.restore_previous_state()

func set_aoe_confirmation_mode(enabled: bool, card_name: String = "", target_count: int = 0) -> void:
	if enabled:
		set_ui_state(UIState.CARD_EXECUTION_STATE)
		
		# Show AOE confirmation UI
		if global_back_button:
			global_back_button.visible = true
			if global_back_button.has_method("set_text"):
				global_back_button.set_text("Cancel")
		
		# Create or show confirm button
		_ensure_aoe_confirm_button()
		if aoe_confirm_button:
			aoe_confirm_button.visible = true
			if aoe_confirm_button.has_method("set_text"):
				aoe_confirm_button.set_text("Execute " + card_name + " (" + str(target_count) + " targets)")
	else:
		hide_aoe_confirmation_mode()

func hide_aoe_confirmation_mode() -> void:
	if aoe_confirm_button:
		aoe_confirm_button.visible = false
	
	if global_back_button:
		global_back_button.visible = false

func _ensure_aoe_confirm_button() -> void:
	if not aoe_confirm_button:
		# Create confirm button dynamically
		aoe_confirm_button = Button.new()
		aoe_confirm_button.name = "AOEConfirmButton"
		aoe_confirm_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		aoe_confirm_button.set_position(Vector2(0, 100))
		aoe_confirm_button.set_size(Vector2(200, 50))
		aoe_confirm_button.pressed.connect(_on_aoe_confirm_pressed)
		add_child(aoe_confirm_button)

func _on_aoe_confirm_pressed() -> void:
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.has_method("confirm_aoe_execution"):
		battle_manager.confirm_aoe_execution()

func _on_global_back_pressed() -> void:
	# Handle different back contexts based on current UI state
	match current_ui_state:
		UIState.ITEMS_MENU_STATE:
			_close_items_menu()
		UIState.CARD_SELECT_STATE:
			_close_card_menu()
		UIState.TARGETING_STATE:
			# Handle targeting mode
			var battle_manager = get_tree().get_first_node_in_group("battle_manager")
			if battle_manager and battle_manager.has_method("exit_targeting_mode"):
				battle_manager.exit_targeting_mode()
			set_targeting_mode(false)

func update_ui():
	update_character_info()
	update_party_status()

# ============================================================================
# REACTIVE DEFENSE UI (DODGE / PARRY / PERFECT PARRY)
# ============================================================================
var _parry_window: ParryWindow = null

func show_parry_window(duration: float, perfect_duration: float, defender_name: String) -> void:
	hide_parry_window()
	
	if not parry_window_scene:
		push_error("Parry window scene not loaded!")
		return
	
	_parry_window = parry_window_scene.instantiate() as ParryWindow
	if not _parry_window:
		push_error("Failed to instantiate parry window!")
		return
	
	_parry_window.setup(defender_name, duration, perfect_duration)
	$Control.add_child(_parry_window)

func update_parry_window(time_remaining: float) -> void:
	if _parry_window and is_instance_valid(_parry_window):
		_parry_window.update_progress(time_remaining)

func hide_parry_window() -> void:
	if _parry_window and is_instance_valid(_parry_window):
		_parry_window.queue_free()
		_parry_window = null

# ============================================================================
# MOVE ANNOUNCEMENT BANNER
# ============================================================================
var _move_banner_tween: Tween

func show_move_announcement(actor_name: String, move_name: String, move_type: String = "attack") -> void:
	if not move_banner:
		return
	
	if _move_banner_tween and _move_banner_tween.is_running():
		_move_banner_tween.kill()
	
	if move_banner_actor:
		move_banner_actor.text = actor_name.to_upper()
	if move_banner_label:
		move_banner_label.text = "◆ %s ◆" % move_name.to_upper()
	
	# Apply rich styled panel box depending on move type
	var panel = $Control/MoveBanner/Panel as PanelContainer
	if panel:
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_right = 10
		style.corner_radius_bottom_left = 10
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		
		match move_type:
			"buff", "heal":
				style.bg_color = Color(0.05, 0.12, 0.22, 0.92)
				style.border_color = Color(0.2, 0.8, 1.0, 0.9)
				style.border_width_left = 2
				style.border_width_top = 2
				style.border_width_right = 2
				style.border_width_bottom = 2
				if move_banner_actor:
					move_banner_actor.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
			_:
				style.bg_color = Color(0.18, 0.05, 0.06, 0.92)
				style.border_color = Color(1.0, 0.3, 0.25, 0.9)
				style.border_width_left = 2
				style.border_width_top = 2
				style.border_width_right = 2
				style.border_width_bottom = 2
				if move_banner_actor:
					move_banner_actor.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		
		panel.add_theme_stylebox_override("panel", style)
	
	move_banner.visible = true
	move_banner.modulate.a = 0.0
	move_banner.scale = Vector2(0.9, 0.9)
	move_banner.pivot_offset = move_banner.size / 2.0
	
	_move_banner_tween = create_tween()
	_move_banner_tween.set_parallel(true)
	_move_banner_tween.set_ease(Tween.EaseType.EASE_OUT)
	_move_banner_tween.set_trans(Tween.TransitionType.TRANS_BACK)
	_move_banner_tween.tween_property(move_banner, "modulate:a", 1.0, 0.25)
	_move_banner_tween.tween_property(move_banner, "scale", Vector2(1.0, 1.0), 0.25)

func hide_move_announcement() -> void:
	if not move_banner or not move_banner.visible:
		return
	
	if _move_banner_tween and _move_banner_tween.is_running():
		_move_banner_tween.kill()
	
	_move_banner_tween = create_tween()
	_move_banner_tween.set_parallel(true)
	_move_banner_tween.set_ease(Tween.EaseType.EASE_IN)
	_move_banner_tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	_move_banner_tween.tween_property(move_banner, "modulate:a", 0.0, 0.2)
	_move_banner_tween.tween_property(move_banner, "scale", Vector2(0.9, 0.9), 0.2)
	_move_banner_tween.chain().tween_callback(func(): move_banner.visible = false)
