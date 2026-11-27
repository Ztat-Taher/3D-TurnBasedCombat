class_name GainShieldOnTrigger
extends VestigeEffect
## Gives the Protected state: shield hits that each block one whole attack.

const PROTECTED_STATE := preload("res://database/states/resources/protected_state.tres")

@export var shield_hits: int = 1
@export_enum("self", "all_allies") var apply_to: String = "self"


func execute(_vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	if battler == null:
		return false
	var targets: Array = [battler]
	var battle_manager = context.get("battle_manager")
	if apply_to == "all_allies" and battle_manager:
		targets = battle_manager.players.filter(
			func(p): return is_instance_valid(p) and p.current_health > 0)
	for target in targets:
		var shield = PROTECTED_STATE.make_instance()
		shield.set_shield_hits(shield_hits)
		target.apply_state(shield, battler)
	return not targets.is_empty()
