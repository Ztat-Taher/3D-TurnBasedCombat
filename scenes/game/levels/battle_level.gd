extends Node3D
## Battle level wrapper for the level flow.
##
## Each level of the run is a thin scene that instances a battle scene as a
## child named 'Battle' (by default 'res://maps/battle_scenes/example_scene.tscn').
## This script translates the battle's outcome into the level signals consumed
## by the LevelManager (and synced to the GameState by level_and_state_manager.gd):
## - WIN    -> level_won    (the LevelManager advances to the next level in the
##                            SceneLister, or opens the game-won screen on the last one)
## - DEFEAT -> level_lost   (the run ends: the run-over window is shown)
## - ESCAPE -> level_changed (the same battle is replayed)
##
## To give each level its own encounter, instance a different battle scene or
## override properties (e.g. 'active_troop') on the 'Battle' instance.

signal level_won(next_level_path : String)
signal level_lost
signal level_changed(next_level_path : String)

## Optional troop override. If set, replaces the battle's active_troop before it starts.
@export var troop_override : Troops = null

func _enter_tree() -> void:
	# Runs before the battle's _ready(), so the override applies before enemies spawn.
	if troop_override == null: return
	var battle := get_node_or_null("Battle") as BattleManager
	if battle:
		battle.active_troop = troop_override

func _ready() -> void:
	var battle := $Battle as BattleManager
	if battle == null:
		push_error("BattleLevel: no BattleManager found as a child named 'Battle' in %s" % scene_file_path)
		return
	battle.battle_ended.connect(_on_battle_ended)

func _on_battle_ended(end_condition : BattleManager.BattleEndCondition) -> void:
	match end_condition:
		BattleManager.BattleEndCondition.WIN:
			# Empty path: the LevelManager picks the next level from the SceneLister.
			level_won.emit("")
		BattleManager.BattleEndCondition.DEFEAT:
			level_lost.emit()
		BattleManager.BattleEndCondition.ESCAPE:
			# Replay the same battle.
			level_changed.emit(scene_file_path)
		BattleManager.BattleEndCondition.CUTSCENE:
			pass # Reserved for future cutscene endings.