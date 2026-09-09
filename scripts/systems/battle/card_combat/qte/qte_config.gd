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
## Whether reactive dodge/parry is enabled when attacked
@export var reactive_defense_enabled: bool = true
## Duration (seconds) of the total reactive defense window
@export var reactive_window_duration: float = 0.65
## Duration (seconds from start of window) for a Perfect Parry
@export var perfect_parry_window: float = 0.25
## Damage reduction for successful normal parry (0.0 = no reduction, 1.0 = complete avoidance)
@export_range(0.0, 1.0, 0.1) var parry_damage_reduction: float = 0.5
## Damage multiplier for perfect parry counterattack
@export var counter_damage_multiplier: float = 1.5
## Input action name for parry
@export var parry_action: String = "parry"
## Input action name for dodge
@export var dodge_action: String = "dodge"

@export_group("QTE Timing")
## Base time (seconds) for countdown QTEs
@export var base_qte_time: float = 3.0
## Minimum time (seconds) for QTEs (prevents impossible QTEs)
@export var min_qte_time: float = 0.5
## Input key for countdown QTEs (action name)
@export var qte_input_key: String = "f"
