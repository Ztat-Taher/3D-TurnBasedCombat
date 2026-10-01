# WeaponTrail Setup Guide

This guide explains how to set up and use the WeaponTrail effect for melee attack animations.

## Overview

The WeaponTrail is a visual effect that creates a glowing trail following a weapon during attack animations. It uses animation method callbacks to control when the trail appears and disappears, with automatic detection of blade marker nodes.

## Components

### 1. WeaponTrail Script
- Location: `assets/effects/slash/weapon_trail.gd`
- Type: MeshInstance3D with custom ImmediateMesh rendering
- Uses a shader material for the trail appearance

### 2. Blade Markers
Two Node3D markers are required to define the blade geometry:
- **trail_top**: Marker at the tip of the blade
- **trail_bottom**: Marker at the base/hilt of the blade

### 3. Animation Callbacks
Two callback methods control the trail:
- `_on_trail_start()`: Starts trail emission
- `_on_trail_end()`: Stops trail emission

## Setup Instructions

### Step 1: Add WeaponTrail to Weapon Scene

1. Open your weapon or character scene in the Godot editor
2. Add a new child node
3. Search for "WeaponTrail" and select it
4. Position the WeaponTrail node appropriately (usually as a child of the weapon or character root)

### Step 2: Add Blade Markers

1. Add two Node3D nodes to your scene (as children of the weapon mesh or character)
2. Name the first marker: `trail_top`
3. Position `trail_top` at the tip of the blade
4. Name the second marker: `trail_bottom`
5. Position `trail_bottom` at the base/hilt of the blade

**Important**: The markers must be named exactly `trail_top` and `trail_bottom` for auto-detection to work.

### Step 3: Configure WeaponTrail Material

1. Select the WeaponTrail node
2. In the Inspector, find the `material_override` property
3. Assign the trail shader material: `assets/effects/materials/slash_trail_mat.tres`
4. Adjust shader parameters as needed (color, emission energy, etc.)

### Step 4: Add Animation Method Tracks

1. Open the AnimationPlayer for your character/weapon
2. Select the attack animation you want to add the trail to
3. Click "Add Track" and select "Call Method Track"
4. Set the path to `.` (refers to the scene root with the Battler script)
5. Add a keyframe at the start of the animation:
   - Frame 0 (or when the swing begins)
   - Method name: `_on_trail_start`
6. Add a keyframe at the end of the animation:
   - Last frame (or when the swing ends)
   - Method name: `_on_trail_end`

**Note**: The callback methods must be called on the same node that has the WeaponTrail as a child (usually the Battler/character root).

### Step 5: Configure Trail Parameters (Optional)

The WeaponTrail has the following adjustable parameters:

- **trail_lifespan**: How long trail segments last before fading (default: 0.3 seconds)
- **resolution**: Minimum distance between trail points (default: 0.05)
- **subdivisions**: Number of interpolated segments for smoothness (default: 4)

## Example Timing Reference

### Standard Melee Attack (1.6 seconds, 48 frames)
- Trail Start: Frame 0 (when the swing begins)
- Trail End: Frame 48 (when the swing ends)

### Quick Slash (1.0 seconds, 30 frames)
- Trail Start: Frame 0
- Trail End: Frame 30

## Advanced Usage

### Material Override at Runtime

You can change the trail material dynamically using the provided methods:

```gdscript
# Change to fire trail material
var fire_material = preload("res://assets/effects/materials/fire_trail.tres")
weapon_trail.set_effect_material(fire_material)

# Revert to default material
weapon_trail.clear_effect_material()
```

### Multiple Weapons

If a character has multiple weapons (e.g., dual wielding), each weapon needs:
1. Its own WeaponTrail instance
2. Its own set of trail_top and trail_bottom markers
3. The WeaponTrail nodes should be named uniquely to distinguish them

## Troubleshooting

### Trail not appearing
- Verify trail_top and trail_bottom markers exist and are named correctly
- Check the console for warning messages about missing markers
- Ensure the WeaponTrail has a material assigned
- Verify the animation method tracks are calling the correct methods

### Trail appears at wrong position
- Check that trail_top and trail_bottom markers are positioned correctly on the blade
- Ensure markers are children of the weapon mesh (so they move with it)
- Verify the WeaponTrail node has `top_level = true` (set automatically)

### Trail timing is off
- Adjust the _on_trail_start keyframe earlier or later in the animation
- Adjust the _on_trail_end keyframe to match the actual end of the swing
- Test with the animation playing in the editor to verify timing

### Trail looks jagged
- Increase the `subdivisions` parameter for smoother interpolation
- Decrease the `resolution` parameter for more frequent point sampling
- Note: Higher subdivisions and lower resolution may impact performance

## Performance Considerations

- Each WeaponTrail instance creates dynamic geometry every frame
- For many characters with trails, consider:
  - Increasing `resolution` to reduce point density
  - Decreasing `subdivisions` to reduce triangle count
  - Decreasing `trail_lifespan` to reduce history size
- The trail uses world-space rendering (top_level = true) to stay stationary in air

## Migration from Old System

If you were using the old hitbox-based system:

1. Remove the `hitbox_path` export from WeaponTrail (no longer needed)
2. Remove the `top_point_path` and `bottom_point_path` exports (auto-detected now)
3. Rename your markers to `trail_top` and `trail_bottom`
4. Replace hitbox.active monitoring with animation method callbacks
5. Update any code that manually controlled the trail to use `_on_trail_start()` and `_on_trail_end()`

## Related Documentation

- [Animation Callback Setup Guide](ANIMATION_CALLBACK_SETUP.md) - For setting up attack hit timing
- [Animation System Guide](ANIMATION_SYSTEM_GUIDE.md) - For understanding the animation architecture
