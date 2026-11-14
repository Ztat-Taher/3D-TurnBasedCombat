extends TextureButton
## Vestige button for displaying vestiges in UI with hover tooltip

@export var vestige: Vestige = null
@export var stack_count: int = 1

@onready var tooltip: Control = get_node_or_null("../VestigeTooltip")
@onready var vestige_icon: TextureRect = $VestigeIcon
@onready var rarity_border: NinePatchRect = $RarityBorder
@onready var scope_indicator: Label = $ScopeIndicator


func _ready():
	if vestige:
		setup_vestige(vestige, stack_count)
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func setup_vestige(v: Vestige, stacks: int = 1) -> void:
	vestige = v
	stack_count = stacks
	
	if vestige == null:
		return
	
	# Set icon if available
	if vestige.icon and vestige_icon:
		vestige_icon.texture = vestige.icon
	
	# Set rarity border color
	if rarity_border:
		match vestige.rarity:
			Vestige.Rarity.COMMON:
				rarity_border.modulate = Color.WHITE
			Vestige.Rarity.UNCOMMON:
				rarity_border.modulate = Color.CYAN
			Vestige.Rarity.RARE:
				rarity_border.modulate = Color.GOLD
			Vestige.Rarity.BOSS:
				rarity_border.modulate = Color.RED
			Vestige.Rarity.EVENT:
				rarity_border.modulate = Color.MAGENTA
			Vestige.Rarity.SHOP:
				rarity_border.modulate = Color.GREEN
	
	# Set scope indicator
	if scope_indicator:
		match vestige.scope:
			Vestige.Scope.GLOBAL:
				scope_indicator.text = "G"
				scope_indicator.modulate = Color.GOLD
			Vestige.Scope.PER_CHARACTER:
				scope_indicator.text = "P"
				scope_indicator.modulate = Color.WHITE


func _on_mouse_entered():
	if tooltip and tooltip.has_method("set_vestige"):
		tooltip.set_vestige(vestige, stack_count)
		tooltip.show_tooltip()


func _on_mouse_exited():
	if tooltip and tooltip.has_method("hide_tooltip"):
		tooltip.hide_tooltip()
