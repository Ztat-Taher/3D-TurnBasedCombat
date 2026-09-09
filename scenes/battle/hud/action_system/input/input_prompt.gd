extends Label
## Shows controller button prompts for UI elements

enum InputType { KEYBOARD, CONTROLLER }
var current_input_type: InputType = InputType.KEYBOARD
var action_name: String = ""
var button_mapping: Dictionary = {
	"open_cards": "A",
	"select_card": "A",
	"cancel_card": "B", 
	"global_back": "B",
	"cycle_target_forward": "RB",
	"cycle_target_backward": "LB",
	"toggle_items": "Y",
	"toggle_run": "X",
	"ui_accept": "A",
	"ui_cancel": "B",
	"ui_left": "←",
	"ui_right": "→",
	"ui_up": "↑",
	"ui_down": "↓"
}

var keyboard_mapping: Dictionary = {
	"open_cards": "Space",
	"select_card": "Space",
	"cancel_card": "Esc",
	"global_back": "Esc",
	"cycle_target_forward": "W",
	"cycle_target_backward": "S",
	"toggle_items": "I",
	"toggle_run": "R",
	"ui_accept": "Space",
	"ui_cancel": "Esc",
	"ui_left": "←",
	"ui_right": "→",
	"ui_up": "↑",
	"ui_down": "↓"
}

func _ready():
	update_prompt()

func set_action(p_action_name: String) -> void:
	self.action_name = p_action_name
	update_prompt()

func update_prompt():
	if action_name.is_empty():
		return
	
	# Detect input type
	if Input.is_joy_known(0):
		current_input_type = InputType.CONTROLLER
	else:
		current_input_type = InputType.KEYBOARD
	
	# Update text based on input type
	match current_input_type:
		InputType.CONTROLLER:
			text = "[" + button_mapping.get(action_name, "?") + "]"
		InputType.KEYBOARD:
			text = "[" + keyboard_mapping.get(action_name, "?") + "]"

func _process(_delta):
	# Check for input type changes periodically
	if Input.is_joy_known(0) and current_input_type == InputType.KEYBOARD:
		current_input_type = InputType.CONTROLLER
		update_prompt()
	elif not Input.is_joy_known(0) and current_input_type == InputType.CONTROLLER:
		current_input_type = InputType.KEYBOARD
		update_prompt()
