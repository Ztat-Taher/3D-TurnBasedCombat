## BurningState
## Stacking DOT effect - damage scales with stack count
## Based on Clair Obscure Expedition 33's burn effect
## Each application adds stacks, damage = stacks * base_damage_per_stack
## Stacks decay by 1 each turn if not renewed

class_name BurningState
extends State

@export var overlay_material: ShaderMaterial = null  # VFX overlay to apply
@export var base_damage_per_stack: int = 5  # Damage per stack per turn

func _init():
	state_name = "Burning"
	state_type = StateType.DOT
	state_description = "Takes fire damage each turn. Damage increases with more stacks."
	icon_texture = preload("res://assets/images/ui/status_effects/burning.png")
	damage_per_turn = 0  # Calculated dynamically based on stacks
	stack_max = 10  # Maximum stacks
	turns_active = 3  # Lasts 3 turns by default
	can_be_cured = true

## Calculate actual damage based on stack count
func get_burn_damage() -> int:
	return base_damage_per_stack * stack_count

## Process turn end - decay stacks by 1
func process_turn_end() -> void:
	if stack_count > 0:
		remove_stacks(1)
		# If stacks reach 0, the state should be removed
		if stack_count == 0:
			turns_active = 0  # Will cause state to be removed

## Load the fire overlay material
func load_overlay_material() -> ShaderMaterial:
	if overlay_material:
		return overlay_material
	
	var overlay_path = "res://assets/effects/overlays/fire_overlay.tres"
	if ResourceLoader.exists(overlay_path):
		overlay_material = ResourceLoader.load(overlay_path) as ShaderMaterial
	return overlay_material

## Add burn stacks when this state is applied to a target
func apply_stacks(amount: int) -> void:
	add_stacks(amount)

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
