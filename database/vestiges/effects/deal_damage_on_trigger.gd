class_name DealDamageOnTrigger
extends VestigeEffect
## Deal damage when a specific trigger occurs

var damage_amount: int = 5
var target_type: String = "random_enemy"  # random_enemy, all_enemies, self
var trigger_limit: int = -1  # -1 = unlimited

var _trigger_count: int = 0


func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> void:
	var params = context.get("hook_parameters", {})
	damage_amount = params.get("damage_amount", 5)
	target_type = params.get("target_type", "random_enemy")
	trigger_limit = params.get("trigger_limit", -1)
	
	if trigger_limit > 0 and _trigger_count >= trigger_limit:
		return
	
	if battler == null:
		return
	
	var battle_manager = context.get("battle_manager")
	if battle_manager == null:
		return
	
	var targets: Array[Battler] = []
	
	match target_type.to_lower():
		"random_enemy":
			if battle_manager.enemies.size() > 0:
				targets.append(battle_manager.enemies.pick_random())
		"all_enemies":
			targets = battle_manager.enemies.duplicate()
		"self":
			targets.append(battler)
		_:
			push_warning("DealDamageOnTrigger: Unknown target type '%s'" % target_type)
	
	for target in targets:
		if target and target.current_health > 0:
			target.take_damage(damage_amount, battler)
	
	_trigger_count += 1
