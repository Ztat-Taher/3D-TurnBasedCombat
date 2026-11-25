extends "res://addons/maaacks_game_template/base/nodes/utilities/pause_menu_controller.gd"
## Opens the pause menu on the dedicated `pause` action (Tab / gamepad Start) as
## well as the template's ui_cancel. Battles consume both inputs themselves
## (ui_cancel is "Back" there and the battle HUD opens its own pause menu on
## `pause`), so this only fires on the map and other non-battle screens.

## `pause` is read in _input (before the GUI): Tab is also Godot's ui_focus_next,
## so a focused button would otherwise consume it.
func _input(event : InputEvent) -> void:
	if event.is_action_pressed(&"pause") and pause_menu and not pause_menu.visible:
		get_viewport().set_input_as_handled()
		pause()
