extends MainMenu
## Main menu extension that adds options.
## The scene adds a 'Continue' button if a game is in progress.

## If true, have the player confirm before starting a new game if a game is in progress.
@export var confirm_new_game : bool = true

@onready var continue_game_button = %ContinueGameButton
@onready var new_game_confirmation = %NewGameConfirmation

func load_game_scene() -> void:
	GameState.start_game()
	super.load_game_scene()

func new_game() -> void:
	if confirm_new_game and continue_game_button.visible:
		new_game_confirmation.show()
	else:
		GameState.reset()
		load_game_scene()

func _show_continue_if_set() -> void:
	if GameState.get_current_level_path().is_empty(): return
	continue_game_button.show()

func _ready() -> void:
	super._ready()
	_show_continue_if_set()

func _on_continue_game_button_pressed() -> void:
	GameState.continue_game()
	load_game_scene()

func _on_new_game_confirmation_confirmed() -> void:
	GameState.reset()
	load_game_scene()
