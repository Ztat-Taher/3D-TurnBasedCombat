@abstract
class_name VestigeEffect
extends Resource
## Base class for what a vestige [TriggerHook] does when it fires.
##
## Effects are sub-resources of a hook, configured with their own exported
## fields in the inspector. One effect instance is shared by every battler
## carrying the vestige, so it must never change its own fields at runtime:
## keep per-battler, per-combat state in [method memory].
## A new effect is a new subclass; nothing else needs to know about it.


## Does the effect for [param battler]. [param context] holds the battle event's
## data (see [BattleEvents]) plus "battle_manager" and "vestige_holder".
## Return true when the effect actually happened; only then does it count
## toward the hook's trigger limit.
@abstract func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> bool


## This effect's scratch state for the battler being handled, for the current
## combat (empty at each combat start).
func memory(context: Dictionary) -> Dictionary:
	var holder: VestigeHolder = context.get("vestige_holder")
	return holder.get_combat_memory(self) if holder else {}
