extends Node
## Global singleton for hit effect library management
## Provides a centralized location for hit effect configuration

## The current hit effect library being used
var current_library: HitEffectLibrary = null

## Default library path
const DEFAULT_LIBRARY_PATH = "res://database/effects/default_hit_effects.tres"

func _ready() -> void:
	# Load the default library
	load_default_library()

## Load the default hit effect library
func load_default_library() -> void:
	if ResourceLoader.exists(DEFAULT_LIBRARY_PATH):
		current_library = load(DEFAULT_LIBRARY_PATH) as HitEffectLibrary
		if not current_library:
			push_error("Failed to load default hit effect library from: %s" % DEFAULT_LIBRARY_PATH)
	else:
		push_warning("Default hit effect library not found at: %s" % DEFAULT_LIBRARY_PATH)
		# Create an empty library as fallback
		current_library = HitEffectLibrary.new()

## Set a custom hit effect library
## library: The HitEffectLibrary resource to use
func set_library(library: HitEffectLibrary) -> void:
	if library:
		current_library = library
	else:
		push_error("Cannot set null hit effect library")

## Get the current hit effect library
func get_library() -> HitEffectLibrary:
	return current_library

## Get effects for a specific damage type and element
## damage_type: e.g., "physical", "magical", "true_damage"
## element: e.g., "fire", "ice", "lightning", "none"
## Returns array of HitEffectConfig
func get_effects(damage_type: String, element: String) -> Array[HitEffectConfig]:
	if current_library:
		return current_library.get_effects_for_type(damage_type, element)
	return []

## Reload the default library (useful for development/debugging)
func reload_default_library() -> void:
	load_default_library()
