class_name StateConfig
extends Resource
## How a card applies a state: which [State] (its effect, icon and name live
## on that resource), for how long, with what chance and how it stacks.

enum StackingBehavior {
	NONE,               # Fails if the target already has the state
	REFRESH,            # Reapplying refreshes the duration
	ADDITIVE,           # Adds stacks_per_application stacks, up to the state's stack_max
	MULTIPLICATIVE,     # Doubles the current stacks, up to the state's stack_max
	INDEPENDENT         # Not supported yet (battlers hold one instance per state): behaves as REFRESH
}

@export var state: State                             ## The state to apply
@export var duration: int = 1                        ## Duration in turns (-1 = until cured)
@export var chance: float = 1.0                      ## Application chance (0.0-1.0)
@export var stacking_behavior: StackingBehavior = StackingBehavior.REFRESH
@export var stacks_per_application: int = 1          ## How many stacks to add per application (ADDITIVE; first application of MULTIPLICATIVE)
@export var can_dispel: bool = true                  ## Whether state can be dispelled
@export var is_purgeable: bool = true                ## Whether state can be purged
@export var applies_to_actor: bool = false           ## Whether state applies to actor instead of target
@export var spread_on_contact: bool = false          ## Whether state spreads on contact
@export var spread_chance: float = 0.25              ## Chance to spread on contact
@export var spread_range: float = 2.0                ## Range for spreading
@export var tick_damage: int = 0                     ## Damage per tick (for DoT effects)
@export var tick_interval: float = 1.0               ## Time between ticks (seconds)
@export var tick_count: int = 0                     ## Number of ticks (0 = use duration)
@export var remove_on_damage: bool = false          ## Whether state removes when taking damage
@export var remove_on_move: bool = false             ## Whether state removes when moving
@export var immunity_duration: int = 0                ## Immunity duration after state ends

## Name the state is tracked under on battlers ([member Battler.active_states]).
func get_state_name() -> String:
	return state.state_name if state else ""

## Rolls [member chance] and, on success, puts a configured copy of
## [member state] on [param target] (or on [param actor] when
## [member applies_to_actor]). Stacking is resolved against the stacks the
## recipient already has.
func apply_state(target: Node, actor: Node = null) -> Dictionary:
	var result = {
		"success": false,
		"state_applied": false,
		"duration": duration,
		"stacks": 0,
		"message": ""
	}
	if state == null:
		result["message"] = "No state set"
		return result

	if randf() > chance:
		result["message"] = "State application failed (chance check)"
		return result

	var actual_target = actor if applies_to_actor else target
	if not actual_target or not actual_target.has_method("apply_state"):
		result["message"] = "No valid target for state"
		return result

	var existing: State = null
	if "active_states" in actual_target:
		existing = actual_target.active_states.get(state.state_name) as State
	if existing and stacking_behavior == StackingBehavior.NONE:
		result["message"] = "State already applied and no stacking allowed"
		return result

	var current_stacks := existing.stack_count if existing else 0
	# The battler adds an incoming stack_count onto an existing state's stacks
	var added := _stacks_to_add(current_stacks, existing != null)
	actual_target.apply_state(state.make_instance(duration, added), actor)
	result["success"] = true
	result["state_applied"] = true
	result["stacks"] = current_stacks + maxi(added, 0)
	result["message"] = "State applied successfully"
	return result

## Stacks this application adds on top of [param current_stacks], or -1 to
## keep the state's own stack_count. (A state that doesn't stack ignores it.)
func _stacks_to_add(current_stacks: int, has_state: bool) -> int:
	# The state owns its cap ([member State.stack_max])
	var room := maxi(0, state.stack_max - current_stacks)
	match stacking_behavior:
		StackingBehavior.ADDITIVE:
			return mini(stacks_per_application, room)
		StackingBehavior.MULTIPLICATIVE:
			return mini(current_stacks if has_state and current_stacks > 0 else stacks_per_application, room)
		_:
			# REFRESH: a re-application only refreshes; a first one is as authored
			return 0 if has_state else -1

## Handle tick-based effects (DoT, HoT, etc.)
func process_tick(target: Node):
	if tick_damage > 0 and target.has_method("take_damage"):
		target.take_damage(tick_damage)

## Handle state spread
func try_spread(source: Node, nearby_targets: Array) -> Array:
	if not spread_on_contact:
		return []
	
	var spread_targets: Array = []
	
	for target in nearby_targets:
		if _is_in_range(source, target) and randf() < spread_chance:
			var spread_result = apply_state(target)
			if spread_result["success"]:
				spread_targets.append(target)
	
	return spread_targets

## Check if target is in spread range
func _is_in_range(source: Node, target: Node) -> bool:
	if not source or not target:
		return false
	
	var distance = source.global_position.distance_to(target.global_position)
	return distance <= spread_range

## Get state description for UI
func get_description() -> String:
	var description = get_state_name()
	
	if duration > 0:
		description += " (%d turns)" % duration
	
	if chance < 1.0:
		description += " (%d%% chance)" % int(chance * 100)
	
	if tick_damage > 0:
		description += " - %d damage/tick" % tick_damage
	
	if stacking_behavior in [StackingBehavior.ADDITIVE, StackingBehavior.MULTIPLICATIVE] and state and state.stack_max > 1:
		description += " (max %d stacks)" % state.stack_max
	
	return description

## Validate configuration
func validate() -> Array[String]:
	var issues: Array[String] = []
	
	if state == null:
		issues.append("No state specified")
	
	if duration == 0 or duration < -1:
		issues.append("Invalid duration (must be > 0, or -1 until cured)")
	
	if chance <= 0 or chance > 1:
		issues.append("Invalid chance (must be 0.0-1.0)")
	
	return issues
