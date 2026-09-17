extends Control
class_name MapPathDrawer

## Draws the paths between map nodes with dashed lines
## Differentiates between traveled and untraveled paths

var run_map: RunMap
var completed_nodes: Array = []

## Path styling
@export var line_color: Color = Color(0.5, 0.5, 0.5, 0.5)  # Gray for untraveled
@export var line_color_traveled: Color = Color(1.0, 1.0, 1.0, 0.9)  # White for traveled
@export var line_width: float = 8.0
@export var dash_length: float = 20.0
@export var gap_length: float = 15.0
@export var animated: bool = true
@export var animation_speed: float = 2.0

var animation_offset: float = 0.0

func _ready() -> void:
	# Ignore mouse input so clicks pass through to nodes
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if animated:
		animation_offset += animation_speed * delta
		if animation_offset > (dash_length + gap_length):
			animation_offset -= (dash_length + gap_length)
		queue_redraw()

func set_run_map(map: RunMap) -> void:
	run_map = map
	queue_redraw()

func set_completed_nodes(nodes: Array) -> void:
	completed_nodes = nodes
	queue_redraw()

func _draw() -> void:
	if not run_map:
		return
	
	for node in run_map.nodes:
		var map_node := node as RunMapNode
		if map_node == null:
			continue
		
		# Draw paths from this node to its next nodes
		var traveled: bool = map_node.id in completed_nodes
		
		for next_id in map_node.next_node_ids:
			var next_node := run_map.get_node_by_id(next_id)
			if next_node == null:
				continue
			
			var from_pos: Vector2 = _get_node_pixel_position(map_node)
			var to_pos: Vector2 = _get_node_pixel_position(next_node)
			
			var color: Color = line_color_traveled if traveled else line_color
			_draw_dashed_line(from_pos, to_pos, color, traveled)

func _get_node_pixel_position(map_node: RunMapNode) -> Vector2:
	# This should match the positioning logic in map_menu_3d.gd exactly
	var map_margin := 64.0
	# Use the parent's size if our size is not set properly
	var parent_size = size
	if parent_size.x <= 1.0 or parent_size.y <= 1.0:
		var parent_control = get_parent() as Control
		if parent_control:
			parent_size = parent_control.size
	
	# Fallback to a reasonable default size
	if parent_size.x <= 1.0 or parent_size.y <= 1.0:
		parent_size = Vector2(1920, 1080)
	
	var area_size: Vector2 = (parent_size - Vector2(map_margin, map_margin) * 2.0).max(Vector2.ZERO)
	# Return the CENTER of the node (add half node size offset of 32,32)
	return Vector2(map_margin, map_margin) + Vector2(
		map_node.map_position.x * area_size.x, 
		map_node.map_position.y * area_size.y
	)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, traveled: bool) -> void:
	var direction: Vector2 = to - from
	var distance: float = direction.length()
	var normal: Vector2 = direction.normalized()
	
	var total_dash_length: float = dash_length + gap_length
	var current_distance: float = 0.0
	
	# Add animation offset for traveled paths
	var start_offset: float = animation_offset if traveled and animated else 0.0
	current_distance = start_offset
	
	while current_distance < distance:
		var dash_start: float = current_distance
		var dash_end: float = min(current_distance + dash_length, distance)
		
		if dash_start < distance:
			var start_pos: Vector2 = from + normal * dash_start
			var end_pos: Vector2 = from + normal * dash_end
			draw_line(start_pos, end_pos, color, line_width, true)
		
		current_distance += total_dash_length

func draw_connection_line(from: Vector2, to: Vector2, color: Color, traveled: bool) -> void:
	# Fallback to solid line if dashed drawing fails
	_draw_dashed_line(from, to, color, traveled)

func get_line_color(traveled: bool) -> Color:
	return line_color_traveled if traveled else line_color
