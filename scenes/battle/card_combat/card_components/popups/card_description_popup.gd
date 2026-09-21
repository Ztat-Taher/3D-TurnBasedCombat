extends Control
## Timer-based description pop-up for cards
## Appears after hovering for a set duration and auto-hides when not hovering

var hover_duration_threshold: float = 0.5  # Seconds to hover before showing pop-up
var current_hover_time: float = 0.0
var is_hovering_card: bool = false
var card_button: Control = null
var description_text: String = ""
var status_effects: Array[State] = []
var status_info_popup_scene: PackedScene = null
var active_status_popups: Array[Control] = []
var content_container: VBoxContainer = null  # Container to group description and status popups
var popup_container: VBoxContainer = null  # Reference to PopUpContainer from parent

const POPUP_OFFSET: Vector2 = Vector2(10, -20)  # Offset from card
const STATUS_STACK_OFFSET: Vector2 = Vector2(0, 50)  # Offset for stacked status popups

@onready var description_label: Label = get_node_or_null("MarginContainer/DescriptionLabel") if has_node("MarginContainer/DescriptionLabel") else get_node_or_null("DescriptionLabel")
@onready var background: Panel = get_node("Background")

func _ready():
	visible = false
	modulate.a = 0.0
	
	# Load status info popup scene
	var status_popup_path = "res://scenes/battle/hud/status_info_popup.tscn"
	if ResourceLoader.exists(status_popup_path):
		status_info_popup_scene = load(status_popup_path)

func _process(delta: float) -> void:
	if is_hovering_card:
		current_hover_time += delta
		if current_hover_time >= hover_duration_threshold and not visible:
			show_popup()
	else:
		current_hover_time = 0.0
		if visible:
			hide_popup()

func setup(card: Control, description: String, effects: Array[State] = []) -> void:
	card_button = card
	description_text = description
	status_effects = effects
	
	# Get reference to PopUpContainer from parent scene (card_button)
	if card_button:
		popup_container = card_button.get_node_or_null("PopUpContainer")
	
	# Set description text
	if description_label:
		description_label.text = description
	
	# Create status effect popups if any
	_create_status_popups()
	
	# Position popup relative to card
	update_position()

func _create_status_popups() -> void:
	# Clean up existing status popups
	for popup in active_status_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	active_status_popups.clear()
	
	# Create new status popups
	if not status_info_popup_scene or status_effects.is_empty():
		return
	
	for i in range(status_effects.size()):
		var state = status_effects[i]
		if not state:
			continue
		
		var popup = status_info_popup_scene.instantiate()
		
		# Add popup to the PopUpContainer from the scene
		if popup_container:
			popup_container.add_child(popup)
		else:
			# Fallback: add as direct child if container doesn't exist
			add_child(popup)
		
		# Setup popup with state data
		if popup.has_method("setup"):
			# Use self as target control so status popups position relative to description popup
			popup.setup(self, state, i)
			if popup.has_method("set_bypass_timer"):
				popup.set_bypass_timer(true)
		
		popup.visible = false
		popup.modulate.a = 0.0
		active_status_popups.append(popup)
	
	# Update size to accommodate content
	_update_popup_size()

func _update_popup_size() -> void:
	# Let the VBoxContainer handle sizing automatically
	if content_container:
		await get_tree().process_frame
		# Force the container to update its size
		content_container.queue_sort()
		await get_tree().process_frame
		
		# Set popup size to match container content
		var content_size = content_container.get_combined_minimum_size()
		custom_minimum_size = Vector2(200.0, content_size.y + 30)
		size = custom_minimum_size

func update_position() -> void:
	if not card_button or (get_parent() is VBoxContainer):
		return
	
	# Position popup to the right of the card
	position = Vector2(card_button.size.x + POPUP_OFFSET.x, POPUP_OFFSET.y)
	
	# Ensure popup stays on screen
	var card_global_pos = card_button.global_position
	var viewport_rect = get_viewport_rect()
	var global_popup_pos = card_global_pos + position
	
	if global_popup_pos.x + size.x > viewport_rect.size.x:
		position.x = -size.x - POPUP_OFFSET.x
	if global_popup_pos.y < 0:
		position.y = -card_global_pos.y + POPUP_OFFSET.y
	if global_popup_pos.y + size.y > viewport_rect.size.y:
		position.y = viewport_rect.size.y - size.y - card_global_pos.y

func show_popup() -> void:
	visible = true
	update_position()
	
	# Show status popups directly (bypass their hover timer)
	for popup in active_status_popups:
		if is_instance_valid(popup):
			popup.visible = true
			popup.modulate.a = 1.0
	
	# Fade in animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

func hide_popup() -> void:
	# Hide status popups directly
	for popup in active_status_popups:
		if is_instance_valid(popup):
			popup.visible = false
			popup.modulate.a = 0.0
	
	# Fade out animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): visible = false)

func set_hovering(hovering: bool) -> void:
	is_hovering_card = hovering

func _exit_tree():
	# Clean up status popups when popup is destroyed
	for popup in active_status_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	active_status_popups.clear()
	
	# Clean up content container
	if content_container and is_instance_valid(content_container):
		content_container.queue_free()
		content_container = null
