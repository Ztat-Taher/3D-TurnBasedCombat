# 3D Turn-Based Combat: Animation System Architecture

This document provides a comprehensive breakdown of how animations are managed, routed, timed, and synchronized across the combat system in this project.

---

## 1. High-Level Architecture Overview

Animation in this game operates across four distinct cooperating layers:

```
┌───────────────────────────────────────────────────────────────────────────┐
│                           1. Combat Orchestrator                          │
│        (BattleManager, CardBattleManager, AIManager, QTEManager)          │
│       Controls turn phases, camera cues, QTE windows, and damage math     │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │ Commands (walk, attack, idle)
┌─────────────────────────────────────▼─────────────────────────────────────┐
│                          2. Battler State Machine                         │
│                    (battler.gd & AnimationTree playback)                  │
│       Routes state transitions, conditions, durations, and hit frames     │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │ Reads clips & drives skeleton
┌─────────────────────────────────────▼─────────────────────────────────────┐
│                     3. Low-Level Skeletal Animation                       │
│                           (AnimationPlayer)                               │
│       Stores raw keyframe tracks (Locomotion, attacks, reactions)         │
└───────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ Projections / Tweens
┌─────────────────────────────────────┴─────────────────────────────────────┐
│                       4. Visual & UI Micro-Animations                     │
│         (Tween system, Damage Numbers, 3D Camera, Over-Head Bars)         │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Core Components & Hierarchy

Each combatant (`Battler`) possesses the following animation-related node tree:

```
Battler (CharacterBody3D - battler.gd)
├── AnimationPlayer                  # Raw animation clip container & libraries
├── AnimationTree                    # State machine controller + condition parameters
├── %Alpha_Surface (MeshInstance3D)  # Mesh receiving outline shaders & death dissolves
├── SubViewport (DamageIndicator)    # 3D floating damage text viewport
└── Camera Pivot Nodes               # OTS / Focus target attachment anchors
```

### Key Scripts
- **[`battler.gd`](file:///c:/Users/XTAHA/Godot/Projects/3D-TurnBasedCombat/scripts/systems/battle/battlers/main/battler.gd)**: Core character controller handling state transitions, straight-line movement tweens, and hit-frame synchronization.
- **[`battler_combat_helper.gd`](file:///c:/Users/XTAHA/Godot/Projects/3D-TurnBasedCombat/scripts/systems/battle/battlers/combat/battler_combat_helper.gd)**: Utility module for distance calculations, stuck timeouts, and state tracking.
- **[`battlecamera.gd`](file:///c:/Users/XTAHA/Godot/Projects/3D-TurnBasedCombat/scripts/systems/battle/core/camera/battlecamera.gd)**: Smooth 3D camera transitions (Default, OTS, Enemy Overview, Target Focus) driven by `create_tween()`.
- **[`damage_number.gd`](file:///c:/Users/XTAHA/Godot/Projects/3D-TurnBasedCombat/scenes/battle/effects/damage/damage_number.gd)**: Sine-wave oscillation, vertical rise, and fade-out tween for floating combat text.
- **[`card_battle_manager.gd`](file:///c:/Users/XTAHA/Godot/Projects/3D-TurnBasedCombat/scripts/systems/battle/card_combat/core/card_battle_manager.gd)**: Drives card action animations, phase sequencing, and QTE synchronization.

---

## 3. Animation State Routing (`AnimationTree`)

Rather than invoking `AnimationPlayer.play()` directly, the game uses an **`AnimationTree` State Machine** with hierarchical state navigation to ensure smooth blending and state safety.

### State Structure:
- **Root State Machine**: Contains base states like `idle1`, `walk`, `dodge`, `parry`, `jump`, `jump_land`, `hit`, `death`, and a sub-state machine `combat_actions`.
- **`combat_actions` Sub-Machine**: Houses the standardised offensive slots `melee_combo_1..3` and `ranged_cast_1..2`.

### Two-Step Nested Travel Pattern
Because Godot's root `AnimationNodeStateMachinePlayback` cannot travel into child state machine nodes in a single jump, `_try_animation()` performs a two-step travel:

```gdscript
# Step 1: Travel root playback into the combat_actions container
state_machine.travel("combat_actions")
# Step 2: Travel child playback into the specific attack leaf state
var ca_sm = anim_tree.get("parameters/combat_actions/playback")
if ca_sm:
    ca_sm.travel(target_leaf)  # e.g. "melee_combo_1"
```

### Canonical Names Only — No Fallbacks
Cards, skills, and `EnemyAttackConfig` **must reference canonical slot names**
(`melee_combo_1..3`, `ranged_cast_1..2`, `idle`, `walk`, `dodge`, …). This is the
single source of truth; the animation system does **not** substitute or remap
unknown names.

`_try_animation()` validates the requested state against this character's
`AnimationTree` before travelling:

1. The name is resolved through `AnimationMapping` (slot → character-specific state) if one is attached.
2. `combat_actions` slots are travelled to with intermediate validation.
3. Root states are travelled to only if they exist.
4. A missing state returns `false` with a clear `push_error` naming the bad state —
   it never silently plays a different animation, and it never feeds an invalid
   state name into the engine state machine.

If you see the error `Animation state 'xyz' does not exist on 'name'`, fix the
**card/skill/config** that requested `xyz` (or add that state to the character's
tree) — the state machine is not the place to paper over bad content.

---

## 4. Dynamic Duration & Hit-Frame Synchronization

Because `AnimationTree` does not reliably emit `AnimationPlayer.animation_finished` when transitioning inside nested trees, the game uses **dynamic clip inspection** and **timer-based event scheduling**.

### Step 1: Clip Length Resolution (`_get_animation_duration`)
When an animation state begins, `_resolve_state_animation_name()` inspects the `AnimationNodeAnimation` node inside the state machine to identify the actual clip name (e.g. `"Locomotion-Library/attack1"`), then fetches its exact length from the `AnimationPlayer`:

```gdscript
var clip_length = anim_player.get_animation(resolved_name).length
_current_attack_duration = max(0.25, clip_length)
```

### Step 2: The `hit_moment` Signal
To ensure damage numbers and reactive defense windows (dodge/parry) line up precisely with the physical impact of the swing/punch (rather than firing when the animation starts or finishes), the system schedules a `hit_moment` signal:

```gdscript
# Default: contact occurs at 55% of the total animation duration
var hit_delay = duration * hit_frame_ratio # e.g. 1.2s * 0.55 = 0.66s

_hit_moment_timer = get_tree().create_timer(hit_delay)
_hit_moment_timer.timeout.connect(func():
    hit_moment.emit(self)
    anim_damage.emit()
)
```

---

## 5. Card-Driven Animation & Mapping Pipeline

When playing a card via `CardBattleManager.execute_card_with_config()`, character animations use **canonical slot names** that map directly to AnimationTree states:

```
CardConfig (actor_animation: "ranged_cast_1")
       │
       ▼
Battler.get_resolved_animation("ranged_cast_1")
       │  (Uses Battler.animation_mapping -> AnimationMapping resource,
       │   or passes the canonical name through unchanged)
       ▼
Resolved Name: "ranged_cast_1" (canonical slot, always valid)
       │
       ▼
Battler._try_animation("ranged_cast_1")
       │
       ▼
CardConfig.animation_events (staggered callbacks during animation playback)
```

> **Canonical slots** (`melee_combo_1..3`, `ranged_cast_1..2`) are the single source of
> truth. Cards must reference these names — see the *Canonical Names Only* section above.
> Legacy generic names (`"attack"`, `"heal"`, `"magic_cast"`, …) are **not** valid and will
> fail `_try_animation()` validation with a clear error.

### Staggered Animation Callbacks (`process_animation_events`)
Cards can attach `AnimationEvent` resources scheduled at fractional progress points (e.g. 0.3 for particle summon, 0.6 for hit impact). `CardBattleManager.process_animation_events()` monitors normalized animation progress `(animation_time / animation_duration)` and triggers events dynamically.

### Enemy Attack Animation Routing (`EnemyAttackConfig`)
Enemies trigger attacks through their configured skills rather than card configs:
```
EnemyStats.attacks -> EnemyAttackConfig
       │
       ├─ animation_name: Canonical slot name (default "melee_combo_1")
       ├─ damage_multiplier: Scales outgoing physical damage
       ├─ hit_frame_ratio: Custom contact frame ratio (overriding Battler.hit_frame_ratio)
       └─ move_announcement_type: Triggers HUD banner before execution
```
In `battler.gd`, `attack_anim(target, attack_config)` dynamically adapts to the config's `animation_name` and `hit_frame_ratio` during the strike phase.

---

## 6. Combat Motion & Advance Mechanics

For melee strikes, characters advance physically across the 3D battlefield before playing the attack clip. **Movement is straight-line only — there is no rotation or facing**; the battler keeps its original orientation throughout.

```
[Start Position]
       │
       ▼ 1. Move to contact distance (advance_to_target)
       │    ├─ Calculates advance_target_position = target.pos - direction * distance
       │    ├─ Plays "walk" animation
       │    └─ Godot SceneTree Tween moves global_position smoothly
       │
       ▼ 2. Strike & Contact Frame (attack_anim / _try_animation)
       │    ├─ Plays a melee_combo slot
       │    ├─ Awaits `hit_moment`
       │    └─ Applies damage_calculation / QTE reactive defense
       │
       ▼ 3. Animation Follow-Through
       │    └─ Awaits remaining animation duration (attack_dur - hit_time)
       │
       ▼ 4. Return Movement (return_to_original_position)
       │    ├─ Plays "walk_back" — a dedicated backward-walk clip
       │    │  (sword_dodge_combat_backward), so the battler backs away
       │    │  in its original facing direction (no turn)
       │    ├─ Tweens position back to original_position
       │    └─ Calls battle_idle() upon arrival
```

### Auto-Return to Idle
The `combat_to_idle` transition in `battle_tree_node.tres` uses `advance_mode = 2`
(AUTO), so any combat animation (attack or cast) automatically returns the battler
to idle when the clip ends — consistent with `jump_land_to_idle` and
`start_to_idle`. This is what allows card casts (heal, buff) to settle back to
idle without getting stuck mid-pose.

The `hit_to_idle`, `dodge_to_idle`, and `parry_to_idle` transitions use manual
`advance_mode = 0` instead. The code explicitly travels back to idle after these
reaction clips finish (see *Hit Reaction* and *Dodge & Parry* below). These
manual transitions prevent the animations from being instantly overwritten by idle
— a bug that occurred with `advance_mode = 2` AUTO on short reaction clips.

### Card Flow Idle Return
`CardBattleManager.execute_card_with_config()` finishes with **Phase 10:
`battle_idle()`**, so any card (heal, buff, attack via config) returns the actor to
its idle animation after the cast/effect/audio phases complete. The auto-return
transition above means the battler is already idle before Phase 10 runs.

### Hit Reaction
`Battler.take_damage()` calls `play_hit_reaction()` whenever the battler takes
damage (`damage_taken > 0`, still alive). The `hit` root state plays its flinch
clip fully, then the code explicitly travels back to `idle1`. `is_hit` is
cleared before the return travel so the `idle_to_hit` transition doesn't
immediately re-fire. Fully-avoided hits (dodge/jump → 0 damage) do not flinch.

### Dodge & Parry
The `dodge_to_idle` and `parry_to_idle` transitions also use manual
`advance_mode = 0`. The dodge return flow (`_on_dodge_dash_complete` →
`_on_return_complete`) explicitly travels back to `idle1` after the dash.

---

## 7. Defensive Micro-Animations & Counters

### Dodge & Parry Reactions
- **Parry**: When timed during an incoming enemy `hit_moment`, the target deflects, reducing damage and triggering cyan HUD text.
- **Perfect Parry & Counterattack**:
  1. The incoming attack damage is negated (`0 damage`).
  2. The attacking enemy is temporarily flagged as `attacker.is_counter_stunned = true`.
  3. The defending ally executes their own `melee_combo_1` counterattack (no rotation).
  4. Upon the defender's `hit_moment`, counter damage (`1.5x`) is applied to the enemy before they can return.
  5. Built-in `stuck_movement_timeout` and `allow_animation_fallback` in `battler.gd` prevent characters from freezing if animation frames are interrupted by counters.

### Death & Despawn Animation (`_fade_and_remove`)
Defeated enemies fade out using a dual tween:
1. Material transparency fades to `1.0` (if an `Alpha_Surface` mesh is present).
2. Universal fallback: `scale` scales down to `Vector3.ZERO` over `0.35s` before calling `queue_free()`.

---

## 8. Cinematic Camera Choreography

Camera movement is synchronized with turn actions via `battlecamera.gd`:

| Camera Mode | Description | Animation Implementation |
| :--- | :--- | :--- |
| **Default Camera** | Wide battlefield view | `create_tween()` interpolates `global_transform` and `fov` to default over `0.45s`. |
| **Over-the-Shoulder** | Close angle behind active ally | Calculates transform relative to the ally's basis with dynamic FOV calculation based on visual AABB. |
| **Enemy Overview** | Wide shot centered across all enemies | Centers the midpoint of all active enemy battlers. |
| **Target Focus** | Close zoom on an enemy | Centers on target battler with `TRANS_CUBIC` ease-out. |

---

## 9. Summary of Animation Events & Signals

| Signal / Method | Origin | Purpose |
| :--- | :--- | :--- |
| `hit_moment(attacker)` | `Battler` | Fired at the exact impact frame of an attack; triggers damage, QTE parry windows, and effects. |
| `anim_damage()` | `Battler` | Legacy animation event signal (maintained for backward compatibility). |
| `health_changed(cur, max)` | `Battler` | Fired on damage/heal to drive smooth health bar tweens and damage flashes. |
| `ap_changed(cur, max)` | `Battler` | Fired when battler AP is spent or regenerated; drives HUD AP bar updates. |
| `reactive_defense_result(type)` | `QTEManager` | Emits `"perfect_parry"`, `"parry"`, `"dodge"`, or `"none"` to trigger counter-animations. |
