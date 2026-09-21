class_name State
extends Resource

enum StateType {
	DOT,           # Damage over time (poison, burn)
	COUNTER,       # Counter attacks
	BUFF,         # Stat increases
	DEBUFF        # Stat decreases
}

@export var state_name: String = ""
@export var state_description: String = ""
@export var state_type: StateType
@export var icon_texture: Texture2D = null  ## UI icon for this status effect
@export_range(0, 100, 1) var damage_per_turn: int = 0  ## Base damage/healing per turn.
@export_range(0.0, 2.0, 0.1) var power_multiplier: float = 1.0  ## Multiplier for state damage. Scales with attacker's attack stat.
@export_range(0.0, 100.0, 1.0) var hit_chance: float = 100.0  ## Accuracy modifier (100 = normal, 60 = 60% hit chance). Used for Blind and accuracy debuffs.
@export_range(-1, 99, 1) var turns_active: int = -1  ## Duration in turns. -1 means infinite until cured.
@export var can_be_cured: bool = true  ## Whether this state can be removed by cure card effects or items.
@export_range(0.1, 2.0, 0.1) var damage_taken_multiplier: float = 1.0  ## Incoming damage multiplier. 1.0 = normal, 1.5 = 50% more damage, 0.5 = 50% less damage

# Status effect mechanics
@export var skip_turn: bool = false  ## If true, battler skips their turn (Chilled)
@export var stack_count: int = 0  ## Current stack count (Burning)
@export_range(1, 20, 1) var stack_max: int = 10  ## Maximum stack count (Burning)
@export var accumulation_value: int = 0  ## Current accumulation value (Bleed)
@export_range(10, 200, 10) var accumulation_max: int = 100  ## Accumulation threshold for proc (Bleed)
@export_range(0.1, 2.0, 0.1) var damage_dealt_multiplier: float = 1.0  ## Outgoing damage multiplier (Electrocuted, Berserk)
@export var shield_amount: int = 0  ## Shield absorption amount (Protected)
@export var is_taunting: bool = false  ## Forces AI targeting (Taunt)
@export_range(1.0, 3.0, 0.1) var marked_damage_bonus: float = 1.0  ## Bonus damage for marked targets (Marked)

## Helper methods for status effect management

func add_stacks(amount: int) -> void:
	## Add stacks up to the maximum cap
	stack_count = mini(stack_count + amount, stack_max)

func remove_stacks(amount: int) -> void:
	## Remove stacks, minimum 0
	stack_count = maxi(stack_count - amount, 0)

func add_accumulation(amount: int) -> void:
	## Add to accumulation value
	accumulation_value += amount

func should_proc() -> bool:
	## Check if state should trigger (e.g., bleed reaching threshold)
	return accumulation_value >= accumulation_max

func reset_accumulation() -> void:
	## Reset accumulation after proc
	accumulation_value = 0

func absorb_damage(damage: int) -> int:
	## Reduce damage by shield amount, return remaining damage
	if shield_amount <= 0:
		return damage
	
	var absorbed = mini(damage, shield_amount)
	shield_amount -= absorbed
	return damage - absorbed
