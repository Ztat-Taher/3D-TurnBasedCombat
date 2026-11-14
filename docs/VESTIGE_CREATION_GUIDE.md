# Vestige Creation Guide

## Overview

Vestiges are permanent modifiers (similar to relics/artifacts) that persist through battles, map nodes, and save/load. They can be global (party-wide) or per-character. Vestiges provide passive stat bonuses and trigger custom effects at specific combat moments.

## Quick Start

### Creating a Simple Stat-Boost Vestige

1. Navigate to `database/vestiges/resources/` and choose a rarity folder (common, uncommon, rare)
2. Copy an existing simple vestige like `gilded_seal.tres`
3. Rename the file (e.g., `my_vestige.tres`)
4. Open the file and update:
   - `uid` - Unique identifier (change to match filename)
   - `vestige_id` - Internal ID (snake_case, e.g., "my_vestige")
   - `vestige_name` - Display name (e.g., "My Vestige")
   - `description` - Effect description
   - Adjust stat multipliers (gold_multiplier, xp_multiplier, etc.)
5. Add to `vestige_library.tres` in the appropriate rarity array

### Creating a Trigger-Based Vestige

Trigger-based vestiges fire effects at specific combat moments (on damage, on turn start, etc.).

**Example: Start combat with +3 Attack**

1. Create a new .tres file in the appropriate rarity folder
2. Set up the resource:
```ini
[gd_resource type="Resource" script_class_name="Vestige" load_steps=3 format=3 uid="uid://my_vestige"]

[ext_resource type="Script" path="res://database/vestiges/vestige_template.gd" id="1_vest"]
[ext_resource type="Script" path="res://database/vestiges/effects/gain_stat_on_combat_start.gd" id="2_stat"]
[ext_resource type="Script" path="res://database/vestiges/trigger_hook.gd" id="3_hook"]

[sub_resource type="Resource" script_class_name="TriggerHook" id="TriggerHook_xxx"]
script = ExtResource("3_hook")
trigger_type = 0  # ON_COMBAT_START
effect_script_path = "res://database/vestiges/effects/gain_stat_on_combat_start.gd"
stat_to_gain = "attack"
amount = 3
is_temporary = true

[resource]
script = ExtResource("1_vest")
vestige_id = "my_vestige"
vestige_name = "My Vestige"
description = "Start each combat with +3 Attack."
scope = 1  # 0 = GLOBAL, 1 = PER_CHARACTER
rarity = 1  # 0 = COMMON, 1 = UNCOMMON, 2 = RARE
# ... other properties ...
trigger_hooks = Array[Resource]([SubResource("TriggerHook_xxx")])
```

## Vestige Properties

### Core Properties

- **vestige_id**: Internal unique identifier (snake_case)
- **vestige_name**: Display name shown in UI
- **description**: Effect description
- **scope**: 0 = GLOBAL (party-wide), 1 = PER_CHARACTER
- **rarity**: 0 = COMMON, 1 = UNCOMMON, 2 = RARE, 3 = BOSS, 4 = EVENT, 5 = SHOP
- **icon**: Texture2D for UI display
- **base_price**: Shop price (if purchasable)
- **max_stacks**: Maximum number of copies allowed
- **stack_behavior**: How stacking works (refer to Vestige.StackBehavior enum)

### Passive Stat Modifiers

These modifiers apply automatically when the vestige is equipped:

- **max_health_bonus**: Flat HP increase
- **attack_bonus**: Flat attack increase
- **defense_bonus**: Flat defense increase
- **agility_bonus**: Flat agility increase
- **max_ap_bonus**: Flat AP increase
- **ap_regen_bonus**: AP regeneration increase
- **max_health_percent**: Percentage HP multiplier (1.0 = 100%)
- **attack_percent**: Percentage attack multiplier
- **defense_percent**: Percentage defense multiplier
- **agility_percent**: Percentage agility multiplier
- **damage_dealt_multiplier**: Damage output multiplier
- **damage_taken_multiplier**: Damage received multiplier
- **healing_multiplier**: Healing received multiplier
- **xp_multiplier**: XP gained multiplier
- **gold_multiplier**: Gold gained multiplier
- **cards_drawn_per_turn**: Extra cards drawn each turn
- **starting_hand_size**: Additional starting hand cards
- **ap_cost_reduction**: Reduces card AP costs (minimum 0)

### Drop Configuration

- **can_drop_from_elites**: True if available from elite enemies
- **can_drop_from_bosses**: True if available from bosses
- **can_drop_from_treasure**: True if available from treasure chests
- **can_drop_from_events**: True if available from map events
- **can_be_purchased**: True if available in shops
- **can_drop_from_rest_sites**: True if available at rest sites

## Trigger Hooks

Trigger hooks define when a vestige effect fires.

### Available Trigger Types

```gdscript
enum TriggerType {
    ON_COMBAT_START,      # 0
    ON_COMBAT_END,        # 1
    ON_TURN_START,        # 2
    ON_TURN_END,          # 3
    ON_CARD_PLAY,         # 4
    ON_DAMAGE_DEALT,      # 5
    ON_DAMAGE_TAKEN,      # 6
    ON_HEAL,              # 7
    ON_STATE_APPLIED,     # 8
    ON_STATE_REMOVED,     # 9
    ON_ENEMY_DEFEAT,      # 10
    ON_LOW_HP,            # 11
    ON_HIGH_HP            # 12
}
```

### Trigger Hook Properties

When creating a TriggerHook sub-resource:

- **trigger_type**: Which event triggers the effect (see enum above)
- **effect_script_path**: Path to the effect script (e.g., "res://database/vestiges/effects/gain_stat_on_combat_start.gd")
- **condition_script_path**: (Optional) Path to a condition script that determines if the effect should trigger
- **parameters**: Dictionary of parameters passed to the effect script

**Direct field parameters** (can be set directly on the hook instead of in parameters dict):
- For GainStatOnCombatStart: `stat_to_gain`, `amount`, `is_temporary`, `apply_once`
- For GainBlockOnTrigger: `block_amount`, `apply_to`, `trigger_limit`
- For DealDamageOnTrigger: `damage_amount`, `target_type`, `trigger_limit`
- For HealOnDeath: `heal_percentage`, `trigger_limit`
- For HPThresholdCondition: `threshold_percent`, `trigger_when_below`

## Built-in Effects

### GainStatOnCombatStart
Adds a stat bonus at combat start (can be temporary).

**Parameters:**
- `stat_to_gain`: "attack", "defense", "agility", or "max_health"
- `amount`: Amount to add
- `is_temporary`: If true, remove at combat end
- `apply_once`: If true, only apply once per combat; if false, can reapply each trigger

**Use case:** Vajra (War Banner), Odd Mushroom (Cornered Shield)

### GainBlockOnTrigger
Applies block/protected shields when triggered.

**Parameters:**
- `block_amount`: Number of shield hits
- `apply_to`: "self" or "all_allies"
- `trigger_limit`: -1 = unlimited, or maximum triggers per combat

**Use case:** Frozen Egg (Bastion Emblem)

### DealDamageOnTrigger
Deals damage to enemies when triggered.

**Parameters:**
- `damage_amount`: Damage to deal
- `target_type`: "random_enemy", "all_enemies", or "self"
- `trigger_limit`: -1 = unlimited, or maximum triggers per combat

**Use case:** Crystal Core (Reactive Emblem), Burning Ring (Barbed Circlet)

### HealOnDeath
Heals to a percentage of max HP when would die.

**Parameters:**
- `heal_percentage`: 0.5 = 50% of max HP
- `trigger_limit`: Typically 1 (once per combat)

**Use case:** Lizard Tail (Phoenix Feather)

### ApplyStateOnTrigger
Applies a state effect when triggered.

**Parameters:**
- `state_resource_path`: Path to state resource (e.g., "res://database/states/resources/burning_state.tres")
- `apply_to_target`: If true, apply to target from context; if false, apply to self
- `trigger_limit`: -1 = unlimited, or maximum triggers per combat

**Use case:** Can apply Burning, Chilled, or other states

## Built-in Conditions

### HPThresholdCondition
Triggers only when HP is at or below/above a threshold.

**Parameters:**
- `threshold_percent`: 0.0 to 1.0 (0.5 = 50%)
- `trigger_when_below`: If true, trigger when HP ≤ threshold; if false, trigger when HP ≥ threshold

**Use case:** Odd Mushroom (Cornered Shield)

## Creating Custom Effects

If the built-in effects don't meet your needs, create a custom effect:

1. Create a new script in `database/vestiges/effects/` (e.g., `my_custom_effect.gd`)
2. Extend `VestigeEffect`:
```gdscript
class_name MyCustomEffect
extends VestigeEffect

var my_param: int = 5

func execute(vestige: Vestige, battler: Battler, context: Dictionary) -> void:
    # Get parameters from hook
    var params = context.get("hook_parameters", {})
    my_param = params.get("my_param", 5)
    
    # Implement your effect logic
    if battler:
        # Do something with battler
        pass
```

3. Reference it in your vestige's TriggerHook:
```ini
effect_script_path = "res://database/vestiges/effects/my_custom_effect.gd"
my_param = 10
```

## Creating Custom Conditions

If you need custom trigger conditions:

1. Create a new script in `database/vestiges/conditions/` (e.g., `my_custom_condition.gd`)
2. Extend `VestigeCondition`:
```gdscript
class_name MyCustomCondition
extends VestigeCondition

var my_threshold: int = 5

func should_trigger(_vestige: Vestige, battler: Battler, context: Dictionary) -> bool:
    var params = context.get("hook_parameters", {})
    my_threshold = params.get("my_threshold", 5)
    
    # Return true if condition is met
    if battler and battler.current_health >= my_threshold:
        return true
    return false
```

3. Reference it in your vestige's TriggerHook:
```ini
condition_script_path = "res://database/vestiges/conditions/my_custom_condition.gd"
my_threshold = 10
```

## Adding to the Library

After creating a vestige, add it to `database/vestiges/vestige_library.tres`:

```ini
[resource]
script = ExtResource("1_lib123")
common_vestiges = Array[Resource]([
    Resource("res://database/vestiges/resources/common/gilded_seal.tres"),
    Resource("res://database/vestiges/resources/common/my_vestige.tres"),
    # ... other common vestiges
])
uncommon_vestiges = Array[Resource]([
    # ... uncommon vestiges
])
rare_vestiges = Array[Resource]([
    # ... rare vestiges
])
boss_vestiges = []
event_vestiges = []
shop_vestiges = []
```

## Context Dictionary

When triggers fire, a context dictionary is passed to effects and conditions with relevant data:

- **ON_COMBAT_START**: `{"battle_manager": BattleManager}`
- **ON_COMBAT_END**: `{"battle_manager": BattleManager}`
- **ON_TURN_START**: `{"battle_manager": BattleManager}`
- **ON_TURN_END**: `{"battle_manager": BattleManager}`
- **ON_CARD_PLAY**: `{"card": Card, "target": Battler, "battle_manager": BattleManager}`
- **ON_DAMAGE_DEALT**: `{"target": Battler, "damage": int, "battle_manager": BattleManager}`
- **ON_DAMAGE_TAKEN**: `{"attacker": Battler, "damage": int, "damage_amount": int, "damage_type": String, "element": String, "battle_manager": BattleManager}`
- **ON_HEAL**: `{"heal_amount": int, "battle_manager": BattleManager}`
- **ON_STATE_APPLIED**: `{"state": State, "state_name": String, "target": Battler, "battle_manager": BattleManager}`
- **ON_STATE_REMOVED**: `{"state_name": String, "battle_manager": BattleManager}`
- **ON_ENEMY_DEFEAT**: `{"enemy": Battler, "battle_manager": BattleManager}`

## Best Practices

1. **Use existing effects when possible** - The built-in effects cover most common patterns
2. **Use parameters for configuration** - Set effect parameters in the hook rather than hardcoding values
3. **Choose appropriate rarity** - Stronger effects should be rarer
4. **Consider scope carefully** - Global effects affect the whole party, per-character effects are more personal
5. **Test with different triggers** - Some effects work better with specific trigger types
6. **Write clear descriptions** - Players should understand what the vestige does from the description alone
7. **Use the trigger_limit** - Prevent effects from triggering too frequently (especially damage/heal effects)

## Examples

### Example 1: Simple Gold Multiplier
```ini
[resource]
vestige_id = "fortune_coin"
vestige_name = "Fortune Coin"
description = "Gold rewards increased by 25%."
scope = 0  # GLOBAL
rarity = 0  # COMMON
gold_multiplier = 1.25
trigger_hooks = []
```

### Example 2: Damage on Turn End
```ini
[sub_resource type="Resource" script_class_name="TriggerHook" id="TriggerHook_xxx"]
script = ExtResource("3_hook")
trigger_type = 3  # ON_TURN_END
effect_script_path = "res://database/vestiges/effects/deal_damage_on_trigger.gd"
damage_amount = 2
target_type = "random_enemy"

[resource]
vestige_id = "viper_token"
vestige_name = "Viper Token"
description = "Deal 2 damage to a random enemy at the end of each turn."
scope = 1  # PER_CHARACTER
rarity = 1  # UNCOMMON
trigger_hooks = Array[Resource]([SubResource("TriggerHook_xxx")])
```

### Example 3: Conditional Stat Boost
```ini
[sub_resource type="Resource" script_class_name="TriggerHook" id="TriggerHook_xxx"]
script = ExtResource("3_hook")
trigger_type = 2  # ON_TURN_START
effect_script_path = "res://database/vestiges/effects/gain_stat_on_combat_start.gd"
condition_script_path = "res://database/vestiges/conditions/hp_threshold_condition.gd"
stat_to_gain = "attack"
amount = 3
is_temporary = true
apply_once = false
threshold_percent = 0.25
trigger_when_below = true

[resource]
vestige_id = "berserker_amulet"
vestige_name = "Berserker Amulet"
description = "When at or below 25% HP, gain +3 Attack each turn."
scope = 1  # PER_CHARACTER
rarity = 2  # RARE
trigger_hooks = Array[Resource]([SubResource("TriggerHook_xxx")])
```

## Troubleshooting

### Effect not triggering
- Check trigger_type matches the event you expect
- Verify effect_script_path is correct
- If using a condition, verify it returns true

### Effect triggering but not working
- Check if battle_manager is available in context (some triggers may not have it)
- Verify effect parameters are set correctly
- Add debug prints to trace execution

### Vestige not appearing in rewards
- Check can_drop_from_* flags are set appropriately
- Verify vestige is added to the correct rarity array in vestige_library.tres
- Check vestige scope (GLOBAL vs PER_CHARACTER)

### Script instantiation errors
- Ensure effect/condition scripts don't use @tool (they need to be instantiable at runtime)
- Verify scripts extend VestigeEffect or VestigeCondition
- Check for syntax errors in custom scripts
