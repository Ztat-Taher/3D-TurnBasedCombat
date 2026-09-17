class_name RunMap
extends Resource
## The map of nodes for a run (Slay the Spire style path selection).
##
## The player starts at any of the 'starting_node_ids' and, after completing
## a node, may travel to any of its 'next_node_ids'. Completing a node with
## no next nodes finishes the run.

## Nodes where a new run can begin.
@export var starting_node_ids : Array[String] = []
## All nodes on the map. Untyped so hand-authored .tres files stay simple;
## entries are expected to be RunMapNode resources.
@export var nodes : Array = []

func get_node_by_id(node_id : String) -> RunMapNode:
	if node_id.is_empty():
		return null
	for node in nodes:
		var map_node := node as RunMapNode
		if map_node and map_node.id == node_id:
			return map_node
	return null

## The nodes the player can travel to next, given the completed node ids.
## With nothing completed yet, the starting nodes are available.
func get_available_node_ids(completed_nodes : Array) -> Array[String]:
	var available : Array[String] = []
	if completed_nodes.is_empty():
		available.assign(starting_node_ids)
		return available
	for node_id in completed_nodes:
		var node := get_node_by_id(node_id)
		if node == null:
			continue
		for next_id in node.next_node_ids:
			if next_id not in available and next_id not in completed_nodes:
				available.append(next_id)
	return available

## The built-in default map: Complex, intertwining paths that all lead to boss
## Starting from bottom center, with varied branching, no dead ends
static func create_default() -> RunMap:
	var map := RunMap.new()
	
	# Load NodeConfig resources
	var combat_config = load("res://scripts/game_state/map/node_config_combat.tres") as NodeConfig
	var boss_config = load("res://scripts/game_state/map/node_config_boss.tres") as NodeConfig

	# Starting node at bottom center
	var start_node := RunMapNode.new()
	start_node.id = "start"
	start_node.display_name = "Start"
	start_node.node_config = combat_config
	start_node.level_path = ""
	start_node.next_node_ids.assign(["river_path", "ancient_bridge", "foggy_road"])
	start_node.map_position = Vector2(0.5, 0.92)
	
	# Bottom layer - diverse branching
	var river_path := RunMapNode.new()
	river_path.id = "river_path"
	river_path.display_name = "Combat"
	river_path.node_config = combat_config
	river_path.level_path = "res://scenes/game/levels/battle_level_1.tscn"
	river_path.next_node_ids.assign(["marsh_lands", "twisted_forest"])
	river_path.map_position = Vector2(0.28, 0.75)
	
	var ancient_bridge := RunMapNode.new()
	ancient_bridge.id = "ancient_bridge"
	ancient_bridge.display_name = "Combat"
	ancient_bridge.node_config = combat_config
	ancient_bridge.level_path = "res://scenes/game/levels/battle_level_1.tscn"
	ancient_bridge.next_node_ids.assign(["twisted_forest", "stone_gate"])
	ancient_bridge.map_position = Vector2(0.52, 0.71)
	
	var foggy_road := RunMapNode.new()
	foggy_road.id = "foggy_road"
	foggy_road.display_name = "Combat"
	foggy_road.node_config = combat_config
	foggy_road.level_path = "res://scenes/game/levels/battle_level_1.tscn"
	foggy_road.next_node_ids.assign(["stone_gate", "mountain_pass"])
	foggy_road.map_position = Vector2(0.78, 0.73)
	
	# Middle layer - intertwining paths
	var marsh_lands := RunMapNode.new()
	marsh_lands.id = "marsh_lands"
	marsh_lands.display_name = "Combat"
	marsh_lands.node_config = combat_config
	marsh_lands.level_path = "res://scenes/game/levels/battle_level_2.tscn"
	marsh_lands.next_node_ids.assign(["crystal_cave", "sunken_ruins"])
	marsh_lands.map_position = Vector2(0.18, 0.54)
	
	var twisted_forest := RunMapNode.new()
	twisted_forest.id = "twisted_forest"
	twisted_forest.display_name = "Combat"
	twisted_forest.node_config = combat_config
	twisted_forest.level_path = "res://scenes/game/levels/battle_level_2.tscn"
	twisted_forest.next_node_ids.assign(["sunken_ruins", "windy_cliff"])
	twisted_forest.map_position = Vector2(0.42, 0.48)
	
	var stone_gate := RunMapNode.new()
	stone_gate.id = "stone_gate"
	stone_gate.display_name = "Combat"
	stone_gate.node_config = combat_config
	stone_gate.level_path = "res://scenes/game/levels/battle_level_2.tscn"
	stone_gate.next_node_ids.assign(["windy_cliff", "summit_path"])
	stone_gate.map_position = Vector2(0.62, 0.52)
	
	var mountain_pass := RunMapNode.new()
	mountain_pass.id = "mountain_pass"
	mountain_pass.display_name = "Combat"
	mountain_pass.node_config = combat_config
	mountain_pass.level_path = "res://scenes/game/levels/battle_level_2.tscn"
	mountain_pass.next_node_ids.assign(["summit_path", "hidden_valley"])
	mountain_pass.map_position = Vector2(0.85, 0.55)
	
	# Upper layer - all paths converge to boss
	var crystal_cave := RunMapNode.new()
	crystal_cave.id = "crystal_cave"
	crystal_cave.display_name = "Combat"
	crystal_cave.node_config = combat_config
	crystal_cave.level_path = "res://scenes/game/levels/battle_level_3.tscn"
	crystal_cave.next_node_ids.assign(["final_gate"])  # No dead end
	crystal_cave.map_position = Vector2(0.25, 0.35)
	
	var sunken_ruins := RunMapNode.new()
	sunken_ruins.id = "sunken_ruins"
	sunken_ruins.display_name = "Combat"
	sunken_ruins.node_config = combat_config
	sunken_ruins.level_path = "res://scenes/game/levels/battle_level_3.tscn"
	sunken_ruins.next_node_ids.assign(["final_gate", "summit_alt"])  # Converges to boss
	sunken_ruins.map_position = Vector2(0.38, 0.32)
	
	var windy_cliff := RunMapNode.new()
	windy_cliff.id = "windy_cliff"
	windy_cliff.display_name = "Combat"
	windy_cliff.node_config = combat_config
	windy_cliff.level_path = "res://scenes/game/levels/battle_level_3.tscn"
	windy_cliff.next_node_ids.assign(["summit_alt", "final_gate"])  # Converges to boss
	windy_cliff.map_position = Vector2(0.55, 0.28)
	
	var summit_path := RunMapNode.new()
	summit_path.id = "summit_path"
	summit_path.display_name = "Combat"
	summit_path.node_config = combat_config
	summit_path.level_path = "res://scenes/game/levels/battle_level_3.tscn"
	summit_path.next_node_ids.assign(["final_gate", "hidden_valley"])  # Converges to boss
	summit_path.map_position = Vector2(0.72, 0.36)
	
	var hidden_valley := RunMapNode.new()
	hidden_valley.id = "hidden_valley"
	hidden_valley.display_name = "Combat"
	hidden_valley.node_config = combat_config
	hidden_valley.level_path = "res://scenes/game/levels/battle_level_3.tscn"
	hidden_valley.next_node_ids.assign(["final_gate"])  # Converges to boss
	hidden_valley.map_position = Vector2(0.88, 0.32)
	
	# Additional convergence node
	var summit_alt := RunMapNode.new()
	summit_alt.id = "summit_alt"
	summit_alt.display_name = "Combat"
	summit_alt.node_config = combat_config
	summit_alt.level_path = "res://scenes/game/levels/battle_level_3.tscn"
	summit_alt.next_node_ids.assign(["final_gate"])  # Converges to boss
	summit_alt.map_position = Vector2(0.48, 0.15)
	
	# Final convergence to boss
	var final_gate := RunMapNode.new()
	final_gate.id = "final_gate"
	final_gate.display_name = "Combat"
	final_gate.node_config = combat_config
	final_gate.level_path = "res://scenes/game/levels/battle_level_3.tscn"
	final_gate.next_node_ids.assign(["boss"])
	final_gate.map_position = Vector2(0.65, 0.18)
	
	# Boss at top
	var boss := RunMapNode.new()
	boss.id = "boss"
	boss.display_name = "Boss"
	boss.node_config = boss_config
	boss.level_path = "res://scenes/game/levels/battle_level_3.tscn"
	boss.next_node_ids.assign([])
	boss.map_position = Vector2(0.58, 0.08)
	
	# Set starting node and add all nodes
	map.starting_node_ids.assign(["start"])
	map.nodes = [start_node, river_path, ancient_bridge, foggy_road, marsh_lands, twisted_forest, stone_gate, mountain_pass, crystal_cave, sunken_ruins, windy_cliff, summit_path, hidden_valley, summit_alt, final_gate, boss]
	return map
