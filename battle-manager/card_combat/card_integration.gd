class_name CardIntegration
extends Node
## Integration script that ties the card combat system into the existing battle system
## This should be added to the BattleManager scene

var card_battle_manager: CardBattleManager
var card_ui: CardUI
var battle_manager: BattleManager
var card_database: CardDatabase

# Sample deck composition (which cards to include in deck)
var deck_card_ids: Array[String] = ["strike", "fireball", "ice_shard", "thunder_strike", "heal", "poison", "berserk_rage"]

func _ready():
	print("CardIntegration _ready() called")
	
	# Load card database
	card_database = CardDatabase.new()
	print("CardDatabase loaded with ", card_database.cards.size(), " cards")
	print("Available card IDs: ", card_database.cards.keys())
	
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

func get_deck_cards() -> Array[CardData]:
	if not card_database:
		push_error("CardDatabase not loaded")
		return []
	
	print("Getting deck cards, looking for IDs: ", deck_card_ids)
	print("Database has cards: ", card_database.cards.keys())
	
	var deck_cards: Array[CardData] = []
	for card_id in deck_card_ids:
		var card = card_database.get_card(card_id)
		if card:
			deck_cards.append(card)
			print("Found card: ", card.name)
		else:
			print("Warning: Card not found in database: ", card_id)
	
	print("Created deck with ", deck_cards.size(), " cards")
	return deck_cards

func initialize_for_player(player_battler: Battler):
	if not card_battle_manager or not player_battler:
		return
	
	var deck_cards = get_deck_cards()
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
	
	# Get target scope from card metadata (default to single_enemy for backward compatibility)
	var target_scope = card.metadata.get("target_scope", "single_enemy")
	print("Card target scope: ", target_scope)
	
	match target_scope:
		"self":
			# Execute immediately on self without targeting
			print("Self-targeting card, executing immediately")
			if card_battle_manager and card_battle_manager.current_player_battler:
				card_battle_manager.play_card(card, card_battle_manager.current_player_battler)
		
		"single_enemy":
			# Existing enemy targeting flow
			var available_enemies = get_alive_enemies()
			if available_enemies.size() > 0:
				print("Single enemy targeting mode")
				start_targeting_mode(card, "enemy")
			else:
				print("No enemies available for targeting")
		
		"all_enemies":
			# AOE on all enemies - show overview camera, confirm execution
			var available_enemies = get_alive_enemies()
			if available_enemies.size() > 0:
				print("All enemies AOE mode")
				start_aoe_targeting_mode(card, available_enemies, "enemy")
			else:
				print("No enemies available for AOE")
		
		"single_ally":
			# Single ally targeting with target focus camera
			var available_allies = get_alive_allies()
			if available_allies.size() > 0:
				print("Single ally targeting mode")
				start_targeting_mode(card, "ally")
			else:
				print("No allies available for targeting")
		
		"all_allies":
			# AOE on all allies - show default camera, confirm execution
			var available_allies = get_alive_allies()
			if available_allies.size() > 0:
				print("All allies AOE mode")
				start_aoe_targeting_mode(card, available_allies, "ally")
			else:
				print("No allies available for AOE")
		
		"all_allies_self":
			# AOE on all allies including self - show default camera, confirm execution
			var available_allies = get_alive_allies()
			if available_allies.size() > 0:
				print("All allies including self AOE mode")
				start_aoe_targeting_mode(card, available_allies, "ally")
			else:
				print("No allies available for AOE")
		
		_:
			# Fallback to existing behavior for unknown scopes
			print("Unknown target scope: ", target_scope, ", using fallback")
			var available_enemies = get_alive_enemies()
			if available_enemies.size() > 0:
				var target = available_enemies[0]
				card_battle_manager.play_card(card, target)
			else:
				print("No targets available")

func start_targeting_mode(card: CardData, target_type: String = "enemy"):
	if not battle_manager:
		print("ERROR: No battle manager for targeting")
		return
	
	var available_targets = []
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
