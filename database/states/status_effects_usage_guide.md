# States (status effects): guide

A **state** is a status effect on a battler: Burning, Protected, Taunt... Every
state is a `State` resource (`database/states/states_template.gd`). Its rules
live in its own script, through **hooks** that the battle calls on every state a
battler holds. The battle, the HUD and the AI never name a state: adding one
means adding a resource (and, if it needs rules of its own, a script), and
touching nothing else.

A battler holds one state per `state_name`, in `battler.active_states`.

## The states

| State | Kind | What it does | Ends |
|---|---|---|---|
| Burning | DOT, stacks (max 10) | 5 damage per stack each turn start (defense doesn't reduce it), then a stack burns out. Each application adds stacks | When its stacks burn out |
| Bleed | DOT, bar | Damage taken fills a hidden bar (half of each hit). Full: 20% of max HP and the bar empties. A new application adds its own bar; a full bar procs at once | Cured |
| Chilled | Debuff | Skips its battler's turns | 1 turn |
| Stunned | Debuff | Skips its battler's turns (plain resource, no script) | The STUN card effect's value |
| Electrocuted | Debuff | Takes 1.5x damage, deals 0.5x | 2 turns |
| Marked | Debuff | The next attack on it deals 1.5x and spends the mark. Bonus damage is neither boosted nor spends it | 3 turns, or spent |
| Berserk | Buff | Deals 1.5x damage, takes 1.25x | 2 turns |
| Taunt | Buff | Enemy AI must target its battler. Optionally breaks after enough attack damage | 2 turns |
| Protected | Buff | Each shield hit blocks one whole hit (damage and on-hit effects). Shown as the shield row | When its hits are used |
| Counter | Counter | Strikes back at an attacking opponent with a normal attack, up to 2 times per turn | Cured |

Resources: `database/states/resources/`. Card applications (duration, stacks,
chance): `database/state_configs/`.

## Applying a state

Every way of applying a state builds its copy with `State.make_instance()`,
then hands it to `Battler.apply_state()`:

```gdscript
# As authored
target.apply_state(BURNING.make_instance(), source)

# make_instance(duration, stacks, accumulation):
#   duration     turns; 0 = as authored, -1 = until something else ends it
#   stacks       stacks this application adds; -1 = as authored
#   accumulation bar (Bleed) this application adds; 0 = as authored
target.apply_state(BURNING.make_instance(0, 3), source)        # 3 stacks
target.apply_state(BLEED.make_instance(0, -1, 15), source)     # a 15 bar
target.apply_state(STUNNED.make_instance(2), source)           # 2 turns
```

`source` is the battler applying it. It's credited with the state's damage
(the XP for a Burning kill).

- **Cards:** a `StateConfig` on the card (chance, duration, stacking
  behaviour, target). `StateConfig.apply_state(target, actor)` does the
  above. Stacking behaviour: ADDITIVE adds `stacks_per_application`,
  MULTIPLICATIVE doubles, REFRESH re-applies without adding stacks.
- **Card effects:** SHIELD (Protected hits), STUN (turns), CURE / DISPEL (see
  below).
- **Weapons and orbs:** a `WeaponEffect` / orb with `state`,
  `state_stack_count`, `state_accumulation`.
- **Vestiges:** e.g. `gain_shield_on_trigger.gd`.

Re-applying a state the battler already has **merges** it into the one on:
by default it adds the stacks (up to `stack_max`) and refreshes the duration.
A state script can merge differently (Protected adds hits, Bleed adds its bar,
Taunt restarts its damage count).

A defeated battler takes no new states, and loses all of its states.

## Removing a state

```gdscript
battler.remove_state("Burning")
battler.clear_states()
battler.remove_states_if(func(s: State): return s.is_harmful(), 1)  # oldest first; 0 = all
```

Card effects **CURE** (harmful states) and **DISPEL** (helpful states) remove
`value` of them, oldest first (0 = all), skipping states with
`can_be_cured = false`. Harmful = `state_type` DOT or DEBUFF
(`State.is_harmful()`).

## Generic fields (no script needed)

| Field | Effect |
|---|---|
| `turns_active` | Duration: ticks down at the start of its battler's turns (1 = until its battler's next turn starts). -1 = until something else ends it |
| `skip_turn` | Its battler skips its turns |
| `is_taunting` | Enemy AI must target its battler |
| `damage_per_turn` | Damage at the start of its battler's turns, reduced by defense |
| `heal_per_turn` | HP its battler regains at the start of its turns (a heal: healing multipliers, the HEALED event) |
| `damage_taken_multiplier` / `damage_dealt_multiplier` | Incoming / outgoing damage |
| `hit_chance` | Chance (%) its battler's attacks hit. Several multiply: 60 and 80 give 48 |
| `stack_count` / `stack_max` | Stacks. `stack_max` 1 = doesn't stack (no badge) |
| `accumulation_value` / `accumulation_max` | A bar that procs when full |
| `overlay_material` / `aura_effect` | Shown on the battler while the state is on (the aura plays its "open" / "close" animations) |
| `state_type` / `can_be_cured` | For CURE / DISPEL |

So a simple state is just a `State` resource: a weakness debuff with
`damage_dealt_multiplier = 0.7` and a duration, a Regen buff with
`heal_per_turn`, a blinding debuff with `hit_chance = 60`.

## Hooks (a state with rules of its own)

Extend `State` and override what you need. `owner` is the battler holding it.

| Hook | When | Example |
|---|---|---|
| `modify_damage_dealt(damage, owner, hit)` | Its battler deals damage | Electrocuted (default: the multiplier) |
| `modify_damage_taken(damage, owner, hit)` | Its battler takes damage | Marked |
| `modify_hit_chance(chance, owner, hit)` | Its battler attacks (default: x `hit_chance`) | |
| `blocks_hit(owner, hit) -> bool` | Before a hit lands: true stops it outright | Protected |
| `on_hit_taken(owner, hit)` | After a hit lands (awaitable: the hit waits) | Bleed, Taunt, Counter |
| `get_turn_damage(owner) -> int` | Its battler's turn starts | Burning |
| `get_turn_heal(owner) -> int` | After the turn damage (default: `heal_per_turn`) | |
| `on_turn_tick(owner)` | After the turn damage | Burning (a stack burns out) |
| `is_expired() -> bool` | After the tick: true removes it | Burning (no stacks) |
| `on_any_turn_start(owner)` | Any battler's turn starts | Counter (uses reset) |
| `merge(incoming, owner)` | Re-applied | Protected, Bleed, Taunt |
| `on_applied(owner)` / `on_removed(owner)` | Put on / taken off | Bleed (procs a full bar) |
| `get_shield_hits() -> int` | The HUD's shield row | Protected |

`hit` holds: attacker, target, damage (in `on_hit_taken`: the HP lost),
damage_type, element, is_attack, is_critical. **`is_attack`** is false for
bonus damage (weapon and orb procs): Marked, Taunt, Counter and on-hit effects
only react to attacks.

Turn damage from states (Burning) is not an attack: nothing blocks it or
reacts to it, but it is damage taken and dealt (events, revive vestiges), and a
lethal tick defeats its battler like a hit does.

## HUD

The battler emits **`states_changed`** whenever a state is applied,
re-applied, ticked or removed. A state that changes itself mid-turn emits it
too (Protected using a hit, Bleed's bar filling). The status icons, the
shield rows (`Battler.get_shield_hits()`) and the bars redraw on it. Stack
badges show only for stacking states.

Battle events (vestiges, weapons): `STATE_APPLIED` and `STATE_INFLICTED` (to
the source) carry the state as it now is on the battler and `reapplied`;
`STATE_REMOVED` carries the state taken off.

## Adding a state

1. **Only generic fields:** create a `State` resource in
   `database/states/resources/`, set its name, icon, type and fields.
2. **Rules of its own:** a script `extends State` with a `class_name`, its
   defaults in `_init()`, and the hooks it needs; then its resource.
3. **For cards:** a `StateConfig` in `database/state_configs/` pointing to the
   resource, on the card.

Nothing else needs to change.
