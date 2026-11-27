class_name HealOnDeath
extends VestigeEffect
## Saves the battler from a lethal hit: instead of being defeated it is left
## with a fraction of its max HP. Use on an ON_LETHAL_DAMAGE hook (with a
## trigger_limit for "once per combat").

@export_range(0.0, 1.0, 0.05) var heal_percentage: float = 0.5


func execute(_vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	if battler == null:
		return false
	var revive := maxi(int(battler.max_health * heal_percentage), 1)
	context["revive_health"] = maxi(int(context.get("revive_health", 0)), revive)
	return true
