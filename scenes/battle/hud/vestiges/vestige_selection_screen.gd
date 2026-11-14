extends Control
## Vestige selection screen for boss rewards (3 choices)

signal vestige_selected(vestige: Vestige)

@onready var title_label: Label = $VBoxContainer/Title
@onready var choices_container: HBoxContainer = $VBoxContainer/ChoicesContainer
@onready var continue_button: Button = $VBoxContainer/ContinueButton

var vestige_choices: Array[Vestige] = []
var selected_vestige: Vestige = null


func _ready():
	continue_button.pressed.connect(_on_continue_pressed)
	continue_button.disabled = true


func set_vestige_choices(choices: Array[Vestige]) -> void:
	vestige_choices = choices
	
	# Clear existing choices
	for child in choices_container.get_children():
		child.queue_free()
	
	# Create choice buttons
	for i in range(choices.size()):
		var vestige = choices[i]
		if vestige == null:
			continue
		
		var choice_button = create_choice_button(vestige, i)
		choices_container.add_child(choice_button)


func create_choice_button(vestige: Vestige, index: int) -> Button:
	var button = Button.new()
	button.text = vestige.vestige_name
	button.custom_minimum_size = Vector2(200, 100)
	
	# Create button content
	var vbox = VBoxContainer.new()
	button.add_child(vbox)
	
	var icon = TextureRect.new()
	icon.texture = vestige.icon
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	vbox.add_child(icon)
	
	var name_label = Label.new()
	name_label.text = vestige.vestige_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	var desc_label = Label.new()
	desc_label.text = vestige.description
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)
	
	button.pressed.connect(_on_choice_selected.bind(vestige, button))
	
	return button


func _on_choice_selected(vestige: Vestige, button: Button) -> void:
	selected_vestige = vestige
	
	# Visual feedback - highlight selected button
	for child in choices_container.get_children():
		if child is Button:
			child.modulate = Color.WHITE
	
	button.modulate = Color.GOLD
	continue_button.disabled = false


func _on_continue_pressed():
	if selected_vestige:
		vestige_selected.emit(selected_vestige)
		hide()
