class_name HealOnDeath
extends VestigeEffect
## Heal to percentage of max HP when would die (once per combat)

var heal_percentage: float = 0.5  # 0.5 = 50% of max HP
var trigger_limit: int = 1  # Once per combat

var _trigger_count: int = 0
var _has_triggered_this_combat: bool = false


func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> void:
	var params = context.get("hook_parameters", {})
	heal_percentage = params.get("heal_percentage", 0.5)
	trigger_limit = params.get("trigger_limit", 1)
	
	if _has_triggered_this_combat:
		return
	
	if trigger_limit > 0 and _trigger_count >= trigger_limit:
		return
	
	if battler == null:
		return
	
	# Check if this damage would be lethal
	var damage_amount = context.get("damage_amount", 0)
	if damage_amount <= 0:
		return
	
	# Only trigger if damage would reduce HP to 0 or below
	if battler.current_health - damage_amount > 0:
		return
	
	var heal_amount = int(battler.max_health * heal_percentage)
	
	if battler.has_method("take_healing"):
		battler.take_healing(heal_amount)
	elif "current_health" in battler and "max_health" in battler:
		battler.current_health = mini(battler.current_health + heal_amount, battler.max_health)
	
	_has_triggered_this_combat = true
	_trigger_count += 1
	
	_register_combat_end_reset(battler)


func _register_combat_end_reset(battler: Battler) -> void:
	if battler.has_signal("combat_ended"):
		battler.combat_ended.connect(_on_combat_end)


func _on_combat_end() -> void:
	_has_triggered_this_combat = false
