# Current Cards, Attacks, and Hit Types Inventory

## Damage Types Available

### GlobalBattleSettings Elements (GlobalBattleSettings.gd)
**Updated to match CardConfig.Element as source of truth:**
```gdscript
enum Elements {
    NONE = 0,
    FIRE = 1,
    ICE = 2,
    LIGHTNING = 3,
    EARTH = 4,
    WIND = 5,
    LIGHT = 6,
    DARK = 7,
    ENDLIST
}
```

### CardConfig DamageType (card_config.gd)
```gdscript
enum DamageType {
    PHYSICAL = 0,
    MAGICAL = 1,
    TRUE_DAMAGE = 2
}
```

### CardConfig Element (card_config.gd)
```gdscript
enum Element {
    NONE = 0,
    FIRE = 1,
    ICE = 2,
    LIGHTNING = 3,
    EARTH = 4,
    WIND = 5,
    LIGHT = 6,
    DARK = 7
}
```

**Note**: GlobalBattleSettings.Elements has been updated to match CardConfig.Element exactly. CardConfig.Element is now the single source of truth for elements.

---

## Card Configurations

### Attack Cards

#### 1. basic_attack_config.tres
- **Name**: Basic Attack
- **Damage Type**: PHYSICAL (enum 0)
- **Element**: physical (from card_tags)
- **Base Damage**: 10
- **Scaling**: attack * 0.5
- **Animation**: melee_combo_1
- **QTE**: timing (0.5s window)
- **Tags**: ["attack", "basic", "physical"]

#### 2. flurry_attack_config.tres
- **Name**: Flurry Attack
- **Damage Type**: PHYSICAL (default)
- **Element**: physical (from card_tags)
- **Base Damage**: 15
- **Scaling**: attack * 0.5
- **Animation**: Multi-strike (melee_combo_1, melee_combo_2, melee_combo_3)
- **Multipliers**: [1.0, 1.2, 1.5]
- **QTE**: Multi-strike with varying difficulties
- **Tags**: ["attack", "multi-strike", "physical"]

### Ice/Status Cards

#### 3. ice_strike_config.tres
- **Name**: Ice Strike
- **Damage Type**: PHYSICAL (enum 0)
- **Element**: ICE (enum 2)
- **Base Damage**: 5
- **Scaling**: attack * 0.4
- **Animation**: ranged_cast_1
- **Applies**: Chilled state (100% chance, 1 turn)
- **Tags**: ["status", "ice", "single_target"]

#### 4. ice_spear_config.tres
- **Name**: Ice Spear
- **Damage Type**: PHYSICAL (enum 0)
- **Element**: ICE (enum 2)
- **Base Damage**: 12
- **Scaling**: attack * 0.6
- **Animation**: ranged_cast_1
- **Applies**: Chilled state (100% chance, 1 turn)
- **Tags**: ["status", "ice", "single_target"]

#### 5. blizzard_config.tres
- **Name**: Blizzard
- **Damage Type**: PHYSICAL (default)
- **Element**: ICE (enum 2)
- **Base Damage**: 8
- **Scaling**: attack * 0.4
- **Animation**: ranged_cast_1
- **Target**: ALL_ENEMIES
- **Applies**: Chilled state (60% chance, 1 turn)
- **Tags**: ["status", "ice", "aoe"]

### Fire/Status Cards

#### 6. burning_card_config.tres
- **Name**: Burning Strike
- **Damage Type**: PHYSICAL (default)
- **Element**: FIRE (inferred from name/state)
- **Animation**: ranged_cast_1
- **Applies**: Burning state (3 stacks)
- **Tags**: Not specified in config

### Lightning/Status Cards

#### 7. electrocuted_card_config.tres
- **Name**: Electrocute
- **Damage Type**: PHYSICAL (default)
- **Element**: LIGHTNING (inferred from name/state)
- **Animation**: ranged_cast_1
- **Applies**: Electrocuted state (2 turns)
- **Tags**: Not specified in config

### Bleed/Status Cards

#### 8. bleed_strike_config.tres
- **Name**: Bleed Strike
- **Damage Type**: PHYSICAL (default)
- **Element**: None (physical)
- **Base Damage**: 8
- **Scaling**: attack * 0.5
- **Animation**: ranged_cast_1
- **Applies**: Bleed state (infinite duration)
- **Tags**: ["status", "bleed", "single_target"]

### Heal Cards (No Hit Effects Needed)

#### 9. minor_heal_config.tres
- **Type**: HEAL (no damage, no hit effects)

#### 10. group_heal_config.tres
- **Type**: HEAL (no damage, no hit effects)

### Shield Cards (No Hit Effects Needed)

#### 11. single_shield_config.tres
- **Type**: SHIELD (no damage, no hit effects)

#### 12. group_shield_config.tres
- **Type**: SHIELD (no damage, no hit effects)

---

## Enemy Attack Configurations

### Bone Marauder Attacks

#### 1. bone_sweep.tres
- **Name**: Bone Sweep
- **Damage Type**: physical (default)
- **Element**: none (default)
- **Animation**: melee_combo_2
- **Damage Multiplier**: 1.2
- **Weight**: 2.0
- **Defense**: Jump only (dodge disabled, parry disabled, requires_jump = true)

#### 2. fractured_frenzy.tres
- **Name**: Fractured Frenzy
- **Damage Type**: physical (default)
- **Element**: none (default)
- **Animation**: ranged_cast_2
- **Damage Multiplier**: 1.4
- **Weight**: 2.5
- **Defense**: Dodge or parry (both enabled)

#### 3. rib_swipe.tres
- **Name**: Rib Swipe
- **Damage Type**: physical (default)
- **Element**: none (default)
- **Animation**: Not specified (uses default)
- **Weight**: 3.0
- **Defense**: Dodge only (parry disabled)

#### 4. skull_crush.tres
- **Name**: Skull Crush
- **Damage Type**: physical (default)
- **Element**: none (default)
- **Animation**: melee_combo_3
- **Damage Multiplier**: 1.6
- **Weight**: 1.5
- **Defense**: Parry only (dodge disabled)

---

## Hit Type Summary

### Currently Used in Cards
1. **physical** - Basic Attack, Flurry Attack, Ice Strike, Ice Spear, Blizzard, Bleed Strike
2. **ice** - Ice Strike, Ice Spear, Blizzard
3. **fire** - Burning Strike (inferred)
4. **lightning** - Electrocute (inferred)
5. **bleed** - Bleed Strike (status effect, not direct damage type)

### Currently Used in Enemy Attacks
1. **physical** - All enemy attacks (Bone Sweep, Fractured Frenzy, Rib Swipe, Skull Crush)
2. **none** - All enemy attacks (no element specified)

### Available but Not Currently Used
- **magical** - Damage type available but not used
- **true_damage** - Damage type available but not used
- **earth** - Element available but not used
- **wind** - Element available but not used
- **light** - Element available but not used
- **dark** - Element available but not used

---

## Hit Effect Library Mapping

### Current Hit Effect Library
The default hit effect library now includes effects for all damage types and elements:

**Damage Types:**
- `physical` - Basic physical hits (white)
- `magical` - Magical damage (purple)
- `true_damage` - True damage (red, larger scale)

**Elements:**
- `fire` - Fire effects (orange, larger scale)
- `ice` - Ice effects (light blue)
- `lightning` - Lightning effects (yellow, faster fps)
- `earth` - Earth effects (brown, slower fps)
- `wind` - Wind effects (light gray)
- `light` - Light effects (gold)
- `dark` - Dark effects (dark magenta)
- `magic` - Magic effects (purple) - mapped from old "air/magic"

### Mapping Strategy
The hit effect library uses string keys that match the lowercase element names from CardConfig.Element:
- CardConfig.Element.FIRE → "fire"
- CardConfig.Element.ICE → "ice"
- CardConfig.Element.LIGHTNING → "lightning"
- CardConfig.Element.EARTH → "earth"
- CardConfig.Element.WIND → "wind"
- CardConfig.Element.LIGHT → "light"
- CardConfig.Element.DARK → "dark"
- CardConfig.Element.NONE → "physical" (physical attacks use NONE element)

For damage types:
- CardConfig.DamageType.PHYSICAL → "physical"
- CardConfig.DamageType.MAGICAL → "magical"
- CardConfig.DamageType.TRUE_DAMAGE → "true_damage"

---

## Recommendations for Hit Effect System

### Immediate Hit Effects Needed
Based on current usage, the hit effect library should include:
1. **physical** - Most common (basic attacks, flurry, enemy attacks) ✓ **DONE**
2. **ice** - Ice Strike, Ice Spear, Blizzard ✓ **DONE**
3. **fire** - Burning Strike ✓ **DONE**
4. **lightning** - Electrocute ✓ **DONE**

### Future Hit Effects to Consider
- **earth** - For future earth-based attacks ✓ **DONE**
- **wind** - For wind-based attacks ✓ **DONE**
- **light** - For light-based attacks ✓ **DONE**
- **dark** - For dark-based attacks ✓ **DONE**
- **magical** - For magical damage types ✓ **DONE**
- **true_damage** - For true damage ✓ **DONE**

All hit effects are now configured in the default library with placeholder textures. Replace with actual spritesheet art for production.
