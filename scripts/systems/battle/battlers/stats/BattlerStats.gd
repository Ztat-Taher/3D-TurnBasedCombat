@tool
class_name BattlerStats
extends Resource
## Configuration and progression stats for player/ally battlers

@export var character_name: String = "Player" ## Character display name
@export var thumbnail: Texture2D = preload("res://Placeholder.svg") ## Portrait shown in battle results and HUD

## LEVEL-FOCUSED PROGRESSION SYSTEM
## Stat = base_stat + (level - 1) * stat_multiplier
@export var level: int = 1 ## Character level (determines stat scaling)

@export_group("Base Stats (at Level 1)")
@export var max_health: int = 100 ## Health is used to make sure character's take longer to be downed.
@export var attack: int = 10 ## Attack increases the amount of base damage when performing cards/attacks.
@export var defense: int = 5 ## Defense reduces incoming damage.
@export var agility: int = 5 ## Agility affects combat speed and turn order.
@export var max_ap: int = 3 ## Maximum Action Points for actions and card play
@export var ap_regen_per_turn: int = 3 ## AP regenerated at the start of each turn

@export_group("Stat Multipliers (per level)")
## Growth per level: new_stat = base_stat + (level - 1) * multiplier
@export var health_multiplier: int = 15 ## Health gain per level
@export var attack_multiplier: int = 2 ## Attack gain per level
@export var defense_multiplier: int = 1 ## Defense gain per level
@export var agility_multiplier: int = 1 ## Agility gain per level
@export var ap_multiplier: int = 0 ## AP gain per level (default 0)

@export_group("Other Stats")
@export var element: int = GlobalBattleSettings.Elements.Physical ## Character element

## Voicelines and Audio
@export var voicelines: Voicelines ## Character voicelines for combat events
