# Fakemon Editor

Standalone content-authoring project for the runtime Fakemon schema.

Run from the repository root:

```powershell
godot --rendering-driver opengl3 --path tools/fakemon_editor
```

The editor intentionally writes the existing owners of each field:

- base species: `data/battle_data.json` → `fakemon`
- evolved species and evolution relationships: `data/evolved_fakemon.json`
- egg-group assignments: `data/egg_groups.json`
- wild locations: read-only scan of `data/maps/*.json`

Sprites are not stored as paths in the runtime schema. The Art tab treats `art_id` as a filename-driven package containing independent Player/Wild battle images, four static directional Follow images, and independent Player/Wild anchor maps. Image selection is staged; **Write Art Package** shows the exact overwrite/create set before writing canonical PNG filenames. Assigning an existing package only changes the Fakemon draft's `art_id` and never modifies images.

The embedded anchor pane uses the existing anchor-map v1 signature, marker colors, required/optional/custom anchor rules, nearest-neighbor 200-pixel processing cap, and `generated_battle_anchors.json` structure. `.anchors.png` remains the authoring source of truth. Godot-generated `.png.import` files are deliberately neither displayed nor written by the tool.

Current engine conflicts/limitations shown accurately by the editor:

- Fakemon have no separate internal ID; their case-sensitive `name` is used by evolution, trainer, and encounter references.
- Evolved Fakemon inherit both starting moves and learnsets from `moveset_source` at runtime. Those inherited lists are displayed as such; the source relationship is the editable engine field.
- Wild encounters do not currently store encounter levels. Runtime creates the species at its default `level` (currently generally 5), so Found In reports that fact instead of inventing a level range.
- Removing or renaming a species can break references in maps, trainers, evolutions, or moveset sources. The editor never silently rewrites those unrelated files.
