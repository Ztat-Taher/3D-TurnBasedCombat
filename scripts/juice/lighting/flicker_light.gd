class_name FlickerLight
extends Light3D
## Fire-like flicker: drives [member Light3D.light_energy] (and optionally a
## small position wobble) from smooth noise around the energy set in the scene.

## Fraction of the base energy the flicker may add/remove.
@export_range(0.0, 1.0) var energy_variation : float = 0.25
## Noise speed; higher = faster flicker.
@export var speed : float = 6.0
## Max wobble of the light's position (meters), so shadows dance a little.
@export var position_wobble : float = 0.03

var _base_energy : float
var _base_position : Vector3
var _noise := FastNoiseLite.new()
var _time : float = 0.0


func _ready() -> void:
	_base_energy = light_energy
	_base_position = position
	_noise.seed = randi()
	_noise.frequency = 1.0


func _process(delta : float) -> void:
	_time += delta * speed
	light_energy = _base_energy * (1.0 + _noise.get_noise_1d(_time) * energy_variation * 2.0)
	if position_wobble > 0.0:
		position = _base_position + Vector3(
			_noise.get_noise_2d(_time, 17.0),
			_noise.get_noise_2d(_time, 53.0) * 0.5,
			_noise.get_noise_2d(_time, 91.0)) * position_wobble * 2.0
