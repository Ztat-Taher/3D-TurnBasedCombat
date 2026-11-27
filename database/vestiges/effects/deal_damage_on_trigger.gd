class_name DealDamageOnTrigger
extends VestigeEffect
## Deals damage to enemies or the battler.

@export var damage_amount: int = 5
@export_enum("random_enemy", "all_enemies", "self") var target_type: String = "random_enemy"


func execute(_vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	var battle_manager = context.get("battle_manager")
	if battler == null or battle_manager == null:
		return false
	var alive_enemies: Array = battle_manager.enemies.filter(
		func(e): return is_instance_valid(e) and e.current_health > 0)
	var targets: Array = []
	match target_type:
		"random_enemy":
			if not alive_enemies.is_empty():
				targets.append(alive_enemies.pick_random())
		"all_enemies":
			targets = alive_enemies
		"self":
			targets.append(battler)
	for target in targets:
		target.take_damage(damage_amount, battler)
	return not targets.is_empty()
