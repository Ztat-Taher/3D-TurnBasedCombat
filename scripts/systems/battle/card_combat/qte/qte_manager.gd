class_name QTEManager
extends Node
## Manages QTE (Quick Time Event) system for card combat attack boosting
## QTEs are purely for enhancing player attacks (damage/effects), no defensive mechanics

signal qte_started(qte_type: String)
signal qte_completed(success: bool, qte_type: String)
signal qte_failed(qte_type: String)

var qte_config: QTEConfig
var current_qte_type: String = ""
var is_qte_active: bool = false
var qte_result: bool = false

var qte_overlay_scene: PackedScene = preload("res://scenes/battle/hud/qte_system/overlay/qte_overlay.tscn")

# QTE types
enum QTEType {
	NONE,
	CARD_ATTACK		# QTE when playing attack cards for damage boosting
}

func _ready():
	qte_config = load_qte_config()

func load_qte_config() -> QTEConfig:
	var config_path = "res://database/qte_config.tres"
	if ResourceLoader.exists(config_path):
		return load(config_path)
	
	# Create default config
	var default_config = QTEConfig.new()
	return default_config

# ============================================================================
# CARD ATTACK QTE
# ============================================================================

## Whether card QTEs are on at all ([member QTEConfig.card_qte_enabled]).
func is_enabled() -> bool:
	return qte_config == null or qte_config.card_qte_enabled


## Whether playing [param card] runs a QTE: card QTEs are enabled and the
## card's qte_type isn't NONE. (Multi-strike cards set a QTE per strike
## instead, through strike_qte_windows.)
func wants_card_qte(card: CardConfig) -> bool:
	return card != null and is_enabled() and card.should_trigger_qte()


## Starts [param card]'s QTE (when [method wants_card_qte]), lasting
## [param window] seconds (the card's qte_window_duration when 0). Returns
## whether one started.
func start_card_qte(card: CardConfig, window: float = 0.0) -> bool:
	if not wants_card_qte(card):
		return false
	if card.qte_type in [CardConfig.QTEType.BUTTON_MASH, CardConfig.QTEType.SEQUENCE]:
		push_warning("%s: %s QTEs aren't implemented yet, playing a timing QTE" % [card.card_name, CardConfig.QTEType.keys()[card.qte_type]])
	return start_qte(QTEType.CARD_ATTACK, card.qte_difficulty, window if window > 0.0 else card.qte_window_duration)

# ============================================================================
# GENERIC QTE ENGINE
# ============================================================================

var qte_ui_panel: Control = null

## Starts a QTE. A QTE still running (one whose hit never came to resolve it)
## is dropped first, and the previous result is cleared: an outcome only ever
## belongs to the QTE that produced it. [param difficulty] sets the duration
## only when no [param custom_time_limit] is given.
func start_qte(qte_type: QTEType, difficulty: float, custom_time_limit: float = 0.0) -> bool:
	if is_qte_active:
		cancel_qte()
	qte_result = false
	is_qte_active = true
	current_qte_type = QTEType.keys()[qte_type]
	
	# Use custom time limit if provided, otherwise calculate from difficulty
	var time_limit: float
	if custom_time_limit > 0.0:
		time_limit = custom_time_limit
	else:
		# Calculate time based on difficulty (using the same logic as before)
		var base_time = qte_config.base_qte_time if qte_config else 3.0
		var min_time = qte_config.min_qte_time if qte_config else 0.5
		var time_multiplier = 1.0 - (difficulty * 0.8)
		var calculated_time = base_time * time_multiplier
		time_limit = max(calculated_time, min_time)
	
	var input_key = qte_config.qte_input_key if qte_config else "f"
	
	# Create the new self-contained visual UI on BattleHUD
	_create_qte_ui(input_key, time_limit)
	
	qte_started.emit(current_qte_type)
	
	return true



func _create_qte_ui(input_key: String, time_limit: float) -> void:
	_remove_qte_ui()
	
	if not qte_overlay_scene:
		push_error("QTE overlay scene not loaded!")
		return
	
	var target_parent: Control = null
	var hud_node = get_tree().get_first_node_in_group("BattleHud")
	if hud_node:
		target_parent = hud_node.get_node_or_null("Control/QTEContainer")
		if not target_parent:
			target_parent = hud_node.get_node_or_null("Control")
	if not target_parent:
		var bm = get_tree().get_first_node_in_group("battle_manager")
		if bm and bm.hud:
			target_parent = bm.hud.get_node_or_null("Control/QTEContainer")
			if not target_parent:
				target_parent = bm.hud.get_node_or_null("Control")
	
	if not target_parent:
		return
	
	qte_ui_panel = qte_overlay_scene.instantiate()
	if not qte_ui_panel:
		push_error("Failed to instantiate QTE overlay!")
		return
	
	# Connect to the new QTE overlay's completion signal
	if qte_ui_panel.has_signal("qte_completed"):
		qte_ui_panel.qte_completed.connect(_on_qte_overlay_completed)
	
	# Setup the QTE overlay with the input key and time limit
	if qte_ui_panel.has_method("setup"):
		qte_ui_panel.setup(input_key, time_limit)
	else:
		push_error("QTE overlay instance does not have setup method!")
		return
	
	target_parent.add_child(qte_ui_panel)



func _remove_qte_ui() -> void:
	if qte_ui_panel and is_instance_valid(qte_ui_panel):
		if qte_ui_panel.has_signal("qte_completed"):
			if qte_ui_panel.qte_completed.is_connected(_on_qte_overlay_completed):
				qte_ui_panel.qte_completed.disconnect(_on_qte_overlay_completed)
		qte_ui_panel.queue_free()
		qte_ui_panel = null

func _on_qte_overlay_completed(success: bool) -> void:
	# Handle completion from the new self-contained QTE overlay
	
	# Emit the appropriate signals
	if success:
		qte_result = true
		qte_completed.emit(true, current_qte_type)
	else:
		qte_result = false
		qte_failed.emit(current_qte_type)
		qte_completed.emit(false, current_qte_type)
	
	is_qte_active = false
	# Note: UI cleanup is handled by the overlay itself (queue_free)

func get_damage_multiplier(qte_type: String, success: bool) -> float:
	if not qte_config:
		return 1.0
	
	match qte_type:
		"CARD_ATTACK":
			if success:
				return qte_config.card_qte_success_multiplier
			else:
				return qte_config.card_qte_failure_multiplier
		_:
			return 1.0

## Multiplier a QTE result gives [param card]: the card's own success /
## failure multiplier when it sets one (above 0), else the QTE config's.
func get_card_multiplier(card: CardConfig, success: bool) -> float:
	var own := 0.0
	if card:
		own = card.qte_success_multiplier if success else card.qte_failure_multiplier
	return own if own > 0.0 else get_damage_multiplier("CARD_ATTACK", success)

func cancel_qte() -> void:
	if is_qte_active:
		_remove_qte_ui()
		is_qte_active = false
		qte_result = false


## Ends the current QTE and returns whether it succeeded. Call it when the
## outcome is needed (the hit): a QTE still running had no press in time, so
## it fails. The result is consumed, so it can't carry over to a later hit.
func resolve_qte() -> bool:
	if is_qte_active:
		cancel_qte()
	var success := qte_result
	qte_result = false
	return success

func is_active() -> bool:
	return is_qte_active
