extends Control
## Vestige tooltip that displays vestige information on hover

@onready var vestige_name_label: Label = $VBoxContainer/VestigeName
@onready var description_label: Label = $VBoxContainer/Description
@onready var rarity_label: Label = $VBoxContainer/Rarity
@onready var scope_label: Label = $VBoxContainer/Scope
@onready var stack_label: Label = $VBoxContainer/Stacks

var vestige: Vestige = null
var stack_count: int = 1


func set_vestige(v: Vestige, stacks: int = 1) -> void:
	vestige = v
	stack_count = stacks
	
	if vestige == null:
		return
	
	if vestige_name_label:
		vestige_name_label.text = vestige.vestige_name
	
	if description_label:
		description_label.text = vestige.description
	
	if rarity_label:
		rarity_label.text = "Rarity: " + vestige.get_rarity_name()
		# Set color based on rarity
		match vestige.rarity:
			Vestige.Rarity.COMMON:
				rarity_label.modulate = Color.WHITE
			Vestige.Rarity.UNCOMMON:
				rarity_label.modulate = Color.CYAN
			Vestige.Rarity.RARE:
				rarity_label.modulate = Color.GOLD
			Vestige.Rarity.BOSS:
				rarity_label.modulate = Color.RED
			Vestige.Rarity.EVENT:
				rarity_label.modulate = Color.MAGENTA
			Vestige.Rarity.SHOP:
				rarity_label.modulate = Color.GREEN
	
	if scope_label:
		scope_label.text = "Scope: " + vestige.get_scope_name()
	
	if stack_label:
		if stack_count > 1:
			stack_label.text = "Stacks: " + str(stack_count) + "/" + str(vestige.max_stacks)
		else:
			stack_label.text = ""


func show_tooltip() -> void:
	visible = true


func hide_tooltip() -> void:
	visible = false
