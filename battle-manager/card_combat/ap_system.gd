class_name APSystem
extends Node
## Action Points system for card costs
## Manages AP regeneration, spending, and UI display

signal ap_changed(current_ap: int, max_ap: int)
signal ap_insufficient(required_ap: int)

var current_ap: int = 3
var max_ap: int = 3
var ap_per_turn: int = 3

func _ready():
	current_ap = ap_per_turn
	max_ap = ap_per_turn

func setup(ap_per_turn_value: int, max_ap_value: int) -> void:
	ap_per_turn = ap_per_turn_value
	max_ap = max_ap_value
	current_ap = ap_per_turn
	ap_changed.emit(current_ap, max_ap)

func can_spend_ap(amount: int) -> bool:
	return current_ap >= amount

func spend_ap(amount: int) -> bool:
	if not can_spend_ap(amount):
		ap_insufficient.emit(amount)
		return false
	
	current_ap -= amount
	ap_changed.emit(current_ap, max_ap)
	return true

func regen_ap() -> void:
	current_ap = min(current_ap + ap_per_turn, max_ap)
	ap_changed.emit(current_ap, max_ap)

func add_ap(amount: int) -> void:
	current_ap = min(current_ap + amount, max_ap)
	ap_changed.emit(current_ap, max_ap)

func get_current_ap() -> int:
	return current_ap

func get_max_ap() -> int:
	return max_ap

func get_ap_percentage() -> float:
	if max_ap == 0:
		return 0.0
	return float(current_ap) / float(max_ap)
