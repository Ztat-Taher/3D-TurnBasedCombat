# Combat Mechanics: Cards & Defense

## Card System

Cards are Godot Resources (`CardData.tres`). 

### AP Management
- Allies start with 3 AP.
- Each card play deducts AP.
- Turn ends automatically if AP hits 0, or manually via "End Turn".

### QTE Logic

During card animation, a `hit_moment` signal is emitted. 
- **Success Window**: 0.2s.
- **Effect**: Increases `base_power` by a 1.5x multiplier.

## Real-Time Defense

Active during `ENEMY_TURN` state.

- **Q** — Action: Parry · Timing: 0.15s before hit · Window: Frame-perfect
- **E** — Action: Dodge · Timing: 0.25s before hit · Window: Standard
- **Space** — Action: Jump · Timing: 0.25s before hit · Window: Specialized

### Counter Attacks

Successful Parries trigger a `counter_stun` on the enemy. The player battler immediately performs a `melee_combo` animation, dealing 1.5x damage.