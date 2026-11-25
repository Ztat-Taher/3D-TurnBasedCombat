class_name PartyScreen
extends WindowPanel
## Party overlay: member row, 3D preview, stats, equipped/owned weapons
## (display-only for now), deck and vestiges.
##
## Opened by the pause menu (instanced per open, freed when closed). Close
## button / ui_cancel handling comes from [WindowPanel].
##
## Deck navigation doesn't use GUI focus (a mouse click anywhere can't break
## it): ui_left/right/up/down (WASD / ZQSD, d-pad, left stick) move a deck
## cursor wherever focus is, read in _input before the GUI. The arrow keys never
## navigate the deck - Left/Right rotate the preview, Up/Down do nothing here.
## Mouse hover moves the same cursor, so mouse and keys share one hover path.
##
## cycle_party_previous / cycle_party_next (Q/E, shown as A/E on AZERTY; LB/RB)
## switch members from anywhere on the screen.
##
## Deck scrolling: moving the cursor with keys/d-pad scrolls only when the focused
## row isn't fully visible, and leaves a peek of the next row in the direction
## of travel (unless it's the first/last row), tweened so it reads as motion.

const PARTY_MEMBER_BUTTON_SCENE : PackedScene = preload("res://scenes/windows/party_member_button.tscn")
const WEAPON_LIST_ITEM_SCENE : PackedScene = preload("res://scenes/windows/weapon_list_item.tscn")
const CARD_BUTTON_SCENE : PackedScene = preload("res://scenes/battle/card_combat/card_components/buttons/card_button.tscn")

const DECK_COLUMNS : int = 3
## Size of one deck cell (matches CardButton's own minimum size).
const CARD_SLOT_SIZE : Vector2 = Vector2(120, 180)
## How long the hovered copy keeps playing its un-hover animation before it's freed.
const UNHOVER_DURATION : float = 0.16
## How much of the next row stays visible when the deck scrolls to a card.
const DECK_SCROLL_PEEK : float = 48.0
const DECK_SCROLL_DURATION : float = 0.18

@onready var party_members_list : HBoxContainer = %PartyMembersList
@onready var character_preview : CharacterPreview = %CharacterPreview
@onready var stats_section : StatsSection = %StatsSection
@onready var vestiges_section : VestigesSection = %VestigesSection
@onready var weapon_info_section : WeaponInfoSection = %WeaponInfoSection
@onready var weapon_list_container : VBoxContainer = %WeaponListVBox
@onready var deck_grid : GridContainer = %DeckGrid
@onready var deck_scroll : ScrollContainer = %DeckScroll

var _party : Array[AllyPartyMember] = []
var _selected_member : AllyPartyMember = null
var _member_group := ButtonGroup.new()
## Hovered deck card is drawn as a copy on this layer so the hover scale/lift
## and description popup aren't clipped by the deck's ScrollContainer.
var _card_overlay : CanvasLayer = null
var _hover_slot : Control = null
var _hover_copy : CardButton = null
var _deck_scroll_tween : Tween = null
## Deck cursor (index into the deck slots), -1 = none
var _deck_index : int = -1
var _deck_scroll_target : float = 0.0


func _ready() -> void:
	super._ready()
	_card_overlay = CanvasLayer.new()
	_card_overlay.layer = 100
	add_child(_card_overlay)
	visibility_changed.connect(_on_screen_visibility_changed)
	# Wheel / scrollbar scrolling hides the hover; key-driven scrolling moves it along.
	deck_scroll.get_v_scroll_bar().value_changed.connect(func(_v : float) -> void:
		if not _is_deck_key_scrolling():
			_hide_hover())
	deck_grid.columns = DECK_COLUMNS

	_party = GameState.get_party()
	if _party.is_empty():
		GameState.ensure_starter_party()
		_party = GameState.get_party()
	_build_member_list()
	if not _party.is_empty():
		_select_member(_party[0])
	_on_screen_visibility_changed()


func _on_screen_visibility_changed() -> void:
	var shown := is_visible_in_tree()
	# CanvasLayers don't inherit visibility from their parent Control.
	_card_overlay.visible = shown
	if not shown:
		_hide_hover()
	else:
		_select_deck_slot.call_deferred(maxi(_deck_index, 0))


const ARROW_KEYS : Array[Key] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
const DECK_NAV := {
	&"ui_left": Vector2i(-1, 0), &"ui_right": Vector2i(1, 0),
	&"ui_up": Vector2i(0, -1), &"ui_down": Vector2i(0, 1),
}


## Deck navigation runs before the GUI so it works wherever focus is, and so the
## GUI never moves focus on this screen.
func _input(event : InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and ((event as InputEventKey).physical_keycode in ARROW_KEYS 			or (event as InputEventKey).keycode in ARROW_KEYS):
		# Arrows never navigate (Left/Right rotate the preview, which polls Input)
		get_viewport().set_input_as_handled()
		return
	for action in DECK_NAV:
		if event.is_action(action):
			get_viewport().set_input_as_handled()
			if event.is_action_pressed(action, true):
				_move_deck_cursor(DECK_NAV[action])
			return


func _unhandled_input(event : InputEvent) -> void:
	if is_visible_in_tree() and _party.size() > 1:
		var step := 0
		if event.is_action_pressed(&"cycle_party_previous"):
			step = -1
		elif event.is_action_pressed(&"cycle_party_next"):
			step = 1
		if step != 0:
			get_viewport().set_input_as_handled()
			_cycle_member(step)
			return
	super._unhandled_input(event)


## Keeps the hovered copy glued to its slot while the deck scrolls under it.
func _process(_delta : float) -> void:
	if is_instance_valid(_hover_copy) and is_instance_valid(_hover_slot):
		_hover_copy.global_position = _hover_slot.get_global_rect().position


func _cycle_member(step : int) -> void:
	var index := _party.find(_selected_member)
	var deck_index := maxi(_deck_index, 0)
	_select_member(_party[wrapi(index + step, 0, _party.size())])
	_scroll_member_into_view.call_deferred()
	# The old deck was freed; keep the cursor at the same spot in the new deck
	_select_deck_slot.call_deferred(deck_index)


func _scroll_member_into_view() -> void:
	for button in party_members_list.get_children():
		if button is PartyMemberButton and button.member == _selected_member:
			(party_members_list.get_parent() as ScrollContainer).ensure_control_visible(button)


func _deck_slots() -> Array[Control]:
	var slots : Array[Control] = []
	for child in deck_grid.get_children():
		if child.has_meta(&"deck_slot") and not child.is_queued_for_deletion():
			slots.append(child as Control)
	return slots


## Moves the deck cursor by [param step] (columns, rows). No wrapping; going
## down into a shorter last row lands on its last card.
func _move_deck_cursor(step : Vector2i) -> void:
	var slots := _deck_slots()
	if slots.is_empty():
		return
	if _deck_index < 0 or _hover_slot == null:
		# First press (or after the mouse left the deck) just shows the cursor
		_select_deck_slot(clampi(_deck_index, 0, slots.size() - 1))
		return
	var col := _deck_index % DECK_COLUMNS
	var index := _deck_index
	if step.x != 0:
		var new_col := clampi(col + step.x, 0, DECK_COLUMNS - 1)
		index = mini(_deck_index - col + new_col, slots.size() - 1)
	elif step.y > 0:
		var row_start := _deck_index - col
		if row_start + DECK_COLUMNS < slots.size():
			index = mini(_deck_index + DECK_COLUMNS, slots.size() - 1)
	elif step.y < 0:
		index = maxi(_deck_index - DECK_COLUMNS, col if _deck_index >= DECK_COLUMNS else _deck_index)
	_select_deck_slot(index)


## Puts the deck cursor on slot [param index]: scrolls it into view (keys) and
## shows its hovered copy.
func _select_deck_slot(index : int, from_mouse : bool = false) -> void:
	var slots := _deck_slots()
	if slots.is_empty():
		_deck_index = -1
		return
	_deck_index = clampi(index, 0, slots.size() - 1)
	var slot := slots[_deck_index]
	if not from_mouse:
		_scroll_deck_to(slot)
	_show_hover(slot)


# ---------------------------------------------------------------------------
# Members
# ---------------------------------------------------------------------------

func _build_member_list() -> void:
	for member in _party:
		var button := PARTY_MEMBER_BUTTON_SCENE.instantiate() as PartyMemberButton
		button.button_group = _member_group
		party_members_list.add_child(button)
		button.setup(member)
		button.member_selected.connect(_select_member)


func _select_member(member : AllyPartyMember) -> void:
	if member == _selected_member:
		return
	_selected_member = member
	for button in party_members_list.get_children():
		if button is PartyMemberButton:
			button.set_pressed_no_signal(button.member == member)
	_refresh_detail()


func _refresh_detail() -> void:
	var member := _selected_member
	if member == null:
		return
	character_preview.show_member(member)
	stats_section.setup(member, _party)
	vestiges_section.setup(member)
	weapon_info_section.setup(member)
	_build_weapon_list(member)
	_build_deck(member)


func _build_weapon_list(member : AllyPartyMember) -> void:
	_clear_container(weapon_list_container)
	if member.inventory != null:
		# The inventory also holds consumables; only weapons belong here.
		for item in member.inventory.collection:
			if item is Weapon:
				var row := WEAPON_LIST_ITEM_SCENE.instantiate() as WeaponListItem
				weapon_list_container.add_child(row)
				row.setup(item, member)
	if weapon_list_container.get_child_count() == 0:
		weapon_list_container.add_child(_make_label("No weapons"))


# ---------------------------------------------------------------------------
# Deck
# ---------------------------------------------------------------------------

func _build_deck(member : AllyPartyMember) -> void:
	_hide_hover()
	_clear_container(deck_grid)
	var deck := member.get_deck()
	if deck == null or deck.cards.is_empty():
		deck_grid.add_child(_make_label("No deck"))
		return
	for card in deck.cards:
		var slot := Control.new()
		slot.custom_minimum_size = CARD_SLOT_SIZE
		slot.focus_mode = Control.FOCUS_NONE
		slot.set_meta(&"deck_slot", true)
		# PASS so wheel scrolling still reaches the ScrollContainer.
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		deck_grid.add_child(slot)
		var card_button := CARD_BUTTON_SCENE.instantiate() as CardButton
		slot.add_child(card_button)
		card_button.setup(card)
		_make_display_only(card_button)
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_mouse_exited.bind(slot))



func _on_slot_mouse_entered(slot : Control) -> void:
	_select_deck_slot(_deck_slots().find(slot), true)


## The cursor stays on the card; only the hover visual goes away
func _on_slot_mouse_exited(slot : Control) -> void:
	if _hover_slot == slot:
		_hide_hover()


func _is_deck_key_scrolling() -> bool:
	return _deck_scroll_tween != null and _deck_scroll_tween.is_running()


## Scrolls the deck just enough to show [param slot]'s whole row (+ its hover
## lift), plus a peek of the row beyond it. No scroll if it's already in view.
func _scroll_deck_to(slot : Control) -> void:
	var view_height := deck_scroll.size.y
	var row_top := slot.position.y
	var row_bottom := row_top + slot.size.y
	var content_height := deck_grid.size.y
	var current := float(deck_scroll.scroll_vertical)
	if _is_deck_key_scrolling():
		current = _deck_scroll_target
	var target := current
	var is_first_row := row_top <= 0.5
	var is_last_row := row_bottom >= content_height - 0.5
	if row_top < current:
		# Going up: row at the top, previous row peeking above it
		target = row_top - (0.0 if is_first_row else DECK_SCROLL_PEEK)
	elif row_bottom > current + view_height:
		# Going down: row at the bottom, next row peeking below it
		target = row_bottom - view_height + (0.0 if is_last_row else DECK_SCROLL_PEEK)
	var max_scroll := maxf(0.0, content_height - view_height)
	target = clampf(target, 0.0, max_scroll)
	if is_equal_approx(target, current):
		return
	_deck_scroll_target = target
	if _deck_scroll_tween:
		_deck_scroll_tween.kill()
	_deck_scroll_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_deck_scroll_tween.tween_property(deck_scroll, "scroll_vertical", int(target), DECK_SCROLL_DURATION) 		.from(int(deck_scroll.scroll_vertical))


## Draws a hovered copy of [param slot]'s card on the overlay; the original
## stays in the grid (transparent) so the layout never changes.
func _show_hover(slot : Control) -> void:
	if _hover_slot == slot or not is_instance_valid(slot) or slot.get_child_count() == 0:
		return
	_hide_hover()
	var original := slot.get_child(0) as CardButton
	if original == null or original.card_config == null:
		return
	var copy := CARD_BUTTON_SCENE.instantiate() as CardButton
	_card_overlay.add_child(copy)
	copy.setup(original.card_config)
	_make_display_only(copy)
	copy.set_anchors_preset(Control.PRESET_TOP_LEFT)
	copy.global_position = slot.get_global_rect().position
	copy.size = slot.size
	copy.set_controller_hover(true)
	original.modulate.a = 0.0
	_hover_slot = slot
	_hover_copy = copy


func _hide_hover() -> void:
	# Weak ref: the slot may be freed (deck rebuilt) before the callback runs.
	var slot_ref : WeakRef = weakref(_hover_slot)
	var copy := _hover_copy
	_hover_slot = null
	_hover_copy = null
	if not is_instance_valid(copy):
		return
	copy.set_controller_hover(false)
	var tween := copy.create_tween()
	tween.tween_interval(UNHOVER_DURATION)
	tween.tween_callback(func() -> void:
		# Only reveal the grid card if it wasn't re-hovered meanwhile.
		var slot := slot_ref.get_ref() as Control
		if slot != null and _hover_slot != slot and slot.get_child_count() > 0:
			(slot.get_child(0) as CanvasItem).modulate.a = 1.0
		copy.queue_free())


## Display-only cards: nothing inside may take mouse input (no dragging, and
## the slot underneath keeps receiving hover/scroll events).
func _make_display_only(card : CardButton) -> void:
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for node in card.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _clear_container(container : Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _make_label(text : String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"PartyBodyLabel"
	label.text = text
	return label
