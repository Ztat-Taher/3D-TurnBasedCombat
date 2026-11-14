class_name HPThresholdCondition
extends VestigeCondition
## Condition that triggers when HP is below or above a threshold

var threshold_percent: float = 0.5  # 0.0 to 1.0 (50% = 0.5)
var trigger_when_below: bool = true  # If true, trigger when below; if false, trigger when above


func should_trigger(_vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	var params = context.get("hook_parameters", {})
	threshold_percent = params.get("threshold_percent", 0.5)
	trigger_when_below = params.get("trigger_when_below", true)
	
	if battler == null:
		return false
	
	if battler.max_health <= 0:
		return false
	
	var hp_ratio = float(battler.current_health) / float(battler.max_health)
	
	if trigger_when_below:
		return hp_ratio <= threshold_percent
	else:
		return hp_ratio >= threshold_percent
