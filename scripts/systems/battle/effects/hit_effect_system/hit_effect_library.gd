class_name HitEffectLibrary
extends Resource
## Library of hit effects organized by damage type and element
## Maps damage/element combinations to arrays of HitEffectConfig

## Dictionary mapping type keys to arrays of HitEffectConfig
## Key format: "damage_type_element" or just "element" or "damage_type"
## Examples: "physical", "fire", "physical_fire", "magical_lightning"
@export var effect_map: Dictionary = {}

## Get effects for a specific damage type and element
## damage_type: e.g., "physical", "magical", "true_damage"
## element: e.g., "fire", "ice", "lightning", "none"
## Returns array of HitEffectConfig (may be empty if no match found)
func get_effects_for_type(damage_type: String, element: String) -> Array[HitEffectConfig]:
	# Try exact match first: damage_type_element
	var combined_key = "%s_%s" % [damage_type.to_lower(), element.to_lower()]
	if effect_map.has(combined_key):
		var effects: Array[HitEffectConfig] = []
		effects.assign(effect_map[combined_key])
		return effects
	
	# Try element only
	var element_key = element.to_lower()
	if effect_map.has(element_key):
		var effects: Array[HitEffectConfig] = []
		effects.assign(effect_map[element_key])
		return effects
	
	# Try damage type only
	var damage_key = damage_type.to_lower()
	if effect_map.has(damage_key):
		var effects: Array[HitEffectConfig] = []
		effects.assign(effect_map[damage_key])
		return effects
	
	# Fallback to physical if no match
	if effect_map.has("physical"):
		var effects: Array[HitEffectConfig] = []
		effects.assign(effect_map["physical"])
		return effects
	
	# Return empty array if nothing found
	return []

## Add an effect to the library
## key: The type key (e.g., "fire", "physical_fire")
## effect: The HitEffectConfig to add
func add_effect(key: String, effect: HitEffectConfig) -> void:
	var normalized_key = key.to_lower()
	if not effect_map.has(normalized_key):
		effect_map[normalized_key] = []
	effect_map[normalized_key].append(effect)

## Remove an effect from the library
## key: The type key
## effect: The HitEffectConfig to remove
func remove_effect(key: String, effect: HitEffectConfig) -> void:
	var normalized_key = key.to_lower()
	if effect_map.has(normalized_key):
		effect_map[normalized_key].erase(effect)
		if effect_map[normalized_key].is_empty():
			effect_map.erase(normalized_key)

## Get all keys in the library
func get_all_keys() -> Array[String]:
	return effect_map.keys()

## Check if a key exists in the library
func has_key(key: String) -> bool:
	return effect_map.has(key.to_lower())

## Clear all effects from the library
func clear() -> void:
	effect_map.clear()

## Create a default library with basic effects
static func create_default() -> HitEffectLibrary:
	var library = HitEffectLibrary.new()
	# Effects will be populated by the default_hit_effects.tres resource
	return library
