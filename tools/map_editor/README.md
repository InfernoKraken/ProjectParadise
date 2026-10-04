# Project Paradise Map Editor

This is a standalone Godot project for authoring the current `data/maps/*.json`
format. It does not import gameplay, battle, or player scripts. Start it with:

```powershell
godot --path tools/map_editor
```

The editor opens `eastern_rainforest_route.json` initially. X is shown left/right;
negative world Z is shown upward/north. Middle- or right-drag pans, the mouse wheel
zooms, and left-drag moves objects. Drag the yellow lower-right handle of a selected
water or grass rectangle to resize it.

The left activity sidebar has three mutually exclusive views: **Objects** for the
placement palette, **Inspector** for the selected object, and **Map** for map identity,
dimensions, terrain, encounters, validation, raw JSON, and the warp graph. Selecting
an object automatically opens Inspector; clearing selection does not change the
current activity. The canvas occupies all space to the right of this single sidebar.

Canonical `terrain_tiles` have a dedicated toolbar palette. Choose a terrain type,
then Paint or Erase and drag across the canvas; cells always snap to the 1×1 terrain
grid. Select returns to ordinary object editing, and Escape exits either brush.
Grouped `positions` records are displayed as individual cells but remain grouped in
JSON, so legacy terrain blocks and unknown record fields are not rewritten. The map
metadata panel exposes `base_terrain_type`. Each brush stroke is one undo/redo step,
and invalid or overlapping terrain cells receive a red canvas outline linked to the
Validation tab.

Drag an entry from the Object Palette and release it over the map to place it at
the cursor. The drop position follows the current grid/snap settings and the asset
catalog supplies its default Y, footprint, size, and variant. The new object is
selected immediately. "Add at Origin" remains available as a keyboard-friendly
fallback.

Use **Import Sprite** in the toolbar to select one or more PNG, WebP, or JPEG files.
The editor validates and copies them into `assets/overworld`, refreshes the object
palette immediately, and asks the gameplay Godot project to generate its normal
import sidecars in the background. Existing files are never overwritten. Numbered
suffixes such as `_00`, `_01`, and `_02` become variants of one palette asset.

New Map creates a format-version 2 universal document with explicit `map_metadata`
(`id`, display name, map type, group, and tags), connection/arrival collections,
universal objects, terrain arrays, and optional cave/interior collections. Its
capabilities no longer depend on a temporary filename. Saving registers the map in
`map_index.json` under `maps` and `map_groups`, and the runtime loader reads that
authored-map catalog alongside the legacy prototype sections.

Buildings, trees, flowers, vines, water, sand, and rocks are universal. When the
current map has a legacy typed array, the editor continues writing that array. On
other maps it creates an `objects` array containing stable catalog `type`, `position`,
and `size` records. The same runtime builder consumes those records in outdoor maps,
caves, and interiors. Only genuinely map-specific gameplay markers remain dimmed.

Select an array-backed object and use the toolbar Delete button or focus the map and
press the Delete key. Required singular markers such as an entry point cannot be
removed because that would make the current map invalid; the status bar explains
this distinction. All successful deletions can be undone.

Rectangle schemas are explicit: water and rocks serialize as six-number Block6
arrays, while encounter grass serializes as an object containing `position`, `size`,
and `encounter_chance`. Moving a rectangle preserves its serialized dimensions.
Non-colliding shoreline pieces use `sand_blocks` Block6 arrays and the gameplay sand
texture. Current water rectangles are bordered by editable half-tile sand strips.

Current-schema building tiles use `floor_blocks` and `wall_blocks` Block6 arrays.
They tile the real gameplay interior floor/wall textures across their X/Z rectangles, expose collision dimensions in the
inspector, and can be placed, moved, resized, duplicated, deleted, and undone.
Existing house and medical-ward exterior records render at the same size-derived
width used by gameplay and show their serialized X/Z collision footprint.
Additional house and medical-ward exteriors can be placed on every map through the
universal object format; they receive the same billboard scaling, Y-sort registration,
and collision generation. Entrances remain separate warp/connection data, allowing
the exterior and its travel destination to be authored independently.

`Trainer Opponent` and `NPC Position` are also universal. Selecting either placeholder
cube exposes its speaker/name and dialogue in the inspector; separate dialogue pages
use `|`. Trainers additionally expose a comma-separated team such as
`Scorchick:8, Sylvafin:12`. Fakemon may be identified by name or roster index, teams
may contain one to seven members, and levels are constrained to 1–100. Clicking an
NPC shows its text, while closing a trainer's final text page begins the configured
battle.
Legacy `trainers` records use the same inspector: their old index-only `party` values
are displayed as level-5 members and become named/indexed Fakemon-and-level records
when edited.

Universal sprite objects serialize an explicit visual `height`. The canvas and
runtime consume that same number; building-only width scaling is never applied to
trees or other sprites. The selected-object inspector can change visual height.
Imported assets can persist a shared scale beside the sprite. Their collision rows
also provide **Edit**, which opens numeric Offset X/Z and Size X/Y/Z controls without
requiring the collision rectangle to win canvas hit-testing.

Interior furnishings are serialized as `furnishings` records containing a stable
`type`, local `position` (`[x,y,z]`), and display `height`. The editor draws floors
below walls and furnishings and gives the floor the lowest click priority. Existing
house, city-house, and ward billboard layouts have been migrated to these records;
the game retains its old layouts as compatibility fallbacks for unmigrated files.

Undo is available from the toolbar or `Ctrl+Z`. Redo uses `Ctrl+Shift+Z`, `Ctrl+Y`,
or the toolbar.

Double-click a warp trigger to open its serialized runtime destination map. When
the destination's arrival marker is stored in that file, it is selected immediately.
The editor asks before discarding unsaved changes. Indoor maps expose four editable
transition positions: exterior `door`, interior `entry`, interior `exit_door`, and
outdoor `exterior_return`. Interior exits open the containing clearing or city and
select the linked exterior-return marker rather than the nearby building art.

Saving is deterministic and atomic. Existing destinations receive a `.bak` copy,
and validation errors prevent replacement. Untouched numeric tokens retain their
original spelling, including trailing precision and exponent notation. Unknown JSON
fields remain in the document and serialized output.

Rename changes a saved map's filename, updates its metadata ID, recursively updates
world-index and connection references, and retains the old file as a `.bak`. The
The runtime keeps the physical `map_index.json` filename fixed. Manifest detection is
based on its index structure (`root`, `sections`, and `nested_sections`), not merely
its current filename, so Rename and Save As cannot disguise or relocate it. The
editor's Rename action edits `index_metadata.display_name`, allowing the world/index
to be named without breaking the runtime bootstrap path.

Trainer placements store a stable `trainer_id`; reusable names, dialogue, colors, and explicit Fakemon/level team rows live in `data/trainers.json`. Saving a map also atomically saves any edited trainer definitions. Legacy inline trainer records remain readable during migration.

Warps expose a numeric ID, their X/Y/Z position, an Entrance Map picker populated
from the map directory, and an Entrance Map Warp ID. These editor-facing fields are
stored as `warp_metadata`; legacy runtime connection fields remain synchronized so
gameplay still arrives at the configured return warp. Following a link to a map with
no warp creates a placeholder return warp with ID 1 at `[0, 0.12, 0]`.
Use **Add Warp** in the toolbar to create a warp at the map origin. It receives the
next available numeric ID, is selected immediately, and can be positioned and linked
from the Inspector. Editor-authored `warp_*` markers can also be deleted and undone.
Placed `Warp Outdoor` art is decorative until converted: select it and use **Convert
to Functional Warp** to preserve its position and facing while assigning it a warp ID
and editable destination.

Outdoor maps serialize named `arrival_points` and directed `outdoor_connections`.
Attached overlays store `local_position` as a bottom-center offset on the host's
artwork, in sprite display units. Gameplay scales both components equally, matching
the editor; camera ground projection and the host's stored Y do not alter this
offset. Rotation remains around the overlay's bottom-center anchor.

The Warp Graph pairs reverse links and reports missing destinations/arrivals, one-way
links, duplicate IDs, and duplicate warp endpoints. Selecting a warp exposes its
destination map, arrival name, reverse-link ID, and facing in the inspector. Legacy
coordinate fields remain runtime and editor fallbacks during incremental migration.

Water decorations are imported automatically from `assets/overworld/`:

- **Water Floaters** (`floater_*`): lilies and foliage above the water surface,
  using ordinary world Y-sort so foreground actors and objects still occlude them.
- **Water Submerged** (`submerged_*`): floor artwork below swimming Fakemon and
  the shared translucent water surface. Numbered files appear as asset variants.

Both families support visual height, rotation, and ordinary map save/load. They
never create collision or navigation, including from asset-sidecar metadata;
their inspector therefore omits collision authoring. Paint canonical water beneath
them for surface compositing. A submerged prop enables the existing surface over
the map's water cells even without swimming NPCs. Props and swimmers share one
surface container, with no per-prop water clocks or processing callbacks. This
checkpoint reuses the current translucent surface; it does not add a new water
shader or change shoreline legality. `semi_submerged_*` stays out of the palette
until its separate behavior is implemented.

Regression scripts: `tests/water_decoration_test.gd` in the game project and
`tests/water_decoration_editor_test.gd` in the map-editor project. Both report a
zero-failure summary on success. The runtime test optionally accepts
`-- --render-check` with a real OpenGL3 renderer to verify pixel compositing and
mask clipping; headless runs validate nodes, ordering, and shared surface reuse.
