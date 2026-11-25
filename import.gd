@tool
extends EditorScenePostImport

const TARGET_NAME := "Master_Armature"

func _post_import(scene: Node) -> Object:
	var anim_players: Array[AnimationPlayer] = []
	_find_animation_players(scene, anim_players)

	for player in anim_players:
		for lib_name in player.get_animation_library_list():
			var lib: AnimationLibrary = player.get_animation_library(lib_name)
			if lib == null:
				continue

			for anim_name in lib.get_animation_list():
				var anim: Animation = lib.get_animation(anim_name)
				if anim == null:
					continue

				_remove_target_tracks(anim, TARGET_NAME)

	return scene


func _find_animation_players(node: Node, out_players: Array[AnimationPlayer]) -> void:
	if node is AnimationPlayer:
		out_players.append(node)

	for child in node.get_children():
		_find_animation_players(child, out_players)


func _remove_target_tracks(anim: Animation, target_name: String) -> void:
	# Iterate backwards so removing tracks does not shift upcoming indices.
	for track_idx in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(track_idx)
		if _path_matches_target(path, target_name):
			anim.remove_track(track_idx)


func _path_matches_target(path: NodePath, target_name: String) -> bool:
	# Check node names in the NodePath (e.g., "Master_Armature:position" or "Armature/Master_Armature:scale")
	for i in range(path.get_name_count()):
		if String(path.get_name(i)) == target_name:
			return true

	# Also check subnames (e.g., bone or property subpaths if applicable)
	for i in range(path.get_subname_count()):
		if String(path.get_subname(i)) == target_name:
			return true

	# Fallback string check for edge cases
	var path_str := String(path)
	return path_str.begins_with(target_name + ":") or ("/" + target_name + ":") in path_str
