class_name AnimationMapping
extends Resource
## Standardised animation mapping resource for ally/player characters.
## Maps canonical generic slot names to character-specific AnimationTree state names,
## with optional per-slot metadata (hit-frame ratio, movement requirement).
##
## ─── CANONICAL SLOTS ───────────────────────────────────────────────────────────
##   Locomotion  : IDLE, WALK
##   Defensive   : DODGE, PARRY, JUMP, JUMP_LAND, HIT, DEATH
##   Offensive   : MELEE_COMBO_1, MELEE_COMBO_2, MELEE_COMBO_3,
##                 RANGED_CAST_1, RANGED_CAST_2

# ---------------------------------------------------------------------------
# Standard slot name constants — use these everywhere instead of raw strings
# ---------------------------------------------------------------------------
const IDLE          := "idle"
const WALK          := "walk"
const WALK_BACK     := "walk_back"
const DODGE         := "dodge"
const PARRY         := "parry"
const JUMP          := "jump"
const JUMP_LAND     := "jump_land"
const HIT           := "hit"
const DEATH         := "death"
const MELEE_COMBO_1 := "melee_combo_1"
const MELEE_COMBO_2 := "melee_combo_2"
const MELEE_COMBO_3 := "melee_combo_3"
const RANGED_CAST_1 := "ranged_cast_1"
const RANGED_CAST_2 := "ranged_cast_2"

## All canonical slots in declaration order — useful for validation.
const ALL_SLOTS: Array = [
	IDLE, WALK, WALK_BACK,
	DODGE, PARRY, JUMP, JUMP_LAND, HIT, DEATH,
	MELEE_COMBO_1, MELEE_COMBO_2, MELEE_COMBO_3,
	RANGED_CAST_1, RANGED_CAST_2,
]

## Slots that live inside the combat_actions sub-state-machine.
const COMBAT_ACTION_SLOTS: Array = [
	MELEE_COMBO_1, MELEE_COMBO_2, MELEE_COMBO_3,
	RANGED_CAST_1, RANGED_CAST_2,
]

# ---------------------------------------------------------------------------
# Exported data
# ---------------------------------------------------------------------------

## Maps canonical slot name -> character-specific AnimationTree state name.
## Example: {"melee_combo_1": "warrior_slash", "ranged_cast_1": "warrior_shout"}
@export var animation_map: Dictionary = {}

## Per-slot hit-frame ratio overrides.
## If a slot is absent the battler's default hit_frame_ratio is used.
## Example: {"melee_combo_1": 0.35, "melee_combo_2": 0.65, "melee_combo_3": 0.75}
@export var hit_frame_ratios: Dictionary = {}

## Per-slot advance-to-target override.
## Defaults: melee slots = true, everything else = false.
## Set an entry here only when you need to *override* the default.
@export var advance_overrides: Dictionary = {}

# ---------------------------------------------------------------------------
# Resolution API
# ---------------------------------------------------------------------------

## Resolve a canonical slot name to the character-specific AnimationTree state name.
## Returns the mapped name when found, otherwise returns the original slot name unchanged
## (allowing direct state names from cards/code to pass through).
func resolve_animation(slot_name: String) -> String:
	if slot_name.is_empty():
		return slot_name
	if animation_map.has(slot_name):
		return animation_map[slot_name]
	return slot_name

## Return the hit-frame ratio for a given slot, or -1.0 if no override is set.
## Battler code should fall back to Battler.hit_frame_ratio when -1.0 is returned.
func get_hit_frame_ratio(slot_name: String) -> float:
	if hit_frame_ratios.has(slot_name):
		return float(hit_frame_ratios[slot_name])
	return -1.0

## Return whether the character should advance to the target before playing this slot.
## Melee slots default to true; all other slots default to false.
## Override via advance_overrides if a character needs different behaviour.
func requires_advance(slot_name: String) -> bool:
	if advance_overrides.has(slot_name):
		return bool(advance_overrides[slot_name])
	return slot_name in [MELEE_COMBO_1, MELEE_COMBO_2, MELEE_COMBO_3]

## Return true if this slot is routed through the combat_actions sub-state-machine.
func is_combat_action(slot_name: String) -> bool:
	# Check by the resolved state name too, in case the mapping points to a custom name.
	var resolved := resolve_animation(slot_name)
	return slot_name in COMBAT_ACTION_SLOTS or resolved in COMBAT_ACTION_SLOTS

# ---------------------------------------------------------------------------
# Map management helpers
# ---------------------------------------------------------------------------

## Add or update a single slot mapping.
func add_mapping(slot_name: String, state_name: String) -> void:
	animation_map[slot_name] = state_name

## Remove a slot mapping.
func remove_mapping(slot_name: String) -> void:
	animation_map.erase(slot_name)

## Check if a mapping exists for the given slot.
func has_mapping(slot_name: String) -> bool:
	return animation_map.has(slot_name)

## Return all canonical slot names that have mappings.
func get_mapped_names() -> Array[String]:
	var result: Array[String] = []
	for k in animation_map.keys():
		if k is String:
			result.append(k)
	return result

## Validate the mapping and return a list of issue strings (empty = all good).
func validate() -> Array[String]:
	var issues: Array[String] = []
	if animation_map.is_empty():
		issues.append("Animation mapping is empty — no slots defined.")
	for key in animation_map.keys():
		if not key is String:
			issues.append("Key '%s' is not a String." % str(key))
		if not animation_map[key] is String:
			issues.append("Value for key '%s' is not a String." % str(key))
	return issues
