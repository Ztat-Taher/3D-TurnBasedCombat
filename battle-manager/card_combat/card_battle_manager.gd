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
	
	# Use card config if available, otherwise fall back to metadata
	if card.has_card_config():
		await execute_card_with_config(card, target)
	else:
		# Handle different card types based on metadata (backward compatibility)
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

## Execute card using the new CardConfig system
func execute_card_with_config(card: CardData, target: Battler) -> void:
	var card_config = card.card_config
	if not card_config:
		push_error("Card has_card_config() returned true but card_config is null")
		return
	
	print("Executing card with config: ", card.name)
	
	# Build execution context
	var context = {
		"card_data": card,
		"card_config": card_config,
		"actor": current_player_battler,
		"target": target,
		"enemies": battle_manager.enemies if battle_manager else [],
		"allies": battle_manager.allies if battle_manager else [],
		"effect_manager": battle_manager.effect_manager if battle_manager else null,
		"qte_manager": qte_manager,
		"camera": battle_manager.battle_camera if battle_manager else null,
		"parent_node": self
	}
	
	# Phase 1: Animation Phase
	await execute_animation_phase(card_config, context)
	
	# Phase 2: QTE Phase
	if card_config.should_trigger_qte():
		await execute_qte_phase(card_config, context)
	
	# Phase 3: Effect Phase
	await execute_effect_phase(card_config, context)
	
	# Phase 4: VFX Phase
	execute_vfx_phase(card_config, context)
	
	# Phase 5: Camera Phase
	execute_camera_phase(card_config, context)
	
	# Phase 6: Screen Phase
	execute_screen_phase(card_config, context)
	
	# Phase 7: Audio Phase
	execute_audio_phase(card_config, context)
	
	print("Card execution with config complete: ", card.name)

## Execute animation phase
func execute_animation_phase(card_config: CardConfig, context: Dictionary) -> void:
	var actor = context["actor"]
	if not actor:
		return
	
	var animation_name = card_config.actor_animation
	if animation_name.is_empty():
		animation_name = card_config.fallback_animation
	
	if not animation_name.is_empty():
		# Resolve animation name through character's animation mapping if available
		if actor.has_method("get_resolved_animation"):
			animation_name = actor.get_resolved_animation(animation_name)
		
		# Apply animation settings
		if actor.has_method("_try_animation"):
			actor._try_animation(animation_name)
			
			# Handle animation events
			if not card_config.animation_events.is_empty():
				await process_animation_events(card_config, context)
	else:
		print("No animation specified for card")

## Process animation events
func process_animation_events(card_config: CardConfig, context: Dictionary) -> void:
	var actor = context["actor"]
	if not actor or not actor.has_method("_get_animation_duration"):
		return
	
	# Resolve animation name through character's animation mapping if available
	var animation_name = card_config.actor_animation
	if actor.has_method("get_resolved_animation"):
		animation_name = actor.get_resolved_animation(animation_name)
	
	var animation_duration = actor._get_animation_duration(animation_name)
	var animation_time = 0.0
	
	while animation_time < animation_duration:
		var animation_progress = animation_time / animation_duration
		
		# Check each animation event
		for event in card_config.animation_events:
			if event.should_trigger(animation_progress, animation_duration):
				if event.check_condition(actor, context["target"]):
					var event_result = event.execute(actor, context["target"], context)
					print("Animation event executed: ", event.get_description(), " Result: ", event_result)
		
		await get_tree().process_frame
		animation_time += get_process_delta_time()

## Execute QTE phase
func execute_qte_phase(card_config: CardConfig, context: Dictionary) -> void:
	var qte_manager = context["qte_manager"]
	if not qte_manager:
		return
	
	match card_config.qte_type:
		CardConfig.QTEType.TIMING:
			await execute_timing_qte(card_config, context)
		CardConfig.QTEType.BUTTON_MASH:
			await execute_button_mash_qte(card_config, context)
		CardConfig.QTEType.SEQUENCE:
			await execute_sequence_qte(card_config, context)
		_:
			print("No QTE to execute")

## Execute timing-based QTE
func execute_timing_qte(card_config: CardConfig, context: Dictionary) -> void:
	var qte_manager = context["qte_manager"]
	if not qte_manager.has_method("start_qte"):
		return
	
	var difficulty = card_config.qte_difficulty
	var time_limit = card_config.qte_window_duration
	
	var qte_started = qte_manager.start_qte(QTEManager.QTEType.CARD_ATTACK, difficulty)
	if qte_started:
		var qte_success = await await_qte_completion()
		var multiplier = card_config.qte_success_multiplier if qte_success else card_config.qte_failure_multiplier
		context["qte_multiplier"] = multiplier
		print("Timing QTE result: ", qte_success, " Multiplier: ", multiplier)

## Execute button mash QTE
func execute_button_mash_qte(card_config: CardConfig, context: Dictionary) -> void:
	var required_presses = card_config.qte_mash_count
	var time_window = card_config.qte_window_duration
	var current_presses = 0
	var start_time = Time.get_ticks_msec() / 1000.0
	
	print("Button mash QTE: Press ", required_presses, " times in ", time_window, " seconds")
	
	while current_presses < required_presses:
		var elapsed = (Time.get_ticks_msec() / 1000.0) - start_time
		if elapsed >= time_window:
			print("Button mash QTE failed - time expired")
			context["qte_multiplier"] = card_config.qte_failure_multiplier
			return
		
		# Check for button press (would need input system integration)
		if Input.is_action_just_pressed("ui_accept"):
			current_presses += 1
			print("Button mash progress: ", current_presses, "/", required_presses)
		
		await get_tree().process_frame
	
	print("Button mash QTE succeeded!")
	context["qte_multiplier"] = card_config.qte_success_multiplier

## Execute sequence QTE
func execute_sequence_qte(card_config: CardConfig, context: Dictionary) -> void:
	var sequence = card_config.qte_sequence
	if sequence.is_empty():
		return
	
	var time_window = card_config.qte_window_duration
	var current_index = 0
	var start_time = Time.get_ticks_msec() / 1000.0
	
	print("Sequence QTE: Input sequence: ", sequence)
	
	while current_index < sequence.size():
		var elapsed = (Time.get_ticks_msec() / 1000.0) - start_time
		if elapsed >= time_window:
			print("Sequence QTE failed - time expired")
			context["qte_multiplier"] = card_config.qte_failure_multiplier
			return
		
		var required_button = sequence[current_index]
		
		# Check for correct button input (would need input system integration)
		if Input.is_action_just_pressed(required_button):
			current_index += 1
			print("Sequence progress: ", current_index, "/", sequence.size())
		elif Input.is_action_just_pressed("ui_accept"):
			print("Sequence QTE failed - wrong button")
			context["qte_multiplier"] = card_config.qte_failure_multiplier
			return
		
		await get_tree().process_frame
	
	print("Sequence QTE succeeded!")
	context["qte_multiplier"] = card_config.qte_success_multiplier

## Execute effect phase
func execute_effect_phase(card_config: CardConfig, context: Dictionary) -> void:
	var actor = context["actor"]
	var target = context["target"]
	var enemies = context["enemies"]
	var allies = context["allies"]
	
	# Check all conditions before executing effects
	if not check_card_conditions(card_config, context):
		print("Card conditions not met, skipping effect execution")
		return
	
	# Apply QTE multiplier if present
	var qte_multiplier = context.get("qte_multiplier", 1.0)
	
	# Handle effect timing
	match card_config.effect_timing:
		CardConfig.EffectTiming.IMMEDIATE:
			_execute_effects_immediate(card_config, context, qte_multiplier)
		CardConfig.EffectTiming.AFTER_ANIMATION:
			# Effects are handled after animation completes (already in animation phase)
			_execute_effects_immediate(card_config, context, qte_multiplier)
		CardConfig.EffectTiming.ON_HIT:
			# Wait for hit frame timing
			await _execute_effects_on_hit(card_config, context, qte_multiplier)
		CardConfig.EffectTiming.ON_IMPACT:
			# Wait for impact timing
			await _execute_effects_on_impact(card_config, context, qte_multiplier)
		CardConfig.EffectTiming.CHANNEL_START:
			_execute_effects_channel_start(card_config, context, qte_multiplier)
		CardConfig.EffectTiming.CHANNEL_END:
			await _execute_effects_channel_end(card_config, context, qte_multiplier)
		_:
			# Default to immediate
			_execute_effects_immediate(card_config, context, qte_multiplier)

## Check all conditions for card execution
func check_card_conditions(card_config: CardConfig, context: Dictionary) -> bool:
	var actor = context["actor"]
	var target = context["target"]
	
	# Check effect conditions
	for condition in card_config.effect_conditions:
		if not condition.evaluate(actor, target):
			print("Card condition failed: ", condition.get_description())
			return false
	
	# Check primary effect conditions
	if card_config.primary_effect:
		for condition in card_config.primary_effect.conditions:
			if not condition.evaluate(actor, target):
				print("Primary effect condition failed: ", condition.get_description())
				return false
	
	# Check secondary effect conditions
	for effect in card_config.secondary_effects:
		for condition in effect.conditions:
			if not condition.evaluate(actor, target):
				print("Secondary effect condition failed: ", condition.get_description())
				return false
	
	# Check state application conditions
	for state_config in card_config.applies_states:
		if not check_state_conditions(state_config, actor, target):
			print("State condition failed for: ", state_config.state_name)
			return false
	
	print("All card conditions passed")
	return true

## Check conditions for state application
func check_state_conditions(state_config: StateConfig, actor: Node, target: Node) -> bool:
	# Check application chance
	if randf() > state_config.chance:
		print("State application failed (chance check): ", state_config.chance)
		return false
	
	# Check if target is immune
	if _is_immune_to_state(target, state_config.state_id):
		print("Target is immune to state: ", state_config.state_id)
		return false
	
	return true

## Check if target is immune to a specific state
func _is_immune_to_state(target: Node, state_id: String) -> bool:
	if not target:
		return false
	
	if target.has_method("has_state_immunity"):
		return target.has_state_immunity(state_id)
	
	if target.has_method("has_state"):
		return target.has_state("immunity_" + state_id)
	
	return false

## Execute effects immediately
func _execute_effects_immediate(card_config: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	var actor = context["actor"]
	var target = context["target"]
	var enemies = context["enemies"]
	var allies = context["allies"]
	
	# Execute primary effect
	if card_config.primary_effect:
		var effect_result = card_config.primary_effect.apply_effect(actor, target, enemies, allies)
		print("Primary effect result: ", effect_result)
		
		# Apply damage/healing with QTE multiplier
		if effect_result["success"] and qte_multiplier != 1.0:
			var original_value = effect_result["total_value"]
			var modified_value = int(original_value * qte_multiplier)
			print("Effect value modified by QTE: ", original_value, " -> ", modified_value)
	
	# Execute secondary effects
	for effect in card_config.secondary_effects:
		# Check individual effect conditions
		var conditions_met = true
		for condition in effect.conditions:
			if not condition.evaluate(actor, target):
				print("Secondary effect condition failed: ", condition.get_description())
				conditions_met = false
				break
		
		if conditions_met:
			var effect_result = effect.apply_effect(actor, target, enemies, allies)
			print("Secondary effect result: ", effect_result)
	
	# Apply states
	for state_config in card_config.applies_states:
		if check_state_conditions(state_config, actor, target):
			var state_result = state_config.apply_state(target, actor)
			print("State application result: ", state_result)
	
	# Apply self states
	for state_config in card_config.applies_self_states:
		if check_state_conditions(state_config, actor, actor):
			var state_result = state_config.apply_state(actor, actor)
			print("Self state application result: ", state_result)

## Execute effects on hit frame
func _execute_effects_on_hit(card_config: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	var actor = context["actor"]
	if not actor or not actor.has_method("_get_animation_duration"):
		# Fallback to immediate execution
		_execute_effects_immediate(card_config, context, qte_multiplier)
		return
	
	# Resolve animation name through character's animation mapping if available
	var animation_name = card_config.actor_animation
	if actor.has_method("get_resolved_animation"):
		animation_name = actor.get_resolved_animation(animation_name)
	
	var animation_duration = actor._get_animation_duration(animation_name)
	var hit_frame_delay = animation_duration * 0.55 # Typical hit frame at 55%
	
	print("Waiting for hit frame: ", hit_frame_delay, " seconds")
	await get_tree().create_timer(hit_frame_delay).timeout
	
	print("Hit frame reached, executing effects")
	_execute_effects_immediate(card_config, context, qte_multiplier)

## Execute effects on impact
func _execute_effects_on_impact(card_config: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	# Wait slightly longer than hit frame for impact
	var actor = context["actor"]
	if not actor or not actor.has_method("_get_animation_duration"):
		_execute_effects_immediate(card_config, context, qte_multiplier)
		return
	
	# Resolve animation name through character's animation mapping if available
	var animation_name = card_config.actor_animation
	if actor.has_method("get_resolved_animation"):
		animation_name = actor.get_resolved_animation(animation_name)
	
	var animation_duration = actor._get_animation_duration(animation_name)
	var impact_delay = animation_duration * 0.65 # Impact at 65%
	
	print("Waiting for impact: ", impact_delay, " seconds")
	await get_tree().create_timer(impact_delay).timeout
	
	print("Impact reached, executing effects")
	_execute_effects_immediate(card_config, context, qte_multiplier)

## Execute effects at channel start
func _execute_effects_channel_start(card_config: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	# Apply channeling effects immediately
	print("Channel start effects")
	_execute_effects_immediate(card_config, context, qte_multiplier)
	
	# Store channel end time for later execution
	var channel_duration = 2.0 if card_config.effect_conditions.size() > 0 else 1.0 # Default channel duration
	context["channel_end_time"] = Time.get_ticks_msec() / 1000.0 + channel_duration

## Execute effects at channel end
func _execute_effects_channel_end(card_config: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	var channel_end_time = context.get("channel_end_time", 0.0)
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if channel_end_time > current_time:
		var wait_time = channel_end_time - current_time
		print("Waiting for channel end: ", wait_time, " seconds")
		await get_tree().create_timer(wait_time).timeout
	
	print("Channel end, executing delayed effects")
	_execute_effects_immediate(card_config, context, qte_multiplier)

## Execute VFX phase
func execute_vfx_phase(card_config: CardConfig, context: Dictionary) -> void:
	var effect_manager = context["effect_manager"]
	if not effect_manager:
		return
	
	var actor = context["actor"]
	var target = context["target"]
	
	# Spawn VFX on actor
	if card_config.vfx_on_actor:
		var vfx_instance = card_config.vfx_on_actor.spawn_vfx(actor.global_position, actor)
		if vfx_instance:
			get_tree().current_scene.add_child(vfx_instance)
	
	# Spawn VFX on target
	if card_config.vfx_on_target and target:
		var vfx_instance = card_config.vfx_on_target.spawn_vfx(target.global_position, target)
		if vfx_instance:
			get_tree().current_scene.add_child(vfx_instance)

## Execute camera phase
func execute_camera_phase(card_config: CardConfig, context: Dictionary) -> void:
	var camera = context["camera"]
	if not camera or not card_config.camera_effects:
		return
	
	card_config.camera_effects.apply_camera_effects(camera, context["actor"], context["target"])

## Execute screen phase
func execute_screen_phase(card_config: CardConfig, context: Dictionary) -> void:
	var effect_manager = context["effect_manager"]
	if not effect_manager or not card_config.screen_effects:
		return
	
	card_config.screen_effects.apply_screen_effect(effect_manager)

## Execute audio phase
func execute_audio_phase(card_config: CardConfig, context: Dictionary) -> void:
	var actor = context["actor"]
	var target = context["target"]
	
	# Play cast sound
	if card_config.cast_sound:
		card_config.cast_sound.play_audio(self, actor.global_position)
	
	# Play hit sound
	if card_config.hit_sound and target:
		card_config.hit_sound.play_audio(self, target.global_position)
	
	# Play impact sound
	if card_config.impact_sound and target:
		await get_tree().create_timer(0.3).timeout # Delay for impact
		card_config.impact_sound.play_audio(self, target.global_position)

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
		if current_player_battler.advance_to_target(target):
			current_player_battler._try_animation("walk")
			while current_player_battler.is_advancing:
				await get_tree().create_timer(0.016).timeout
	
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
			
			# Perform dodge dash movement
			if target_defender and target_defender.has_method("perform_dodge_dash"):
				target_defender.perform_dodge_dash()
			
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
