class_name HitEffectConfig
extends Resource
## Configuration for a single billboard spritesheet hit effect
## Supports smart spacing when multiple effects are spawned together

@export var spritesheet_texture: Texture2D = null
@export var hframes: int = 1
@export var vframes: int = 1
@export var fps: float = 12.0
@export var scale: Vector3 = Vector3.ONE
@export var color: Color = Color.WHITE
@export var duration: float = 0.5
@export var spacing_offset: Vector2 = Vector2.ZERO

## Spacing radius for circle arrangement (in world units)
@export var spacing_radius: float = 0.3

## Spawn this effect on a target battler
## target: The battler being hit
## center_position: The center position for effects (usually AABB center)
## spacing_index: Index of this effect in the sequence (0-based)
## total_effects: Total number of effects being spawned
## Returns the created HitEffect node
func spawn(target: Battler, center_position: Vector3, spacing_index: int, total_effects: int) -> HitEffect:
	if not spritesheet_texture:
		push_error("HitEffectConfig: No spritesheet texture set")
		return null
	
	# Calculate smart spacing position
	var spawn_position = calculate_spacing_position(center_position, spacing_index, total_effects, spacing_radius)
	
	# Offset Z to appear in front of the target (closer to camera)
	spawn_position.z += 0.5
	
	# Instantiate the template scene
	var hit_effect_scene = load("res://scenes/effects/hit_effect.tscn")
	var hit_effect = hit_effect_scene.instantiate() as HitEffect
	
	# Add to target as child first
	target.add_child(hit_effect)
	
	# Now set position after it's in the tree
	hit_effect.position = spawn_position
	
	# Configure the effect with this config
	hit_effect.configure(self)
	
	return hit_effect

## Calculate position for this effect based on spacing algorithm
func calculate_spacing_position(center: Vector3, index: int, total: int, radius: float) -> Vector3:
	# Apply manual offset if set
	if spacing_offset != Vector2.ZERO:
		return center + Vector3(spacing_offset.x, spacing_offset.y, 0)
	
	# Single effect - use center
	if total <= 1:
		return center
	
	# Circle arrangement for 2-6 effects
	if total <= 6:
		var angle = (2.0 * PI * float(index)) / float(total)
		var offset_x = radius * cos(angle)
		var offset_y = radius * sin(angle)
		return center + Vector3(offset_x, offset_y, 0)
	
	# Grid arrangement for 7+ effects
	return calculate_grid_position(center, index, total)

## Calculate grid position for larger effect counts
func calculate_grid_position(center: Vector3, index: int, total: int) -> Vector3:
	var grid_size = ceil(sqrt(float(total)))
	var cell_spacing = 0.2
	
	# Calculate grid row and column
	var row = index / int(grid_size)
	var col = index % int(grid_size)
	
	# Center the grid around the spawn point
	var grid_width = (grid_size - 1) * cell_spacing
	var grid_height = (grid_size - 1) * cell_spacing
	
	var offset_x = (col * cell_spacing) - (grid_width / 2.0)
	var offset_y = (row * cell_spacing) - (grid_height / 2.0)
	
	return center + Vector3(offset_x, offset_y, 0)

## Static helper to calculate all spacing positions at once
static func calculate_spacing_positions(center: Vector3, count: int, radius: float = 0.3) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	
	for i in range(count):
		if count <= 1:
			positions.append(center)
		elif count <= 6:
			var angle = (2.0 * PI * float(i)) / float(count)
			var offset_x = radius * cos(angle)
			var offset_y = radius * sin(angle)
			positions.append(center + Vector3(offset_x, offset_y, 0))
		else:
			# Grid arrangement
			var grid_size = ceil(sqrt(float(count)))
			var cell_spacing = 0.2
			var row = i / int(grid_size)
			var col = i % int(grid_size)
			var grid_width = (grid_size - 1) * cell_spacing
			var grid_height = (grid_size - 1) * cell_spacing
			var offset_x = (col * cell_spacing) - (grid_width / 2.0)
			var offset_y = (row * cell_spacing) - (grid_height / 2.0)
			positions.append(center + Vector3(offset_x, offset_y, 0))
	
	return positions
