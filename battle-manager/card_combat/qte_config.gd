class_name QTEConfig
extends Resource
## Configuration for QTE system
## Resource-driven QTE difficulty and effect settings

@export_group("Card QTE Settings")
## Whether QTEs are enabled for card execution
@export var card_qte_enabled: bool = true
## Default QTE difficulty for card attacks (0.0 = easy, 1.0 = hard)
@export_range(0.0, 1.0, 0.1) var default_card_qte_difficulty: float = 0.5
## Damage multiplier for successful card QTE
@export_range(1.0, 2.0, 0.1) var card_qte_success_multiplier: float = 1.5
## Damage multiplier for failed card QTE
@export_range(0.5, 1.0, 0.1) var card_qte_failure_multiplier: float = 0.8

@export_group("Reactive Defense Settings")
## Whether reactive dodge/parry QTEs are enabled when attacked
@export var reactive_defense_enabled: bool = true
## QTE difficulty for reactive dodge (0.0 = easy, 1.0 = hard)
@export_range(0.0, 1.0, 0.1) var dodge_qte_difficulty: float = 0.6
## QTE difficulty for reactive parry (0.0 = easy, 1.0 = hard)
@export_range(0.0, 1.0, 0.1) var parry_qte_difficulty: float = 0.7
## Damage reduction for successful dodge (0.0 = no reduction, 1.0 = complete avoidance)
@export_range(0.0, 1.0, 0.1) var dodge_damage_reduction: float = 1.0
## Damage reduction for successful parry (0.0 = no reduction, 1.0 = complete avoidance)
@export_range(0.0, 1.0, 0.1) var parry_damage_reduction: float = 0.5

@export_group("QTE Timing")
## Base time (seconds) for countdown QTEs
@export var base_qte_time: float = 3.0
## Minimum time (seconds) for QTEs (prevents impossible QTEs)
@export var min_qte_time: float = 0.5
## Input key for countdown QTEs (action name)
@export var qte_input_key: String = "f"
