@tool
class_name ApplyStateOnTrigger
extends VestigeEffect
## Apply a state when a specific trigger occurs

var state_resource_path: String = ""  # Path to state resource
var stack_count: int = 1
var apply_to_target: bool = false  # If true, apply to target; if false, apply to self
var trigger_limit: int = -1  # -1 = unlimited

var _trigger_count: int = 0


func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> void:
	var params = context.get("hook_parameters", {})
	state_resource_path = params.get("state_resource_path", "")
	apply_to_target = params.get("apply_to_target", false)
	trigger_limit = params.get("trigger_limit", -1)
	
	if trigger_limit > 0 and _trigger_count >= trigger_limit:
		return
	
	if battler == null:
		return
	
	if state_resource_path.is_empty():
		push_warning("ApplyStateOnTrigger: No state resource path set for %s" % vestige.vestige_name)
		return
	
	var state_resource = load(state_resource_path)
	if state_resource == null:
		push_warning("ApplyStateOnTrigger: Failed to load state from path '%s'" % state_resource_path)
		return
	
	var target: Battler = battler
	
	if apply_to_target and context.has("target"):
		var context_target = context["target"]
		if context_target is Battler:
			target = context_target
	
	if target == null:
		return
	
	if target.has_method("apply_state"):
		target.apply_state(state_resource)
	elif target.has_property("active_states"):
		if not target.active_states.has(state_resource.state_name):
			target.active_states[state_resource.state_name] = state_resource.duplicate()
			target.state_applied.emit(state_resource.state_name)
	
	_trigger_count += 1
