class_name EffectCondition
extends Resource
## Condition for effect execution
## Controls when effects can be applied based on game state

enum ConditionType {
	TARGET_HEALTH,       # Target health condition
	ACTOR_HEALTH,        # Actor health condition
	TARGET_STATE,        # Target has specific state
	ACTOR_STATE,         # Actor has specific state
	TIME_OF_DAY,         # Time-based condition
	TURN_COUNT,          # Turn-based condition
	RANDOM_CHANCE,       # Random chance condition
	CUSTOM               # Custom condition
}

enum Operator {
	EQUALS,              # Value equals target
	NOT_EQUALS,          # Value does not equal target
	GREATER_THAN,        # Value greater than target
	LESS_THAN,           # Value less than target
	GREATER_EQUAL,       # Value greater than or equal to target
	LESS_EQUAL,          # Value less than or equal to target
	CONTAINS,            # Value contains target
	NOT_CONTAINS,        # Value does not contain target
	IS_TRUE,             # Value is true
	IS_FALSE             # Value is false
}

@export var condition_type: ConditionType = ConditionType.RANDOM_CHANCE
@export var operator: Operator = Operator.EQUALS
@export var condition_value: Variant = null              ## Value to check against
@export var target_value: Variant = null                 ## Target value to compare
@export var check_target: bool = true                    ## Whether to check target or actor
@export var negate: bool = false                         ## Whether to negate the condition result

## Evaluate this condition
func evaluate(actor: Node, target: Node) -> bool:
	var base_result = _evaluate_condition(actor, target)
	var final_result = negate if not base_result else not negate
	return final_result

## Internal condition evaluation
func _evaluate_condition(actor: Node, target: Node) -> bool:
	var subject = target if check_target else actor
	
	match condition_type:
		ConditionType.TARGET_HEALTH:
			return _evaluate_health_condition(subject)
		ConditionType.ACTOR_HEALTH:
			return _evaluate_health_condition(actor)
		ConditionType.TARGET_STATE:
			return _evaluate_state_condition(subject)
		ConditionType.ACTOR_STATE:
			return _evaluate_state_condition(actor)
		ConditionType.TIME_OF_DAY:
			return _evaluate_time_condition()
		ConditionType.TURN_COUNT:
			return _evaluate_turn_condition()
		ConditionType.RANDOM_CHANCE:
			return _evaluate_random_condition()
		ConditionType.CUSTOM:
			return _evaluate_custom_condition(actor, target)
		_:
			return true

## Evaluate health condition
func _evaluate_health_condition(subject: Node) -> bool:
	if not subject:
		return false
	
	var current_health = 0
	var max_health = 1
	
	if subject.has_method("get_current_health"):
		current_health = subject.get_current_health()
	if subject.has_method("get_max_health"):
		max_health = subject.get_max_health()
	
	var health_ratio = float(current_health) / float(max_health) if max_health > 0 else 0
	
	return _compare_values(health_ratio, condition_value)

## Evaluate state condition
func _evaluate_state_condition(subject: Node) -> bool:
	if not subject or condition_value == null:
		return false
	
	var state_id = condition_value as String
	
	if subject.has_method("has_state"):
		var has_state = subject.has_state(state_id)
		return _compare_values(has_state, target_value)
	
	return false

## Evaluate time condition
func _evaluate_time_condition() -> bool:
	if condition_value == null:
		return false
	
	# Would need actual time system implementation
	# For now, return true
	return true

## Evaluate turn condition
func _evaluate_turn_condition() -> bool:
	if condition_value == null:
		return false
	
	# Would need turn counter from battle manager
	# For now, return true
	return true

## Evaluate random chance condition
func _evaluate_random_condition() -> bool:
	if condition_value == null:
		return false
	
	var chance = float(condition_value)
	if chance < 0 or chance > 1:
		chance = 0.5
	
	return randf() < chance

## Evaluate custom condition
func _evaluate_custom_condition(actor: Node, target: Node) -> bool:
	# Would need custom script implementation
	# For now, return true
	return true

## Compare values based on operator
func _compare_values(value1: Variant, value2: Variant) -> bool:
	if target_value != null:
		value2 = target_value
	
	match operator:
		Operator.EQUALS:
			return value1 == value2
		Operator.NOT_EQUALS:
			return value1 != value2
		Operator.GREATER_THAN:
			return value1 > value2
		Operator.LESS_THAN:
			return value1 < value2
		Operator.GREATER_EQUAL:
			return value1 >= value2
		Operator.LESS_EQUAL:
			return value1 <= value2
		Operator.CONTAINS:
			if value1 is Array and value2:
				return value2 in value1
			if value1 is String and value2 is String:
				return value2 in value1
			return false
		Operator.NOT_CONTAINS:
			if value1 is Array and value2:
				return not (value2 in value1)
			if value1 is String and value2 is String:
				return not (value2 in value1)
			return true
		Operator.IS_TRUE:
			return bool(value1) == true
		Operator.IS_FALSE:
			return bool(value1) == false
		_:
			return value1 == value2

## Get condition description for UI
func get_description() -> String:
	var description = ""
	
	match condition_type:
		ConditionType.TARGET_HEALTH:
			description = "Target health "
		ConditionType.ACTOR_HEALTH:
			description = "Actor health "
		ConditionType.TARGET_STATE:
			description = "Target has state "
		ConditionType.ACTOR_STATE:
			description = "Actor has state "
		ConditionType.TIME_OF_DAY:
			description = "Time of day "
		ConditionType.TURN_COUNT:
			description = "Turn count "
		ConditionType.RANDOM_CHANCE:
			description = "Random chance "
		ConditionType.CUSTOM:
			description = "Custom condition "
		_:
			description = "Condition "
	
	description += _get_operator_string()
	
	if condition_value != null:
		description += str(condition_value)
	
	if negate:
		description = "NOT " + description
	
	return description

## Get operator string for description
func _get_operator_string() -> String:
	match operator:
		Operator.EQUALS:
			return "== "
		Operator.NOT_EQUALS:
			return "!= "
		Operator.GREATER_THAN:
			return "> "
		Operator.LESS_THAN:
			return "< "
		Operator.GREATER_EQUAL:
			return ">= "
		Operator.LESS_EQUAL:
			return "<= "
		Operator.CONTAINS:
			return "contains "
		Operator.NOT_CONTAINS:
			return "does not contain "
		Operator.IS_TRUE:
			return "is true"
		Operator.IS_FALSE:
			return "is false"
		_:
			return "== "

## Create preset conditions
static func create_low_health_condition(threshold: float = 0.3) -> EffectCondition:
	var condition = EffectCondition.new()
	condition.condition_type = ConditionType.TARGET_HEALTH
	condition.operator = Operator.LESS_THAN
	condition.condition_value = threshold
	condition.check_target = true
	condition.negate = false
	return condition

static func create_high_health_condition(threshold: float = 0.7) -> EffectCondition:
	var condition = EffectCondition.new()
	condition.condition_type = ConditionType.TARGET_HEALTH
	condition.operator = Operator.GREATER_THAN
	condition.condition_value = threshold
	condition.check_target = true
	condition.negate = false
	return condition

static func create_random_chance_condition(chance: float = 0.5) -> EffectCondition:
	var condition = EffectCondition.new()
	condition.condition_type = ConditionType.RANDOM_CHANCE
	condition.operator = Operator.IS_TRUE
	condition.condition_value = chance
	condition.check_target = false
	condition.negate = false
	return condition

static func create_state_condition(state_id: String, has_state: bool = true) -> EffectCondition:
	var condition = EffectCondition.new()
	condition.condition_type = ConditionType.TARGET_STATE
	condition.operator = Operator.IS_TRUE if has_state else Operator.IS_FALSE
	condition.condition_value = state_id
	condition.target_value = has_state
	condition.check_target = true
	condition.negate = false
	return condition

## Validate configuration
func validate() -> Array[String]:
	var issues: Array[String] = []
	
	if condition_type == ConditionType.RANDOM_CHANCE:
		if condition_value == null:
			issues.append("Random chance condition requires a value")
		else:
			var chance = float(condition_value)
			if chance < 0 or chance > 1:
				issues.append("Random chance must be between 0.0 and 1.0")
	
	if condition_type in [ConditionType.TARGET_STATE, ConditionType.ACTOR_STATE]:
		if condition_value == null or (condition_value as String).is_empty():
			issues.append("State condition requires a state ID")
	
	return issues
