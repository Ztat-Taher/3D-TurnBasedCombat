## State
## A status effect on a battler (Burning, Protected, Taunt...). Its rules live
## in its own script, through the hooks below: the battle calls them on every
## state a battler holds and knows no state by name. The generic fields cover
## the simple cases (multipliers, skipping turns, damage over time) with no
## script at all. Guide: database/states/status_effects_usage_guide.md
class_name State
extends Resource

enum StateType {
	DOT,           # Damage over time (Burning, Bleed): harmful
	COUNTER,       # Reacts to attacks (Counter): helpful
	BUFF,          # Helps its battler (Protected, Berserk): helpful
	DEBUFF         # Hinders its battler (Chilled, Marked): harmful
}

# -- Identity ---------------------------------------------------------------
## Unique key: a battler holds one state per name.
@export var state_name: String = ""
@export var state_description: String = ""
## What kind of state it is. DOT and DEBUFF are harmful (a CURE removes
## them), BUFF and COUNTER helpful (a DISPEL removes them): [method is_harmful].
@export var state_type: StateType
@export var icon_texture: Texture2D = null  ## UI icon for this status effect
## Shader overlay on the battler while the state is on (fire, ice...).
@export var overlay_material: ShaderMaterial = null
## Effect scene around the battler while the state is on. Plays its
## AnimationPlayer's "open" / "close" animations when it has them.
@export var aura_effect: PackedScene = null

# -- Duration and generic rules ---------------------------------------------
## Duration in turns, ticking down at the start of its battler's turns.
## -1 = until something else ends it (cured, used up, stacks burnt out).
@export_range(-1, 99, 1) var turns_active: int = -1
@export var can_be_cured: bool = true  ## Whether a CURE / DISPEL card effect can remove it.
@export var skip_turn: bool = false  ## Its battler skips its turns (Chilled, Stunned)
@export var is_taunting: bool = false  ## Enemy AI must target its battler (Taunt)
## Damage its battler takes at the start of its turns (reduced by defense).
@export_range(0, 100, 1) var damage_per_turn: int = 0
## HP its battler regains at the start of its turns (Regen).
@export_range(0, 100, 1) var heal_per_turn: int = 0
@export_range(0.1, 2.0, 0.1) var damage_taken_multiplier: float = 1.0  ## Incoming damage multiplier. 1.0 = normal, 1.5 = 50% more damage, 0.5 = 50% less damage
@export_range(0.1, 2.0, 0.1) var damage_dealt_multiplier: float = 1.0  ## Outgoing damage multiplier (Electrocuted, Berserk)
## Chance (%) its battler's attacks hit: 100 = always (a blinding debuff).
## Several multiply: 60 and 80 give 48.
@export_range(0.0, 100.0, 1.0) var hit_chance: float = 100.0

# -- Stacks and bar ---------------------------------------------------------
## Stacks. On a battler: its current stacks. On a resource or an application:
## the stacks one application adds (a stacking state always adds at least 1).
@export var stack_count: int = 0
## Maximum stacks. 1 = the state doesn't stack (re-applying only refreshes it).
@export_range(1, 20, 1) var stack_max: int = 1
## A bar that fills and procs when full (Bleed). On an application: what it adds.
@export var accumulation_value: int = 0
@export_range(10, 200, 10) var accumulation_max: int = 100  ## The bar's proc threshold (Bleed)

## Runtime: the battler that put this state on (its last application). Its
## turn damage is credited to them, e.g. the XP for a Burning kill.
var source: Node = null

## The aura this state put around its battler.
var _aura: Node3D = null


# -- Helpers ----------------------------------------------------------------

## Whether this state hurts its battler (damage over time, debuffs). Harmful
## states are what a cure removes, the others what a dispel removes.
func is_harmful() -> bool:
	return state_type == StateType.DOT or state_type == StateType.DEBUFF

## Whether this state stacks (Burning): only then do stack counts mean anything.
func uses_stacks() -> bool:
	return stack_max > 1

## A copy of this state for one application, which
## [method Battler.apply_state] puts on (or folds into the state already on).
## [param duration]: turns (0 = as authored; -1 = until cured).
## [param stacks]: stacks this application adds (-1 = as authored).
## [param accumulation]: Bleed-style bar it adds (0 = as authored).
## Every way of applying a state (cards, weapons, orbs, vestiges...) builds
## its copy here.
func make_instance(duration: int = 0, stacks: int = -1, accumulation: int = 0) -> State:
	var instance := duplicate() as State
	if duration != 0:
		instance.turns_active = duration
	if stacks >= 0:
		instance.stack_count = stacks
	if accumulation > 0:
		instance.accumulation_value = accumulation
	return instance

## Adds stacks, up to [member stack_max].
func add_stacks(amount: int) -> void:
	stack_count = mini(stack_count + amount, stack_max)

## Removes stacks, down to 0.
func remove_stacks(amount: int) -> void:
	stack_count = maxi(stack_count - amount, 0)

## Fills the bar.
func add_accumulation(amount: int) -> void:
	accumulation_value += amount

## Whether the bar is full.
func should_proc() -> bool:
	return accumulation_value >= accumulation_max

## Empties the bar.
func reset_accumulation() -> void:
	accumulation_value = 0


# -- Hooks ------------------------------------------------------------------
# The defaults apply the generic fields above (or do nothing); a state script
# overrides what it needs. [param owner] is the battler holding the state.

## Damage [param owner] deals (after the stat formula). [param hit]:
## attacker, target, damage_type, element, is_attack (false for bonus damage:
## weapon and orb procs), is_critical. Default: [member damage_dealt_multiplier].
func modify_damage_dealt(damage: int, _owner: Node, _hit: Dictionary) -> int:
	return int(damage * damage_dealt_multiplier) if damage_dealt_multiplier != 1.0 else damage

## Damage [param owner] takes; [param hit] as in [method modify_damage_dealt].
## Default: [member damage_taken_multiplier].
func modify_damage_taken(damage: int, _owner: Node, _hit: Dictionary) -> int:
	return int(damage * damage_taken_multiplier) if damage_taken_multiplier != 1.0 else damage

## The chance (%) a hit by [param owner] lands, [param hit] as in
## [method modify_damage_dealt]. Default: scaled by [member hit_chance], so
## several states multiply.
func modify_hit_chance(chance: float, _owner: Node, _hit: Dictionary) -> float:
	return chance * hit_chance / 100.0

## Whether this state stops a hit on [param owner] outright: no damage and
## no on-hit effects. [param hit] as in [method on_hit_taken].
func blocks_hit(_owner: Node, _hit: Dictionary) -> bool:
	return false

## Hits this state will block, shown as the battler's shield row (Protected).
## The battler sums it over its states: [method Battler.get_shield_hits].
func get_shield_hits() -> int:
	return 0

## [param owner] was hit (not blocked). [param hit]: attacker, damage (the
## HP lost; 0 if none), damage_type, element, is_attack, is_critical.
## Awaitable: the hit waits for it (e.g. a counter-attack).
func on_hit_taken(_owner: Node, _hit: Dictionary) -> void:
	pass

## Damage this state deals [param owner] at the start of its turn. Default:
## [member damage_per_turn], reduced by the owner's defense.
func get_turn_damage(owner: Node) -> int:
	if damage_per_turn <= 0:
		return 0
	var defense_multiplier = max(0.1, 1.0 - (float(owner.defense) / 100.0))
	return max(1, int(damage_per_turn * defense_multiplier))

## HP this state restores to [param owner] at the start of its turn (after
## its turn damage). Default: [member heal_per_turn].
func get_turn_heal(_owner: Node) -> int:
	return heal_per_turn

## Start of [param owner]'s turn, after this state's turn damage and heal: per-turn
## upkeep (e.g. stacks decaying). Durations tick down on their own.
func on_turn_tick(_owner: Node) -> void:
	pass

## Whether this state is used up (it's removed when its owner's states update).
func is_expired() -> bool:
	return false

## Any battler's turn starts ([param owner] holds this state).
func on_any_turn_start(_owner: Node) -> void:
	pass

## This state was just put on [param owner] (its visuals are already shown).
func on_applied(_owner: Node) -> void:
	pass

## The same state lands on [param owner] again: fold [param incoming] into
## this one. Default: add its stacks (up to [member stack_max]) and refresh
## the duration.
func merge(incoming: State, _owner: Node) -> void:
	if uses_stacks() and incoming.stack_count > 0:
		add_stacks(incoming.stack_count)
	if incoming.turns_active > 0:
		turns_active = incoming.turns_active

## This state was just taken off [param owner] (its visuals are already gone).
func on_removed(_owner: Node) -> void:
	pass


# -- Visuals (called by the battler) ----------------------------------------

## Shows [member overlay_material] and [member aura_effect] on [param owner].
func show_visuals(owner: Node) -> void:
	if overlay_material:
		owner.add_overlay(Battler.OverlayType.STATUS, overlay_material, 5, state_name)
	if aura_effect:
		_aura = owner.apply_aura_effect(aura_effect)
		var anim = _aura.get_node_or_null("AnimationPlayer") if _aura else null
		if anim and anim.has_animation("open"):
			anim.play("open")

## Takes this state's overlay and aura off [param owner].
func hide_visuals(owner: Node) -> void:
	if overlay_material:
		owner.remove_overlay(state_name)
	if is_instance_valid(_aura):
		owner.remove_aura_effect(_aura)
	_aura = null
