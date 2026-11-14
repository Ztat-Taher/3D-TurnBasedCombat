class_name GainStatOnCombatStart
extends VestigeEffect
## Gain temporary stat bonus at combat start

var stat_to_gain: String = "attack"  # attack, defense, agility
var amount: int = 5
var is_temporary: bool = true  # If true, remove at combat end
var apply_once: bool = true  # If true, only apply once per combat; if false, can reapply each trigger

var _stat_gain_applied: bool = false


func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> void:
	var params = context.get("hook_parameters", {})
	stat_to_gain = params.get("stat_to_gain", "attack")
	amount = params.get("amount", 5)
	is_temporary = params.get("is_temporary", true)
	apply_once = params.get("apply_once", true)
	
	if apply_once and _stat_gain_applied:
		return
	
	if battler == null:
		return
	
	match stat_to_gain.to_lower():
		"attack":
			battler.attack += amount
		"defense":
			battler.defense += amount
		"agility":
			battler.agility += amount
		"max_health":
			battler.max_health += amount
			battler.current_health += amount
		_:
			push_warning("GainStatOnCombatStart: Unknown stat '%s'" % stat_to_gain)
	
	if apply_once:
		_stat_gain_applied = true
	
	if is_temporary:
		_register_combat_end_removal(battler, vestige)


func _register_combat_end_removal(battler: Battler, vestige: Vestige) -> void:
	# Listen for combat end signal to remove the stat bonus
	if battler.has_signal("combat_ended"):
		battler.combat_ended.connect(_on_combat_end.bind(battler, vestige))


func _on_combat_end(battler: Battler, _vestige: Vestige) -> void:
	if battler == null:
		return
	
	match stat_to_gain.to_lower():
		"attack":
			battler.attack -= amount
		"defense":
			battler.defense -= amount
		"agility":
			battler.agility -= amount
		"max_health":
			battler.max_health -= amount
			battler.current_health = mini(battler.current_health, battler.max_health)
	
	_stat_gain_applied = false
