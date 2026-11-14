class_name RecruitScreen
extends Control
## Recruit UI, opened as its own scene from the run map (the same way a Combat
## node opens its battle scene): the map emits level_changed with this scene's
## path, the LevelManager swaps it in, and when the player decides we emit
## level_changed back to the map to return.
##
## Layout lives in recruit_screen.tscn (panel, labels, buttons wired via scene
## connections). This script fills the preview text and builds one recruit
## button per ally type offered at recruit nodes.

## Emitted to tell the LevelManager to load the next scene (the run map).
signal level_changed(next_level_path : String)

## Scene path of the run map hub we return to.
const MAP_LEVEL_PATH : String = "res://scenes/menus/map_menu/map_menu_3d.tscn"

@onready var preview_label : Label = $CenterContainer/Panel/VBox/PreviewLabel
@onready var options_container : VBoxContainer = $CenterContainer/Panel/VBox/RecruitOptions


func _ready() -> void:
	var templates := GameState.get_recruit_templates()
	preview_label.text = "Choose an ally to recruit:"
	for template in templates:
		var button := Button.new()
		button.text = "Recruit %s" % template.display_name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_recruit_button_pressed.bind(template))
		options_container.add_child(button)
	if templates.is_empty():
		preview_label.text = "No allies available to recruit."


func _on_recruit_button_pressed(template : AllyPartyMember) -> void:
	var added := GameState.recruit_ally(template)
	if added == null:
		push_warning("RecruitScreen: recruit_ally returned null.")
	level_changed.emit(MAP_LEVEL_PATH)


func _on_cancel_button_pressed() -> void:
	level_changed.emit(MAP_LEVEL_PATH)
