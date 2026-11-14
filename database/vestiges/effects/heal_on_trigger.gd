@tool
class_name HealOnTrigger
extends VestigeEffect
## Heal when a specific trigger occurs

@export var heal_amount: int = 10
@export var target_type: String = "self"  # self, random_ally, all_allies
@export var trigger_limit: int = -1  # -1 = unlimited

var _trigger_count: int = 0


func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> void:
	if trigger_limit > 0 and _trigger_count >= trigger_limit:
		return
	
	if battler == null:
		return
	
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager == null:
		return
	
	var targets: Array[Battler] = []
	
	match target_type.to_lower():
		"self":
			targets.append(battler)
		"random_ally":
			if battle_manager.players.size() > 0:
				targets.append(battle_manager.players.pick_random())
		"all_allies":
			targets = battle_manager.players.duplicate()
		_:
			push_warning("HealOnTrigger: Unknown target type '%s'" % target_type)
	
	for target in targets:
		if target and target.current_health > 0:
			target.take_healing(heal_amount)
	
	_trigger_count += 1
