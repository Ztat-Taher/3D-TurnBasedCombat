# AI Card Creation Guide

This guide provides AI agents with precise instructions for creating new cards in the turn-based combat system. It is designed to be machine-readable and actionable.

## System Architecture Overview

The card system uses a **simplified two-resource architecture**:
1. **CardConfig** - Card-level configuration (targeting, animation, QTE, states, display assets)
2. **CardEffect** - Effect-level configuration (numeric values, scaling, damage type, element)

**Note:** The addon card_combat system (CardData, CombatDeck, CombatSession) has been deprecated and is no longer used. The game now uses only CardConfig and CardEffect resources directly.

## Deck Management

**Deck Composition:**
- Cards are loaded as CardConfig resources from the `database/card_configs/` directory
- Decks are composed by passing an array of CardConfig resources to `CardIntegration.initialize_for_player()`
- No card ID lookup system exists - cards are referenced directly by their resource objects
- Decks use SimplifiedDeck (lightweight deck management) instead of the addon's CombatDeck

**When creating cards for a deck:**
1. Create the CardConfig resource file
2. Create associated CardEffect resources
3. Link resources in the .tres files using ExtResource format
4. Add CardConfig to DeckResource.cards array
5. Load the DeckResource and pass it to the deck initialization system

## Card Creation Process

### Step 1: Create CardConfig Resource

**File Location:** `database/card_configs/[card_name]_config.tres`

**Required Script Reference:**
```
[ext_resource type="Script" path="res://scenes/battle/card_combat/resources/cards/card_config.gd" id="1"]
script = ExtResource("1")
```

**Note:** Resource references (like CardEffect, StateConfig, etc.) should be set in the .tres file using the proper ExtResource format to avoid circular reference issues.

## CardConfig Property Configuration

### Animation Configuration

**Required Fields:**
- `animation_name`: Animation name (string) - for single-strike cards
  - Use **canonical slot names only** — these work on every standardised character:
    - Offensive: `"melee_combo_1"`, `"melee_combo_2"`, `"melee_combo_3"`, `"ranged_cast_1"`, `"ranged_cast_2"`
    - Locomotion: `"walk"` · Defensive: `"dodge"`, `"parry"`, `"jump"`, `"jump_land"`, `"hit"`, `"death"`
  - Non-melee skills/casts (heal, buff, debuff, spell attacks) all use the canonical cast slots `"ranged_cast_1"` / `"ranged_cast_2"`
  - Legacy names like `"attack"`, `"heal"`, `"magic_cast"`, `"cast"`, `"defend"`, `"heavy_attack"` do **not** exist on the standardised AnimationTree and will fail validation

**Animation Timing:**
- Timing is controlled by AnimationPlayer method tracks in the animation itself
- The system uses callbacks (`_on_attack_start`, `_on_attack_hit`, `_on_attack_end`) triggered by method tracks
- Damage is applied when the `hit_moment` signal is emitted by the `_on_attack_hit()` callback
- See [`ANIMATION_CALLBACK_SETUP.md`](file:///c:/Users/XTAHA/Godot/Projects/3D-TurnBasedCombat/docs/ANIMATION_CALLBACK_SETUP.md) for details on setting up animation callbacks

### Multi-Strike Configuration

**Overview:** Multi-strike cards execute a sequence of multiple attacks with individual animations, QTEs, and damage multipliers. This is ideal for combo moves, flurry attacks, and rapid-fire abilities.

**Required Fields:**
- `is_multi_strike`: Boolean (set to `true` for multi-strike cards)
- `animation_name`: Empty string (must be empty when using multi-strike)
- `strike_animations`: Array[String] - Animation names for each strike
- `strike_multipliers`: Array[float] - Damage multipliers for each strike
- `strike_qte_windows`: Array[float] - QTE window duration for each strike

**Optional Fields:**
- `strike_delays`: Array[float] - Delays between strikes in seconds (0.0 for no delay)
- `strike_chain_leads`: Array[float] - Optional per-strike chain lead: seconds trimmed from THIS strike's clip so the next strike starts early. Indexed by the current strike - the last entry is unused. Empty = use CardBattleConfig.multi_strike_chain_lead
- `strike_qte_difficulties`: Array[float] - QTE difficulty for each strike (0.0-1.0)

**Configuration Rules:**
- All arrays must have the same size (one entry per strike)
- `animation_name` must be empty when `is_multi_strike` is true
- Each strike uses its own QTE with individual timing and difficulty
- Damage is applied per strike with individual multipliers
- Movement to target happens once before the first strike
- Return movement happens once after the final strike

**Example Multi-Strike Card Configuration:**
```gdscript
is_multi_strike = true
animation_name = ""
strike_animations = Array[String](["melee_combo_1", "melee_combo_2", "melee_combo_3"])
strike_multipliers = Array[float]([1.0, 1.2, 1.5])
strike_delays = Array[float]([0.0, 0.1, 0.1])
strike_qte_difficulties = Array[float]([0.4, 0.5, 0.6])
strike_qte_windows = Array[float]([0.4, 0.4, 0.4])
```

**Multi-Strike Execution Flow:**
1. Actor moves to target (once)
2. For each strike in sequence:
   - Apply strike delay if configured
   - Start QTE for this strike (if qte_window > 0)
   - Play strike animation
   - Wait for hit moment callback
   - Apply damage with strike-specific multiplier
   - Wait for animation end
3. Actor returns to original position (once)

**QTE Timing in Multi-Strike:**
- Each strike has its own QTE window
- QTEs are sequential - one per strike
- QTE timing uses the same `BEFORE_ATTACK` pattern as single-strike cards
- Each QTE result affects only its corresponding strike's damage
- QTE multipliers are cumulative across all strikes for total damage

### Animation Mapping System

**Overview:** The animation mapping system allows cards to use the **canonical slot names** which are automatically remapped to character-specific animation states. This keeps cards portable across characters while still allowing each character to look unique.

**How It Works:**
1. Cards specify canonical slot names (e.g., "melee_combo_1", "ranged_cast_1")
2. Each character can have an AnimationMapping resource that maps canonical slots to their specific animation states
3. When a card is played, the system resolves the slot name through the character's mapping
4. If no mapping exists, the canonical slot name is used directly (every standardised tree has it)

**AnimationMapping Resource:**

**File Location:** `database/animation_mappings/[character_name]_mapping.tres`

**Required Script:**
```
[ext_resource type="Script" path="res://battle-manager/card_combat/resources/animation_mapping.gd" id="1"]
script = ExtResource("1")
```

**Required Fields:**
- `animation_map`: Dictionary mapping generic names to character-specific animations

**Example AnimationMapping for Wizard:**
```gdscript
animation_map = {
    "melee_combo_1": "wizard_staff_bash",
    "melee_combo_2": "wizard_staff_combo",
    "ranged_cast_1": "wizard_spell_cast",
    "ranged_cast_2": "wizard_fireball_cast",
    "hit": "wizard_hit",
    "death": "wizard_death"
}
```

**Example AnimationMapping for Ninja:**
```gdscript
animation_map = {
    "melee_combo_1": "ninja_quick_slash",
    "melee_combo_2": "ninja_combo_slash",
    "ranged_cast_1": "ninja_ninja_magic",
    "ranged_cast_2": "ninja_shuriken_flurry",
    "hit": "ninja_hit",
    "death": "ninja_vanish"
}
```
**Important:** every value in `animation_map` must be a state that actually exists on
that character's AnimationTree. Mapping to a state that is not in the tree will fail
`_try_animation()` validation loudly — the character's tree is the source of truth.

**Assigning AnimationMapping to Characters:**
1. Create AnimationMapping resource in `database/animation_mappings/`
2. In the Godot Editor, select the character's Battler node
3. Set the `animation_mapping` property to the created resource
4. Characters without animation_mapping will use generic names directly

**Benefits:**
- Cards work across different character types without modification
- New characters only need their own animations, not every card animation
- Easy to change a character's animation style by updating one resource
- Backward compatible with existing characters without mapping

**Best Practices:**
- Use descriptive generic names (e.g., "magic_cast" instead of "anim1")
- Keep generic names consistent across cards
- Document the generic animation names used in your card system
- Test cards with different character types to ensure mappings work correctly

**Available Preset Mappings:**
The following example animation mapping resources have been created:
- `database/animation_mappings/wizard_mapping.tres` - Wizard character animations
- `database/animation_mappings/warrior_mapping.tres` - Warrior character animations
- `database/animation_mappings/ninja_mapping.tres` - Ninja character animations

These can be used as templates or directly assigned to character Battler nodes.
- Keep generic names consistent across cards
- Document the generic animation names used in your card system
- Test cards with different character types to ensure mappings work correctly

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

**File Location:** `database/card_effects/[effect_name].tres`

**Required Script:**
```
[ext_resource type="Script" path="res://scenes/battle/card_combat/resources/cards/card_effect.gd" id="1"]
script = ExtResource("1")
```

**Required Fields:**
- `effect_type`: Integer from EffectType enum
- `value`: Integer (base effect value - damage, heal, shield amount)
- `targeting`: Integer from EffectTargeting enum
- `scaling`: Dictionary (stat scaling, e.g., {"attack": 0.5})
- `conditions`: Array of EffectCondition resources (empty if none)

**Important:** CardEffect is the **source of truth** for numeric values:
- `value` contains the base damage/heal/shield amount
- `scaling` contains stat scaling configuration
- `damage_type` (for damage effects) can be "physical", "magical", or "true_damage"
- `element` (for hit effects) can be "none", "fire", "ice", "lightning", "bleed", etc.

These fields are NOT in CardConfig - they must be set in CardEffect.

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

**Effect Timing Enum:**
- 0 = IMMEDIATE (effect triggers immediately)
- 1 = AFTER_ANIMATION (effect triggers after animation completes)
- 2 = ON_HIT (effect triggers on hit frame)
- 3 = ON_IMPACT (effect triggers on impact with target)
- 4 = CHANNEL_START (effect triggers when channeling starts)
- 5 = CHANNEL_END (effect triggers when channeling ends)

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

**Overview:** The projectile system supports single projectiles, multi-projectile volleys, AOE projectiles, curved trajectories, and sophisticated spread patterns. Projectiles are object-pooled for performance and support both sequential and simultaneous firing modes.

**Required Fields for Projectile Cards:**
- `projectile_enabled`: Boolean (set to `true` to enable projectile system)
- `projectile_scene`: String (path to projectile VFX scene file)
- `projectile_speed`: Float (travel speed in world units/second, typically 10-30)
- `projectile_lifetime`: Float (maximum projectile lifetime in seconds, typically 2-5)
- `projectile_arc`: Float (arc height for projectile trajectory in world units)
- `projectile_spawn_point`: String ("actor" - spawns in front of actor)

**Optional Projectile Properties:**

**Curve and Trajectory Control:**
- `projectile_speed_curve`: Curve resource (speed varies over time: slow start, fast travel, etc.)
  - Subresource in card config (inline Curve, not separate file)
  - Example: `[(0, 0.2), (0.3, 0.4), (1, 1)]` for accelerating projectile
- `projectile_arc_curve`: Curve resource (arc height varies over time for dynamic curvature)
  - Subresource in card config (inline Curve, not separate file)
  - Example: `[(0, 0), (0.5, 1), (1, 0)]` for parabolic arc
- `projectile_curve_influence`: Float (0.0-1.0, how much the curve affects path)
  - 0.0 = straight line (no arc)
  - 1.0 = full curve from arc_curve
  - 0.5 = half arc (balanced)

**Projectile Scaling:**
- `projectile_scale`: Vector3 (scale of projectile VFX, default `Vector3(1, 1, 1)`)
  - Use larger scales for AOE effects (e.g., `Vector3(2, 2, 2)` for wide slash)
  - Use smaller scales for rapid-fire projectiles (e.g., `Vector3(0.3, 0.3, 0.3)` for fireballs)

**Multi-Projectile Configuration:**
- `projectile_fire_simultaneously`: Boolean (fire all projectiles at once vs sequentially)
  - `true`: All projectiles spawn simultaneously (best for Card Salvo, volleys)
  - `false`: Projectiles fire one at a time (default, works with wait_for_impact)
- `projectile_spawn_spread`: Float (spread radius in world units for spawn position)
  - Creates a ring facing forward from the actor
  - Higher values = wider ring, more visual spread
  - Typical values: 0.5-2.0 for most cards
- `projectile_trajectory_spread`: Float (variance in arc height for path variety)
  - Randomizes arc height by ±spread value
  - Projectiles always reach target but take different curved paths
  - Higher values = more arc height variation
  - Typical values: 0.2-1.0 for variety

**Multi-Strike with Projectiles:**
- `projectile_wait_for_impact`: Boolean (wait for projectile impact before next strike)
  - `true`: Next strike waits for current projectile to hit (sequential, controlled)
  - `false`: Next strike fires immediately without waiting (rapid-fire, chaotic)
  - Works with multi-strike cards only
- `projectile_strike_delay`: Float (delay between strikes if not waiting for impact)
  - Only used when `projectile_wait_for_impact = false`
  - Controls spacing between rapid-fire projectiles
  - Typical values: 0.0-0.3 seconds

**AOE Projectile Configuration:**
- `projectile_aoe`: Boolean (single projectile damages all targets instead of one per target)
  - `true`: One projectile damages multiple targets (e.g., Horizontal Slash)
  - `false`: Each projectile damages one target (default)
  - For AOE cards, projectile travels to center of all targets
  - Damage applied to all targets on impact simultaneously

**Projectile System Architecture:**

**Object Pooling:**
- Projectiles use object pooling for performance (20 pre-allocated containers)
- Eliminates node instantiation overhead during combat
- Pooled projectiles are reset (position, rotation, scale, damage_data) before reuse
- Pool creates new projectiles if exhausted (fallback safety)

**Scene Caching and Preloading:**
- Projectile scenes are cached after first load to avoid repeated `load()` calls
- All projectile scenes are preloaded at combat start from deck draw piles
- Background loading prevents frame stutter during projectile spawning
- Synchronous fallback if preload doesn't complete in time

**Spread System:**
- **Spawn Spread**: Creates a ring facing forward from the actor
  - Uses `sqrt(randf())` for uniform area distribution (prevents center bias)
  - Spatial grid collision detection prevents overlap (O(1) lookup)
  - Up to 10 attempts to find unique position before using last candidate
  - Global grid for simultaneous fire (shared across volley)
  - Local grid for sequential fire (per-projectile)

- **Trajectory Spread**: Randomizes arc height, not target position
  - Variance: `(randf() - 0.5) * 2.0 * trajectory_spread`
  - Projectiles always reach actual target
  - Visual variety in curved paths without breaking targeting

**AOE Execution Context:**
- AOE projectiles use `ProjectileExecutionContext` for data passing
- Context contains: center position, target list
- Stored in `card_battle_manager._aoe_execution_context` dictionary
- Keyed by CardConfig resource
- Cleaned up after card execution completes
- Replaces fragile metadata-based passing

**Damage Application:**
- Damage applied when projectile arrives at target
- AOE projectiles: damage all targets from context simultaneously (no await)
- Single-target projectiles: damage single target
- Damage data stored in projectile's `damage_data` dictionary
- Includes: actor, target, card_cfg, damage_multiplier, aoe_targets
- Pool return clears damage_data to prevent stale data

**Projectile VFX Orientation:**
- Projectile container uses `look_at()` to face travel direction
- VFX child nodes may need manual rotation due to baked scene transforms
- System applies +PI/2 Y rotation to align VFX with forward direction
- VFX scenes should be authored with +Y facing forward for best results

**Animation Integration:**
- Projectile cards use `ranged_cast_1` or `ranged_cast_2` animations
- Hit moment callback triggers projectile launch
- Multi-strike cards: each strike can launch its own projectile
- Movement to target happens before first projectile (for melee-range hybrids)
- No movement if purely ranged (distance check configurable)

**Example: Basic Single Projectile Card**
```gdscript
projectile_enabled = true
projectile_scene = "res://assets/effects/attacks/projectiles/vfx_basic_projectile_01.tscn"
projectile_speed = 20.0
projectile_lifetime = 2.0
projectile_arc = 0.0
projectile_scale = Vector3(1, 1, 1)
projectile_aoe = false
projectile_fire_simultaneously = false
projectile_spawn_spread = 0.0
projectile_trajectory_spread = 0.0
projectile_wait_for_impact = true
animation_name = "ranged_cast_1"
```

**Example: Multi-Projectile Volley (Card Salvo)**
```gdscript
projectile_enabled = true
projectile_scene = "res://assets/effects/attacks/projectiles/vfx_evil_projectile_01.tscn"
projectile_speed = 25.0
projectile_lifetime = 2.0
projectile_arc = 1.5
projectile_arc_curve = SubResource("Curve_arc")  # Parabolic
projectile_curve_influence = 0.7
projectile_scale = Vector3(0.5, 0.5, 0.5)
projectile_fire_simultaneously = true  # All at once
projectile_spawn_spread = 1.0  # Ring facing forward
projectile_trajectory_spread = 0.5  # Arc height variety
projectile_speed_curve = SubResource("Curve_speed")  # Accelerating
is_multi_strike = true
strike_animations = Array[String](["ranged_cast_1", "ranged_cast_1", "ranged_cast_1"])
strike_multipliers = Array[float]([0.8, 1.0, 1.2])
```

**Example: AOE Projectile (Horizontal Slash)**
```gdscript
projectile_enabled = true
projectile_scene = "res://assets/effects/attacks/slash/vfx_blank_slash.tscn"
projectile_speed = 30.0
projectile_lifetime = 1.0
projectile_arc = 0.0  # Straight line
projectile_scale = Vector3(2, 2, 2)  # Large slash
projectile_aoe = true  # One projectile, damages all targets
target_type = 2  # ALL_ENEMIES
animation_name = "melee_combo_1"  # Melee animation with projectile
```

**Example: Rapid-Fire Multi-Strike (Pyroclast Barrage)**
```gdscript
projectile_enabled = true
projectile_scene = "res://assets/effects/attacks/projectiles/vfx_fire_projectile_01.tscn"
projectile_speed = 20.0
projectile_lifetime = 2.0
projectile_arc = 2.0
projectile_arc_curve = SubResource("Curve_arc")
projectile_curve_influence = 0.7
projectile_scale = Vector3(0.3, 0.3, 0.3)  # Small fireballs
projectile_fire_simultaneously = false  # Sequential
projectile_spawn_spread = 1.0
projectile_trajectory_spread = 5.0  # High arc variety
projectile_wait_for_impact = false  # Don't wait, rapid-fire
projectile_strike_delay = 0.0  # No delay
projectile_speed_curve = SubResource("Curve_speed")
is_multi_strike = true
strike_animations = Array[String](["melee_combo_1", "melee_combo_2", "melee_combo_3"])
strike_multipliers = Array[float]([0.8, 1.0, 1.4])
```

**Best Practices:**

1. **Curve Resources**: Use inline Curve subresources in card config, not separate files
   - Click "Curve" in inspector to edit points
   - X-axis = time (0-1), Y-axis = value
   - First point at (0, 0), last point at (1, 1) for normalized curves

2. **Spread Tuning**:
   - Spawn spread: 0.5-1.0 for tight volleys, 1.5-2.0 for wide spreads
   - Trajectory spread: 0.2-0.5 for subtle variety, 1.0+ for chaotic paths
   - Adjust based on projectile count (more projectiles = higher spread)

3. **AOE Projectiles**:
   - Use `projectile_aoe = true` for cards that should hit all targets with one projectile
   - Set target_type to ALL_ENEMIES, ALL_ALLIES, or ALL_UNITS
   - Use larger projectile_scale for visual clarity
   - Arc height typically 0 (straight line to center)

4. **Performance**:
   - Object pooling handles up to 20 simultaneous projectiles efficiently
   - Preloading prevents stutter on first projectile spawn
   - Avoid excessive projectile counts (>10) unless using simultaneous fire
   - Use projectile_lifetime to prevent stuck projectiles

5. **Visual Clarity**:
   - Larger projectiles for main attacks, smaller for rapid-fire
   - Use speed curves for dramatic effect (slow start, fast impact)
   - Arc curves for gravity-based projectiles (fireballs, arrows)
   - Straight arcs for magical energy beams

6. **Multi-Strike Integration**:
   - Use `projectile_wait_for_impact = true` for controlled, sequential strikes
   - Use `projectile_wait_for_impact = false` for chaotic, rapid-fire attacks
   - Adjust `projectile_strike_delay` to space out rapid-fire projectiles
   - Combine with trajectory spread for visual variety per strike

**Common Pitfalls:**

1. **Targeting Broken by Trajectory Spread**: Never use trajectory spread on single-target cards that must hit precisely. Use it only on multi-strike or AOE cards where slight path variation is acceptable.

2. **Projectile Not Reaching Target**: If projectile seems to miss, check:
   - `projectile_speed` is too low (increase)
   - `projectile_lifetime` is too short (increase)
   - Arc height is too high for the distance (reduce)
   - VFX scene has baked transforms affecting rotation

3. **Overlapping Projectiles**: If projectiles overlap visually:
   - Increase `projectile_spawn_spread`
   - Check if `projectile_fire_simultaneously` is set correctly
   - For sequential fire, ensure spread collision detection is working

4. **Stale Damage Data**: If wrong damage is applied:
   - Check pool return clears damage_data (fixed in current system)
   - Ensure damage is applied before pool return
   - Verify callback data is stored correctly

5. **AOE Only Damaging One Target**: If AOE projectile only hits one enemy:
   - Verify `projectile_aoe = true` is set
   - Check target_type is ALL_ENEMIES (2) or similar
   - Ensure execution context is created and passed correctly
   - Verify context cleanup doesn't happen too early

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
- 0 = BEFORE_ATTACK (QTE starts before animation, ends at hit moment)
- 1 = ON_HIT_FRAME (QTE on hit frame - not currently used)
- 2 = AFTER_ATTACK (QTE after attack animation - not currently used)

**Note:** The system currently uses `BEFORE_ATTACK` timing. QTEs start before the animation and end exactly at the hit moment. The window duration is configured via `qte_window_duration` in the card config.

**QTE Type-Specific Fields:**
- For SEQUENCE type: `qte_sequence`: Array[String] (button sequence)
- For BUTTON_MASH type: `qte_mash_count`: Integer (required button presses), `qte_mash_window`: Float (time window)

### CardConfig Display Assets Configuration

**Required Fields:**
- `card_name`: String - Display name of the card (shown in UI)
- `ap_cost`: int - AP cost to play the card (typically 1-3)
- `card_description`: String - Flavor text and description

**Optional Display Asset Fields:**
- `background_sprite`: Texture2D - Type-based background texture
- `main_image`: Texture2D - Character portrait or icon
- `attack_icon`: Texture2D - Attack damage icon
- `effect_icon`: Texture2D - Effect/special ability icon
- `card_frame_texture`: Texture2D - Outer frame/border texture
- `name_banner_texture`: Texture2D - Textured banner for card name
- `cost_badge_texture`: Texture2D - Cost badge texture
- `type_icon`: Texture2D - Card type indicator icon

**Note:** Numeric values (damage, heal, shield) are set in CardEffect, not CardConfig.

### State and Debuff Configuration

**Required Fields:**
- `applies_states`: Array of StateConfig resources (empty if none)
- `applies_self_states`: Array of StateConfig resources (empty if none)
- `state_chance`: Float (0.0-1.0 chance to apply states)
- `state_duration`: Integer (duration in turns)
