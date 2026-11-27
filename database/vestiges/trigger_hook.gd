@tool
class_name TriggerHook
extends Resource
## One reaction of a vestige: when [member trigger_type] fires for the battler
## carrying it (and the optional [member condition] passes), run [member effect].
##
## Vestige resources, and so their hooks, effects and conditions, are shared by
## every battler carrying the vestige. Nothing here or in an effect/condition
## keeps state: per-battler, per-combat state lives in the battler's
## [VestigeHolder] (see [method VestigeHolder.get_combat_memory]).

## When a hook fires (for the battler carrying the vestige). New values go at
## the end: resources store them as numbers.
enum TriggerType {
	ON_COMBAT_START,
	ON_COMBAT_END,
	ON_TURN_START,
	ON_TURN_END,
	ON_CARD_PLAY,
	## Its hit made a target lose HP
	ON_DAMAGE_DEALT,
	## It lost HP to a hit (blocked or dodged hits don't count)
	ON_DAMAGE_TAKEN,
	## It regained HP
	ON_HEAL,
	## A state was put on it
	ON_STATE_APPLIED,
	ON_STATE_REMOVED,
	## A battler of the opposing team was defeated
	ON_ENEMY_DEFEAT,
	## Its HP dropped to or below [member hp_threshold] of max
	ON_LOW_HP,
	## Its HP rose to or above [member hp_threshold] of max
	ON_HIGH_HP,
	## A hit is about to defeat it (the effect may save it)
	ON_LETHAL_DAMAGE,
	## It put a state on another battler
	ON_STATE_INFLICTED,
}

@export var trigger_type: TriggerType
## What happens.
@export var effect: VestigeEffect
## Optional extra requirement; empty = always.
@export var condition: VestigeCondition
## Times the effect may happen per combat for each battler (-1 = unlimited).
@export var trigger_limit: int = -1
## HP fraction crossed by ON_LOW_HP / ON_HIGH_HP (ignored by other triggers).
@export_range(0.0, 1.0, 0.05) var hp_threshold: float = 0.5


## True when the hook may run now for [param battler]: its trigger limit for
## this combat isn't used up and its condition (if any) passes.
func should_trigger(vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	if effect == null:
		return false
	if trigger_limit >= 0 and int(_memory(context).get("count", 0)) >= trigger_limit:
		return false
	return condition == null or condition.should_trigger(vestige, battler, context)


## Runs the effect. Counts toward the trigger limit only when the effect
## reports that it actually happened.
func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> void:
	if effect and effect.execute(vestige, battler, context):
		var memory := _memory(context)
		memory["count"] = int(memory.get("count", 0)) + 1


## Get the trigger type name as a string
func get_trigger_name() -> String:
	return TriggerType.keys()[trigger_type]


## This hook's per-combat state for the battler being handled.
func _memory(context: Dictionary) -> Dictionary:
	var holder: VestigeHolder = context.get("vestige_holder")
	return holder.get_combat_memory(self) if holder else {}
