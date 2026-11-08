# Vehicle patrols

Use **Add Patrol** or **Edit Patrols** in the map editor toolbar. Apply commits the configuration to the map. Save the map normally. Cancel leaves the map unchanged. Patrol edits use normal map undo/redo.

Choose Finite or Traffic, a positive creation interval in seconds, and (for finite patrols) Repeat. The first vehicle is due immediately. Traffic patrols default to eight active ships. Set **Maximum active ships** to change the limit. Spawning waits when the limit is reached. An occupied start delays the next spawn; intervals restart after successful spawns, without catch-up bursts.

Vehicle definitions use existing vehicle data, for example `{"type":"vehicle","sprite":"Tug"}`. Finite patrols take a JSON array in spawn order; traffic takes one object. Existing sprites are Tug, Cargo, and Luxury. New patrols start with an empty path. Click the map to place the start, intermediate waypoints, and endpoint. Turn off **Add nodes by clicking map** to select and drag waypoints. The node list also supports numeric edits, insertion, and deletion.

Configurations live in the map's `patrols` array, separate from transient runtime NPCs:

```json
{
  "type": "finite",
  "creation_interval": 3.0,
  "path": [[0, 0], [0, 12], [8, 12]],
  "vehicles": [{"type": "vehicle", "sprite": "Tug"}],
  "traffic_vehicle": {"type": "vehicle", "sprite": "Cargo"},
  "repeat": true
}
```

Finite vehicles park at their destination; Repeat reverses the same instances along the same waypoints. Traffic despawns on arrival and keeps spawning. Patrols use existing NPC MOVE routes, speed, animation, vehicle hull collisions, swimmer pushing, and water restrictions. Obstructions cause indefinite waiting without detours. Current vehicles are boats: the full hull must fit on canonical water. No additional art is required.

A patrol is active only in its current location with the route's padded bounds intersecting the camera's existing ground-view region. The whole route remains active together, allowing an offscreen start to feed visible traffic. Leaving this region pauses timers and movement; returning resumes route cursors and remaining delays. Leaving the viewport never deletes vehicles. Ordinary battle/dialogue/script locks also pause patrols.

Routes need room for their hulls. Parked vehicles can block following vehicles, and opposing vehicles on a repeating route can block each other; there is no extra avoidance or traffic AI.

Validation:

- `godot --headless --rendering-driver opengl3 --path . --script tests/patrol_test.gd`
- `godot --headless --rendering-driver opengl3 --path tools/map_editor --script tests/patrol_editor_test.gd`
- Existing regression: `tests/vehicle_test.gd`.
