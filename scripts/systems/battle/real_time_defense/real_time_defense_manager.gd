class_name RealTimeDefenseManager
extends Node

signal defense_result(defender: Battler, result_type: String)
signal defense_input_buffered(action: String)
signal counterattack_triggered(defender: Battler, attacker: Battler)

var parry_action: String = "parry"
var dodge_action: String = "dodge"
var jump_action: String  = "jump"

var commit_duration: float = 0.6
var late_forgiveness_window: float = 0.15
var evade_window: float = 0.25

var _buffer_active: bool = false
var _last_defense_action: String = "none"
var _last_press_time: float = -1.0
var _attack_start_time: float = 0.0
var _current_attacker: Battler = null
var _current_defender: Battler = null
var _current_attack_config: EnemyAttackConfig = null

func _ready() -> void:
	add_to_group("real_time_defense_manager")
	set_process_input(true)

func open_buffer(attacker: Battler, defender: Battler, config: EnemyAttackConfig = null) -> void:
	if not defender or defender.is_defeated():
		return
	_current_attacker = attacker
	_current_defender = defender
	_current_attack_config = config
	_last_defense_action = "none"
	_last_press_time = -1.0
	_attack_start_time = Time.get_ticks_msec() / 1000.0
	_buffer_active = true

func lock_and_evaluate(actual_hit_time: float) -> String:
	_buffer_active = false
	
	if not _current_defender or _current_defender.is_defeated():
		return "none"

	if _last_defense_action == "none" or _last_press_time < 0:
		defense_result.emit(_current_defender, "none")
		return "none"

	var time_before_hit = actual_hit_time - _last_press_time

	var allowed: Dictionary = {}
	if _current_attack_config:
		allowed = _current_attack_config.get_allowed_defenses()
	else:
		allowed = {"jump": false, "dodge": true, "parry": true}

	var action = _last_defense_action

	if action == "parry" and allowed.get("parry", true):
		var perfect_window: float = 0.15
		if _current_attack_config:
			perfect_window = _current_attack_config.pre_hit_parry_window
		
		# For Parry, there is ONLY perfect parry now.
		if time_before_hit <= perfect_window and time_before_hit >= -late_forgiveness_window:
			defense_result.emit(_current_defender, "perfect_parry")
			return "perfect_parry"

	elif action == "dodge" and allowed.get("dodge", true):
		if time_before_hit <= evade_window and time_before_hit >= -late_forgiveness_window:
			defense_result.emit(_current_defender, "dodge")
			return "dodge"

	elif action == "jump" and allowed.get("jump", false):
		if time_before_hit <= evade_window and time_before_hit >= -late_forgiveness_window:
			defense_result.emit(_current_defender, "jump")
			return "jump"

	# Missed the window (pressed too early or too late)
	defense_result.emit(_current_defender, "none")
	return "none"

func close_buffer() -> void:
	_buffer_active = false
	_current_attacker = null
	_current_defender = null
	_current_attack_config = null
	_last_defense_action = "none"

func cancel_defense_window() -> void:
	close_buffer()

func _input(event: InputEvent) -> void:
	if not _buffer_active or not _current_defender:
		return

	var current_time = Time.get_ticks_msec() / 1000.0

	# Prevent spamming while locked in animation
	if _last_press_time > 0 and (current_time - _last_press_time) < commit_duration:
		return

	var action := ""
	if event.is_action_pressed(parry_action):
		action = "parry"
	elif event.is_action_pressed(dodge_action):
		action = "dodge"
	elif event.is_action_pressed(jump_action):
		action = "jump"

	if action.is_empty():
		return

	_last_defense_action = action
	_last_press_time = current_time
	defense_input_buffered.emit(action)

	match action:
		"dodge":
			if _current_defender.has_method("perform_dodge_dash"):
				_current_defender.perform_dodge_dash()
		"jump":
			if _current_defender.has_method("perform_jump_evade"):
				_current_defender.perform_jump_evade()
		"parry":
			if _current_defender.has_method("_try_animation"):
				_current_defender._try_animation("parry")

func execute_perfect_parry_counter(defender: Battler, attacker: Battler) -> void:
	if not is_instance_valid(defender) or not is_instance_valid(attacker):
		return

	attacker.is_counter_stunned = true
	defender._try_animation("melee_combo_1")
	await defender.hit_moment

	var multiplier := 1.5
	var base_counter_dmg := int(defender.attack * multiplier)
	var final_counter_dmg := Formulas.physical_damage(defender, attacker, max(1, base_counter_dmg))
	await attacker.take_damage(final_counter_dmg, defender)

	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.hud:
		battle_manager.hud.update_health_bars()

	if attacker.has_method("return_to_original_position") and attacker.original_position != Vector3.ZERO:
		attacker.return_to_original_position()
		while attacker.is_advancing:
			await get_tree().create_timer(0.1).timeout
		attacker.battle_idle()

	attacker._counter_handled_return = true

	if attacker.is_defeated():
		if battle_manager:
			battle_manager._cleanup_defeated_from_turn_order()
			battle_manager.cleanup_defeated_enemies()

	counterattack_triggered.emit(defender, attacker)
