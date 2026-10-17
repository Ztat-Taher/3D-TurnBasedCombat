# Key Combat Classes

### 2.1 BattleManager (`battle_manager.gd`)
The central orchestrator of the battle loop. It manages:
- Spawning allies and enemies via `Troops` resources.
- Turn order calculations based on Agility stats.
- Transitioning between UI states (Player Turn, Enemy Turn, Execution).
- Checking win/loss conditions.

### 2.2 Battler (`battler.gd`)
The base unit for all combatants (NPCs and Players). Inherits from `Node3D` and contains:
- **`active_states`**: A dictionary tracking current `State` resources (Buffs/Debuffs).
- **`stats`**: A reference to the underlying `BattlerStats` or `EnemyStats` resource.
- **`AnimationTree`**: Logic for managing movement, attacks, and hit reactions.

### 2.3 RealTimeDefenseManager
Specifically handles the timing-based input windows for Parry, Dodge, and Jump during the `ENEMY_TURN` state. It communicates with the `AttackIndicator3D` to provide visual feedback.

### 2.4 Formulas
A static utility class containing the mathematical logic for damage calculation, status effect procs, and the exponential experience curve.