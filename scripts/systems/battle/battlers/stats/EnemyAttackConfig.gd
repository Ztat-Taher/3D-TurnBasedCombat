class_name EnemyAttackConfig
extends Resource

@export var attack_name: String = "Strike"
@export var animation_name: String = "melee_combo_1"
@export var damage_multiplier: float = 1.0
@export var move_announcement_type: String = "attack"
@export_range(0.1, 10.0, 0.1) var weight: float = 1.0
@export var description: String = ""

@export_group("Defense Rules")
@export var can_dodge: bool = true
@export var can_parry: bool = true
@export var requires_jump: bool = false

@export_group("Defense Timing")
@export var pre_hit_parry_window: float = 0.15

func get_allowed_defenses() -> Dictionary:
	if requires_jump:
		return {"jump": true, "dodge": false, "parry": false}
	return {"jump": false, "dodge": can_dodge, "parry": can_parry}
