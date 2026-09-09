extends Control
## Timer-based description pop-up for cards
## Appears after hovering for a set duration and auto-hides when not hovering

var hover_duration_threshold: float = 0.5  # Seconds to hover before showing pop-up
var current_hover_time: float = 0.0
var is_hovering_card: bool = false
var card_button: Control = null
var description_text: String = ""

const POPUP_OFFSET: Vector2 = Vector2(10, -20)  # Offset from card

@onready var description_label: Label = get_node("DescriptionLabel")
@onready var background: NinePatchRect = get_node("Background")

func _ready():
	visible = false
	
	if description_label:
		description_label.modulate = Color(1, 1, 1, 1)

func _process(delta: float) -> void:
	if is_hovering_card:
		current_hover_time += delta
		if current_hover_time >= hover_duration_threshold and not visible:
			show_popup()
	else:
		current_hover_time = 0.0
		if visible:
			hide_popup()

func setup(card: Control, description: String) -> void:
	card_button = card
	description_text = description
	
	if description_label:
		description_label.text = description
	
	# Position popup relative to card
	update_position()

func update_position() -> void:
	if not card_button:
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
	
	# Fade in animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

func hide_popup() -> void:
	# Fade out animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): visible = false)

func set_hovering(hovering: bool) -> void:
	is_hovering_card = hovering
