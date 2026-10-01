extends Control
## Card-pick reward screen shown after a won level, before returning to the run
## map. Each party member is offered 3 random cards; picking one adds it to that
## member's deck. The LevelManager instantiates this after a won level and
## connects 'continue_pressed' / 'main_menu_pressed' (see
## level_and_state_manager.gd). Hiding the screen frees it (the manager listens
## to the built-in 'hidden' signal).
##
## Static layout lives in level_complete_screen.tscn; the member rows and card
## options are instanced at runtime from card_pick_member.tscn /
## card_pick_option.tscn (node-based scenes, not code-built UI).

signal continue_pressed
signal main_menu_pressed

## Folder scanned (recursively) for the reward card pool.
const CARD_POOL_DIR : String = "res://database/cards"
## Cards offered to each party member.
const OPTIONS_PER_MEMBER : int = 3
const CARD_BUTTON_SCENE : PackedScene = preload("res://scenes/battle/card_combat/card_components/buttons/card_button.tscn")

## Party members that have already picked a card (by member id).
var _picked_member_ids : Array[String] = []
var _selected_buttons : Dictionary = {}
var _hovered_button : CardButton = null
var _total_members : int = 0
var _active_card_buttons : Array[CardButton] = []

@onready var members_container : VBoxContainer = %MembersContainer
@onready var continue_button : Button = %ContinueButton


func _ready() -> void:
	continue_button.disabled = true
	_build_card_choices()
	continue_button.grab_focus()

func _process(_delta: float) -> void:
	if not visible or _active_card_buttons.is_empty():
		_set_hovered_button(null)
		return
	if _is_any_card_dragging():
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var current := _hovered_button
	if is_instance_valid(current) and not current.is_returning and current.is_point_over_visual(mouse_pos):
		return
	var candidate: CardButton = null
	for i in range(_active_card_buttons.size() - 1, -1, -1):
		var button := _active_card_buttons[i]
		if is_instance_valid(button) and not button.is_dragging and not button.is_returning and button.is_point_over_visual(mouse_pos):
			candidate = button
			break
	_set_hovered_button(candidate)

func _is_any_card_dragging() -> bool:
	for button in _active_card_buttons:
		if is_instance_valid(button) and button.is_dragging:
			return true
	return false

func _set_hovered_button(button: CardButton) -> void:
	if _hovered_button == button:
		return
	if is_instance_valid(_hovered_button) and _hovered_button.is_hovered:
		_hovered_button.set_controller_hover(false)
	_hovered_button = button
	if button:
		button.set_controller_hover(true)


## Recursively load every CardData .tres under CARD_POOL_DIR.
func _load_card_pool() -> Array[CardData]:
	var pool : Array[CardData] = []
	_collect_cards(CARD_POOL_DIR, pool)
	return pool


func _collect_cards(dir_path : String, out : Array[CardData]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.get_extension() != "tres":
			continue
		var card := load(dir_path.path_join(file_name)) as CardData
		if card != null:
			out.append(card)
	for sub_dir in dir.get_directories():
		_collect_cards(dir_path.path_join(sub_dir), out)


func _build_card_choices() -> void:
	var party := GameState.get_party()
	if party.is_empty():
		GameState.ensure_starter_party()
		party = GameState.get_party()
	_total_members = party.size()
	var pool := _load_card_pool()
	if _total_members == 0 or pool.is_empty():
		# Nothing to pick: let the player continue straight away.
		continue_button.disabled = false
		return
	for member in party:
		var member_box := VBoxContainer.new()
		member_box.name = "Member_" + member.id
		member_box.alignment = BoxContainer.ALIGNMENT_CENTER
		member_box.add_theme_constant_override("separation", 8)
		members_container.add_child(member_box)

		var name_label := Label.new()
		name_label.text = (member.display_name if not member.display_name.is_empty() else member.id).to_upper()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		member_box.add_child(name_label)

		var options := HBoxContainer.new()
		options.name = "Options"
		options.alignment = BoxContainer.ALIGNMENT_CENTER
		options.add_theme_constant_override("separation", 24)
		member_box.add_child(options)

		for card in _pick_choices(pool, member):
			var card_button := CARD_BUTTON_SCENE.instantiate() as CardButton
			options.add_child(card_button)
			card_button.setup(card)
			card_button.card_drag_ended.connect(_on_card_drag_ended.bind(member, card_button))
			_active_card_buttons.append(card_button)


## Choose up to OPTIONS_PER_MEMBER distinct cards from the pool, skipping cards
## already in the member's deck (falling back to duplicates if the deck has them
## all).
func _pick_choices(pool : Array[CardData], member : AllyPartyMember) -> Array[CardData]:
	var shuffled := pool.duplicate()
	shuffled.shuffle()
	var deck := member.get_deck()
	var choices : Array[CardData] = []
	for card in shuffled:
		if choices.size() >= OPTIONS_PER_MEMBER:
			break
		if deck != null and _deck_has_card_id(deck, card.card_id):
			continue
		choices.append(card)
	if choices.is_empty():
		# Every pool card is already in the deck: offer the first few anyway.
		choices.assign(shuffled.slice(0, OPTIONS_PER_MEMBER))
	return choices


func _deck_has_card_id(deck : DeckResource, card_id : String) -> bool:
	if card_id.is_empty():
		return false
	for existing in deck.cards:
		if existing != null and existing.card_id == card_id:
			return true
	return false


func _on_card_drag_ended(_card_button : CardButton, _dropped_in_play_zone : bool, member : AllyPartyMember, chosen_button : CardButton) -> void:
	if member.id in _picked_member_ids or not is_instance_valid(chosen_button):
		return
	var previous := _selected_buttons.get(member.id) as CardButton
	if is_instance_valid(previous):
		previous.set_highlighted(false)
		previous.modulate = Color.WHITE
	chosen_button.set_highlighted(true)
	_selected_buttons[member.id] = chosen_button
	continue_button.disabled = _selected_buttons.size() < _total_members


func _on_continue_button_pressed() -> void:
	if _selected_buttons.size() < _total_members:
		return
	for member in GameState.get_party():
		var chosen_button := _selected_buttons.get(member.id) as CardButton
		if not is_instance_valid(chosen_button) or chosen_button.card_data == null:
			return
		var deck := member.get_deck()
		if deck != null:
			deck.add_card(chosen_button.card_data)
		_picked_member_ids.append(member.id)
		chosen_button.set_highlighted(false)
		chosen_button.modulate = Color(0.72, 1.0, 0.78, 1.0)
		chosen_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var face: Control = chosen_button.get_node_or_null("Card3DContainer")
		if face:
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GlobalState.save()
	continue_pressed.emit()
	hide()


func _on_main_menu_button_pressed() -> void:
	main_menu_pressed.emit()
	hide()


func _on_exit_button_pressed() -> void:
	get_tree().quit()
