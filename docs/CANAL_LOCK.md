# Canal lock checkpoint

Instance `world/canal_lock.tscn` with its origin at water level. Local X spans
the opening; rotate the root around Y for other canal directions.

`gate_scale` uniformly scales the art and collider without scaling a physics
body transform. `animation_time` is seconds per frame, default 1 second.
Playback is 0, 1, 2, 1, 0. Both closed endpoints receive a full interval, so a
loop holds closed for two intervals across the loop boundary. Disable `loop`
for a single cycle; disable `autoplay` to start closed and idle.

`play_cycle()` restarts the cycle. `set_open(true)` holds frame 2 open;
`set_open(false)` holds frame 0 closed. `frame_changed` reports each entry.
The closed and transition frames block boats and other solid movers on layer 1.
Only frame 2 clears the passage. Closing does not wait for an occupied opening;
boat detection and coordinated lock controls are a later checkpoint.

The collider is a convex hull generated from a box mesh, independent of sprite
transparency. `collider_size` defaults to placeholder bounds (6 x 2 x 0.4 map
units); tune it to the canal. All frames use one pixels-to-world ratio and a
shared center. Frame canvases should share dimensions and artwork alignment.

## Map Editor and overworld

In the Map Editor palette, choose **Watercraft & Canal → Canal Lock (Animated)**.
Place it across a water route, with Y at water level (normally 0). Select it to
edit gate scale, seconds per frame, base visual height, base collider dimensions,
collider yaw, sort depth offset, autoplay and loop. Changes use the normal
save/load and undo/redo flow. The editor shows the closed frame and the scaled
collider footprint. Collider yaw rotates the opening in the map plane while
the supplied billboard art remains upright.

Saved objects use type `structure.canal_lock`. The `size` field is the base
collider size and `height` is the base sprite height; `gate_scale` multiplies
both. No existing map placements are changed. To test, place a gate across an
existing vehicle route, save, and start/reload gameplay. Autoplay and loop are
enabled by default. Set a longer frame duration to inspect passage at frame 2.
Disabling autoplay keeps the gate closed; disabling loop plays one full cycle.

Runtime placement reuses the gate scene and the ordinary projected Sprite2D
Y-sort roots, above the water surface. The source Sprite3D is hidden to avoid
double rendering. Frame changes synchronize the sorted texture and invalidate
cached projection bounds, including while the camera is stationary. Map layer
visibility and authored sort offsets use the existing object-sorting system.

Validation: `tests/canal_lock_test.gd` tests timing and actual boat collision;
`tests/canal_lock_map_test.gd` tests map placement and sorted texture updates;
`tools/map_editor/tests/canal_lock_editor_test.gd` tests palette placement,
inspector controls, scale/yaw bounds, undo/redo, serialization and validation.
