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

# Public property to access the last QTE result
var last_qte_result: bool = false:
	get:
		return qte_result

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

func start_card_qte(card: CardData) -> bool:
	if not qte_config or not qte_config.card_qte_enabled:
		return false
	
	# Check CardConfig for QTE settings (primary system)
	if card.has_card_config():
		if not card.card_config.should_trigger_qte():
			return false
		var card_cfg_diff = card.card_config.qte_difficulty
		return start_qte(QTEType.CARD_ATTACK, card_cfg_diff)
	
	# Fallback to metadata for legacy cards
	var card_type = card.metadata.get("card_type", "attack")
	if card_type != "attack":
		return false  # Only attack cards get QTEs
	
	var metadata_diff = card.metadata.get("qte_difficulty", qte_config.default_card_qte_difficulty)
	return start_qte(QTEType.CARD_ATTACK, metadata_diff)

# ============================================================================
# GENERIC QTE ENGINE
# ============================================================================

var qte_ui_panel: Control = null

func start_qte(qte_type: QTEType, difficulty: float, custom_time_limit: float = 0.0) -> bool:
	if is_qte_active:
		return false
	
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

func cancel_qte() -> void:
	if is_qte_active:
		_remove_qte_ui()
		is_qte_active = false

func is_active() -> bool:
	return is_qte_active
