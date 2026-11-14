@tool
class_name TriggerHook
extends Resource
## Defines when a vestige effect should trigger

enum TriggerType {
	ON_COMBAT_START,
	ON_COMBAT_END,
	ON_TURN_START,
	ON_TURN_END,
	ON_CARD_PLAY,
	ON_DAMAGE_DEALT,
	ON_DAMAGE_TAKEN,
	ON_HEAL,
	ON_STATE_APPLIED,
	ON_STATE_REMOVED,
	ON_ENEMY_DEFEAT,
	ON_LOW_HP,
	ON_HIGH_HP
}

@export var trigger_type: TriggerType
@export var effect_script_path: String = ""  # Path to effect script
@export var condition_script_path: String = ""  # Path to condition script
@export var parameters: Dictionary = {}  # Parameters to pass to effect script

var effect_script: Object = null
var condition_script: Object = null

func _ensure_scripts_loaded():
	# Load and instantiate scripts from paths when needed (Resources don't have _ready)
	if effect_script == null and not effect_script_path.is_empty():
		var script_resource = load(effect_script_path)
		if script_resource:
			# Try to instantiate the script
			if script_resource is Script:
				effect_script = script_resource.new()
			else:
				effect_script = script_resource
	if condition_script == null and not condition_script_path.is_empty():
		var script_resource = load(condition_script_path)
		if script_resource:
			if script_resource is Script:
				condition_script = script_resource.new()
			else:
				condition_script = script_resource


## Check if this hook should trigger based on condition
func should_trigger(vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
	_ensure_scripts_loaded()
	if condition_script == null:
		return true
	
	if condition_script.has_method("should_trigger"):
		return condition_script.should_trigger(vestige, battler, context)
	
	return true


## Execute the effect for this hook
func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> void:
	_ensure_scripts_loaded()
	if effect_script == null:
		return
	
	# Build parameters dictionary from both the parameters dict and direct fields
	var combined_params = parameters.duplicate()
	
	# Add direct fields from the hook if they exist
	if has_method("get_property_list"):
		for prop in get_property_list():
			var prop_name = prop.name
			if prop_name in ["script", "trigger_type", "effect_script_path", "condition_script_path", "parameters", "effect_script", "condition_script"]:
				continue
			if prop.usage & PROPERTY_USAGE_STORAGE:
				combined_params[prop_name] = get(prop_name)
	
	# Merge hook parameters into context
	if not combined_params.is_empty():
		context["hook_parameters"] = combined_params
	
	if effect_script.has_method("execute"):
		effect_script.execute(vestige, battler, context)


## Get the trigger type name as a string
func get_trigger_name() -> String:
	return TriggerType.keys()[trigger_type]
