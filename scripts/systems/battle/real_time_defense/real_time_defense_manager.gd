class_name RealTimeDefenseManager
extends Node
## Manages real-time defense detection tied to attacker animations
## Defense input (dodge/parry/jump) is checked against attacker's hit frame timing
## No visual timing cues - players learn attack patterns visually

signal defense_result(defender: Battler, result_type: String) # "perfect_parry", "parry", "dodge", "jump", "none"
signal counterattack_triggered(defender: Battler, attacker: Battler)

enum DefenseType {
	NONE,
	DODGE,
	PARRY,
	JUMP
}

var defense_window_duration: float = 0.15  # Tight window around hit frame (seconds)
var perfect_parry_window: float = 0.05     # Even tighter window for perfect parry
var parry_action: String = "parry"
var dodge_action: String = "dodge"
var jump_action: String = "jump"

var _active_defense_window: bool = false
var _current_attacker: Battler = null
var _current_defender: Battler = null
var _attack_config: EnemyAttackConfig = null
var _window_start_time: float = 0.0
var _defense_detected: bool = false
var _current_result: String = "none"

func _ready():
	add_to_group("real_time_defense_manager")

## Starts monitoring for defense input around an attacker's hit frame
## Called when attacker's animation reaches hit moment
## Returns: "perfect_parry", "parry", "dodge", "jump", or "none"
func start_defense_window(attacker: Battler, defender: Battler, attack_config: EnemyAttackConfig = null) -> String:
	if not defender or defender.is_defeated():
		return "none"
	
	_current_attacker = attacker
	_current_defender = defender
	_attack_config = attack_config
	
	# Extended defense window - lasts throughout attack animation
	# Player can commit to wrong defenses as punishment
	var extended_window_duration = 1.0  # Extended window for entire attack
	
	_active_defense_window = true
	_defense_detected = false
	_window_start_time = Time.get_ticks_msec() / 1000.0
	
	# Monitor defense input for extended duration
	var window_timer = get_tree().create_timer(extended_window_duration)
	window_timer.timeout.connect(_on_defense_window_timeout)
	
	# Monitor input each frame - accept any defense input regardless of attack type
	while _active_defense_window and not _defense_detected:
		await get_tree().process_frame
		_check_defense_input({}, perfect_parry_window)
	
	# Return the detected result (or "none" if timeout)
	return _get_current_result()

func _check_defense_input(allowed: Dictionary, perfect_duration: float) -> void:
	if not _active_defense_window or _defense_detected:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var elapsed = current_time - _window_start_time
	
	# Check for Jump input (Space or jump action) - always allowed (unrestricted)
	var jump_pressed = false
	if InputMap.has_action(jump_action):
		if Input.is_action_just_pressed(jump_action):
			jump_pressed = true
	if not jump_pressed:
		if Input.is_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SPACE):
			jump_pressed = true
	
	# Check for Dodge input (E key or dodge action) - always allowed (unrestricted)
	var dodge_pressed = false
	if InputMap.has_action(dodge_action):
		if Input.is_action_just_pressed(dodge_action):
			dodge_pressed = true
	if not dodge_pressed:
		if Input.is_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_E):
			dodge_pressed = true
	
	# Check for Parry input (Q key or parry action) - always allowed (unrestricted)
	var parry_pressed = false
	if InputMap.has_action(parry_action):
		if Input.is_action_just_pressed(parry_action):
			parry_pressed = true
	if not parry_pressed:
		if Input.is_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_Q):
			parry_pressed = true
	
	# Resolve outcome - player commits to whatever they press (punishment system)
	if jump_pressed:
		_defense_detected = true
		_active_defense_window = false
		_trigger_defense("jump")
	elif parry_pressed:
		_defense_detected = true
		_active_defense_window = false
		# Check if within perfect parry window (first 0.05s)
		if elapsed <= perfect_parry_window:
			_trigger_defense("perfect_parry")
		else:
			_trigger_defense("parry")
	elif dodge_pressed:
		_defense_detected = true
		_active_defense_window = false
		_trigger_defense("dodge")

func _trigger_defense(result_type: String) -> void:
	if not _current_defender:
		return
	
	_current_result = result_type
	
	print("[RealTimeDefense] Triggering defense: %s for defender: %s" % [result_type, _current_defender.character_name])
	
	# Play defense animation based on result
	match result_type:
		"dodge":
			if _current_defender.has_method("perform_dodge_dash"):
				_current_defender.perform_dodge_dash()
		"jump":
			if _current_defender.has_method("perform_jump_evade"):
				_current_defender.perform_jump_evade()
		"parry":
			# Always play parry animation using state machine
			if _current_defender.has_method("_try_animation"):
				var success = _current_defender._try_animation("parry")
				print("[RealTimeDefense] Parry animation success: %s" % success)
		"perfect_parry":
			# Play parry animation first, then counterattack
			if _current_defender.has_method("_try_animation"):
				var success = _current_defender._try_animation("parry")
				print("[RealTimeDefense] Perfect parry animation success: %s" % success)
				# Wait for parry animation to complete
				var parry_duration = 0.3  # Approximate parry animation duration
				await get_tree().create_timer(parry_duration).timeout
	
	# Emit result for UI feedback
	defense_result.emit(_current_defender, result_type)
	
	# Trigger counterattack for perfect parry (after parry animation completes)
	if result_type == "perfect_parry" and _current_attacker:
		_execute_perfect_parry_counter()

func _execute_perfect_parry_counter() -> void:
	if not is_instance_valid(_current_defender) or not is_instance_valid(_current_attacker):
		return
	
	# Stun the attacker momentarily so they don't return before taking counter damage
	_current_attacker.is_counter_stunned = true
	
	# Play attack animation on defender (standardised melee slot)
	_current_defender._try_animation("melee_combo_1")
	
	# Wait for defender's contact frame (hit_moment)
	await _current_defender.hit_moment
	
	# Calculate counter damage
	var multiplier = 1.5
	var base_counter_dmg = int(_current_defender.attack * multiplier)
	var final_counter_dmg = Formulas.physical_damage(_current_defender, _current_attacker, max(1, base_counter_dmg))
	
	# Apply damage to attacker
	await _current_attacker.take_damage(final_counter_dmg, _current_defender)
	
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.hud:
		battle_manager.hud.update_health_bars()
		if battle_manager.hud.battle_text_display:
			battle_manager.hud.battle_text_display.show_counter(_current_defender, _current_attacker, final_counter_dmg)
	
	# CRITICAL: Ensure attacker returns to original position after counterattack
	# The attacker's original attack flow was interrupted, so we need to handle return here
	if _current_attacker.has_method("return_to_original_position") and _current_attacker.original_position != Vector3.ZERO:
		print("[RealTimeDefense] Counterattack complete - forcing attacker to return to position")
		_current_attacker.return_to_original_position()
		# Wait for return movement to complete
		while _current_attacker.is_advancing:
			await get_tree().create_timer(0.1).timeout
		print("[RealTimeDefense] Attacker return complete")
		_current_attacker.battle_idle()
	
	# Check if attacker was defeated by counter attack
	if _current_attacker.is_defeated():
		if battle_manager:
			battle_manager._cleanup_defeated_from_turn_order()
			battle_manager.cleanup_defeated_enemies()
	
	counterattack_triggered.emit(_current_defender, _current_attacker)

func _on_defense_window_timeout() -> void:
	if _active_defense_window and not _defense_detected:
		_active_defense_window = false
		_current_result = "none"
		if _current_defender:
			defense_result.emit(_current_defender, "none")

func _get_current_result() -> String:
	return _current_result

## Cancel the current defense window (e.g., if attack is interrupted)
func cancel_defense_window() -> void:
	_active_defense_window = false
	_defense_detected = false
	_current_attacker = null
	_current_defender = null
	_attack_config = null
