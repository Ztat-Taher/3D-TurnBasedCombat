class_name RunMapNode
extends Resource
## A single node on the run map (Slay the Spire style path selection).

@export var id : String = ""
@export var display_name : String = "Combat"
@export_enum("Combat", "Elite", "Boss", "Rest", "Shop", "Treasure") var node_type : String = "Combat"
## Path to the level scene this node opens (e.g. a battle level wrapper).
@export_file("*.tscn") var level_path : String = ""
## IDs of the nodes the player can travel to after completing this one.
## An empty list marks this node as the end of the run.
@export var next_node_ids : Array[String] = []
## Normalized position on the map (0..1, with y growing downward).
@export var map_position : Vector2 = Vector2(0.5, 0.5)
