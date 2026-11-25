class_name PartyScreen
extends WindowPanel
## Party overlay: member row, 3D preview, stats, equipped/owned weapons
## (display-only for now), deck and vestiges.
##
## Opened by the pause menu (instanced per open, freed when closed). Close
## button / ui_cancel handling comes from [WindowPanel].
##
## Navigation: member tiles, deck cards and the preview are all focusable, so
## the screen works with keyboard/controller. Deck cards are wrapped in
## focusable "slots"; mouse hover simply focuses the slot, so mouse and
## keyboard share one hover path.

const PARTY_MEMBER_BUTTON_SCENE : PackedScene = preload("res://scenes/windows/party_member_button.tscn")
const WEAPON_LIST_ITEM_SCENE : PackedScene = preload("res://scenes/windows/weapon_list_item.tscn")
const CARD_BUTTON_SCENE : PackedScene = preload("res://scenes/battle/card_combat/card_components/buttons/card_button.tscn")

const DECK_COLUMNS : int = 3
## Size of one deck cell (matches CardButton's own minimum size).
const CARD_SLOT_SIZE : Vector2 = Vector2(120, 180)
## How long the hovered copy keeps playing its un-hover animation before it's freed.
const UNHOVER_DURATION : float = 0.16

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
var _focus_from_mouse : bool = false


func _ready() -> void:
	super._ready()
	_card_overlay = CanvasLayer.new()
	_card_overlay.layer = 100
	add_child(_card_overlay)
	visibility_changed.connect(_on_screen_visibility_changed)
	deck_scroll.get_v_scroll_bar().value_changed.connect(func(_v : float) -> void: _hide_hover())
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
		_focus_selected_member.call_deferred()


func _focus_selected_member() -> void:
	for button in party_members_list.get_children():
		if button is PartyMemberButton and button.member == _selected_member:
			button.grab_focus()
			return


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
		slot.focus_mode = Control.FOCUS_ALL
		# PASS so wheel scrolling still reaches the ScrollContainer.
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		deck_grid.add_child(slot)
		var card_button := CARD_BUTTON_SCENE.instantiate() as CardButton
		slot.add_child(card_button)
		card_button.setup(card)
		_make_display_only(card_button)
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_mouse_exited.bind(slot))
		slot.focus_entered.connect(_on_slot_focus_entered.bind(slot))
		slot.focus_exited.connect(_on_slot_focus_exited.bind(slot))


func _on_slot_mouse_entered(slot : Control) -> void:
	_focus_from_mouse = true
	slot.grab_focus()
	_focus_from_mouse = false


func _on_slot_mouse_exited(slot : Control) -> void:
	if slot.has_focus():
		slot.release_focus()


func _on_slot_focus_entered(slot : Control) -> void:
	if not _focus_from_mouse:
		deck_scroll.ensure_control_visible(slot)
	_show_hover(slot)


func _on_slot_focus_exited(slot : Control) -> void:
	if _hover_slot == slot:
		_hide_hover()


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
