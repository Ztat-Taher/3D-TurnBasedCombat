class_name ProceduralMapGenerator
extends Node

## Procedural map generator inspired by Slay the Spire
## Uses distance-based connections and A* pathfinding to create branching paths
## Based on: https://github.com/VladoCC/Map-Generator-Godot-Tutorial
## Adapted for Godot 4 compatibility

## Generates a procedural map with the given parameters
## plane_size: Size of the grid (e.g., 30 for a 30x30 grid)
## node_count: Number of nodes to generate (excluding start/end)
## path_count: Number of unique paths from start to end
## min_node_distance: Minimum distance between any two nodes (default 3.0)
## Returns: GeneratedMapData containing paths and node positions
func generate(plane_size: int, node_count: int, path_count: int, min_node_distance: float = 3.0) -> GeneratedMapData:
	# Randomize for different maps each time
	randomize()
	
	# Step 1: Generate points on a grid randomly
	var points = []
	
	# Start point at bottom center
	points.append(Vector2(float(plane_size) / 2.0, float(plane_size)))
	# End point at top center
	points.append(Vector2(float(plane_size) / 2.0, 0.0))
	
	var center = Vector2(float(plane_size) / 2.0, float(plane_size) / 2.0)
	for i in range(node_count):
		var attempts = 0
		var max_attempts = 100  # Prevent infinite loop
		
		while attempts < max_attempts:
			var point = Vector2(randi() % plane_size, randi() % plane_size)
			
			var dist_from_center = (point - center).length_squared()
			# Only accept points inside of a circle (increased radius for better spread)
			var in_circle = dist_from_center <= float(plane_size * plane_size) / 3.6
			
			# Check minimum distance from all existing points
			var too_close = false
			for existing_point in points:
				if point.distance_to(existing_point) < min_node_distance:
					too_close = true
					break
			
			if not points.has(point) and in_circle and not too_close:
				points.append(point)
				break
			
			attempts += 1
	
	# Step 2: Connect points using distance-based approach (Godot 4 compatible)
	# Connect each point to its nearest neighbors within a threshold
	var connection_distance = plane_size / 2.5  # Connect to points within 2/5 of grid size (increased for better spread)
	
	var astar = AStar2D.new()
	for i in range(points.size()):
		astar.add_point(i, points[i])
	
	# Connect points based on distance
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			var distance = points[i].distance_to(points[j])
			if distance <= connection_distance:
				astar.connect_points(i, j, distance)  # Use distance as weight
	
	# Ensure start and end are connected by finding shortest paths and adding missing connections
	if not astar.are_points_connected(0, 1):
		# Add additional connections to ensure start and end can reach each other
		for i in range(2, points.size()):
			var dist_to_start = points[0].distance_to(points[i])
			var dist_to_end = points[1].distance_to(points[i])
			if dist_to_start <= connection_distance * 1.5:
				astar.connect_points(0, i, dist_to_start)
			if dist_to_end <= connection_distance * 1.5:
				astar.connect_points(1, i, dist_to_end)
	
	var paths = []
	
	# Step 3: Generate multiple unique paths by removing nodes
	for i in range(path_count):
		var id_path = astar.get_id_path(0, 1)
		if id_path.size() == 0:
			break
		
		paths.append(id_path)
		
		# Remove some nodes from this path to force the next path to be different
		for j in range(randi() % 2 + 1):
			# Index between 1 and id_path.size() - 2 (exclusive of start and end)
			var index = randi() % (id_path.size() - 2) + 1
			
			var id = id_path[index]
			astar.set_point_disabled(id, true)
	
	# Create and return the map data
	var data = GeneratedMapData.new()
	data.set_paths(paths, points.duplicate())
	return data
