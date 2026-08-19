class_name CardEffect
extends Resource
## Encapsulates individual card effects for modular configuration
## Each effect can be independently configured and combined

enum EffectType {
	DAMAGE,             # Deal damage to target(s)
	HEAL,               # Heal target(s)
	SHIELD,             # Apply shield/defense to target(s)
	BUFF,               # Apply buff to target(s)
	DEBUFF,             # Apply debuff to target(s)
	SUMMON,             # Summon a unit
	KNOCKBACK,          # Knock target back
	STUN,               # Stun target(s)
	DRAIN,              # Drain health from target
	LETHAL,             # Instant kill if target below threshold
	CUSTOM              # Custom effect (requires script implementation)
}

enum EffectTargeting {
	ACTOR,              # Effect applied to actor
	TARGET,              # Effect applied to primary target
	ALL_ENEMIES,        # Effect applied to all enemies
	ALL_ALLIES,         # Effect applied to all allies
	ALL_UNITS,          # Effect applied to all units
	RANDOM_ENEMY,       # Effect applied to random enemy
	RANDOM_ALLY,        # Effect applied to random ally
	CUSTOM_SELECTION    # Custom targeting logic
}

@export var effect_type: EffectType = EffectType.DAMAGE
@export var value: int = 0                          ## Base effect value
@export var targeting: EffectTargeting = EffectTargeting.TARGET
@export var scaling: Dictionary = {}                ## Stat scaling configuration
@export var conditions: Array[EffectCondition] = [] ## Conditions for effect execution
@export var is_percentage: bool = false             ## If true, value is percentage (0-100)
@export var delay: float = 0.0                      ## Delay before effect triggers (seconds)
@export var duration: float = 0.0                   ## Effect duration for temporary effects (seconds)
@export var stack_count: int = 1                    ## Number of stacks for stacking effects
@export var can_crit: bool = true                   ## Whether effect can critical hit
@export var crit_multiplier: float = 2.0            ## Critical hit multiplier

## Apply this effect to the given context
func apply_effect(actor: Node, target: Node, all_enemies: Array, all_allies: Array) -> Dictionary:
	var result = {
		"success": false,
		"targets_hit": [],
		"total_value": 0,
		"crit": false,
		"effects_applied": []
	}
	
	# Check conditions
	if not _check_conditions(actor, target):
		return result
	
	# Get targets based on targeting mode
	var targets = _get_targets(actor, target, all_enemies, all_allies)
	if targets.is_empty():
		return result
	
	# Calculate value with scaling
	var calculated_value = _calculate_value(actor)
	
	# Check for critical hit
	var is_critical = can_crit and _roll_critical()
	if is_critical:
		calculated_value = int(calculated_value * crit_multiplier)
	
	# Apply effect to each target
	for single_target in targets:
		var target_result = _apply_to_target(single_target, calculated_value, is_critical)
		result["targets_hit"].append(single_target)
		result["total_value"] += target_result.get("value", 0)
		result["effects_applied"].append(target_result)
	
	result["success"] = true
	result["crit"] = is_critical
	
	return result

## Get targets based on targeting configuration
func _get_targets(actor: Node, primary_target: Node, all_enemies: Array, all_allies: Array) -> Array:
	match targeting:
		EffectTargeting.ACTOR:
			return [actor] if actor else []
		EffectTargeting.TARGET:
			return [primary_target] if primary_target else []
		EffectTargeting.ALL_ENEMIES:
			return all_enemies
		EffectTargeting.ALL_ALLIES:
			return all_allies
		EffectTargeting.ALL_UNITS:
			return all_enemies + all_allies
		EffectTargeting.RANDOM_ENEMY:
			return [all_enemies.pick_random()] if not all_enemies.is_empty() else []
		EffectTargeting.RANDOM_ALLY:
			return [all_allies.pick_random()] if not all_allies.is_empty() else []
		EffectTargeting.CUSTOM_SELECTION:
			# Would need custom logic implementation
			return [primary_target] if primary_target else []
		_:
			return []

## Calculate final value with scaling
func _calculate_value(actor: Node) -> int:
	var final_value = value
	
	if scaling.is_empty():
		return final_value
	
	# Apply stat scaling
	for stat_name in scaling:
		var scaling_value = scaling[stat_name]
		if actor and actor.has_method("get_stat"):
			var stat_value = actor.get_stat(stat_name)
			final_value += int(stat_value * scaling_value)
	
	return final_value

## Apply effect to a single target
func _apply_to_target(target: Node, calculated_value: int, is_critical: bool) -> Dictionary:
	var result = {
		"target": target,
		"value": 0,
		"effect_type": EffectType.keys()[effect_type]
	}
	
	if not target:
		return result
	
	match effect_type:
		EffectType.DAMAGE:
			result["value"] = _apply_damage(target, calculated_value, is_critical)
		EffectType.HEAL:
			result["value"] = _apply_heal(target, calculated_value)
		EffectType.SHIELD:
			result["value"] = _apply_shield(target, calculated_value)
		EffectType.BUFF:
			result["value"] = _apply_buff(target, calculated_value)
		EffectType.DEBUFF:
			result["value"] = _apply_debuff(target, calculated_value)
		EffectType.STUN:
			result["value"] = _apply_stun(target, calculated_value)
		EffectType.DRAIN:
			result["value"] = _apply_drain(target, calculated_value)
		EffectType.KNOCKBACK:
			result["value"] = _apply_knockback(target, calculated_value)
		EffectType.LETHAL:
			result["value"] = _apply_lethal(target, calculated_value)
		_:
			# Custom effects would need script implementation
			pass
	
	return result

func _apply_damage(target: Node, damage: int, is_critical: bool) -> int:
	if target.has_method("take_damage"):
		target.take_damage(damage)
		return damage
	return 0

func _apply_heal(target: Node, heal_amount: int) -> int:
	if target.has_method("take_healing"):
		target.take_healing(heal_amount)
		return heal_amount
	return 0

func _apply_shield(target: Node, shield_amount: int) -> int:
	if target.has_method("add_shield"):
		target.add_shield(shield_amount)
		return shield_amount
	return 0

func _apply_buff(target: Node, buff_amount: int) -> int:
	# Would need buff system integration
	return buff_amount

func _apply_debuff(target: Node, debuff_amount: int) -> int:
	# Would need debuff system integration
	return debuff_amount

func _apply_stun(target: Node, stun_duration: int) -> int:
	if target.has_method("apply_stun"):
		target.apply_stun(stun_duration)
		return stun_duration
	return 0

func _apply_drain(target: Node, drain_amount: int) -> int:
	if target.has_method("take_damage"):
		var actual_drain = target.take_damage(drain_amount)
		# Would need to heal actor by drain amount
		return actual_drain
	return 0

func _apply_knockback(target: Node, knockback_force: int) -> int:
	if target.has_method("apply_knockback"):
		target.apply_knockback(knockback_force)
		return knockback_force
	return 0

func _apply_lethal(target: Node, threshold: int) -> int:
	if target.has_method("get_current_health") and target.has_method("is_defeated"):
		var current_health = target.get_current_health()
		if current_health <= threshold and not target.is_defeated():
			if target.has_method("instant_kill"):
				target.instant_kill()
				return current_health
	return 0

## Check if conditions are met
func _check_conditions(actor: Node, target: Node) -> bool:
	for condition in conditions:
		if not condition.evaluate(actor, target):
			return false
	return true

## Roll for critical hit
func _roll_critical() -> bool:
	# Would need crit chance from actor stats
	# For now, assume 5% crit chance
	return randf() < 0.05

## Get effect description for UI
func get_description() -> String:
	var description = ""
	
	match effect_type:
		EffectType.DAMAGE:
			description = "Deal %d damage" % value
		EffectType.HEAL:
			description = "Heal for %d HP" % value
		EffectType.SHIELD:
			description = "Grant %d shield" % value
		EffectType.BUFF:
			description = "Buff target"
		EffectType.DEBUFF:
			description = "Debuff target"
		EffectType.STUN:
			description = "Stun target"
		EffectType.DRAIN:
			description = "Drain %d HP" % value
		EffectType.KNOCKBACK:
			description = "Knockback target"
		EffectType.LETHAL:
			description = "Instant kill if below %d HP" % value
		_:
			description = "Custom effect"
	
	if is_percentage:
		description += " (%d%%)" % value
	
	return description
