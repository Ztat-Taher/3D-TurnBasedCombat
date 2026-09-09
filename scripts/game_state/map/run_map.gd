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

## The built-in default map: three floors of combat with branching paths,
## ending at the summit gate. Author a RunMap resource in the inspector and
## assign it (to the map menu or the level manager) to replace this later.
static func create_default() -> RunMap:
	var map := RunMap.new()
	map.starting_node_ids.assign(["crossroads", "ambush"])

	var crossroads := RunMapNode.new()
	crossroads.id = "crossroads"
	crossroads.display_name = "Combat"
	crossroads.node_type = "Combat"
	crossroads.level_path = "res://scenes/game/levels/battle_level_1.tscn"
	crossroads.next_node_ids.assign(["hill_pass", "ruined_outpost"])
	crossroads.map_position = Vector2(0.25, 0.15)

	var ambush := RunMapNode.new()
	ambush.id = "ambush"
	ambush.display_name = "Combat"
	ambush.node_type = "Combat"
	ambush.level_path = "res://scenes/game/levels/battle_level_2.tscn"
	ambush.next_node_ids.assign(["ruined_outpost"])
	ambush.map_position = Vector2(0.75, 0.15)

	var hill_pass := RunMapNode.new()
	hill_pass.id = "hill_pass"
	hill_pass.display_name = "Combat"
	hill_pass.node_type = "Combat"
	hill_pass.level_path = "res://scenes/game/levels/battle_level_3.tscn"
	hill_pass.next_node_ids.assign(["summit_gate"])
	hill_pass.map_position = Vector2(0.3, 0.5)

	var ruined_outpost := RunMapNode.new()
	ruined_outpost.id = "ruined_outpost"
	ruined_outpost.display_name = "Combat"
	ruined_outpost.node_type = "Combat"
	ruined_outpost.level_path = "res://scenes/game/levels/battle_level_2.tscn"
	ruined_outpost.next_node_ids.assign(["summit_gate"])
	ruined_outpost.map_position = Vector2(0.7, 0.5)

	var summit_gate := RunMapNode.new()
	summit_gate.id = "summit_gate"
	summit_gate.display_name = "Boss"
	summit_gate.node_type = "Boss"
	summit_gate.level_path = "res://scenes/game/levels/battle_level_3.tscn"
	summit_gate.next_node_ids.assign([])
	summit_gate.map_position = Vector2(0.5, 0.85)

	map.nodes = [crossroads, ambush, hill_pass, ruined_outpost, summit_gate]
	return map
