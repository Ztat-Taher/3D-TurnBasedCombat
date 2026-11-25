@tool
extends PopupWindowPanel

@export var options_menu_scene : PackedScene
@export var party_screen_scene : PackedScene
## Path to a main menu scene.
## Will use ProjectSettings paths if left empty.
@export_file("*.tscn") var main_menu_scene_path : String

@onready var restart_confirmation = %RestartConfirmation
@onready var main_menu_confirmation = %MainMenuConfirmation
@onready var exit_confirmation = %ExitConfirmation
@onready var options_button = %OptionsButton
@onready var party_button = %PartyButton
@onready var main_menu_button = %MainMenuButton
@onready var exit_button = %ExitButton

var open_window : Node
var restarting : bool = false
## Bottom-right Back / Confirm hints (authored in the scene; Back is connected to close())
@onready var contextual_bar : ContextualButtonBar = $ContextualRoot/ContextualButtons

func get_main_menu_scene_path() -> String:
	return MaaacksGameTemplate.get_main_menu_path(main_menu_scene_path)

func close_window() -> void:
	if open_window != null:
		if open_window.has_method(&"close"):
			open_window.close()
		else:
			open_window.hide()
		open_window = null

func _load_scene(scene_path: String) -> void:
	_scene_tree.paused = false
	SceneLoader.load_scene(scene_path)

func _show_window(window : Control) -> void:
	window.show()
	open_window = window
	# The sub-window (options, party, confirmation) brings its own hints
	if contextual_bar:
		contextual_bar.visible = false
	await window.hidden
	open_window = null
	if contextual_bar:
		contextual_bar.visible = true

func _load_and_show_menu(scene : PackedScene) -> void:
	var window_instance : Control = scene.instantiate()
	window_instance.visible = false
	add_sibling.call_deferred(window_instance)
	await _show_window(window_instance)
	window_instance.queue_free()

func _handle_cancel_input() -> void:
	if open_window != null:
		return
	super._handle_cancel_input()

## The pause input toggles the menu closed again. Read in _input (before the GUI),
## because Tab is also Godot's ui_focus_next and a focused button would eat it.
func _input(event : InputEvent) -> void:
	if not Engine.is_editor_hint() and is_visible_in_tree() and open_window == null 			and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()

## Confirm is only shown while a menu button is highlighted, and presses it
func _setup_contextual_bar() -> void:
	contextual_bar.follow_focus(self, &"Confirm")

func _refresh_exit_button() -> void:
	exit_button.visible = !OS.has_feature("web")

func _refresh_options_button() -> void:
	options_button.visible = options_menu_scene != null

func _refresh_party_button() -> void:
	party_button.visible = party_screen_scene != null

func _refresh_main_menu_button() -> void:
	main_menu_button.visible = !get_main_menu_scene_path().is_empty()

func _ready() -> void:
	super._ready()
	_refresh_exit_button()
	_refresh_options_button()
	_refresh_party_button()
	_refresh_main_menu_button()
	restart_confirmation.confirmed.connect(_on_restart_confirmation_confirmed)
	restart_confirmation.closed.connect(_on_restart_confirmation_closed)
	main_menu_confirmation.confirmed.connect(_on_main_menu_confirmation_confirmed)
	exit_confirmation.confirmed.connect(_on_exit_confirmation_confirmed)
	if not Engine.is_editor_hint():
		_setup_contextual_bar()

func _on_restart_button_pressed() -> void:
	_show_window(restart_confirmation)

func _on_options_button_pressed() -> void:
	_load_and_show_menu(options_menu_scene)

func _on_party_button_pressed() -> void:
	_load_and_show_menu(party_screen_scene)

func _on_main_menu_button_pressed() -> void:
	_show_window(main_menu_confirmation)

func _on_exit_button_pressed() -> void:
	_show_window(exit_confirmation)

func _on_restart_confirmation_confirmed() -> void:
	restarting = true

func _on_restart_confirmation_closed() -> void:
	if restarting:
		await draw
		SceneLoader.reload_current_scene()

func _on_main_menu_confirmation_confirmed():
	_load_scene(get_main_menu_scene_path())

func _on_exit_confirmation_confirmed():
	get_tree().quit()
