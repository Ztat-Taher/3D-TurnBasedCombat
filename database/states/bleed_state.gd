## BleedState
## Accumulation mechanic - invisible bleed bar fills up, triggers devastating damage when full
## Based on Elden Ring's bleed mechanic

class_name BleedState
extends State

@export var bleed_proc_damage_percent: float = 0.2  # 20% of max HP when proc triggers
@export var accumulation_per_damage_taken: float = 0.5  # 50% of damage taken adds to accumulation

func _init():
	state_name = "Bleed"
	state_type = StateType.DOT
	state_description = "Accumulates bleed from damage taken. Triggers massive damage when full."
	icon_texture = preload("res://assets/images/ui/status_effects/bleeding.png")
	accumulation_max = 100  # Threshold for bleed proc
	turns_active = -1  # Persists until proc or cured
	can_be_cured = true

## Add accumulation based on damage taken
func add_accumulation_from_damage(damage_taken: int) -> void:
	var accumulation_add = int(damage_taken * accumulation_per_damage_taken)
	add_accumulation(accumulation_add)

## Check if bleed should proc and calculate proc damage
func should_proc_bleed() -> bool:
	return should_proc()

## Calculate the devastating bleed proc damage
func get_proc_damage(max_hp: int) -> int:
	return int(max_hp * bleed_proc_damage_percent)

## Process the bleed proc - reset accumulation and return damage
func trigger_bleed_proc(max_hp: int) -> int:
	var proc_damage = get_proc_damage(max_hp)
	reset_accumulation()
	return proc_damage
