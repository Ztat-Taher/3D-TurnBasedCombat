class_name CardBattleManager
extends Node
## Bridges the 3D battle system with the card combat addon
## Manages card-based combat for the player while enemies use AI attacks

signal card_played(card: CardConfig, target: Variant)
signal turn_ended()
signal ap_changed(current_ap: int, max_ap: int)
## A card drawn for [param battler] found their hand full and went straight to
## the graveyard.
signal card_overdrawn(battler: Battler, card: CardConfig)

## Per-battler decks (keyed by Battler object)
var decks_by_battler: Dictionary = {}     # Battler -> SimplifiedDeck

var battle_manager: BattleManager
## The acting battler. Its AP is the one AP store: its ap_changed is relayed
## as this manager's [signal ap_changed] (spending, regen, passive gains).
var current_player_battler: Battler:
	set(value):
		if is_instance_valid(current_player_battler) and current_player_battler.ap_changed.is_connected(_relay_ap_changed):
			current_player_battler.ap_changed.disconnect(_relay_ap_changed)
		current_player_battler = value
		if is_instance_valid(value) and not value.ap_changed.is_connected(_relay_ap_changed):
			value.ap_changed.connect(_relay_ap_changed)
var card_battle_config: CardBattleConfig
var qte_manager: QTEManager

# Projectile scene cache to avoid repeated load() calls
var _projectile_cache: Dictionary = {}  # scene_path -> PackedScene
# Background preload task for projectile scenes
var _preload_task: Dictionary = {}  # scene_path -> bool (loading status)
# Projectile object pool to avoid repeated node instantiation
## Projectiles launched whose impact hasn't resolved yet. A card doesn't
## finish until this is back to 0 (see _await_projectiles_landed).
var _projectiles_in_flight: int = 0
## Spread spawns try to stay at least this far apart (metres, and at least a
## fifth of the card's spawn spread)
const _MIN_SPAWN_SEPARATION = 0.4

func _ready():
	# Add to group for easy access
	add_to_group("card_battle_manager")
	
	# Find the battle manager
	battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		push_error("CardBattleManager: Could not find BattleManager")
		return
	
# Create QTE manager
	qte_manager = QTEManager.new()
	add_child(qte_manager)
	
	# Load configuration
	card_battle_config = load_card_config()

	# Initialize projectile pool

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
	_opening_hand_pending[player_battler] = true
	
	# A card drawn into a full hand is burned: tell the UI
	deck.card_overdrawn.connect(func(card: CardConfig): card_overdrawn.emit(player_battler, card))
	
	# Preload all projectile scenes for performance
	preload_all_projectile_scenes()

## Battlers whose first hand of the combat hasn't been dealt yet (it gets
## their "starting_hand_size" bonus).
var _opening_hand_pending: Dictionary = {}


## AP the current player pays to play [param card] (after passive reductions).
func get_card_ap_cost(card: CardConfig) -> int:
	if current_player_battler:
		return current_player_battler.get_card_ap_cost(card)
	return card.ap_cost


## Draws [param count] extra cards into [param battler]'s hand (e.g. from a
## passive effect) and refreshes the hand display. Returns how many were drawn.
func draw_cards(battler: Battler, count: int) -> int:
	var deck: SimplifiedDeck = decks_by_battler.get(battler)
	if deck == null or count <= 0:
		return 0
	# Only cards that reach the hand count: one drawn into a full hand burns
	# (the deck's card_overdrawn) and isn't a card drawn
	var drawn := 0
	for _i in count:
		var card := draw_card_for_deck(deck)
		if card and deck.hand.has(card):
			drawn += 1
	if drawn > 0 and battler == current_player_battler and battle_manager and battle_manager.hud:
		var card_ui = battle_manager.hud.get_node_or_null("Control/CardUI")
		if card_ui and card_ui.has_method("update_hand_display"):
			card_ui.update_hand_display()
	return drawn


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

## Whether the acting battler can play [param card] now: it's in their hand
## and they can pay its AP cost.
func can_play_card(card: CardConfig) -> bool:
	var deck := _get_current_deck()
	if deck == null or card == null or not deck.hand.has(card):
		return false
	return current_player_battler.can_spend_ap(get_card_ap_cost(card))


## AP the draw pile asks for one extra card.
func get_draw_ap_cost() -> int:
	return card_battle_config.draw_card_ap_cost if card_battle_config else 1


## Whether the acting battler can buy a card from the draw pile: a card to draw
## (the draw pile, or a graveyard to recycle), room in hand and the AP.
func can_buy_card_draw() -> bool:
	var deck := _get_current_deck()
	if deck == null or is_executing_card or deck.is_hand_full():
		return false
	if deck.draw_pile.is_empty() and deck.graveyard.is_empty():
		return false
	return current_player_battler.can_spend_ap(get_draw_ap_cost())


## Buys one card from the draw pile. The AP is only spent once a card was
## actually drawn. Returns the card (null when nothing could be bought).
func buy_card_draw() -> CardConfig:
	if not can_buy_card_draw():
		return null
	var card := draw_card_for_deck(_get_current_deck())
	if card:
		current_player_battler.spend_ap(get_draw_ap_cost())
	return card

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

var is_executing_card: bool = false
## >0 while replay_card_resolution re-runs card effects (e.g. for a hit-echo
## weapon's ghost strike) — emitted resolutions are tagged is_replay so
## listeners don't react recursively.
var _replay_depth: int = 0

## Emits the generic card-resolution combat event. Weapon systems and other
## listeners subscribe via SignalBus.card_hit_resolved — this pipeline stays
## mechanic-agnostic.
func _emit_card_hit_resolved(actor, target, info: Dictionary) -> void:
	if actor == null or target == null:
		return
	info["actor"] = actor
	info["target"] = target
	info["is_replay"] = info.get("is_replay", false) or _replay_depth > 0
	SignalBus.card_hit_resolved.emit(info)


## Re-runs a card resolution captured by a listener (e.g. a hit-echo weapon's
## ghost strike). Rebuilds a fresh context and calls the same effect function
## the original used, so damage_calculation / apply_state / weapon procs all
## run through the real pipeline.
func replay_card_resolution(info: Dictionary) -> void:
	var actor = info.get("actor")
	var card_cfg: CardConfig = info.get("card")
	var target = info.get("target")
	if not is_instance_valid(actor) or not is_instance_valid(target) or card_cfg == null:
		return
	if target is Battler and (target as Battler).is_defeated():
		return
	var allies_array: Array = []
	if battle_manager and battle_manager.players:
		for player in battle_manager.players:
			if is_instance_valid(player) and player is Battler and not (player as Battler).is_defeated():
				allies_array.append(player)
	if actor is Battler and actor not in allies_array:
		allies_array.append(actor)
	var context := {
		"card_config": card_cfg,
		"actor": actor,
		"target": target,
		"enemies": battle_manager.enemies if battle_manager else [],
		"allies": allies_array,
		"effect_manager": battle_manager.effect_manager if battle_manager else null,
		"qte_manager": qte_manager,
		"camera": battle_manager.battle_camera if battle_manager else null,
		"parent_node": self,
		"qte_multiplier": float(info.get("qte_multiplier", 1.0)),
		"skip_primary_effect": bool(info.get("skip_primary_effect", false)),
	}
	_replay_depth += 1
	match str(info.get("kind", "")):
		"effects":
			_execute_effects_immediate(card_cfg, context, float(info.get("qte_multiplier", 1.0)))
		"strike":
			apply_strike_damage_inline(context, float(info.get("damage_multiplier", 1.0)), float(info.get("qte_multiplier", 1.0)))
		"projectile":
			# Re-fire the real projectile visual; its impact re-applies damage
			# (at the echo fraction) through _apply_projectile_damage. The
			# is_replay flag rides through damage_data so the impact-time
			# resolution event is tagged even after _replay_depth resets.
			# aoe_targets (merged same-card resolutions) restores the AOE
			# execution context so one projectile hits every recorded target.
			var dmg_mult := float(info.get("damage_multiplier", 1.0))
			var aoe_targets: Array = info.get("aoe_targets", [])
			if card_cfg.projectile_enabled and not card_cfg.projectile_scene.is_empty():
				var ctx: BattleManager.AoeContext = null
				if card_cfg.projectile_aoe and not aoe_targets.is_empty():
					ctx = BattleManager.AoeContext.from_targets(aoe_targets)
					if ctx.targets.is_empty():
						ctx = null
				_travel_projectile(card_cfg, actor, target, dmg_mult, [], null, true, true, ctx)
			else:
				_apply_projectile_damage(card_cfg, actor, target, dmg_mult, aoe_targets, true)
	_replay_depth -= 1

## [param aoe]: an AOE cast's targets (every AOE card): the card resolves once,
## on all of them.
func play_card(card: CardConfig, target: Battler = null, aoe: BattleManager.AoeContext = null) -> bool:
	if is_executing_card or not can_play_card(card):
		return false
	
	if current_player_battler:
		var targets: Array = aoe.targets.duplicate() if aoe else [target]
		current_player_battler.notify_battle_event(BattleEvents.CARD_PLAYED, {"card": card, "target": target, "targets": targets, "battle_manager": battle_manager})
	
	is_executing_card = true
	if battle_manager:
		battle_manager.is_animating = true
		if battle_manager.hud and battle_manager.hud.has_method("set_ui_state"):
			battle_manager.hud.set_ui_state(3) # CARD_EXECUTION_STATE
	
	# Camera choreography, by who the card is aimed at (not its tags, which
	# also drive QTEs and visuals): a card on an enemy gets the wide shot, so
	# a melee attacker walking in stays in frame; a card on an ally or the
	# caster gets a close-up on them. Outranks targeting, so it shows as soon
	# as the card starts.
	var rig: BattleCamera = battle_manager.battle_camera if battle_manager else null
	if rig:
		var shot_target: Battler = target if is_instance_valid(target) else null
		var aims_at_enemy: bool
		if shot_target:
			aims_at_enemy = battle_manager.enemies.has(shot_target)
		else:
			aims_at_enemy = card.target_type in [CardConfig.TargetScope.SINGLE_ENEMY,
					CardConfig.TargetScope.ALL_ENEMIES, CardConfig.TargetScope.ALL_UNITS]
			# No target picked (e.g. a self card): frame the caster
			shot_target = current_player_battler if is_instance_valid(current_player_battler) else null
		# An AOE card (on any side) also gets the wide shot, framing every target
		if aims_at_enemy or aoe:
			rig.request_shot(&"execution", BattleCamera.ShotPriority.EXECUTION, BattleCamera.CameraMode.DEFAULT)
		elif shot_target:
			rig.request_shot(&"execution", BattleCamera.ShotPriority.EXECUTION, BattleCamera.CameraMode.TARGET_FOCUS, shot_target)
	
	# Execute card effect
	await execute_card_effect(card, target, aoe)
	
	# Spend AP only AFTER the effect resolves
	if current_player_battler:
		current_player_battler.spend_ap(get_card_ap_cost(card))
	
	# Remove from hand (move to graveyard through deck system)
	var deck = _get_current_deck()
	if deck:
		deck.discard_card(card)
	
	# Back to the turn's shot
	if rig:
		rig.release_shot(&"execution")
	
	is_executing_card = false
	if battle_manager:
		battle_manager.is_animating = false
	
	card_played.emit(card, target)
	
	return true

func execute_card_effect(card: CardConfig, target: Battler, aoe: BattleManager.AoeContext = null) -> void:
	if not target:
		return
	
	if not current_player_battler:
		return
	
	await execute_card_with_config(card, target, aoe)

## Execute card using the CardConfig system
func execute_card_with_config(card: CardConfig, target: Battler, aoe: BattleManager.AoeContext = null) -> void:
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

	# Expose the card's target on the battler so hit-frame callbacks
	# (hit_moment -> weapon system) know who was struck.
	if current_player_battler:
		current_player_battler.current_target = target

	# Spawn points this cast has used, shared by every strike/projectile of
	# it (strike contexts are shallow copies) so spread spawns stay apart
	var spawn_history: Array[Vector3] = []
	var context = {
		"card_config": card_cfg,
		"actor": current_player_battler,
		"target": target,
		"enemies": battle_manager.enemies if battle_manager else [],
		"allies": allies_array,
		"effect_manager": battle_manager.effect_manager if battle_manager else null,
		"qte_manager": qte_manager,
		"camera": battle_manager.battle_camera if battle_manager else null,
		"parent_node": self,
		"aoe": aoe,
		"spawn_history": spawn_history,
	}
	
	# Determine if this is an AOE effect
	var is_aoe = card_cfg.target_type in [CardConfig.TargetScope.ALL_ENEMIES, CardConfig.TargetScope.ALL_ALLIES, CardConfig.TargetScope.ALL_UNITS, CardConfig.TargetScope.ALL_ALLIES_SELF]
	
	# Phase 0: Movement Phase (for non-AOE enemy melee targeting)
	var should_return_to_position = false
	var is_ranged = card_cfg.projectile_enabled or "ranged" in card_cfg.card_tags
	if not is_aoe and not is_ranged and card_cfg.target_type == CardConfig.TargetScope.SINGLE_ENEMY and target:
		should_return_to_position = true  # Store decision before target might die
		if await current_player_battler.advance_to_target(target):
			current_player_battler._try_animation("walk")
			while current_player_battler.is_advancing:
				await get_tree().process_frame

	# The cast begins: cast sound, VFX on the caster
	_play_cast_feedback(card_cfg, context)

	# Phase 0.5: Check if multi-strike or single-strike
	if card_cfg.is_multi_strike:
		# Multi-strike execution: every strike applies its own damage at its own hit frame.
		await execute_multi_strike_sequence(card_cfg, context)
		# The sequence sets skip_primary_effect so the phase below cannot double-dip.
	else:
		# Single-strike execution (original flow)
		await execute_single_strike_sequence(card_cfg, context)

	# Fire-and-continue projectiles (e.g. multi-strike barrages) may still be in
	# the air: the card only resolves once every one has landed
	await _await_projectiles_landed()
	
	# Phase 3: Effect Phase (applies damage with QTE multiplier).
	# Single-strike cards run their effects from the hit callback and set
	# damage_applied_at_hit; multi-strike cards set skip_primary_effect. Either way the
	# primary damage is never applied twice here. Secondary effects / states still resolve.
	await execute_effect_phase(card_cfg, context)
	
	# Phase 6: Return Movement (for non-AOE enemy targeting)
	# Use stored decision instead of checking target (target may have died)
	if should_return_to_position:
		if current_player_battler.has_method("return_to_original_position"):
			current_player_battler.return_to_original_position()
			while current_player_battler.is_advancing:
				await get_tree().process_frame

	# Phase 10: Return the actor to its battle idle once the card fully resolves.
	if current_player_battler and current_player_battler.has_method("battle_idle"):
		current_player_battler.battle_idle()

## Execute animation phase with hit moment damage application
func execute_animation_phase_with_hit_timing(card_cfg: CardConfig, context: Dictionary) -> void:
	var actor = context["actor"]
	if not actor:
		return
	
	var animation_name = card_cfg.animation_name
	
	if not animation_name.is_empty():
		# Resolve animation name through character's animation mapping if available
		if actor.has_method("get_resolved_animation"):
			animation_name = actor.get_resolved_animation(animation_name)
		
		# Start the animation
		var animation_start := Time.get_ticks_msec() / 1000.0
		if actor.has_method("_try_animation"):
			actor._try_animation(animation_name)
		var anim_duration: float = 0.0
		if actor.has_method("_get_animation_duration"):
			anim_duration = actor._get_animation_duration(animation_name)

		# Wait a few frames for the state machine to process the transition
		await get_tree().process_frame
		await get_tree().process_frame

		# For projectile cards, launch projectile at hit moment (damage applied on impact)
		# For non-projectile cards, apply damage at hit moment. A clip without
		# a hit frame times out: the card then resolves after the animation
		# (execute_effect_phase), instead of hanging.
		if await _await_hit_moment(actor, anim_duration):
			_play_hit_frame_feedback(card_cfg, context)

			# The hit settles this card's QTE (still running = no press in time)
			if context.get("qte_started", false) and qte_manager:
				var qte_result := qte_manager.resolve_qte()
				context["qte_success"] = qte_result
				context["qte_success_set"] = true
				context["qte_multiplier"] = qte_manager.get_card_multiplier(card_cfg, qte_result)

			if card_cfg.projectile_enabled:
				await launch_projectile_and_await_impact(card_cfg, context)
				# The projectiles dealt the primary damage; the card's states and
				# secondary effects resolve now that they've landed
				_apply_projectile_followup_effects(card_cfg, context)
			else:
				await execute_effect_phase(card_cfg, context, true)
			context["damage_applied_at_hit"] = true
			_play_impact_feedback(card_cfg, context)

			# Stop the animation if everyone the cast hit died
			if _cast_targets(context).is_empty():
				return

		# Wait out what is left of the clip (it started at animation_start)
		var remaining := anim_duration - (Time.get_ticks_msec() / 1000.0 - animation_start)
		if remaining > 0.0:
			await get_tree().create_timer(remaining).timeout


## Waits for [param actor]'s next hit_moment, giving up after its clip
## ([param clip_length] seconds, plus a margin): a clip without a hit frame
## must not hang the card. Resumes right at the hit (inside its emission), like
## awaiting the signal itself. Returns whether the hit came.
func _await_hit_moment(actor: Node, clip_length: float) -> bool:
	if actor == null or not actor.has_signal("hit_moment"):
		return false
	var race := _HitRace.new()
	var on_hit := func(_attacker): race.finish(true)
	actor.hit_moment.connect(on_hit, CONNECT_ONE_SHOT)
	var timeout := (clip_length if clip_length > 0.05 else 4.0) + 1.0
	get_tree().create_timer(timeout).timeout.connect(race.finish.bind(false))
	var hit: bool = await race.finished
	if not hit and is_instance_valid(actor) and actor.hit_moment.is_connected(on_hit):
		actor.hit_moment.disconnect(on_hit)
	return hit


## First of two outcomes (the hit, or the timeout) wins; later ones are ignored.
class _HitRace extends RefCounted:
	signal finished(hit: bool)
	var _done := false

	func finish(hit: bool) -> void:
		if _done:
			return
		_done = true
		finished.emit(hit)


## Execute effect phase
func execute_effect_phase(card_cfg: CardConfig, context: Dictionary, from_animation_callback: bool = false) -> void:
	var actor = context["actor"]
	var target = context["target"]
	var _enemies = context["enemies"]
	var _allies = context["allies"]
	
	# Skip if damage was already applied at hit moment
	if context.get("damage_applied_at_hit", false):
		return
	
# Apply QTE multiplier if present
	var qte_multiplier = context.get("qte_multiplier", 1.0)
	
	# The card resolves now: at its hit frame (the animation callback), after
	# its strikes (their states and secondary effects), or once its animation
	# ended without a hit frame
	_resolve_on_cast_targets(card_cfg, context, qte_multiplier)
	if not from_animation_callback and not context.get("skip_primary_effect", false):
		_play_impact_feedback(card_cfg, context)

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
	
	# States roll their own chance (and check immunity) when applied: a missed
	# state never stops the rest of the card
	return true

## Execute single-strike sequence (original flow)
func execute_single_strike_sequence(card_cfg: CardConfig, context: Dictionary) -> void:
	var actor = context["actor"]

	# Phase 0.5: Start QTE early (before animation) if card has QTE
	if qte_manager and qte_manager.wants_card_qte(card_cfg):
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
		context["qte_started"] = qte_manager.start_card_qte(card_cfg, qte_window)
		
		# Delay animation start if needed
		if anim_delay > 0:
			await get_tree().create_timer(anim_delay).timeout
	
	# Phase 1: Animation Phase with hit timing
	await execute_animation_phase_with_hit_timing(card_cfg, context)

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
		# Abort the combo once an earlier strike defeated every target
		if _cast_targets(context).is_empty():
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

		if actor is Battler:
			actor.chaining_strikes = has_next_strike
		await execute_single_strike_inline(strike_context)
		if actor is Battler and is_instance_valid(actor):
			actor.chaining_strikes = false
		
		# Track QTE success for cumulative effect
		if strike_context.get("qte_success_set", false):
			var strike_qte_success = strike_context.get("qte_success", false)
			if not strike_qte_success:
				total_qte_success = false
			# The card's own QTE multipliers, else the QTE config's
			var strike_multiplier := 1.0
			if qte_manager:
				strike_multiplier = qte_manager.get_card_multiplier(card_cfg, strike_qte_success)
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
	var qte_started := false

	# Seconds trimmed from this strike's clip so the NEXT strike chains in early.
	# Only used when another strike follows (set by execute_multi_strike_sequence).
	var chain_lead = context.get("chain_lead", 0.0) if context.get("has_next_strike", false) else 0.0
	
	# Start QTE for this strike (if card QTEs are enabled)
	if qte_window > 0 and qte_manager and qte_manager.is_enabled():
		var hit_moment_time = 0.0
		if actor.has_method("_get_hit_moment_time"):
			hit_moment_time = actor._get_hit_moment_time(animation_name)
		
		# Calculate QTE timing for this strike
		var anim_delay := 0.0
		
		if qte_window > hit_moment_time:
			anim_delay = qte_window - hit_moment_time
		
		# Start QTE immediately
		qte_started = qte_manager.start_qte(QTEManager.QTEType.CARD_ATTACK, qte_difficulty, qte_window)
		
		# Delay animation start if needed
		if anim_delay > 0:
			await get_tree().create_timer(anim_delay).timeout
	
	# Play animation with hit timing
	var animation_start_time := Time.get_ticks_msec() / 1000.0
	if actor.has_method("_try_animation"):
		actor._try_animation(animation_name)
	var clip_length = _get_strike_clip_length(actor, animation_name)
	var strike_card: CardConfig = context.get("card_config")

	# Wait for hit moment signal (a strike clip without one times out)
	if await _await_hit_moment(actor, clip_length):
		_play_hit_frame_feedback(strike_card, context)

		# The hit settles this strike's QTE (still running = no press in time).
		# Its multiplier comes from the project's QTE config; no QTE on this
		# strike = no modifier
		var strike_multiplier := 1.0
		if qte_started:
			var qte_result := qte_manager.resolve_qte()
			context["qte_success"] = qte_result
			context["qte_success_set"] = true
			strike_multiplier = qte_manager.get_card_multiplier(context.get("card_config"), qte_result)

		var _strike_card_cfg: CardConfig = context.get("card_config")
		if _strike_card_cfg and _strike_card_cfg.projectile_enabled:
			# Projectile handles its own damage on impact
			var wait_for_impact: bool = _strike_card_cfg.projectile_wait_for_impact if "projectile_wait_for_impact" in _strike_card_cfg else true
			var spawn_history: Array[Vector3] = []
			if context.get("spawn_history") is Array:
				spawn_history = context["spawn_history"]
			var aims := _projectile_aims(_strike_card_cfg, context)
			# All but the last fly on their own; the last one is waited on
			for i in aims.size() - 1:
				_travel_projectile(_strike_card_cfg, actor, aims[i], damage_multiplier * strike_multiplier,
						spawn_history, null, wait_for_impact, false, context.get("aoe"))
			if not aims.is_empty():
				await _travel_projectile(_strike_card_cfg, actor, aims[-1], damage_multiplier * strike_multiplier,
						spawn_history, null, wait_for_impact, false, context.get("aoe"))
		else:
			apply_strike_damage_inline(context, damage_multiplier, strike_multiplier)
		context["damage_applied_at_hit"] = true
		_play_impact_feedback(strike_card, context)
	
	# Mid-combo: the next strike takes over once this swing's attack is done
	# (its _on_attack_end key, `chain_lead` early), cutting its recovery instead
	# of playing it out. Timed by the clip's own clock (hit-stop freezes it).
	if context.get("has_next_strike", false) and actor is Battler:
		var release: float = actor.get_strike_release_time(animation_name, chain_lead)
		await actor.await_attack_clip_time(animation_name, release, clip_length + 2.0)
		return

	# Last strike: wait out the rest of its clip before the post-combat transition.
	# Timing is anchored to animation_start_time so the wait is always correct
	# regardless of how long damage_calculation takes.
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
	var card_cfg = context["card_config"]

	# Calculate damage from primary effect
	if card_cfg.primary_effect and battle_manager:
		var base_value = card_cfg.primary_effect._calculate_value(actor)
		var strike_damage = int(base_value * damage_multiplier * qte_multiplier)
		var dmg_type = card_cfg.primary_effect.damage_type if "damage_type" in card_cfg.primary_effect else "physical"
		var elem = card_cfg.primary_effect.element if "element" in card_cfg.primary_effect else "none"
		# Every living target of the cast (none freed mid-combo) is hit at once;
		# the last one's hit reaction is waited out
		var targets := _cast_targets(context)
		for i in targets.size():
			var t = targets[i]
			# Generic combat event — listeners (echo weapons, etc.) may replay it.
			# Sent at the hit frame, before the damage await (which waits out the
			# hit reaction): listeners pair it with this hit's hit_moment, and a
			# replay is still inside replay_card_resolution so it gets tagged.
			_emit_card_hit_resolved(actor, t, {
				"kind": "strike",
				"card": card_cfg,
				"strike_index": int(context.get("strike_index", 0)),
				"damage_multiplier": damage_multiplier,
				"qte_multiplier": qte_multiplier,
			})
			var crit: float = card_cfg.primary_effect.roll_crit_multiplier(actor)
			if i == targets.size() - 1:
				await battle_manager.damage_calculation(actor, t, strike_damage, null, dmg_type, elem, true, crit)
			else:
				battle_manager.damage_calculation(actor, t, strike_damage, null, dmg_type, elem, true, crit)

## Every living battler the cast resolves on: all of an AOE cast's targets,
## else its one target.
func _cast_targets(context: Dictionary) -> Array:
	var aoe: BattleManager.AoeContext = context.get("aoe")
	var list: Array = aoe.targets if aoe else [context.get("target")]
	return list.filter(func(t): return is_instance_valid(t) and not (t is Battler and (t as Battler).is_defeated()))


## Resolves the card's effects and states on every target of the cast, each
## gated by the card's conditions for that target. Self states land once.
func _resolve_on_cast_targets(card_cfg: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	var per_target := context.duplicate()
	var self_states_done := bool(context.get("skip_self_states", false))
	for t in _cast_targets(context):
		per_target["target"] = t
		if not check_card_conditions(card_cfg, per_target):
			continue
		per_target["skip_self_states"] = self_states_done
		_execute_effects_immediate(card_cfg, per_target, qte_multiplier)
		self_states_done = true


## The cast's projectile aims: its target, or, for an AOE card whose
## projectile hits one battler (not projectile_aoe), each of its targets.
## (A projectile_aoe projectile flies to the AOE center and hits them all.)
func _projectile_aims(card_cfg: CardConfig, context: Dictionary) -> Array:
	if context.get("aoe") and not card_cfg.projectile_aoe:
		return _cast_targets(context)
	return [context.get("target")]


## Applies [param effect] from [param actor] (on [param target], or the actor
## for an ACTOR effect) with its scaled value times [param multiplier]. Not
## awaited: the effect resolves on its own, like a hit landing.
func _apply_card_effect(effect: CardEffect, actor, target, multiplier: float) -> void:
	if battle_manager == null:
		return
	var recipient = effect.get_recipient(actor, target)
	if recipient is Battler:
		effect.apply_to(actor, recipient, int(effect._calculate_value(actor) * multiplier), battle_manager)


## Applies the card's effects to the context's target (one target: see
## [method _resolve_on_cast_targets])
func _execute_effects_immediate(card_cfg: CardConfig, context: Dictionary, qte_multiplier: float) -> void:
	var actor = context["actor"]
	var target = context["target"]
	var enemies = context["enemies"]
	var allies = context["allies"]
	
	# Execute primary effect (scaled by the QTE). Multi-strike cards deal their
	# damage per strike and set skip_primary_effect, so it never lands twice.
	if card_cfg.primary_effect and not context.get("skip_primary_effect", false):
		_apply_card_effect(card_cfg.primary_effect, actor, target, qte_multiplier)

	# Execute secondary effects
	for effect in card_cfg.secondary_effects:
		if effect and effect._check_conditions(actor, target):
			_apply_card_effect(effect, actor, target, 1.0)
	
	# Apply states (each rolls its chance and checks immunity once, in apply_state)
	for state_cfg in card_cfg.applies_states:
		state_cfg.apply_state(target, actor)
	
	# Apply self states
	for self_state_cfg in card_cfg.applies_self_states:
		if context.get("skip_self_states", false):
			break
		self_state_cfg.apply_state(actor, actor)
			
	# Update health bars only (don't call update_hud during card execution)
	if battle_manager and battle_manager.hud:
		battle_manager.hud.update_health_bars()
	
	# Generic combat event — listeners (echo weapons, etc.) may replay it.
	_emit_card_hit_resolved(actor, target, {
		"kind": "effects",
		"card": card_cfg,
		"qte_multiplier": qte_multiplier,
		"skip_primary_effect": context.get("skip_primary_effect", false),
	})

## The cast begins: cast sound and VFX on the caster.
func _play_cast_feedback(card_cfg: CardConfig, context: Dictionary) -> void:
	var actor = context.get("actor")
	if not is_instance_valid(actor):
		return
	if card_cfg.cast_sound:
		card_cfg.cast_sound.play_audio(self, actor.global_position)
	if card_cfg.vfx_on_actor:
		var vfx = card_cfg.vfx_on_actor.spawn_vfx(actor.global_position, actor)
		if vfx:
			get_tree().current_scene.add_child(vfx)


## The animation's hit frame (a swing connecting, a projectile leaving).
func _play_hit_frame_feedback(card_cfg: CardConfig, context: Dictionary) -> void:
	var target = context.get("target")
	if card_cfg.hit_sound and is_instance_valid(target):
		card_cfg.hit_sound.play_audio(self, target.global_position)


## The card's effect landed (at the hit frame, or when its projectiles hit):
## impact sound and VFX on every target, camera and screen effects.
func _play_impact_feedback(card_cfg: CardConfig, context: Dictionary) -> void:
	var targets := _cast_targets(context)
	if card_cfg.impact_sound and not targets.is_empty():
		card_cfg.impact_sound.play_audio(self, targets[0].global_position)
	if card_cfg.vfx_on_target:
		for t in targets:
			var vfx = card_cfg.vfx_on_target.spawn_vfx(t.global_position, t)
			if vfx:
				get_tree().current_scene.add_child(vfx)
	var camera = context.get("camera")
	if card_cfg.camera_effects and camera:
		card_cfg.camera_effects.apply_camera_effects(camera, context.get("actor"), context.get("target"))
	var effect_manager = context.get("effect_manager")
	if card_cfg.screen_effects and effect_manager:
		card_cfg.screen_effects.apply_screen_effect(effect_manager)

func draw_card_for_deck(deck: SimplifiedDeck) -> CardConfig:
	if not deck:
		push_warning("CardBattleManager: draw_card_for_deck called with a null deck")
		return null
	
	# If draw pile is empty, recycle graveyard back into draw pile and shuffle
	if deck.draw_pile.is_empty() and not deck.graveyard.is_empty():
		deck.recycle_graveyard()
	
	var drawn_card = deck.draw_card()
	return drawn_card

func start_player_turn() -> void:
	# Always sync to the currently acting player from battle_manager
	if battle_manager and is_instance_valid(battle_manager.current_character):
		current_player_battler = battle_manager.current_character
	
	# Refresh AP on active player battler
	if current_player_battler:
		current_player_battler.regen_ap()
	
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
		
		# Draw a fresh hand: initial_hand_size plus passive bonuses
		var hand_size: int = card_battle_config.initial_hand_size if card_battle_config else 3
		if current_player_battler:
			hand_size += current_player_battler.get_bonus(&"cards_drawn_per_turn")
			if _opening_hand_pending.get(current_player_battler, false):
				_opening_hand_pending.erase(current_player_battler)
				hand_size += current_player_battler.get_bonus(&"starting_hand_size")
		for _i in range(hand_size):
			draw_card_for_deck(deck)
	
# --- Step 3: Update CardUI display for the new hand and notify HUD ---
	if battle_manager and battle_manager.hud:
		if card_ui:
			# The old hand was discarded (discard_hand_to_pile), so the whole new hand draws in
			if card_ui.has_method("update_hand_display"):
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
	
	turn_ended.emit()
	if battle_manager:
		battle_manager.end_turn()

func _relay_ap_changed(current_ap: int, max_ap: int) -> void:
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
	return {
		"current_ap": 0,
		"max_ap": 0,
		"ap_percentage": 0.0
	}

## Travel a single projectile scene from [param actor] to [param target] and await arrival.
## Applies damage on impact. Handles multi-strike and multi-projectile correctly.
## [param used_spawn_positions] the spawn points already used this cast (a
##   spread spawn is picked away from them, then added)
## [param spawn_at] a precomputed spawn point (simultaneous volleys), or null
## [param wait_for_impact] if true, waits for projectile to hit; if false, returns after launch
## [param aoe] the cast's AOE context: aim at its center and hit all its targets
func _travel_projectile(card_cfg: CardConfig, actor: Node3D, target: Node3D, damage_multiplier: float = 1.0, used_spawn_positions: Array[Vector3] = [], spawn_at: Variant = null, wait_for_impact: bool = true, is_replay: bool = false, aoe: BattleManager.AoeContext = null) -> void:
	if card_cfg.projectile_scene.is_empty() or not ResourceLoader.exists(card_cfg.projectile_scene):
		push_error("BattleProjectile: projectile_scene not found — " + card_cfg.projectile_scene)
		return
	if not is_instance_valid(actor) or not is_instance_valid(target):
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

	# Spawn in front of the actor (toward the other side of the battle axis),
	# spread over a disc facing that way if the card asks for it
	var spawn_pos: Vector3
	if spawn_at is Vector3:
		spawn_pos = spawn_at
	else:
		spawn_pos = _spread_spawn_position(card_cfg, actor, used_spawn_positions)

	# Determine target position - use center for AOE projectiles
	var base_hit_pos: Vector3
	var is_aoe_projectile: bool = card_cfg.projectile_aoe and aoe != null and not aoe.targets.is_empty()
	if is_aoe_projectile:
		base_hit_pos = _aoe_pierce_end(spawn_pos, _projectile_forward(actor), aoe)
	else:
		base_hit_pos = target.global_position + Vector3(0, 1.0, 0)

	# Trajectory spread randomizes the PATH, not the target position
	# Projectiles always reach the target but take slightly different curved paths
	var trajectory_spread: float = card_cfg.projectile_trajectory_spread if "projectile_trajectory_spread" in card_cfg else 0.0
	var hit_pos = base_hit_pos

	# A fresh container per shot (freed once its impact resolves)
	var battle_proj := BattleProjectile.new()
	get_tree().current_scene.add_child(battle_proj)
	battle_proj.global_position = spawn_pos

	# Instantiate projectile VFX as child of container
	var proj_vfx: Node3D = proj_res.instantiate()
	battle_proj.add_child(proj_vfx)
	proj_vfx.position = Vector3.ZERO  # Relative to container
	proj_vfx.scale = card_cfg.projectile_scale if "projectile_scale" in card_cfg else Vector3.ONE

	# AOE projectile: one projectile hits every target of the cast
	var aoe_targets: Array = aoe.targets.duplicate() if is_aoe_projectile else []
	battle_proj.damage_data = {
		"actor": actor,
		"target": target,
		"card_cfg": card_cfg,
		"damage_multiplier": damage_multiplier,
		"aoe_targets": aoe_targets,
		"is_replay": is_replay,
	}

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
	battle_proj.lifetime = card_cfg.projectile_lifetime
	battle_proj.battle_manager = battle_manager
	battle_proj.launch(spawn_pos, hit_pos, battle_proj.speed, battle_proj.arc_height)
	if is_aoe_projectile:
		# Sweeps through every target, hitting each as it reaches them
		battle_proj.set_pierce_targets(aoe_targets, _projectile_forward(actor))

	# If VFX child has play method, play open animation on spawn
	if proj_vfx.has_method("play"):
		proj_vfx.play()

	# The one impact path, whether or not the caller waits for it
	_projectiles_in_flight += 1
	_resolve_projectile_on_arrival(battle_proj, proj_vfx)

	if wait_for_impact:
		await battle_proj.resolved
	else:
		# Fire-and-continue (multi-strike): pace the next strike instead
		var strike_delay: float = card_cfg.projectile_strike_delay if "projectile_strike_delay" in card_cfg else 0.3
		if strike_delay > 0:
			await get_tree().create_timer(strike_delay / _battle_speed()).timeout


## Waits for [param battle_proj] to arrive, then resolves its impact exactly
## once: stop the VFX, apply damage, spawn the target impact VFX, mark it
## landed, then let the VFX play out before freeing it. Every projectile
## goes through here.
func _resolve_projectile_on_arrival(battle_proj: BattleProjectile, proj_vfx: Node3D) -> void:
	var data: Dictionary = battle_proj.damage_data
	var card_cfg: CardConfig = data.get("card_cfg")
	var pierce: Array = data.get("aoe_targets", [])
	if card_cfg and not pierce.is_empty():
		# AOE: each target is hit as the projectile passes it (all are passed
		# by the time it arrives)
		battle_proj.passed_target.connect(func(t): _projectile_hit(data, t))
	await battle_proj.arrived

	if is_instance_valid(proj_vfx) and proj_vfx.has_method("stop"):
		proj_vfx.stop()

	if card_cfg and pierce.is_empty():
		_projectile_hit(data, data.get("target"))

	_projectiles_in_flight = maxi(0, _projectiles_in_flight - 1)
	if is_instance_valid(battle_proj):
		battle_proj.resolved.emit()
		_free_after_fade(battle_proj, proj_vfx)


## One target struck by a projectile: damage plus the card's impact VFX.
func _projectile_hit(data: Dictionary, target) -> void:
	var card_cfg: CardConfig = data.get("card_cfg")
	if not card_cfg or not is_instance_valid(target):
		return
	_apply_projectile_damage(card_cfg, data.get("actor"), target,
			float(data.get("damage_multiplier", 1.0)), [], bool(data.get("is_replay", false)))
	if card_cfg.vfx_on_target:
		var vfx = card_cfg.vfx_on_target.spawn_vfx(target.global_position, target)
		if vfx:
			get_tree().current_scene.add_child(vfx)


## Where an AOE projectile from [param from] ends: heading for the targets'
## center, carried on until it is a metre past the deepest target along
## [param forward] (the attack's direction across the battle axis), at the
## center's height, so it sweeps across all of them.
func _aoe_pierce_end(from: Vector3, forward: Vector3, aoe: BattleManager.AoeContext) -> Vector3:
	forward.y = 0.0
	forward = forward.normalized()
	var dir := aoe.center_position - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else forward
	var depth := 0.0
	for t in aoe.targets:
		if is_instance_valid(t):
			var offset: Vector3 = t.global_position - from
			offset.y = 0.0
			depth = maxf(depth, offset.dot(forward))
	# Flight length whose forward component reaches depth + 1 (a steep sideways
	# heading is capped so the slash can't fly off for miles)
	var length := (depth + 1.0) / maxf(dir.dot(forward), 0.3)
	var end := from + dir * length
	end.y = aoe.center_position.y
	return end


## Longest a spent projectile may linger to finish its VFX (seconds at 1x).
const _MAX_PROJECTILE_FADE := 3.0

## Frees [param battle_proj] once its stopped VFX has played out: the close
## animation, the particles already emitted, and trails shrinking away. The
## card doesn't wait for this (its impact has already resolved).
func _free_after_fade(battle_proj: BattleProjectile, proj_vfx: Node3D) -> void:
	var linger := 0.0
	if is_instance_valid(proj_vfx):
		var anim: AnimationPlayer = proj_vfx.get("anim") as AnimationPlayer
		if anim and anim.has_animation("close"):
			linger = anim.get_animation("close").length
		for p in proj_vfx.find_children("*", "GPUParticles3D", true, false):
			linger = maxf(linger, (p as GPUParticles3D).lifetime)
		for trail in proj_vfx.find_children("*", "MeshInstance3D", true, false):
			if "points" in trail and "lifetime" in trail:
				linger = maxf(linger, float(trail.lifetime))
	linger = minf(linger, _MAX_PROJECTILE_FADE)
	var waited := 0.0
	while waited < linger and is_instance_valid(battle_proj):
		await get_tree().process_frame
		waited += get_process_delta_time() * _battle_speed()
	if is_instance_valid(battle_proj):
		battle_proj.queue_free()


## Battle speed (hold Space), for scaling waits.
func _battle_speed() -> float:
	if battle_manager and battle_manager.speed_multiplier > 0.0:
		return battle_manager.speed_multiplier
	return 1.0


## Waits until every launched projectile has resolved its impact. The
## projectiles' own lifetime forces arrival, so this only times out if a
## projectile node was freed mid-flight; then the count is reset.
func _await_projectiles_landed(timeout: float = 10.0) -> void:
	var waited := 0.0
	while _projectiles_in_flight > 0:
		if waited >= timeout:
			push_warning("CardBattleManager: %d projectile(s) never resolved; continuing" % _projectiles_in_flight)
			_projectiles_in_flight = 0
			return
		await get_tree().process_frame
		waited += get_process_delta_time()


## Direction projectiles leave [param actor] in: toward the other side along
## the battle axis (battlers face +Z), falling back to the actor's own +Z.
func _projectile_forward(actor: Node3D) -> Vector3:
	var rig: BattleCamera = battle_manager.battle_camera if battle_manager else null
	if rig and actor is Battler:
		return rig.get_side_basis(actor).z
	var z := actor.global_transform.basis.z
	z.y = 0.0
	return z.normalized() if z.length_squared() > 0.0001 else Vector3.BACK

## States and secondary effects of a single-strike projectile card, once its
## projectiles have landed (they only deal the primary damage). Runs for the
## card's target, or every target of an AOE projectile.
func _apply_projectile_followup_effects(card_cfg: CardConfig, context: Dictionary) -> void:
	if card_cfg.secondary_effects.is_empty() and card_cfg.applies_states.is_empty() \
			and card_cfg.applies_self_states.is_empty():
		return
	var followup := context.duplicate()
	followup["skip_primary_effect"] = true
	_resolve_on_cast_targets(card_cfg, followup, float(context.get("qte_multiplier", 1.0)))

## Apply damage from projectile impact
func _apply_projectile_damage(card_cfg: CardConfig, actor: Node3D, target: Node3D, damage_multiplier: float, aoe_targets: Array = [], is_replay: bool = false) -> void:
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
		battle_manager.damage_calculation(actor, t, final_val, null, dmg_type, elem, true, card_cfg.primary_effect.roll_crit_multiplier(actor))
		# Generic combat event — listeners (echo weapons, etc.) may replay it.
		_emit_card_hit_resolved(actor, t, {
			"kind": "projectile",
			"card": card_cfg,
			"damage_multiplier": damage_multiplier,
			"is_replay": is_replay,
		})

## Spawn point for one projectile of [param card_cfg]: 0.5 m in front of the
## actor at chest height, offset across a disc of radius projectile_spawn_spread
## that faces the other side. Among a dozen random candidates it takes the one
## farthest from [param used_positions] (the cast's earlier spawns), so a
## volley fans out instead of clumping, then records it there. Spawns never
## dip below 0.3 m above the actor's feet.
func _spread_spawn_position(card_cfg: CardConfig, actor: Node3D, used_positions: Array[Vector3]) -> Vector3:
	var forward := _projectile_forward(actor)
	var base := actor.global_position + forward * 0.5 + Vector3(0, 1.2, 0)
	var radius := card_cfg.projectile_spawn_spread
	if radius <= 0.0:
		return base
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var floor_y := actor.global_position.y + 0.3
	var min_sep := maxf(_MIN_SPAWN_SEPARATION, radius * 0.2)
	var best := base
	var best_gap := -1.0
	for attempt in 12:
		# sqrt(randf()) spreads candidates evenly over the disc's area
		var angle := randf() * TAU
		var r := sqrt(randf()) * radius
		var offset := (right * cos(angle) + up * sin(angle)) * r
		var candidate := base + offset
		if candidate.y < floor_y:
			# Mirror below-floor points up (keeps the spread, loses no area)
			candidate.y = floor_y + (floor_y - candidate.y)
		var gap := INF
		for used in used_positions:
			gap = minf(gap, candidate.distance_to(used))
		if gap > best_gap:
			best = candidate
			best_gap = gap
		if gap >= min_sep * 2.0:
			break  # comfortably clear; no need to keep looking
	used_positions.append(best)
	return best

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
	var qte_multiplier := context.get("qte_multiplier", 1.0) as float

	# --- Determine projectile count and discard hand cards if needed -------
	var hand_multiplier := 1
	if card_cfg.primary_effect and card_cfg.primary_effect.consume_hand_cards:
		var deck := _get_current_deck()
		if deck:
			var other_cards: Array[CardConfig] = []
			for c in deck.get_hand():
				# Every other card in hand: only this copy is excluded (deck
				# copies are distinct instances, so a second Salvo is consumed)
				if c != card_cfg:
					other_cards.append(c)
			hand_multiplier = max(1, other_cards.size())
			for c in other_cards:
				deck.discard_card(c)

	# --- Fire projectiles (configurable stagger or simultaneous) -------------
	var fire_simultaneously: bool = card_cfg.projectile_fire_simultaneously if "projectile_fire_simultaneously" in card_cfg else false
	
	# Spawn points already used this cast, so spread spawns stay apart
	var used_spawn_positions: Array[Vector3] = []
	if context.get("spawn_history") is Array:
		used_spawn_positions = context["spawn_history"]
	var aoe: BattleManager.AoeContext = context.get("aoe")

	# Every projectile of the cast: hand_multiplier per aim
	var shots: Array = []
	for i in hand_multiplier:
		shots.append_array(_projectile_aims(card_cfg, context))

	if fire_simultaneously:
		# Pick every spawn point first (each away from the ones before it)
		var spawns: Array[Vector3] = []
		for i in shots.size():
			spawns.append(_spread_spawn_position(card_cfg, actor, used_spawn_positions))

		# Fire all at once, no waiting between projectiles
		for i in shots.size():
			_travel_projectile(card_cfg, actor, shots[i], qte_multiplier, used_spawn_positions, spawns[i], true, false, aoe)
		# Wait for every projectile of the volley to land
		await _await_projectiles_landed()
	else:
		# Fire with staggered delays
		for i in shots.size():
			if i > 0:
				await get_tree().create_timer(0.15 / _battle_speed()).timeout
			await _travel_projectile(card_cfg, actor, shots[i], qte_multiplier, used_spawn_positions, null, true, false, aoe)
