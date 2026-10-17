# Battle Scene Structure

Standard node structure for a combat encounter:

- **BattleManager (Node3D)**
  - **BattleHUD (CanvasLayer)**: Contains Party Panels, Turn Queue, and Card UI.
  - **BattleCameraController**: Manages cinematic pivots.
  - **RealTimeDefenseManager**: Logic for parry/dodge windows.
  - **AllyContainer/EnemyContainer**: Parents for spawned battler nodes.
  - **SpawnPoints**: Marker3D nodes for formation positioning.