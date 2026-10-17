# Hit Effect Billboard System

## Overview
The hit effect system provides billboard spritesheet visual effects that play when battlers take damage. Effects are dynamically selected based on damage type and element, and are smartly spaced around the target's AABB center.

## Features
- **Billboard spritesheets only** - Effects use Sprite3D with billboard enabled to always face the camera
- **Smart spacing** - Multiple effects are arranged in a circle or grid around the center point instead of stacking
- **Dynamic selection** - Effects are chosen based on damage type (physical, magical, true_damage) and element (fire, ice, lightning, etc.)
- **Configurable** - Per-battler override or global library
- **Auto-cleanup** - Effects automatically remove themselves after playing

## Components

### HitEffectConfig
Resource that defines a single hit effect:
- `spritesheet_texture`: Texture2D - The spritesheet to use
- `hframes`: int - Horizontal frames in spritesheet
- `vframes`: int - Vertical frames in spritesheet
- `fps`: float - Animation speed
- `scale`: Vector3 - Size of billboard
- `color`: Color - Color modulation
- `duration`: float - How long to play
- `spacing_offset`: Vector2 - Optional manual offset from center
- `spacing_radius`: float - Radius for circle arrangement

### HitEffectLibrary
Resource that maps damage/element types to arrays of HitEffectConfig:
- `effect_map`: Dictionary - Maps type keys to effect arrays
- `get_effects_for_type(damage_type, element)`: Returns matching effects
- `add_effect(key, effect)`: Add an effect to the library
- `remove_effect(key, effect)`: Remove an effect from the library

### GlobalHitEffectLibrary
Autoload singleton that manages the global hit effect library:
- `current_library`: HitEffectLibrary - The active library
- `load_default_library()`: Load the default library from database
- `set_library(library)`: Set a custom library
- `get_library()`: Get the current library
- `get_effects(damage_type, element)`: Get effects for a type
- `reload_default_library()`: Reload the default library (for debugging)

## Usage

### For Enemy Attacks
Set damage_type and element in EnemyAttackConfig:
```gdscript
var attack_config = EnemyAttackConfig.new()
attack_config.damage_type = "fire"
attack_config.element = "fire"
```

When the enemy attacks, the system will automatically:
1. Extract damage_type and element from the attack config
2. Look up matching effects from the global library
3. Spawn effects on the target at their AABB center
4. Space multiple effects in a circle/grid pattern

### For Card Effects
Set damage_type and element in CardEffect:
```gdscript
var card_effect = CardEffect.new()
card_effect.damage_type = "lightning"
card_effect.element = "lightning"
```

The card battle manager will pass these to take_damage() when applying damage.

### Custom Hit Effects
To add custom hit effects:

1. Create your spritesheet textures in `assets/effects/hits/`
2. Create HitEffectConfig resources:
```gdscript
var effect = HitEffectConfig.new()
effect.spritesheet_texture = preload("res://assets/effects/hits/my_effect.png")
effect.hframes = 4
effect.vframes = 4
effect.fps = 12.0
effect.scale = Vector3(1.5, 1.5, 1.5)
effect.color = Color.RED
effect.duration = 0.6
```

3. Add to a library:
```gdscript
var library = HitEffectLibrary.new()
library.add_effect("fire", effect)
```

4. Set as global or per-battler:
```gdscript
# Global
GlobalHitEffectLibrary.set_library(library)

# Per-battler override
battler.hit_effect_library = library
```

## Spacing Algorithm

### Circle Arrangement (2-6 effects)
Effects are arranged in a circle around the center point:
- Radius: 0.3 units (configurable per effect)
- Angle per effect: 360° / N
- Position: center + (cos(angle) * radius, sin(angle) * radius, 0)

### Grid Arrangement (7+ effects)
Effects are arranged in a grid:
- Grid size: ceil(sqrt(N))
- Cell spacing: 0.2 units
- Grid is centered around the spawn point

## File Structure
```
scripts/systems/battle/effects/hit_effect_system/
├── hit_effect_config.gd          # Single effect configuration
└── hit_effect_library.gd          # Library of effects

database/effects/
└── default_hit_effects.tres       # Default library resource

assets/effects/hits/
├── hit_physical.png               # Physical hit spritesheet
├── hit_fire.png                   # Fire hit spritesheet
├── hit_ice.png                    # Ice hit spritesheet
├── hit_lightning.png              # Lightning hit spritesheet
├── hit_earth.png                  # Earth hit spritesheet
└── hit_magic.png                  # Magic hit spritesheet

assets/globals/hit_effect_library/
└── hit_effect_library_globals.gd  # Global autoload singleton
```

## Integration Points

### Battler.take_damage()
Modified to accept damage_type and element parameters:
```gdscript
func take_damage(amount: int, attacker: Battler = null, damage_type: String = "physical", element: String = "none") -> void:
    play_hit_effects(damage_type, element, attacker)
    # ... rest of damage logic
```

### BattleManager.damage_calculation()
Modified to pass damage_type and element to take_damage():
```gdscript
func damage_calculation(attacker, target, damage, attack_config: EnemyAttackConfig = null, damage_type: String = "physical", element: String = "none") -> void:
    # ... damage calculation
    await target.take_damage(damage, attacker, final_damage_type, final_element)
```

### CardEffect._apply_damage()
Modified to pass damage_type and element:
```gdscript
func _apply_damage(target: Node, damage: int, _is_critical: bool, attacker: Node = null) -> int:
    if target.has_method("take_damage"):
        target.take_damage(damage, attacker, damage_type, element)
        return damage
    return 0
```

## Default Effects
The default library includes effects for:
- **physical**: Basic slash impact (white)
- **fire**: Fire explosion (orange, larger scale)
- **ice**: Ice shatter (light blue)
- **lightning**: Electric spark (yellow, faster fps)
- **earth**: Rock impact dust (brown, slower fps)
- **magic**: Magical glow (purple)
- **air**: Wind swirl (light gray)

Note: These use placeholder textures. Replace with actual spritesheet art for production.

## Troubleshooting

### Effects not appearing
1. Check that GlobalHitEffectLibrary autoload is loaded (check project.godot)
2. Verify default_hit_effects.tres exists and loads correctly
3. Check that damage_type and element are being passed correctly
4. Enable debug output in HitEffectConfig.spawn() to verify spawning

### Effects overlapping
- Check spacing_radius in HitEffectConfig
- Adjust scale of effects if they're too large
- For many effects (7+), verify grid arrangement is working

### Wrong effects playing
- Verify damage_type and element values match library keys
- Check library mapping in default_hit_effects.tres
- Ensure per-battler override isn't conflicting with global library

## Performance Considerations
- Sprite3D billboards are generally performant
- Limit simultaneous effects if experiencing FPS drops
- Consider effect pooling for very frequent hits
- Optimize spritesheet textures (compress, reduce resolution if needed)

## Future Enhancements
- Add effect variants for variety
- Support conditional effects (e.g., different effects based on damage amount)
- Add effect combinations (e.g., fire + lightning effects)
- Support custom spacing patterns
- Add effect pooling for performance
