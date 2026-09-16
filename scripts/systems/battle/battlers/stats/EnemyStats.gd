@tool
class_name EnemyStats
extends Resource
## Dedicated stats resource for enemy battlers
## Lightweight and free from player AP, card systems, and level progression multipliers

@export var enemy_name: String = "Enemy"
@export var is_boss: bool = false ## If true, triggers the cinematic top-center boss health bar
@export var thumbnail: Texture2D = preload("res://Placeholder.svg")

@export_group("Combat Stats")
@export var max_health: int = 100
@export var attack: int = 10
@export var defense: int = 5
@export var agility: int = 5
@export var element: int = GlobalBattleSettings.Elements.Physical

@export_group("Attacks & Skills")
## Available attacks the AI can select from in combat
@export var attacks: Array[EnemyAttackConfig] = []

@export_group("Battle Rewards & Drops")
@export var exp_reward: int = 100
@export var cash_reward: int = 10
@export var item_drops: Array[EnemyDrop] = []
