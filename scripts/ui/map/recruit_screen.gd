class_name RecruitScreen
extends Node3D
## Recruit node: a small campsite where the party finds one ally resting by
## the fire. Recruit them (they stand up and join) or leave them be.
##
## Opened as its own scene from the run map (the same way a Combat node opens
## its battle scene): the map emits level_changed with this scene's path, the
## LevelManager swaps it in, and when the player decides we emit
## level_changed back to the map to return.
##
## Which ally is found comes from [method GameState.get_found_recruit]; the
## resting/stand-up animations come from the ally's AnimationTree (see
## [AllyDisplayModel]).

## Emitted to tell the LevelManager to load the next scene (the run map).
signal level_changed(next_level_path : String)

## Scene path of the run map hub we return to.
const MAP_LEVEL_PATH : String = "res://scenes/menus/map_menu/map_menu_3d.tscn"

## Pause after the ally is back on their feet before leaving the room.
@export var join_linger_time : float = 0.8

@onready var rest_spot : Marker3D = %RestSpot
@onready var title_label : Label = %TitleLabel
@onready var description_label : Label = %DescriptionLabel
@onready var stats_label : Label = %StatsLabel
@onready var stats_graph : StatRadarGraph = %StatsGraph
@onready var recruit_button : Button = %RecruitButton
@onready var leave_button : Button = %LeaveButton
## Bottom-right Cancel / Confirm (authored in the scene; Cancel is connected to _leave)
@onready var contextual_bar : ContextualButtonBar = $UI/UIRoot/ContextualButtons

var _template : AllyPartyMember = null
var _model : Node3D = null


func _ready() -> void:
	recruit_button.pressed.connect(_on_recruit_button_pressed)
	leave_button.pressed.connect(_leave)
	# Confirm shows while Recruit/Leave is highlighted and presses it
	contextual_bar.follow_focus(recruit_button.get_parent(), &"Confirm")
	for button : BaseButton in [recruit_button, leave_button]:
		button.mouse_entered.connect(func() -> void:
			if button.is_visible_in_tree() and not button.disabled:
				button.grab_focus())
	_template = GameState.get_found_recruit()
	if _template == null:
		_show_empty_camp()
		return
	_model = AllyDisplayModel.build(_template)
	if _model != null:
		rest_spot.add_child(_model)
		AllyDisplayModel.start_resting(_model)
	_show_encounter(_template)
	recruit_button.grab_focus.call_deferred()


func _show_encounter(template : AllyPartyMember) -> void:
	var ally_name := template.get_display_name()
	title_label.text = ally_name
	description_label.text = "%s is resting by the fire. They could join your party." % ally_name
	var stats := StatsSection.display_stats(template)
	stats_label.text = "Lv %d · %s" % [template.level, WeaponInfoSection.weapon_type_name(template.weapon_type)]
	stats_graph.set_stats(stats, StatsSection.REFERENCE_FLOORS)
	recruit_button.text = "Recruit %s" % ally_name


func _show_empty_camp() -> void:
	title_label.text = "Empty campsite"
	description_label.text = "The fire is still warm, but nobody is here."
	stats_label.visible = false
	stats_graph.visible = false
	recruit_button.visible = false
	leave_button.grab_focus.call_deferred()


func _on_recruit_button_pressed() -> void:
	contextual_bar.hide_all()
	recruit_button.disabled = true
	leave_button.disabled = true
	var ally_name := _template.get_display_name()
	if GameState.recruit_ally(_template) == null:
		push_warning("RecruitScreen: recruit_ally returned null.")
		description_label.text = "%s couldn't join right now." % ally_name
	else:
		description_label.text = "%s joins your party!" % ally_name
	var wait := AllyDisplayModel.stand_up(_model) if _model != null else 0.0
	await get_tree().create_timer(wait + join_linger_time).timeout
	_leave()


func _leave() -> void:
	level_changed.emit(MAP_LEVEL_PATH)
