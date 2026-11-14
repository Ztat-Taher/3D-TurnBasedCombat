extends Node

## Simple test script to verify procedural map generation
## Run this in Godot editor to test the map generator

func _ready() -> void:
	print("Testing procedural map generation...")
	
	# Test 1: Generate a procedural map
	var map = RunMap.create_procedural(30, 75, 12)
	
	print("Map generated successfully!")
	print("Number of nodes: ", map.nodes.size())
	print("Starting nodes: ", map.starting_node_ids)
	
	# Test 2: Verify node properties
	var node_count = 0
	var boss_count = 0
	var elite_count = 0
	var combat_count = 0
	var rest_count = 0
	
	for node in map.nodes:
		var map_node = node as RunMapNode
		if map_node:
			node_count += 1
			if map_node.node_config:
				match map_node.node_config.node_type:
					"Boss":
						boss_count += 1
					"Elite":
						elite_count += 1
					"Combat":
						combat_count += 1
					"Rest":
						rest_count += 1
	
	print("\nNode type distribution:")
	print("Total nodes: ", node_count)
	print("Boss nodes: ", boss_count)
	print("Elite nodes: ", elite_count)
	print("Combat nodes: ", combat_count)
	print("Rest nodes: ", rest_count)
	
	# Test 3: Verify connectivity
	var connected_count = 0
	for node in map.nodes:
		var map_node = node as RunMapNode
		if map_node and not map_node.next_node_ids.is_empty():
			connected_count += 1
	
	print("\nConnectivity:")
	print("Nodes with connections: ", connected_count)
	print("Nodes without connections (should be boss): ", node_count - connected_count)
	
	print("\nTest complete!")
