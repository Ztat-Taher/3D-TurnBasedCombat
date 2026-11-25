class_name WeaponEffect
extends Resource
## One param-driven weapon effect, evaluated by [WeaponSystem] when its
## trigger fires. Mirrors the vestige effect-script pattern but stays
## data-only so weapons are fully editable in the inspector.

enum Trigger {
	ON_ATTACK_HIT,     ## Weapon owner's attack lands a hit.
	ON_CARD_PLAY,      ## Owner plays a card.
	ON_DAMAGE_TAKEN,   ## Owner takes damage.
	ON_BATTLE_START,
	ON_BATTLE_END,
}

enum Kind {
	DAMAGE,            ## Bonus weapon damage (separate hit via damage_calculation).
	APPLY_STATE,       ## Apply a State resource to the recipient.
	HEAL,              ## Heal the recipient.
	GAIN_STACK,        ## Add to a weapon-internal stack (stack_id).
	CONSUME_STACKS,    ## Consume weapon stacks for bonus damage; may apply state.
}

@export var trigger: Trigger = Trigger.ON_ATTACK_HIT
@export var kind: Kind = Kind.APPLY_STATE

@export_group("Values")
## Flat amount, or percent when [member value_is_attack_percent] (of owner's
## attack stat). For APPLY_STATE also used as accumulation_value when
## [member state_accumulation] is 0 and the state supports it.
@export var value: float = 0.0
@export var value_is_attack_percent: bool = false
@export var chance: float = 1.0  ## 0..1 proc chance.
## Only fires while the weapon holds at least this many stacks of [member stack_id].
@export var requires_stacks: int = 0
## Apply to the weapon owner instead of the attack target.
@export var scope_self: bool = false

@export_group("State")
@export var state: State = null
## Stacks written to state.stack_count on application (0 = leave as authored).
@export var state_stack_count: int = 0
## Value written to state.accumulation_value (bleed-style states).
@export var state_accumulation: int = 0

@export_group("Stacks")
@export var stack_id: StringName = &""
@export var max_stacks: int = 0  ## 0 = uncapped.
@export var stacks_per_trigger: int = 1
## For DAMAGE: multiply the amount by the weapon's current count of this stack
## (e.g. Edge stacks ramping bonus damage). 0/empty = no scaling.
@export var scale_with_stack: StringName = &""
