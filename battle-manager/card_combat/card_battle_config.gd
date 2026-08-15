class_name CardBattleConfig
extends Resource
## Configuration for card-based combat system
## Resource-driven balance parameters for card combat integration

@export_group("Action Points System")
## Action Points granted per turn
@export var ap_per_turn: int = 3
## Maximum Action Points a player can have
@export var max_ap: int = 3

@export_group("Deck Settings")
## Number of cards in initial hand
@export var initial_hand_size: int = 4
## Maximum number of cards in hand
@export var max_hand_size: int = 10
## Maximum number of cards on the board (if using board mechanics)
@export var max_board_size: int = -1  # -1 = unlimited

@export_group("QTE Settings")
## Whether QTEs are enabled for card execution
@export var qte_enabled: bool = true
## Default QTE difficulty (0.0 = easy, 1.0 = hard)
@export_range(0.0, 1.0, 0.1) var default_qte_difficulty: float = 0.5
## Damage multiplier for successful QTE
@export_range(1.0, 2.0, 0.1) var qte_success_multiplier: float = 1.5
## Damage multiplier for failed QTE
@export_range(0.5, 1.0, 0.1) var qte_failure_multiplier: float = 0.8

@export_group("Reactive Defense")
## Whether reactive dodge/parry QTEs are enabled when attacked
@export var reactive_defense_enabled: bool = true
## QTE difficulty for reactive dodge
@export_range(0.0, 1.0, 0.1) var dodge_qte_difficulty: float = 0.6
## QTE difficulty for reactive parry
@export_range(0.0, 1.0, 0.1) var parry_qte_difficulty: float = 0.7
## Damage reduction for successful dodge
@export_range(0.0, 1.0, 0.1) var dodge_damage_reduction: float = 1.0  # 100% damage avoided
## Damage reduction for successful parry
@export_range(0.0, 1.0, 0.1) var parry_damage_reduction: float = 0.5  # 50% damage reduced

@export_group("Card Balance")
## Base damage multiplier for attack cards
@export_range(0.5, 2.0, 0.1) var attack_damage_multiplier: float = 1.0
## Base healing multiplier for heal cards
@export_range(0.5, 2.0, 0.1) var heal_multiplier: float = 1.0
