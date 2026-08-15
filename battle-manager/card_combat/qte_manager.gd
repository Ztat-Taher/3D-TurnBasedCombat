class_name QTEManager
extends Node
## Manages QTE (Quick Time Event) system for card combat
## Handles QTE triggering for card execution and reactive dodge/parry

signal qte_started(qte_type: String)
signal qte_completed(success: bool, qte_type: String)
signal qte_failed(qte_type: String)

var qte_config: QTEConfig
var current_qte: QTE
var current_qte_type: String = ""
var is_qte_active: bool = false
var qte_result: bool = false

# Public property to access the last QTE result
var last_qte_result: bool = false:
	get:
		return qte_result

# QTE types
enum QTEType {
	NONE,
	CARD_ATTACK,		# QTE when playing attack cards
	REACTIVE_DODGE,		# QTE when player is attacked (dodge opportunity)
	REACTIVE_PARRY		# QTE when player is attacked (parry opportunity)
}

func _ready():
	qte_config = load_qte_config()

func load_qte_config() -> QTEConfig:
	var config_path = "res://battle-manager/card_combat/qte_config.tres"
	if ResourceLoader.exists(config_path):
		return load(config_path)
	
	# Create default config
	var default_config = QTEConfig.new()
	return default_config

func start_card_qte(card: CardData) -> bool:
	if not qte_config or not qte_config.card_qte_enabled:
		return false
	
	var card_type = card.metadata.get("card_type", "attack")
	if card_type != "attack":
		return false  # Only attack cards get QTEs
	
	# Get QTE difficulty from card metadata or use default
	var difficulty = card.metadata.get("qte_difficulty", qte_config.default_card_qte_difficulty)
	
	return start_qte(QTEType.CARD_ATTACK, difficulty)

func start_reactive_dodge() -> bool:
	if not qte_config or not qte_config.reactive_defense_enabled:
		return false
	
	return start_qte(QTEType.REACTIVE_DODGE, qte_config.dodge_qte_difficulty)

func start_reactive_parry() -> bool:
	if not qte_config or not qte_config.reactive_defense_enabled:
		return false
	
	return start_qte(QTEType.REACTIVE_PARRY, qte_config.parry_qte_difficulty)

var qte_ui_panel: Panel = null
var qte_progress_bar: ProgressBar = null
var qte_key_label: Label = null
var qte_title_label: Label = null

func start_qte(qte_type: QTEType, difficulty: float) -> bool:
	if is_qte_active:
		print("QTE already active, cannot start new QTE")
		return false
	
	is_qte_active = true
	current_qte_type = QTEType.keys()[qte_type]
	
	# Create appropriate QTE based on type
	match qte_type:
		QTEType.CARD_ATTACK:
			current_qte = create_countdown_qte(difficulty)
		QTEType.REACTIVE_DODGE:
			current_qte = create_countdown_qte(difficulty)
		QTEType.REACTIVE_PARRY:
			current_qte = create_countdown_qte(difficulty)
		_:
			current_qte = create_countdown_qte(difficulty)
	
	if not current_qte:
		is_qte_active = false
		return false
	
	# Connect signals
	current_qte.success.connect(_on_qte_success)
	current_qte.failed.connect(_on_qte_failed)
	
	# Add to scene and start
	add_child(current_qte)
	current_qte.start_qte()
	
	# Create visual UI on BattleHUD
	_create_qte_ui(current_qte.input, current_qte.time_left)
	
	qte_started.emit(current_qte_type)
	print("QTE started: ", current_qte_type, " with difficulty: ", difficulty)
	
	return true

func create_countdown_qte(difficulty: float) -> CountdownQTE:
	var qte = CountdownQTE.new()
	
	# Use config values if available
	var base_time = qte_config.base_qte_time if qte_config else 3.0
	var min_time = qte_config.min_qte_time if qte_config else 0.5
	var input_key = qte_config.qte_input_key if qte_config else "f"
	
	# Adjust time based on difficulty (higher difficulty = less time)
	var time_multiplier = 1.0 - (difficulty * 0.8)  # 0.2 to 1.0 multiplier
	var calculated_time = base_time * time_multiplier
	qte.time_left = max(calculated_time, min_time)
	
	# Set input key
	qte.input = input_key
	
	return qte

func _create_qte_ui(input_key: String, time_limit: float) -> void:
	_remove_qte_ui()
	
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
	
	qte_ui_panel = Panel.new()
	qte_ui_panel.name = "QTEOverlay"
	qte_ui_panel.anchors_preset = Control.PRESET_FULL_RECT
	qte_ui_panel.anchor_left = 0.0
	qte_ui_panel.anchor_top = 0.0
	qte_ui_panel.anchor_right = 1.0
	qte_ui_panel.anchor_bottom = 1.0
	qte_ui_panel.offset_left = 0
	qte_ui_panel.offset_top = 0
	qte_ui_panel.offset_right = 0
	qte_ui_panel.offset_bottom = 0
	qte_ui_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	qte_ui_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.9, 0.7, 0.2, 1.0)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	qte_ui_panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	qte_ui_panel.add_child(vbox)
	
	qte_title_label = Label.new()
	qte_title_label.text = "QUICK TIME EVENT!"
	qte_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qte_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(qte_title_label)
	
	qte_key_label = Label.new()
	qte_key_label.text = "[ " + input_key.to_upper() + " ]"
	qte_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qte_key_label.add_theme_font_size_override("font_size", 28)
	qte_key_label.add_theme_color_override("font_color", Color(1, 1, 1))
	vbox.add_child(qte_key_label)
	
	qte_progress_bar = ProgressBar.new()
	qte_progress_bar.custom_minimum_size = Vector2(0, 20)
	qte_progress_bar.max_value = time_limit
	qte_progress_bar.value = time_limit
	qte_progress_bar.show_percentage = false
	vbox.add_child(qte_progress_bar)
	
	target_parent.add_child(qte_ui_panel)

func _process(_delta: float) -> void:
	if is_qte_active and current_qte and is_instance_valid(current_qte):
		if qte_progress_bar and is_instance_valid(qte_progress_bar):
			if current_qte.timer and is_instance_valid(current_qte.timer):
				qte_progress_bar.value = current_qte.timer.time_left

func _remove_qte_ui() -> void:
	if qte_ui_panel and is_instance_valid(qte_ui_panel):
		qte_ui_panel.queue_free()
		qte_ui_panel = null
		qte_progress_bar = null
		qte_key_label = null
		qte_title_label = null

func _on_qte_success() -> void:
	print("QTE success: ", current_qte_type)
	is_qte_active = false
	qte_result = true
	qte_completed.emit(true, current_qte_type)
	_remove_qte_ui()
	
	if current_qte:
		current_qte.queue_free()
		current_qte = null

func _on_qte_failed() -> void:
	print("QTE failed: ", current_qte_type)
	is_qte_active = false
	qte_result = false
	qte_failed.emit(current_qte_type)
	qte_completed.emit(false, current_qte_type)
	_remove_qte_ui()
	
	if current_qte:
		current_qte.queue_free()
		current_qte = null

func get_damage_multiplier(qte_type: String, success: bool) -> float:
	if not qte_config:
		return 1.0
	
	match qte_type:
		"CARD_ATTACK":
			if success:
				return qte_config.card_qte_success_multiplier
			else:
				return qte_config.card_qte_failure_multiplier
		"REACTIVE_DODGE":
			if success:
				return 1.0 - qte_config.dodge_damage_reduction  # Damage reduction
			else:
				return 1.0
		"REACTIVE_PARRY":
			if success:
				return 1.0 - qte_config.parry_damage_reduction  # Damage reduction
			else:
				return 1.0
		_:
			return 1.0

func cancel_qte() -> void:
	if is_qte_active and current_qte:
		current_qte.queue_free()
		current_qte = null
		is_qte_active = false
		print("QTE cancelled")

func is_active() -> bool:
	return is_qte_active
