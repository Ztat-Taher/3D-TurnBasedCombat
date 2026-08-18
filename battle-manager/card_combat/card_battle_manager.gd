class_name CardBattleManager
extends Node
## Bridges the 3D battle system with the card combat addon
## Manages card-based combat for the player while enemies use AI attacks

signal card_played(card: CardData, target: Variant)
signal turn_ended()
signal ap_changed(current_ap: int, max_ap: int)
signal player_attacked(attacker: Battler, damage: int)

## Per-battler sessions and decks (keyed by Battler object)
var sessions_by_battler: Dictionary = {}  # Battler -> CombatSession
var decks_by_battler: Dictionary = {}     # Battler -> CombatDeck

var ap_system: APSystem

var battle_manager: BattleManager
var current_player_battler: Battler
var card_config: CardBattleConfig
var qte_manager: QTEManager

# Cards played this turn (to be executed when turn ends)
var queued_cards: Array = []

func _ready():
	# Add to group for easy access
	add_to_group("card_battle_manager")
	print("CardBattleManager added to group card_battle_manager")
	
	# Find the battle manager
	battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		push_error("CardBattleManager: Could not find BattleManager")
		return
	else:
		print("CardBattleManager found BattleManager")
	
	# Create AP system
	ap_system = APSystem.new()
	add_child(ap_system)
	
	# Create QTE manager
	qte_manager = QTEManager.new()
	add_child(qte_manager)
	
	# Load configuration
	card_config = load_card_config()
	if card_config:
		ap_system.setup(card_config.ap_per_turn, card_config.max_ap)
		ap_system.ap_changed.connect(_on_ap_changed)

func load_card_config() -> CardBattleConfig:
	# Try to load from project settings or create default
	var config_path = "res://battle-manager/card_combat/card_battle_config.tres"
	if ResourceLoader.exists(config_path):
		return load(config_path)
	
	# Create default config if none exists
	var default_config = CardBattleConfig.new()
	return default_config

## Sets up an independent CombatSession and CombatDeck for one ally battler.
## Call this once per ally during battle initialisation.
func setup_card_combat(player_battler: Battler, card_data_resources: Array[CardData]) -> void:
	if not player_battler:
		return
	
	# Create combat session with player as side 0
	var player_combatant = Combatant.new()
	player_combatant.max_health = player_battler.max_health
	player_combatant.current_health = player_battler.current_health
	
	# Create a dummy enemy combatant for side 1 (enemies use AI, not cards)
	var enemy_combatant = Combatant.new()
	enemy_combatant.max_health = 100
	enemy_combatant.current_health = 100
	
	var session = CombatSession.new()
	session.config = create_combat_config()
	session.setup_sides([
		{"hero": player_combatant, "cards": card_data_resources},
		{"hero": enemy_combatant, "cards": []}
	], [0, 1])
	
	# Store by battler reference
	sessions_by_battler[player_battler] = session
	var deck = session.decks[0]
	decks_by_battler[player_battler] = deck
	
	# Connect deck signals
	if not deck.card_played.is_connected(_on_card_played):
		deck.card_played.connect(_on_card_played)
	if not deck.mana_changed.is_connected(_on_mana_changed):
		deck.mana_changed.connect(_on_mana_changed)
	
	print("Card combat setup complete for player: ", player_battler.character_name)

func create_combat_config() -> CombatConfig:
	var config = CombatConfig.new()
	if card_config:
		config.initial_hand_size = card_config.initial_hand_size
		config.max_hand_size = card_config.max_hand_size
		config.max_board_size = card_config.max_board_size
	return config

## Returns the current player's active deck. Null if not set up.
func _get_current_deck() -> CombatDeck:
	if current_player_battler and decks_by_battler.has(current_player_battler):
		return decks_by_battler[current_player_battler]
	return null

func get_hand() -> Array[CardData]:
	var deck = _get_current_deck()
	if deck:
		return deck.get_hand()
	return []

func can_play_card(card: CardData) -> bool:
	if not _get_current_deck():
		print("Cannot play card: No player deck")
		return false
	
	# Use our own AP system for cost validation
	var ap_can_spend = ap_system.can_spend_ap(card.cost)
	print("AP can spend: ", ap_can_spend, " (card cost: ", card.cost, ")")
	
	var ap_info = get_ap_info()
	print("Current AP: ", ap_info.get("current_ap", 0), " / ", ap_info.get("max_ap", 0))
	
	return ap_can_spend

var is_executing_card: bool = false

func play_card(card: CardData, target: Battler = null) -> bool:
	if is_executing_card or not can_play_card(card):
		print("Cannot play card: ", card.name, " (is_executing: ", is_executing_card, ")")
		return false
	
	is_executing_card = true
	if battle_manager:
		battle_manager.is_animating = true
		if battle_manager.hud:
			battle_manager.hud.hide_action_buttons()
	
	print("=== PLAYING CARD ===")
	print("Card: ", card.name)
	print("Target: ", target.character_name if target else "None")
	print("Battle manager enemies before play: ", battle_manager.enemies.size() if battle_manager else "No battle manager")
	
	# Camera choreography: wider view for player attack cards only
	var card_type = card.metadata.get("card_type", "attack")
	if (card_type == "attack" or card_type == "skill") and battle_manager and battle_manager.battle_camera:
		battle_manager.battle_camera.set_default_camera()
	
	# Execute card effect first (attack animation, damage, heal, defense)
	await execute_card_effect(card, target)
	
	# Spend AP and discard card systematically only AFTER effect resolves
	ap_system.spend_ap(card.cost)
	
	# Remove from hand (move to graveyard through deck system without mana restriction)
	var deck = _get_current_deck()
	if deck:
		deck.discard_card(card)
	
	# Restore over-the-shoulder camera on the acting player after attack finishes
	if (card_type == "attack" or card_type == "skill") and battle_manager and battle_manager.battle_camera and is_instance_valid(current_player_battler):
		battle_manager.battle_camera.set_over_the_shoulder(current_player_battler)
	
	is_executing_card = false
	if battle_manager:
		battle_manager.is_animating = false
		if battle_manager.hud and is_instance_valid(current_player_battler):
			if battle_manager.hud.card_ui:
				battle_manager.hud.card_ui.visible = true
			battle_manager.hud.show_action_buttons(current_player_battler)
	
	print("Card executed: ", card.name, " targeting: ", target.character_name if target else "None")
	print("Battle manager enemies after play: ", battle_manager.enemies.size() if battle_manager else "No battle manager")
	card_played.emit(card, target)
	
	return true

func execute_queued_cards() -> void:
	print("Executing ", queued_cards.size(), " queued cards")
	
	for card_action in queued_cards:
		var card: CardData = card_action["card"]
		var target: Battler = card_action["target"]
		await execute_card_effect(card, target)
	
	# Clear queued cards
	queued_cards.clear()
	
	# End turn
	turn_ended.emit()

func execute_card_effect(card: CardData, target: Battler) -> void:
	print("Executing card effect: ", card.name)
	
	if not target:
		print("No target for card: ", card.name)
		return
	
	if not current_player_battler:
		print("No player battler for card execution")
		return
	
	# Apply state effects BEFORE execution (to avoid target being freed)
	apply_card_states(card, target)
	
	# Handle different card types based on metadata
	var card_type = card.metadata.get("card_type", "attack")
	var target_scope = card.metadata.get("target_scope", "single_enemy")
	
	# Skip camera setup for AOE cards (camera is set by integration layer)
	var is_aoe = target_scope in ["all_enemies", "all_allies", "all_allies_self"]
	
	match card_type:
		"attack":
			await execute_attack_card(card, target, is_aoe)
		"skill":
			await execute_skill_card(card, target, is_aoe)
		"defense":
			execute_defense_card(card)
		"heal":
			execute_heal_card(card, target, is_aoe)
		"buff":
			execute_buff_card(card, target, is_aoe)
		"debuff":
			await execute_debuff_card(card, target, is_aoe)
		_:
			print("Unknown card type: ", card_type)

func execute_attack_card(card: CardData, target: Battler, is_aoe: bool = false) -> void:
	print("Executing attack card: ", card.name, " AOE: ", is_aoe)
	
	if not current_player_battler or not target:
		print("Missing player battler or target for attack card")
		return
	
	# Calculate damage based on card stats and battler stats
	var base_damage = card.attack
	var attacker_stat = current_player_battler.attack if current_player_battler else 0
	var total_damage = base_damage + attacker_stat
	
	# Apply config multiplier if available
	if card_config:
		total_damage = int(total_damage * card_config.attack_damage_multiplier)
	
	# For AOE, skip movement animation - just play attack animation from current position
	if not is_aoe:
		# Move to target and attack
		await current_player_battler.turn_to_face_target(target)
		
		if current_player_battler.advance_to_target(target):
			current_player_battler._try_animation("walk")
			while current_player_battler.is_advancing:
				await get_tree().create_timer(0.016).timeout
		
		await current_player_battler.turn_to_face_target(target)
	
	# Play attack animation
	current_player_battler._try_animation("attack")
	
	# Simple QTE system: start QTE, get result, apply damage with multiplier
	var damage_multiplier = 1.0
	
	if qte_manager and qte_manager.start_card_qte(card):
		var qte_success = await await_qte_completion()
		print("QTE result: ", qte_success)
		damage_multiplier = qte_manager.get_damage_multiplier("CARD_ATTACK", qte_success)
		print("Damage multiplier: ", damage_multiplier)
	else:
		print("No QTE for this card or QTE disabled")
	
	# Wait for attack animation to reach hit point
	await get_tree().create_timer(0.5).timeout
	
	# Apply damage with the calculated multiplier
	var final_damage = int(total_damage * damage_multiplier)
	print("Final damage to apply: ", final_damage)
	
	# Trigger AOE effect if applicable
	if is_aoe and battle_manager and battle_manager.effect_manager:
		battle_manager.effect_manager.trigger_aoe_attack()
	
	if battle_manager:
		await battle_manager.damage_calculation(current_player_battler, target, final_damage)
	
	# Wait for attack animation to complete
	await get_tree().create_timer(0.5).timeout
	
	# Return to position (only for single target)
	if not is_aoe:
		print("Returning to original position: ", current_player_battler.original_position)
		current_player_battler.return_to_original_position()
		if current_player_battler.is_advancing:
			while current_player_battler.is_advancing:
				await get_tree().create_timer(0.1).timeout
	
	current_player_battler.battle_idle()
	print("Attack execution complete")

func execute_skill_card(card: CardData, target: Battler, is_aoe: bool = false) -> void:
	print("Executing skill card: ", card.name, " AOE: ", is_aoe)
	await execute_attack_card(card, target, is_aoe)

func execute_defense_card(card: CardData) -> void:
	print("Executing defense card: ", card.name)
	current_player_battler.defend()
	if card.metadata.has("defense_boost"):
		var boost = card.metadata["defense_boost"]
		print("Defense boost: ", boost)

func execute_heal_card(card: CardData, target: Battler, is_aoe: bool = false) -> void:
	print("Executing heal card: ", card.name, " AOE: ", is_aoe)
	var heal_amount = card.health
	target.take_healing(heal_amount)
	
	if battle_manager and battle_manager.hud:
		battle_manager.hud.update_health_bars()

func execute_buff_card(card: CardData, target: Battler, is_aoe: bool = false) -> void:
	print("Executing buff card: ", card.name, " AOE: ", is_aoe)
	# Handle buff effects like damage multipliers, speed boosts, etc.
	if card.metadata.has("damage_multiplier"):
		var multiplier = card.metadata["damage_multiplier"]
		print("Applying damage multiplier: ", multiplier)
		# This would need a buff system integration
	
	if card.metadata.has("speed_multiplier"):
		var multiplier = card.metadata["speed_multiplier"]
		print("Applying speed multiplier: ", multiplier)
		# This would need a buff system integration
	
	if card.metadata.has("damage_reduction"):
		var reduction = card.metadata["damage_reduction"]
		print("Applying damage reduction: ", reduction)
		# This would need a buff system integration

func execute_debuff_card(card: CardData, target: Battler, is_aoe: bool = false) -> void:
	print("Executing debuff card: ", card.name, " AOE: ", is_aoe)
	# Deal initial damage
	if card.attack > 0:
		await execute_attack_card(card, target, is_aoe)
	
func apply_card_states(card: CardData, target: Battler) -> void:
	if not card.metadata.has("applies_state"):
		return
	
	var state_name = card.metadata["applies_state"]
	var state_chance = card.metadata.get("state_chance", 1.0)
	var state_duration = card.metadata.get("state_duration", 0)
	
	print("Applying state: ", state_name, " with chance: ", state_chance)
	
	# Check if state should be applied
	if randf() > state_chance:
		print("State application failed (chance check)")
		return
	
	# Apply the state to the target
	print("State applied: ", state_name, " for ", state_duration, " turns")
	# This would need integration with the existing state system
	# For now, just log the application

func draw_card_for_deck(deck: CombatDeck) -> CardData:
	if not deck:
		return null
	# If draw pile is empty, recycle graveyard back into draw pile and shuffle
	if deck._draw_pile.is_empty() and not deck._graveyard.is_empty():
		deck._draw_pile.append_array(deck._graveyard)
		deck._graveyard.clear()
		deck.shuffle()
	return deck.draw_card()

func start_player_turn() -> void:
	print("Starting player turn")
	
	# Always sync to the currently acting player from battle_manager
	if battle_manager and is_instance_valid(battle_manager.current_character):
		current_player_battler = battle_manager.current_character
		print("Player turn for: ", current_player_battler.character_name)
	
	# Refresh AP
	ap_system.regen_ap()
	
	# Refresh hand: discard remaining cards, draw a fresh hand
	var deck = _get_current_deck()
	if deck:
		# Discard whatever is left in hand from the previous turn
		var old_hand = deck.get_hand().duplicate()
		for card in old_hand:
			deck.discard_card(card)
		
		# Draw a fresh hand up to initial_hand_size
		var hand_size = card_config.initial_hand_size if card_config else 3
		for i in range(hand_size):
			draw_card_for_deck(deck)
		
		print("Hand refreshed for ", current_player_battler.character_name, ": ", deck.get_hand().size(), " cards")
	
	# Clear queued cards from previous turn
	queued_cards.clear()
	
	# Update CardUI display for the new hand and notify HUD
	if battle_manager and battle_manager.hud:
		var card_ui = battle_manager.hud.get_node_or_null("Control/CardUI")
		if card_ui:
			card_ui.visible = true
			if card_ui.has_method("update_hand_display"):
				card_ui.update_hand_display()
		if battle_manager.hud.has_method("update_party_status"):
			var ap_info = get_ap_info()
			battle_manager.hud.last_ap_by_battler[current_player_battler] = {
				"current": ap_info.get("current_ap", 3),
				"max": ap_info.get("max_ap", 3)
			}
			battle_manager.hud.set_activebattler(current_player_battler)

func end_player_turn() -> void:
	print("Ending player turn")
	# If a card is currently playing out, wait for it to finish first
	while is_executing_card:
		await get_tree().process_frame
	
	# Execute all queued cards
	if not queued_cards.is_empty():
		await execute_queued_cards()
	
	turn_ended.emit()
	if battle_manager:
		battle_manager.end_turn()

func _on_card_played(_card_instance: CardInstance) -> void:
	print("Card played in deck system")
	# Card is already handled in play_card()

func _on_mana_changed(new_mana: int) -> void:
	# Mana in card system maps to our AP system
	print("Deck mana changed: ", new_mana)

func _on_ap_changed(current_ap: int, max_ap: int) -> void:
	# Forward AP changes to UI
	ap_changed.emit(current_ap, max_ap)

func get_ap_info() -> Dictionary:
	if ap_system:
		return {
			"current_ap": ap_system.get_current_ap(),
			"max_ap": ap_system.get_max_ap(),
			"ap_percentage": ap_system.get_ap_percentage()
		}
	return {}

func await_qte_completion() -> bool:
	# Helper function to wait for QTE completion with robust safety mechanisms
	var state = {"completed": false, "success": false}
	
	if qte_manager:
		# Use a single handler that catches both success and failure
		var completion_handler = func(s: bool, _type = ""):
			state["completed"] = true
			state["success"] = s
			print("QTE completion handler called with success: ", s)
		
		if not qte_manager.qte_completed.is_connected(completion_handler):
			qte_manager.qte_completed.connect(completion_handler)
		
		var timeout = 5.0 # 5 seconds max safety guard
		var start_time = Time.get_ticks_msec() / 1000.0
		
		# Wait for completion or timeout
		while not state["completed"]:
			var elapsed = (Time.get_ticks_msec() / 1000.0) - start_time
			if elapsed > timeout:
				print("WARNING: QTE completion timed out after ", timeout, " seconds")
				state["completed"] = true
				state["success"] = false # Default to failure on timeout
				# Force cancel the QTE if it's still active
				if qte_manager.is_active():
					qte_manager.cancel_qte()
				break
			await get_tree().process_frame
		
		if qte_manager.qte_completed.is_connected(completion_handler):
			qte_manager.qte_completed.disconnect(completion_handler)
	
	print("QTE final result: ", state["success"])
	return state["success"]

func trigger_reactive_defense(attacker: Battler, damage: int, defender: Battler = null) -> int:
	var target_defender = defender if defender else current_player_battler
	if not target_defender or not qte_manager or not card_config:
		return damage
	
	if not card_config.reactive_defense_enabled:
		return damage
	
	print("Triggering reactive defense window for defender: ", target_defender.character_name)
	player_attacked.emit(attacker, damage)
	
	var outcome = await qte_manager.await_reactive_defense(target_defender)
	var hud = battle_manager.hud if battle_manager else null
	
	match outcome:
		"perfect_parry":
			print("PERFECT PARRY by %s against %s! Triggering counterattack." % [target_defender.character_name, attacker.character_name])
			if hud and hud.battle_text_display:
				hud.battle_text_display.show_perfect_parry(target_defender)
			
			# Trigger perfect parry effect
			if battle_manager and battle_manager.effect_manager:
				battle_manager.effect_manager.trigger_perfect_parry()
			
			# Execute counterattack from defender to attacker
			await _execute_perfect_parry_counter(target_defender, attacker)
			return 0 # Complete damage avoidance on defender
			
		"dodge":
			print("DODGE by %s! No damage taken." % target_defender.character_name)
			if hud and hud.battle_text_display:
				hud.battle_text_display.show_dodge(target_defender)
			
			# Trigger dodge effect
			if battle_manager and battle_manager.effect_manager:
				battle_manager.effect_manager.trigger_dodge()
			
			return 0 # Complete damage avoidance
			
		"parry":
			var reduction = card_config.parry_damage_reduction
			var reduced_damage = int(damage * (1.0 - reduction))
			var amount_reduced = damage - reduced_damage
			print("PARRY by %s! Damage reduced from %d to %d" % [target_defender.character_name, damage, reduced_damage])
			if hud and hud.battle_text_display:
				hud.battle_text_display.show_parry(target_defender, amount_reduced)
			
			# Trigger block/parry effect
			if battle_manager and battle_manager.effect_manager:
				battle_manager.effect_manager.trigger_block()
			
			return reduced_damage
			
		_:
			print("Reactive defense missed or timed out. Full damage: ", damage)
			return damage

## Executes a counterattack animation & damage from defender to attacker on Perfect Parry
func _execute_perfect_parry_counter(defender: Battler, attacker: Battler) -> void:
	if not is_instance_valid(defender) or not is_instance_valid(attacker):
		return
	
	print("[Counterattack] %s counterattacks %s!" % [defender.character_name, attacker.character_name])
	
	# Stun the attacker momentarily so they don't return before taking counter damage
	attacker.is_counter_stunned = true
	
	# Face each other
	await defender.turn_to_face_target(attacker)
	
	# Play attack animation on defender
	var attack_anim_name = "basic_attacks/attack"
	if not defender._try_animation(attack_anim_name):
		defender._try_animation("attack")
	
	# Wait for defender's contact frame (hit_moment)
	await defender.hit_moment
	
	# Calculate counter damage
	var multiplier = 1.5
	if qte_manager and qte_manager.qte_config:
		multiplier = qte_manager.qte_config.counter_damage_multiplier
	
	var base_counter_dmg = int(defender.attack * multiplier)
	var final_counter_dmg = Formulas.physical_damage(defender, attacker, max(1, base_counter_dmg))
	
	# Apply damage to attacker
	await attacker.take_damage(final_counter_dmg, defender)
	
	if battle_manager and battle_manager.hud:
		battle_manager.hud.update_health_bars()
		if battle_manager.hud.battle_text_display:
			battle_manager.hud.battle_text_display.show_counter(defender, attacker, final_counter_dmg)
	
	# Check if attacker was defeated by counter attack
	if attacker.is_defeated():
		print("[Counterattack] Attacker %s was defeated by counter attack!" % attacker.character_name)
		# Clean up defeated enemy
		if battle_manager:
			battle_manager._cleanup_defeated_from_turn_order()
			battle_manager._cleanup_defeated_enemies()
	
	# Allow defender to finish swing and return to idle
	await get_tree().create_timer(0.3).timeout
	defender.battle_idle()
