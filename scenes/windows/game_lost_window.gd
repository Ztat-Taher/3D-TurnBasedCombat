@tool
extends PopupWindowPanel
## Run-over window: shown when the player is defeated and the run ends.
## There is no retry (Slay the Spire style); the run is cleared when the
## window appears, so 'Continue' won't offer a dead run from the main menu.

signal main_menu_pressed

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint(): return
	# The run ends here: clear it so the main menu doesn't offer to continue it.
	GameState.reset()
	if OS.has_feature("web"):
		%ExitButton.hide()

func _on_exit_button_pressed():
	%ExitConfirmation.show()

func _on_close_button_pressed():
	main_menu_pressed.emit()
	close()

func _on_exit_confirmation_confirmed():
	get_tree().quit()