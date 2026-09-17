class_name NodeConfig
extends Resource

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