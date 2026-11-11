class_name CardBattleManager
extends Node
## Bridges the 3D battle system with the card combat addon
## Manages card-based combat for the player while enemies use AI attacks

signal card_played(card: CardConfig, target: Variant)
signal turn_ended()
signal ap_changed(current_ap: int, max_ap: int)
signal player_attacked(attacker: Battler, damage: int)

## Per-battler decks (keyed by Battler object)
var decks_by_battler: Dictionary = {}     # Battler -> SimplifiedDeck

var ap_system: APSystem

var battle_manager: BattleManager
var current_player_battler: Battler
var card_battle_config: CardBattleConfig
var qte_manager: QTEManager

## Execution context for AOE projectiles (keyed by CardConfig)
var _aoe_execution_context: Dictionary = {}

# Cards played this turn (to be executed when turn ends)
var queued_cards: Array = []

# Projectile scene cache to avoid repeated load() calls
var _projectile_cache: Dictionary = {}  # scene_path -> PackedScene
# Background preload task for projectile scenes
var _preload_task: Dictionary = {}  # scene_path -> bool (loading status)
# Projectile object pool to avoid repeated node instantiation
var _projectile_pool: Array[BattleProjectile] = []
const _POOL_SIZE = 20
const _GRID_CELL_SIZE = 0.5  # Spatial grid cell size for spread calculation

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
	
	# Initialize projectile pool
	_initialize_projectile_pool()

func load_card_config() -> CardBattleConfig:
	# Try to load from project settings or create default
	var config_path = "res://scripts/systems/battle/card_combat/systems/card_battle_config.tres"
	if ResourceLoader.exists(config_path):
		return load(config_path)
	
	# Create default config if none exists
	var default_config = CardBattleConfig.new()
	return default_config

## Sets up a SimplifiedDeck for one ally battler.
## Call this once per ally during battle initialisation.
func setup_card_combat(player_battler: Battler, card_configs: Array[CardConfig]) -> void:
	if not player_battler:
		return
	
	# Create simplified deck
	var deck = SimplifiedDeck.new()
	var max_hand = card_battle_config.max_hand_size if card_battle_config else 3
	deck.setup(card_configs, max_hand)
	
	# Store by battler reference
	decks_by_battler[player_battler] = deck
	
	# Connect deck signals
	if not deck.card_drawn.is_connected(_on_card_drawn):
		deck.card_drawn.connect(_on_card_drawn)
	
	# Preload all projectile scenes for performance
	preload_all_projectile_scenes()

## Returns the current player's active deck. Null if not set up.
func _get_current_deck() -> SimplifiedDeck:
	if current_player_battler and decks_by_battler.has(current_player_battler):
		return decks_by_battler[current_player_battler]
	return null

func get_hand() -> Array[CardConfig]:
	var deck = _get_current_deck()
	if deck:
		return deck.get_hand()
	return []

func can_play_card(card: CardConfig) -> bool:
	if not _get_current_deck():
		return false

	# Check AP on active player battler first, fallback to ap_system
	if current_player_battler:
		return current_player_battler.can_spend_ap(card.ap_cost)
	elif ap_system:
		return ap_system.can_spend_ap(card.ap_cost)

	# Preload projectile scene in background if this is a projectile card
	if card.projectile_enabled and not card.projectile_scene.is_empty():
		_preload_projectile_scene(card.projectile_scene)

	return true

## Preload projectile scene in background to avoid lag spike
func _preload_projectile_scene(scene_path: String) -> void:
	if scene_path in _projectile_cache:
		return  # Already loaded
	if scene_path in _preload_task:
		return  # Already loading

	_preload_task[scene_path] = true
	ResourceLoader.load_threaded_request(scene_path)

## Check and complete background preload
func _complete_preload(scene_path: String) -> PackedScene:
	if scene_path in _projectile_cache:
		return _projectile_cache[scene_path]

	if scene_path in _preload_task:
		var status = ResourceLoader.load_threaded_get_status(scene_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var res = ResourceLoader.load_threaded_get(scene_path)
			if res is PackedScene:
				_projectile_cache[scene_path] = res
				_preload_task.erase(scene_path)
				return res
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			_preload_task.erase(scene_path)

	return null

## Initialize projectile object pool
func _initialize_projectile_pool() -> void:
	for i in _POOL_SIZE:
		var proj = BattleProjectile.new()
		proj.process_mode = Node.PROCESS_MODE_INHERIT
		_projectile_pool.append(proj)

## Get a projectile from pool (creates new if pool exhausted)
func _get_pooled_projectile() -> BattleProjectile:
	if _projectile_pool.size() > 0:
		return _projectile_pool.pop_back()
	# Fallback: create new if pool exhausted
	return BattleProjectile.new()

## Return projectile to pool for reuse
func _return_projectile_to_pool(proj: BattleProjectile) -> void:
	# Remove from scene tree first (before accessing transform properties)
	if proj.get_parent():
		proj.get_parent().remove_child(proj)
	
	# Reset projectile state (only if still valid)
	if is_instance_valid(proj):
		proj._traveling = false
		proj.position = Vector3.ZERO  # Use position instead of global_position
		proj.rotation = Vector3.ZERO
		proj.scale = Vector3.ONE
		proj.damage_data.clear()
		
		# Add back to pool if not full
		if _projectile_pool.size() < _POOL_SIZE:
			_projectile_pool.append(proj)
		else:
			proj.queue_free()

var is_executing_card: bool = false

func play_card(card: CardConfig, target: Battler = null) -> bool:
	if is_executing_card or not can_play_card(card):
		return false
	
	is_executing_card = true
	if battle_manager:
		battle_manager.is_animating = true
		if battle_manager.hud and battle_manager.hud.has_method("set_ui_state"):
			battle_manager.hud.set_ui_state(3) # CARD_EXECUTION_STATE
	
	# Camera choreography: wider view for player attack cards only
	var card_tags = card.card_tags
	var is_attack_card = "attack" in card_tags or "skill" in card_tags
	if is_attack_card and battle_manager and battle_manager.battle_camera:
		battle_manager.battle_camera.set_default_camera()
	
	# Execute card effect
	await execute_card_effect(card, target)
	
	# Spend AP from battler systematically only AFTER effect resolves
	if current_player_battler:
		current_player_battler.spend_ap(card.ap_cost)
		if ap_system:
			ap_system.current_ap = current_player_battler.current_ap
			ap_system.max_ap = current_player_battler.max_ap
		ap_changed.emit(current_player_battler.current_ap, current_player_battler.max_ap)
	elif ap_system:
		ap_system.spend_ap(card.ap_cost)
	
	# Remove from hand (move to graveyard through deck system)
	var deck = _get_current_deck()
	if deck:
		deck.discard_card(card)
	
	# Restore over-the-shoulder camera on the acting player after attack finishes
	if is_attack_card and battle_manager and battle_manager.battle_camera and is_instance_valid(current_player_battler):
		battle_manager.battle_camera.set_over_the_shoulder(current_player_battler)
	
	is_executing_card = false
	if battle_manager:
		battle_manager.is_animating = false
	
	card_played.emit(card, target)
	
	return true

func execute_queued_cards() -> void:
	for card_action in queued_cards:
		var card: CardConfig = card_action["card"]
		var target: Battler = card_action["target"]
		await execute_card_effect(card, target)
	
	# Clear queued cards
	queued_cards.clear()
	
	# End turn
	turn_ended.emit()

func execute_card_effect(card: CardConfig, target: Battler) -> void:
	if not target:
		return
	
	if not current_player_battler:
		return
	
	# Apply state effects BEFORE execution (to avoid target being freed)
	apply_card_states(card, target)
	
	# Execute using CardConfig directly
	await execute_card_with_config(card, target)

## Execute card using the CardConfig system
func execute_card_with_config(card: CardConfig, target: Battler) -> void:
	var card_cfg = card
	if not card_cfg:
		push_error("CardConfig is null")
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
	
	# Phase 0: Movement Phase (for non-AOE enemy melee targeting)
	var movement_time := 0.0
	var should_return_to_position = false
	var is_ranged = card_cfg.projectile_enabled or "ranged" in card_cfg.card_tags
	if not is_aoe and not is_ranged and card_cfg.target_type == CardConfig.TargetScope.SINGLE_ENEMY and target:
		# Store original position before movement so we can return later
		var original_pos_before_move = current_player_battler.global_position
		should_return_to_position = true  # Store decision before target might die
		if current_player_battler.advance_to_target(target):
			current_player_battler._try_animation("walk")
			var movement_start = Time.get_ticks_msec() / 1000.0
			while current_player_battler.is_advancing:
				await get_tree().create_timer(0.016).timeout
			movement_time = (Time.get_ticks_msec() / 1000.0) - movement_start
	
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
	# Use stored decision instead of checking target (target may have died)
	if should_return_to_position:
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
		
		# Start the animation
		if actor.has_method("_try_animation"):
			actor._try_animation(animation_name)

		# Wait a few frames for the state machine to process the transition
		await get_tree().process_frame
		await get_tree().process_frame

		# For projectile cards, launch projectile at hit moment (damage applied on impact)
		# For non-projectile cards, apply damage at hit moment
		if actor.has_signal("hit_moment"):
			var hit_time = Time.get_ticks_msec() / 1000.0
			await actor.hit_moment
			var time_until_hit = (Time.get_ticks_msec() / 1000.0) - hit_time

			# Calculate QTE duration if QTE was started early
			if card_cfg.should_trigger_qte() and qte_start_time > 0:
				var qte_duration = (Time.get_ticks_msec() / 1000.0) - qte_start_time

			# Capture QTE result at hit moment
			if card_cfg.should_trigger_qte() and qte_manager:
				var qte_result = qte_manager.last_qte_result
				context["qte_success"] = qte_result
				context["qte_success_set"] = true

			if card_cfg.projectile_enabled:
				await launch_projectile_and_await_impact(card_cfg, context)
			else:
				await execute_effect_phase(card_cfg, context, true)
			context["damage_applied_at_hit"] = true

			# Stop animation if target died
			var hit_target = context.get("target")
			if hit_target and hit_target.has_method("is_defeated") and hit_target.is_defeated():
				return

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
	var qte_started = qte_mgr.start_card_qte(context["card_config"])
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
		
		# Start QTE immediately
		qte_start_time = Time.get_ticks_msec() / 1000.0
		
		var qte_mgr = context["qte_manager"]
		if qte_mgr:
			qte_mgr.start_qte(QTEManager.QTEType.CARD_ATTACK, card_cfg.qte_difficulty, qte_window)
		
		# Delay animation start if needed
		if anim_delay > 0:
			await get_tree().create_timer(anim_delay).timeout
	
	# Phase 1: Animation Phase with hit timing
	await execute_animation_phase_with_hit_timing(card_cfg, context, qte_start_time)

## Execute multi-strike sequence
func execute_multi_strike_sequence(card_cfg: CardConfig, context: Dictionary) -> void:
	var actor = context["actor"]
	var strike_count = card_cfg.strike_animations.size()

	if strike_count == 0:
		push_error("Multi-strike enabled but strike_animations is empty")
		return

	var total_qte_success = true
	var cumulative_qte_multiplier = 1.0

	var sequence_start := Time.get_ticks_msec() / 1000.0

	# Prevent combat_to_idle AUTO transition during multi-strike to avoid idle insertion
	if actor and actor.has_method("set_animation_condition"):
		actor.set_animation_condition("allow_combat_to_idle", false)
	
	for strike_index in range(strike_count):
		# Abort the combo if the target was destroyed mid-sequence (defeated, faded
		# out and freed by an earlier strike).
		if not is_instance_valid(context.get("target")):
			break
		
		var animation_name = card_cfg.strike_animations[strike_index]
		var damage_multiplier = card_cfg.strike_multipliers[strike_index] if strike_index < card_cfg.strike_multipliers.size() else 1.0
		var qte_difficulty = card_cfg.strike_qte_difficulties[strike_index] if strike_index < card_cfg.strike_qte_difficulties.size() else 0.5
		var qte_window = card_cfg.strike_qte_windows[strike_index] if strike_index < card_cfg.strike_qte_windows.size() else 0.4
		var has_next_strike = strike_index < strike_count - 1
		
		# Read unified timing and split it into delay (positive gap before this strike) 
		# and chain_lead (negative overlap before the next strike).
		var strike_timing = get_strike_timing(card_cfg, strike_index)
		var strike_delay = maxf(0.0, strike_timing)
		var chain_lead = maxf(0.0, -strike_timing) if has_next_strike else 0.0
		
		# Apply strike delay if configured (only applies to gaps, not overlaps)
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

	# Re-enable combat_to_idle AUTO transition after multi-strike completes
	if actor and actor.has_method("set_animation_condition"):
		actor.set_animation_condition("allow_combat_to_idle", true)

## Unified per-strike timing offset (seconds).
## Per-strike values come from CardConfig.strike_timing; the global default is
## CardBattleConfig.default_strike_timing.
func get_strike_timing(card_cfg: CardConfig, strike_index: int) -> float:
	if strike_index >= 0 and strike_index < card_cfg.strike_timing.size():
		return card_cfg.strike_timing[strike_index]
	if card_battle_config and "default_strike_timing" in card_battle_config:
		return card_battle_config.default_strike_timing
	return -0.2 # Safe fallback if not found

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
		
		# Start QTE immediately
		qte_start_time = Time.get_ticks_msec() / 1000.0
		
		var qte_mgr = context["qte_manager"]
		if qte_mgr:
			qte_mgr.start_qte(QTEManager.QTEType.CARD_ATTACK, qte_difficulty, qte_window)
		
		# Delay animation start if needed
		if anim_delay > 0:
			await get_tree().create_timer(anim_delay).timeout
	
	# Play animation with hit timing
	var animation_start_time := Time.get_ticks_msec() / 1000.0
	if actor.has_method("_try_animation"):
		actor._try_animation(animation_name)
	
	# Wait for hit moment signal
	if actor.has_signal("hit_moment"):
		var hit_time = Time.get_ticks_msec() / 1000.0
		await actor.hit_moment
		var time_until_hit = (Time.get_ticks_msec() / 1000.0) - hit_time
		
		# Calculate QTE duration if QTE was started
		if qte_window > 0 and qte_start_time > 0:
			var qte_duration = (Time.get_ticks_msec() / 1000.0) - qte_start_time
		
		# Capture QTE result at hit moment
		if qte_window > 0 and qte_manager:
			var qte_result = qte_manager.last_qte_result
			context["qte_success"] = qte_result
			context["qte_success_set"] = true
		
		# Apply damage for this strike with strike-specific multiplier
		var strike_multiplier = 1.2 if context.get("qte_success", false) else 0.8

		var _strike_card_cfg: CardConfig = context.get("card_config")
		if _strike_card_cfg and _strike_card_cfg.projectile_enabled:
			# Projectile handles its own damage on impact
			var wait_for_impact: bool = _strike_card_cfg.projectile_wait_for_impact if "projectile_wait_for_impact" in _strike_card_cfg else true
			await _travel_projectile(_strike_card_cfg, actor, context["target"], damage_multiplier * strike_multiplier, [], [], wait_for_impact)
		else:
			apply_strike_damage_inline(context, damage_multiplier, strike_multiplier)
		context["damage_applied_at_hit"] = true
	
	# Wait out the remainder of this strike's clip before the next strike (or the
	# post-combat transition) begins. Timing is anchored to animation_start_time so
	# the wait is always correct regardless of how long damage_calculation takes.
	# `chain_lead` shortens the wait for mid-combo strikes so the next travel() is
	# issued while this clip is still playing, keeping the actor inside combat_actions.
	var clip_length = _get_strike_clip_length(actor, animation_name)
	var clip_end_time = animation_start_time + clip_length
	var clip_remaining = clip_end_time - (Time.get_ticks_msec() / 1000.0)
	var wait_time = maxf(0.0, clip_remaining - chain_lead)
	if wait_time > 0.0:
		await get_tree().create_timer(wait_time).timeout

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
	
	# Calculate damage from primary effect
	if card_cfg.primary_effect:
		var base_value = card_cfg.primary_effect._calculate_value(actor)
		var strike_damage = int(base_value * damage_multiplier * qte_multiplier)
		
		# Apply damage to target (guard against the target being freed mid-combo)
		if battle_manager and is_instance_valid(target):
			var dmg_type = card_cfg.primary_effect.damage_type if "damage_type" in card_cfg.primary_effect else "physical"
			var elem = card_cfg.primary_effect.element if "element" in card_cfg.primary_effect else "none"
			await battle_manager.damage_calculation(actor, target, strike_damage, null, dmg_type, elem)

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
				var dmg_type = card_cfg.primary_effect.damage_type if "damage_type" in card_cfg.primary_effect else "physical"
				var elem = card_cfg.primary_effect.element if "element" in card_cfg.primary_effect else "none"
				battle_manager.damage_calculation(actor, target, final_val, null, dmg_type, elem)
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
				var dmg_type = effect.damage_type if "damage_type" in effect else "physical"
				var elem = effect.element if "element" in effect else "none"
				battle_manager.damage_calculation(actor, target, effect._calculate_value(actor), null, dmg_type, elem)
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

func execute_attack_card(card: CardConfig, target: Battler, is_aoe: bool = false) -> void:
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

func execute_skill_card(card: CardConfig, target: Battler, is_aoe: bool = false) -> void:
	await execute_attack_card(card, target, is_aoe)

func execute_defense_card(card: CardConfig) -> void:
	current_player_battler.defend()
	# Defense boost would be handled through stat_modifiers in CardConfig

func execute_heal_card(card: CardConfig, target: Battler, _is_aoe: bool = false) -> void:
	# Heal is now handled through CardEffect in the effect phase
	# This function is kept for compatibility but the actual healing happens in _execute_effects_immediate
	pass

func execute_buff_card(card: CardConfig, _target: Battler, _is_aoe: bool = false) -> void:
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

func execute_debuff_card(card: CardConfig, target: Battler, is_aoe: bool = false) -> void:
	# Deal initial damage if primary effect is a damage effect
	if card.primary_effect and card.primary_effect.effect_type == CardEffect.EffectType.DAMAGE:
		await execute_attack_card(card, target, is_aoe)
	
func apply_card_states(card: CardConfig, target: Battler) -> void:
	# States are applied through CardConfig.applies_states array
	# This is handled in the effect phase, so this function is now a no-op
	pass

func draw_card_for_deck(deck: SimplifiedDeck) -> CardConfig:
	if not deck:
		push_warning("CardBattleManager: draw_card_for_deck called with a null deck")
		return null
	
	# If draw pile is empty, recycle graveyard back into draw pile and shuffle
	if deck.draw_pile.is_empty() and not deck.graveyard.is_empty():
		deck.recycle_graveyard()
	
	var drawn_card = deck.draw_card()
	return drawn_card

func _on_card_drawn(_card: CardConfig):
	pass

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
	return {
		"current_ap": 0,
		"max_ap": 0,
		"ap_percentage": 0.0
	}

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
	else:
		return false

## Travel a single projectile scene from [param actor] to [param target] and await arrival.
## Applies damage on impact. Handles multi-strike and multi-projectile correctly.
## [param used_spawn_positions] tracks already-used spawn positions to prevent overlap
## [param used_target_positions] tracks already-used target positions to prevent path overlap
## [param wait_for_impact] if true, waits for projectile to hit; if false, returns after launch
func _travel_projectile(card_cfg: CardConfig, actor: Node3D, target: Node3D, damage_multiplier: float = 1.0, used_spawn_positions: Array[Vector3] = [], used_target_positions: Array[Vector3] = [], wait_for_impact: bool = true) -> void:
	if card_cfg.projectile_scene.is_empty() or not ResourceLoader.exists(card_cfg.projectile_scene):
		push_error("BattleProjectile: projectile_scene not found — " + card_cfg.projectile_scene)
		return

	# Check background preload first
	var proj_res: PackedScene = _complete_preload(card_cfg.projectile_scene)

	# Fallback to synchronous load if preload didn't complete
	if not proj_res:
		proj_res = load(card_cfg.projectile_scene)
		if proj_res is PackedScene:
			_projectile_cache[card_cfg.projectile_scene] = proj_res

	if not proj_res is PackedScene:
		return

	# Spawn projectile in front of the actor (using their forward direction)
	var actor_forward = -actor.global_transform.basis.z.normalized()  # -Z is forward in Godot
	var base_spawn_pos = actor.global_position + (actor_forward * 0.5) + Vector3(0, 1.2, 0)
	
	# Add random spread to spawn position for variety (ring facing forward from actor)
	var spawn_spread: float = card_cfg.projectile_spawn_spread if "projectile_spawn_spread" in card_cfg else 0.0
	var spawn_pos = base_spawn_pos
	if spawn_spread > 0.0:
		# Create local grid for sequential mode (each projectile fired separately)
		var occupied_cells: Dictionary = {}
		# Pass actor_forward to create ring facing outward from actor
		spawn_pos = _calculate_spread_position(base_spawn_pos, spawn_spread, occupied_cells, used_spawn_positions, 10, actor_forward)
	
	# Determine target position - use center for AOE projectiles
	var base_hit_pos: Vector3
	var is_aoe_projectile = card_cfg.get("projectile_aoe") if "projectile_aoe" in card_cfg else false
	if is_aoe_projectile and _aoe_execution_context.has(card_cfg):
		base_hit_pos = _aoe_execution_context[card_cfg].center_position
	else:
		base_hit_pos = target.global_position + Vector3(0, 1.0, 0)
	
	# Trajectory spread randomizes the PATH, not the target position
	# Projectiles always reach the target but take slightly different curved paths
	var trajectory_spread: float = card_cfg.projectile_trajectory_spread if "projectile_trajectory_spread" in card_cfg else 0.0
	var hit_pos = base_hit_pos

	# Create BattleProjectile container (from pool for performance)
	var battle_proj := _get_pooled_projectile()
	get_tree().current_scene.add_child(battle_proj)
	battle_proj.global_position = spawn_pos

	# Instantiate projectile VFX as child of container
	var proj_vfx: Node3D = proj_res.instantiate()
	battle_proj.add_child(proj_vfx)
	proj_vfx.position = Vector3.ZERO  # Relative to container
	proj_vfx.scale = card_cfg.projectile_scale if "projectile_scale" in card_cfg else Vector3.ONE

	# Set damage data for this projectile
	var damage_data = {
		"actor": actor,
		"target": target,
		"card_cfg": card_cfg,
		"damage_multiplier": damage_multiplier,
		"battle_manager": battle_manager
	}
	
	# Check if this is an AOE projectile (single projectile hitting multiple targets)
	if is_aoe_projectile:
		# Check execution context
		var aoe_targets = []
		if _aoe_execution_context.has(card_cfg):
			aoe_targets = _aoe_execution_context[card_cfg].targets
		
		if not aoe_targets.is_empty():
			damage_data["aoe_targets"] = aoe_targets
	
	battle_proj.damage_data = damage_data

	# Connect to arrived signal to apply damage on impact and cleanup
	# Only connect callback if we're NOT waiting for impact (otherwise we handle it synchronously)
	if not wait_for_impact:
		var aoe_targets = damage_data.get("aoe_targets", [])
		# Store callback data in damage_data instead of binding arguments
		damage_data["callback_data"] = {
			"proj_vfx": proj_vfx,
			"card_cfg": card_cfg,
			"target": target,
			"actor": actor,
			"damage_multiplier": damage_multiplier,
			"aoe_targets": aoe_targets
		}
		# Also store a direct reference to card_cfg at top level for safety
		damage_data["card_cfg"] = card_cfg
		damage_data["target"] = target
		damage_data["actor"] = actor
		damage_data["damage_multiplier"] = damage_multiplier
		damage_data["aoe_targets"] = aoe_targets
		# Disconnect any existing connection first to prevent errors from pooled projectiles
		if battle_proj.arrived.get_connections().size() > 0:
			for connection in battle_proj.arrived.get_connections():
				battle_proj.arrived.disconnect(connection.callable)
		battle_proj.arrived.connect(_on_projectile_arrived_with_data.bind(battle_proj))
	
	# Apply trajectory spread: randomize the arc height for path variety
	# Projectiles always reach the target but take different curved paths
	if trajectory_spread > 0.0:
		# Randomize arc height by ±trajectory_spread
		var arc_variance = (randf() - 0.5) * 2.0 * trajectory_spread  # -spread to +spread
		battle_proj.arc_height = max(0.0, card_cfg.projectile_arc + arc_variance)
	else:
		battle_proj.arc_height = card_cfg.projectile_arc

	# Launch using BattleProjectile component with curve parameters
	battle_proj.speed = card_cfg.projectile_speed
	battle_proj.speed_curve = card_cfg.projectile_speed_curve
	battle_proj.arc_curve = card_cfg.projectile_arc_curve
	battle_proj.curve_influence = card_cfg.projectile_curve_influence
	battle_proj.launch(spawn_pos, hit_pos)

	# If VFX child has play method, play open animation on spawn
	if proj_vfx.has_method("play"):
		proj_vfx.play()

	# Wait for arrival if configured
	if wait_for_impact:
		await battle_proj.arrived
		
		# Play close animation on impact
		if is_instance_valid(proj_vfx) and proj_vfx.has_method("stop"):
			proj_vfx.stop()

		# Clean up VFX child
		if is_instance_valid(proj_vfx):
			proj_vfx.queue_free()
		
		# Apply damage for projectiles BEFORE returning to pool
		var aoe_targets = battle_proj.damage_data.get("aoe_targets", []) if battle_proj.damage_data else []
		await _apply_projectile_damage(card_cfg, actor, target, damage_multiplier, aoe_targets)
		
		# Return container to pool AFTER damage is applied
		if is_instance_valid(battle_proj):
			_return_projectile_to_pool(battle_proj)
	else:
		# Apply strike delay if not waiting for impact
		var strike_delay: float = card_cfg.projectile_strike_delay if "projectile_strike_delay" in card_cfg else 0.3
		if strike_delay > 0:
			await get_tree().create_timer(strike_delay).timeout
		
		# Projectile will handle its own damage and cleanup via arrived signal callback
		# Don't apply damage here since projectile callback will handle it on impact

	# Spawn impact VFX at target if configured
	if card_cfg.vfx_on_target and is_instance_valid(target):
		var vfx = card_cfg.vfx_on_target.spawn_vfx(target.global_position, target)
		if vfx:
			get_tree().current_scene.add_child(vfx)

## Called when a projectile with BattleProjectile component arrives at target
## Only used when NOT waiting for impact (cleanup is handled synchronously when waiting)
## Reads callback data from damage_data to avoid bind() type issues
func _on_projectile_arrived_with_data(battle_proj: BattleProjectile) -> void:
	if not battle_proj or not battle_proj.damage_data:
		return
	
	# Read from top-level damage_data first (more reliable), fallback to callback_data
	var proj_vfx = battle_proj.damage_data.get("callback_data", {}).get("proj_vfx")
	var card_cfg = battle_proj.damage_data.get("card_cfg")
	var target = battle_proj.damage_data.get("target")
	var actor = battle_proj.damage_data.get("actor")
	var damage_multiplier = battle_proj.damage_data.get("damage_multiplier", 1.0)
	var aoe_targets = battle_proj.damage_data.get("aoe_targets", [])
	
	# Apply damage on impact
	await _apply_projectile_damage(card_cfg, actor, target, damage_multiplier, aoe_targets)
	
	# Play close animation
	if is_instance_valid(proj_vfx) and proj_vfx.has_method("stop"):
		proj_vfx.stop()
	
	# Clean up VFX child
	if is_instance_valid(proj_vfx):
		proj_vfx.queue_free()
	
	# Return container to pool
	if is_instance_valid(battle_proj):
		_return_projectile_to_pool(battle_proj)

## Apply damage from projectile impact
func _apply_projectile_damage(card_cfg: CardConfig, actor: Node3D, target: Node3D, damage_multiplier: float, aoe_targets: Array = []) -> void:
	if not battle_manager or not card_cfg.primary_effect:
		return
	
	# Check if this is an AOE projectile (from aoe_targets parameter)
	var projectile_aoe = card_cfg.get("projectile_aoe") if card_cfg.has_method("get") else false
	var targets_to_damage: Array[Node3D] = []
	
	if projectile_aoe and not aoe_targets.is_empty():
		for t in aoe_targets:
			if t is Node3D and is_instance_valid(t):
				targets_to_damage.append(t)
	
	# If no AOE targets or not AOE, use the single target
	if targets_to_damage.is_empty():
		if is_instance_valid(target):
			targets_to_damage.append(target)
	
	# Apply damage to all targets simultaneously (no await)
	for t in targets_to_damage:
		if not is_instance_valid(t):
			continue
		
		var base_val = card_cfg.primary_effect._calculate_value(actor, 1)
		var final_val := int(base_val * damage_multiplier)
		var dmg_type: String = card_cfg.primary_effect.damage_type \
			if "damage_type" in card_cfg.primary_effect else "physical"
		var elem: String = card_cfg.primary_effect.element \
			if "element" in card_cfg.primary_effect else "none"
		battle_manager.damage_calculation(actor, t, final_val, null, dmg_type, elem)

## Calculate a spread position with collision detection
## [param base_pos] Center position to spread around
## [param spread_radius] Maximum spread distance in world units (meters)
## [param occupied_cells] Dictionary tracking used grid cells for collision avoidance
## [param used_positions] Array tracking all used positions for this volley
## [param max_attempts] Maximum retry attempts before fallback
## [param forward_direction] Optional forward direction for oriented ring spread (if provided, creates ring facing this direction)
## Returns a valid spread position
func _calculate_spread_position(base_pos: Vector3, spread_radius: float, occupied_cells: Dictionary, used_positions: Array[Vector3], max_attempts: int = 10, forward_direction: Vector3 = Vector3.ZERO) -> Vector3:
	if spread_radius <= 0.0:
		return base_pos
	
	var attempt = 0
	var found_unique = false
	var candidate_pos = base_pos
	
	while attempt < max_attempts and not found_unique:
		# Use sqrt(randf()) for uniform area distribution (prevents center bias)
		var angle = randf() * TAU
		var radius = sqrt(randf()) * spread_radius
		
		var spread_offset: Vector3
		if forward_direction.length_squared() > 0.01:
			# Create ring facing forward direction (perpendicular to forward)
			# Ring is in the plane perpendicular to forward direction
			var right = forward_direction.cross(Vector3.UP).normalized()
			var up = right.cross(forward_direction).normalized()
			spread_offset = (right * cos(angle) + up * sin(angle)) * radius
		else:
			# Circular spread on horizontal plane (default behavior)
			spread_offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		
		candidate_pos = base_pos + spread_offset
		
		# Check collision using spatial grid
		var grid_x = floor(candidate_pos.x / _GRID_CELL_SIZE)
		var grid_z = floor(candidate_pos.z / _GRID_CELL_SIZE)
		var grid_key = Vector2i(grid_x, grid_z)
		
		var too_close = false
		if grid_key in occupied_cells:
			too_close = true
		else:
			# Check adjacent cells for minimum distance
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var neighbor_key = Vector2i(grid_x + dx, grid_z + dz)
					if neighbor_key in occupied_cells:
						too_close = true
						break
				if too_close:
					break
		
		if not too_close:
			used_positions.append(candidate_pos)
			occupied_cells[grid_key] = 1
			found_unique = true
		
		attempt += 1
	
	# If we couldn't find a unique position after max attempts, just use the last candidate
	# This ensures the projectile still fires even if slightly overlapping
	return candidate_pos

## Pre-calculate spread positions for simultaneous fire
## Uses random distribution matching sequential mode for consistency
func _precalculate_spread_positions(card_cfg: CardConfig, actor: Node3D, target: Node3D, count: int, out_spawn_positions: Array[Vector3], out_target_positions: Array[Vector3]) -> void:
	var actor_forward = -actor.global_transform.basis.z.normalized()
	var base_spawn_pos = actor.global_position + (actor_forward * 0.5) + Vector3(0, 1.2, 0)
	var base_hit_pos = target.global_position + Vector3(0, 1.0, 0)
	
	var spawn_spread: float = card_cfg.projectile_spawn_spread if "projectile_spawn_spread" in card_cfg else 0.0
	
	# Use global spatial grid for the entire volley to prevent overlap
	var occupied_spawn_cells: Dictionary = {}
	var used_spawn_positions: Array[Vector3] = []
	
	for i in count:
		# Calculate spawn position with collision detection (ring facing forward from actor)
		var spawn_pos = _calculate_spread_position(base_spawn_pos, spawn_spread, occupied_spawn_cells, used_spawn_positions, 10, actor_forward)
		
		# Target position is always the actual target (no spread)
		# Trajectory spread will be applied to arc height, not target position
		out_spawn_positions.append(spawn_pos)
		out_target_positions.append(base_hit_pos)

## Preload all projectile scenes at combat start
func preload_all_projectile_scenes() -> void:
	# Collect all card configs from decks
	for deck in decks_by_battler.values():
		if deck:
			# Preload from draw pile
			for card_cfg in deck.draw_pile:
				if card_cfg and card_cfg.projectile_enabled and not card_cfg.projectile_scene.is_empty():
					_preload_projectile_scene(card_cfg.projectile_scene)

## Launch projectile(s) toward the target. Each projectile handles its own damage on impact.
## Handles [code]consume_hand_cards[/code] multi-projectile stagger internally.
func launch_projectile_and_await_impact(card_cfg: CardConfig, context: Dictionary) -> void:
	var actor: Node3D  = context["actor"]
	var target: Node3D = context["target"]
	var qte_multiplier := context.get("qte_multiplier", 1.0) as float

	# --- Determine projectile count and discard hand cards if needed -------
	var hand_multiplier := 1
	if card_cfg.primary_effect and card_cfg.primary_effect.consume_hand_cards:
		var deck := _get_current_deck()
		if deck:
			var other_cards: Array[CardConfig] = []
			for c in deck.get_hand():
				# Exclude the playing card by object identity to handle multiple Card Salvo cards
				if c != card_cfg:
					other_cards.append(c)
			hand_multiplier = max(1, other_cards.size())
			for c in other_cards:
				deck.discard_card(c)

	# --- Fire projectiles (configurable stagger or simultaneous) -------------
	var fire_simultaneously: bool = card_cfg.projectile_fire_simultaneously if "projectile_fire_simultaneously" in card_cfg else false
	
	# Track used positions to prevent overlap
	var used_spawn_positions: Array[Vector3] = []
	var used_target_positions: Array[Vector3] = []
	
	if fire_simultaneously:
		# Pre-calculate positions for simultaneous fire to eliminate retry loop
		_precalculate_spread_positions(card_cfg, actor, target, hand_multiplier, used_spawn_positions, used_target_positions)
		
		# Fire all at once, no waiting between projectiles
		for i in hand_multiplier:
			_travel_projectile(card_cfg, actor, target, qte_multiplier, used_spawn_positions, used_target_positions)
		# Wait for all to finish (short delay to ensure all launched)
		await get_tree().create_timer(0.5).timeout
	else:
		# Fire with staggered delays
		for i in hand_multiplier:
			if i > 0:
				await get_tree().create_timer(0.15).timeout
			await _travel_projectile(card_cfg, actor, target, qte_multiplier, used_spawn_positions, used_target_positions)
