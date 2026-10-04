# Bounded NPC movement presets

Select an NPC in the Map Editor. Its inspector now has **Movement**, **Max X range ±**, and **Max Y range ±** controls. Range is measured in map units from its placed initial position, in both directions: X = 3 permits movement from start X − 3 to start X + 3. Map/screen Y corresponds to world Z. Elevation remains unchanged.

Presets:

- Stationary: preserves previous NPC behavior and is the default for definitions without movement settings.
- Walk Left / Right: alternates between horizontal limits.
- Walk Up / Down: alternates between vertical limits.
- Walk Clockwise / Counterclockwise: approaches the upper-left corner on cardinal legs, then traverses the rectangle's corners in the selected order. A zero range on one axis degenerates to a line.
- Random Within Range: picks a bounded destination along one axis at a time.
- Idle Look Around: changes cardinal facing periodically without moving.

Walking speed is 1.2 map units per second, with a one-second pause at endpoints or when blocked. Look-around changes facing every 1.5 seconds. Both zero ranges hold the NPC in place.

## Ownership and integration

Optional companion definition data:

```json
"movement": {
  "preset": "clockwise",
  "range": [3.5, 1.25]
}
```

Supported stored preset values are `stationary`, `left_right`, `up_down`, `clockwise`, `counterclockwise`, `random`, and `look_around`. Initial placement still contains only ID, position and facing. Movement configuration shares the existing companion save/load, undo/redo, duplicate and deletion paths. Old definitions do not need migration or rewriting.

`world/npc_movement.gd` centralizes configuration validation, bounded waypoint selection and mutable planning state. `npc_map_data.gd::issues()` validates optional movement data using that module. Invalid presets or negative/non-finite/malformed ranges produce controlled diagnostics and prevent instance resolution/save.

`world/main.gd::_build_placed_npcs()` initializes one movement state per live NPC. `_physics_process()` calls `_update_placed_npcs()`, which applies a proposed displacement using `_npc_motion_fraction()` and the existing foot collision shape. The query includes solid obstacles, terrain/water obstacles, platform walls, the player and other NPC bodies. Only the new placed NPC foot offset is aligned to its ground-anchor position; legacy NPC collider offsets remain unchanged.

Movement runs only in the active map. Dialogue, battles and the existing exploration pause gates freeze movement. Sorting and click interaction continue to follow live NPC nodes. Runtime movement and facing never write back into authored placement or companion definitions.

The current NPC catalog supplies directional idle art. Moving NPCs use those poses while changing facing; new walk-animation artwork/parsing was not introduced. Obstacles stop movement, and the controller retries a subsequent leg after pausing. There is no pathfinding or navigation around obstacles; authors should keep intended patrol areas clear. Bounds are centered on placement, rather than inferred from map edges.

## Files

Added `world/npc_movement.gd`, `world/npc_movement.gd.uid`, `tests/npc_movement_test.gd`, `tests/npc_movement_test.gd.uid`, and this document.

Modified `world/npc_map_data.gd`, `world/main.gd`, `tools/map_editor/map_editor.gd`, `tools/map_editor/tests/npc_editor_test.gd`, `.gitignore`, and the original checkpoint report's link to this follow-up.

## Verification

Godot checks use `--headless --rendering-driver opengl3` with explicit log files. Run the editor fixture generator first:

```powershell
godot --headless --rendering-driver opengl3 --path tools/map_editor --script res://tests/npc_editor_test.gd --log-file npc_movement_npc_editor_test.log
godot --headless --rendering-driver opengl3 --path . --script res://tests/npc_movement_test.gd --log-file npc_movement_focused.log
godot --quiet --headless --rendering-driver opengl3 --path . --script res://tests/npc_checkpoint_test.gd --log-file npc_movement_checkpoint_verified.log
```

`npc_movement_test.gd` verifies all presets, bounds/elevation, opposite rectangle winding, zero ranges, all idle facings, legacy defaults, invalid movement data, runtime updates, dialogue/battle pauses, inactive-map pauses, wall collisions and authored-state isolation. `npc_editor_test.gd` now also verifies movement controls, ranges, undo/redo, companion save/reload and placement-field separation.

All three tests passed. The focused movement test uses the actual runtime NPC factory and physics world without constructing unrelated terrain.

Verification logs are archived under `tests/generated/npc_verification_logs/movement/`.

The existing `map_editor_ui_test.gd`, `npc_behavior_test.gd` and `npc_sprite_test.gd` also passed. Full-world checks were rerun with `--quiet` and a longer process timeout after the initial 45-second runs did not finish. Gameplay `--editor --quit` import and the diff whitespace check passed; Godot still reports the environment's certificate-store/global editor-settings errors. No existing failing terrain/warp tests were changed.

Manual check: add/select an NPC, choose a movement preset and X/Y ranges, save/reopen, then use **Test Map**. Confirm bounds and direction, click the moving NPC to pause it for dialogue, and check that **Idle Look Around** changes facing without changing position. Repeat with a Fakemon. Returning to the editor retains the authored starting position.
