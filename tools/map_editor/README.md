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
The runtime keeps the physical `map_index.json` filename fixed. The editor's Rename action edits its `index_metadata.display_name`, so the world/index can be named without breaking the runtime bootstrap path.

Trainer placements store a stable `trainer_id`; reusable names, dialogue, colors, and explicit Fakemon/level team rows live in `data/trainers.json`. Saving a map also atomically saves any edited trainer definitions. Legacy inline trainer records remain readable during migration.

Outdoor maps serialize named `arrival_points` and directed `outdoor_connections`.
The Warp Graph pairs reverse links and reports missing destinations/arrivals, one-way
links, duplicate IDs, and duplicate warp endpoints. Selecting a warp exposes its
destination map, arrival name, reverse-link ID, and facing in the inspector. Legacy
coordinate fields remain runtime and editor fallbacks during incremental migration.
