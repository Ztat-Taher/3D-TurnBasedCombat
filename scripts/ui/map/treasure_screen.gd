class_name TreasureScreen
extends Control
## Treasure chest UI, opened as its own scene from the run map
## Awards a random vestige to the player

signal level_changed(next_level_path : String)

const MAP_LEVEL_PATH : String = "res://scenes/menus/map_menu/map_menu_3d.tscn"

@onready var title_label: Label = $CenterContainer/Panel/VBox/TitleLabel
@onready var vestige_name_label: Label = $CenterContainer/Panel/VBox/VestigeContainer/VestigeName
@onready var vestige_description_label: Label = $CenterContainer/Panel/VBox/VestigeContainer/VestigeDescription
@onready var rarity_label: Label = $CenterContainer/Panel/VBox/VestigeContainer/RarityLabel
@onready var take_button: Button = $CenterContainer/Panel/VBox/Actions/TakeButton
@onready var skip_button: Button = $CenterContainer/Panel/VBox/Actions/SkipButton
@onready var party_selection_container: HBoxContainer = $CenterContainer/Panel/VBox/PartySelectionContainer
@onready var party_selection_label: Label = $CenterContainer/Panel/VBox/PartySelectionContainer/SelectionLabel

var awarded_vestige: Vestige = null
var selected_party_member: AllyPartyMember = null


func _ready() -> void:
	_generate_random_vestige()
	_setup_party_selection()


func _generate_random_vestige() -> void:
	# Load vestige library
	var library_path = "res://database/vestiges/vestige_library.tres"
	if not ResourceLoader.exists(library_path):
		_show_error("Vestige library not found")
		return

	var library = load(library_path)
	if library == null:
		_show_error("Failed to load vestige library")
		return

	# Get already owned vestiges to avoid duplicates
	var owned_vestiges: Array = []
	var global_vestiges = GameState.get_global_vestiges()
	owned_vestiges.append_array(global_vestiges)

	var party = GameState.get_party()
	for member in party:
		owned_vestiges.append_array(member.vestiges)

	# Get random vestige from common/uncommon/rare pools
	var all_pools: Array = []
	all_pools.append_array(library.common_vestiges)
	all_pools.append_array(library.uncommon_vestiges)
	all_pools.append_array(library.rare_vestiges)

	var available = all_pools.filter(func(v): return not v in owned_vestiges)

	if available.is_empty():
		_show_no_vestiges_available()
		return

	# Weighted random selection (rarer vestiges have lower chance)
	var roll = randf()
	var selected: Vestige

	if roll < 0.05:
		# 5% chance for rare
		var rare_pool = library.rare_vestiges.filter(func(v): return not v in owned_vestiges)
		if not rare_pool.is_empty():
			selected = rare_pool.pick_random()
	elif roll < 0.30:
		# 25% chance for uncommon
		var uncommon_pool = library.uncommon_vestiges.filter(func(v): return not v in owned_vestiges)
		if not uncommon_pool.is_empty():
			selected = uncommon_pool.pick_random()

	# Fallback to common
	if selected == null:
		var common_pool = library.common_vestiges.filter(func(v): return not v in owned_vestiges)
		if not common_pool.is_empty():
			selected = common_pool.pick_random()

	if selected == null:
		_show_no_vestiges_available()
		return

	awarded_vestige = selected
	_display_vestige(selected)


func _display_vestige(vestige: Vestige) -> void:
	if vestige_name_label:
		vestige_name_label.text = vestige.vestige_name
	
	if vestige_description_label:
		vestige_description_label.text = vestige.description
	
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
	
	# Update party selection based on vestige scope
	_update_party_selection_visibility()


func _setup_party_selection() -> void:
	if not party_selection_container:
		return
	
	var party = GameState.get_party()
	
	# If only one party member, auto-select and hide selection
	if party.size() == 1:
		selected_party_member = party[0]
		party_selection_container.visible = false
		return
	
	# Multiple party members - show selection UI
	party_selection_container.visible = true
	
	# Clear existing buttons
	for child in party_selection_container.get_children():
		if child is Button:
			child.queue_free()
	
	# Create buttons for each party member
	for member in party:
		var button = Button.new()
		button.text = member.display_name
		button.custom_minimum_size = Vector2(100, 30)
		
		# Connect button press
		button.pressed.connect(_on_party_member_selected.bind(member))
		
		party_selection_container.add_child(button)
	
	# Select first member by default
	if party.size() > 0:
		selected_party_member = party[0]


func _update_party_selection_visibility() -> void:
	if not party_selection_container:
		return
	
	# Only show party selection for per-character vestiges
	if awarded_vestige and awarded_vestige.scope == Vestige.Scope.PER_CHARACTER:
		var party = GameState.get_party()
		if party.size() > 1:
			party_selection_container.visible = true
		else:
			party_selection_container.visible = false
	else:
		# Global vestige - hide party selection
		party_selection_container.visible = false


func _on_party_member_selected(member: AllyPartyMember) -> void:
	selected_party_member = member
	
	# Update button states to show selection
	for child in party_selection_container.get_children():
		if child is Button:
			var is_selected = (child.text == member.display_name)
			child.modulate = Color.GREEN if is_selected else Color.WHITE


func _on_take_button_pressed() -> void:
	if awarded_vestige == null:
		_show_error("No vestige to award")
		return
	
	# Award the vestige
	if awarded_vestige.scope == Vestige.Scope.GLOBAL:
		GameState.add_global_vestige(awarded_vestige, 1)
	else:
		# Award to selected party member
		if selected_party_member == null:
			var party = GameState.get_party()
			if not party.is_empty():
				selected_party_member = party[0]
		
		if selected_party_member:
			selected_party_member.add_vestige(awarded_vestige, 1)
		else:
			_show_error("No party member to award vestige to")
			return
	
	GlobalState.save()
	
	# Return to map immediately
	level_changed.emit(MAP_LEVEL_PATH)


func _on_skip_button_pressed() -> void:
	level_changed.emit(MAP_LEVEL_PATH)


func _show_error(message: String) -> void:
	if vestige_name_label:
		vestige_name_label.text = "Error"
	if vestige_description_label:
		vestige_description_label.text = message
	take_button.disabled = true


func _show_no_vestiges_available() -> void:
	if vestige_name_label:
		vestige_name_label.text = "No Vestiges"
	if vestige_description_label:
		vestige_description_label.text = "You already own all available vestiges!"
	take_button.disabled = true


func _show_success() -> void:
	if vestige_name_label:
		vestige_name_label.text = "Vestige Acquired!"
	if vestige_description_label:
		vestige_description_label.text = "You obtained " + awarded_vestige.vestige_name + "!"
