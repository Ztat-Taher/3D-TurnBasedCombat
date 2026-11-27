@abstract
class_name VestigeCondition
extends Resource
## Base class for when a vestige [TriggerHook] may fire.
##
## Conditions are sub-resources of a hook, configured with their own exported
## fields. Shared by every battler carrying the vestige, so they must never
## change their own fields at runtime.


## True if the hook should fire for [param battler]. [param context] is the
## same dictionary the effect gets (see [method VestigeEffect.execute]).
@abstract func should_trigger(vestige: Vestige, battler: Battler, context: Dictionary) -> bool
