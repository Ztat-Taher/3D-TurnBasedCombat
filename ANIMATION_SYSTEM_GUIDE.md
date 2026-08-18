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
- **[`battler.gd`](file:///c:/Users/XTAHA/Godot/Projects/3D-TurnBasedCombat/battle-manager/scripts/battler_scripts/battler.gd)**: Core character controller handling state transitions, movement tweens, turning, and hit-frame synchronization.
- **[`battler_combat_helper.gd`](file:///c:/Users/XTAHA/Godot/Projects/3D-TurnBasedCombat/battle-manager/scripts/battler_combat_helper.gd)**: Utility module for distance calculations, stuck timeouts, and state tracking.
- **[`battlecamera.gd`](file:///c:/Users/XTAHA/Godot/Projects/3D-TurnBasedCombat/battle-manager/battlecamera.gd)**: Smooth 3D camera transitions (Default, OTS, Enemy Overview, Target Focus) driven by `create_tween()`.
- **[`damage_number.gd`](file:///c:/Users/XTAHA/Godot/Projects/3D-TurnBasedCombat/battle-manager/scripts/damage_number.gd)**: Sine-wave oscillation, vertical rise, and fade-out tween for floating combat text.

---

## 3. Animation State Routing (`AnimationTree`)

Rather than invoking `AnimationPlayer.play()` directly, the game uses an **`AnimationTree` State Machine** with hierarchical state navigation to ensure smooth blending and state safety.

### State Structure:
- **Root State Machine**: Contains base states like `idle1`, `walk`, `turn_right`, `turn_left`, and a sub-state machine `basic_attacks`.
- **`basic_attacks` Sub-Machine**: Houses specific attack variants such as `attack` and `kick`.

### Two-Step Nested Travel Pattern
Because Godot's root `AnimationNodeStateMachinePlayback` cannot travel into child state machine nodes in a single jump, `_try_animation()` performs a two-step travel:

```gdscript
func _try_animation(anim_name: String) -> bool:
    var attack_states = ["attack", "kick"]
    if anim_name in attack_states:
        # Step 1: Travel root playback into the sub-machine container
        state_machine.travel("basic_attacks")
        # Step 2: Travel child playback into the specific attack leaf state
        var attacks_sm = anim_tree.get("parameters/basic_attacks/playback")
        if attacks_sm:
            attacks_sm.travel(anim_name)
```

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

## 5. Combat Motion & Advance Mechanics

For melee strikes, characters advance physically across the 3D battlefield before playing the attack clip:

```
[Start Position]
       │
       ▼ 1. Rotate to face target (turn_to_face_target)
       │    └─ Sets anim_tree "parameters/conditions/is_turning_right|left"
       │
       ▼ 2. Move to contact distance (advance_to_target)
       │    ├─ Calculates advance_target_position = target.pos - direction * distance
       │    ├─ Plays "walk" animation
       │    └─ Godot SceneTree Tween moves global_position smoothly
       │
       ▼ 3. Re-align rotation (turn_to_face_target)
       │
       ▼ 4. Strike & Contact Frame (attack_anim / _try_animation)
       │    ├─ Plays "attack"
       │    ├─ Awaits `hit_moment`
       │    └─ Applies damage_calculation / QTE reactive defense
       │
       ▼ 5. Animation Follow-Through
       │    └─ Awaits remaining animation duration (attack_dur - hit_time)
       │
       ▼ 6. Return Movement (return_to_original_position)
       │    ├─ Tweens position back to original_position
       │    └─ Calls battle_idle() upon arrival
```

---

## 6. Defensive Micro-Animations & Counters

### Dodge & Parry Reactions
- **Parry**: When timed during an incoming enemy `hit_moment`, the target deflects, reducing damage and triggering cyan HUD text.
- **Perfect Parry & Counterattack**:
  1. The incoming attack damage is negated (`0 damage`).
  2. The attacking enemy is temporarily flagged as `attacker.is_counter_stunned = true`.
  3. The defending ally immediately rotates towards the attacker and executes their own `attack` animation.
  4. Upon the defender's `hit_moment`, counter damage (`1.5x`) is applied to the enemy before they can return.

### Death & Despawn Animation (`_fade_and_remove`)
Defeated enemies fade out using a dual tween:
1. Material transparency fades to `1.0` (if an `Alpha_Surface` mesh is present).
2. Universal fallback: `scale` scales down to `Vector3.ZERO` over `0.35s` before calling `queue_free()`.

---

## 7. Cinematic Camera Choreography

Camera movement is synchronized with turn actions via `battlecamera.gd`:

| Camera Mode | Description | Animation Implementation |
| :--- | :--- | :--- |
| **Default Camera** | Wide battlefield view | `create_tween()` interpolates `global_transform` and `fov` to default over `0.45s`. |
| **Over-the-Shoulder** | Close angle behind active ally | Calculates transform relative to the ally's basis with dynamic FOV calculation based on visual AABB. |
| **Enemy Overview** | Wide shot centered across all enemies | Centers the midpoint of all active enemy battlers. |
| **Target Focus** | Close zoom on an enemy | Centers on target battler with `TRANS_CUBIC` ease-out. |

---

## 8. Summary of Animation Events & Signals

| Signal / Method | Origin | Purpose |
| :--- | :--- | :--- |
| `hit_moment(attacker)` | `Battler` | Fired at the exact impact frame of an attack; triggers damage, QTE parry windows, and effects. |
| `anim_damage()` | `Battler` | Legacy animation event signal (maintained for backward compatibility). |
| `health_changed(cur, max)` | `Battler` | Fired on damage/heal to drive smooth health bar tweens and damage flashes. |
| `reactive_defense_result(type)` | `QTEManager` | Emits `"perfect_parry"`, `"parry"`, `"dodge"`, or `"none"` to trigger counter-animations. |
