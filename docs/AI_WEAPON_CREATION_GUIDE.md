# AI Weapon Creation Guide

This guide provides AI agents with precise instructions for creating new weapons in the turn-based combat system. It is designed to be machine-readable and actionable.

## System Architecture Overview

Weapons use a **composition architecture**: a lean `Weapon` resource holds only intrinsic equipment data, and special mechanics are composed via `WeaponModule` sub-resources — never as fields on `Weapon` itself.

1. **Weapon** (`database/weapons/weapon.gd`) — identity, model scene, stat modifiers, combat multipliers, progression, generic `WeaponEffect` list, and `modules: Array[WeaponModule]`.
2. **WeaponModule** (`database/weapons/weapon_module.gd`) — base `Resource` for mechanics. Each module can spawn a runtime `Node` under the battler's `WeaponSystem` and contribute combat modifiers.
3. **WeaponSystem** (`scripts/systems/battle/weapons/weapon_system.gd`) — runtime `Node3D` spawned by `Battler.set_weapon()`. Resolves the model visual, applies stat modifiers, evaluates `WeaponEffect`s, and instantiates every module's runtime child. Contains **no mechanic-specific code**.

**Rule for AI agents:** never add mechanic-specific fields (orb rosters, echo delays, etc.) to `weapon.gd`, `weapon_system.gd`, `battlemanager.gd`, `card_battle_manager.gd`, or `battler.gd`. New mechanics = new `WeaponModule` subclass + optional runtime `Node` + an entry in the weapon's `modules` array.

## Weapon Equip Categories

`Weapon.WType` enum (returned by `Weapon.equip_kind()`, derived from modules — there is no `weapon_type` field on weapons):

| Value | Name | Meaning |
|---|---|---|
| 0 | `BLADE` | Melee weapon: handheld model socketed into the hand, `WeaponEffect` procs |
| 1 | `ORB` | Orbiting relic: cyclic orb roster via `OrbModule`, root-space visual |

- `equip_kind()` returns `ORB` iff `modules` contains an `OrbModule`; otherwise `BLADE`.
- `AllyPartyMember.weapon_type` (a separate field on the party member, not the weapon) type-locks which weapons an ally may equip via `can_equip_weapon()` → `w.equip_kind() == weapon_type`.
- `game_state.gd` constants grant weapons per type:
  - `DEFAULT_WEAPON_PATHS` — auto-equipped starter per `Weapon.WType`
  - `BONUS_WEAPON_PATHS` — extra weapons added to inventory (un-equipped)

## Weapon Resource Properties

**File Location:** `database/weapons/items/[weapon_name].tres`

**Required Script Reference:**
```
[ext_resource type="Script" path="res://database/weapons/weapon.gd" id="1_weapon"]
script = ExtResource("1_weapon")
```

### Identity & Model

| Property | Type | Notes |
|---|---|---|
| `model_scene` | PackedScene | Weapon visual scene (see "Model Scene Conventions") |
| `item_name` | String | Display name (inherited from Item) |
| `description` | String | Flavor text (inherited from Item) |

Weapons are non-stackable, non-battle items, unsellable (`_init` enforces this).

### Progression

| Property | Type | Default | Notes |
|---|---|---|---|
| `weapon_xp` | int | 0 | Current XP |
| `weapon_level` | int | 1 | Current level |
| `xp_per_level` | int | 50 | XP threshold multiplier per level |
| `max_level` | int | 5 | Level cap |

`add_weapon_xp(amount)` is called by `WeaponSystem.notify_attack_hit` (+1 XP per landed hostile hit, skipped for replay hits).

### Stat Modifiers

Applied to the battler each battle by `Battler.apply_weapon_stat_modifiers()`; re-equipping never double-applies (previous mods are subtracted first).

| Property | Type | Notes |
|---|---|---|
| `max_health_bonus` / `attack_bonus` / `defense_bonus` / `agility_bonus` / `max_ap_bonus` / `ap_regen_bonus` | int | Flat bonuses |
| `max_health_percent` / `attack_percent` / `defense_percent` / `agility_percent` | float | Percent of post-vestige stat value |

### Combat Multipliers

| Property | Type | Default | Notes |
|---|---|---|---|
| `damage_dealt_multiplier` | float | 1.0 | Scales all damage dealt (via `WeaponSystem.get_damage_dealt_multiplier()`) |
| `damage_taken_multiplier` | float | 1.0 | Scales all damage received |

`get_damage_dealt_multiplier()` = `damage_dealt_multiplier` × every module's `get_damage_dealt_multiplier()`. Consumed by `BattleManager.damage_calculation`.

### Generic Effects

| Property | Type | Notes |
|---|---|---|
| `effects` | `Array[WeaponEffect]` | Param-driven procs evaluated on triggers — the baseline mechanic every weapon can carry |

See "WeaponEffect Resources" below.

### Modules

| Property | Type | Notes |
|---|---|---|
| `modules` | `Array[WeaponModule]` | Composed mechanics; each spawns its runtime node under `WeaponSystem` |

**.tres syntax:** the typed array uses the `WeaponModule` **base** script as its element type:
```
[ext_resource type="Script" path="res://database/weapons/weapon_module.gd" id="mod_base"]
[ext_resource type="Script" path="res://database/weapons/hit_echo_module.gd" id="echo_mod"]

[sub_resource type="Resource" id="my_echo"]
script = ExtResource("echo_mod")
echo_delay = 0.25

[resource]
modules = Array[ExtResource("mod_base")]([SubResource("my_echo")])
```

## WeaponEffect Resources

**File Location:** `database/weapons/items/` (inline sub-resources in the weapon `.tres` are the convention — no separate files needed)

**Script:** `res://database/weapons/weapon_effect.gd`

### Trigger Enum

| Value | Name | Fires when |
|---|---|---|
| 0 | `ON_ATTACK_HIT` | Weapon owner's attack lands a hostile hit (`notify_attack_hit`) |
| 1 | `ON_CARD_PLAY` | Owner plays a card (`notify_card_play`, wired from `CardBattleManager`) |
| 2 | `ON_DAMAGE_TAKEN` | Owner takes damage (`notify_damage_taken`, wired from `Battler.take_damage`) |
| 3 | `ON_BATTLE_START` | WeaponSystem `_ready` |
| 4 | `ON_BATTLE_END` | WeaponSystem `_exit_tree` |

### Kind Enum

| Value | Name | Behavior |
|---|---|---|
| 0 | `DAMAGE` | Bonus hit via `battle_manager.damage_calculation` (physical/none) |
| 1 | `APPLY_STATE` | Applies a `State` resource to the recipient |
| 2 | `HEAL` | `recipient.take_healing(amount)` |
| 3 | `GAIN_STACK` | Adds to weapon-internal stack counter (`stack_id`) |
| 4 | `CONSUME_STACKS` | Consumes all stacks of `stack_id` for bonus damage; may apply state |

### Properties

| Group | Property | Type | Notes |
|---|---|---|---|
| — | `trigger` | Trigger | When it evaluates |
| — | `kind` | Kind | What it does |
| Values | `value` | float | Flat amount, or % when `value_is_attack_percent` (of owner's `attack`) |
| Values | `value_is_attack_percent` | bool | `value` = percent of owner attack |
| Values | `chance` | float | 0–1 proc chance |
| Values | `requires_stacks` | int | Only fires with ≥ this many stacks of `stack_id` |
| Values | `scope_self` | bool | Apply to weapon owner instead of attack target |
| State | `state` | State | State resource to apply (APPLY_STATE / CONSUME_STACKS) |
| State | `state_stack_count` | int | Written to `state.stack_count` (0 = as authored) |
| State | `state_accumulation` | int | Written to `state.accumulation_value` (e.g. bleed) |
| Stacks | `stack_id` | StringName | Stack bucket key |
| Stacks | `max_stacks` | int | 0 = uncapped |
| Stacks | `stacks_per_trigger` | int | Stacks added per GAIN_STACK |
| Stacks | `scale_with_stack` | StringName | DAMAGE only: multiply amount by current count of this stack |

**Example — bleed proc + stacking edge damage (from `soldiers_blade.tres`):**
```
[sub_resource type="Resource" id="bleed_proc"]
script = ExtResource("fx")
value = 15.0
chance = 0.15
state = ExtResource("bleed_state")
state_accumulation = 15

[sub_resource type="Resource" id="edge_gain"]
script = ExtResource("fx")
kind = 3            # GAIN_STACK
stack_id = &"edge"
max_stacks = 5

[sub_resource type="Resource" id="edge_damage"]
script = ExtResource("fx")
kind = 0            # DAMAGE
value = 4.0
value_is_attack_percent = true
scale_with_stack = &"edge"
```

## Composed Modules

### WeaponModule (base)

`database/weapons/weapon_module.gd` — `class_name WeaponModule extends Resource`.

```gdscript
func create_runtime(_weapon_system: WeaponSystem) -> Node:
	return null  # data-only module

func get_damage_dealt_multiplier(_weapon: Weapon) -> float:
	return 1.0
```

`WeaponSystem._ready` iterates `weapon.modules`, calls `create_runtime(self)`, and `add_child`s any returned node **before its `_ready` runs**. To add a mechanic: subclass `WeaponModule` for the data, write a runtime `Node` for behavior, wire `create_runtime`.

### OrbModule — ORB weapons

`database/weapons/orb_module.gd` — owns the orb roster, spawns `OrbSystem` (`scripts/systems/battle/weapons/orb_system.gd`).

| Property | Type | Notes |
|---|---|---|
| `orbs` | `Array[OrbDefinition]` | The cycle roster |

**OrbDefinition** (`database/weapons/orb_definition.gd`):

| Group | Property | Type | Notes |
|---|---|---|---|
| — | `orb_name` | String | Display name |
| — | `color` / `emission_energy` | Color / float | Orb material |
| Detonation | `state` | State | Applied on detonation |
| Detonation | `stack_count` | int | Written to `state.stack_count` |
| Detonation | `damage` | int | Flat damage, or % when `damage_is_attack_percent` (of owner `attack`) |
| Detonation | `damage_is_attack_percent` | bool | Interpret `damage` as % of attack |
| Detonation | `chance` | float | 0–1 detonation chance (before multipliers) |
| Detonation | `element` | String | Damage element ("fire", "water", "lightning", "none", ...) |
| Detonation | `overcharge_multiplier` | float | Overcharge potency applied once to **this orb's** detonation when it follows a previous detonation — every detonation after the first in a battle (default 1.5) |
| Attuned | `attuned_effect` | WeaponEffect | Optional effect evaluated on every landed hit while this orb is Attuned |

**OrbSystem behavior:**
- The Attuned orb (cycle index `_orb_index`) detonates on each landed **hostile** hit via `WeaponSystem.notify_attack_hit` → `OrbSystem.detonate(target, context)`.
- On detonation: damage via `battle_manager.damage_calculation(owner, target, dmg, null, "magic", orb.element)`, state via `weapon_system.make_state`, then `attuned_effect` via `weapon_system.run_effect`.
- After each hit the circuit advances; `_overcharge_next` makes the next detonation use that orb's own `overcharge_multiplier` once (every detonation after the first in a battle is overcharged).
- Signals: `orb_detonated(index, orb, target_pos)`, `orb_attuned_changed(index)` — currently no external listeners; available for future UI/VFX.
- Visual contract: calls `setup_orbs(orbs)`, `set_attuned_orb(idx)`, `play_detonation(idx, target_pos)` on the weapon visual **if it has those methods** (i.e. `OrbWeaponVisual`).

### HitEchoModule — delayed hit echo

`database/weapons/hit_echo_module.gd` — presence of the module IS the opt-in.

| Property | Type | Default | Notes |
|---|---|---|---|
| `echo_delay` | float | 0.35 | Seconds between original hit and ghost replica |
| `echo_damage_fraction` | float | 0.3333 | Fraction dealt by EACH instance (live + each replay) |

`get_damage_dealt_multiplier` returns `echo_damage_fraction`, so every damage instance — original and replayed — passes through `damage_calculation` at the same fraction.

**HitEcho runtime** (`scripts/systems/battle/weapons/hit_echo.gd`) — spawned as a `HitEcho` child of `WeaponSystem`:

- Records the echo node's `global_transform` every frame **only while the weapon's `WeaponTrail` is emitting** (trail-less visuals record continuously). Frames store `{t, xf, trail}`.
- `Battler.hit_moment` arms a *pending hit*; the first `SignalBus.card_hit_resolved` event of the burst claims it (real hit-frame timing preserved even for delayed projectile impacts). Same-burst resolutions join one session's `replay_queue` (0.25s window) — **one ghost per hit burst regardless of target count**.
- After `echo_delay`, duplicates the weapon node, ghost-shades it, replays recorded transforms; ghost `WeaponTrail`s fire `_on_trail_start`/`_on_trail_end` at the recorded emission moments. At the recorded hit offset it fires the replay.
- Replay = `weapon_system.notify_attack_hit(target, {}, is_replay=true)` (weapon procs re-run, no XP, no new echoes) + `CardBattleManager.replay_card_resolution(info)` per queued event. Projectile infos of the same card merge into one replay carrying `aoe_targets` (rebuilt as a `ProjectileExecutionContext` → real projectile flight).
- `is_replay` events are ignored — replays cannot recurse.
- Recording frames are retained while any unfired session needs them, so `echo_delay` can exceed the 4s history window without losing the ghost.

## Model Scene Conventions

`model_scene` resolves two ways in `WeaponSystem._ready`:

### Socketed (BLADE) — handheld prop

When `Battler.weapon_socket_path` resolves to a node (e.g. `Armature/GeneralSkeleton/WeaponAttachement`, a `BoneAttachment3D`):

- `model_scene` is instanced as a child **named exactly `Weapon`** under the socket node, at the socket origin — then, if the socket has a **`WeaponSocket` marker child**, the instance copies that marker's `transform` (authored palm placement) while remaining the marker's sibling.
- The `"Weapon"` name is **load-bearing**: baked `AnimationPlayer` method tracks target paths like `.../WeaponAttachement/Weapon/WeaponTrail`. Never rename it.
- Weapon scenes should contain a `WeaponTrail` (`assets/effects/slash/weapon_trail.gd`) plus `trail_top` / `trail_bottom` `Node3D` markers at the blade's tip and hilt. Trails driven by animation method tracks are left alone; trails at other paths are auto-wired to `attack_start`/`attack_end` (`_wire_trail_fallback`).
- Reference: `scenes/battle/weapons/elf_leaf_blade.tscn`, `soldiers_blade.tscn`.

### Root-space (ORB) — orbiting rig

- `model_scene` should be an `OrbWeaponVisual`-based scene (`scenes/battle/weapons/orb_weapon_visual.gd`). If the battler's scene already contains a visual whose `scene_file_path` matches, it is reused; otherwise the scene is instanced under `WeaponSystem`.
- The visual may pre-author `Orb0`, `Orb1`, ... holder nodes (each with a `Mesh` `MeshInstance3D`); `setup_orbs` adopts them, captures their authored orbit slots, and creates missing ones. Orbs stay hidden until configured.
- Reference: `scenes/battle/weapons/prism_orb_weapon.tscn`.

## WeaponSystem Runtime Flow

`Battler.set_weapon(weapon)` → `WeaponSystem.new()` + `setup(weapon, battler)` + `add_child` → `_ready`:

1. `_battle_manager` = first node in group `"battle_manager"`.
2. Model resolution (socketed vs root-space, above).
3. `owner_battler.apply_weapon_stat_modifiers(weapon)`.
4. Connect `owner_battler.hit_moment` → `_on_hit_moment`.
5. **Module loop**: `for mod in weapon.modules: add_child(mod.create_runtime(self))`.
6. `_run_trigger(ON_BATTLE_START, owner, {})`.

Public API used by modules and pipelines:

| Method | Purpose |
|---|---|
| `notify_attack_hit(target, context={}, is_replay=false)` | A hostile hit landed: +1 weapon XP (unless replay), `OrbSystem.detonate`, `ON_ATTACK_HIT` effects. **Hostile-only gate** — never procs on allies/self. |
| `notify_card_play(card)` | `ON_CARD_PLAY` trigger (wired from `CardBattleManager`). |
| `notify_damage_taken(attacker, damage)` | `ON_DAMAGE_TAKEN` trigger (wired from `Battler.take_damage`). |
| `get_damage_dealt_multiplier()` | `weapon.damage_dealt_multiplier` × all module contributions. |
| `get_damage_taken_multiplier()` | `weapon.damage_taken_multiplier`. |
| `get_weapon_stack(stack_id)` / stacks dict | WeaponEffect stack counters. |
| `run_effect(fx, target, context)` | Evaluate one `WeaponEffect` (used by `OrbSystem` for `attuned_effect`). |
| `effect_amount(fx, recipient)` / `make_state(base, stacks, accumulation)` | Effect helpers exposed to module runtimes. |
| `get_battle_manager()` | The `"battle_manager"` group node. |
| `weapon_visual` / `weapon` / `owner_battler` | Public fields for module runtimes. |

## Creating a New Weapon — Step by Step

### Step 1: Choose the kind

- **BLADE** — melee weapon for `weapon_type = BLADE` allies: socketed model + `WeaponEffect`s (+ optional modules).
- **ORB** — orbiting relic for `weapon_type = ORB` allies: `OrbModule` + `OrbWeaponVisual` scene.

### Step 2: Create the model scene

- BLADE: new `.tscn` under `scenes/battle/weapons/` — `Node3D` root, instanced GLB/mesh child, `WeaponTrail` + `trail_top`/`trail_bottom` markers.
- ORB: base it on `prism_orb_weapon.tscn` or a minimal `OrbWeaponVisual` node (script `orb_weapon_visual.gd`); pre-author `OrbN` holders or let `setup_orbs` create them.

### Step 3: Create the weapon `.tres`

`database/weapons/items/[name].tres` — see "Weapon Resource Properties" and the examples below. Link every sub-resource and ext_resource explicitly; use the `WeaponModule` base script for the `modules` array element type.

### Step 4: Grant / equip it

- Add the path to `DEFAULT_WEAPON_PATHS` or `BONUS_WEAPON_PATHS` in `scripts/game_state/main/game_state.gd` (keyed by `Weapon.WType`), **or**
- add it to a party member's inventory in `database/party/recruitables.tres` / inspector and set `equipped_weapon`, **or**
- call `member.equip_weapon(weapon)` at runtime (must match `member.weapon_type`).

### Step 5: Verify

```
Godot_v4.6.2-stable_win64_console.exe --headless --import
```

Then run the game, enter battle, equip the weapon, and confirm: model appears in hand/orbit, stat modifiers apply, effects proc on the right triggers, modules spawn their runtime children (check the `WeaponSystem` node's children in the remote tree — expect `OrbSystem`/`HitEcho` nodes).

## Complete .tres Examples

### Plain blade with generic effects (`soldiers_blade.tres` pattern)

```
[gd_resource type="Resource" script_class="Weapon" format=3]

[ext_resource type="Script" path="res://database/weapons/weapon.gd" id="1_weapon"]
[ext_resource type="Script" path="res://database/weapons/weapon_effect.gd" id="2_fx"]
[ext_resource type="Resource" path="res://database/states/resources/bleed_state.tres" id="3_bleed"]
[ext_resource type="PackedScene" path="res://scenes/battle/weapons/soldiers_blade.tscn" id="4_model"]

[sub_resource type="Resource" id="1_bleed_proc"]
script = ExtResource("2_fx")
value = 15.0
chance = 0.15
state = ExtResource("3_bleed")
state_accumulation = 15

[resource]
script = ExtResource("1_weapon")
model_scene = ExtResource("4_model")
effects = Array[ExtResource("2_fx")]([SubResource("1_bleed_proc")])
item_name = "Soldier's Blade"
description = "..."
```

### Blade with a module (`elf_leaf_blade.tres` pattern)

```
[ext_resource type="Script" path="res://database/weapons/weapon_module.gd" id="4_mod_base"]
[ext_resource type="Script" path="res://database/weapons/hit_echo_module.gd" id="4_echo_mod"]
[ext_resource type="PackedScene" path="res://scenes/battle/weapons/elf_leaf_blade.tscn" id="5_model"]

[sub_resource type="Resource" id="3_hit_echo"]
script = ExtResource("4_echo_mod")
echo_delay = 0.25
echo_damage_fraction = 0.3333

[resource]
script = ExtResource("1_weapon")
model_scene = ExtResource("5_model")
effects = Array[ExtResource("2_fx")]([...])
modules = Array[ExtResource("4_mod_base")]([SubResource("3_hit_echo")])
attack_bonus = 1
item_name = "Elven Leaf Blade"
```

### ORB weapon (`prism_circuit.tres` pattern)

```
[ext_resource type="Script" path="res://database/weapons/orb_module.gd" id="3_orb_mod"]
[ext_resource type="Script" path="res://database/weapons/orb_definition.gd" id="2_orb"]
[ext_resource type="PackedScene" path="res://scenes/battle/weapons/prism_orb_weapon.tscn" id="5_visual"]

[sub_resource type="Resource" id="1_ember"]
script = ExtResource("2_orb")
orb_name = "Ember"
color = Color(1, 0.35, 0.1, 1)
state = ExtResource("burning")
damage = 6
damage_is_attack_percent = true
chance = 0.9
element = "fire"
attuned_effect = SubResource("0_attuned_dmg")
# ... more OrbDefinition sub-resources ...

[sub_resource type="Resource" id="4_orb_module"]
script = ExtResource("3_orb_mod")
orbs = Array[ExtResource("2_orb")]([SubResource("1_ember"), SubResource("2_tide"), SubResource("3_volt")])

[resource]
script = ExtResource("1_weapon")
model_scene = ExtResource("5_visual")
modules = Array[ExtResource("mod_base")]([SubResource("4_orb_module")])
item_name = "Prism Circuit"
```

Note: an ORB weapon needs **no** `weapon_type` field — `equip_kind()` returns `ORB` automatically because `OrbModule` is present.

## Adding a Brand-New Mechanic

When no existing module fits:

1. **Data:** create `database/weapons/[name]_module.gd` — `class_name XModule extends WeaponModule` with `@export` config fields; implement `create_runtime()` to return your runtime node (call `runtime.setup(...)` before returning) and optionally `get_damage_dealt_multiplier()`.
2. **Runtime:** create `scripts/systems/battle/weapons/[name]_system.gd` — `extends Node`; read config from the module, hook `SignalBus.card_hit_resolved`, `Battler.hit_moment`, or call `weapon_system.notify_attack_hit`/`run_effect`/`make_state`/`get_battle_manager` as needed. Ignore `info.is_replay` if the mechanic must not echo.
3. **Wire:** nothing else — `WeaponSystem._ready` picks it up from `weapon.modules` automatically.
4. **Content:** add the module as a sub-resource in the weapon's `modules` array.

Do **not** add fields to `weapon.gd`, branches in `weapon_system.gd`, or weapon checks in `battlemanager.gd`/`card_battle_manager.gd`/`battler.gd`.

## Pitfalls

1. **Stale `.tres` while running:** weapon resources are cached per process and the equipped weapon is a `duplicate()` made at game start. **Restart the game** after editing a weapon `.tres` — replaying a battle in the same session keeps old values.
2. **`modules` array element type:** use `weapon_module.gd` (base) as the `Array[...]` element script, not the concrete module script. Godot normalizes this on save but hand-edited files must match.
3. **`echo_delay` location:** it lives inside the `HitEchoModule` sub-resource, not on `Weapon`. Same for any future module config — module fields live on module sub-resources.
4. **Node name `"Weapon"`:** socketed models MUST instance as a child named `Weapon` under the socket — animation method tracks depend on the path. Never rename.
5. **Trail markers:** `WeaponTrail` silently does nothing without `trail_top`/`trail_bottom` markers under it (it searches children then parent hierarchy). HitEcho recording is gated on trail emission — a weapon with no working trail records nothing and produces no ghost.
6. **Hostile-only procs:** `notify_attack_hit` drops same-team targets before any module/effect runs. Design modules accordingly.
7. **Replay recursion:** module runtimes listening to `SignalBus.card_hit_resolved` must check `info.is_replay` or they will echo echoes.
8. **`duplicate()` shares module objects:** the equipped weapon's modules are the same resource instances as the `.tres` template — fine for config data; keep per-run state on runtime nodes, never on module resources.
9. **ORB visual adoption:** `OrbWeaponVisual` adopts scene-authored `OrbN` nodes by name — keep that naming if authoring custom orb scenes.
10. **Type-locking:** `AllyPartyMember.weapon_type` (0=BLADE, 1=ORB) gates equipping. A weapon with an `OrbModule` can never be equipped by a BLADE ally and vice versa.
