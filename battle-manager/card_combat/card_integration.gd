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

func _on_card_selected(card: CardData):
	print("Card selected in UI: ", card.name)
	
	var available_enemies = get_alive_enemies()
	var card_type = card.metadata.get("card_type", "attack")
	
	if card_type == "attack" and battle_manager:
		print("Attack card selected, enemies available: ", available_enemies.size())
		if available_enemies.size() > 0:
			print("Entering targeting mode")
			start_targeting_mode(card)
		else:
			print("No enemies available for targeting")
	else:
		if available_enemies.size() > 0:
			var target = available_enemies[0]
			card_battle_manager.play_card(card, target)
		else:
			print("No enemies to target")

func start_targeting_mode(card: CardData):
	if not battle_manager:
		print("ERROR: No battle manager for targeting")
		return
	
	var available_enemies = get_alive_enemies()
	print("=== STARTING TARGETING MODE ===")
	print("Battle manager enemies: ", available_enemies.size())
	
	if available_enemies.size() == 0:
		print("ERROR: No enemies available for targeting")
		return
	
	if battle_manager.battle_camera:
		battle_manager.battle_camera.set_enemy_overview(available_enemies)
		
	battle_manager.mouse_input_toggle = true
	battle_manager.in_target_selection = true
	battle_manager.current_character = card_battle_manager.current_player_battler
	battle_manager.valid_targets = available_enemies
	
	for enemy in available_enemies:
		if enemy is Battler:
			enemy.is_valid_target = true
			enemy.is_selectable = true
			print("Made enemy selectable: ", enemy.character_name)
	
	battle_manager.set_meta("pending_card", card)
	
	# Update HUD: hide cards & action buttons, show cancel target button
	if battle_manager.hud and battle_manager.hud.has_method("set_targeting_mode"):
		battle_manager.hud.set_targeting_mode(true)
	
	print("Targeting mode started for card: ", card.name)
	print("Valid targets: ", battle_manager.valid_targets.size())
	print("Mouse input enabled: ", battle_manager.mouse_input_toggle)

func _on_end_turn_pressed():
	print("End turn pressed")
	# Execute cards and then let battle manager handle turn advancement
	await card_battle_manager.end_player_turn()
	print("Card execution complete")
