extends Control
## Full-screen "Level Complete" interstitial shown between levels, before the
## run map. Intended to double as the future reward screen: populate
## %RewardsContainer with reward entries before the screen is shown.
##
## The LevelManager instantiates this after a won level and connects to
## 'continue_pressed' / 'main_menu_pressed'. Hiding the screen frees it
## (the manager listens to the built-in 'hidden' signal).

signal continue_pressed
signal main_menu_pressed

func _ready() -> void:
	%ContinueButton.pressed.connect(_on_continue_button_pressed)
	%MainMenuButton.pressed.connect(_on_main_menu_button_pressed)
	%ExitButton.pressed.connect(_on_exit_button_pressed)
	%ContinueButton.grab_focus()

func _on_continue_button_pressed() -> void:
	continue_pressed.emit()
	hide()

func _on_main_menu_button_pressed() -> void:
	main_menu_pressed.emit()
	hide()

func _on_exit_button_pressed() -> void:
	get_tree().quit()
