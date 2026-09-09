class_name StateConfig
extends Resource
## State/debuff configuration for card effects
## Controls which states are applied and how they behave

enum StackingBehavior {
	NONE,               # No stacking allowed
	REFRESH,            # Refresh duration on reapply
	ADDITIVE,           # Add to existing duration
	MULTIPLICATIVE,     # Multiply existing effect
	INDEPENDENT         # Multiple instances can exist independently
}

@export var state_id: String = ""                   ## Reference to state resource
@export var state_name: String = ""                  ## Display name of the state
@export var duration: int = 1                        ## Duration in turns
@export var chance: float = 1.0                      ## Application chance (0.0-1.0)
@export var stacking_behavior: StackingBehavior = StackingBehavior.REFRESH
@export var max_stacks: int = 1                      ## Maximum number of stacks
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

## Apply this state to a target
func apply_state(target: Node, actor: Node = null) -> Dictionary:
	var result = {
		"success": false,
		"state_applied": false,
		"duration": duration,
		"stacks": 1,
		"message": ""
	}
	
	# Check chance
	if randf() > chance:
		result["message"] = "State application failed (chance check)"
		return result
	
	# Determine actual target
	var actual_target = actor if applies_to_actor else target
	if not actual_target:
		result["message"] = "No valid target for state"
		return result
	
	# Check if target is immune
	if _is_immune(actual_target):
		result["message"] = "Target is immune to this state"
		return result
	
	# Handle stacking
	var current_stacks = _get_current_stacks(actual_target)
	var new_stacks = _calculate_new_stacks(current_stacks)
	
	if new_stacks == 0 and stacking_behavior == StackingBehavior.NONE:
		result["message"] = "State already applied and no stacking allowed"
		return result
	
	# Apply the state
	if actual_target.has_method("apply_state"):
		var state_data = {
			"state_id": state_id,
			"state_name": state_name,
			"duration": duration,
			"stacks": new_stacks,
			"tick_damage": tick_damage,
			"tick_interval": tick_interval,
			"tick_count": tick_count,
			"remove_on_damage": remove_on_damage,
			"remove_on_move": remove_on_move
		}
		
		actual_target.apply_state(state_data)
		result["success"] = true
		result["state_applied"] = true
		result["stacks"] = new_stacks
		result["message"] = "State applied successfully"
	else:
		# Fallback: try to use existing state system
		result["message"] = "Target does not support state application"
	
	return result

## Check if target is immune to this state
func _is_immune(target: Node) -> bool:
	if target.has_method("has_state_immunity"):
		return target.has_state_immunity(state_id)
	
	# Check for immunity state
	if target.has_method("has_state"):
		return target.has_state("immunity_" + state_id)
	
	return false

## Get current stacks of this state on target
func _get_current_stacks(target: Node) -> int:
	if target.has_method("get_state_stacks"):
		return target.get_state_stacks(state_id)
	
	if target.has_method("has_state") and target.has_state(state_id):
		return 1
	
	return 0

## Calculate new stack count based on stacking behavior
func _calculate_new_stacks(current_stacks: int) -> int:
	match stacking_behavior:
		StackingBehavior.NONE:
			return 0 if current_stacks > 0 else 1
		StackingBehavior.REFRESH:
			return 1 # Duration will be refreshed
		StackingBehavior.ADDITIVE:
			return min(current_stacks + 1, max_stacks)
		StackingBehavior.MULTIPLICATIVE:
			return min(current_stacks * 2, max_stacks)
		StackingBehavior.INDEPENDENT:
			return current_stacks + 1
		_:
			return 1

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
	var description = state_name.capitalize()
	
	if duration > 0:
		description += " (%d turns)" % duration
	
	if chance < 1.0:
		description += " (%d%% chance)" % int(chance * 100)
	
	if tick_damage > 0:
		description += " - %d damage/tick" % tick_damage
	
	if max_stacks > 1:
		description += " (max %d stacks)" % max_stacks
	
	return description

## Create preset state configurations
static func create_burn_state() -> StateConfig:
	var config = StateConfig.new()
	config.state_id = "burn"
	config.state_name = "Burn"
	config.duration = 3
	config.chance = 0.5
	config.stacking_behavior = StackingBehavior.ADDITIVE
	config.max_stacks = 3
	config.tick_damage = 5
	config.tick_interval = 1.0
	config.tick_count = 3
	return config

static func create_poison_state() -> StateConfig:
	var config = StateConfig.new()
	config.state_id = "poison"
	config.state_name = "Poison"
	config.duration = 4
	config.chance = 0.75
	config.stacking_behavior = StackingBehavior.REFRESH
	config.max_stacks = 1
	config.tick_damage = 8
	config.tick_interval = 1.0
	config.tick_count = 4
	return config

static func create_stun_state() -> StateConfig:
	var config = StateConfig.new()
	config.state_id = "stun"
	config.state_name = "Stun"
	config.duration = 1
	config.chance = 0.3
	config.stacking_behavior = StackingBehavior.NONE
	config.max_stacks = 1
	config.remove_on_damage = true
	return config

static func create_slow_state() -> StateConfig:
	var config = StateConfig.new()
	config.state_id = "slow"
	config.state_name = "Slow"
	config.duration = 2
	config.chance = 1.0
	config.stacking_behavior = StackingBehavior.REFRESH
	config.max_stacks = 1
	return config

## Validate configuration
func validate() -> Array[String]:
	var issues: Array[String] = []
	
	if state_id.is_empty():
		issues.append("No state ID specified")
	
	if state_name.is_empty():
		issues.append("No state name specified")
	
	if duration <= 0:
		issues.append("Invalid duration (must be > 0)")
	
	if chance <= 0 or chance > 1:
		issues.append("Invalid chance (must be 0.0-1.0)")
	
	if max_stacks <= 0:
		issues.append("Invalid max stacks (must be > 0)")
	
	return issues
