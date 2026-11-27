@tool
class_name Vestige
extends Resource
## Vestige: Permanent passive item that provides ongoing bonuses throughout a run
## Similar to Slay the Spire relics, with hybrid global/per-character scope.
##
## A vestige is pure data: modifier fields (read by [VestigeHolder]) and
## [member trigger_hooks] (an effect per battle event). Who owns it is
## [GameState]'s concern; how it acts in battle is [VestigeHolder]'s.

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

## Where vestiges can be obtained (see [method can_drop_from]).
enum DropSource { TREASURE, ELITE, BOSS, EVENT, SHOP, REST_SITE }

@export var can_drop_from_elites: bool = true
@export var can_drop_from_bosses: bool = true
@export var can_drop_from_treasure: bool = true
@export var can_drop_from_events: bool = true
@export var can_be_purchased: bool = true
@export var can_drop_from_rest_sites: bool = false
## Shop price (for when shops sell vestiges).
@export var base_price: int = 100

## Most copies one owner can stack (1 = unique, 0 = unlimited). Each stack
## repeats the vestige's modifiers (multipliers compound).
@export_range(0, 99) var max_stacks: int = 1

## What the vestige does on battle events.
@export var trigger_hooks: Array[TriggerHook] = []

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
## Not applied yet: there is no gold economy.
@export var gold_multiplier: float = 1.0

## Card modifiers
@export_group("Card Modifiers")
## Extra cards in every turn's hand.
@export var cards_drawn_per_turn: int = 0
## Extra cards in the first hand of each combat.
@export var starting_hand_size: int = 0
## AP taken off every card's cost (never below 0).
@export var ap_cost_reduction: int = 0


## True if an owner holding [param current_stacks] of this can take another.
func can_gain_stack(current_stacks: int) -> bool:
	return max_stacks <= 0 or current_stacks < max_stacks


## True if this vestige can be obtained from [param source].
func can_drop_from(source: DropSource) -> bool:
	match source:
		DropSource.TREASURE: return can_drop_from_treasure
		DropSource.ELITE: return can_drop_from_elites
		DropSource.BOSS: return can_drop_from_bosses
		DropSource.EVENT: return can_drop_from_events
		DropSource.SHOP: return can_be_purchased
		DropSource.REST_SITE: return can_drop_from_rest_sites
	return false


## Get the rarity name as a string
func get_rarity_name() -> String:
	return Rarity.keys()[rarity]


## Display color for each rarity (UI tags, chest VFX, glows)
const RARITY_COLORS := {
	Rarity.COMMON: Color(0.85, 0.85, 0.85),
	Rarity.UNCOMMON: Color(0.35, 0.85, 1.0),
	Rarity.RARE: Color(1.0, 0.78, 0.25),
	Rarity.BOSS: Color(1.0, 0.32, 0.28),
	Rarity.EVENT: Color(0.85, 0.45, 1.0),
	Rarity.SHOP: Color(0.45, 1.0, 0.5),
}

## How flashy a reveal should be for each rarity: 0 = modest .. 3 = huge
const RARITY_TIERS := {
	Rarity.COMMON: 0,
	Rarity.UNCOMMON: 1,
	Rarity.RARE: 2,
	Rarity.BOSS: 3,
	Rarity.EVENT: 2,
	Rarity.SHOP: 1,
}

static func get_rarity_color(for_rarity: Rarity) -> Color:
	return RARITY_COLORS.get(for_rarity, Color.WHITE)

static func get_rarity_tier(for_rarity: Rarity) -> int:
	return RARITY_TIERS.get(for_rarity, 0)
