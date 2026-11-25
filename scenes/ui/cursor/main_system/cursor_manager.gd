extends Node
class_name CursorManager
## Custom cursor controller (autoload "CursorSystem").
##
## Three looks, derived fresh every frame from what's actually happening -
## nothing has to be connected to, registered, or restored:
##   CLOSED - left mouse button held (clicking, dragging a card, rotating a model)
##   OPEN   - hovering something interactable
##   POINT  - everything else
##
## "Interactable" means:
##   - the GUI control under the mouse is an enabled button (BaseButton), or
##   - the GUI control under the mouse asks for Godot's pointing-hand cursor
##     (mouse_default_cursor_shape = CURSOR_POINTING_HAND), for custom
##     clickable controls, or
##   - something that does its own hover detection called
##     CursorManager.set_hover(self, true): the card hand (CardUI hit-tests
##     cards under the HUD), map stops (input pushed into a SubViewport), the 3D
##     treasure chest (raycast).

@onready var cursor_display: CursorDisplay = %CursorDisplay

## Non-GUI hover requests: requester -> true (see set_hovering)
var _hover_requests: Dictionary = {}


func _process(_delta: float) -> void:
	if cursor_display:
		cursor_display.set_cursor_state(_compute_state())


func get_cursor_state() -> int:
	return cursor_display.current_state if cursor_display else CursorDisplay.CursorState.POINT


## For hover targets the GUI can't see. Every requester must clear its own
## request; freed requesters are dropped automatically.
func set_hovering(requester: Object, hovering: bool) -> void:
	if hovering:
		_hover_requests[requester] = true
	else:
		_hover_requests.erase(requester)


## [method set_hovering] on the CursorSystem autoload, callable from anywhere
## (no-op when the cursor system isn't running).
static func set_hover(requester: Object, hovering: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var manager := tree.root.get_node_or_null("CursorSystem") as CursorManager
	if manager:
		manager.set_hovering(requester, hovering)


func _compute_state() -> int:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return CursorDisplay.CursorState.CLOSED
	if _is_hovering_interactable():
		return CursorDisplay.CursorState.OPEN
	return CursorDisplay.CursorState.POINT


func _is_hovering_interactable() -> bool:
	for requester in _hover_requests.keys():
		if is_instance_valid(requester):
			return true
		_hover_requests.erase(requester)
	# The hovered control's mouse_default_cursor_shape; Godot tracks it even
	# while the OS cursor is hidden
	if Input.get_current_cursor_shape() == Input.CURSOR_POINTING_HAND:
		return true
	var hovered := get_viewport().gui_get_hovered_control()
	while hovered != null:
		if hovered is BaseButton:
			return not (hovered as BaseButton).disabled
		hovered = hovered.get_parent() as Control
	return false
