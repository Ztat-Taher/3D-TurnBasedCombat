class_name StatusIconsContainer
extends HBoxContainer
## Reusable container for displaying status effect icons with hover tooltips
## Used by EnemyHealthBar, PartyStatusCard, and other UI elements
## Shows all active status effects when hovering over the container

var status_icon_template: TextureRect = null
var battler: Battler = null
var status_info_popup_scene: PackedScene = null
var active_status_popups: Array[Control] = []  # Array of popup instances for all states
var popup_container: VBoxContainer = null  # Reference to the PopUpContainer node in the scene

@export var skip_protected: bool = true  # Skip Protected state (has its own UI)

func _ready():
	# Load status info popup scene
	var popup_path = "res://scenes/battle/hud/status_info_popup.tscn"
	if ResourceLoader.exists(popup_path):
		status_info_popup_scene = load(popup_path)
	
	# Set up container-level hover detection
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_container_hovered)
	mouse_exited.connect(_on_container_exited)

func setup(battler_node: Battler, template: TextureRect) -> void:
	battler = battler_node
	status_icon_template = template
	
	if not battler:
		return
	
	# Get reference to PopUpContainer from parent scene
	if get_parent():
		popup_container = get_parent().get_node_or_null("PopUpContainer")
	
	# Connect to state changes
	if battler.has_signal("state_applied") and not battler.state_applied.is_connected(_on_state_applied):
		battler.state_applied.connect(_on_state_applied)
	if battler.has_signal("state_removed") and not battler.state_removed.is_connected(_on_state_removed):
		battler.state_removed.connect(_on_state_removed)
	if battler.has_signal("burn_stack_changed") and not battler.burn_stack_changed.is_connected(_on_burn_stack_changed):
		battler.burn_stack_changed.connect(_on_burn_stack_changed)
	
	# Initial status icons update
	update_status_icons()

func update_status_icons() -> void:
	if not status_icon_template or not battler:
		return
	
	# Clear existing icons
	for child in get_children():
		if child != status_icon_template:
			child.queue_free()
	
	# Add icons for each active state
	for state_name in battler.active_states:
		# Skip Protected state if configured (it has its own shield UI)
		if skip_protected and state_name == "Protected":
			continue
			
		var state = battler.active_states[state_name] as State
		if state:
			var icon = status_icon_template.duplicate()
			icon.visible = true
			icon.custom_minimum_size = Vector2(16, 16)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Icons don't handle mouse events anymore
			
			# Use the state's icon texture if available
			if state.icon_texture:
				icon.texture = state.icon_texture
			
			# Show stack count if applicable
			var count_label = icon.get_node_or_null("StatusCount")
			if count_label:
				# For Bleed, show stack count (determined by card applications)
				if state_name == "Bleed":
					count_label.text = str(state.stack_count)
					count_label.visible = state.stack_count > 0
				# For other states, show stack count
				elif state.stack_count > 0:
					count_label.text = str(state.stack_count)
					count_label.visible = true
				else:
					count_label.visible = false
			
			add_child(icon)

func _on_state_applied(state_name: String) -> void:
	update_status_icons()

func _on_state_removed(state_name: String) -> void:
	update_status_icons()

func _on_burn_stack_changed(stack_count: int) -> void:
	update_status_icons()

func _on_container_hovered() -> void:
	_show_all_status_effects()

func _on_container_exited() -> void:
	_hide_status_popup()

func _show_all_status_effects() -> void:
	if not battler or not status_info_popup_scene:
		return
	
	# Clean up existing popups
	for popup in active_status_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	active_status_popups.clear()
	
	# Only show popups if there are active states
	if battler.active_states.is_empty():
		return
	
	# Use the PopUpContainer from the scene if available
	var container = popup_container
	if not container:
		return
	
	# Create individual popup instances for each state
	var state_index = 0
	for state_name in battler.active_states:
		var state = battler.active_states[state_name] as State
		if state:
			var popup = status_info_popup_scene.instantiate()
			
			# Add popup to the PopUpContainer
			container.add_child(popup)
			
			# Setup popup with individual state and stack index
			if popup.has_method("setup"):
				popup.setup(self, state, state_index)
				# Set bypass timer to show immediately
				if popup.has_method("set_bypass_timer"):
					popup.set_bypass_timer(true)
				# Set hovering to true
				if popup.has_method("set_hovering"):
					popup.set_hovering(true)
				# Show immediately
				if popup.has_method("show_popup"):
					popup.show_popup()
			
			active_status_popups.append(popup)
			state_index += 1

func _hide_status_popup() -> void:
	# Clean up all popups
	for popup in active_status_popups:
		if is_instance_valid(popup):
			if popup.has_method("hide_popup"):
				popup.hide_popup()
			popup.queue_free()
	active_status_popups.clear()

func _exit_tree():
	# Clean up popups when container is destroyed
	for popup in active_status_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	active_status_popups.clear()
