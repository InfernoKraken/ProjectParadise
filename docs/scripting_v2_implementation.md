# Scripting V2 implementation report

V2 extends V1 with exactly four commands: MoveSprite, FollowSprite, StopFollowing,
and FaceSprite. The primary [command reference](scripting_reference.md) is generated
from registry metadata, with a regression check against the committed output.

## Resources and authoring

Optional map JSON root `script_paths` is an array of `{name, type, nodes}` records.
Type is `MOVE` or `FOLLOW`; nodes are ordered `[X,Z]` pairs in map-local coordinates.
MOVE requires one node; FOLLOW requires at least two distinct nodes. Names are unique
ASCII identifiers. Coordinates must be finite and within ±1,000,000 for engine safety.
`script_sprite_names` optionally maps aliases such as Professor to existing NPC IDs.
Numeric IDs and NPC1/NPC2 names still work. Reserved actor/direction names cannot be
aliases. Source, associations, paths, and aliases remain separate from placement and
NPC companion definitions. Existing atomic map serialization/backups/snapshots preserve
them; legacy maps without these fields load normally. No map-format migration occurred.

SCRIPT now contains Source, Paths, and Reference pages. Paths has Create MOVE/FOLLOW,
select, rename, delete, add/insert/delete node, and numeric X/Z editing. Click-to-add
uses existing canvas snapping; dragging a numbered handle commits through map undo.
Rename/delete does not rewrite code and instead diagnoses stale references. Selecting
an NPC in Source exposes its optional alias alongside the V1 Block association.

MOVE is solid orange with arrows. FOLLOW is dashed cyan with arrows. Both show type,
name, and ordered node numbers; color is not their only distinction. Overlays appear
only in SCRIPT and never enter the ordinary object list. Parser/completion reference
pools provide NPC names, Player, cardinal directions, and correctly typed path names.

## Runtime and collision

`world/npc_script_movement.gd` owns transient MOVE/FOLLOW/HOLD modes per actual NPC
instance. ScriptRunner remains an instruction sequencer. Host dispatch delegates
requests to this service. Move returns `{pending:true}`; completing the final node
calls the runner's existing generation-guarded resume callback. Collision blockage
uses a guarded failure callback with current map/Block/line/command context. Cancellation
stops Move and releases input locks. A Move still executes while Lock prevents player
movement. Dialogue pauses movement through the existing game gates.

FOLLOW returns immediately and survives End. The follower projects itself and its
target onto the ordered polyline, approaches the corridor, then visits intervening
bends toward the target's projected progress, in either direction. It stops within
1.25 world units of the target and avoids entering the player's personal space.
Targets over three units from the corridor pause pursuit. Blocked followers retry
each tick; they resume when the corridor becomes reachable. There is no navigation
mesh, route search, wall bypass, teleport, or cross-map transport. StopFollowing is
idempotent and holds the NPC where it stopped. Established follow modes remain outside
script cleanup; map changes, new adventures, and loads clear all modes. None is saved.

Scripted motion uses the exact existing `_npc_motion_fraction` shape sweep, preserving
collision layers/shapes and ground/flying/swimming rules. `_animate_placed_npc` is the
shared extraction of the existing pose/walk-frame update, not another animation system.
FaceSprite uses `_set_npc_pose` immediately and the existing up/down/left/right states.
Player and other actors are resolved only through the current map's actor registry.

Editor warnings consume existing extracted asset boxes, wall/rock/water blocks, and
baked fence collision strips. The existing NPC foot size is now a shared constant
in `npc_movement.gd`; warnings expand bounds by that footprint. Red segments and
diagnostics mark known intersections. This editor check is conservative and incomplete:
polygons, asset transforms, height differences, dynamic blockers, and the initial
actor-to-first-node approach remain runtime physics responsibilities. No second runtime
collision system was introduced. MOVE fails after two seconds of sustained blocking.

## Command metadata and documentation

`world/scripting/command_registry.gd` remains authoritative. Existing argument-type
definitions are preserved; HELP adds argument names, category, blocking status,
behavior, and examples. `metadata()` combines them. Parser recognition, typo assistance,
and autocomplete continue using this registry. The reference generator also reads
the same types, names, descriptions, errors, and examples for all 25 commands.

`world/scripting/generate_reference.gd` writes `docs/scripting_reference.md`.
`tests/scripting_v2_test.gd` compares exact generated output, checks metadata completeness
and argument counts, and parses every example. Adding a command without metadata or
regenerating documentation fails this test. No speculative commands are documented.

## Files changed

Added:

- `world/npc_script_movement.gd`
- `world/scripting/script_paths.gd`, `command_reference.gd`, `generate_reference.gd`
- `tools/map_editor/ui/script_path_panel.gd`
- `tools/map_editor/core/script_path_collision.gd`
- `tests/scripting_v2_test.gd`, `tests/scripting_movement_test.gd`
- `tools/map_editor/tests/scripting_v2_editor_test.gd`
- `tests/fixtures/script_tour.json`
- `docs/scripting_reference.md`, this report, and Godot-generated UID sidecars

Modified:

- `world/scripting/command_registry.gd`, `script_runner.gd`, `world_script_host.gd`, README
- `world/main.gd`, `world/npc_movement.gd`
- `tools/map_editor/map_editor.gd`, `ui/editor_canvas.gd`, `ui/script_panel.gd`, README
- `.gitignore` to retain new tests/fixture

No existing maps or NPC companion files were edited for the fixture. Previously
modified workspace files were preserved.

## Validation and limits

Godot 4.7.1 with `--headless --rendering-driver opengl3`:

- V2 paths, validation, completion, registry/reference/examples: **137 checks passed**.
- Live NPC movement, acceptance tour, blocking, collision, follow/stop/facing,
  cancellation, map cleanup, blocked-follow recovery: **33 checks passed**.
- Editor path editing, undo/redo, atomic persistence, aliases, typed completion,
  stale references, static-box/fence warnings, canvas clicks/dragging: **20 checks passed**.
- V1 parser/runtime (**51**), editor (**16**), and overworld (**22**) checks still pass.
- Existing NPC movement preset/collision/animation regression suite passes.

The acceptance fixture demonstrates BeginTour and StopAtExhibit in an isolated test
map, not an implemented Research Institute event. All tests use temporary map fixtures
and do not overwrite gameplay save slots.

Use simple non-branching, non-self-crossing FOLLOW corridors. Off-corridor targets
are approached via their projection; followers do not invent a detour. Move/Stop
leave an NPC held until the transient mode is cleared or a new movement request
replaces it. Renaming paths/aliases/maps requires repairing source references.
Editor collision warnings do not certify traversability. Existing V1 limits on
visual-only Hide/Show, full parties, pictures, and map-boundary termination remain.
