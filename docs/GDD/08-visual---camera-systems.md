# Visual & Camera Systems

### 4.1 Shader Overlay Stack
Battlers support a priority-based overlay chain for stacking visual effects. The `next_pass` chain is dynamically rebuilt whenever a status (like Burning or Electrocuted) is added or removed, ensuring high-priority highlights (like selection) always render on top.

### 4.2 State-Driven Battle Camera
The camera is a dynamic node that transitions between specific focus modes:
- **Overview**: Wide shot of the field.
- **Focus**: Close-up on the acting battler or target.
- **Over-the-Shoulder**: Positioned behind the defender to facilitate the Real-Time Defense system.