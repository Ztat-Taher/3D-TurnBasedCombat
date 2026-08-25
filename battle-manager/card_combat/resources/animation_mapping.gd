class_name AnimationMapping
extends Resource
## Animation mapping resource for character-specific animation remapping
## Allows cards to use generic animation names that are remapped to character-specific animations

@export var animation_map: Dictionary = {}  ## Maps generic animation names to character-specific animations
## Example: {"attack": "warrior_slash", "magic_cast": "warrior_shout", "heal": "warrior_rally"}

## Resolve a generic animation name to a character-specific animation
## Returns the mapped name if found, otherwise returns the original generic name
func resolve_animation(generic_name: String) -> String:
	if generic_name.is_empty():
		return generic_name
	
	if animation_map.has(generic_name):
		var mapped_name = animation_map[generic_name]
		print("AnimationMapping: Resolved '%s' to '%s'" % [generic_name, mapped_name])
		return mapped_name
	
	# No mapping found, return original name
	return generic_name

## Add or update an animation mapping
func add_mapping(generic_name: String, specific_name: String):
	animation_map[generic_name] = specific_name

## Remove an animation mapping
func remove_mapping(generic_name: String):
	animation_map.erase(generic_name)

## Check if a mapping exists for a generic name
func has_mapping(generic_name: String) -> bool:
	return animation_map.has(generic_name)

## Get all mapped generic names
func get_mapped_names() -> Array[String]:
	return animation_map.keys()

## Validate the animation mapping configuration
func validate() -> Array[String]:
	var issues: Array[String] = []
	
	if animation_map.is_empty():
		issues.append("Animation mapping is empty")
	
	for key in animation_map.keys():
		if not key is String:
			issues.append("Animation map key '%s' is not a String" % str(key))
		if not animation_map[key] is String:
			issues.append("Animation map value for '%s' is not a String" % str(key))
	
	return issues

## Create a preset animation mapping for a warrior character
static func create_warrior_mapping() -> AnimationMapping:
	var mapping = AnimationMapping.new()
	mapping.animation_map = {
		"attack": "warrior_slash",
		"heavy_attack": "warrior_heavy_slash",
		"magic_cast": "warrior_shout",
		"heal": "warrior_rally",
		"defend": "warrior_shield_raise",
		"hit": "warrior_hit",
		"death": "warrior_death"
	}
	return mapping

## Create a preset animation mapping for a wizard character
static func create_wizard_mapping() -> AnimationMapping:
	var mapping = AnimationMapping.new()
	mapping.animation_map = {
		"attack": "wizard_staff_bash",
		"heavy_attack": "wizard_fireball_cast",
		"magic_cast": "wizard_spell_cast",
		"heal": "wizard_heal_cast",
		"defend": "wizard_barrier",
		"hit": "wizard_hit",
		"death": "wizard_death"
	}
	return mapping

## Create a preset animation mapping for a ninja character
static func create_ninja_mapping() -> AnimationMapping:
	var mapping = AnimationMapping.new()
	mapping.animation_map = {
		"attack": "ninja_quick_slash",
		"heavy_attack": "ninja_combo_attack",
		"magic_cast": "ninja_ninja_magic",
		"heal": "ninja_meditate",
		"defend": "ninja_dodge",
		"hit": "ninja_hit",
		"death": "ninja_vanish"
	}
	return mapping

## Create a preset animation mapping for a cleric character
static func create_cleric_mapping() -> AnimationMapping:
	var mapping = AnimationMapping.new()
	mapping.animation_map = {
		"attack": "cleric_mace_strike",
		"heavy_attack": "cleric_smite",
		"magic_cast": "cleric_prayer",
		"heal": "cleric_divine_heal",
		"defend": "cleric_blessing",
		"hit": "cleric_hit",
		"death": "cleric_death"
	}
	return mapping
