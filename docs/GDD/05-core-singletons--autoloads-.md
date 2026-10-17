# Core Singletons (Autoloads)

These systems persist across scenes and manage the global state of the game and combat engine.

- **`GlobalBattleSettings`**: Central hub for combat enums (Teams, Elements, Target Types), global damage multipliers, and shared audio stream references.
- **`GameState`**: Manages the persistent run data, including current party members, inventory, and progression flags.
- **`SignalBus`**: Facilitates decoupled communication between UI components, the camera system, and the BattleManager.
- **`PartyBattleSync`**: Orchestrates the transfer of stats (HP, XP, Decks) between the persistent `AllyPartyMember` resources and the active `Battler` nodes in a scene.
- **`DifficultyManager`**: Applies global scaling factors to damage, defense, and rewards based on the selected difficulty level.
- **`SaveLoader`**: Handles the serialisation and de-serialisation of the run state to disk.