class_name MapConverter
extends RefCounted

## Converts GeneratedMapData to RunMap resource format
## Handles position normalization and node type assignment

## Converts generated map data to a RunMap resource
## map_data: The GeneratedMapData from the procedural generator
## plane_size: The grid size used for generation (for normalization)
## Returns: A RunMap resource ready for use in the game
static func convert_to_run_map(map_data: GeneratedMapData, plane_size: int) -> RunMap:
	var run_map = RunMap.new()
	
	# Get all unique node indices
	var all_indices = map_data.get_all_node_indices()
	
	# Assign node types using the distributor
	var node_configs = NodeTypeDistributor.assign_node_types(map_data, all_indices)
	
	# Build adjacency dictionary from paths
	var adjacency = _build_adjacency_from_paths(map_data.paths)
	
	# Create RunMapNode for each index
	var run_nodes: Array[RunMapNode] = []
	var start_indices: Array[String] = []
	
	for index in all_indices:
		var map_node = _create_run_map_node(
			index,
			map_data.get_node_position(index),
			plane_size,
			node_configs.get(index),
			adjacency.get(index, [])
		)
		
		run_nodes.append(map_node)
		
		# Start node is index 0
		if index == 0:
			start_indices.append(map_node.id)
	
	# Set the map properties
	run_map.nodes = run_nodes
	run_map.starting_node_ids = start_indices
	
	return run_map

## Builds an adjacency dictionary from the paths
## Returns: Dictionary mapping node_index to Array of next node indices
static func _build_adjacency_from_paths(paths: Array) -> Dictionary:
	var adjacency: Dictionary = {}
	
	for path in paths:
		for i in range(path.size() - 1):
			var current = path[i]
			var next_node = path[i + 1]
			
			if current not in adjacency:
				adjacency[current] = []
			
			if next_node not in adjacency[current]:
				adjacency[current].append(next_node)
	
	return adjacency

## Creates a single RunMapNode from the generated data
static func _create_run_map_node(
	index: int,
	grid_position: Vector2,
	plane_size: int,
	node_config: NodeConfig,
	next_indices: Array
) -> RunMapNode:
	var map_node = RunMapNode.new()
	
	# Set ID
	map_node.id = "node_%d" % index
	
	# Set display name based on node type
	if node_config:
		map_node.display_name = node_config.node_type
	else:
		map_node.display_name = "Combat"
	
	# Set node config
	map_node.node_config = node_config
	
	# Set level path based on node type
	map_node.level_path = _get_level_path_for_node_type(node_config)
	
	# Set next node IDs (convert to typed Array[String])
	var next_ids: Array[String] = []
	for next_idx in next_indices:
		next_ids.append("node_%d" % next_idx)
	map_node.next_node_ids = next_ids
	
	# Normalize position to 0-1 range
	# Original: 0 is left/top, plane_size is right/bottom
	# Normalized: 0 is left/top, 1 is right/bottom
	# Map flows from bottom (0.9) to top (0.1) naturally
	var normalized_x = float(grid_position.x) / float(plane_size)
	var normalized_y = float(grid_position.y) / float(plane_size)
	
	map_node.map_position = Vector2(normalized_x, normalized_y)
	
	return map_node

## Returns the appropriate level path for a given node type
static func _get_level_path_for_node_type(node_config: NodeConfig) -> String:
	if node_config == null:
		return "res://scenes/game/levels/battle_level_1.tscn"  # Default to combat
	
	var node_type = node_config.node_type
	
	match node_type:
		"Boss":
			return "res://scenes/game/levels/battle_level_3.tscn"
		"Elite":
			return ""  # Elite nodes disabled for now
		"Combat":
			return "res://scenes/game/levels/battle_level_1.tscn"
		"Rest":
			return "res://scenes/menus/map_menu/rest_screen.tscn"
		"Recruit":
			return "res://scenes/menus/map_menu/recruit_screen.tscn"
		"Shop":
			return ""  # TODO: Add shop screen when available
		"Treasure":
			return ""  # TODO: Add treasure screen when available
		_:
			return "res://scenes/game/levels/battle_level_1.tscn"  # Default to combat
