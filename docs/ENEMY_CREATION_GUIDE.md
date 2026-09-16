# Enemy Creation & Configuration Guide

This guide walks through creating, configuring, and deploying new enemy battlers in the 3D Turn-Based Combat system.

---

## 1. Architecture Overview

Enemies in this project are decoupled from ally/player systems:
- **Allies** use [`BattlerStats.gd`](res://scripts/systems/battle/battlers/stats/BattlerStats.gd) (AP, AP regen, card decks, level progression multipliers).
- **Enemies** use [`EnemyStats.gd`](res://scripts/systems/battle/battlers/stats/EnemyStats.gd) and [`EnemyAttackConfig.gd`](res://scripts/systems/battle/battlers/stats/EnemyAttackConfig.gd).
- Both ally and enemy characters share [`battler.gd`](res://scripts/systems/battle/battlers/main/battler.gd) as their base controller, which automatically detects whether `enemy_stats` or `stats` is assigned.

```
Enemy Scene (.tscn)
 └── Root (Battler - battler.gd)
      └── enemy_stats: EnemyStats (.tres or inlined)
           ├── enemy_name: String
           ├── is_boss: bool (cinematic top-center health bar)
           ├── Combat Stats (max_health, attack, defense, agility, element)
           ├── attacks: Array[EnemyAttackConfig]
           │    ├── attack_name: String (e.g. "Heavy Slam")
           │    ├── animation_name: String (e.g. "attack", "kick")
           │    ├── damage_multiplier: float (e.g. 1.5)
           │    ├── hit_frame_ratio: float (-1.0 to use battler default)
           │    ├── move_announcement_type: String ("attack", "heal", "buff")
           │    └── weight: float (AI selection weighting)
           └── Battle Rewards & Drops (exp_reward, cash_reward, item_drops)
```

---

## 2. Step-by-Step Enemy Creation

### Option A: Duplicating / Inheriting from Base Template (Fastest)

1. In Godot FileSystem, locate `res://scenes/battle/core/enemies/enemy.tscn` or `res://scenes/battle/core/allies/models/y_bot-ally.tscn`.
2. Right click -> **New Inherited Scene** (or duplicate `enemy.tscn`).
3. Save your new scene under `scenes/battle/core/enemies/` (e.g. `goblin_scout.tscn` or `boss_dragon.tscn`).

### Option B: Creating from Scratch

1. Create a `CharacterBody3D` root node and attach `res://scripts/systems/battle/battlers/main/battler.gd`.
2. Add the required child nodes:
   - `CollisionShape3D`
   - 3D Model / `Armature` with `AnimationPlayer` and `AnimationTree`
   - `DamageIndicator` (`Node3D` -> child `SubViewport` -> child `Sprite3D`)
   - `BattlerTarget` (`Marker3D` positioned at chest height, e.g. `(0, 1.25, 0)`)
3. In the Inspector for the root node, leave `stats` empty and assign **`enemy_stats`**.

---

## 3. Configuring `EnemyStats`

Create a new `EnemyStats` resource either inlined inside the Inspector or saved as a `.tres` file (e.g., `database/enemies/goblin_stats.tres`).

### Core Attributes
- **`enemy_name`**: Display name shown in targeting UI and battle logs (e.g., `"Iron Golem"`).
- **`is_boss`**: Set to `true` for major encounters. When active, `battlehud.gd` displays the large cinematic boss health bar across the top of the screen instead of normal health indicators.
- **`thumbnail`**: Icon texture shown in targeting/turn order indicators.

### Combat Stats
- **`max_health`**: Total hit points (e.g., `120`).
- **`attack`**: Base physical/skill offensive power.
- **`defense`**: Damage mitigation stat.
- **`agility`**: Determines turn order priority in combat.
- **`element`**: Elemental alignment using `GlobalBattleSettings.Elements` (`Physical`, `Fire`, `Water`, `Earth`, `Wind`, `Light`, `Dark`).

### Battle Rewards & Drops
- **`exp_reward`**: Experience granted to player party upon defeat.
- **`cash_reward`**: Currency rewarded upon defeat.
- **`item_drops`**: Array of `EnemyDrop` resources:
  - `item`: Reference to item resource (e.g. `apple.tres`).
  - `drop_chance`: Percentage chance from `0.0` to `100.0`.

---

## 4. Configuring Enemy Attacks (`EnemyAttackConfig`)

Enemies choose their actions using their `attacks` list rather than card decks. In the `EnemyStats` resource under **Attacks & Skills**, add items to the `attacks` array:

| Property | Type | Description |
| :--- | :--- | :--- |
| `attack_name` | String | Displayed on the screen via HUD banner (e.g., `"Poison Sting"`). |
| `animation_name` | String | Animation state in `AnimationTree` or clip name in `AnimationPlayer` (e.g., `"attack"`, `"kick"`). |
| `damage_multiplier`| float | Damage scale factor applied to base attack damage (`1.0` = standard, `1.5` = heavy). |
| `hit_frame_ratio` | float | Exact contact frame timing (`0.0` - `1.0`). `-1.0` uses the default battler contact frame (`0.55`). |
| `move_announcement_type` | String | Visual styling for the announcement banner: `"attack"` (red/hostile), `"heal"`, or `"buff"`. |
| `weight` | float | AI selection probability weight (higher values = chosen more frequently). |
| `description` | String | Optional editor notes describing the attack. |

> **Note:** If an enemy has no entries in `attacks`, the AI falls back safely to the battler's default basic attack animation.

---

## 5. Integrating with Troop Encounters

To place your new enemy in battle:

1. Open or create an **`EnemyGroup`** resource (`database/troops/enemy_group.gd`):
   - Add your enemy `.tscn` to the `enemy_scenes` array.
2. Open or create a **`Troops`** resource (`database/troops/troops_template.gd`):
   - Link the `EnemyGroup`.
   - Select formation: `FRONT_ROW`, `TRIANGLE`, `CIRCLE_PLAYER`, or `CUSTOM_MARKERS`.
3. In `battlemanager.gd` (or on your battle scene instance), set the troop encounter to test.
