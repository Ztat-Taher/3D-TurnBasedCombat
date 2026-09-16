class_name EnemyAttackConfig
extends Resource
## Configuration for an individual attack or skill an enemy can perform

@export var attack_name: String = "Strike"
@export var animation_name: String = "melee_combo_1"
@export var damage_multiplier: float = 1.0
@export var hit_frame_ratio: float = -1.0 ## Contact frame ratio override (e.g. 0.55). Set to -1 to use the battler's default.
@export var move_announcement_type: String = "attack" ## "attack", "heal", "buff"
@export_range(0.1, 10.0, 0.1) var weight: float = 1.0 ## Weight for AI attack selection
@export var description: String = ""

@export_group("Defense Rules")
## If true, this attack can be dodged (only applies when requires_jump is false)
@export var can_dodge: bool = true
## If true, this attack can be parried (only applies when requires_jump is false)
@export var can_parry: bool = true
## If true, this attack MUST be jumped over. Dodge and parry are disabled.
@export var requires_jump: bool = false

## Returns a dictionary of allowed defense options for this attack.
## Keys: "jump", "dodge", "parry" — values are booleans.
func get_allowed_defenses() -> Dictionary:
	if requires_jump:
		return {"jump": true, "dodge": false, "parry": false}
	return {"jump": false, "dodge": can_dodge, "parry": can_parry}

