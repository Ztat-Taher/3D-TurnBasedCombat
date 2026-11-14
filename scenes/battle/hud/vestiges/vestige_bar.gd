extends Control
## Vestige bar panel for displaying owned vestiges in battle HUD

@onready var global_vestiges_container: HBoxContainer = $VBoxContainer/GlobalVestiges/Container
@onready var per_character_vestiges_container: HBoxContainer = $VBoxContainer/PerCharacterVestiges/Container

var current_battler: Battler = null


func _ready():
	# Listen for battler changes
	if has_node("/root/SignalBus"):
		# Would connect to a signal when active battler changes
		pass


func set_battler(battler: Battler) -> void:
	current_battler = battler
	refresh_vestiges()


func refresh_vestiges() -> void:
	if current_battler == null:
		return
	
	# Clear existing vestige buttons
	for child in global_vestiges_container.get_children():
		child.queue_free()
	for child in per_character_vestiges_container.get_children():
		child.queue_free()
	
	# Load global vestiges
	var global_vestiges = GameState.get_global_vestiges()
	for vestige in global_vestiges:
		var stacks = GameState.get_global_vestige_stack_count(vestige.vestige_id)
		var button = create_vestige_button(vestige, stacks)
		global_vestiges_container.add_child(button)
	
	# Load per-character vestiges for current battler
	var member_id = str(current_battler.get_meta(AllyPartyMember.META_PARTY_MEMBER_ID, ""))
	if not member_id.is_empty():
		var member = GameState.get_party_member(member_id)
		if member:
			for vestige in member.vestiges:
				if vestige.scope == Vestige.Scope.PER_CHARACTER:
					var stacks = member.get_vestige_stack_count(vestige.vestige_id)
					var button = create_vestige_button(vestige, stacks)
					per_character_vestiges_container.add_child(button)


func create_vestige_button(vestige: Vestige, stacks: int) -> TextureButton:
	var button = TextureButton.new()
	button.custom_minimum_size = Vector2(48, 48)
	
	# Create vestige icon
	var icon = TextureRect.new()
	icon.texture = vestige.icon
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.custom_minimum_size = Vector2(40, 40)
	icon.position = Vector2(4, 4)
	button.add_child(icon)
	
	# Rarity border
	var border = NinePatchRect.new()
	border.custom_minimum_size = Vector2(48, 48)
	border.position = Vector2(0, 0)
	match vestige.rarity:
		Vestige.Rarity.COMMON:
			border.modulate = Color.WHITE
		Vestige.Rarity.UNCOMMON:
			border.modulate = Color.CYAN
		Vestige.Rarity.RARE:
			border.modulate = Color.GOLD
		Vestige.Rarity.BOSS:
			border.modulate = Color.RED
		Vestige.Rarity.EVENT:
			border.modulate = Color.MAGENTA
		Vestige.Rarity.SHOP:
			border.modulate = Color.GREEN
	button.add_child(border)
	
	# Add tooltip support
	button.mouse_entered.connect(_on_vestige_hovered.bind(vestige, stacks))
	button.mouse_exited.connect(_on_vestige_unhovered)
	
	return button


func _on_vestige_hovered(vestige: Vestige, stacks: int):
	# Show tooltip - would integrate with tooltip system
	print("[VESTIGE BAR] Hover: %s (stacks: %d)" % [vestige.vestige_name, stacks])


func _on_vestige_unhovered():
	# Hide tooltip
	pass
