class_name HPThresholdCondition
extends VestigeCondition
## Passes while the battler's HP is at or below (or at or above) a fraction of
## its max HP.

@export_range(0.0, 1.0, 0.05) var threshold_percent: float = 0.5
## Pass at or below the threshold (otherwise at or above).
@export var trigger_when_below: bool = true


func should_trigger(_vestige: Vestige, battler: Battler, _context: Dictionary) -> bool:
	if battler == null or battler.max_health <= 0:
		return false
	var hp_ratio := float(battler.current_health) / float(battler.max_health)
	if trigger_when_below:
		return hp_ratio <= threshold_percent
	return hp_ratio >= threshold_percent
