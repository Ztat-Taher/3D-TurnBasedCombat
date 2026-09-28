# Animation Callback Setup Guide

This guide explains how to add method tracks to attack animations for the animation callback-based timing system.

## Overview

The system uses AnimationPlayer method tracks to trigger callbacks at specific points in the animation timeline:
- `_on_attack_start()` - Called at animation start frame
- `_on_attack_hit()` - Called at hit moment frame
- `_on_attack_end()` - Called at animation end frame

**Note**: The callback methods are already implemented in `battler.gd`. This guide is for adding the method tracks to animations.

## Which Animations Need Callbacks

### Ally Animations (y_bot-ally.tscn)
- `sword_02/sword_combo_attack_01_var002` (melee_combo_1)
- `sword_02/sword_combo_attack_02_var001` (melee_combo_2)
- `sword_02/sword_combo_attack_03_var001` (melee_combo_3)
- `sword_02/sword_attack_up_var001` (ranged_cast_1)
- `sword_02/sword_attack_down_var001` (ranged_cast_2)

### Enemy Animations (enemy.tscn)
- `monster_01/monster_swipe_var001` (melee_combo_1)
- `monster_02/zombie_kick_var001` (melee_combo_2)
- `monster_03/slime_jump_var001` (melee_combo_3)
- Any other attack animations used by enemies

## How to Add Method Tracks

### Step 1: Open the Scene
1. Open the ally scene: `scenes/battle/core/allies/models/y_bot-ally.tscn`
2. Select the `AnimationPlayer` node
3. Open the Animation panel (bottom of the editor)

### Step 2: Select the Animation
1. In the Animation panel, select the animation to modify (e.g., `sword_02/sword_combo_attack_01_var002`)
2. Make sure the animation is in edit mode (not playback)

### Step 3: Add Method Track
1. Click the "Add Track" button in the Animation panel
2. Select "Call Method Track"
3. In the Path field, type: `.` (this refers to the root node of the scene)
4. Click "Add Track"

### Step 4: Add Start Callback
1. At frame 0 (or the first frame of the animation), right-click on the method track
2. Select "Insert Key"
3. In the method name field, type: `_on_attack_start`
4. Click "OK"

### Step 5: Add Hit Callback
1. Navigate to the frame where the attack hits the target
   - For melee attacks: usually around 50-60% of the animation
   - For ranged attacks: usually when the projectile should spawn
2. Right-click on the method track at that frame
3. Select "Insert Key"
4. In the method name field, type: `_on_attack_hit`
5. Click "OK"

### Step 6: Add End Callback
1. Navigate to the last frame of the animation
2. Right-click on the method track at that frame
3. Select "Insert Key"
4. In the method name field, type: `_on_attack_end`
5. Click "OK"

### Step 7: Repeat for Other Animations
Repeat steps 2-6 for all attack animations that need callbacks.

## Example Timing Reference

### Melee Combo 1 (1.6 seconds)
- Start: Frame 0
- Hit: Frame ~30 (where the sword connects with target)
- End: Frame 48

### Ranged Cast 1 (1.5 seconds)
- Start: Frame 0
- Hit: Frame ~25 (where the attack motion completes)
- End: Frame 45

**Note**: The hit moment is now defined by the actual animation frame where the attack connects, not by a fixed ratio. Adjust the hit callback frame based on visual feedback.

## Verification

After adding the method tracks:
1. Play the animation in the editor
2. Check the console output for callback messages:
   ```
   [Battler] Attack start callback: [character_name]
   [Battler] Attack hit callback: [character_name]
   [Battler] Attack end callback: [character_name]
   ```

## Troubleshooting

### Callbacks not firing
- Ensure the method names are exactly: `_on_attack_start`, `_on_attack_hit`, `_on_attack_end`
- Check that the AnimationPlayer is on the correct node path
- Verify the scene root node has the Battler script attached

### Timing feels off
- Adjust the hit callback frame earlier or later based on visual feedback
- Test with actual combat to ensure damage timing feels right
- Consider projectile travel time for ranged attacks

### Multiple callbacks firing
- Ensure only one keyframe per callback method
- Check for duplicate method tracks

## Notes

- The callback methods are already implemented in `battler.gd`
- These callbacks replace the old timer-based hit_frame_ratio system
- Defense timing is now automatically aligned with the hit callback
- The system is more flexible and can be tuned per-animation
- Multi-strike cards use the same callback system - each strike's animation should have its own method tracks
- The `attack_end` callback is critical for multi-strike sequences to ensure proper chain timing