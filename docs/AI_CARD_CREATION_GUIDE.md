# AI Card Creation Guide

This guide provides AI agents with precise instructions for creating new cards in the turn-based combat system. It is designed to be machine-readable and actionable.

## System Architecture Overview

The card system has two parallel configuration methods:
1. **Legacy Metadata System** (backward compatible)
2. **New CardConfig System** (recommended, fully featured)

AI agents should prefer the CardConfig system for new cards as it provides complete control over all card behaviors.

## Deck Management

**Important:** There is no longer a central CardDatabase. Cards are managed as individual CardData resources that are passed directly to the deck system.

**Deck Composition:**
- Cards are loaded as CardData resources from the `database/cards/` directory
- Decks are composed by passing an array of CardData resources to `CardIntegration.initialize_for_player()`
- No card ID lookup system exists - cards are referenced directly by their resource objects

**When creating cards for a deck:**
1. Create the CardData resource file
2. Create all associated CardConfig and sub-resources
3. Link resources in Godot Editor
4. Load the CardData resource and pass it to the deck initialization system

## Card Creation Process

### Step 1: Choose Creation Method

**For AI Agents: Always use CardConfig system** unless specifically requested to use legacy metadata.

### CardData Resource Configuration

**Required Fields:**
- `card_id`: Unique identifier (snake_case)
- `name`: Display name
- `cost`: AP cost (integer)
- `attack`: Base damage value (integer)  
- `health`: Base heal value (integer)
- `play_kind`: 0 = EFFECT, 1 = UNIT, 2 = PERSISTENT
- `card_config`: Reference to CardConfig resource (set in Godot Editor)
- `metadata`: Dictionary (only if not using CardConfig)
- `spell_effects`: Array of SpellEffect resources (legacy system)

**Important:** Set `card_config` to `null` in the .tres file and add a comment indicating what should be set in the Godot Editor. This avoids circular reference issues during file loading.

### Step 3: Create CardConfig Resource

**File Location:** `database/card_configs/[card_name]_config.tres`

**Required Script Reference:**
```
[ext_resource type="Script" path="res://battle-manager/card_combat/resources/card_config.gd" id="1"]
script = ExtResource("1")
```

**Important Note:** Resource references (like CardEffect, VFXConfig, etc.) should be set in the Godot Editor, not directly in the .tres file. Set the properties to `null` in the .tres file and add comments indicating what should be set in the editor. This avoids circular reference issues.

## CardConfig Property Configuration

### Animation Configuration

**Required Fields:**
- `actor_animation`: Animation name (string)
  - Common values: "attack", "kick", "skill-animations/strong-attack"
  - Check battler animation tree for available animations
- `animation_priority`: Integer (0-10, higher = more important)
- `animation_blend_time`: Float (0.0-1.0 seconds)
- `animation_speed`: Float (0.5-2.0 multiplier)
- `fallback_animation`: Animation name if primary not found
- `animation_layer`: "full_body", "upper_body", or "additive"

**Animation Events (Optional):**
- `animation_events`: Array of AnimationEvent resources
  - Each event specifies trigger time (0.0-1.0 of animation)
  - Event types: EFFECT_TRIGGER, SOUND_PLAY, VFX_SPAWN, CAMERA_EFFECT, etc.

### Targeting Configuration

**Target Type Enum:**
- 0 = SELF (effect applied to caster only)
- 1 = SINGLE_ENEMY (targets one enemy)
- 2 = ALL_ENEMIES (AOE on all enemies)
- 3 = SINGLE_ALLY (targets one ally including self)
- 4 = ALL_ALLIES (AOE on all allies)
- 5 = SINGLE_TARGET (can target any single unit)
- 6 = ALL_UNITS (AOE on all units)
- 7 = ALL_ALLIES_SELF (AOE on all allies including self)

**Selection Mode Enum:**
- 0 = MANUAL (player manually selects target)
- 1 = AUTO_CLOSEST (automatically targets closest enemy)
- 2 = AUTO_RANDOM (randomly selects valid target)
- 3 = AUTO_WEAKEST (targets weakest enemy)
- 4 = AUTO_STRONGEST (targets strongest enemy)

**Required Fields:**
- `target_type`: Integer (0-7 from enum above)
- `target_selection_mode`: Integer (0-4 from enum above)
- `target_filter`: String (filter conditions, empty for none)
- `requires_los`: Boolean (line of sight requirement)

### Effect Configuration

**Required Fields:**
- `primary_effect`: CardEffect resource reference
- `secondary_effects`: Array of CardEffect resources (empty if none)
- `effect_timing`: Integer from EffectTiming enum
- `effect_conditions`: Array of EffectCondition resources (empty if none)

**Effect Timing Enum:**
- 0 = IMMEDIATE (effect triggers immediately)
- 1 = AFTER_ANIMATION (effect triggers after animation completes)
- 2 = ON_HIT (effect triggers on hit frame)
- 3 = ON_IMPACT (effect triggers on impact with target)
- 4 = CHANNEL_START (effect triggers when channeling starts)
- 5 = CHANNEL_END (effect triggers when channeling ends)

### CardEffect Resource Configuration

**File Location:** `database/card_effects/[effect_name]_effect.tres`

**Required Script:**
```
[ext_resource type="Script" path="res://battle-manager/card_combat/resources/card_effect.gd" id="1"]
script = ExtResource("1")
```

**Required Fields:**
- `effect_type`: Integer from EffectType enum
- `value`: Integer (base effect value)
- `targeting`: Integer from EffectTargeting enum
- `scaling`: Dictionary (stat scaling, e.g., {"attack": 0.5})
- `conditions`: Array of EffectCondition resources (empty if none)

**Effect Type Enum:**
- 0 = DAMAGE (deal damage to target(s))
- 1 = HEAL (heal target(s))
- 2 = SHIELD (apply shield/defense to target(s))
- 3 = BUFF (apply buff to target(s))
- 4 = DEBUFF (apply debuff to target(s))
- 5 = SUMMON (summon a unit)
- 6 = KNOCKBACK (knock target back)
- 7 = STUN (stun target(s))
- 8 = DRAIN (drain health from target)
- 9 = LETHAL (instant kill if target below threshold)
- 10 = CUSTOM (custom effect requires script)

**Effect Targeting Enum:**
- 0 = ACTOR (effect applied to actor)
- 1 = TARGET (effect applied to primary target)
- 2 = ALL_ENEMIES (effect applied to all enemies)
- 3 = ALL_ALLIES (effect applied to all allies)
- 4 = ALL_UNITS (effect applied to all units)
- 5 = RANDOM_ENEMY (effect applied to random enemy)
- 6 = RANDOM_ALLY (effect applied to random ally)
- 7 = CUSTOM_SELECTION (custom targeting logic)

**Optional Fields:**
- `is_percentage`: Boolean (if true, value is percentage 0-100)
- `delay`: Float (delay before effect triggers in seconds)
- `duration`: Float (effect duration for temporary effects)
- `stack_count`: Integer (number of stacks for stacking effects)
- `can_crit`: Boolean (whether effect can critical hit)
- `crit_multiplier`: Float (critical hit multiplier)

### Visual Effect Configuration

**Required Fields:**
- `vfx_on_actor`: VFXConfig resource (null if none)
- `vfx_on_target`: VFXConfig resource (null if none)
- `vfx_on_projectile`: VFXConfig resource (null if none)
- `camera_effects`: CameraEffectConfig resource (null if none)
- `screen_effects`: ScreenEffectConfig resource (null if none)

**VFXConfig Resource Configuration:**

**File Location:** `database/vfx_configs/[vfx_name]_vfx.tres`

**Required Script:**
```
[ext_resource type="Script" path="res://battle-manager/card_combat/resources/vfx_config.gd" id="1"]
script = ExtResource("1")
```

**Required Fields:**
- `vfx_scene`: String (path to VFX scene file)
- `vfx_spawn_point`: Integer from VFXSpawnPoint enum
- `vfx_duration`: Float (how long VFX plays in seconds)
- `vfx_scale`: Vector3 (scale of VFX)
- `vfx_color`: Color (color modulation)
- `attach_to_target`: Boolean (whether VFX follows target)

**VFX Spawn Point Enum:**
- 0 = ACTOR (spawn at actor position)
- 1 = TARGET (spawn at target position)
- 2 = PROJECTILE (spawn on projectile)
- 3 = GROUND (spawn at ground level)
- 4 = AIR (spawn in air above target)
- 5 = CUSTOM (custom spawn point)

**Optional Fields:**
- `offset`: Vector3 (offset from spawn point)
- `rotation`: Vector3 (rotation offset)
- `random_offset_range`: Float (random position variation)
- `random_rotation_range`: Float (random rotation variation)
- `fade_in_duration`: Float (fade in time)
- `fade_out_duration`: Float (fade out time)
- `loop`: Boolean (whether VFX should loop)
- `emission_rate`: Float (emission rate for particle systems)
- `burst`: Boolean (whether to burst particles immediately)

### Camera Effect Configuration

**CameraEffectConfig Resource Configuration:**

**File Location:** `database/camera_effects/[camera_name]_camera.tres`

**Required Script:**
```
[ext_resource type="Script" path="res://battle-manager/card_combat/resources/camera_effect_config.gd" id="1"]
script = ExtResource("1")
```

**Camera Shake Fields:**
- `camera_shake_enabled`: Boolean
- `shake_intensity`: Float (0.0-2.0)
- `shake_duration`: Float (0.0-2.0 seconds)
- `shake_style`: Integer (0=RANDOM, 1=DIRECTIONAL, 2=ROTATIONAL)
- `shake_frequency`: Float (1.0-50.0)
- `shake_decay`: Float (0.0-2.0)

**Camera Zoom Fields:**
- `camera_zoom_enabled`: Boolean
- `zoom_amount`: Float (1.0 = no zoom, <1.0 = zoom out, >1.0 = zoom in)
- `zoom_duration`: Float (0.0-2.0 seconds)
- `zoom_delay`: Float (delay before zoom starts)
- `zoom_return`: Boolean (whether to return to original zoom)

**Camera Tracking Fields:**
- `tracking_mode`: Integer (0=NONE, 1=ACTOR, 2=TARGET, 3=BOTH, 4=PROJECTILE, 5=CUSTOM)
- `tracking_speed`: Float (1.0-20.0)
- `tracking_offset`: Vector3 (offset from tracked target)
- `tracking_duration`: Float (how long to track in seconds)

**Optional Fields:**
- `camera_tilt`: Vector3 (camera tilt/rotation)
- `tilt_duration`: Float (tilt animation duration)
- `tilt_return`: Boolean (whether to return to original tilt)
- `camera_fov`: Float (FOV override, -1 = no change)
- `fov_duration`: Float (FOV change duration)

### Screen Effect Configuration

**ScreenEffectConfig Resource Configuration:**

**File Location:** `database/screen_effects/[screen_name]_screen.tres`

**Required Script:**
```
[ext_resource type="Script" path="res://battle-manager/card_combat/resources/screen_effect_config.gd" id="1"]
script = ExtResource("1")
```

**Required Fields:**
- `effect_type`: Integer from EffectType enum
- `effect_duration`: Float (how long effect lasts in seconds)
- `effect_intensity`: Float (0.0-2.0 intensity)
- `effect_color`: Color (color for flash effects)

**Effect Type Enum:**
- 0 = NONE (no effect)
- 1 = FLASH (screen flash)
- 2 = TIME_SLOW (time slow motion)
- 3 = CHROMATIC (chromatic aberration)
- 4 = VIGNETTE (vignette effect)
- 5 = GRAIN (film grain)
- 6 = BLUR (motion blur)
- 7 = CUSTOM (custom effect)

**Optional Fields:**
- `fade_in`: Float (fade in duration)
- `fade_out`: Float (fade out duration)
- `time_scale`: Float (time scale for time slow effects)
- `affect_physics`: Boolean (whether time slow affects physics)

### Projectile Configuration

**Required Fields:**
- `projectile_enabled`: Boolean
- `projectile_scene`: String (path to projectile scene)
- `projectile_speed`: Float (travel speed in units/second)
- `projectile_lifetime`: Float (maximum projectile lifetime in seconds)
- `projectile_arc`: Float (arc height for projectile trajectory)
- `projectile_spawn_point`: String ("actor", "weapon", "custom")

### Audio Configuration

**Required Fields:**
- `cast_sound`: AudioConfig resource (null if none)
- `hit_sound`: AudioConfig resource (null if none)
- `impact_sound`: AudioConfig resource (null if none)
- `loop_sound`: AudioConfig resource (null if none)
- `voice_line`: String (character voice line path, empty if none)

**AudioConfig Resource Configuration:**

**File Location:** `database/audio_configs/[audio_name]_audio.tres`

**Required Script:**
```
[ext_resource type="Script" path="res://battle-manager/card_combat/resources/audio_config.gd" id="1"]
script = ExtResource("1")
```

**Required Fields:**
- `audio_stream`: String (path to audio file)
- `volume`: Float (0.0-2.0)
- `pitch`: Float (0.1-4.0)
- `bus`: String (audio bus name, default "Master")

**Optional Fields:**
- `loop`: Boolean (whether audio should loop)
- `random_pitch_variation`: Float (0.0-1.0 for variety)
- `random_volume_variation`: Float (0.0-1.0 for variety)
- `delay`: Float (delay before playing in seconds)
- `fade_in_duration`: Float (fade in time)
- `fade_out_duration`: Float (fade out time)
- `max_distance`: Float (max 3D distance for attenuation)
- `attenuation`: Float (attenuation factor)
- `doppler`: Float (doppler effect strength)

### QTE Configuration

**Required Fields:**
- `qte_type`: Integer from QTEType enum
- `qte_difficulty`: Float (0.0-1.0 difficulty level)
- `qte_timing`: Integer from QTETiming enum
- `qte_window_duration`: Float (time window for QTE input in seconds)
- `qte_success_multiplier`: Float (damage/effect multiplier on success)
- `qte_failure_multiplier`: Float (damage/effect multiplier on failure)

**QTE Type Enum:**
- 0 = NONE (no QTE)
- 1 = TIMING (timing-based QTE - press at right moment)
- 2 = BUTTON_MASH (button mash QTE - rapid pressing)
- 3 = SEQUENCE (sequence input QTE - specific button order)

**QTE Timing Enum:**
- 0 = BEFORE_ATTACK (QTE before attack animation)
- 1 = ON_HIT_FRAME (QTE on hit frame)
- 2 = AFTER_ATTACK (QTE after attack animation)

**QTE Type-Specific Fields:**
- For SEQUENCE type: `qte_sequence`: Array[String] (button sequence)
- For BUTTON_MASH type: `qte_mash_count`: Integer (required button presses), `qte_mash_window`: Float (time window)

### Damage and Stats Configuration

**Required Fields:**
- `base_damage`: Integer (base damage value)
- `damage_scaling`: Dictionary (stat scaling, e.g., {"attack": 0.5, "magic": 0.3})
- `damage_type`: Integer from DamageType enum
- `heal_amount`: Integer (base healing amount)
- `shield_amount`: Integer (shield/defense amount)
- `stat_modifiers`: Dictionary (temporary stat changes)

**Damage Type Enum:**
- 0 = PHYSICAL (physical damage)
- 1 = MAGICAL (magical damage)
- 2 = TRUE_DAMAGE (true damage - ignores defense)

### State and Debuff Configuration

**Required Fields:**
- `applies_states`: Array of StateConfig resources (empty if none)
- `applies_self_states`: Array of StateConfig resources (empty if none)
- `state_chance`: Float (0.0-1.0 chance to apply states)
- `state_duration`: Integer (duration in turns)

**StateConfig Resource Configuration:**

**File Location:** `database/state_configs/[state_name]_state.tres`

**Required Script:**
```
[ext_resource type="Script" path="res://battle-manager/card_combat/resources/state_config.gd" id="1"]
script = ExtResource("1")
```

**Required Fields:**
- `state_id`: String (reference to state resource)
- `state_name`: String (display name of the state)
- `duration`: Integer (duration in turns)
- `chance`: Float (application chance 0.0-1.0)
- `stacking_behavior`: Integer from StackingBehavior enum

**Stacking Behavior Enum:**
- 0 = NONE (no stacking allowed)
- 1 = REFRESH (refresh duration on reapply)
- 2 = ADDITIVE (add to existing duration)
- 3 = MULTIPLICATIVE (multiply existing effect)
- 4 = INDEPENDENT (multiple instances can exist independently)

**Optional Fields:**
- `max_stacks`: Integer (maximum number of stacks)
- `can_dispel`: Boolean (whether state can be dispelled)
- `is_purgeable`: Boolean (whether state can be purged)
- `applies_to_actor`: Boolean (whether state applies to actor instead of target)
- `spread_on_contact`: Boolean (whether state spreads on contact)
- `spread_chance`: Float (chance to spread on contact)
- `spread_range`: Float (range for spreading)
- `tick_damage`: Integer (damage per tick for DoT effects)
- `tick_interval`: Float (time between ticks in seconds)
- `tick_count`: Integer (number of ticks, 0 = use duration)
- `remove_on_damage`: Boolean (whether state removes when taking damage)
- `remove_on_move`: Boolean (whether state removes when moving)
- `immunity_duration`: Integer (immunity duration after state ends)

### Card Metadata

**Required Fields:**
- `card_rarity`: Integer from CardRarity enum
- `card_element`: Integer from Element enum
- `card_tags`: Array[String] (tags for filtering and grouping)
- `card_description`: String (flavor text and description)

**Card Rarity Enum:**
- 0 = COMMON (common cards)
- 1 = UNCOMMON (uncommon cards)
- 2 = RARE (rare cards)
- 3 = EPIC (epic cards)
- 4 = LEGENDARY (legendary cards)

**Element Enum:**
- 0 = NONE (no element)
- 1 = FIRE (fire element)
- 2 = ICE (ice element)
- 3 = LIGHTNING (lightning element)
- 4 = EARTH (earth element)
- 5 = WIND (wind element)
- 6 = LIGHT (light element)
- 7 = DARK (dark element)

## AI Agent Card Creation Process

### Phase 1: File Creation
AI agents create all necessary .tres files with null resource references and editor comments.

### Phase 2: Godot Editor Configuration
After file creation, resources must be linked in the Godot Editor:
1. Open the project in Godot Editor
2. Navigate to the created resource files
3. Set resource references (CardConfig → CardEffect, VFXConfig, etc.)
4. Validate configurations in the inspector
5. Test the card in the battle system

### Example Request: "Create a lightning bolt card that deals 40 damage to a single enemy with a 0.5 difficulty timing QTE, stun chance of 30%, rare rarity, and lightning element"

### AI Agent Process:

1. **Create CardData resource** (`database/cards/skills/lightning_bolt.tres`)
   - Set basic properties (card_id, name, cost, attack, etc.)
   - Set card_config to null with comment
   - Leave metadata and spell_effects empty

2. **Create CardConfig resource** (`database/card_configs/lightning_bolt_config.tres`)
   - Configure targeting as SINGLE_ENEMY (1)
   - Set base_damage to 40
   - Configure QTE as TIMING (1) with difficulty 0.5
   - Set appropriate animation
   - Set primary_effect to null with comment
   - Set vfx_on_target to null with comment
   - Add fire element and rarity
   - Set applies_states to null with comment for stun state

3. **Create CardEffect resource** (`database/card_effects/lightning_damage_effect.tres`)
   - Set effect_type to DAMAGE (0)
   - Set value to 40
   - Set targeting to TARGET (1)
   - Add magic scaling

4. **Create VFXConfig resource** (`database/vfx_configs/lightning_vfx.tres`)
   - Set vfx_scene path
   - Configure spawn point and timing

5. **Create StateConfig resource** (`database/state_configs/stun_state.tres`)
   - Set state_id to "stun"
   - Configure duration and chance

6. **Add editor comments** to all files indicating which resources should be linked in Godot Editor

7. **Provide completion instructions** to the user for Godot Editor setup

### Example Cards Created
The card database has been cleared for a fresh start with the new resource-driven system. Example cards will be created as needed when requested.

**Note:** Previous example cards (Lightning Bolt, Fire Explosion, etc.) have been removed as part of the database reset. The system is now ready for new card creation using the updated resource architecture.

### AI Agent Template Example

### Request Format
When requesting card creation, AI agents should provide:

```
Create a card with the following specifications:
- Card Name: [name]
- Card Type: [attack/skill/heal/buff/debuff]
- Target: [single enemy/all enemies/single ally/all allies/self]
- Damage/Heal: [value]
- Cost: [AP cost]
- Animation: [animation name]
- QTE: [type and difficulty]
- Effects: [list of effects]
- States: [states to apply]
- Visual Effects: [VFX requirements]
- Audio: [sound requirements]
- Rarity: [rarity tier]
- Element: [element type]
- Special Conditions: [any special requirements]
```

### Creation Checklist

AI agents must ensure:

1. **File Structure:**
   - CardData in `database/cards/[category]/[card_name].tres`
   - CardConfig in `database/card_configs/[card_name]_config.tres`
   - Related resources in appropriate subdirectories

2. **Resource References:**
   - All resource references use proper ExtResource format
   - Script references are correct and paths are valid
   - Circular references are avoided

3. **Enum Values:**
   - All enum values are within valid ranges
   - Enums match the definitions in this guide
   - Default values are used where appropriate

4. **Configuration Completeness:**
   - All required fields are populated
   - Optional fields are included when relevant
   - Validation would pass (check each resource's validate() method)

5. **Integration:**
   - CardData properly references CardConfig
   - CardConfig references all sub-resources correctly
   - File paths are relative to project root (res://)

## Example Card Creation Process

### Example Request: "Create a fireball card that deals 50 damage to all enemies with a 0.4 difficulty timing QTE"

### AI Agent Process:

1. **Create CardData resource** (`database/cards/skills/fireball_burst.tres`)
2. **Create CardConfig resource** (`database/card_configs/fireball_burst_config.tres`)
3. **Create CardEffect resource** (`database/card_effects/fireball_damage_effect.tres`)
4. **Configure targeting as ALL_ENEMIES (2)**
5. **Set base_damage to 50**
6. **Configure QTE as TIMING (1) with difficulty 0.4**
7. **Set appropriate animation and VFX**
8. **Add fire element and rarity**
9. **Validate all configurations**

## Common Card Patterns

### Basic Attack Card
- Target: SINGLE_ENEMY
- Effect: DAMAGE with attack stat scaling
- Animation: "attack"
- QTE: TIMING with 0.3-0.5 difficulty
- No states or complex effects

### AOE Attack Card
- Target: ALL_ENEMIES
- Effect: DAMAGE (possibly with multiplier)
- Animation: "skill-animations/strong-attack"
- QTE: TIMING with 0.4-0.6 difficulty
- Camera: Set enemy overview
- Screen: Damage flash

### Heal Card
- Target: SINGLE_ALLY or ALL_ALLIES
- Effect: HEAL
- Animation: "heal" or "cast"
- No QTE typically
- VFX: Healing aura on target
- Audio: Heal sound

### Buff Card
- Target: SINGLE_ALLY or ALL_ALLIES
- Effect: BUFF with stat modifiers
- Animation: "buff" or "cast"
- No QTE typically
- VFX: Buff glow on target
- Duration: 2-3 turns

### Debuff Card
- Target: SINGLE_ENEMY or ALL_ENEMIES
- Effect: DEBUFF + State application
- Animation: "debuff" or "cast"
- QTE: Optional timing QTE
- States: Apply poison/slow/etc.
- State chance: 0.5-0.75

## Validation and Testing

After creating a card, AI agents should:

1. **Check resource validation:**
   - Call `validate()` method on each resource
   - Fix any reported issues

2. **Verify file paths:**
   - Ensure all paths use `res://` format
   - Check that referenced files exist

3. **Test card integration:**
   - Add card to deck configuration
   - Verify card appears in UI
   - Test targeting and execution

4. **Check backward compatibility:**
   - Ensure existing cards still work
   - Test both CardConfig and metadata systems

## Troubleshooting

### Common Issues:

1. **Card not appearing in deck:**
   - Check card_id matches deck configuration
   - Verify CardData resource loads correctly
   - Ensure CardConfig reference is valid

2. **Effects not triggering:**
   - Check effect timing configuration
   - Verify conditions are being met
   - Ensure target selection is working

3. **Animation not playing:**
   - Verify animation name exists in battler
   - Check fallback animation is set
   - Ensure animation priority is appropriate

4. **QTE not triggering:**
   - Check qte_type is not NONE
   - Verify QTE timing configuration
   - Ensure QTE difficulty is valid (0.0-1.0)

5. **VFX not appearing:**
   - Check VFX scene path is correct
   - Verify spawn point configuration
   - Ensure VFX duration is > 0

## Advanced Features

### Conditional Effects
Use EffectCondition resources to create cards that only work under specific circumstances:
- Low health targets
- Specific states present
- Random chance execution
- Custom conditions

### Multi-Effect Cards
Use secondary_effects array to create cards with multiple effects:
- Primary damage + secondary heal
- Main effect + conditional bonus
- Complex effect chains

### Animation Events
Use AnimationEvent resources for precise timing:
- Damage on specific frame
- Sound effects synchronized with animation
- VFX triggered at animation milestones
- Camera effects timed to animation beats

### State Combinations
Apply multiple states for complex debuffs:
- Poison + damage reduction
- Stun + vulnerability
- DoT + spread mechanics

## File Organization Best Practices

#### Directory Structure:
```
database/
├── cards/
│   ├── attacks/
│   ├── skills/
│   ├── heals/
│   ├── buffs/
│   └── debuffs/
├── card_configs/
├── card_effects/
├── vfx_configs/
├── audio_configs/
├── camera_effects/ (optional - can be embedded in CardConfig)
├── screen_effects/ (optional - can be embedded in CardConfig)
└── state_configs/ (optional - can be embedded in CardConfig)
```

**Note:** Some directories (camera_effects, screen_effects, state_configs) are optional as these resources can be embedded directly in CardConfig rather than stored as separate files. Use separate files only when the same resource is shared across multiple cards.

**Current Database State:**
- `database/cards/` - Empty (needs creation)
- `database/card_configs/` - Empty (needs creation)
- `database/card_effects/` - Empty (needs creation)
- `database/vfx_configs/` - Empty (needs creation)
- `database/audio_configs/` - Empty (needs creation)
- `database/items/` - Contains item resources (preserve)
- `database/states/` - Contains state resources (preserve)
- `database/troops/` - Contains troop resources (preserve)

AI agents should create directories as needed when adding new cards.

### Naming Conventions:
- Card files: `[card_name].tres`
- Config files: `[card_name]_config.tres`
- Effect files: `[effect_name]_effect.tres`
- VFX files: `[vfx_name]_vfx.tres`
- Audio files: `[audio_name]_audio.tres`
- State files: `[state_name]_state.tres`

### Resource IDs:
- Use snake_case for all IDs
- Keep IDs descriptive but concise
- Avoid special characters and spaces
- Maintain consistency across related resources

## Performance Considerations

1. **Resource Loading:**
   - Resources are loaded at runtime
   - Heavy VFX/audio should be used sparingly
   - Consider LOD for complex effects

2. **Effect Complexity:**
   - Limit secondary effects array size
   - Avoid deep condition nesting
   - Use simple conditions when possible

3. **Memory Management:**
   - VFX instances are auto-destroyed
   - Audio players are cleaned up after playback
   - Large resource chains may impact load times

## Extension Points

The system is designed for extensibility:

### Custom Effect Types:
- Add new enum values to EffectType
- Implement custom effect logic in CardEffect
- Update execute_effect_phase as needed

### Custom QTE Types:
- Add new enum values to QTEType
- Implement QTE logic in QTEManager
- Update execute_qte_phase as needed

### Custom Targeting Modes:
- Add new enum values to SelectionMode
- Implement targeting logic in CardConfig
- Update get_targets_for_card as needed

### Custom Animation Events:
- Add new enum values to AnimationEventType
- Implement event logic in AnimationEvent
- Update process_animation_events as needed

## Maintenance Notes

### When updating the core system:
1. Update this documentation
2. Maintain backward compatibility
3. Add migration tools if needed
4. Test existing cards
5. Update example resources

### When adding new features:
1. Document feature in this guide
2. Provide example configurations
3. Update validation methods
4. Add AI agent support
5. Test with various card types

## Implementation Notes for AI Agents

### Resource Script Architecture

The resource scripts in `battle-manager/card_combat/resources/` have been designed with the following considerations:

**AudioConfig:**
- Uses generic Node return type for audio players to handle both 2D and 3D audio
- Doppler tracking uses numeric values (0=DISABLED, 1=ENABLED) for Godot compatibility
- Audio players are auto-cleanup with optional fade effects
- Supports delayed playback via Timer nodes
- Type checking used for method availability across AudioStreamPlayer variants

**CameraEffectConfig:**
- Camera effects require a Camera3D node parameter for SceneTree access
- Uses fixed 60 FPS assumption for shake/tracking loops (avoiding get_process_delta_time())
- Async effects use `await camera.get_tree().process_frame` instead of `await get_tree().process_frame`
- Tween-based animations for smooth camera movements
- Resource classes cannot call Node methods directly - camera node must be passed as parameter

**CardIntegration:**
- No CardDatabase class - cards are passed as CardData arrays
- Deck initialization: `initialize_for_player(player_battler, deck_resources: Array[CardData])`
- Backward compatible with legacy metadata system for existing cards
- Removed `deck_card_ids` array - no longer uses ID-based lookup

**General Principles:**
- Resource classes cannot call Node methods directly - always pass Node as parameter
- Avoid circular references by setting resource properties to null in .tres files
- Use type checking (`is` operator) when working with base classes
- Test Godot parser/compilation after resource script changes
- Use Godot ternary syntax: `value_if_true if condition else value_if_false`

### Recent Bug Fixes (for reference)

The following issues were resolved in the resource scripts:

1. **AudioConfig Type Errors:** Fixed invalid casts between AudioStreamPlayer base class and 2D/3D subclasses by using separate branches and generic Node return type
2. **AudioConfig Doppler Tracking:** Fixed invalid enum members by using numeric values (0/1) instead of DISABLED/ENABLED constants
3. **CameraEffectConfig SceneTree Access:** Fixed "Function not found in base self" errors by calling `camera.get_tree()` instead of `get_tree()` in resource methods
4. **CameraEffectConfig Delta Time:** Fixed by using fixed 1.0/60.0 per-frame increment instead of `get_process_delta_time()`
5. **CardIntegration CardDatabase:** Removed references to non-existent CardDatabase class; changed to direct CardData array passing

When creating new resource scripts, follow these patterns to avoid similar issues.

This guide should be updated whenever the card system is modified to ensure AI agents can always create cards using the most current and accurate information.
