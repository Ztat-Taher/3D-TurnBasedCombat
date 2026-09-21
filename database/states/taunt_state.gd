## TauntState
## Forces enemies to target this battler if possible
## Used by tanks to protect allies

class_name TauntState
extends State

@export var break_after_damage: int = 0  # Break taunt after taking this much damage (0 = never break)

var damage_taken_while_taunting: int = 0

func _init():
	state_name = "Taunt"
	state_type = StateType.BUFF
	state_description = "Forces enemies to target this battler"
	is_taunting = true  # Forces AI targeting
	turns_active = 2  # Lasts 2 turns by default
	can_be_cured = true
	break_after_damage = 0  # Never break by default
	damage_taken_while_taunting = 0

## Track damage taken while taunting
func add_damage_taken(damage: int) -> void:
	damage_taken_while_taunting += damage

## Check if taunt should break due to damage threshold
func should_break_from_damage() -> bool:
	if break_after_damage <= 0:
		return false
	return damage_taken_while_taunting >= break_after_damage

## Reset damage tracking
func reset_damage_tracking() -> void:
	damage_taken_while_taunting = 0