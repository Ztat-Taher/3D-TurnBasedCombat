class_name NodeTypeDistributor
extends RefCounted

## Distributes node types (Combat, Boss, Elite, Rest, Shop, Treasure) to generated map nodes
## Uses weighted probabilities and position-based logic for balanced map generation

## Configuration for node type distribution
const ELITE_PROBABILITY: float = 0.15  # 15% of nodes
const REST_PROBABILITY: float = 0.15   # 15% of nodes
const SHOP_PROBABILITY: float = 0.08   # 8% of nodes
const TREASURE_PROBABILITY: float = 0.08  # 8% of nodes
## Combat fills the remainder (~54%)

## Minimum distance between special nodes (in path steps)
const MIN_SPECIAL_NODE_DISTANCE: int = 2

## Assigns node types to all nodes in the generated map
## Returns a dictionary mapping node_index to NodeConfig
static func assign_node_types(map_data: GeneratedMapData, all_indices: Array) -> Dictionary:
	var node_configs: Dictionary = {}
	var path_positions: Dictionary = _calculate_path_positions(map_data)
	
	# Load node configs
	var configs = _load_configs()
	
	# Process nodes in order of their path position (early to late)
	var sorted_indices = _sort_indices_by_path_position(all_indices, path_positions)
	
	var last_special_node_step: int = -MIN_SPECIAL_NODE_DISTANCE
	
	for index in sorted_indices:
		var path_step = path_positions.get(index, 0)
		var is_start = (index == 0)
		var is_end = (index == 1)
		
		var config: NodeConfig
		
		if is_start:
			# Start node: Combat or Rest
			config = configs.combat
		elif is_end:
			# End node: Always Boss
			config = configs.boss
		else:
			# Distribute other node types based on probability and position
			config = _get_random_node_type(path_step, last_special_node_step, configs)
			if config != configs.combat:
				last_special_node_step = path_step
		
		node_configs[index] = config
	
	return node_configs

## Loads all node config resources
static func _load_configs() -> Dictionary:
	var configs = {}
	configs.combat = load("res://scripts/game_state/map/node_config_combat.tres") as NodeConfig
	configs.boss = load("res://scripts/game_state/map/node_config_boss.tres") as NodeConfig
	configs.elite = load("res://scripts/game_state/map/node_config_elite.tres") as NodeConfig
	configs.rest = load("res://scripts/game_state/map/node_config_rest.tres") as NodeConfig
	configs.shop = load("res://scripts/game_state/map/node_config_shop.tres") as NodeConfig
	configs.treasure = load("res://scripts/game_state/map/node_config_treasure.tres") as NodeConfig
	configs.recruit = load("res://scripts/game_state/map/node_config_recruit.tres") as NodeConfig
	return configs

## Calculates the average path position for each node (0.0 = start, 1.0 = end)
static func _calculate_path_positions(map_data: GeneratedMapData) -> Dictionary:
	var positions: Dictionary = {}
	var path_counts: Dictionary = {}
	var path_sums: Dictionary = {}
	
	for path in map_data.paths:
		for i in range(path.size()):
			var node_index = path[i]
			var normalized_position = float(i) / float(path.size() - 1)
			
			if node_index not in path_counts:
				path_counts[node_index] = 0
				path_sums[node_index] = 0.0
			
			path_counts[node_index] += 1
			path_sums[node_index] += normalized_position
	
	# Calculate average position for each node
	for node_index in path_counts:
		positions[node_index] = path_sums[node_index] / path_counts[node_index]
	
	return positions

## Sorts node indices by their average path position (early to late)
static func _sort_indices_by_path_position(indices: Array, path_positions: Dictionary) -> Array:
	var sorted = indices.duplicate()
	sorted.sort_custom(func(a, b): return path_positions.get(a, 0.0) < path_positions.get(b, 0.0))
	return sorted

## Gets a random node type based on probability and position
static func _get_random_node_type(path_position: float, last_special_step: int, configs: Dictionary) -> NodeConfig:
	var distance_from_last_special = path_position - last_special_step
	
	# If too close to last special node, default to combat
	if distance_from_last_special < MIN_SPECIAL_NODE_DISTANCE:
		return configs.combat
	
	# Bias elites toward later positions (50%+ through the map)
	var elite_chance = ELITE_PROBABILITY
	if path_position > 0.5:
		elite_chance *= 1.5  # 50% more likely in later half
	
	var roll = randf()
	
	# Try elite first (highest value)
	if roll < elite_chance:
		return configs.elite
	
	roll -= elite_chance
	
	# Try rest
	if roll < REST_PROBABILITY:
		return configs.rest
	
	roll -= REST_PROBABILITY
	
	# Try shop
	if roll < SHOP_PROBABILITY:
		return configs.shop
	
	roll -= SHOP_PROBABILITY
	
	# Try treasure
	if roll < TREASURE_PROBABILITY:
		return configs.treasure
	
	# Default to combat
	return configs.combat
