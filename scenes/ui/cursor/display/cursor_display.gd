extends Control
class_name CursorDisplay
## Draws the custom cursor: follows the mouse, shows the texture for the state
## the [CursorManager] picks, and plays the click / state-change juice. The
## trail keeps the one color set on CursorTrail in the scene.
##
## The OS cursor is hidden by giving every cursor shape a transparent image
## once, rather than forcing MOUSE_MODE_HIDDEN: popups and menus can set the
## mouse mode to VISIBLE (as the window template does) without the OS cursor
## ever appearing, and nothing has to fight over the mouse mode each frame.

enum CursorState {
	POINT = 0,   ## Pointing finger - default
	OPEN = 1,    ## Open hand - hovering something interactable
	CLOSED = 2,  ## Closed hand - left mouse button held
}

@export var point_texture: Texture2D
@export var open_texture: Texture2D
@export var closed_texture: Texture2D
@export var cursor_scale: float = 1.0

var current_state: CursorState = CursorState.POINT

@onready var cursor_sprite: TextureRect = $CursorSprite
@onready var cursor_juice: CursorJuice = $CursorJuice
@onready var trail_tracker: Node2D = $TrailTracker


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_os_cursor()
	cursor_sprite.scale = Vector2.ONE * cursor_scale
	cursor_sprite.texture = _texture_for(current_state)
	if cursor_juice:
		cursor_juice.setup(cursor_sprite, cursor_scale)


func set_cursor_state(new_state: CursorState) -> void:
	if new_state == current_state:
		return
	current_state = new_state
	cursor_sprite.texture = _texture_for(new_state)
	if cursor_juice:
		cursor_juice.animate_state_transition(Vector2.ONE * cursor_scale, Vector2.ONE * cursor_scale, 1.0)


func _texture_for(state: CursorState) -> Texture2D:
	match state:
		CursorState.OPEN:
			return open_texture
		CursorState.CLOSED:
			return closed_texture
		_:
			return point_texture


## A fully transparent image for every OS cursor shape (controls can still
## request shapes; the custom cursor reads them, the OS draws nothing).
func _hide_os_cursor() -> void:
	var blank := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	var texture := ImageTexture.create_from_image(blank)
	for shape in Input.CURSOR_HELP + 1:
		Input.set_custom_mouse_cursor(texture, shape as Input.CursorShape)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_click()


func _process(_delta: float) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	global_position = mouse_pos
	trail_tracker.global_position = mouse_pos


func _play_click() -> void:
	if not cursor_juice:
		return
	cursor_juice.animate_click()
	await get_tree().create_timer(0.1).timeout
	cursor_juice.animate_click_release()
