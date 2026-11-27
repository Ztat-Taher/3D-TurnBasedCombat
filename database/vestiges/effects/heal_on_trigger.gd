class_name HealOnTrigger
extends VestigeEffect
## Heals the battler or its allies.

@export var heal_amount: int = 10
@export_enum("self", "random_ally", "all_allies") var target_type: String = "self"


func execute(_vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	if battler == null:
		return false
	var allies: Array = [battler]
	var battle_manager = context.get("battle_manager")
	if battle_manager:
		allies = battle_manager.players.filter(
			func(p): return is_instance_valid(p) and p.current_health > 0)
	var targets: Array = []
	match target_type:
		"self":
			targets.append(battler)
		"random_ally":
			if not allies.is_empty():
				targets.append(allies.pick_random())
		"all_allies":
			targets = allies
	for target in targets:
		target.take_healing(heal_amount)
	return not targets.is_empty()
