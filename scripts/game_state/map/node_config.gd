class_name NodeConfig
extends Resource

# Preload vestige class for reward configuration
const Vestige = preload("res://database/vestiges/vestige_template.gd")

## Configuration for different node types on the map
## Allows modular customization of appearance and behavior

@export var node_type: String = "Combat"
@export var icon_texture: Texture2D
@export var pawn_scene: PackedScene
@export var difficulty_level: int = 1
@export var reward_multiplier: float = 1.0
@export var description: String = ""

## Visual properties
@export var node_color: Color = Color.WHITE
@export var glow_color: Color = Color.WHITE
@export var glow_intensity: float = 0.0

## Audio properties
@export var hover_sound: AudioStream
@export var select_sound: AudioStream
@export var complete_sound: AudioStream

## Vestige reward configuration
@export var vestige_reward: Vestige = null  # Fixed vestige reward
@export var vestige_reward_rarity: Vestige.Rarity = Vestige.Rarity.COMMON  # Or random by rarity
@export var vestige_reward_count: int = 1
@export var vestige_reward_source: String = "combat"  # combat, treasure, event, shop, rest