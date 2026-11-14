class_name GainBlockOnTrigger
extends VestigeEffect
## Gain block when a specific trigger occurs

var block_amount: int = 5
var apply_to: String = "self"  # self, all_allies
var trigger_limit: int = -1  # -1 = unlimited

var _trigger_count: int = 0


func execute(_vestige: Vestige, battler: Battler, context: Dictionary) -> void:
	var params = context.get("hook_parameters", {})
	block_amount = params.get("block_amount", 5)
	apply_to = params.get("apply_to", "self")
	trigger_limit = params.get("trigger_limit", -1)
	
	if trigger_limit > 0 and _trigger_count >= trigger_limit:
		return
	
	if battler == null:
		return
	
	var battle_manager = context.get("battle_manager")
	var targets: Array[Battler] = []
	
	match apply_to.to_lower():
		"self":
			targets.append(battler)
		"all_allies":
			if battle_manager != null:
				targets = battle_manager.players.duplicate()
			else:
				targets.append(battler)
		_:
			push_warning("GainBlockOnTrigger: Unknown apply target '%s'" % apply_to)
	
	for target in targets:
		if target and target.current_health > 0:
			if target.has_method("apply_state"):
				var protected_state = load("res://database/states/resources/protected_state.tres")
				if protected_state:
					var state_instance = protected_state.duplicate()
					if state_instance.has_method("set_shield_hits"):
						state_instance.set_shield_hits(block_amount)
					target.apply_state(state_instance)
	
	_trigger_count += 1
