extends TextureButton
class_name StopNode

## Individual stop node on the map
## Accepts NodeConfig resource to configure appearance and behavior

signal node_selected(node_id: String, level_path: String)
signal node_hovered(node_id: String)
signal node_exited(node_id: String)

var node_id: String = ""
var node_config: NodeConfig
var level_path: String = ""
var is_available: bool = false
var is_completed: bool = false
var is_locked: bool = false

func _ready() -> void:
	# Enable focus for keyboard/gamepad navigation
	focus_mode = Control.FOCUS_ALL
	
	# Connect signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	pressed.connect(_on_button_pressed)

## Configure the node with NodeConfig resource
func setup(node_data: RunMapNode) -> void:
	node_id = node_data.id
	node_config = node_data.node_config
	level_path = node_data.level_path
	
	# Apply icon texture from config
	if node_config and node_config.icon_texture:
		texture_normal = node_config.icon_texture
	
	# Set initial state
	update_state(false, false)

## Update the node's visual state based on availability and completion
func update_state(available: bool, completed: bool) -> void:
	is_available = available
	is_completed = completed
	is_locked = not available and not completed
	
	if is_completed:
		modulate = Color(0.5, 0.5, 0.5, 0.7)  # Grayed out for completed
		disabled = true
	elif is_available:
		modulate = Color.WHITE  # Normal icon color (no coloring)
		disabled = false
	else:
		modulate = Color(0.5, 0.5, 0.5, 0.4)  # Grayed out for unavailable
		disabled = true

func _on_mouse_entered() -> void:
	if is_locked:
		return
	node_hovered.emit(node_id)

func _on_mouse_exited() -> void:
	node_exited.emit(node_id)

func _on_focus_entered() -> void:
	if is_locked:
		return
	node_hovered.emit(node_id)

func _on_focus_exited() -> void:
	node_exited.emit(node_id)

func _on_button_pressed() -> void:
	if is_available and not is_locked:
		node_selected.emit(node_id, level_path)
