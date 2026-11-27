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

enum QTEType {
	NONE,               # No QTE
	TIMING,             # Timing-based QTE (press at right moment)
	BUTTON_MASH,        # Button mash QTE (rapid pressing). Not implemented yet: plays as TIMING
	SEQUENCE            # Sequence input QTE (specific button order). Not implemented yet: plays as TIMING
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
@export var strike_multipliers: Array[float] = []     ## Per-strike damage multiplier on top of effect value. [1.0, 1.2, 1.5] = escalating hits.
@export var strike_qte_difficulties: Array[float] = [] ## Per-strike QTE difficulty (0.0 = easy, 1.0 = hard).
@export var strike_qte_windows: Array[float] = []     ## Per-strike QTE window duration in seconds (0 = no QTE on that strike). Multi-strike cards use these, not qte_type.

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

# ─────────────────────────────────────────────────────────────────────────────
# Effect Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Effects")
@export var primary_effect: Resource                 ## Main effect configuration
@export var secondary_effects: Array[Resource] = [] ## Additional effects
@export var effect_conditions: Array[Resource] = [] ## Conditions for effect execution

# ─────────────────────────────────────────────────────────────────────────────
# Visual Effect Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Visual Effects")
@export var vfx_on_actor: Resource                   ## Visual effects on the actor
@export var vfx_on_target: Resource                  ## Visual effects on target(s)
@export var camera_effects: Resource        ## Camera shake, zoom, etc.
@export var screen_effects: Resource        ## Screen flash, time slow, etc.

# ─────────────────────────────────────────────────────────────────────────────
# Projectile Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Projectile")
@export var projectile_enabled: bool = false           ## Whether card uses a projectile
@export var projectile_scene: String = ""              ## Path to projectile scene
@export var projectile_speed: float = 10.0            ## Base travel speed of projectile
@export var projectile_speed_curve: Curve = null     ## Speed over time (slow start, fast travel)
@export var projectile_lifetime: float = 5.0           ## Maximum projectile lifetime
@export var projectile_arc: float = 0.0                ## Arc height for projectile trajectory
@export var projectile_arc_curve: Curve = null        ## Arc height over time for dynamic curvature
@export var projectile_curve_influence: float = 0.5     ## How much the curve affects path (0=straight, 1=full curve)
@export var projectile_fire_simultaneously: bool = false  ## Fire all projectiles at once (multi-projectile cards)
@export var projectile_spawn_spread: float = 0.5        ## Random spread radius in world units (meters) for spawn position (ring facing forward from actor)
@export var projectile_trajectory_spread: float = 0.2    ## Random variance in arc height for trajectory variety (projectiles always reach target but take different curved paths)
@export var projectile_wait_for_impact: bool = true     ## Multi-strike: wait for projectile impact before next strike
@export var projectile_strike_delay: float = 0.3        ## Multi-strike: delay between strikes if not waiting for impact
@export var projectile_scale: Vector3 = Vector3(1, 1, 1)  ## Scale of the projectile VFX
@export var projectile_aoe: bool = false               ## Single projectile damages all targets (instead of one projectile per target)

# ─────────────────────────────────────────────────────────────────────────────
# Audio Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Audio")
@export var cast_sound: Resource                    ## Sound when card is cast
@export var hit_sound: Resource                     ## Sound when effect hits target
@export var impact_sound: Resource                 ## Sound on impact/damage

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
@export var qte_difficulty: float = 0.5                ## Difficulty level (0.0-1.0): sets the QTE length only when qte_window_duration is 0
@export var qte_window_duration: float = 2.0           ## Time window for QTE input
@export var qte_success_multiplier: float = 0.0        ## Damage/effect multiplier on success (0 = the QTE config's)
@export var qte_failure_multiplier: float = 0.0        ## Damage/effect multiplier on failure (0 = the QTE config's)
@export var qte_sequence: Array[String] = []          ## Button sequence for sequence QTEs
@export var qte_mash_count: int = 5                    ## Required button presses for mash QTEs

# ─────────────────────────────────────────────────────────────────────────────
# State and Debuff Configuration
# ─────────────────────────────────────────────────────────────────────────────
@export_group("States & Debuffs")
@export var applies_states: Array[Resource] = []   ## States to apply to targets
@export var applies_self_states: Array[Resource] = [] ## States to apply to self (chance, duration and stacking live on each StateConfig)

# ─────────────────────────────────────────────────────────────────────────────
# Card Metadata
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Metadata")
@export var card_name: String = ""                     ## Display name of the card
@export var card_rarity: CardRarity = CardRarity.COMMON
@export var card_tags: Array[String] = []              ## Tags for filtering and grouping
@export var card_description: String = ""              ## Flavor text and description
@export var ap_cost: int = 1                           ## AP cost to play the card

# ─────────────────────────────────────────────────────────────────────────────
# Card Display Assets
# ─────────────────────────────────────────────────────────────────────────────
@export_group("Display Assets")
@export var background_sprite: Texture2D = null        ## Type-based background texture
@export var main_image: Texture2D = null               ## Character portrait or icon
@export var attack_icon: Texture2D = null               ## Attack damage icon
@export var effect_icon: Texture2D = null               ## Effect/special ability icon
@export var card_frame_texture: Texture2D = null        ## Outer frame/border texture
@export var name_banner_texture: Texture2D = null      ## Textured banner for card name
@export var cost_badge_texture: Texture2D = null       ## Cost badge texture
@export var type_icon: Texture2D = null                 ## Card type indicator icon

## Helper function to check if card should trigger QTE
## (The global switch is [method QTEManager.wants_card_qte].)
func should_trigger_qte() -> bool:
	return qte_type != QTEType.NONE

## Parse QTE type from string
func _parse_qte_type(type_string: String) -> QTEType:
	match type_string.to_lower():
		"none": return QTEType.NONE
		"timing": return QTEType.TIMING
		"button_mash": return QTEType.BUTTON_MASH
		"sequence": return QTEType.SEQUENCE
		_: return QTEType.NONE

## Parse QTE timing from string
## Helper function to get target list based on target type
func get_targets(actor: Node, all_enemies: Array, all_allies: Array) -> Array:
	match target_type:
		TargetScope.SELF:
			return [actor] if actor else []
		TargetScope.SINGLE_ENEMY:
			if target_selection_mode == SelectionMode.MANUAL:
				return all_enemies
			return _get_single_target(all_enemies, actor)
		TargetScope.ALL_ENEMIES:
			return all_enemies
		TargetScope.SINGLE_ALLY:
			if target_selection_mode == SelectionMode.MANUAL:
				return all_allies
			return _get_single_target(all_allies, actor)
		TargetScope.ALL_ALLIES:
			return all_allies
		TargetScope.SINGLE_TARGET:
			if target_selection_mode == SelectionMode.MANUAL:
				return all_enemies + all_allies
			return _get_single_target(all_enemies + all_allies, actor)
		TargetScope.ALL_UNITS:
			return all_enemies + all_allies
		TargetScope.ALL_ALLIES_SELF:
			return all_allies + [actor]
		_:
			return []

func _get_single_target(targets: Array, actor: Node = null) -> Array:
	if targets.is_empty():
		return []
	
	match target_selection_mode:
		SelectionMode.AUTO_CLOSEST:
			return [_get_closest_target(targets, actor)]
		SelectionMode.AUTO_RANDOM:
			return [targets.pick_random()]
		SelectionMode.AUTO_WEAKEST:
			return [_get_weakest_target(targets)]
		SelectionMode.AUTO_STRONGEST:
			return [_get_strongest_target(targets)]
		_:
			return [targets[0]] # Default to first target

func _get_closest_target(targets: Array, actor: Node = null) -> Node:
	if targets.is_empty():
		return null
	if not actor is Node3D:
		return targets[0]
	var closest: Node = targets[0]
	var best := INF
	for target in targets:
		if target is Node3D:
			var d: float = (target as Node3D).global_position.distance_squared_to((actor as Node3D).global_position)
			if d < best:
				best = d
				closest = target
	return closest

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
