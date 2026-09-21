## ChilledState
## Causes the entity to skip their turn in the turn queue
## Based on the user's specification for Chilled effect

class_name ChilledState
extends State

@export var overlay_material: ShaderMaterial = null  # VFX overlay to apply
@export var aura_effect: PackedScene = null  # Aura effect scene

func _init():
	state_name = "Chilled"
	state_type = StateType.DEBUFF
	state_description = "Frozen solid - skips their next turn"
	icon_texture = preload("res://assets/images/ui/status_effects/chilled.png")
	skip_turn = true  # Skip turn in the queue
	turns_active = 1  # Lasts 1 turn by default
	can_be_cured = true

## Load the ice overlay material
func load_overlay_material() -> ShaderMaterial:
	if overlay_material:
		return overlay_material
	
	var overlay_path = "res://assets/effects/overlays/ice_overlay.tres"
	if ResourceLoader.exists(overlay_path):
		overlay_material = ResourceLoader.load(overlay_path) as ShaderMaterial
	return overlay_material

## Load the aura effect scene
func load_aura_effect() -> PackedScene:
	if aura_effect:
		return aura_effect
	
	var aura_path = "res://assets/effects/auras/aura_chilled.tscn"
	if ResourceLoader.exists(aura_path):
		aura_effect = ResourceLoader.load(aura_path) as PackedScene
	return aura_effect

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

## Apply aura effect to a battler
func apply_aura_effect(battler: Battler) -> void:
	var aura = load_aura_effect()
	if not aura:
		return
	
	# Use battler's systematic aura application method
	if battler.has_method("apply_aura_effect"):
		var aura_instance = battler.apply_aura_effect(aura)
		if aura_instance:
			# Play open animation
			if aura_instance.has_node("AnimationPlayer"):
				var anim_player = aura_instance.get_node("AnimationPlayer")
				if anim_player:
					anim_player.play("open")
			
			# Store reference for cleanup
			if not battler.has_meta("chilled_aura"):
				battler.set_meta("chilled_aura", aura_instance)

## Remove aura effect from a battler
func remove_aura_effect(battler: Battler) -> void:
	if battler.has_meta("chilled_aura"):
		var aura = battler.get_meta("chilled_aura")
		if is_instance_valid(aura):
			# Use battler's systematic aura removal method
			if battler.has_method("remove_aura_effect"):
				battler.remove_aura_effect(aura)
			else:
				aura.queue_free()
		battler.remove_meta("chilled_aura")