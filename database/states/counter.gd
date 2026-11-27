## CounterState
## When an opponent attacks its battler, it strikes back with a normal attack
## (stat formula, states, hit chance). Bonus damage (weapon and orb procs)
## and states' damage don't trigger it. Limited uses per turn.
##
## interrupt_attacker: true counters while the attacker is still close; false
## waits for it to return first.

class_name CounterState
extends State

@export var counter_damage_multiplier: float = 1.5
@export var interrupt_attacker: bool = true  ## If true, counter fires while attacker is close. If false, wait for return.
@export var max_counters_per_turn: int = 2  ## Limit how many times counter can trigger per turn

var counters_used_this_turn: int = 0  ## Track usage this turn

func _init():
	state_name = "Counter"
	state_type = StateType.COUNTER
	# (A countering battler takes normal damage)
	turns_active = -1  # Infinite until cured

## Uses reset each time any battler's turn starts.
func on_any_turn_start(_owner: Node) -> void:
	counters_used_this_turn = 0

## Being attacked by an opponent triggers the counter (the hit waits for it).
## Bonus damage (weapon and orb procs) and states' damage don't.
func on_hit_taken(owner: Node, hit: Dictionary) -> void:
	await super(owner, hit)
	var attacker = hit.get("attacker")
	if hit.get("is_attack", false) and attacker is Battler and is_instance_valid(attacker) and not owner.is_defeated():
		await perform_counter(owner, attacker)

func perform_counter(defender: Battler, attacker: Battler) -> void:
	# Only trigger if counter is still active
	if not defender.active_states.has(state_name):
		return
	
	# Safety: Don't counter allies
	if attacker.team == defender.team:
		return
	
	# Check usage limit
	if counters_used_this_turn >= max_counters_per_turn:
		return
	
	counters_used_this_turn += 1
	
	# Delay slightly for visual feedback
	await defender.get_tree().create_timer(0.2).timeout
	
	if interrupt_attacker:
		# INTERRUPT mode: Counter happens immediately while attacker is in position
		await _execute_counter_attack(defender, attacker)
	else:
		# DELAYED mode: Let attacker return first, then counter
		await _wait_for_attacker_return(attacker)
		await _execute_counter_attack(defender, attacker)

## Execute the actual counter attack
func _execute_counter_attack(defender: Battler, attacker: Battler) -> void:
	# Default counter attack (basic attack with multiplier)
	attacker.is_counter_stunned = true  # Stun attacker
	# The swing's hit frame (hit_moment) resolves against current_target
	defender.current_target = attacker

	defender._try_animation(AnimationMapping.MELEE_COMBO_1)
	await defender.get_tree().create_timer(0.5).timeout

	# A normal attack: stat formula, states (Marked, Electrocuted...), hit
	# chance, then the attacker's own on-hit reactions
	var battle_manager = defender.get_tree().get_first_node_in_group("battle_manager")
	if battle_manager:
		battle_manager.damage_calculation(defender, attacker, int(defender.attack * counter_damage_multiplier), null, "physical", "none", true)

	# Trigger camera shake for counter attack
	if battle_manager and battle_manager.effect_manager:
		battle_manager.effect_manager.apply_camera_shake(0.25, 0.35)  # Strong shake for counter

## Wait for attacker to return to original position before counter
func _wait_for_attacker_return(attacker: Battler) -> void:
	var timeout = 5.0
	var elapsed = 0.0
	
	while attacker.is_advancing and elapsed < timeout:
		await attacker.get_tree().create_timer(0.1).timeout
		elapsed += 0.1
