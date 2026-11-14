@tool
class_name Vestige
extends Resource
## Vestige: Permanent passive item that provides ongoing bonuses throughout a run
## Similar to Slay the Spire relics, with hybrid global/per-character scope

## Vestige identifier
@export var vestige_id: String = ""
@export var vestige_name: String = ""
@export var description: String = ""
@export var icon: Texture2D = null

## Scope: Global (party-wide) or Per-Character
enum Scope {
	GLOBAL,         # Affects entire party
	PER_CHARACTER  # Each ally has their own instance
}
@export var scope: Scope = Scope.PER_CHARACTER

## Rarity and acquisition
enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	BOSS,
	EVENT,
	SHOP
}
@export var rarity: Rarity = Rarity.COMMON
@export var can_drop_from_elites: bool = true
@export var can_drop_from_bosses: bool = true
@export var can_drop_from_treasure: bool = true
@export var can_drop_from_events: bool = true
@export var can_be_purchased: bool = true
@export var can_drop_from_rest_sites: bool = false
@export var base_price: int = 100

## Stacking rules
enum StackBehavior {
	NO_STACK,       # Cannot have multiple copies
	LIMITED_STACK,  # Can have up to max_stacks copies
	UNLIMITED_STACK # Can have unlimited copies
}
@export var max_stacks: int = 1  # 1 = unique, >1 = limited stacks, -1 = unlimited
@export var stack_behavior: StackBehavior = StackBehavior.NO_STACK

## Activation conditions
@export var required_level: int = 1
@export var required_element: GlobalBattleSettings.Elements = GlobalBattleSettings.Elements.NONE
@export var requires_specific_card_type: bool = false
@export var required_card_tags: Array[String] = []

## Trigger hooks (which events this vestige responds to)
@export var trigger_hooks: Array[Resource] = []

## Stat modifiers (flat and percentage)
@export_group("Stat Modifiers")
@export var max_health_bonus: int = 0
@export var attack_bonus: int = 0
@export var defense_bonus: int = 0
@export var agility_bonus: int = 0
@export var max_ap_bonus: int = 0
@export var ap_regen_bonus: int = 0

@export var max_health_percent: float = 0.0
@export var attack_percent: float = 0.0
@export var defense_percent: float = 0.0
@export var agility_percent: float = 0.0

## Combat modifiers
@export_group("Combat Modifiers")
@export var damage_dealt_multiplier: float = 1.0
@export var damage_taken_multiplier: float = 1.0
@export var healing_multiplier: float = 1.0
@export var xp_multiplier: float = 1.0
@export var gold_multiplier: float = 1.0

## Card modifiers
@export_group("Card Modifiers")
@export var cards_drawn_per_turn: int = 0
@export var starting_hand_size: int = 0
@export var ap_cost_reduction: int = 0
@export var card_remove_on_exhaust: bool = false

## Special effects (script-based for complex behavior)
@export var effect_script: Resource = null

## Visual/audio
@export var pickup_vfx: Resource = null
@export var pickup_sound: AudioStream = null


## Helper method to check if this vestige can be stacked with existing
func can_stack_with(existing_count: int) -> bool:
	match stack_behavior:
		StackBehavior.NO_STACK:
			return existing_count == 0
		StackBehavior.LIMITED_STACK:
			return existing_count < max_stacks
		StackBehavior.UNLIMITED_STACK:
			return true
		_:
			return false


## Get the rarity name as a string
func get_rarity_name() -> String:
	return Rarity.keys()[rarity]


## Get the scope name as a string
func get_scope_name() -> String:
	return Scope.keys()[scope]
