class_name CardIntegration
extends Node
## Integration script that ties the card combat system into the existing battle system
## This should be added to the BattleManager scene

var card_battle_manager: CardBattleManager
var card_ui: CardUI
var battle_manager: BattleManager

func _ready():
	print("CardIntegration _ready() called")
	
	# Find battle manager
	battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		push_error("CardIntegration: Could not find BattleManager")
		return
	
	print("BattleManager found in CardIntegration")
	
	# Create card battle manager
	card_battle_manager = CardBattleManager.new()
	add_child(card_battle_manager)
	print("CardBattleManager created and added")
	
	# Find CardUI in the HUD (it's now part of the BattleHUD scene)
	if battle_manager and battle_manager.hud:
		card_ui = battle_manager.hud.get_node_or_null("Control/CardUI")
		if card_ui:
			print("CardUI found in BattleHUD")
		else:
			print("CardUI not found in BattleHUD")
	else:
		print("Could not find CardUI - battle manager or HUD not available")
	
	# Connect signals through HUD
	if battle_manager and battle_manager.hud:
		battle_manager.hud.card_selected.connect(_on_card_selected)
		battle_manager.hud.end_turn_pressed.connect(_on_end_turn_pressed)
	
	# Connect to battle manager turn system
	if battle_manager:
		# We'll need to hook into the turn system
		# For now, this is a placeholder for integration
		pass
	
	print("Card integration initialized")

func get_deck_cards(deck_resources: Array[CardData] = []) -> Array[CardData]:
	if deck_resources.is_empty():
		print("No deck resources provided")
		return []
	
	print("Getting deck cards from provided resources: ", deck_resources.size())
	
	var deck_cards: Array[CardData] = []
	for card in deck_resources:
		if card:
			deck_cards.append(card)
			print("Added card to deck: ", card.name)
	
	print("Created deck with ", deck_cards.size(), " cards")
	return deck_cards

func initialize_for_player(player_battler: Battler, deck_resources: Array[CardData] = []):
	if not card_battle_manager or not player_battler:
		return
	
	var deck_cards = get_deck_cards(deck_resources)
	card_battle_manager.setup_card_combat(player_battler, deck_cards)
	print("Card combat initialized for player: ", player_battler.character_name)

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
	print("Card selected in UI: ", card.name)
	
	# Update back button visibility when card is selected
	if battle_manager and battle_manager.hud and battle_manager.hud.has_method("_update_back_button_visibility"):
		battle_manager.hud._update_back_button_visibility()
	
	# Use CardConfig if available, otherwise fall back to metadata
	var target_scope_enum: CardConfig.TargetScope
	var target_selection_mode: CardConfig.SelectionMode
	
	if card.has_card_config():
		target_scope_enum = card.card_config.target_type
		target_selection_mode = card.card_config.target_selection_mode
		print("Using CardConfig targeting: ", CardConfig.TargetScope.keys()[target_scope_enum])
	else:
		# Convert metadata string to enum (backward compatibility)
		var target_scope_string = card.metadata.get("target_scope", "single_enemy")
		target_scope_enum = _string_to_target_scope(target_scope_string)
		target_selection_mode = CardConfig.SelectionMode.MANUAL
		print("Using metadata targeting: ", target_scope_string)
	
	# Get targets based on card configuration
	var targets = get_targets_for_card(card, target_scope_enum, target_selection_mode)
	
	match target_scope_enum:
		CardConfig.TargetScope.SELF:
			# Execute immediately on self without targeting
			print("Self-targeting card, executing immediately")
			if card_battle_manager and card_battle_manager.current_player_battler:
				card_battle_manager.play_card(card, card_battle_manager.current_player_battler)
		
		CardConfig.TargetScope.SINGLE_ENEMY:
			# Single enemy targeting
			if targets.size() > 0:
				print("Single enemy targeting mode")
				start_targeting_mode(card, "enemy", targets)
			else:
				print("No enemies available for targeting")
		
		CardConfig.TargetScope.ALL_ENEMIES:
			# AOE on all enemies
			if targets.size() > 0:
				print("All enemies AOE mode")
				start_aoe_targeting_mode(card, targets, "enemy")
			else:
				print("No enemies available for AOE")
		
		CardConfig.TargetScope.SINGLE_ALLY:
			# Single ally targeting
			if targets.size() > 0:
				print("Single ally targeting mode")
				start_targeting_mode(card, "ally", targets)
			else:
				print("No allies available for targeting")
		
		CardConfig.TargetScope.ALL_ALLIES:
			# AOE on all allies
			if targets.size() > 0:
				print("All allies AOE mode")
				start_aoe_targeting_mode(card, targets, "ally")
			else:
				print("No allies available for AOE")
		
		CardConfig.TargetScope.ALL_ALLIES_SELF:
			# AOE on all allies including self
			if targets.size() > 0:
				print("All allies including self AOE mode")
				start_aoe_targeting_mode(card, targets, "ally")
			else:
				print("No allies available for AOE")
		
		CardConfig.TargetScope.SINGLE_TARGET:
			# Can target any single unit
			if targets.size() > 0:
				print("Single target mode (any unit)")
				start_targeting_mode(card, "any", targets)
			else:
				print("No targets available")
		
		CardConfig.TargetScope.ALL_UNITS:
			# AOE on all units
			if targets.size() > 0:
				print("All units AOE mode")
				start_aoe_targeting_mode(card, targets, "any")
			else:
				print("No targets available for AOE")
		
		_:
			# Fallback to existing behavior
			print("Unknown target scope, using fallback")
			var available_enemies = get_alive_enemies()
			if available_enemies.size() > 0:
				var target = available_enemies[0]
				card_battle_manager.play_card(card, target)
			else:
				print("No targets available")

## Convert string target scope to enum (backward compatibility)
func _string_to_target_scope(scope_string: String) -> CardConfig.TargetScope:
	match scope_string:
		"self":
			return CardConfig.TargetScope.SELF
		"single_enemy":
			return CardConfig.TargetScope.SINGLE_ENEMY
		"all_enemies":
			return CardConfig.TargetScope.ALL_ENEMIES
		"single_ally":
			return CardConfig.TargetScope.SINGLE_ALLY
		"all_allies":
			return CardConfig.TargetScope.ALL_ALLIES
		"all_allies_self":
			return CardConfig.TargetScope.ALL_ALLIES_SELF
		_:
			return CardConfig.TargetScope.SINGLE_ENEMY

## Get targets based on card configuration
func get_targets_for_card(card: CardData, target_scope: CardConfig.TargetScope, selection_mode: CardConfig.SelectionMode) -> Array:
	var available_enemies = get_alive_enemies()
	var available_allies = get_alive_allies()
	var actor = card_battle_manager.current_player_battler if card_battle_manager else null
	
	# If card has config, use its targeting system
	if card.has_card_config():
		return card.card_config.get_targets(actor, available_enemies, available_allies)
	
	# Otherwise, use the legacy system
	match target_scope:
		CardConfig.TargetScope.SELF:
			return [actor] if actor else []
		CardConfig.TargetScope.SINGLE_ENEMY:
			return available_enemies
		CardConfig.TargetScope.ALL_ENEMIES:
			return available_enemies
		CardConfig.TargetScope.SINGLE_ALLY:
			return available_allies
		CardConfig.TargetScope.ALL_ALLIES:
			return available_allies
		CardConfig.TargetScope.ALL_ALLIES_SELF:
			return available_allies
		CardConfig.TargetScope.SINGLE_TARGET:
			return available_enemies + available_allies
		CardConfig.TargetScope.ALL_UNITS:
			return available_enemies + available_allies
		_:
			return available_enemies

func start_targeting_mode(card: CardData, target_type: String = "enemy", provided_targets: Array = []):
	if not battle_manager:
		print("ERROR: No battle manager for targeting")
		return
	
	var available_targets = provided_targets
	if available_targets.is_empty():
		if target_type == "enemy":
			available_targets = get_alive_enemies()
		else:
			available_targets = get_alive_allies()
	
	print("=== STARTING TARGETING MODE ===")
	print("Target type: ", target_type)
	print("Available targets: ", available_targets.size())
	
	if available_targets.size() == 0:
		print("ERROR: No targets available for targeting")
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
	
	for target in available_targets:
		if target is Battler:
			target.is_valid_target = true
			target.is_selectable = true
			print("Made target selectable: ", target.character_name)
	
	battle_manager.set_meta("pending_card", card)
	
	# Update HUD: hide cards & action buttons, show cancel target button
	if battle_manager.hud and battle_manager.hud.has_method("set_targeting_mode"):
		battle_manager.hud.set_targeting_mode(true)
	
	print("Targeting mode started for card: ", card.name)
	print("Valid targets: ", battle_manager.valid_targets.size())
	print("Mouse input enabled: ", battle_manager.mouse_input_toggle)

func start_aoe_targeting_mode(card: CardData, targets: Array[Battler], target_type: String = "enemy"):
	if not battle_manager:
		print("ERROR: No battle manager for AOE targeting")
		return
	
	print("=== STARTING AOE TARGETING MODE ===")
	print("Target type: ", target_type)
	print("AOE targets: ", targets.size())
	
	if targets.size() == 0:
		print("ERROR: No targets available for AOE")
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
	
	print("AOE confirmation mode started for card: ", card.name)
	print("AOE will affect: ", targets.size(), " targets")

func _on_end_turn_pressed():
	print("End turn pressed")
	# Execute cards and then let battle manager handle turn advancement
	await card_battle_manager.end_player_turn()
	print("Card execution complete")
