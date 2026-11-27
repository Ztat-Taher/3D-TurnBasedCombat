class_name GainCombatStat
extends VestigeEffect
## Gives a stat bonus for the rest of the combat.
##
## The bonus is a combat modifier on the battler's [VestigeHolder]: part of the
## stat pipeline (stat recalculations keep it) and dropped when the combat ends.
## Each firing adds [member amount] again, so a turn-start hook builds it up.

@export_enum("attack", "defense", "agility", "magic", "crit_chance", "max_health", "max_ap", "ap_regen_per_turn") var stat: String = "attack"
@export var amount: int = 1


func execute(_vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	var holder: VestigeHolder = context.get("vestige_holder")
	if battler == null or holder == null:
		return false
	if not holder.add_combat_modifier(StringName(stat), amount):
		return false
	if stat == "max_health":
		battler.current_health += amount
	return true
