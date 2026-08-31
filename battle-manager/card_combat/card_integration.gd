class_name CardIntegration
extends Node
## Integration script that ties the card combat system into the existing battle system
## This should be added to the BattleManager scene

var card_battle_manager: CardBattleManager
var card_ui: CardUI
var battle_manager: BattleManager

func _ready():
	# Find battle manager
	battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		push_error("CardIntegration: Could not find BattleManager")
		return
	
	# Create card battle manager
	card_battle_manager = CardBattleManager.new()
	add_child(card_battle_manager)
	
	# Find CardUI in the HUD (it's now part of the BattleHUD scene)
	if battle_manager and battle_manager.hud:
		card_ui = battle_manager.hud.get_node_or_null("Control/CardUI")
	
	# Connect signals through HUD
	if battle_manager and battle_manager.hud:
		battle_manager.hud.card_selected.connect(_on_card_selected)
		battle_manager.hud.end_turn_pressed.connect(_on_end_turn_pressed)
	
	# Connect to battle manager turn system
	if battle_manager:
		# We'll need to hook into the turn system
		# For now, this is a placeholder for integration
		pass

func get_deck_cards(deck_resources: Array[CardData] = []) -> Array[CardData]:
	if deck_resources.is_empty():
		return []
	
	var deck_cards: Array[CardData] = []
	for card in deck_resources:
		if card:
			deck_cards.append(card)
	
	return deck_cards

func initialize_for_player(player_battler: Battler, deck_resources: Array[CardData] = []):
	if not card_battle_manager or not player_battler:
		return
	
	# If no deck resources provided, load from default player deck
	if deck_resources.is_empty():
		var deck_path = "res://database/decks/player_deck.tres"
		if ResourceLoader.exists(deck_path):
			var deck_resource = load(deck_path)
			if deck_resource:
				# Try to get cards from the deck resource
				if deck_resource.get("cards") != null:
					deck_resources = deck_resource.cards
					var deck_name = deck_resource.get("deck_name")
					if deck_name == null:
						deck_name = "Unknown Deck"
				else:
					pass
			else:
				pass
		else:
			pass
	
	var deck_cards = get_deck_cards(deck_resources)
	card_battle_manager.setup_card_combat(player_battler, deck_cards)

func get_alive_enemies() -> Array[Battler]:
	var alive: Array[Battler] = []
	if battle_manager:
		for enemy in battle_manager.enemies:
			if is_instance_valid(enemy) and enemy is Battler and not enemy.is_defeated():
				alive.append(enemy)
		
		if alive.is_empty():
			for node in get_tree().get_nodes_in_group("enemies"):
				if node is Battler and is_instance_valid(node) and not node.is_defeated():
					alive.append(node as Battler)
					if not battle_manager.enemies.has(node):
						battle_manager.enemies.append(node as Battler)
	return alive

func get_alive_allies() -> Array[Battler]:
	var alive: Array[Battler] = []
	if battle_manager:
		for player in battle_manager.players:
			if is_instance_valid(player) and player is Battler and not player.is_defeated():
				alive.append(player)
	return alive

func _on_card_selected(card: CardData):
	# Update back button visibility when card is selected
	if battle_manager and battle_manager.hud and battle_manager.hud.has_method("_update_back_button_visibility"):
		battle_manager.hud._update_back_button_visibility()
	
	# Use CardConfig system (primary system)
	if not card.has_card_config():
		push_error("Card '%s' does not have a CardConfig assigned. All cards must use the CardConfig system." % card.name)
		return
	
	var target_scope_enum = card.card_config.target_type
	var target_selection_mode = card.card_config.target_selection_mode
	
	# Get targets based on card configuration
	var targets = get_targets_for_card(card, target_scope_enum, target_selection_mode)
	
	match target_scope_enum:
		CardConfig.TargetScope.SELF:
			# Execute immediately on self without targeting
			if card_battle_manager and card_battle_manager.current_player_battler:
				card_battle_manager.play_card(card, card_battle_manager.current_player_battler)
		
		CardConfig.TargetScope.SINGLE_ENEMY:
			# Single enemy targeting
			if targets.size() > 0:
				start_targeting_mode(card, "enemy", targets)
		
		CardConfig.TargetScope.ALL_ENEMIES:
			# AOE on all enemies
			if targets.size() > 0:
				start_aoe_targeting_mode(card, targets, "enemy")
		
		CardConfig.TargetScope.SINGLE_ALLY:
			# Single ally targeting
			if targets.size() > 0:
				start_targeting_mode(card, "ally", targets)
		
		CardConfig.TargetScope.ALL_ALLIES:
			# AOE on all allies
			if targets.size() > 0:
				start_aoe_targeting_mode(card, targets, "ally")
		
		CardConfig.TargetScope.ALL_ALLIES_SELF:
			# AOE on all allies including self
			if targets.size() > 0:
				start_aoe_targeting_mode(card, targets, "ally")
		
		CardConfig.TargetScope.SINGLE_TARGET:
			# Can target any single unit
			if targets.size() > 0:
				start_targeting_mode(card, "any", targets)
		
		CardConfig.TargetScope.ALL_UNITS:
			# AOE on all units
			if targets.size() > 0:
				start_aoe_targeting_mode(card, targets, "any")
		
		_:
			# Fallback to existing behavior
			var available_enemies = get_alive_enemies()
			if available_enemies.size() > 0:
				var target = available_enemies[0]
				card_battle_manager.play_card(card, target)

## Get targets based on card configuration
func get_targets_for_card(card: CardData, target_scope: CardConfig.TargetScope, selection_mode: CardConfig.SelectionMode) -> Array:
	var available_enemies = get_alive_enemies()
	var available_allies = get_alive_allies()
	var actor = card_battle_manager.current_player_battler if card_battle_manager else null
	
	# Use CardConfig targeting system
	if not card.has_card_config():
		push_error("Card '%s' does not have a CardConfig assigned." % card.name)
		return []
	
	return card.card_config.get_targets(actor, available_enemies, available_allies)

func start_targeting_mode(card: CardData, target_type: String = "enemy", provided_targets: Array = []):
	if not battle_manager:
		return
	
	var available_targets = provided_targets
	if available_targets.is_empty():
		if target_type == "enemy":
			available_targets = get_alive_enemies()
		else:
			available_targets = get_alive_allies()
	
	if available_targets.size() == 0:
		return
	
	# Set camera based on target type
	if battle_manager.battle_camera:
		if target_type == "enemy":
			battle_manager.battle_camera.set_enemy_overview(available_targets)
		else:
			# For ally targeting, we'll use target focus when a specific ally is selected
			# Start with default camera until ally is selected
			battle_manager.battle_camera.set_default_camera()
	
	battle_manager.mouse_input_toggle = true
	battle_manager.in_target_selection = true
	battle_manager.current_character = card_battle_manager.current_player_battler
	battle_manager.valid_targets = available_targets
	battle_manager.set_meta("target_type", target_type)  # Track target type
	battle_manager.current_target_type = target_type  # Sync target type to battle manager variable
	
	# Reset keyboard target index for cycling
	battle_manager.keyboard_target_index = 0
	battle_manager.current_target = null
	battle_manager.current_controller_target = null
	battle_manager.current_default_selector = null
	
	# Clear all targets first to avoid conflicts
	for battler in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("players"):
		if battler is Battler:
			battler.deselect_as_target()
			battler.is_valid_target = false
			battler.is_selectable = false
			battler.is_targeted = false
	
	if available_targets.size() > 0:
		battle_manager.current_controller_target = available_targets[0]
		battle_manager.current_default_selector = available_targets[0]
		battle_manager.current_controller_target.set_as_keyboard_target()
	
	for target in available_targets:
		if target is Battler:
			target.is_valid_target = true
			target.is_selectable = true
	
	battle_manager.set_meta("pending_card", card)
	
	# Update HUD: hide cards & action buttons, show cancel target button
	if battle_manager.hud and battle_manager.hud.has_method("set_targeting_mode"):
		battle_manager.hud.set_targeting_mode(true)

func start_aoe_targeting_mode(card: CardData, targets: Array[Battler], target_type: String = "enemy"):
	if not battle_manager:
		return
	
	if targets.size() == 0:
		return
	
	# Set camera based on target type
	if battle_manager.battle_camera:
		if target_type == "enemy":
			battle_manager.battle_camera.set_enemy_overview(targets)
		else:
			# For ally AOE, use default camera showing all entities
			battle_manager.battle_camera.set_default_camera()
	
	# Store AOE targets for execution
	battle_manager.set_meta("aoe_targets", targets)
	battle_manager.set_meta("pending_card", card)
	battle_manager.set_meta("target_type", target_type)
	battle_manager.set_meta("is_aoe_mode", true)
	
	# Update HUD: show confirm button, hide individual targeting
	if battle_manager.hud and battle_manager.hud.has_method("set_aoe_confirmation_mode"):
		battle_manager.hud.set_aoe_confirmation_mode(true, card.name, targets.size())

func _on_end_turn_pressed():
	# Execute cards and then let battle manager handle turn advancement
	await card_battle_manager.end_player_turn()
