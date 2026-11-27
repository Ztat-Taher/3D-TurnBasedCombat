class_name CardEffect
extends Resource
## Encapsulates individual card effects for modular configuration
## Each effect can be independently configured and combined

## (Values are explicit so saved effects keep their type.)
enum EffectType {
	DAMAGE = 0,         # Deal damage to the target
	HEAL = 1,           # Heal the target
	SHIELD = 2,         # Grant the target `value` Protected hits (each blocks one whole hit)
	STUN = 7,           # The target skips its next `value` turns
	DRAIN = 8,          # Damage the target; the caster heals the HP it lost
	LETHAL = 9,         # Defeat the target outright if its HP is at or below `value` (a percent of max HP with is_percentage)
	CURE = 10,          # Remove `value` of the target's harmful states (0 = all) that can be cured
	DISPEL = 11,        # Remove `value` of the target's helpful states (0 = all) that can be cured
}

## Who the effect lands on. Who a card hits is its target_type: an effect lands
## on that target, or on the caster with ACTOR. The other values are kept for
## saved effects and act as TARGET.
enum EffectTargeting {
	ACTOR,              # Effect applied to actor
	TARGET,             # Effect applied to primary target
	ALL_ENEMIES,        # (as TARGET)
	ALL_ALLIES,         # (as TARGET)
	ALL_UNITS,          # (as TARGET)
	RANDOM_ENEMY,       # (as TARGET)
	RANDOM_ALLY,        # (as TARGET)
	CUSTOM_SELECTION    # (as TARGET)
}

const STUNNED_STATE := preload("res://database/states/resources/stunned_state.tres")
const PROTECTED_STATE := preload("res://database/states/resources/protected_state.tres")

@export var effect_type: EffectType = EffectType.DAMAGE
@export var value: int = 0                          ## Base effect value (damage, heal, shield hits, stun turns, lethal threshold, states cured / dispelled: 0 = all)
@export var targeting: EffectTargeting = EffectTargeting.TARGET
@export var scaling: Dictionary = {}                ## Stat scaling: stat name -> factor added to value (e.g. {"magic": 0.5})
@export var conditions: Array[Resource] = [] ## Conditions for effect execution
@export var is_percentage: bool = false             ## LETHAL: value is a percent of the target's max HP
@export var can_crit: bool = true                   ## Whether this effect's damage can crit (chance: the caster's crit_chance stat)
@export var crit_multiplier: float = 2.0            ## Damage multiplier of a crit

@export var damage_type: String = "physical"        # physical, magical (uses the magic stat), true_damage
@export var element: String = "none"                # fire, ice, lightning, earth, air, magic, none
@export var consume_hand_cards: bool = false        ## If true, damage/value scales with cards consumed from hand

## The battler this effect lands on: the caster for ACTOR, else the cast's
## [param target].
func get_recipient(actor: Node, target: Node) -> Node:
	return actor if targeting == EffectTargeting.ACTOR else target

## Damage multiplier of one hit by [param actor]: [member crit_multiplier] when
## it crits (a roll against the actor's crit_chance percent), else 1.
func roll_crit_multiplier(actor: Node) -> float:
	if not can_crit or actor == null or not "crit_chance" in actor:
		return 1.0
	return crit_multiplier if randf() * 100.0 < float(actor.crit_chance) else 1.0

## Applies this effect from [param actor] to [param recipient] with
## [param amount] (scaling and QTE already in). Damage and healing go through
## [param battle_manager] (formula, hit chance, multipliers, battle events).
## Awaitable: it returns once the effect has resolved.
func apply_to(actor: Battler, recipient: Battler, amount: int, battle_manager) -> void:
	if recipient == null or not is_instance_valid(recipient) or battle_manager == null:
		return
	match effect_type:
		EffectType.DAMAGE:
			await battle_manager.damage_calculation(actor, recipient, amount, null, damage_type, element, true, roll_crit_multiplier(actor))
		EffectType.HEAL:
			battle_manager.heal_calculation(actor, recipient, amount)
		EffectType.SHIELD:
			var shield: State = PROTECTED_STATE.make_instance()
			shield.set_shield_hits(maxi(1, amount))
			recipient.apply_state(shield, actor)
		EffectType.STUN:
			recipient.apply_state(STUNNED_STATE.make_instance(maxi(1, amount)), actor)
		EffectType.DRAIN:
			var health_before := recipient.current_health
			await battle_manager.damage_calculation(actor, recipient, amount, null, damage_type, element, true, roll_crit_multiplier(actor))
			var drained := health_before - recipient.current_health
			if drained > 0 and actor and is_instance_valid(actor) and not actor.is_defeated():
				battle_manager.heal_calculation(actor, actor, drained)
		EffectType.LETHAL:
			if recipient.is_defeated():
				return
			var threshold := amount
			if is_percentage:
				threshold = roundi(recipient.max_health * amount / 100.0)
			if recipient.current_health <= threshold:
				# The whole remaining HP as one attack (a Protected hit still blocks it)
				await recipient.take_damage(recipient.current_health, actor, damage_type, element, true)
				if battle_manager.hud:
					battle_manager.hud.update_health_bars()
		EffectType.CURE, EffectType.DISPEL:
			# A count, not a strength: the authored value, unscaled (a QTE's 0.8
			# would turn 1 into 0 = all). The state decides whether it's harmful
			# and whether it can be removed
			var harmful := effect_type == EffectType.CURE
			recipient.remove_states_if(func(s: State): return s.can_be_cured and s.is_harmful() == harmful, maxi(value, 0))

## Calculate final value with scaling
func _calculate_value(actor: Node, multiplier_from_hand: int = 1) -> int:
	var final_value = value

	if scaling.is_empty():
		return final_value * multiplier_from_hand

	# Apply stat scaling
	for stat_name in scaling:
		var scaling_value = scaling[stat_name]
		if actor and actor.has_method("get_stat"):
			var stat_value = actor.get_stat(stat_name)
			final_value += int(stat_value * scaling_value)
		elif actor and stat_name in actor:
			# Try direct property access as fallback
			var stat_value = actor.get(stat_name)
			final_value += int(stat_value * scaling_value)

	return final_value * multiplier_from_hand

## Check if conditions are met
func _check_conditions(actor: Node, target: Node) -> bool:
	for condition in conditions:
		if not condition.evaluate(actor, target):
			return false
	return true

## Get effect description for UI
func get_description() -> String:
	match effect_type:
		EffectType.DAMAGE:
			if consume_hand_cards:
				return "Deal %d damage per card discarded" % value
			return "Deal %d damage" % value
		EffectType.HEAL:
			return "Heal for %d HP" % value
		EffectType.SHIELD:
			return "Block the next %d hit%s" % [value, "" if value == 1 else "s"]
		EffectType.STUN:
			return "Stun for %d turn%s" % [value, "" if value == 1 else "s"]
		EffectType.DRAIN:
			return "Drain %d HP" % value
		EffectType.LETHAL:
			return "Defeat the target if below %d%s HP" % [value, "%" if is_percentage else ""]
		EffectType.CURE:
			return "Cure all harmful effects" if value <= 0 else "Cure %d harmful effect%s" % [value, "" if value == 1 else "s"]
		EffectType.DISPEL:
			return "Remove all buffs" if value <= 0 else "Remove %d buff%s" % [value, "" if value == 1 else "s"]
	return ""
