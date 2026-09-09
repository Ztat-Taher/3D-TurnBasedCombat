extends Node
## Setup script for global shader variables required by the pseudo 3D card shader
## Attach this to an autoload singleton or run it once during game initialization

func _ready() -> void:
	_setup_shader_globals()

func _setup_shader_globals():
	## Initialize global shader variables for the pseudo 3D card shader
	## mouse_screen_pos: Vector2 - Current mouse position in screen coordinates
	RenderingServer.global_shader_parameter_set("mouse_screen_pos", Vector2(0, 0))
	print("Pseudo 3D card shader globals initialized")