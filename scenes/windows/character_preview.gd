class_name CharacterPreview
extends Control
## Turntable 3D preview of a party member's battle model, rendered in its own
## isolated World3D. Rotate by dragging with the mouse, or with
## rotate_preview_left / _right (Left / Right arrow keys, right stick) at any
## time - no focus needed. The arrow keys are consumed so they don't also move
## GUI focus (WASD / d-pad / left stick still navigate).
##
## Every ally is shown at true scale: the camera frames a fixed slice of the
## world ([member framed_height] above the ground) instead of zooming to each
## model, and each model's feet are snapped onto the same ground line.
##
## Model loading (and stripping the battle logic) lives in [AllyDisplayModel].

## Radians of rotation per pixel of horizontal mouse drag.
@export var drag_rotate_speed : float = 0.01
## Radians per second at full rotate_preview_left / _right input.
@export var key_rotate_speed : float = 2.5
## Starting yaw so the model is seen slightly from the side.
@export var default_yaw_degrees : float = -20.0
## Vertical field of view of the preview camera.
@export var camera_fov : float = 30.0
## World height (meters) framed from the ground up; fits the tallest ally plus
## headroom. All allies share this framing, so relative sizes stay true.
@export var framed_height : float = 2.1
## World width (meters) that must always fit, for narrow layouts.
@export var framed_width : float = 1.6
## Space (meters) kept below the ground line so feet and the hint label never clip.
@export var ground_margin : float = 0.3
## Frames to wait for the idle pose before snapping the feet to the ground.
const GROUND_SNAP_DELAY_FRAMES : int = 2

@onready var viewport : SubViewport = $ViewportContainer/Viewport
@onready var pivot : Node3D = $ViewportContainer/Viewport/Pivot
@onready var camera : Camera3D = $ViewportContainer/Viewport/Camera3D
@onready var placeholder_label : Label = $PlaceholderLabel

var _model : Node3D = null
var _scene_path : String = ""
var _weapon : Weapon = null
var _dragging : bool = false


func _ready() -> void:
	camera.fov = camera_fov
	resized.connect(_frame_view)
	_frame_view()
	focus_exited.connect(func() -> void: _dragging = false)


## Shows [param member]'s battle model (no-op when it's already displayed).
func show_member(member : AllyPartyMember) -> void:
	var path := member.ally_scene_path if member != null else ""
	var weapon := member.equipped_weapon if member != null else null
	if path == _scene_path and weapon == _weapon and is_instance_valid(_model):
		return
	_clear_model()
	_scene_path = path
	_weapon = weapon
	_model = AllyDisplayModel.build(member)
	placeholder_label.visible = _model == null
	if _model == null:
		return
	pivot.add_child(_model)
	pivot.rotation = Vector3(0, deg_to_rad(default_yaw_degrees), 0)
	_snap_to_ground(_model)


func _clear_model() -> void:
	if is_instance_valid(_model):
		pivot.remove_child(_model)
		_model.queue_free()
	_model = null


## Stands [param model] on the ground (y = 0) once its idle pose is applied.
func _snap_to_ground(model : Node3D) -> void:
	for i in GROUND_SNAP_DELAY_FRAMES:
		await get_tree().process_frame
	if not is_instance_valid(model) or model != _model:
		return
	var foot_height := AllyDisplayModel.get_foot_height(model)
	if not is_nan(foot_height):
		model.position.y -= foot_height


## Fixed camera: frames [member framed_height] x [member framed_width] meters
## above the ground, independent of which ally is shown.
func _frame_view() -> void:
	var aspect := maxf(size.x / maxf(size.y, 1.0), 0.1)
	var total_height := framed_height + ground_margin
	var half_height := maxf(total_height, framed_width / aspect) * 0.5
	var center := Vector3(0, framed_height - total_height * 0.5, 0)
	var distance := half_height / tan(deg_to_rad(camera_fov) * 0.5)
	camera.position = center + Vector3(0, 0, distance)
	camera.look_at(center, Vector3.UP)


func _gui_input(event : InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			grab_focus()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		pivot.rotate_y(event.relative.x * drag_rotate_speed)
		accept_event()


## Rotation keys are read in _input (before the GUI) so the arrow keys, which are
## also ui_left / ui_right, rotate instead of moving focus.
func _input(event : InputEvent) -> void:
	if is_visible_in_tree() and (event.is_action(&"rotate_preview_left") or event.is_action(&"rotate_preview_right")):
		get_viewport().set_input_as_handled()


## Rotation itself is polled (Input state updates even for handled events), so
## the stick's analog strength sets the speed.
func _process(delta : float) -> void:
	if not is_visible_in_tree():
		return
	var axis := Input.get_axis(&"rotate_preview_left", &"rotate_preview_right")
	if not is_zero_approx(axis):
		pivot.rotate_y(axis * key_rotate_speed * delta)
