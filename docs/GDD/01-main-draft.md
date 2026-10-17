# 3D Turn-Based Combat System — Game Design Document

**Project:** Cute Fame 3D (Working Title)  
**Studio:** Cute Fame Studio  
**Engine:** Godot 4.x  
**Date:** October 2026  
**Version:** 1.1 (Formatting Pass)

---

## Table of Contents

1. [Game Overview](#1-game-overview)
2. [Core Design Pillars](#2-core-design-pillars)
3. [Game Flow & Structure](#3-game-flow--structure)
4. [Combat System](#4-combat-system)
5. [Card System](#5-card-system)
6. [Real-Time Defense System](#6-real-time-defense-system)
7. [Characters & Party](#7-characters--party)
8. [Enemies & AI](#8-enemies--ai)
9. [Status Effects](#9-status-effects)
10. [Items System](#10-items-system)
11. [Progression Systems](#11-progression-systems)
12. [HUD & Interface](#12-hud--interface)
13. [Camera System](#13-camera-system)
14. [Visual Systems](#14-visual-systems)
15. [Audio](#15-audio)
16. [Battle Configuration](#16-battle-configuration)
17. [Difficulty System](#17-difficulty-system)
18. [Technical Architecture](#18-technical-architecture)
19. [Content Catalog](#19-content-catalog)
20. [Planned & Unimplemented Features](#20-planned--unimplemented-features)

---

## 1. Game Overview

**Genre:** 3D Turn-Based JRPG Combat System

This project is an open-source, modular 3D turn-based combat system for Godot 4, developed by Cute Fame Studio. It serves both as a standalone battle system template and as the foundation for an in-development JRPG (working title: *Cute Fame 3D*).

The design philosophy draws heavily from:
- **RPG Maker** — modular, data-driven approach to combat scripting
- **Persona series** — card-based action selection, stylish HUD presentation
- **Final Fantasy** — classic turn-based structure, party management, enemy formations
- **Pokémon** — elemental type chart, stat-driven damage formulas
- **Elden Ring** — bleed accumulation mechanic
- **Clair Obscur: Expedition 33** — stacking burn mechanic, real-time dodge/parry

**Target Audience:** RPG players who enjoy strategy-driven turn-based combat with active skill expression during enemy turns.

**Platform:** PC (Keyboard + Mouse; Controller supported)

---

## 2. Core Design Pillars

### 2.1 Active Engagement in Every Turn
The player is never fully passive. Even during enemy turns, real-time defense inputs (dodge, parry, jump) keep the player engaged and reward skill.

### 2.2 Card-Based Tactical Expression
Actions are selected from a card hand rather than menus. Cards cost Action Points (AP), forcing meaningful choices about spending and hand management each turn.

### 2.3 Readable, Cinematic Battles
A dynamic camera system automatically choreographs cinematic angles for enemy attacks, move announcements, and key moments. Combat feels like watching an anime battle unfold rather than navigating a menu grid.

### 2.4 Modular and Extensible
All gameplay data (enemies, cards, status effects, items, battles, troops) is defined in Godot Resource files (.tres). New content can be added entirely through the editor without touching code.

### 2.5 Risk vs. Reward Through Timing
QTE windows on card execution reward precise timing with damage bonuses. Perfect parries convert defense into offense. The Berserk status is a deliberate trade-off. Skilled play amplifies outcomes.

---

## 3. Game Flow & Structure

### 3.1 High-Level Flow

```
Opening Scene
    ↓
Main Menu
    ↓
Game Scene (Run Manager / LevelManager)
    ↓
Battle Level 1 → Battle Level 2 → Battle Level 3 → ...
    ↓                                                  ↓
  WIN → next level                            DEFEAT → run ends
    ↓
Run Victory Screen
```

### 3.2 Run Structure

The game is structured as a **linear run of sequential battles**. The `LevelManager` advances the player through a list of battle levels defined in the `SceneLister`. Party state (HP, XP, items, decks) **persists between battles** via `PartyBattleSync` and `GameState`.

**Battle End Conditions:**

- **WIN** — Advance to next battle level
- **DEFEAT** — Run ends; run-over screen displayed
- **ESCAPE** — Replay the same battle
- **CUTSCENE** — Reserved for future story battles

### 3.3 Between-Battle Persistence

`AllyPartyMember` resources track per-ally state that survives between battles:
- Current and maximum HP
- Current level and total experience
- Current card deck composition
- Downed status (0 HP = ally starts next battle downed)

---

## 4. Combat System

### 4.1 Turn Structure

Combat is **initiative-based**. All combatants are sorted into a unified turn order by **Agility** at battle start. Higher agility = earlier turns.

**Each turn cycle:**
1. `start_next_turn()` — checks win/loss conditions first
2. Active status effects are processed (Burning damage, Chilled skip, etc.)
3. Counter state usage resets for all battlers
4. Current battler is determined from the turn queue
5. Player turns are driven by input (card selection); enemy turns are AI-driven and awaited
6. `end_turn()` advances the index and loops back to step 1

The **Turn Queue UI** displays upcoming combatants with portrait icons so the player can plan ahead.

### 4.2 Player Turn

On a player's turn:
1. Camera moves to an over-the-shoulder angle behind the active ally
2. The **Card UI** becomes visible — the player's hand is shown
3. The player selects a card, uses Items, or Escapes
4. Target selection activates if the card requires it
5. The card executes with full animation and optional QTE
6. `end_turn()` is called after card execution resolves

**Player Actions:**

- **Play a Card** — Core action — costs AP from the card's AP cost value
- **Use Item** — Opens the item menu (toggleable per battle)
- **Escape** — Attempt to flee (toggleable per battle)
- **End Turn** — Explicitly end the turn early, forfeiting remaining AP

### 4.3 Enemy Turn

On an enemy's turn:
1. Enemy overview camera pans across all enemies
2. AI selects an action via `AIManager`
3. Camera focuses on the acting enemy; **Move Announcement Banner** displays
4. Camera transitions to over-the-shoulder behind the targeted ally
5. Attack animation plays; the **Real-Time Defense window** opens
6. Damage resolves at the animation's hit frame
7. `end_turn()` is called after the action resolves

### 4.4 Damage Formula

```
offense  = attacker.attack + card.base_power
defense  = target.defense × 0.5
damage   = max(1, offense − defense)
final    = damage × element_multiplier × difficulty_multiplier × state_multipliers
```

Minimum damage is always **1** — stats alone cannot fully negate an attack.

### 4.5 Defense Result Modifiers

- **Perfect Parry** — 0× + counter-attack triggered
- **Dodge / Jump** — 0×
- **Defending (Defend card)** — 0.5×
- **None (no input / missed window)** — 1× full damage

### 4.6 Action Points (AP)

Each ally has an AP pool that **fully recharges** at the start of their turn.

- **Max AP** — 3
- **AP Regen per Turn** — 3

Cards cost 1–4 AP. When AP is exhausted no more cards can be played and the turn must end.

### 4.7 Battle Speed

Hold the speed key (default: `Confirm`) to fast-forward animations at a configurable multiplier (default: **3×**). Toggle mode or hold mode — configurable in `BattleManager`.

### 4.8 Turn Safety Timeout

A configurable timeout (default: **10 seconds**) auto-advances the turn if a battler gets stuck, preventing soft-locks.

---

## 5. Card System

### 5.1 Overview

Cards are the primary means of player action. The player draws from a personal **deck** into a **hand** and selects cards to play each turn. This introduces variability and hand-management decisions across a run.

### 5.2 Card Properties

Each `CardData` resource defines:

- **Name / Description** — Display text
- **AP Cost** — 1–4 points drawn from the player's pool
- **Base Power** — Additive damage/heal value
- **Target Type** — Single enemy, AOE enemies, single ally, all allies, self
- **Animation Name** — Battler animation triggered on use
- **Element** — Elemental type for effectiveness
- **Effect Type** — Damage, Heal, Buff, Status, Revive
- **State Applications** — Array of status effects applied on hit
- **Card Config** — Optional resource for QTE/timing settings

### 5.3 Card Execution Flow

1. Player selects a card from hand
2. Target selection (if required)
3. UI transitions to `CARD_EXECUTION_STATE` — all panels hidden
4. Card animation plays on the battler
5. QTE window opens during the animation (if configured)
6. Damage/healing/effects resolve at the animation's hit frame
7. UI returns to player turn state

### 5.4 Quick Time Events (QTE)

Cards with QTE windows reward accurate timing:

- **Success (timed press)** — 1.5× (configurable)
- **Failure (missed)** — 0.8× (configurable)

**Multi-Strike Cards** (e.g., Flurry Attack): each individual hit has its own QTE window, with multipliers increasing per strike to reward sustained accuracy.

**QTE Configuration** (`QTEConfig` resource):

- **`card_qte_enabled`** — Toggle globally
- **`default_card_qte_difficulty`** — 0.0 (easy) to 1.0 (hard); affects window size
- **`base_qte_time`** — Base countdown timer for countdown QTEs
- **`qte_input_key`** — Input action name for QTE presses

### 5.5 Deck System

- Each ally has a personal `DeckResource`
- Decks are per-ally — card rewards can target specific party members
- Default decks are defined in `BattlerStats`
- Decks persist between battles via `AllyPartyMember.deck`

---

## 6. Real-Time Defense System

### 6.1 Overview

During enemy attacks, the player can execute **real-time defensive actions** within a brief input window. This converts what would otherwise be a passive damage-taking moment into an active skill-expression opportunity.

### 6.2 Defense Types

- **Parry** — Input: Q · Timing Window: 0.15s before hit · Effect: Negate all damage + trigger counter-attack
- **Dodge** — Input: E · Timing Window: 0.25s before hit · Effect: Negate all damage
- **Jump** — Input: Space · Timing Window: 0.25s before hit · Effect: Negate all damage (low-sweep attacks)

A **late forgiveness window** of 0.15s after the hit frame still accepts inputs, compensating for display lag.

### 6.3 Attack-Specific Defense Rules

Each `EnemyAttackConfig` declares which defenses are valid:

- **`can_dodge`** — Dodge avoids this attack
- **`can_parry`** — Parry counters this attack
- **`requires_jump`** — Only a jump avoids it — dodge and parry fail

### 6.4 Attack Indicators

A 3D indicator appears above the attacking enemy during the wind-up, communicating which input is needed:

- **Gold circle** — Dodge
- **Blue highlight** — Parry
- **Up arrow** — Jump

### 6.5 Perfect Parry Counter

A successful parry triggers an immediate counter-attack:
1. Attacker is **counter-stunned** (frozen in position)
2. Defender plays a melee combo animation
3. Counter damage = `defender.attack × 1.5`, processed through the standard damage formula
4. If the counter defeats the attacker, the battle loop advances immediately

### 6.6 Input Buffering

The system buffers the most recent input during the open window. A second press within the commit duration (0.6s) is ignored — deliberate timing is rewarded over spam.

---

## 7. Characters & Party

### 7.1 Party System

The player controls a party of allies defined in a `PartyData` resource (`database/party/player_party.tres`). The system is architected for multiple distinct party members with individual stats, scenes, and decks. Currently one player character is defined.

### 7.2 Ally Stats (`BattlerStats`)

- **Max Health** — Description: HP pool · Default (Lv 1): 100 · Growth / Level: +15
- **Attack** — Description: Damage dealt · Default (Lv 1): 10 · Growth / Level: +2
- **Defense** — Description: Damage reduction · Default (Lv 1): 5 · Growth / Level: +1
- **Agility** — Description: Turn order speed · Default (Lv 1): 5 · Growth / Level: +1
- **Max AP** — Description: Action points · Default (Lv 1): 3 · Growth / Level: +0
- **AP Regen** — Description: AP restored per turn · Default (Lv 1): 3 · Growth / Level: +0

**Level Scaling:** `stat = base_stat + (level − 1) × multiplier`

### 7.3 Team System

- **`TEAM.ALLY`** — Player-controlled; uses card system
- **`TEAM.ENEMY`** — AI-controlled; uses `EnemyStats` and `AIManager`

Team determines targeting rules, counter-attack eligibility, and XP award logic.

### 7.4 AllyPartyMember Resource

Per-run ally state tracked between battles:

- **`stats`** — Reference to `BattlerStats` resource
- **`level` / `exp_total`** — Current progression state
- **`current_health` / `max_health`** — Persists between battles
- **`deck` / `deck_path`** — Personal card deck
- **`ally_scene_path`** — 3D model scene to spawn in battle
- **`portrait_path`** — Portrait for out-of-battle UIs

---

## 8. Enemies & AI

### 8.1 Enemy Stats (`EnemyStats`)

Enemies use a lightweight stat resource with no level scaling or AP:

- **`enemy_name`** — Display name
- **`is_boss`** — Activates the cinematic boss health bar
- **`max_health`** — HP pool
- **`attack`** — Base attack value
- **`defense`** — Damage reduction
- **`agility`** — Turn order position
- **`element`** — Elemental type
- **`attacks`** — Array of `EnemyAttackConfig` resources
- **`exp_reward`** — XP granted to the killing ally
- **`cash_reward`** — Gold dropped on defeat
- **`item_drops`** — Array of `EnemyDrop` (item + drop chance %)

### 8.2 Enemy: Bone Marauder

The primary implemented enemy.

- **HP** — 200
- **Attack** — 1 (scaled by per-attack multiplier)
- **Defense** — 5
- **Agility** — 8
- **XP Reward** — 100
- **Gold Reward** — 41

**Attacks:**

- **Rib Swipe** — Dmg Multiplier: 1.0× · Defense Rules: Dodge only
- **Skull Crush** — Dmg Multiplier: 1.6× · Defense Rules: Parry only
- **Bone Sweep** — Dmg Multiplier: 1.2× · Defense Rules: Jump only (low sweep)
- **Fractured Frenzy** — Dmg Multiplier: 1.4× · Defense Rules: Dodge or parry

**Item Drops:**

- **Apple** — 30%
- **Orange** — 45%
- **Mystery Fruit** — 15%

### 8.3 Troop System

Enemies are grouped into **Troops** (`Troops` resource):

- **`troop_name`** — Display name
- **`enemy_group`** — `EnemyGroup` resource listing enemy scenes
- **`formation`** — Spatial arrangement type
- **`damage_reduction`** — Troop-wide incoming damage modifier

**Formation Types:**

- **FRONT_ROW** — Centered horizontal line, auto-spaced (default)
- **TRIANGLE** — Pyramid arrangement
- **CIRCLE_PLAYER** — Ring surrounding the player
- **CUSTOM_MARKERS** — Uses Marker3D nodes placed manually in the scene

Default formation spacing is **3.0 units** (configurable per `BattleManager`).

### 8.4 AI System (`AIManager`)

**AI Types:**

- **AGGRESSIVE** — Always attacks; targeting quality determined by Intelligence
- **DEFENSIVE** — Uses best healing item when HP < 40%; otherwise aggressive

**Intelligence (0–100):** Probability of making the optimal targeting choice (weakest target) vs. random. A value of 60 means 60% chance of smart targeting, 40% chance random.

**Taunt Override:** If any battler has the `Taunt` state active, all AI prioritises that target.

**Weighted Attack Selection:** Attacks are chosen via a weighted random roll across all `EnemyAttackConfig` entries in the enemy's `attacks` array.

### 8.5 Cinematic Enemy Turn Sequence

- **1. Enemy Overview** — Duration: 0.45s · Description: Camera pans all enemies
- **2. Target Focus + Banner** — Duration: 0.85s · Description: Focus on acting enemy; Move Banner displays
- **3. Banner hide** — Duration: — · Description: Banner fades out
- **4. Over-the-Shoulder** — Duration: 0.35s · Description: Camera behind the targeted ally
- **5. Attack Execution** — Duration: — · Description: Animation, defense window, damage
- **6. Return** — Duration: — · Description: Enemy returns to position; end_turn()

---

## 9. Status Effects

### 9.1 Elemental Chart

- **Physical** — Physical: 1.0× · Earth: 1.0× · Air: 1.0× · Fire: 1.0× · Water: 1.0× · Magic: 0.5×
- **Fire** — Physical: 1.0× · Earth: **2.0×** · Air: 1.0× · Fire: 1.0× · Water: **0.5×** · Magic: 1.0×
- **Water** — Physical: 1.0× · Earth: **0.5×** · Air: 1.0× · Fire: **2.0×** · Water: 1.0× · Magic: 1.0×

*(Earth, Air, and Magic attack rows are reserved for implementation.)*

### 9.2 Damage Over Time

**Burning** *(stacking DOT — inspired by Clair Obscur: Expedition 33)*
- Damage per turn: `stacks × 5`
- Stacks cap at 10; decay by 1 each turn end
- Duration: 3 turns (refreshed on reapplication)
- Visual: fire shader overlay

**Bleed** *(accumulation DOT — inspired by Elden Ring)*
- Fills an invisible accumulation bar: each point of damage taken adds 50% of that value to accumulation
- When accumulation reaches 100: deals **20% of target's max HP** as burst damage, then resets
- Duration: infinite until proc or cured

### 9.3 Debuffs

- **Electrocuted** — Key Effect: +50% incoming damage; −50% outgoing damage · Duration: 2 turns
- **Chilled** — Key Effect: Target skips their next turn entirely · Duration: 1 turn
- **Marked** — Key Effect: Next hit against this target deals 1.5× damage, then consumed · Duration: 3 turns
- **Weakness** — Key Effect: +50% incoming damage from all sources · Duration: Variable
- **Sleep** — Key Effect: Cannot act; immediately broken by any damage · Duration: Infinite until hit

### 9.4 Buffs

- **Protected** — Key Effect: Absorbs the next hit completely (damage + effects); configurable hit charges · Duration: Infinite until consumed
- **Counter** — Key Effect: Auto counter-attacks when hit: 1.5× damage, max 2 per turn · Duration: Infinite until cured
- **Berserk** — Key Effect: +50% damage dealt; +25% damage taken · Duration: 2 turns
- **Taunt** — Key Effect: Forces all AI to target this battler · Duration: 2 turns

### 9.5 Base State Properties

All states extend the `State` resource class:

- **`turns_active`** — Duration (−1 = infinite)
- **`can_be_cured`** — Removable by cure effects/items
- **`damage_per_turn`** — Base DoT value
- **`power_multiplier`** — Scales DoT with attacker's attack stat
- **`damage_taken_multiplier`** — Incoming damage scaling
- **`damage_dealt_multiplier`** — Outgoing damage scaling
- **`skip_turn`** — Whether afflicted battler skips their turn
- **`stack_count` / `stack_max`** — Stack tracking (Burning)
- **`accumulation_value` / `accumulation_max`** — Accumulation tracking (Bleed)
- **`shield_amount`** — Damage absorption hits (Protected)
- **`is_taunting`** — AI targeting override flag (Taunt)
- **`marked_damage_bonus`** — Damage amplifier value (Marked)

---

## 10. Items System

### 10.1 Item Properties

- **`item_name`** — Display name
- **`description`** — Tooltip text
- **`is_battle_item`** — Usable in combat
- **`is_key_item`** — Non-stackable; cannot be sold
- **`base_power`** — Base damage/healing value
- **`element`** — Elemental type
- **`target_type`** — Single, Multiple, or All
- **`skill_type`** — Healing, Throwable, or Buffs
- **`hp_delta`** — HP healed (+) or HP cost (−)
- **`effect_type`** — "Damage", "Heal", "Buff", etc.
- **`base_price`** — Shop / economy value
- **`can_be_sold`** — Whether the item can be sold

### 10.2 Item Catalog

**Healing Items**

- **Apple** — Heal: 30 HP · Target: Single · Notes: Common enemy drop
- **Orange** — Heal: Variable · Target: Single · Notes: Common drop
- **Banana** — Heal: Variable · Target: Single · Notes: Fruit
- **Grape Bunch** — Heal: Variable · Target: Single · Notes: Fruit
- **Watermelon** — Heal: Variable · Target: Single · Notes: Fruit
- **Electric Berry** — Heal: Variable · Target: Single · Notes: Electric elemental tag
- **Mystery Fruit** — Heal: Random · Target: Single · Notes: Rare; randomized effect
- **Holy Water** — Heal: 40 HP · Target: All Allies · Notes: AOE splash

**Revival Items**

- **Revive Potion** — Effect: Restore defeated ally to 50% max HP · Value: 200 gold

**Throwable / Damage Items**

- **Cursed Gold** — Damage: 55 · Notes: Gold coin projectile
- **Poison Apple** — Damage: 50 · Notes: Poisonous fruit
- **Stink Bomb** — Damage: 35 · Notes: AOE + Blind
- **Expired Milk** — Damage: Variable · Notes: Spoiled dairy weapon

### 10.3 Enemy Drop System

`EnemyDrop` resources define:
- `item` — Item resource reference
- `drop_chance` — Percentage probability (0–100)

Evaluated per enemy on defeat in `register_enemy_defeat_reward()`.

---

## 11. Progression Systems

### 11.1 Experience and Leveling

XP is awarded to the **killing ally** equal to `enemy_stats.exp_reward`.

**Level Up Threshold (exponential):**
```
exp_needed = 100 × pow(1.1, current_level − 1)
```

- **1 → 2** — 100
- **2 → 3** — 110
- **3 → 4** — 121
- **5 → 6** — ~146
- **10 → 11** — ~236

**On Level Up:**
- All stats recalculated with the multiplier formula
- HP fully restored
- Level Up VFX plays (3-second particle effect)
- `level_up` signal emitted; floating "+LEVEL UP" indicator appears

### 11.2 Battle Rewards

After each battle:
- **XP** — Awarded per kill to the killing ally
- **Gold** — Accumulated from all defeated enemies and added to party currency
- **Items** — Rolled from each enemy's drop table
- All rewards scaled by the active **Difficulty** multipliers

### 11.3 Party Persistence Between Battles

`PartyBattleSync` orchestrates HP state across the run:
1. **Before battle:** Spawns ally battlers and applies saved HP
2. **After battle:** Reads live HP from battlers and writes back to `AllyPartyMember`

Allies at 0 HP at battle end **start the next battle downed** unless revived by an item or rest site.

---

## 12. HUD & Interface

### 12.1 UI State Machine

- **`BASE_STATE`** — Default; action buttons visible
- **`CARD_SELECT_STATE`** — Card hand visible for selection
- **`ITEMS_MENU_STATE`** — Item list visible
- **`CARD_EXECUTION_STATE`** — All UI hidden during card animation
- **`TARGETING_STATE`** — Target selector active; card/item UI hidden

### 12.2 HUD Components

**Party Status Panel** — Bottom area; one card per ally showing portrait, HP bar, HP text, AP pips, and status effect icons. Updates in real-time as cards are played and effects change.

**Enemy Health Bars** — Top of screen; static panel per living enemy. Removed on death.

**Boss Bar** — Top-centre; triggered by `EnemyStats.is_boss = true`. Larger, cinematic health display reserved for boss encounters.

**Turn Queue UI** — Right side; scrollable list of portraits in upcoming turn order. Highlights the current actor. Updates dynamically when battlers die or skip turns.

**Card UI** — Bottom area; shows current hand with AP costs and names. Cards dim when unaffordable. End Turn button is integrated here.

**Items Menu** — Scrollable list of battle-usable items with icon, name, HP delta, and quantity.

**Move Announcement Banner** — Centre-top; appears during enemy turns to display the enemy name and move name with type-appropriate styling. Auto-hides before attack executes.

**Back Button** — Cancels current selection and returns to the previous UI state.

### 12.3 Number Indicators

Floating 3D numbers over battlers:

- **Damage** — Red/orange
- **Healing** — Green
- **Weakness proc** — Larger, emphasised
- **Shield break** — Dedicated shield-break visual
- **XP gain** — "+XP" on the killing blow attacker

### 12.4 Cursor System

A global `CursorManager` autoload provides custom cursor visuals. Supports simultaneous keyboard/controller and mouse input.

---

## 13. Camera System

A `BattleCamera` controller is dynamically instanced into every battle. Positions are calculated from 3D world space, accounting for any SubViewport scaling.

- **Default** — Trigger: Battle start / idle · Description: Wide overview of full battlefield
- **Enemy Overview** — Trigger: Enemy turn start · Description: Pans across all enemies
- **Target Focus** — Trigger: Post-overview · Description: Zooms on the acting enemy
- **Over-the-Shoulder** — Trigger: Player turn / defending · Description: Behind active ally, facing enemies

Transitions use deliberate pauses to create a cinematic rhythm (0.35–0.85s holds per step).

---

## 14. Visual Systems

### 14.1 Shader Overlay Stack

Battlers support a **priority-based overlay chain** for stacking visual effects:
- Each overlay has a `priority`, a `type` (STATUS or HIGHLIGHT), and a unique `key`
- Multiple effects can be active simultaneously without interfering
- Chain is rebuilt via `next_pass` on any add/remove

**Selection highlight** uses `battler_select_shader.gdshader`.
**Status overlays:** `fire_overlay.tres` (Burning), `lightning_overlay.tres` (Electrocuted).

### 14.2 Attack Indicators

`AttackIndicator3D` nodes above enemies show the required defense input during wind-up:

- **DODGE_ONLY** — Gold circle
- **PARRIABLE_ONLY** — Blue highlight
- **JUMPABLE** — Upward arrow

### 14.3 VFX

- **`vfx_level_up.tscn`** — Level up (3s lifetime)
- **Healing aura** — Any HP increase mid-battle
- **Spawn effect** — Digital-rise when allies enter battle
- **Status overlays** — Applied/removed with status effects

### 14.4 Animation System

- All battler animations use **AnimationTree** state machines
- Hit timing communicated via method track callbacks emitting `hit_moment` signal
- `AnimationMapping` resources allow character-specific name remapping (e.g., card uses "magic_cast", wizard character maps it to "wizard_spell_cast")
- Walking system: battlers physically advance to their target before melee and return to origin afterward

---

## 15. Audio

### 15.1 Sound Effect Slots

The `GlobalBattleSettings` singleton exposes audio stream references:

- **`hit_sound`** — Successful hit
- **`critical_sound`** — Critical hit
- **`miss_sound`** — Miss / evade
- **`escape_sound`** — Flee attempt
- **`enemy_defeat_sound`** — Standard enemy defeated
- **`boss_defeat_sound`** — Boss defeated

### 15.2 Voicelines

A `Voicelines` resource is assigned per `BattlerStats` for character-specific combat dialogue. The architecture is in place; audio assets are not yet populated.

---

## 16. Battle Configuration

Each battle can be customised with a `BattleConfig` resource passed to `GlobalBattleSettings.set_battle_config()` before the battle starts.

- **`battle_name`** — Encounter display name
- **`initial_ally_states`** — States applied to allies at battle start
- **`initial_enemy_states`** — States applied to enemies at battle start
- **`ally_damage_multiplier`** — Scale all player-dealt damage
- **`enemy_damage_multiplier`** — Scale all enemy-dealt damage
- **`ally_defense_multiplier`** — Scale player defense
- **`enemy_defense_multiplier`** — Scale enemy defense
- **`override_difficulty`** — Override the global difficulty for this battle
- **`experience_multiplier`** — Scale XP rewards
- **`gold_multiplier`** — Scale gold rewards
- **`is_story_battle`** — Flag for scripted narrative encounters
- **`allow_escape`** — Whether the Run button is available
- **`custom_tags`** — String tags for scripted event hooks

---

## 17. Difficulty System

Three global difficulties managed by `DifficultyManager`:

- **Player Damage** — Easy: 1.25× · Normal: 1.0× · Hard: 0.85×
- **Enemy Damage** — Easy: 0.75× · Normal: 1.0× · Hard: 1.25×
- **Enemy Defense** — Easy: 0.85× · Normal: 1.0× · Hard: 1.15×
- **Experience Reward** — Easy: 0.75× · Normal: 1.0× · Hard: 1.5×
- **Gold Reward** — Easy: 0.75× · Normal: 1.0× · Hard: 1.5×

**Design intent:** Hard mode is deliberately *more rewarding*, not just more punishing. Players earn 50% more XP and gold on Hard, accelerating progression for those who can survive. Easy mode eases combat at the cost of slower economic/levelling pace.

---

## 18. Technical Architecture

### 18.1 Core Autoloads / Singletons

- **`GlobalBattleSettings`** — Global combat config, enums, damage calc type
- **`GameState`** — Persistent run state (party, progression)
- **`SaveLoader`** — Save / load system
- **`SignalBus`** — Cross-scene signal relay (e.g. `select_target`)
- **`ItemHandler`** — Global item operations
- **`CursorSystem`** — Custom cursor management
- **`DifficultyManager`** — Static difficulty scaling class
- **`PartyBattleSync`** — Sync party state in and out of battles

### 18.2 Key Classes

- **`BattleManager`** — File: `scenes/battle/core/battle_manager/battlemanager.gd` · Role: Orchestrates full battle loop
- **`Battler`** — File: `scripts/systems/battle/battlers/main/battler.gd` · Role: Base class for all combatants
- **`BattleHud`** — File: `scenes/battle/hud/main_hud/battlehud.gd` · Role: Battle UI controller
- **`AIManager`** — File: `scripts/systems/battle/core/ai/ai_manager.gd` · Role: Enemy decision-making
- **`RealTimeDefenseManager`** — File: `scripts/systems/battle/real_time_defense/real_time_defense_manager.gd` · Role: Dodge/parry/jump system
- **`BattleCamera`** — File: *(dynamic node)* · Role: Dynamic camera controller
- **`CardIntegration`** — File: *(bridge)* · Role: Card system bridge to BattleManager
- **`Formulas`** — File: `scripts/systems/battle/progression/formulas/formulas.gd` · Role: All damage calculations
- **`DifficultyManager`** — File: `systems/difficulty/difficulty_manager.gd` · Role: Difficulty scaling

### 18.3 Resource Data Pipeline

```
BattlerStats.tres  ──►  AllyPartyMember.tres  ──►  PartyData.tres
EnemyStats.tres    ──►  Battler scene
CardData.tres      ──►  DeckResource.tres  ──►  AllyPartyMember
EnemyAttackConfig.tres  ──►  EnemyStats.tres
State subclass.gd  ──►  .tres instance  ──►  battler.active_states dict
Item.tres          ──►  Inventory  ──►  BattleManager item menu
Troops.tres        ──►  BattleManager.spawn_troop()
BattleConfig.tres  ──►  GlobalBattleSettings  ──►  BattleManager
```

### 18.4 Battle Scene Structure

```
BattleManager.tscn (Node3D)
├── BattleHUD (CanvasLayer)
│   └── Control
│       ├── PartyStatusPanel       ← ally HP / AP / status icons
│       ├── EnemyHealthBarsContainer ← per-enemy HP bars
│       ├── BossBar                ← cinematic boss HP bar
│       ├── TurnQueueUI            ← turn order portraits
│       ├── CardUI                 ← card hand display
│       ├── ActionButtons          ← End Turn / Items / Run
│       ├── Items                  ← item selection list
│       ├── MoveBanner             ← enemy move announcements
│       └── BackButton             ← cancel/back
├── [dynamic] BattleCameraController
├── [dynamic] EffectManager
├── [dynamic] RealTimeDefenseManager
├── [dynamic] CardIntegration
├── [group: players]  ally Battler nodes
├── [group: enemies]  enemy Battler nodes
└── FRONTROW Marker3D              ← enemy spawn reference point
```

---

## 19. Content Catalog

### 19.1 Cards

**Attack Cards**

- **Basic Attack** — AP: 1 · Damage: 10 physical · QTE: 1.2× on success
- **Flurry Attack** — AP: 2 · Damage: 15 × 3 hits · QTE: Per-hit QTE: 1.0× / 1.2× / 1.5×

**Status Effect Cards**

- **Bleed Strike** — AP: 2 · Effect: Apply Bleed
- **Burning Strike** — AP: 2 · Effect: Apply 3 Burning stacks
- **Electrocute** — AP: 2 · Effect: Apply Electrocuted (2 turns)
- **Ice Strike** — AP: 2 · Effect: Ice damage + Chilled
- **Ice Spear** — AP: 3 · Effect: Ice damage + freeze chance
- **Blizzard** — AP: 4 · Effect: AOE ice to all enemies + freeze chance

**Healing Cards**

- **Minor Heal** — AP: 2 · Effect: +15 HP to single ally
- **Group Heal** — AP: 4 · Effect: +10 HP to all allies

**Support Cards**

- **Shield** — AP: 2 · Effect: Grant 1 shield charge (single ally)
- **Group Shield** — AP: 4 · Effect: Grant shield charges to all allies

### 19.2 Status Effects Summary

- **Burning** — Type: DOT · Duration: 3 turns · Key Effect: `stacks × 5` damage/turn
- **Bleed** — Type: DOT · Duration: ∞ until proc · Key Effect: 20% max HP burst
- **Electrocuted** — Type: Debuff · Duration: 2 turns · Key Effect: +50% in / −50% out damage
- **Chilled** — Type: Debuff · Duration: 1 turn · Key Effect: Skip turn
- **Marked** — Type: Debuff · Duration: 3 turns · Key Effect: Next hit 1.5×
- **Weakness** — Type: Debuff · Duration: Variable · Key Effect: +50% incoming damage
- **Sleep** — Type: Debuff · Duration: ∞ until hit · Key Effect: Cannot act
- **Protected** — Type: Buff · Duration: ∞ until consumed · Key Effect: Absorbs next hit
- **Counter** — Type: Buff · Duration: ∞ until cured · Key Effect: Auto counter 1.5×
- **Berserk** — Type: Buff · Duration: 2 turns · Key Effect: +50% out / +25% in damage
- **Taunt** — Type: Buff · Duration: 2 turns · Key Effect: Forces AI targeting

### 19.3 Enemies

- **Bone Marauder** — HP: 200 · Atk: 1 · Def: 5 · Agi: 8 · XP: 100 · Gold: 41 · Type: Physical, AGGRESSIVE

### 19.4 Battle Maps

- **`maps/battle_scenes/example_scene.tscn`** — Main demo battle arena

### 19.5 Battle Levels (Run Sequence)

- **`battle_level_1.tscn`** — Battle 1
- **`battle_level_2.tscn`** — Battle 2
- **`battle_level_3.tscn`** — Battle 3

---

## 20. Planned & Unimplemented Features

The following have architectural hooks in the codebase but are not yet implemented:

### 20.1 Equipment System
**Status:** Enum definitions only in `GlobalBattleSettings`  
**Planned:** Weapon and armor slots affecting stats and visuals
- Weapon Types: Hands, Sword, Axe, Bow, Claws
- Armor Types: Regular, Light, Magic, Heavy, Metal

### 20.2 Skill Trees / Talent System
No implementation found. Intended for per-character ability unlock progression.

### 20.3 World Map / Overworld
No implementation found. Architecture supports non-linear run maps (a la Slay the Spire) connecting battles, shops, and rest sites.

### 20.4 Shop / Merchant System
Items have `base_price` and `can_be_sold` fields — economy scaffolding exists. No shop scene or transaction logic implemented.

### 20.5 Rest Sites
`AllyPartyMember.heal()` methods exist for this use case. No rest site scene implemented.

### 20.6 Card Reward System
Deck system supports post-battle card rewards. No reward selection UI found.

### 20.7 Multiple Named Party Members
Architecture fully supports distinct party members with different stats, scenes, and decks. Currently only one "Player" character is defined in the database.

### 20.8 Narrative / Story Content
`BattleConfig.is_story_battle` and `BattleEndCondition.CUTSCENE` are reserved. No story scenes, dialogue, or cutscene system found.

### 20.9 Voice Acting
`Voicelines` resource class is referenced in `BattlerStats`. No audio assets or playback implementation found.

### 20.10 Save / Load UI
`SaveLoader` autoload exists. No save UI or save point mechanics found.

### 20.11 Crafting
No crafting system found.