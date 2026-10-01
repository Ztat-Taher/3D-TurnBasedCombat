extends MeshInstance3D
class_name WeaponTrail

## How long a trail segment lasts before fading out completely (seconds)
@export var trail_lifespan: float = 0.3
## Minimum distance between points before a new quad is drawn
@export var resolution: float = 0.05
## How many interpolated segments to create between sampled points for smoothness
@export var subdivisions: int = 4

var default_material: Material
var override_material: Material

var _top_node: Node3D
var _bottom_node: Node3D
var _immediate_mesh: ImmediateMesh

# Each history entry is: {"top": Vector3, "bottom": Vector3, "time": float}
var _history: Array[Dictionary] = []
var _is_emitting: bool = false
var _last_emitted_top: Vector3 = Vector3.ZERO
var _last_emitted_bottom: Vector3 = Vector3.ZERO

func _ready():
	_immediate_mesh = ImmediateMesh.new()
	self.mesh = _immediate_mesh
	
	# Transition to world-space rendering to keep trail stationary in air
	top_level = true
	global_position = Vector3.ZERO
	global_rotation = Vector3.ZERO
	
	default_material = material_override
	
	# Auto-detect blade markers
	_detect_markers()
		
	# Prime the shader to prevent first-swing lag spike
	_prime_shader()
		
	set_process(true)

func _prime_shader():
	# Draw a single invisible triangle to force GPU shader compilation
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_immediate_mesh.surface_set_uv(Vector2.ZERO)
	_immediate_mesh.surface_add_vertex(Vector3.ZERO)
	_immediate_mesh.surface_add_vertex(Vector3.ZERO)
	_immediate_mesh.surface_add_vertex(Vector3.ZERO)
	_immediate_mesh.surface_end()
	_immediate_mesh.clear_surfaces()

func _detect_markers():
	# Try to find markers as direct children first
	_top_node = find_child("trail_top", true, false)
	_bottom_node = find_child("trail_bottom", true, false)
	
	# If not found, search in parent hierarchy
	if not _top_node or not _bottom_node:
		var parent = get_parent()
		while parent:
			if not _top_node:
				_top_node = parent.find_child("trail_top", true, false)
			if not _bottom_node:
				_bottom_node = parent.find_child("trail_bottom", true, false)
			if _top_node and _bottom_node:
				break
			parent = parent.get_parent()
	
	# Log warnings if markers are still not found
	if not _top_node:
		push_warning("WeaponTrail: Could not find 'trail_top' marker node. Trail will not render.")
	if not _bottom_node:
		push_warning("WeaponTrail: Could not find 'trail_bottom' marker node. Trail will not render.")

## Animation callback: Start emitting trail
## Call this via AnimationPlayer method track at the start of attack animation
func _on_trail_start():
	if not _top_node or not _bottom_node:
		return
	
	# Clear old trail history to prevent jumps
	_history.clear()
	_is_emitting = true
	# Record initial point immediately
	_record_point()

## Animation callback: Stop emitting trail
## Call this via AnimationPlayer method track at the end of attack animation
func _on_trail_end():
	_is_emitting = false
	
## Dynamically swap the trail material (e.g. for Fire Weapon Buff)
func set_effect_material(mat: Material):
	override_material = mat
	material_override = override_material if override_material else default_material
	
func clear_effect_material():
	override_material = null
	material_override = default_material

func _process(_delta: float):
	if not _top_node or not _bottom_node: return
	
	# Record points while emitting
	if _is_emitting:
		var curr_top = _top_node.global_position
		# Only drop a point if we've moved enough distance
		if _history.size() == 0 or curr_top.distance_to(_last_emitted_top) > resolution:
			_record_point()
			
	# Update the lifespan of all history points
	var current_time = Time.get_ticks_msec() / 1000.0
	for i in range(_history.size() - 1, -1, -1):
		if current_time - _history[i].time > trail_lifespan:
			_history.remove_at(i)
			
	_draw_mesh()

func _record_point():
	var top = _top_node.global_position
	var bottom = _bottom_node.global_position
	
	# Since we set top_level = true, we record pure global coordinates.
	_history.append({
		"top": top,
		"bottom": bottom,
		"time": Time.get_ticks_msec() / 1000.0
	})
	
	_last_emitted_top = top
	_last_emitted_bottom = bottom

func _draw_mesh():
	_immediate_mesh.clear_surfaces()
	
	if _history.size() < 2:
		return
		
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	var history_count = _history.size()
	
	# Loop through pairs of points and subdivide them
	for i in range(history_count - 1):
		var p0 = _history[max(0, i - 1)]
		var p1 = _history[i]
		var p2 = _history[i + 1]
		var p3 = _history[min(history_count - 1, i + 2)]
		
		# Generate interpolated steps
		for s in range(subdivisions):
			# If it's the last point of the entire trail, we draw the final edge
			if i == history_count - 2 and s == subdivisions - 1:
				_add_interpolated_quad(p0, p1, p2, p3, 1.0, i, history_count)
				break
				
			var t_segment = float(s) / float(subdivisions)
			_add_interpolated_quad(p0, p1, p2, p3, t_segment, i, history_count)
		
	_immediate_mesh.surface_end()

func _add_interpolated_quad(p0, p1, p2, p3, t_segment: float, index: int, total: int):
	# Interpolate top and bottom points using Catmull-Rom
	var top = _catmull_rom(p0.top, p1.top, p2.top, p3.top, t_segment)
	var bottom = _catmull_rom(p0.bottom, p1.bottom, p2.bottom, p3.bottom, t_segment)
	
	# Calculate global UV.x (0 to 1 across entire trail)
	var t_global = (float(index) + t_segment) / float(total - 1)
	
	_immediate_mesh.surface_set_uv(Vector2(t_global, 0.0))
	_immediate_mesh.surface_add_vertex(bottom)
	_immediate_mesh.surface_set_uv(Vector2(t_global, 1.0))
	_immediate_mesh.surface_add_vertex(top)

func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 = t * t
	var t3 = t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)
