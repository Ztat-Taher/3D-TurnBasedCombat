class_name ApplyStateOnTrigger
extends VestigeEffect
## Puts a state on the battler, or on the event's "target".

@export var state: State
## Apply to the event's "target" (e.g. the card's target) instead of the battler.
@export var apply_to_target: bool = false


func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	if state == null:
		push_warning("ApplyStateOnTrigger: no state set on %s" % vestige.vestige_name)
		return false
	var target := battler
	if apply_to_target and context.get("target") is Battler:
		target = context["target"]
	if target == null:
		return false
	target.apply_state(state, battler)
	return true
