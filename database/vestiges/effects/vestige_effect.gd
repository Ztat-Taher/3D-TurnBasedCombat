class_name VestigeEffect
extends Resource
## Base class for vestige effects
## Override execute() to implement custom vestige behavior

## Override to implement custom vestige behavior
## Called when the trigger fires
## vestige: The vestige that owns this effect
## battler: The battler triggering the effect (may be null for global effects)
## context: Dictionary with additional context data (varies by trigger type)
func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> void:
	push_error("VestigeEffect.execute() not implemented for: %s" % vestige.vestige_name)
