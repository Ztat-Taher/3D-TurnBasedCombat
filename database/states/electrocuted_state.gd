## ElectrocutedState
## Makes the entity vulnerable (takes more damage) and weak (deals less damage)
## Based on the user's specification for Electrocuted effect

class_name ElectrocutedState
extends State

@export var overlay_material: ShaderMaterial = null  # VFX overlay to apply

func _init():
	state_name = "Electrocuted"
	state_type = StateType.DEBUFF
	state_description = "Takes 50% more damage and deals 50% less damage"
	icon_texture = preload("res://assets/images/ui/status_effects/electrocuted.png")
	damage_taken_multiplier = 1.5  # Take 50% more damage
	damage_dealt_multiplier = 0.5  # Deal 50% less damage
	turns_active = 2  # Lasts 2 turns by default
	can_be_cured = true

## Load the lightning overlay material
func load_overlay_material() -> ShaderMaterial:
	if overlay_material:
		return overlay_material
	
	var overlay_path = "res://assets/effects/overlays/lightning_overlay.tres"
	if ResourceLoader.exists(overlay_path):
		overlay_material = ResourceLoader.load(overlay_path) as ShaderMaterial
	return overlay_material

## Apply the overlay to a battler
func apply_overlay_to_battler(battler: Battler) -> void:
	var overlay = load_overlay_material()
	if not overlay:
		return
	
	# Use battler's overlay management system
	if battler.has_method("add_overlay"):
		battler.add_overlay(Battler.OverlayType.STATUS, overlay, 5, state_name)

## Remove the overlay from a battler
func remove_overlay_from_battler(battler: Battler) -> void:
	# Use battler's overlay management system
	if battler.has_method("remove_overlay"):
		battler.remove_overlay(state_name)