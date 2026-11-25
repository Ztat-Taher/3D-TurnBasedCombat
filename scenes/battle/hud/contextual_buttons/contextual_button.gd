extends TextureButton
class_name ContextualButton
## Reusable contextual HUD button (target confirm / defense indicators).
## Mirrors the BackButton structure: centered label, input prompt, juice, shadow.

signal confirmed

@export var button_text: String = "" :
	set(value):
		button_text = value
		_apply_text()

@export var prompt_action: StringName = &"" :
	set(value):
		prompt_action = value
		_apply_prompt()

@onready var _label: Label = $ButtonLabel
@onready var _prompt: Control = $InputPrompt

func _ready() -> void:
	# Prompts, not menu entries: keyboard / gamepad / Tab focus never lands here
	# (they're triggered by their own action, or clicked)
	focus_mode = Control.FOCUS_NONE
	_apply_text()
	_apply_prompt()
	pressed.connect(func(): confirmed.emit())

## Smallest the label font may shrink to when the text is long
const MIN_FONT_SIZE := 14

var _base_font_size: int = -1

func _apply_text() -> void:
	if not _label:
		return
	_label.text = button_text
	_fit_label_font()


## Shrinks the label's font until the text fits its area (keeps the button art intact)
func _fit_label_font() -> void:
	if _base_font_size < 0:
		_base_font_size = _label.get_theme_font_size("font_size")
	var font := _label.get_theme_font("font")
	var text := button_text.to_upper() if _label.uppercase else button_text
	var available := _label.size.x if _label.size.x > 0.0 else _label.custom_minimum_size.x
	if available <= 0.0:
		available = _label.offset_right - _label.offset_left
	var size := _base_font_size
	while size > MIN_FONT_SIZE and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > available:
		size -= 1
	_label.add_theme_font_size_override("font_size", size)

func _apply_prompt() -> void:
	if not _prompt:
		return
	_prompt.set("action_name", prompt_action)
	_prompt.visible = prompt_action != &""

func set_button_text(text: String) -> void:
	button_text = text

## Brief press feedback for defense input confirmations.
func flash() -> void:
	var juice := get_node_or_null("ButtonJuice")
	if not (juice and juice.has_method("animate_light_press")):
		return
	juice.animate_light_press()
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(juice):
		juice.animate_light_release()
