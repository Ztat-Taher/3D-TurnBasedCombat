extends Control
class_name CardButton
## Button representing a card in the player's hand with visual polish

signal card_played(card: CardData)

var card_data: CardData
var is_hovered: bool = false
var is_selected: bool = false
var base_position: Vector2
var hover_offset: float = -30.0

@onready var card_panel = get_node("CardPanel")
@onready var name_label = get_node("CardPanel/Content/VBox/CardName")
@onready var cost_label = get_node("CardPanel/Content/VBox/CostContainer/CostLabel")
@onready var cost_background = get_node("CardPanel/Content/VBox/CostContainer")
@onready var description_label = get_node("CardPanel/Content/VBox/CardDescription")
@onready var glow = get_node("Glow")

func setup(card: CardData) -> void:
	card_data = card
	
	print("Setting up card button for: ", card.name)
	print("Has CardPanel: ", has_node("CardPanel"))
	print("Has Glow: ", has_node("Glow"))
	
	# Force refresh node references
	card_panel = get_node_or_null("CardPanel")
	name_label = get_node_or_null("CardPanel/Content/VBox/CardName")
	cost_label = get_node_or_null("CardPanel/Content/VBox/CostContainer/CostLabel")
	description_label = get_node_or_null("CardPanel/Content/VBox/CardDescription")
	glow = get_node_or_null("Glow")
	
	if name_label:
		name_label.text = card.name
		print("Name label set to: ", card.name)
	else:
		print("ERROR: name_label not found!")
	
	if cost_label:
		cost_label.text = str(card.cost)
		print("Cost label set to: ", card.cost)
	else:
		print("ERROR: cost_label not found!")
	
	if description_label:
		# Build description from card stats and metadata
		var description = ""
		
		if card.attack > 0:
			description += "Damage: " + str(card.attack) + "\n"
		if card.health > 0:
			description += "Health: " + str(card.health) + "\n"
		
		# Add custom description from metadata
		if card.metadata.has("description"):
			description += card.metadata["description"]
		
		description_label.text = description
		print("Description label set to: ", description)
	else:
		print("ERROR: description_label not found!")
	
	# Set card type styling
	_set_card_type_color()

var base_rotation: float = 0.0
var base_y_offset: float = 0.0
var base_z_index: int = 0

var hover_tween: Tween

func set_fan_parameters(rot_deg: float, y_offset: float, z_idx: int) -> void:
	base_rotation = rot_deg
	base_y_offset = y_offset
	base_z_index = z_idx
	z_index = z_idx
	
	if not is_hovered:
		if card_panel:
			card_panel.rotation_degrees = base_rotation
			card_panel.position.y = base_y_offset
		if glow:
			glow.rotation_degrees = base_rotation
			glow.position.y = -4.0 + base_y_offset

func _ready():
	pivot_offset = Vector2(60, 180)
	if card_panel:
		card_panel.pivot_offset = Vector2(60, 180)
	if glow:
		glow.pivot_offset = Vector2(64, 184)
		glow.modulate.a = 0.0
	# Initial pop-in animation
	_pop_in()

func _set_card_type_color():
	if not card_data or not card_panel:
		return
	
	var card_type = card_data.metadata.get("card_type", "attack")
	var color: Color
	
	match card_type:
		"attack":
			color = Color(0.8, 0.3, 0.3)  # Red
		"heal":
			color = Color(0.3, 0.8, 0.3)  # Green
		"defense":
			color = Color(0.3, 0.5, 0.8)  # Blue
		_:
			color = Color(0.7, 0.7, 0.7)  # Gray
	
	card_panel.modulate = color

func _pop_in():
	scale = Vector2.ZERO
	var tween = create_tween()
	tween.set_ease(Tween.EaseType.EASE_OUT)
	tween.set_trans(Tween.TransitionType.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2.ONE, 0.3)

func _on_mouse_entered():
	is_hovered = true
	z_index = 100
	_animate_hover(true)

func _on_mouse_exited():
	is_hovered = false
	z_index = base_z_index
	_animate_hover(false)

func _animate_hover(hover: bool):
	if hover_tween and hover_tween.is_running():
		hover_tween.kill()
	
	var panel_target_y = (base_y_offset - 45.0) if hover else base_y_offset
	var glow_target_y = -4.0 + panel_target_y
	var target_rotation = 0.0 if hover else base_rotation
	var target_scale = Vector2(1.2, 1.2) if hover else Vector2.ONE
	var target_glow_alpha = 0.6 if hover else 0.0
	
	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.set_ease(Tween.EaseType.EASE_OUT)
	hover_tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	
	if card_panel:
		hover_tween.tween_property(card_panel, "position:y", panel_target_y, 0.15)
		hover_tween.tween_property(card_panel, "rotation_degrees", target_rotation, 0.15)
		hover_tween.tween_property(card_panel, "scale", target_scale, 0.15)
	
	if glow:
		hover_tween.tween_property(glow, "position:y", glow_target_y, 0.15)
		hover_tween.tween_property(glow, "rotation_degrees", target_rotation, 0.15)
		hover_tween.tween_property(glow, "scale", target_scale, 0.15)
		hover_tween.tween_property(glow, "modulate:a", target_glow_alpha, 0.15)

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_play_card()

func _play_card():
	# Squash and stretch animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.3, 0.7), 0.1)
	tween.tween_property(self, "rotation_degrees", rotation_degrees + 10, 0.1)
	
	tween.tween_interval(0.05)
	
	tween.tween_property(self, "scale", Vector2(0.8, 1.2), 0.1)
	tween.tween_property(self, "rotation_degrees", rotation_degrees - 10, 0.1)
	
	tween.tween_interval(0.05)
	
	tween.tween_property(self, "scale", Vector2.ZERO, 0.15)
	
	await tween.finished
	
	card_played.emit(card_data)
	queue_free()
