class_name RunMapNode
extends Resource
## A single node on the run map (Slay the Spire style path selection).

@export var id : String = ""
@export var display_name : String = "Combat"
@export var node_config : NodeConfig
## Path to the level scene this node opens (e.g. a battle level wrapper).
@export_file("*.tscn") var level_path : String = ""
## IDs of the nodes the player can travel to after completing this one.
## An empty list marks this node as the end of the run.
@export var next_node_ids : Array[String] = []
## Normalized position on the map (0..1, with y growing downward).
@export var map_position : Vector2 = Vector2(0.5, 0.5)


## Plain-data form for saving (JSON-safe). The NodeConfig is stored by its
## resource path, so it must be a saved .tres (all generated maps use those).
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"node_config": node_config.resource_path if node_config else "",
		"level_path": level_path,
		"next_node_ids": Array(next_node_ids),
		"map_position": [map_position.x, map_position.y],
	}


## Rebuilds a node saved with [method to_dict]; null if [param data] isn't one.
static func from_dict(data) -> RunMapNode:
	if not data is Dictionary or not data.has("id"):
		return null
	var node := RunMapNode.new()
	node.id = str(data.id)
	node.display_name = str(data.get("display_name", node.display_name))
	var config_path := str(data.get("node_config", ""))
	if not config_path.is_empty() and ResourceLoader.exists(config_path):
		node.node_config = load(config_path) as NodeConfig
	node.level_path = str(data.get("level_path", ""))
	node.next_node_ids.assign(data.get("next_node_ids", []))
	var pos = data.get("map_position", [0.5, 0.5])
	if pos is Array and pos.size() == 2:
		node.map_position = Vector2(float(pos[0]), float(pos[1]))
	return node
