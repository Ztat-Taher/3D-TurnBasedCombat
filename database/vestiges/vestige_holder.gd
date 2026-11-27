class_name VestigeHolder
extends RefCounted
## The vestiges one battler carries into a battle: its party member's own
## (per-character) vestiges plus the party-wide (global) ones.
##
## This is the battler's only entry point to the vestige system. The battler
## asks it for stat modifiers, multipliers and bonuses, and forwards battle
## events to it; everything vestige-specific (which fields mean what, which
## event fires which trigger, how stacks combine) lives here and in the vestige
## resources, never in the battle, card or battler code.
##
## Adding a vestige-driven stat, multiplier or trigger means editing
## [constant STAT_FIELDS], a [Vestige] field, or [constant EVENT_TRIGGERS].

## Battle events ([BattleEvents]) -> the vestige trigger each one fires.
const EVENT_TRIGGERS := {
	BattleEvents.COMBAT_START: TriggerHook.TriggerType.ON_COMBAT_START,
	BattleEvents.COMBAT_END: TriggerHook.TriggerType.ON_COMBAT_END,
	BattleEvents.TURN_START: TriggerHook.TriggerType.ON_TURN_START,
	BattleEvents.TURN_END: TriggerHook.TriggerType.ON_TURN_END,
	BattleEvents.CARD_PLAYED: TriggerHook.TriggerType.ON_CARD_PLAY,
	BattleEvents.DAMAGE_TAKEN: TriggerHook.TriggerType.ON_DAMAGE_TAKEN,
	BattleEvents.DAMAGE_DEALT: TriggerHook.TriggerType.ON_DAMAGE_DEALT,
	BattleEvents.LETHAL_DAMAGE: TriggerHook.TriggerType.ON_LETHAL_DAMAGE,
	BattleEvents.HEALED: TriggerHook.TriggerType.ON_HEAL,
	BattleEvents.STATE_APPLIED: TriggerHook.TriggerType.ON_STATE_APPLIED,
	BattleEvents.STATE_REMOVED: TriggerHook.TriggerType.ON_STATE_REMOVED,
	BattleEvents.STATE_INFLICTED: TriggerHook.TriggerType.ON_STATE_INFLICTED,
	BattleEvents.ENEMY_DEFEATED: TriggerHook.TriggerType.ON_ENEMY_DEFEAT,
}

## HP threshold triggers (fired by [constant BattleEvents.HEALTH_CHANGED] when
## HP crosses the hook's [member TriggerHook.hp_threshold]) -> true for "dropped below".
const HP_THRESHOLD_TRIGGERS := {
	TriggerHook.TriggerType.ON_LOW_HP: true,
	TriggerHook.TriggerType.ON_HIGH_HP: false,
}

## How deep vestige reactions may chain (an effect's damage triggering
## another hook, and so on) before further triggers are ignored. Stops loops
## such as "on damage dealt, deal damage".
const MAX_CHAIN_DEPTH := 3

## The carried vestiges changed (after [method reload]); for displays.
signal changed

## Battler stat -> the [Vestige] fields that modify it: [flat, percent of
## base] (an empty name = no such field).
const STAT_FIELDS := {
	&"max_health": [&"max_health_bonus", &"max_health_percent"],
	&"attack": [&"attack_bonus", &"attack_percent"],
	&"defense": [&"defense_bonus", &"defense_percent"],
	&"agility": [&"agility_bonus", &"agility_percent"],
	&"max_ap": [&"max_ap_bonus", &""],
	&"ap_regen_per_turn": [&"ap_regen_bonus", &""],
}

var _battler: Battler
## [{vestige: Vestige, stacks: int}], one entry per distinct vestige
var _entries: Array[Dictionary] = []
## stat -> delta granted for the current combat only (e.g. a combat-start
## buff). Part of the stat pipeline, so stat recalculations keep it.
var _combat_modifiers: Dictionary = {}
## Per-combat scratch state for this battler (hook/effect -> Dictionary);
## see [method get_combat_memory]. Cleared when a combat starts.
var _combat_memory: Dictionary = {}
## Between combat start and combat end (HP changes outside combat, e.g. stat
## setup, trigger nothing).
var _in_combat := false
## Current nesting of [method _fire] calls (see [constant MAX_CHAIN_DEPTH]).
var _chain_depth := 0


func _init(battler: Battler) -> void:
	_battler = battler


# ─────────────────────────────────────────────────────────────────────────────
# Owned vestiges
# ─────────────────────────────────────────────────────────────────────────────

## Re-reads the vestiges from the run: the battler's party member (by its
## [constant AllyPartyMember.META_PARTY_MEMBER_ID] meta) and the party-wide
## ones. Battlers with no party member (enemies) carry none.
func reload() -> void:
	_entries.clear()
	var member_id := str(_battler.get_meta(AllyPartyMember.META_PARTY_MEMBER_ID, ""))
	if member_id.is_empty():
		changed.emit()
		return
	var member := GameState.get_party_member(member_id)
	if member:
		for vestige in member.vestiges:
			if vestige and vestige.scope == Vestige.Scope.PER_CHARACTER:
				_add(vestige, member.get_vestige_stack_count(vestige.vestige_id))
	for vestige in GameState.get_global_vestiges():
		if vestige and vestige.scope == Vestige.Scope.GLOBAL:
			_add(vestige, GameState.get_global_vestige_stack_count(vestige.vestige_id))
	changed.emit()


func get_vestiges() -> Array[Vestige]:
	var out: Array[Vestige] = []
	for entry in _entries:
		out.append(entry.vestige)
	return out


## Stack count of [param vestige] (0 if not carried).
func get_stacks(vestige: Vestige) -> int:
	for entry in _entries:
		if entry.vestige == vestige:
			return entry.stacks
	return 0


func is_empty() -> bool:
	return _entries.is_empty()


func _add(vestige: Vestige, stacks: int) -> void:
	for entry in _entries:
		if entry.vestige.vestige_id == vestige.vestige_id:
			return
	_entries.append({"vestige": vestige, "stacks": maxi(stacks, 1)})


# ─────────────────────────────────────────────────────────────────────────────
# Modifiers
# ─────────────────────────────────────────────────────────────────────────────

## Stat deltas from every carried vestige (flat bonus and percent of
## [param base], each times its stacks) plus this combat's modifiers. A stat
## modifier source for [method Battler.refresh_stats].
func get_stat_modifiers(base: Dictionary) -> Dictionary:
	var mods := {}
	for entry in _entries:
		var vestige: Vestige = entry.vestige
		var stacks: int = entry.stacks
		for stat in STAT_FIELDS:
			var fields: Array = STAT_FIELDS[stat]
			var delta := int(vestige.get(fields[0])) * stacks
			if fields[1] != &"":
				delta += roundi(float(base.get(stat, 0)) * float(vestige.get(fields[1])) * stacks)
			if delta != 0:
				mods[stat] = int(mods.get(stat, 0)) + delta
	for stat in _combat_modifiers:
		mods[stat] = int(mods.get(stat, 0)) + int(_combat_modifiers[stat])
	return mods


## Combined [code]<name>_multiplier[/code] of every carried vestige (e.g.
## [code]&"damage_taken"[/code] reads [member Vestige.damage_taken_multiplier]).
## Stacks compound: two stacks of x0.9 give x0.81.
func get_multiplier(name: StringName) -> float:
	var field := StringName(String(name) + "_multiplier")
	var multiplier := 1.0
	for entry in _entries:
		var value: Variant = entry.vestige.get(field)
		if value != null:
			multiplier *= pow(float(value), entry.stacks)
	return multiplier


## Sum of an integer [Vestige] bonus field (e.g. [code]&"ap_cost_reduction"[/code])
## over every carried vestige, times its stacks.
func get_bonus(field: StringName) -> int:
	var total := 0
	for entry in _entries:
		var value: Variant = entry.vestige.get(field)
		if value != null:
			total += int(value) * int(entry.stacks)
	return total


## Changes [param stat] by [param amount] for the rest of this combat (for
## vestige effects such as combat-start buffs). Cleared when combat ends.
## Returns false (and changes nothing) for a stat vestiges can't modify.
func add_combat_modifier(stat: StringName, amount: int) -> bool:
	if not STAT_FIELDS.has(stat):
		push_warning("VestigeHolder: '%s' is not a stat vestiges can modify" % stat)
		return false
	_combat_modifiers[stat] = int(_combat_modifiers.get(stat, 0)) + amount
	_battler.refresh_stats()
	return true


## Scratch state [param owner] (a hook, effect or condition) keeps for this
## battler during the current combat, e.g. trigger counts. Vestige resources
## are shared by every battler carrying the vestige, so per-battler state
## belongs here, never on the resource. Empty again at the next combat start.
func get_combat_memory(owner: Object) -> Dictionary:
	if not _combat_memory.has(owner):
		_combat_memory[owner] = {}
	return _combat_memory[owner]


# ─────────────────────────────────────────────────────────────────────────────
# Events
# ─────────────────────────────────────────────────────────────────────────────

## Reacts to a battle event (see [BattleEvents]): fires the matching trigger
## hooks of every carried vestige. Combat start re-reads the vestiges first
## (so the battle always uses what the run owns now) and resets this combat's
## modifiers; combat end drops them again.
func handle_event(event: StringName, context: Dictionary = {}) -> void:
	if event == BattleEvents.COMBAT_START:
		reload()
		_combat_modifiers.clear()
		_combat_memory.clear()
		_in_combat = true
		_battler.refresh_stats()
	if event == BattleEvents.HEALTH_CHANGED:
		if _in_combat:
			for trigger in HP_THRESHOLD_TRIGGERS:
				_fire(trigger, context, _hp_crossing_filter(HP_THRESHOLD_TRIGGERS[trigger], context))
	elif EVENT_TRIGGERS.has(event):
		_fire(EVENT_TRIGGERS[event], context)
	if event == BattleEvents.COMBAT_END:
		_in_combat = false
		if not _combat_modifiers.is_empty():
			_combat_modifiers.clear()
			_battler.refresh_stats()


## Fires every carried hook of [param trigger] that passes [param filter]
## (a Callable taking the hook; none = all) and its own trigger check.
func _fire(trigger: TriggerHook.TriggerType, context: Dictionary, filter := Callable()) -> void:
	if _entries.is_empty() or _chain_depth >= MAX_CHAIN_DEPTH:
		return
	if not context.has("battle_manager") and _battler.is_inside_tree():
		context["battle_manager"] = _battler.get_tree().get_first_node_in_group("battle_manager")
	context["vestige_holder"] = self
	_chain_depth += 1
	for entry in _entries:
		var vestige: Vestige = entry.vestige
		for hook in vestige.trigger_hooks:
			if hook is TriggerHook and hook.trigger_type == trigger \
					and (not filter.is_valid() or filter.call(hook)) \
					and hook.should_trigger(vestige, _battler, context):
				hook.execute(vestige, _battler, context)
	_chain_depth -= 1


## Passes a hook when this HP change crossed its [member TriggerHook.hp_threshold]
## downwards ([param below]) or upwards.
func _hp_crossing_filter(below: bool, context: Dictionary) -> Callable:
	var max_hp := float(maxi(int(context.get("max_health", 1)), 1))
	var old_ratio := float(context.get("old_health", 0)) / max_hp
	var new_ratio := float(context.get("new_health", 0)) / max_hp
	return func(hook: TriggerHook) -> bool:
		var threshold := hook.hp_threshold
		if below:
			return old_ratio > threshold and new_ratio <= threshold
		return old_ratio < threshold and new_ratio >= threshold
