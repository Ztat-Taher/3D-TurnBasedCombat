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
var card_battle_config: CardBattleConfig
var qte_manager: QTEManager

# Cards played this turn (to be executed when turn ends)
var queued_cards: Array = []

func _ready():
	# Add to group for easy access
	add_to_group("card_battle_manager")
	
	# Find the battle manager
	battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		push_error("CardBattleManager: Could not find BattleManager")
		return
	
	# Create AP system
	ap_system = APSystem.new()
	add_child(ap_system)
	
	# Create QTE manager
	qte_manager = QTEManager.new()
	add_child(qte_manager)
	
	# Load configuration
	card_battle_config = load_card_config()
	if card_battle_config:
		ap_system.setup(card_battle_config.ap_per_turn, card_battle_config.max_ap)
		ap_system.ap_changed.connect(_on_ap_changed)

func load_card_config() -> CardBattleConfig:
	# Try to load from project settings or create default
	var config_path = "res://scripts/systems/battle/card_combat/systems/card_battle_config.tres"
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

func create_combat_config() -> CombatConfig:
	var config = CombatConfig.new()
	if card_battle_config:
		config.initial_hand_size = card_battle_config.initial_hand_size
		config.max_hand_size = card_battle_config.max_hand_size
		config.max_board_size = card_battle_config.max_board_size
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
		return false
	
	# Check AP on active player battler first, fallback to ap_system
	if current_player_battler:
		return current_player_battler.can_spend_ap(card.cost)
	elif ap_system:
		return ap_system.can_spend_ap(card.cost)
	
	return true

var is_executing_card: bool = false

func play_card(card: CardData, target: Battler = null) -> bool:
	if is_executing_card or not can_play_card(card):
		return false
	
	is_executing_card = true
	if battle_manager:
		battle_manager.is_animating = true
		if battle_manager.hud and battle_manager.hud.has_method("set_ui_state"):
			battle_manager.hud.set_ui_state(3) # CARD_EXECUTION_STATE
	
	# Camera choreography: wider view for player attack cards only
	var card_type = card.metadata.get("card_type", "attack")
	if (card_type == "attack" or card_type == "skill") and battle_manager and battle_manager.battle_camera:
		battle_manager.battle_camera.set_default_camera()
	
	# Execute card effect
	await execute_card_effect(card, target)
	
	# Spend AP from battler systematically only AFTER effect resolves
	if current_player_battler:
		current_player_battler.spend_ap(card.cost)
		if ap_system:
			ap_system.current_ap = current_player_battler.current_ap
			ap_system.max_ap = current_player_battler.max_ap
		ap_changed.emit(current_player_battler.current_ap, current_player_battler.max_ap)
	elif ap_system:
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
	
	card_played.emit(card, target)
	
	return true

func execute_queued_cards() -> void:
	for card_action in queued_cards:
		var card: CardData = card_action["card"]
		var target: Battler = card_action["target"]
		await execute_card_effect(card, target)
	
	# Clear queued cards
	queued_cards.clear()
	
	# End turn
	turn_ended.emit()

func execute_card_effect(card: CardData, target: Battler) -> void:
	if not target:
		return
	
	if not current_player_battler:
		return
	
	# Apply state effects BEFORE execution (to avoid target being freed)
	apply_card_states(card, target)
	
	# Use card config if available, otherwise fall back to metadata
	if card.has_card_config():
		await execute_card_with_config(card, target)
	else:
		# Error: All cards must use CardConfig system
		push_error("Card '%s' does not have a CardConfig assigned. All cards must use the CardConfig system." % card.name)

## Execute card using the new CardConfig system
func execute_card_with_config(card: CardData, target: Battler) -> void:
	var card_cfg = card.card_config
	if not card_cfg:
		push_error("Card has_card_config() returned true but card_config is null")
		return
	
	# Build execution context
	var allies_array = []
	if battle_manager and battle_manager.players:
		for player in battle_manager.players:
			if is_instance_valid(player) and player is Battler and not player.is_defeated():
				allies_array.append(player)
	
	# Ensure current player is included in allies for self-targeting
	if current_player_battler and current_player_battler not in allies_array:
		allies_array.append(current_player_battler)
	
	var context = {
		"card_data": card,
		"card_config": card_cfg,
		"actor": current_player_battler,
		"target": target,
		"enemies": battle_manager.enemies if battle_manager else [],
		"allies": allies_array,
		"effect_manager": battle_manager.effect_manager if battle_manager else null,
		"qte_manager": qte_manager,
		"camera": battle_manager.battle_camera if battle_manager else null,
		"parent_node": self
	}
	
	# Determine if this is an AOE effect
	var is_aoe = card_cfg.target_type in [CardConfig.TargetScope.ALL_ENEMIES, CardConfig.TargetScope.ALL_ALLIES, CardConfig.TargetScope.ALL_UNITS, CardConfig.TargetScope.ALL_ALLIES_SELF]
	
	# Phase 0: Movement Phase (for non-AOE enemy targeting)
	var movement_time := 0.0
	if not is_aoe and card_cfg.target_type == CardConfig.TargetScope.SINGLE_ENEMY and target:
		print("[CardBattleManager] Starting movement to target: %s" % target.character_name)
		# Store original position before movement so we can return later
		var original_pos_before_move = current_player_battler.global_position
		if current_player_battler.advance_to_target(target):
			current_player_battler._try_animation("walk")
			var movement_start = Time.get_ticks_msec() / 1000.0
			while current_player_battler.is_advancing:
				await get_tree().create_timer(0.016).timeout
			movement_time = (Time.get_ticks_msec() / 1000.0) - movement_start
			print("[CardBattleManager] Movement took %.3fs" % movement_time)
		else:
			print("[CardBattleManager] advance_to_target returned false (already at target?)")
	
	# Phase 0.5: Check if multi-strike or single-strike
	if card_cfg.is_multi_strike:
		# Multi-strike execution: every strike applies its own damage at its own hit frame.
		await execute_multi_strike_sequence(card_cfg, context)
		# The sequence sets skip_primary_effect so the phase below cannot double-dip.
	else:
		# Single-strike execution (original flow)
		await execute_single_strike_sequence(card_cfg, context)
	
	# Phase 2: Get QTE result if it was running
	var qte_success = false
	var qte_multiplier = 1.0
	if context.get("qte_success_set", false):
		qte_success = context.get("qte_success", false)
		qte_multiplier = qte_manager.get_damage_multiplier("CARD_ATTACK", qte_success)
		# Store multiplier in context for effect phase
		context["qte_multiplier"] = qte_multiplier
	
	# Phase 3: Effect Phase (applies damage with QTE multiplier).
	# Single-strike cards run their effects from the hit callback and set
	# damage_applied_at_hit; multi-strike cards set skip_primary_effect. Either way the
	# primary damage is never applied twice here. Secondary effects / states still resolve.
	await execute_effect_phase(card_cfg, context)
	
	# Phase 5: VFX Phase
	if card_cfg.vfx_on_actor or card_cfg.vfx_on_target or card_cfg.vfx_on_projectile:
		execute_vfx_phase(card_cfg, context)
	
	# Phase 6: Return Movement (for non-AOE enemy targeting)
	if not is_aoe and card_cfg.target_type == CardConfig.TargetScope.SINGLE_ENEMY and target:
		if current_player_battler.has_method("return_to_original_position"):
			current_player_battler.return_to_original_position()
			while current_player_battler.is_advancing:
				await get_tree().create_timer(0.016).timeout
	
	# Phase 7: Camera Phase
	if card_cfg.camera_effects:
		execute_camera_phase(card_cfg, context)
	
	# Phase 8: Screen Phase
	if card_cfg.screen_effects:
		execute_screen_phase(card_cfg, context)
	
	# Phase 9: Audio Phase
	if card_cfg.cast_sound or card_cfg.hit_sound or card_cfg.impact_sound:
		execute_audio_phase(card_cfg, context)
	
	# Phase 10: Return the actor to its battle idle once the card fully resolves.
	if current_player_battler and current_player_battler.has_method("battle_idle"):
		current_player_battler.battle_idle()

## Execute animation phase with hit moment damage application
func execute_animation_phase_with_hit_timing(card_cfg: CardConfig, context: Dictionary, qte_start_time: float = 0.0) -> void:
	var actor = context["actor"]
	if not actor:
		return
	
	var animation_name = card_cfg.animation_name
	
	if not animation_name.is_empty():
		# Resolve animation name through character's animation mapping if available
		if actor.has_method("get_resolved_animation"):
			animation_name = actor.get_resolved_animation(animation_name)
		
		print("Playing animation with hit timing: ", animation_name, " for actor: ", actor.character_name)
		
		# Start the animation
		if actor.has_method("_try_animation"):
			var success = actor._try_animation(animation_name)
			print("Animation success: ", success)
		
		# Wait for hit moment signal to apply damage
		if actor.has_signal("hit_moment"):
			var hit_time = Time.get_ticks_msec() / 1000.0
			await actor.hit_moment
			var time_until_hit = (Time.get_ticks_msec() / 1000.0) - hit_time
			print("[CardBattleManager] HIT MOMENT RECEIVED - Time until hit: %.3fs" % time_until_hit)
			
			# Calculate QTE duration if QTE was started early
			if card_cfg.should_trigger_qte() and qte_start_time > 0:
				var qte_duration = (Time.get_ticks_msec() / 1000.0) - qte_start_time
				print("[CardBattleManager] QTE DURATION: %.3fs (configured: %.3fs)" % [qte_duration, card_cfg.qte_window_duration])
			
			# Capture QTE result at hit moment
			if card_cfg.should_trigger_qte() and qte_manager:
				var qte_result = qte_manager.last_qte_result
				context["qte_success"] = qte_result
				context["qte_success_set"] = true
				print("[CardBattleManager] QTE result at hit moment: %s" % qte_result)
			
			await execute_effect_phase(card_cfg, context, true)
			context["damage_applied_at_hit"] = true
		
		# Wait for remaining animation duration
		var anim_duration: float = 0.0
		if actor.has_method("_get_animation_duration"):
			anim_duration = actor._get_animation_duration(animation_name)
		
		if anim_duration > 0.0:
			await get_tree().create_timer(anim_duration).timeout


## Run QTE asynchronously in background with delay
func _run_qte_async(card_cfg: CardConfig, context: Dictionary, delay: float = 0.0) -> void:
	var qte_mgr = context["qte_manager"]
	if not qte_mgr:
		return
	
	# Wait for delay before starting QTE
	if delay > 0:
		await get_tree().create_timer(delay).timeout
	
	print("[CardBattleManager] Starting QTE for card: %s" % context["card_data"].name)
	
	# Use the configured QTE type from CardConfig
	match card_cfg.qte_type:
		CardConfig.QTEType.TIMING:
			await _execute_timing_qte_async(card_cfg, context)
		CardConfig.QTEType.BUTTON_MASH:
			await _execute_button_mash_qte_async(card_cfg, context)
		CardConfig.QTEType.SEQUENCE:
			await _execute_sequence_qte_async(card_cfg, context)

## Get QTE result (should be called after animation completes)
func _get_qte_result() -> bool:
	return qte_manager.last_qte_result if qte_manager else false

## Execute timing-based QTE (synchronous - waits for completion)
func _execute_timing_qte_async(card_cfg: CardConfig, context: Dictionary) -> void:
	var qte_mgr = context["qte_manager"]
	if not qte_mgr:
		return
	
	# Check if QTE is actually enabled for this card
	if card_cfg.qte_type == CardConfig.QTEType.NONE:
		print("[CardBattleManager] QTE disabled for card: %s" % context["card_data"].name)
		return
	
	var _difficulty = card_cfg.qte_difficulty
	var _time_limit = card_cfg.qte_window_duration
	qte_mgr.start_qte(QTEManager.QTEType.CARD_ATTACK, _difficulty)
	
	# Wait for QTE window duration
	await get_tree().create_timer(_time_limit).timeout
	
	# Get and store result
	var qte_result = qte_manager.last_qte_result
	context["qte_success"] = qte_result
	context["qte_success_set"] = true
	print("[CardBattleManager] QTE completed with result: %s" % qte_result)

## Execute button mash QTE (synchronous - waits for completion)
func _execute_button_mash_qte_async(card_cfg: CardConfig, context: Dictionary) -> void:
	var qte_mgr = context["qte_manager"]
	if not qte_mgr:
		return
	# For now, use timing QTE as fallback
	await _execute_timing_qte_async(card_cfg, context)

## Execute sequence QTE (synchronous - waits for completion)
func _execute_sequence_qte_async(card_cfg: CardConfig, context: Dictionary) -> void:
	var qte_mgr = context["qte_manager"]
	if not qte_mgr:
		return
	# For now, use timing QTE as fallback
	await _execute_timing_qte_async(card_cfg, context)

## Execute QTE phase (legacy, kept for compatibility)
func execute_qte_phase(card_cfg: CardConfig, context: Dictionary) -> void:
	var qte_mgr = context["qte_manager"]
	if not qte_mgr:
		return
	
	# Use the configured QTE type from CardConfig
	match card_cfg.qte_type:
		CardConfig.QTEType.TIMING:
			await execute_timing_qte(card_cfg, context)
		CardConfig.QTEType.BUTTON_MASH:
			await execute_button_mash_qte(card_cfg, context)
		CardConfig.QTEType.SEQUENCE:
			await execute_sequence_qte(card_cfg, context)

## Execute timing-based QTE
func execute_timing_qte(card_cfg: CardConfig, context: Dictionary) -> void:
	var qte_mgr = context["qte_manager"]
	if not qte_mgr:
		return
	
	var _difficulty = card_cfg.qte_difficulty
	var _time_limit = card_cfg.qte_window_duration
	
	# Use the QTEManager's card attack method
	var qte_started = qte_mgr.start_card_qte(context["card_data"])
	if qte_started:
		var qte_success = await await_qte_completion()
		var multiplier = card_cfg.qte_success_multiplier if qte_success else card_cfg.qte_failure_multiplier
		context["qte_multiplier"] = multiplier

## Execute button mash QTE
func execute_button_mash_qte(card_cfg: CardConfig, context: Dictionary) -> void:
	var required_presses = card_cfg.qte_mash_count
	var time_window = card_cfg.qte_window_duration
	var current_presses = 0
	var start_time = Time.get_ticks_msec() / 1000.0
	
	while current_presses < required_presses:
		var elapsed = (Time.get_ticks_msec() / 1000.0) - start_time
		if elapsed >= time_window:
			context["qte_multiplier"] = card_cfg.qte_failure_multiplier
			return
		
		# Check for button press (would need input system integration)
		if Input.is_action_just_pressed("ui_accept"):
			current_presses += 1
		
		await get_tree().process_frame
	
	context["qte_multiplier"] = card_cfg.qte_success_multiplier

## Execute sequence QTE
func execute_sequence_qte(card_cfg: CardConfig, context: Dictionary) -> void:
	var sequence = card_cfg.qte_sequence
	if sequence.is_empty():
		return
	
	var time_window = card_cfg.qte_window_duration
	var current_index = 0
	var start_time = Time.get_ticks_msec() / 1000.0
	
	while current_index < sequence.size():
		var elapsed = (Time.get_ticks_msec() / 1000.0) - start_time
		if elapsed >= time_window:
			context["qte_multiplier"] = card_cfg.qte_failure_multiplier
			return
		
		var required_button = sequence[current_index]
		
		# Check for correct button input (would need input system integration)
		if Input.is_action_just_pressed(required_button):
			current_index += 1
		elif Input.is_action_just_pressed("ui_accept"):
			context["qte_multiplier"] = card_cfg.qte_failure_multiplier
			return
		
		await get_tree().process_frame
	
	context["qte_multiplier"] = card_cfg.qte_success_multiplier

## Execute effect phase
func execute_effect_phase(card_cfg: CardConfig, context: Dictionary, from_animation_callback: bool = false) -> void:
	var actor = context["actor"]
	var target = context["target"]
	var _enemies = context["enemies"]
	var _allies = context["allies"]
	
	# Skip if damage was already applied at hit moment
	if context.get("damage_applied_at_hit", false):
		print("[CardBattleManager] Damage already applied at hit moment, skipping effect phase")
		return
	
	# Check all conditions before executing effects
	if not check_card_conditions(card_cfg, context):
		return
	
	# Apply QTE multiplier if present
	var qte_multiplier = context.get("qte_multiplier", 1.0)
	
	# If called from animation callback, apply effects immediately regardless of effect_timing
	if from_animation_callback:
		_execute_effects_immediate(card_cfg, context, qte_multiplier)
		return
	
	# Handle effect timing
	match card_cfg.effect_timing:
		CardConfig.EffectTiming.IMMEDIATE:
			_execute_effects_immediate(card_cfg, context, qte_multiplier)
		CardConfig.EffectTiming.AFTER_ANIMATION:
			_execute_effects_immediate(card_cfg, context, qte_multiplier)
		CardConfig.EffectTiming.ON_HIT:
			await _execute_effects_on_hit(card_cfg, context, qte_multiplier)
		CardConfig.EffectTiming.ON_IMPACT:
			await _execute_effects_on_impact(card_cfg, context, qte_multiplier)
		CardConfig.EffectTiming.CHANNEL_START:
			_execute_effects_channel_start(card_cfg, context, qte_multiplier)
		CardConfig.EffectTiming.CHANNEL_END:
			await _execute_effects_channel_end(card_cfg, context, qte_multiplier)
		_:
			# Default to immediate
			_execute_effects_immediate(card_cfg, context, qte_multiplier)

## Check all conditions for card execution
func check_card_conditions(card_cfg: CardConfig, context: Dictionary) -> bool:
	var actor = context["actor"]
	var target = context["target"]
	
	# Check effect conditions
	for condition in card_cfg.effect_conditions:
		if not condition.evaluate(actor, target):
			return false
	
	# Check primary effect conditions
	if card_cfg.primary_effect:
		for condition in card_cfg.primary_effect.conditions:
			if not condition.evaluate(actor, target):
				return false
	
	# Check secondary effect conditions
	for effect in card_cfg.secondary_effects:
		for condition in effect.conditions:
			if not condition.evaluate(actor, target):
				return false
	
	# Check state application conditions
	for state_cfg in card_cfg.applies_states:
		if not check_state_conditions(state_cfg, actor, target):
			return false
	
	return true

## Check conditions for state application
func check_state_conditions(state_config: StateConfig, _actor: Node, target: Node) -> bool:
	# Check application chance
	if randf() > state_config.chance:
		return false
	
	# Check if target is immune
	if _is_immune_to_state(target, state_config.state_id):
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

## Execute single-strike sequence (original flow)
func execute_single_strike_sequence(card_cfg: CardConfig, context: Dictionary) -> void:
	var actor = context["actor"]
	var qte_start_time := 0.0
	
	# Phase 0.5: Start QTE early (before animation) if card has QTE
	if card_cfg.should_trigger_qte():
		var hit_moment_time = 0.0
		if actor.has_method("_get_hit_moment_time"):
			hit_moment_time = actor._get_hit_moment_time(card_cfg.animation_name)
		
		# Calculate when to start QTE so it ends at hit moment
		var anim_delay := 0.0
		var qte_window = card_cfg.qte_window_duration
		
		# If QTE window is longer than hit moment time, we need to delay animation start
		if qte_window > hit_moment_time:
			anim_delay = qte_window - hit_moment_time
			print("[CardBattleManager] QTE Timing - QTE window: %.3fs, Hit moment: %.3fs, Animation delay: %.3fs" % [qte_window, hit_moment_time, anim_delay])
		else:
			print("[CardBattleManager] QTE Timing - QTE window: %.3fs, Hit moment: %.3fs, No delay needed" % [qte_window, hit_moment_time])
		
		# Start QTE immediately
		qte_start_time = Time.get_ticks_msec() / 1000.0
		print("[CardBattleManager] QTE STARTED early - Card: %s, Window: %.3fs" % [context["card_data"].name, qte_window])
		
		var qte_mgr = context["qte_manager"]
		if qte_mgr:
			qte_mgr.start_qte(QTEManager.QTEType.CARD_ATTACK, card_cfg.qte_difficulty, qte_window)
		
		# Delay animation start if needed
		if anim_delay > 0:
			await get_tree().create_timer(anim_delay).timeout
			print("[CardBattleManager] Animation delayed by %.3fs to sync with QTE" % anim_delay)
	
	# Phase 1: Animation Phase with hit timing
	await execute_animation_phase_with_hit_timing(card_cfg, context, qte_start_time)

## Execute multi-strike sequence
func execute_multi_strike_sequence(card_cfg: CardConfig, context: Dictionary) -> void:
	var actor = context["actor"]
	var strike_count = card_cfg.strike_animations.size()
	
	if strike_count == 0:
		push_error("Multi-strike enabled but strike_animations is empty")
		return
	
	print("[CardBattleManager] Starting multi-strike sequence with %d strikes" % strike_count)
	
	var total_qte_success = true
	var cumulative_qte_multiplier = 1.0
	
	var sequence_start := Time.get_ticks_msec() / 1000.0
	
	for strike_index in range(strike_count):
		# Abort the combo if the target was destroyed mid-sequence (defeated, faded
		# out and freed by an earlier strike).
		if not is_instance_valid(context.get("target")):
			print("[CardBattleManager] Multi-strike aborted before strike %d - target no longer valid" % (strike_index + 1))
			break
		
		var animation_name = card_cfg.strike_animations[strike_index]
		var damage_multiplier = card_cfg.strike_multipliers[strike_index] if strike_index < card_cfg.strike_multipliers.size() else 1.0
		var strike_delay = card_cfg.strike_delays[strike_index] if strike_index < card_cfg.strike_delays.size() else 0.0
		var qte_difficulty = card_cfg.strike_qte_difficulties[strike_index] if strike_index < card_cfg.strike_qte_difficulties.size() else 0.5
		var qte_window = card_cfg.strike_qte_windows[strike_index] if strike_index < card_cfg.strike_qte_windows.size() else 0.4
		var has_next_strike = strike_index < strike_count - 1
		var chain_lead = get_strike_chain_lead(card_cfg, strike_index) if has_next_strike else 0.0
		
		print("[CardBattleManager] Executing strike %d/%d: %s" % [strike_index + 1, strike_count, animation_name])
		
		# Apply strike delay if configured
		if strike_delay > 0:
			await get_tree().create_timer(strike_delay).timeout
		
		# Execute single strike with its own QTE
		var strike_context = context.duplicate()
		strike_context["strike_index"] = strike_index
		strike_context["animation_name"] = animation_name
		strike_context["damage_multiplier"] = damage_multiplier
		strike_context["qte_difficulty"] = qte_difficulty
		strike_context["qte_window"] = qte_window
		strike_context["has_next_strike"] = has_next_strike
		strike_context["chain_lead"] = chain_lead
		
		await execute_single_strike_inline(strike_context)
		
		# Track QTE success for cumulative effect
		if strike_context.get("qte_success_set", false):
			var strike_qte_success = strike_context.get("qte_success", false)
			if not strike_qte_success:
				total_qte_success = false
			# Use the project's configured QTE multipliers (database/qte_config.tres)
			var strike_multiplier := 1.0
			if qte_manager:
				strike_multiplier = qte_manager.get_damage_multiplier("CARD_ATTACK", strike_qte_success)
			cumulative_qte_multiplier *= strike_multiplier
	
	# Every strike already applied its own damage - tell the effect phase to skip this
	# card's primary effect so it cannot land a phantom final hit. Secondary effects
	# and states are still applied by execute_effect_phase().
	context["skip_primary_effect"] = true
	
	# Store cumulative results in main context
	context["qte_success"] = total_qte_success
	context["qte_success_set"] = true
	context["qte_multiplier"] = cumulative_qte_multiplier
	print("[CardBattleManager] Multi-strike complete - Total QTE success: %s, Cumulative multiplier: %.2f" % [total_qte_success, cumulative_qte_multiplier])
	print("[CardBattleManager] Multi-strike sequence total time: %.3fs" % ((Time.get_ticks_msec() / 1000.0) - sequence_start))

## Chain lead (seconds trimmed from a strike's clip so the next strike starts early).
## Per-strike values come from CardConfig.strike_chain_leads; the global default is
## CardBattleConfig.multi_strike_chain_lead. 0.0 = wait for the full clip.
func get_strike_chain_lead(card_cfg: CardConfig, strike_index: int) -> float:
	if strike_index >= 0 and strike_index < card_cfg.strike_chain_leads.size():
		return max(0.0, card_cfg.strike_chain_leads[strike_index])
	if card_battle_config:
		return max(0.0, card_battle_config.multi_strike_chain_lead)
	return 0.0

## Execute a single strike using inline configuration
func execute_single_strike_inline(context: Dictionary) -> void:
	var actor = context["actor"]
	var animation_name = context["animation_name"]
	var damage_multiplier = context["damage_multiplier"]
	var qte_difficulty = context["qte_difficulty"]
	var qte_window = context["qte_window"]
	var qte_start_time := 0.0
	
	# Seconds trimmed from this strike's clip so the NEXT strike chains in early.
	# Only used when another strike follows (set by execute_multi_strike_sequence).
	var chain_lead = context.get("chain_lead", 0.0) if context.get("has_next_strike", false) else 0.0
	
	# Start QTE for this strike
	if qte_window > 0:
		var hit_moment_time = 0.0
		if actor.has_method("_get_hit_moment_time"):
			hit_moment_time = actor._get_hit_moment_time(animation_name)
		
		# Calculate QTE timing for this strike
		var anim_delay := 0.0
		
		if qte_window > hit_moment_time:
			anim_delay = qte_window - hit_moment_time
			print("[CardBattleManager] Strike %d QTE Timing - Window: %.3fs, Hit moment: %.3fs, Delay: %.3fs" % [context["strike_index"], qte_window, hit_moment_time, anim_delay])
		else:
			print("[CardBattleManager] Strike %d QTE Timing - Window: %.3fs, Hit moment: %.3fs, No delay needed" % [context["strike_index"], qte_window, hit_moment_time])
		
		# Start QTE immediately
		qte_start_time = Time.get_ticks_msec() / 1000.0
		print("[CardBattleManager] Strike %d QTE STARTED - Window: %.3fs" % [context["strike_index"], qte_window])
		
		var qte_mgr = context["qte_manager"]
		if qte_mgr:
			qte_mgr.start_qte(QTEManager.QTEType.CARD_ATTACK, qte_difficulty, qte_window)
		
		# Delay animation start if needed
		if anim_delay > 0:
			await get_tree().create_timer(anim_delay).timeout
	
	# Play animation with hit timing
	print("[CardBattleManager] Strike %d animation: %s" % [context["strike_index"], animation_name])
	var animation_start_time := Time.get_ticks_msec() / 1000.0
	if actor.has_method("_try_animation"):
		actor._try_animation(animation_name)
	
	# Wait for hit moment signal
	if actor.has_signal("hit_moment"):
		var hit_time = Time.get_ticks_msec() / 1000.0
		await actor.hit_moment
		var time_until_hit = (Time.get_ticks_msec() / 1000.0) - hit_time
		print("[CardBattleManager] Strike %d HIT MOMENT RECEIVED - Time until hit: %.3fs" % [context["strike_index"], time_until_hit])
		
		# Calculate QTE duration if QTE was started
		if qte_window > 0 and qte_start_time > 0:
			var qte_duration = (Time.get_ticks_msec() / 1000.0) - qte_start_time
			print("[CardBattleManager] Strike %d QTE DURATION: %.3fs (configured: %.3fs)" % [context["strike_index"], qte_duration, qte_window])
		
		# Capture QTE result at hit moment
		if qte_window > 0 and qte_manager:
			var qte_result = qte_manager.last_qte_result
			context["qte_success"] = qte_result
			context["qte_success_set"] = true
			print("[CardBattleManager] Strike %d QTE result at hit moment: %s" % [context["strike_index"], qte_result])
		
		# Apply damage for this strike with strike-specific multiplier
		var strike_multiplier = 1.2 if context.get("qte_success", false) else 0.8
		
		# Apply damage immediately
		await apply_strike_damage_inline(context, damage_multiplier, strike_multiplier)
		context["damage_applied_at_hit"] = true
	
	# Wait out the remainder of this strike's clip before the next strike starts.
	# Timing is anchored to the frame the animation was triggered, so the target's
	# hit reaction awaited above overlaps the clip tail instead of stacking on top of
	# the combo timing. `chain_lead` shortens the wait so the next strike's travel is
	# issued while this clip is still playing, which keeps the actor inside the
	# combat_actions sub-machine (no drop back to idle between combo hits).
	var clip_length = _get_strike_clip_length(actor, animation_name)
	var clip_end_time = animation_start_time + clip_length
	var clip_remaining = clip_end_time - (Time.get_ticks_msec() / 1000.0)
	var wait_time = maxf(0.0, clip_remaining - chain_lead)
	if wait_time > 0.0:
		if chain_lead > 0.0:
			print("[CardBattleManager] Strike %d - chaining next strike (%.3fs to clip end, %.3fs lead, waiting %.3fs)" % [context["strike_index"], clip_remaining, chain_lead, wait_time])
		await get_tree().create_timer(wait_time).timeout
	print("[CardBattleManager] Strike %d animation complete (clip %.3fs)" % [context["strike_index"], clip_length])

## Resolve the playback length (seconds) of a strike's animation clip.
## Falls back to a safe default so an unresolvable clip can never stall a combo.
func _get_strike_clip_length(actor, animation_name: String) -> float:
	if actor and actor.has_method("_get_animation_duration"):
		var length = actor._get_animation_duration(animation_name)
		if length > 0.05:
			return float(length)
	return 1.0

## Apply damage for a single strike using inline config
func apply_strike_damage_inline(context: Dictionary, damage_multiplier: float, qte_multiplier: float) -> void:
	var actor = context["actor"]
	var target = context["target"]
	var card_cfg = context["card_config"]
	
	# Calculate damage with strike multiplier
	var base_damage = card_cfg.base_damage
	var strike_damage = int(base_damage * damage_multiplier * qte_multiplier)
	
	print("[CardBattleManager] Strike %d damage: %d (base: %d, strike mult: %.2f, QTE mult: %.2f)" % [context["strike_index"], strike_damage, base_damage, damage_multiplier, qte_multiplier])
	
	# Apply damage to target (guard against the target being freed mid-combo)
	if battle_manager and is_instance_valid(target):
		await battle_manager.damage_calculation(actor, target, strike_damage, null)

## Execute effects immediately
func _execute_effects_immediate(card_cfg: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	var actor = context["actor"]
	var target = context["target"]
	var enemies = context["enemies"]
	var allies = context["allies"]
	
	# Execute primary effect. Multi-strike cards deal their damage per strike and set
	# skip_primary_effect, so the card's primary damage can never land twice.
	if card_cfg.primary_effect and not context.get("skip_primary_effect", false):
		var final_multiplier = qte_multiplier
		
		# For DAMAGE and HEAL types, route through BattleManager if possible
		if battle_manager:
			var calculated_val = card_cfg.primary_effect._calculate_value(actor)
			var final_val = int(calculated_val * final_multiplier)
			
			if card_cfg.primary_effect.effect_type == CardEffect.EffectType.DAMAGE:
				battle_manager.damage_calculation(actor, target, final_val)
			elif card_cfg.primary_effect.effect_type == CardEffect.EffectType.HEAL:
				battle_manager.heal_calculation(actor, target, final_val)
			else:
				card_cfg.primary_effect.apply_effect(actor, target, enemies, allies)
		else:
			card_cfg.primary_effect.apply_effect(actor, target, enemies, allies)
	
	# Execute secondary effects
	for effect in card_cfg.secondary_effects:
		# Check individual effect conditions
		var conditions_met = true
		for condition in effect.conditions:
			if not condition.evaluate(actor, target):
				conditions_met = false
				break
		
		if conditions_met:
			if battle_manager and effect.effect_type == CardEffect.EffectType.DAMAGE:
				battle_manager.damage_calculation(actor, target, effect._calculate_value(actor))
			elif battle_manager and effect.effect_type == CardEffect.EffectType.HEAL:
				battle_manager.heal_calculation(actor, target, effect._calculate_value(actor))
			else:
				effect.apply_effect(actor, target, enemies, allies)
	
	# Apply states
	for state_cfg in card_cfg.applies_states:
		if check_state_conditions(state_cfg, actor, target):
			state_cfg.apply_state(target, actor)
	
	# Apply self states
	for self_state_cfg in card_cfg.applies_self_states:
		if check_state_conditions(self_state_cfg, actor, actor):
			self_state_cfg.apply_state(actor, actor)
			
	# Update health bars only (don't call update_hud during card execution)
	if battle_manager and battle_manager.hud:
		battle_manager.hud.update_health_bars()

## Execute effects on hit frame
func _execute_effects_on_hit(card_cfg: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	var actor = context["actor"]
	if not actor or not actor.has_method("_get_animation_duration"):
		# Fallback to immediate execution
		_execute_effects_immediate(card_cfg, context, qte_multiplier)
		return
	
	# Resolve animation name through character's animation mapping if available
	var animation_name = card_cfg.animation_name
	if actor.has_method("get_resolved_animation"):
		animation_name = actor.get_resolved_animation(animation_name)
	
	var animation_duration = actor._get_animation_duration(animation_name)
	var hit_frame_delay = animation_duration * 0.55 # Typical hit frame at 55%
	
	await get_tree().create_timer(hit_frame_delay).timeout
	
	_execute_effects_immediate(card_cfg, context, qte_multiplier)

## Execute effects on impact
func _execute_effects_on_impact(card_cfg: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	# Wait slightly longer than hit frame for impact
	var actor = context["actor"]
	if not actor or not actor.has_method("_get_animation_duration"):
		_execute_effects_immediate(card_cfg, context, qte_multiplier)
		return
	
	# Resolve animation name through character's animation mapping if available
	var animation_name = card_cfg.animation_name
	if actor.has_method("get_resolved_animation"):
		animation_name = actor.get_resolved_animation(animation_name)
	
	var animation_duration = actor._get_animation_duration(animation_name)
	var impact_delay = animation_duration * 0.65 # Impact at 65%
	
	await get_tree().create_timer(impact_delay).timeout
	
	_execute_effects_immediate(card_cfg, context, qte_multiplier)

## Execute effects at channel start
func _execute_effects_channel_start(card_cfg: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	# Apply channeling effects immediately
	_execute_effects_immediate(card_cfg, context, qte_multiplier)
	
	# Store channel end time for later execution
	var channel_duration = 2.0 if card_cfg.effect_conditions.size() > 0 else 1.0 # Default channel duration
	context["channel_end_time"] = Time.get_ticks_msec() / 1000.0 + channel_duration

## Execute effects at channel end
func _execute_effects_channel_end(card_cfg: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	var channel_end_time = context.get("channel_end_time", 0.0)
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if channel_end_time > current_time:
		var wait_time = channel_end_time - current_time
		await get_tree().create_timer(wait_time).timeout
	
	_execute_effects_immediate(card_cfg, context, qte_multiplier)

## Execute VFX phase
func execute_vfx_phase(card_cfg: CardConfig, context: Dictionary) -> void:
	var effect_manager = context["effect_manager"]
	if not effect_manager:
		return
	
	var actor = context["actor"]
	var target = context["target"]
	
	# Spawn VFX on actor
	if card_cfg.vfx_on_actor:
		var vfx_instance = card_cfg.vfx_on_actor.spawn_vfx(actor.global_position, actor)
		if vfx_instance:
			get_tree().current_scene.add_child(vfx_instance)
	
	# Spawn VFX on target
	if card_cfg.vfx_on_target and target:
		var vfx_instance = card_cfg.vfx_on_target.spawn_vfx(target.global_position, target)
		if vfx_instance:
			get_tree().current_scene.add_child(vfx_instance)

## Execute camera phase
func execute_camera_phase(card_cfg: CardConfig, context: Dictionary) -> void:
	var camera = context["camera"]
	if not camera or not card_cfg.camera_effects:
		return
	
	card_cfg.camera_effects.apply_camera_effects(camera, context["actor"], context["target"])

## Execute screen phase
func execute_screen_phase(card_cfg: CardConfig, context: Dictionary) -> void:
	var effect_manager = context["effect_manager"]
	if not effect_manager or not card_cfg.screen_effects:
		return
	
	card_cfg.screen_effects.apply_screen_effect(effect_manager)

## Execute audio phase
func execute_audio_phase(card_cfg: CardConfig, context: Dictionary) -> void:
	var actor = context["actor"]
	var target = context["target"]
	
	# Play cast sound
	if card_cfg.cast_sound:
		card_cfg.cast_sound.play_audio(self, actor.global_position)
	
	# Play hit sound
	if card_cfg.hit_sound and target:
		card_cfg.hit_sound.play_audio(self, target.global_position)
	
	# Play impact sound
	if card_cfg.impact_sound and target:
		await get_tree().create_timer(0.3).timeout # Delay for impact
		card_cfg.impact_sound.play_audio(self, target.global_position)

func execute_attack_card(card: CardData, target: Battler, is_aoe: bool = false) -> void:
	if not current_player_battler or not target:
		return
	
	# Calculate damage based on card stats and battler stats
	var base_damage = card.attack
	var attacker_stat = current_player_battler.attack if current_player_battler else 0
	var total_damage = base_damage + attacker_stat
	
	# Apply config multiplier if available
	if card_battle_config:
		total_damage = int(total_damage * card_battle_config.attack_damage_multiplier)
	
	# For AOE, skip movement animation - just play attack animation from current position
	if not is_aoe:
		# Move to target and attack
		if current_player_battler.advance_to_target(target):
			current_player_battler._try_animation("walk")
			while current_player_battler.is_advancing:
				await get_tree().create_timer(0.016).timeout
	
	# Play attack animation (standardised melee slot — resolves through the character's
	# animation mapping / combat_actions sub-machine automatically).
	current_player_battler._try_animation(AnimationMapping.MELEE_COMBO_1)
	
	# Simple QTE system: start QTE, get result, apply damage with multiplier
	var damage_multiplier = 1.0
	
	if qte_manager and qte_manager.start_card_qte(card):
		var qte_success = await await_qte_completion()
		damage_multiplier = qte_manager.get_damage_multiplier("CARD_ATTACK", qte_success)
	
	# Wait for attack animation to reach hit point
	await get_tree().create_timer(0.5).timeout
	
	# Apply damage with the calculated multiplier
	var final_damage = int(total_damage * damage_multiplier)
	
	# Trigger AOE effect if applicable
	if is_aoe and battle_manager and battle_manager.effect_manager:
		battle_manager.effect_manager.trigger_aoe_attack()
	
	if battle_manager:
		await battle_manager.damage_calculation(current_player_battler, target, final_damage)
	
	# Wait for attack animation to complete
	await get_tree().create_timer(0.5).timeout
	
	# Return to position (only for single target)
	if not is_aoe:
		current_player_battler.return_to_original_position()
		if current_player_battler.is_advancing:
			while current_player_battler.is_advancing:
				await get_tree().create_timer(0.1).timeout
	
	current_player_battler.battle_idle()

func execute_skill_card(card: CardData, target: Battler, is_aoe: bool = false) -> void:
	await execute_attack_card(card, target, is_aoe)

func execute_defense_card(card: CardData) -> void:
	current_player_battler.defend()
	if card.metadata.has("defense_boost"):
		var _boost = card.metadata["defense_boost"]

func execute_heal_card(card: CardData, target: Battler, _is_aoe: bool = false) -> void:
	var heal_amount = card.health
	target.take_healing(heal_amount)
	
	if battle_manager and battle_manager.hud:
		battle_manager.hud.update_health_bars()

func execute_buff_card(card: CardData, _target: Battler, _is_aoe: bool = false) -> void:
	# Handle buff effects like damage multipliers, speed boosts, etc.
	if card.metadata.has("damage_multiplier"):
		var _multiplier = card.metadata["damage_multiplier"]
		# This would need a buff system integration
	
	if card.metadata.has("speed_multiplier"):
		var _multiplier2 = card.metadata["speed_multiplier"]
		# This would need a buff system integration
	
	if card.metadata.has("damage_reduction"):
		var _reduction = card.metadata["damage_reduction"]
		# This would need a buff system integration

func execute_debuff_card(card: CardData, target: Battler, is_aoe: bool = false) -> void:
	# Deal initial damage
	if card.attack > 0:
		await execute_attack_card(card, target, is_aoe)
	
func apply_card_states(card: CardData, _target: Battler) -> void:
	if not card.metadata.has("applies_state"):
		return
	
	var _state_name = card.metadata["applies_state"]
	var state_chance = card.metadata.get("state_chance", 1.0)
	var _state_duration = card.metadata.get("state_duration", 0)
	
	# Check if state should be applied
	if randf() > state_chance:
		return
	
	# Apply the state to the target
	# This would need integration with the existing state system
	# For now, just log the application

func draw_card_for_deck(deck: CombatDeck) -> CardData:
	if not deck:
		push_warning("CardBattleManager: draw_card_for_deck called with a null deck")
		return null
	
	# If draw pile is empty, recycle graveyard back into draw pile and shuffle
	if deck._draw_pile.is_empty() and not deck._graveyard.is_empty():
		deck._draw_pile.append_array(deck._graveyard)
		deck._graveyard.clear()
		deck.shuffle()
	
	var drawn_card = deck.draw_card()
	return drawn_card

func start_player_turn() -> void:
	# Always sync to the currently acting player from battle_manager
	if battle_manager and is_instance_valid(battle_manager.current_character):
		current_player_battler = battle_manager.current_character
	
	# Refresh AP on active player battler
	if current_player_battler:
		current_player_battler.regen_ap()
		if ap_system:
			ap_system.current_ap = current_player_battler.current_ap
			ap_system.max_ap = current_player_battler.max_ap
		ap_changed.emit(current_player_battler.current_ap, current_player_battler.max_ap)
	elif ap_system:
		ap_system.regen_ap()
	
	# --- Step 1: Play discard animation for any leftover hand cards in the UI ---
	var card_ui: CardUI = null
	if battle_manager and battle_manager.hud:
		card_ui = battle_manager.hud.get_node_or_null("Control/CardUI")
	
	if card_ui and card_ui.has_method("discard_hand_to_pile"):
		# Animate the remaining hand flying to the discard corner before the
		# deck-side data is touched (so card buttons still exist for the tween).
		await card_ui.discard_hand_to_pile()
	
	# --- Step 2: Sync deck data (discard leftover hand, draw fresh cards) ---
	var deck = _get_current_deck()
	if deck:
		# Discard whatever is left in hand from the previous turn
		var old_hand = deck.get_hand().duplicate()
		for card in old_hand:
			deck.discard_card(card)
		
		# Draw a fresh hand up to initial_hand_size
		var hand_size = card_battle_config.initial_hand_size if card_battle_config else 3
		for _i in range(hand_size):
			draw_card_for_deck(deck)
	
	# Clear queued cards from previous turn
	queued_cards.clear()
	
	# --- Step 3: Update CardUI display for the new hand and notify HUD ---
	if battle_manager and battle_manager.hud:
		if card_ui:
			# Force a full rebuild by resetting the previous hand size
			if card_ui.has_method("update_hand_display"):
				# Access the internal variable to force rebuild
				if "previous_hand_size" in card_ui:
					card_ui.previous_hand_size = 0
				card_ui.update_hand_display()
		if battle_manager.hud.has_method("update_party_status"):
			var ap_info = get_ap_info()
			battle_manager.hud.last_ap_by_battler[current_player_battler] = {
				"current": ap_info.get("current_ap", 3),
				"max": ap_info.get("max_ap", 3)
			}
			battle_manager.hud.set_activebattler(current_player_battler)
		# Set BASE_STATE at turn start (not show_action_buttons which might auto-select CardUI)
		if battle_manager.hud.has_method("set_ui_state"):
			battle_manager.hud.set_ui_state(0) # BASE_STATE

func end_player_turn() -> void:
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
	pass
	# Card is already handled in play_card()

func _on_mana_changed(_new_mana: int) -> void:
	pass
	# Mana in card system maps to our AP system

func _on_ap_changed(current_ap: int, max_ap: int) -> void:
	# Forward AP changes to UI
	ap_changed.emit(current_ap, max_ap)

func get_ap_info() -> Dictionary:
	if current_player_battler:
		var cur = current_player_battler.current_ap
		var mx = current_player_battler.max_ap
		var pct = float(cur) / float(mx) if mx > 0 else 0.0
		return {
			"current_ap": cur,
			"max_ap": mx,
			"ap_percentage": pct
		}
	elif ap_system:
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
		
		if not qte_manager.qte_completed.is_connected(completion_handler):
			qte_manager.qte_completed.connect(completion_handler)
		
		var timeout = 5.0 # 5 seconds max safety guard
		var start_time = Time.get_ticks_msec() / 1000.0
		
		# Wait for completion or timeout
		while not state["completed"]:
			var elapsed = (Time.get_ticks_msec() / 1000.0) - start_time
			if elapsed > timeout:
				state["completed"] = true
				state["success"] = false # Default to failure on timeout
				# Force cancel the QTE if it's still active
				if qte_manager.is_active():
					qte_manager.cancel_qte()
				break
			await get_tree().process_frame
		
		if qte_manager.qte_completed.is_connected(completion_handler):
			qte_manager.qte_completed.disconnect(completion_handler)
	
	return state["success"]
