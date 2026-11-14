class_name GeneratedMapData
extends RefCounted

## Container for procedurally generated map data
## Holds the paths and node positions from the procedural generator

## Array of paths, where each path is an array of node indices
var paths: Array = []
## Dictionary mapping node index to its grid position
var nodes: Dictionary = {}

## Sets the paths and nodes from the generator
func set_paths(paths_array: Array, points_array: Array) -> void:
	paths = paths_array

	for path in paths:
		for id in path:
			nodes[id] = points_array[id]

## Gets all unique node indices from all paths
func get_all_node_indices() -> Array:
	var indices: Array = []
	for path in paths:
		for id in path:
			if id not in indices:
				indices.append(id)
	return indices

## Gets the position of a node by its index
func get_node_position(index: int) -> Vector2:
	if index in nodes:
		return nodes[index]
	return Vector2.ZERO
