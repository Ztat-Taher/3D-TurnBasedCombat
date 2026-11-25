extends HBoxContainer
class_name ContextualButtonBar
## Generic bottom-right bar of contextual buttons ("what do Confirm / Cancel do
## right now?").
##
## Buttons are normally authored in the scene: instance contextual_button.tscn
## as children of the bar, set their text / prompt action there, and connect
## their `confirmed` signal in the scene. Each child is registered under its node
## name, so code can refer to it:
##
##   bar.follow_focus(card, &"Confirm")   # Confirm shows while a button inside
##                                        # `card` is highlighted, and presses it
##   bar.show_button(&"Cancel") / bar.hide_button(&"Cancel")
##   bar.set_callback(&"Confirm", _open_chest)
##
## Buttons can also be created at runtime (the battle HUD does this) by passing a
## text to show_button().
##
## Layout: the bar spans the bottom of the screen. Back / Cancel buttons (prompt
## action in CANCEL_ACTIONS) always sit on the LEFT; everything else on the RIGHT.
## Within a side, buttons are ordered by `order`, then by when they were added.

## Emitted with the id of the contextual button that was triggered (click or input).
signal confirmed(id: StringName)

const BUTTON_SCENE := preload("res://scenes/battle/hud/contextual_buttons/contextual_button.tscn")
## Buttons bound to these actions are Back / Cancel buttons: left side of the screen
const CANCEL_ACTIONS: Array[StringName] = [&"ui_cancel", &"Cancel"]

## When on, pressing a shown button's input action triggers it. Uses unhandled input,
## so a focused Button (which consumes ui_accept itself) always wins and nothing fires twice.
## Leave off where another system already reads those actions (battle manager, windows).
@export var handle_input_actions: bool = false
@export var button_size: Vector2 = Vector2(250, 60)

var _buttons: Dictionary = {}    # id -> ContextualButton
var _callbacks: Dictionary = {}  # id -> Callable
var _orders: Dictionary = {}     # id -> int

## Expanding gap between the left (cancel) and right buttons (bar scene node)
@onready var _spacer: Control = get_node_or_null("Spacer")

var _focus_root: Control
var _focus_id: StringName
var _focus_target: BaseButton


func _ready() -> void:
	# Buttons authored in the scene register under their node name
	for child in get_children():
		if child is ContextualButton and not _buttons.has(StringName(child.name)):
			_register(StringName(child.name), child, 0)
	_sort_buttons()


# --- API --------------------------------------------------------------------------

## Shows the button `id`. For a scene-authored button, leave `text`/`action` empty to
## keep what the scene set. Passing a `text` for an unknown id creates the button.
## `callback` (if given) runs when it's triggered, in addition to `confirmed`.
## `interactive = false` makes it a display-only indicator that ignores the mouse.
func show_button(id: StringName, text: String = "", action: StringName = &"", callback: Callable = Callable(),
		order: int = 0, interactive: bool = true) -> ContextualButton:
	var button: ContextualButton = _buttons.get(id)
	if button == null:
		if text == "":
			push_warning("ContextualButtonBar: no button '%s' to show" % id)
			return null
		button = BUTTON_SCENE.instantiate()
		button.name = String(id)
		button.custom_minimum_size = button_size
		add_child(button)
		_register(id, button, order)
	if text != "":
		button.set_button_text(text)
	if action != &"":
		button.prompt_action = action
	if callback.is_valid():
		_callbacks[id] = callback
	_orders[id] = order
	button.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	button.visible = true
	button.modulate.a = 1.0
	_sort_buttons()
	return button


func hide_button(id: StringName) -> void:
	var button: ContextualButton = _buttons.get(id)
	if button:
		button.visible = false


## Hides every button (and stops following focus)
func hide_all() -> void:
	stop_following_focus()
	for id in _buttons:
		_buttons[id].visible = false


## Sets (or clears, with an invalid Callable) what triggering `id` runs
func set_callback(id: StringName, callback: Callable) -> void:
	if callback.is_valid():
		_callbacks[id] = callback
	else:
		_callbacks.erase(id)


func set_button_text(id: StringName, text: String) -> void:
	var button: ContextualButton = _buttons.get(id)
	if button:
		button.set_button_text(text)


func is_button_shown(id: StringName) -> bool:
	var button: ContextualButton = _buttons.get(id)
	return button != null and button.visible


func get_button(id: StringName) -> ContextualButton:
	return _buttons.get(id)


## Brief press animation (e.g. to acknowledge input handled elsewhere)
func flash_button(id: StringName) -> void:
	var button: ContextualButton = _buttons.get(id)
	if button and button.visible:
		button.flash()


## Runs a button as if it was pressed. Goes through the button's own `confirmed`
## signal, so connections made in the scene fire for input as well as clicks.
func trigger(id: StringName) -> void:
	if not is_button_shown(id):
		return
	_buttons[id].confirmed.emit()


## Button `id` (e.g. a scene-authored "Confirm") is shown only while a button inside
## `root` is highlighted (keyboard/gamepad focus), and triggering it presses that
## button. Its label stays as authored.
func follow_focus(root: Control, id: StringName = &"Confirm") -> void:
	stop_following_focus()
	_focus_root = root
	_focus_id = id
	set_callback(id, _press_focus_target)
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	_on_gui_focus_changed(get_viewport().gui_get_focus_owner())


func stop_following_focus() -> void:
	if _focus_root == null:
		return
	if get_viewport().gui_focus_changed.is_connected(_on_gui_focus_changed):
		get_viewport().gui_focus_changed.disconnect(_on_gui_focus_changed)
	set_callback(_focus_id, Callable())
	hide_button(_focus_id)
	_focus_root = null
	_focus_target = null


# --- Internals --------------------------------------------------------------------

func _register(id: StringName, button: ContextualButton, order: int) -> void:
	_buttons[id] = button
	_orders[id] = order
	button.confirmed.connect(_on_button_confirmed.bind(id))


## Every press (click or input) ends up here: flash, callback, bar-level signal
func _on_button_confirmed(id: StringName) -> void:
	flash_button(id)
	var callback: Callable = _callbacks.get(id, Callable())
	if callback.is_valid():
		callback.call()
	confirmed.emit(id)


func is_cancel_button(id: StringName) -> bool:
	var button: ContextualButton = _buttons.get(id)
	return button != null and button.prompt_action in CANCEL_ACTIONS


## Cancel buttons left of the Spacer, the rest right of it; each side stable-sorted
## by order, keeping registration order for ties.
func _sort_buttons() -> void:
	var ids := _buttons.keys()
	var left := []
	var right := []
	for i in ids.size():
		var entry := [_orders.get(ids[i], 0), i, ids[i]]
		if is_cancel_button(ids[i]):
			left.append(entry)
		else:
			right.append(entry)
	left.sort()
	right.sort()
	var index := 0
	for entry in left:
		move_child(_buttons[entry[2]], index)
		index += 1
	if _spacer:
		move_child(_spacer, index)
		index += 1
	for entry in right:
		move_child(_buttons[entry[2]], index)
		index += 1


func _unhandled_input(event: InputEvent) -> void:
	if not handle_input_actions or event.is_echo():
		return
	for id in _buttons:
		var button: ContextualButton = _buttons[id]
		if button.visible and button.prompt_action != &"" \
				and InputMap.has_action(button.prompt_action) \
				and event.is_action_pressed(button.prompt_action):
			get_viewport().set_input_as_handled()
			trigger(id)
			return


func _on_gui_focus_changed(control: Control) -> void:
	if _focus_root == null or not is_instance_valid(_focus_root):
		return
	var target := control as BaseButton
	var inside := target != null and _focus_root.is_ancestor_of(target) \
			and target.is_visible_in_tree() and not target.disabled
	_focus_target = target if inside else null
	var button: ContextualButton = _buttons.get(_focus_id)
	if button:
		button.visible = inside


func _press_focus_target() -> void:
	if not is_instance_valid(_focus_target) or _focus_target.disabled:
		return
	if _focus_target.toggle_mode:
		_focus_target.button_pressed = true
	_focus_target.pressed.emit()
