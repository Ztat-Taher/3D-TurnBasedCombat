extends Control
## Hover info popup for status effects
## Displays status icon, name, and description when hovering over status icons

var hover_duration_threshold: float = 0.5  # Seconds to hover before showing pop-up
var current_hover_time: float = 0.0
var is_hovering: bool = false
var target_control: Control = null
var state_data: State = null
var popup_index: int = 0  # Index for stacked popups (0 = first, 1 = second, etc.)
var bypass_hover_timer: bool = false  # If true, show immediately without timer

const POPUP_OFFSET: Vector2 = Vector2(20, 0)  # Base offset from target
const STACK_OFFSET: Vector2 = Vector2(0, 45)  # Offset for each additional stacked popup

@onready var background: Panel = get_node("Background")
@onready var content_container: HBoxContainer = get_node_or_null("MarginContainer/ContentContainer") if has_node("MarginContainer/ContentContainer") else get_node_or_null("ContentContainer")
@onready var icon_texture: TextureRect = content_container.get_node("IconTexture") if content_container else null
@onready var text_container: VBoxContainer = content_container.get_node("TextContainer") if content_container else null
@onready var name_label: Label = content_container.get_node("TextContainer/NameLabel") if content_container else null
@onready var description_label: Label = content_container.get_node("TextContainer/DescriptionLabel") if content_container else null

func _ready():
	visible = false
	modulate.a = 0.0

func _process(delta: float) -> void:
	# If bypassing hover timer, don't process timer logic
	if bypass_hover_timer:
		return
	
	if is_hovering:
		current_hover_time += delta
		if current_hover_time >= hover_duration_threshold and not visible:
			show_popup()
	else:
		current_hover_time = 0.0
		if visible:
			hide_popup()

func setup(control: Control, state: State, index: int = 0) -> void:
	target_control = control
	state_data = state
	popup_index = index
	
	if state_data:
		if name_label:
			name_label.text = state_data.state_name
		if description_label:
			var description_text = state_data.state_description
			
			# Add stack count if applicable
			if state_data.stack_count > 0:
				description_text += "\nStacks: " + str(state_data.stack_count)
			
			# Add accumulation for Bleed state
			if state_data.state_name == "Bleed" and "accumulation_value" in state_data:
				var accumulation = state_data.accumulation_value
				var max_accumulation = state_data.accumulation_max if state_data.accumulation_max > 0 else 100
				var percentage = int((float(accumulation) / float(max_accumulation)) * 100) if max_accumulation > 0 else 0
				description_text += "\nAccumulation: " + str(accumulation) + "/" + str(max_accumulation) + " (" + str(percentage) + "%)"
			
			description_label.text = description_text
		if icon_texture and state_data.icon_texture:
			icon_texture.texture = state_data.icon_texture
			icon_texture.visible = true
		elif icon_texture:
			icon_texture.visible = false
	
	if not (get_parent() is VBoxContainer):
		update_position()

func update_position() -> void:
	if not target_control:
		return
	
	# If this popup is a child of a VBoxContainer (for status container or card hover),
	# the container handles positioning, so we skip manual positioning
	if get_parent() is VBoxContainer:
		return
	
	# If this popup is a child of another popup (like card description),
	# the parent handles positioning, so we skip viewport bounds checking
	if get_parent() != get_tree().root and get_parent() != target_control:
		# Parent handles positioning, we just use local position
		return
	
	# Calculate base position with stack offset
	var stack_offset = STACK_OFFSET * popup_index
	var total_offset = POPUP_OFFSET + stack_offset
	
	# Position popup to the right of the target
	position = Vector2(target_control.size.x + total_offset.x, total_offset.y)
	
	# Ensure popup stays on screen
	var target_global_pos = target_control.global_position
	var viewport_rect = get_viewport_rect()
	var global_popup_pos = target_global_pos + position
	
	# Check right edge
	if global_popup_pos.x + size.x > viewport_rect.size.x:
		position.x = -size.x - total_offset.x
	
	# Check top edge
	if global_popup_pos.y < 0:
		position.y = -target_global_pos.y + total_offset.y
	
	# Check bottom edge
	if global_popup_pos.y + size.y > viewport_rect.size.y:
		position.y = viewport_rect.size.y - size.y - target_global_pos.y

func show_popup() -> void:
	visible = true
	update_position()
	
	# Fade in animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

func hide_popup() -> void:
	# Fade out animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): visible = false)

func set_hovering(hovering: bool) -> void:
	is_hovering = hovering

func set_bypass_timer(bypass: bool) -> void:
	bypass_hover_timer = bypass
