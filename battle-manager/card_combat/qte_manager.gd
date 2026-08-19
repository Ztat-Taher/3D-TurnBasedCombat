class_name QTEManager
extends Node
## Manages QTE (Quick Time Event) system for card combat & reactive dodge/parry defense

signal qte_started(qte_type: String)
signal qte_completed(success: bool, qte_type: String)
signal qte_failed(qte_type: String)

# Reactive Defense Signals
signal reactive_defense_result(result_type: String) # "perfect_parry", "parry", "dodge", "none"

var qte_config: QTEConfig
var current_qte_type: String = ""
var is_qte_active: bool = false
var qte_result: bool = false

var qte_overlay_scene: PackedScene = preload("res://battle-manager/battlehud/qte_overlay.tscn")

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

# ============================================================================
# CARD ATTACK QTE
# ============================================================================

func start_card_qte(card: CardData) -> bool:
	if not qte_config or not qte_config.card_qte_enabled:
		return false
	
	var card_type = card.metadata.get("card_type", "attack")
	if card_type != "attack":
		return false  # Only attack cards get QTEs
	
	var difficulty = card.metadata.get("qte_difficulty", qte_config.default_card_qte_difficulty)
	return start_qte(QTEType.CARD_ATTACK, difficulty)

# ============================================================================
# REACTIVE DEFENSE SYSTEM (TIME-WINDOW DODGE / PARRY / PERFECT PARRY)
# ============================================================================

## Awaits reactive input from player within the defense window.
## Returns: "perfect_parry", "parry", "dodge", or "none"
func await_reactive_defense(defender: Battler) -> String:
	if not qte_config or not qte_config.reactive_defense_enabled:
		return "none"
	
	var window_duration = qte_config.reactive_window_duration
	var perfect_duration = qte_config.perfect_parry_window
	var parry_action = qte_config.parry_action
	var dodge_action = qte_config.dodge_action
	
	var hud = _get_hud()
	if hud and hud.has_method("show_parry_window"):
		hud.show_parry_window(window_duration, perfect_duration, defender.character_name if defender else "Ally")
	
	var start_time = Time.get_ticks_msec() / 1000.0
	var outcome = "none"
	
	while true:
		var current_time = Time.get_ticks_msec() / 1000.0
		var elapsed = current_time - start_time
		var time_left = window_duration - elapsed
		
		if hud and hud.has_method("update_parry_window"):
			hud.update_parry_window(max(0.0, time_left))
		
		# Check for Dodge input (E key or B button)
		var dodge_pressed = false
		if InputMap.has_action(dodge_action):
			if Input.is_action_just_pressed(dodge_action):
				dodge_pressed = true
				print("[Reactive Defense] Dodge action pressed (controller)")
		if not dodge_pressed:
			if Input.is_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_E):
				dodge_pressed = true
				print("[Reactive Defense] Dodge key pressed (keyboard)")
		
		# Check for Parry input (Q key or LB button)
		var parry_pressed = false
		if InputMap.has_action(parry_action):
			if Input.is_action_just_pressed(parry_action):
				parry_pressed = true
				print("[Reactive Defense] Parry action pressed (controller)")
		if not parry_pressed:
			if Input.is_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_Q):
				parry_pressed = true
				print("[Reactive Defense] Parry key pressed (keyboard)")
		
		print("[Reactive Defense] Input check - dodge: ", dodge_pressed, " parry: ", parry_pressed)
		
		if parry_pressed:
			if elapsed <= perfect_duration:
				outcome = "perfect_parry"
				print("[Reactive Defense] PERFECT PARRY! (elapsed: %.3fs <= %.3fs)" % [elapsed, perfect_duration])
			else:
				outcome = "parry"
				print("[Reactive Defense] Normal Parry (elapsed: %.3fs > %.3fs)" % [elapsed, perfect_duration])
			break
		
		if dodge_pressed:
			outcome = "dodge"
			print("[Reactive Defense] Dodge! (elapsed: %.3fs)" % elapsed)
			break
		
		if elapsed >= window_duration:
			outcome = "none"
			print("[Reactive Defense] Defense window expired. Missed.")
			break
		
		await get_tree().process_frame
	
	if hud and hud.has_method("hide_parry_window"):
		hud.hide_parry_window()
	
	reactive_defense_result.emit(outcome)
	return outcome

func _get_hud() -> BattleHud:
	var hud_node = get_tree().get_first_node_in_group("BattleHud")
	if hud_node is BattleHud:
		return hud_node
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm and bm.hud is BattleHud:
		return bm.hud
	return null

# ============================================================================
# GENERIC QTE ENGINE
# ============================================================================

var qte_ui_panel: Control = null

func start_qte(qte_type: QTEType, difficulty: float) -> bool:
	if is_qte_active:
		print("QTE already active, cannot start new QTE")
		return false
	
	is_qte_active = true
	current_qte_type = QTEType.keys()[qte_type]
	
	# Calculate time based on difficulty (using the same logic as before)
	var base_time = qte_config.base_qte_time if qte_config else 3.0
	var min_time = qte_config.min_qte_time if qte_config else 0.5
	var input_key = qte_config.qte_input_key if qte_config else "f"
	
	var time_multiplier = 1.0 - (difficulty * 0.8)
	var calculated_time = base_time * time_multiplier
	var time_limit = max(calculated_time, min_time)
	
	# Create the new self-contained visual UI on BattleHUD
	_create_qte_ui(input_key, time_limit)
	
	qte_started.emit(current_qte_type)
	print("QTE started: ", current_qte_type, " with difficulty: ", difficulty, " time_limit: ", time_limit)
	
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
		print("QTE Manager: Could not find valid parent for QTE overlay")
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
	print("QTE overlay completed: ", success)
	
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
		print("QTE cancelled")

func is_active() -> bool:
	return is_qte_active
