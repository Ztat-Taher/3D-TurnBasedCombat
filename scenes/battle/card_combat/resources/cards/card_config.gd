class_name CardConfig
extends Resource
## Comprehensive card configuration resource for modular, resource-driven card behavior
## Contains all configurable aspects of card behavior without requiring code changes

# Enums for card configuration
enum TargetScope {
	SELF,               # Effect applied to caster only
	SINGLE_ENEMY,       # Targets one enemy
	ALL_ENEMIES,        # AOE on all enemies
	SINGLE_ALLY,        # Targets one ally (including self)
	ALL_ALLIES,         # AOE on all allies
	SINGLE_TARGET,      # Can target any single unit
	ALL_UNITS,          # AOE on all units
	ALL_ALLIES_SELF     # AOE on all allies including self
}

enum SelectionMode {
	MANUAL,             # Player manually selects target
	AUTO_CLOSEST,       # Automatically targets closest enemy
	AUTO_RANDOM,        # Randomly selects valid target
	AUTO_WEAKEST,       # Targets weakest enemy
	AUTO_STRONGEST      # Targets strongest enemy
}

enum EffectTiming {
	IMMEDIATE,          # Effect triggers immediately
	AFTER_ANIMATION,    # Effect triggers after animation completes
	ON_HIT,             # Effect triggers on hit frame
	ON_IMPACT,          # Effect triggers on impact with target
	CHANNEL_START,      # Effect triggers when channeling starts
	CHANNEL_END         # Effect triggers when channeling ends
}

enum QTEType {
	NONE,               # No QTE
	TIMING,             # Timing-based QTE (press at right moment)
	BUTTON_MASH,        # Button mash QTE (rapid pressing)
	SEQUENCE            # Sequence input QTE (specific button order)
}

enum QTETiming {
	BEFORE_ATTACK,      # QTE before attack animation
	ON_HIT_FRAME,       # QTE on hit frame
	AFTER_ATTACK        # QTE after attack animation
}

enum DamageType {
	PHYSICAL,           # Physical damage
	MAGICAL,            # Magical damage
	TRUE_DAMAGE         # True damage (ignores defense)
}

enum CardRarity {
	COMMON,             # Common cards
	UNCOMMON,           # Uncommon cards
	RARE,               # Rare cards
	EPIC,               # Epic cards
	LEGENDARY           # Legendary cards
}

enum Element {
	NONE,               # No element
	FIRE,               # Fire element
	ICE,                # Ice element
	LIGHTNING,          # Lightning element
	EARTH,              # Earth element
	WIND,               # Wind element
	LIGHT,              # Light element
	DARK                # Dark element
}

# Animation Configuration (Simple - just the animation name)
@export_group("Animation")
@export var animation_name: String = ""  ## Animation slot to play (single-strike cards). Must be empty when is_multi_strike = true.

# ─────────────────────────────────────────────────────────────────────────────
# Multi-Strike
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Multi-Strike")
@export var is_multi_strike: bool = false              ## Enable the combo sequence. Disable animation_name when true.
@export var strike_animations: Array[String] = []     ## Animation slot names in order, e.g. ["melee_combo_1", "melee_combo_2", "melee_combo_3"].
@export var strike_multipliers: Array[float] = []     ## Per-strike damage multiplier on top of base_damage. [1.0, 1.2, 1.5] = escalating hits.
@export var strike_qte_difficulties: Array[float] = [] ## Per-strike QTE difficulty (0.0 = easy, 1.0 = hard).
@export var strike_qte_windows: Array[float] = []     ## Per-strike QTE window duration in seconds.

## Unified per-strike timing offset (seconds).
##   > 0  →  delay:  pause this many seconds AFTER the previous clip ends before firing.
##   = 0  →  seamless: next strike fires exactly at clip end.
##   < 0  →  lead:   fire |value| seconds BEFORE the clip ends (overlap / chain).
## Last entry is unused (no strike follows the final hit).
## Empty = use CardBattleConfig.default_strike_timing for every strike.
@export var strike_timing: Array[float] = []

# ─────────────────────────────────────────────────────────────────────────────
# Targeting Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Targeting")
@export var target_type: TargetScope = TargetScope.SINGLE_ENEMY
@export var target_selection_mode: SelectionMode = SelectionMode.MANUAL
@export var target_filter: String = ""                ## Filter conditions for valid targets
@export var requires_los: bool = false                ## Whether line of sight is required

# ─────────────────────────────────────────────────────────────────────────────
# Effect Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Effects")
@export var primary_effect: Resource                 ## Main effect configuration
@export var secondary_effects: Array[Resource] = [] ## Additional effects
@export var effect_timing: EffectTiming = EffectTiming.ON_HIT
@export var effect_conditions: Array[Resource] = [] ## Conditions for effect execution

# ─────────────────────────────────────────────────────────────────────────────
# Visual Effect Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Visual Effects")
@export var vfx_on_actor: Resource                   ## Visual effects on the actor
@export var vfx_on_target: Resource                  ## Visual effects on target(s)
@export var vfx_on_projectile: Resource              ## Projectile visual effects
@export var camera_effects: Resource        ## Camera shake, zoom, etc.
@export var screen_effects: Resource        ## Screen flash, time slow, etc.

# ─────────────────────────────────────────────────────────────────────────────
# Projectile Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Projectile")
@export var projectile_enabled: bool = false           ## Whether card uses a projectile
@export var projectile_scene: String = ""              ## Path to projectile scene
@export var projectile_speed: float = 10.0            ## Travel speed of projectile
@export var projectile_lifetime: float = 5.0           ## Maximum projectile lifetime
@export var projectile_arc: float = 0.0                ## Arc height for projectile trajectory
@export var projectile_spawn_point: String = "actor"  ## Where projectile spawns

# ─────────────────────────────────────────────────────────────────────────────
# Audio Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Audio")
@export var cast_sound: Resource                    ## Sound when card is cast
@export var hit_sound: Resource                     ## Sound when effect hits target
@export var impact_sound: Resource                 ## Sound on impact/damage
@export var loop_sound: Resource                   ## Looping sound during channel/projectile
@export var voice_line: String = ""                    ## Character voice line to play

# ─────────────────────────────────────────────────────────────────────────────
# QTE Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("QTE Settings")
@export var qte_type_string: String = "none"           ## String storage for enum (workaround for .tres loading)
var qte_type: QTEType = QTEType.NONE:
	get:
		return _parse_qte_type(qte_type_string)
	set(value):
		qte_type_string = QTEType.keys()[value]
@export var qte_difficulty: float = 0.5                ## Difficulty level (0.0-1.0)
@export var qte_timing_string: String = "before_attack" ## String storage for enum
var qte_timing: QTETiming = QTETiming.BEFORE_ATTACK:
	get:
		return _parse_qte_timing(qte_timing_string)
	set(value):
		qte_timing_string = QTETiming.keys()[value]
@export var qte_window_duration: float = 2.0           ## Time window for QTE input
@export var qte_success_multiplier: float = 1.5        ## Damage/effect multiplier on success
@export var qte_failure_multiplier: float = 1.0        ## Damage/effect multiplier on failure
@export var qte_sequence: Array[String] = []          ## Button sequence for sequence QTEs
@export var qte_mash_count: int = 5                    ## Required button presses for mash QTEs
@export var qte_mash_window: float = 3.0               ## Time window for mash QTEs

# ─────────────────────────────────────────────────────────────────────────────
# Damage and Stats Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Damage & Stats")
@export var base_damage: int = 0                       ## Base damage value
@export var damage_scaling: Dictionary = {}            ## Stat scaling (attack, magic, etc.)
@export var damage_type: DamageType = DamageType.PHYSICAL
@export var heal_amount: int = 0                       ## Base healing amount
@export var shield_amount: int = 0                     ## Shield/defense amount
@export var stat_modifiers: Dictionary = {}           ## Temporary stat changes

# ─────────────────────────────────────────────────────────────────────────────
# State and Debuff Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("States & Debuffs")
@export var applies_states: Array[Resource] = []   ## States to apply to targets
@export var applies_self_states: Array[Resource] = [] ## States to apply to self
@export var state_chance: float = 1.0                  ## Chance to apply states (0.0-1.0)
@export var state_duration: int = 1                    ## Duration in turns

# ─────────────────────────────────────────────────────────────────────────────
# Card Metadata
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Metadata")
@export var card_rarity: CardRarity = CardRarity.COMMON
@export var card_element: Element = Element.NONE
@export var card_tags: Array[String] = []              ## Tags for filtering and grouping
@export var card_description: String = ""              ## Flavor text and description

## Helper function to get total damage with scaling
func get_scaled_damage(actor_stats: Dictionary) -> int:
	var total_damage = base_damage
	
	# Apply stat scaling
	for stat_name in damage_scaling:
		var scaling_value = damage_scaling[stat_name]
		if actor_stats.has(stat_name):
			total_damage += int(actor_stats[stat_name] * scaling_value)
	
	return total_damage

## Helper function to check if card should trigger QTE
func should_trigger_qte() -> bool:
	# Primary check: QTE type is not NONE
	if qte_type != QTEType.NONE:
		return true
	
	# Fallback: Check if card is attack type and has QTE difficulty configured
	# This handles cases where enum loading fails
	if card_tags.has("attack") and qte_difficulty > 0.0:
		return true
	
	return false

## Parse QTE type from string
func _parse_qte_type(type_string: String) -> QTEType:
	match type_string.to_lower():
		"none": return QTEType.NONE
		"timing": return QTEType.TIMING
		"button_mash": return QTEType.BUTTON_MASH
		"sequence": return QTEType.SEQUENCE
		_: return QTEType.NONE

## Parse QTE timing from string
func _parse_qte_timing(timing_string: String) -> QTETiming:
	match timing_string.to_lower():
		"before_attack": return QTETiming.BEFORE_ATTACK
		"on_hit_frame": return QTETiming.ON_HIT_FRAME
		"after_attack": return QTETiming.AFTER_ATTACK
		_: return QTETiming.BEFORE_ATTACK

## Helper function to get target list based on target type
func get_targets(actor: Node, all_enemies: Array, all_allies: Array) -> Array:
	match target_type:
		TargetScope.SELF:
			return [actor] if actor else []
		TargetScope.SINGLE_ENEMY:
			if target_selection_mode == SelectionMode.MANUAL:
				return all_enemies
			return _get_single_target(all_enemies)
		TargetScope.ALL_ENEMIES:
			return all_enemies
		TargetScope.SINGLE_ALLY:
			if target_selection_mode == SelectionMode.MANUAL:
				return all_allies
			return _get_single_target(all_allies)
		TargetScope.ALL_ALLIES:
			return all_allies
		TargetScope.SINGLE_TARGET:
			if target_selection_mode == SelectionMode.MANUAL:
				return all_enemies + all_allies
			return _get_single_target(all_enemies + all_allies)
		TargetScope.ALL_UNITS:
			return all_enemies + all_allies
		TargetScope.ALL_ALLIES_SELF:
			return all_allies + [actor]
		_:
			return []

func _get_single_target(targets: Array) -> Array:
	if targets.is_empty():
		return []
	
	match target_selection_mode:
		SelectionMode.AUTO_CLOSEST:
			return [_get_closest_target(targets)]
		SelectionMode.AUTO_RANDOM:
			return [targets.pick_random()]
		SelectionMode.AUTO_WEAKEST:
			return [_get_weakest_target(targets)]
		SelectionMode.AUTO_STRONGEST:
			return [_get_strongest_target(targets)]
		_:
			return [targets[0]] # Default to first target

func _get_closest_target(targets: Array) -> Node:
	# Implementation would require actor position reference
	# For now, return first target
	return targets[0] if not targets.is_empty() else null

func _get_weakest_target(targets: Array) -> Node:
	var weakest = null
	var lowest_health = INF
	
	for target in targets:
		if target.has_method("get_health_ratio"):
			var health_ratio = target.get_health_ratio()
			if health_ratio < lowest_health:
				lowest_health = health_ratio
				weakest = target
	
	return weakest if weakest else targets[0]

func _get_strongest_target(targets: Array) -> Node:
	var strongest = null
	var highest_health = -INF
	
	for target in targets:
		if target.has_method("get_health_ratio"):
			var health_ratio = target.get_health_ratio()
			if health_ratio > highest_health:
				highest_health = health_ratio
				strongest = target
	
	return strongest if strongest else targets[0]

## Validate configuration and return any issues
func validate() -> Array[String]:
	var issues: Array[String] = []
	
	if projectile_enabled and projectile_scene.is_empty():
		issues.append("Projectile enabled but no scene specified")
	
	if qte_type == QTEType.SEQUENCE and qte_sequence.is_empty():
		issues.append("Sequence QTE type but no sequence specified")
	
	if qte_type == QTEType.BUTTON_MASH and qte_mash_count <= 0:
		issues.append("Button mash QTE type but invalid mash count")
	
	if is_multi_strike and strike_animations.is_empty():
		issues.append("Multi-strike enabled but no strike animations specified")
	
	if is_multi_strike and not animation_name.is_empty():
		issues.append("Multi-strike enabled but animation_name should be empty (use strike_animations instead)")
	
	if is_multi_strike and strike_animations.size() != strike_multipliers.size():
		issues.append("Multi-strike: strike_animations and strike_multipliers arrays must have same size")
	
	if is_multi_strike and strike_animations.size() != strike_qte_windows.size():
		issues.append("Multi-strike: strike_animations and strike_qte_windows arrays must have same size")
	
	return issues
