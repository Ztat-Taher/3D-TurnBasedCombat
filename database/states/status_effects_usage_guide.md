# Status Effects System - Usage Guide

## Overview
This system implements 8 unique status effects for turn-based combat:

### Core Effects
1. **Electrocuted** - Takes 50% more damage, deals 50% less damage
2. **Burning** - Stacking DOT (damage per turn × stack count)
3. **Bleed** - Accumulation mechanic (invisible bar fills, triggers massive damage when full)

### Additional Effects
4. **Chilled** - Skips turn in the turn queue
5. **Berserk** - Deals 50% more damage, takes 25% more damage (risk/reward)
6. **Taunt** - Forces AI to target this battler
7. **Marked** - Next attack deals bonus damage, then removes
8. **Protected** - Shield that absorbs damage until broken

## How to Apply Status Effects

### Using Resource Files
```gdscript
# Load a state resource
var electrocuted_state = load("res://database/states/resources/electrocuted_state.tres")

# Apply to a battler
battler.apply_state(electrocuted_state)
```

### Using State Classes Directly
```gdscript
# Create state instance
var burning_state = BurningState.new()
burning_state.apply_stacks(3)  # Start with 3 stacks

# Apply to battler
battler.apply_state(burning_state)
```

### Custom State Configuration
```gdscript
# Create custom state
var custom_protected = ProtectedState.new()
custom_protected.set_shield_amount(50)  # 50 HP shield
custom_protected.turns_active = 3  # Lasts 3 turns if not broken

battler.apply_state(custom_protected)
```

## How to Remove Status Effects

```gdscript
# Remove by state name
battler.remove_state("Burning")

# Check if state exists
if battler.active_states.has("Electrocuted"):
    var state = battler.active_states["Electrocuted"] as ElectrocutedState
    # Access state properties
    print("Turns remaining: %d" % state.turns_active)
```

## State-Specific Methods

### Burning State
```gdscript
# Add stacks
battler.add_burn_stacks(2)

# Get current burn damage
if battler.active_states.has("Burning"):
    var burn_state = battler.active_states["Burning"] as BurningState
    var damage = burn_state.get_burn_damage()
```

### Bleed State
```gdscript
# Add accumulation from damage
battler.add_bleed_accumulation(10)

# Manually trigger bleed proc
battler.trigger_bleed_proc()
```

### Protected State
```gdscript
# Break shield manually
battler.break_shield()

# Check shield status
if battler.active_states.has("Protected"):
    var protected_state = battler.active_states["Protected"] as ProtectedState
    if protected_state.has_shield():
        print("Shield remaining: %d" % protected_state.get_remaining_shield())
```

## Integration with Card Abilities

Example card effect that applies Burning:
```gdscript
func apply_card_effect(target: Battler) -> void:
    var burning_state = load("res://database/states/resources/burning_state.tres")
    var state_instance = burning_state.duplicate() as BurningState
    state_instance.apply_stacks(2)  # Apply 2 burn stacks
    target.apply_state(state_instance)
```

Example card effect that applies Marked:
```gdscript
func apply_card_effect(target: Battler) -> void:
    var marked_state = MarkedState.new()
    marked_state.marked_damage_bonus = 2.0  # 100% bonus damage
    target.apply_state(marked_state)
```

## Visual Effects

Status effects use your existing overlay system:
- **Electrocuted**: `lightning_overlay.tres` 
- **Burning**: `fire_overlay.tres`
- **Other effects**: No VFX currently (can be added later)

To attach VFX overlays to a battler, use your existing overlay system instead of creating new scenes.

## UI Integration

Status effects automatically display as colored icons on party status cards:
- Icons appear in the status icons container
- Color-coded by effect type
- Hover for state information (basic implementation)

## Testing Checklist

- [ ] Electrocuted: Verify damage multipliers apply correctly
- [ ] Burning: Test stack accumulation and damage scaling
- [ ] Bleed: Test accumulation and proc damage trigger
- [ ] Chilled: Verify turn skipping works
- [ ] Berserk: Test both damage multipliers
- [ ] Taunt: Verify AI targets taunting battlers
- [ ] Marked: Test bonus damage and state removal
- [ ] Protected: Test shield absorption and break mechanic
- [ ] Visual effects: Verify VFX scenes work
- [ ] UI: Check status icons display correctly
- [ ] State cleanup: Verify states expire correctly

## Balance Considerations

### Default Values (can be adjusted in .tres files):
- **Electrocuted**: 2 turns, 1.5x damage taken, 0.5x damage dealt
- **Burning**: 3 turns, 3 damage per stack, max 10 stacks
- **Bleed**: Infinite duration, 20% max HP proc, 10% accumulation per damage
- **Chilled**: 1 turn skip
- **Berserk**: 2 turns, 1.5x damage dealt, 1.25x damage taken
- **Taunt**: 2 turns, never breaks from damage
- **Marked**: 3 turns, 1.5x bonus damage, removes after hit
- **Protected**: 20 HP shield, persists until broken

## Future Enhancements

Potential additions:
- Status immunity (resistance to specific effects)
- Status spreading (e.g., burning spreads to adjacent)
- Status combinations (unique interactions between effects)
- More sophisticated tooltips with detailed information
- Status effect priority system
- Status cure items and abilities