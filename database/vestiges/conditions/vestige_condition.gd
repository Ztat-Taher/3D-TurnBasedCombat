class_name VestigeCondition
extends Resource
## Base class for vestige activation conditions
## Override should_trigger() to implement custom conditions

## Override to implement activation conditions
## Returns true if the vestige should trigger
## vestige: The vestige being checked
## battler: The battler triggering the effect (may be null for global effects)
## context: Dictionary with additional context data (varies by trigger type)
func should_trigger(vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	return true  # Default: always trigger
