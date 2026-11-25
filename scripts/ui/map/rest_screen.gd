class_name RestScreen
extends Control
## Rest site UI, opened as its own scene from the run map (the same way a
## Combat node opens its battle scene): the map emits level_changed with this
## scene's path, the LevelManager swaps it in, and when the player is done we
## emit level_changed back to the map to return.
##
## Layout lives in rest_screen.tscn (panel, title, party-row container, action
## buttons wired via scene connections). This script only fills the party rows
## and reacts to the buttons.

## Emitted to tell the LevelManager to load the next scene (the run map).
signal level_changed(next_level_path : String)

## Scene path of the run map hub we return to.
const MAP_LEVEL_PATH : String = "res://scenes/menus/map_menu/map_menu_3d.tscn"
## Row scene instanced once per party member.
const PARTY_ROW_SCENE : PackedScene = preload("res://scenes/menus/map_menu/party_row.tscn")

## HP restored per heal (999 = full heal).
@export var heal_amount : int = 999

@onready var party_rows : VBoxContainer = $CenterContainer/Panel/VBox/PartyRows
@onready var panel : Control = $CenterContainer/Panel
@onready var heal_all_button : Button = $CenterContainer/Panel/VBox/Actions/HealAllButton
## Bottom-right Cancel / Confirm (authored in the scene; Cancel is connected to Done)
@onready var contextual_bar : ContextualButtonBar = $ContextualButtons


func _ready() -> void:
	_populate_party_rows()
	_setup_navigation()


## Keyboard / gamepad: start on Heal All; hovering a button highlights it too.
## Confirm is shown while a button is highlighted and presses it.
func _setup_navigation() -> void:
	for button in panel.find_children("*", "BaseButton", true, false):
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_entered.connect(button.grab_focus)
	contextual_bar.follow_focus(panel, &"Confirm")
	heal_all_button.grab_focus.call_deferred()


func _ensure_party() -> Array[AllyPartyMember]:
	var party := GameState.get_party()
	if party.is_empty():
		GameState.ensure_starter_party()
		party = GameState.get_party()
	return party


func _populate_party_rows() -> void:
	for member in _ensure_party():
		var row := PARTY_ROW_SCENE.instantiate() as PartyRow
		if row == null:
			continue
		party_rows.add_child(row)
		row.setup(member, heal_amount)


func _on_heal_all_button_pressed() -> void:
	for member in GameState.get_party():
		member.heal(heal_amount)
	for row in party_rows.get_children():
		if row is PartyRow:
			row.refresh()
	GlobalState.save()


func _on_done_button_pressed() -> void:
	level_changed.emit(MAP_LEVEL_PATH)
