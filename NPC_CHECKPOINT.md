# NPC placement/runtime — checkpoint one

This describes the original placement checkpoint. The subsequent movement presets and their verification are documented in [NPC_MOVEMENT.md](NPC_MOVEMENT.md).

The Map Editor can add, select, drag, delete and duplicate stationary Human or Fakemon NPCs, choose a sprite and semantic facing, enter interaction text, and save/reload placements with companion definitions. Runtime instances use the existing talking-NPC physics, rendering, sorting and dialogue systems. No walking, AI, battles, scripting, schedules or quests were added.

## Source changes

Added:

- `world/npc_map_data.gd` — companion loading, placement/definition validation, default creation, ID allocation and resolution into independent runtime records.
- `world/npc_visual_resolver.gd` — explicit four-human selector catalog and centralized visual resolution; Fakemon come from the existing base and evolved species registries.
- `tests/npc_checkpoint_test.gd` — resolver/error/runtime/click-interaction tests.
- `tools/map_editor/tests/npc_editor_test.gd` — editor creation, selectors, mouse dragging, text, paired persistence, IDs and history tests.
- `NPC_CHECKPOINT.md` — this report and manual procedure.
- `world/npc_map_data.gd.uid`
- `world/npc_visual_resolver.gd.uid`
- `tests/npc_checkpoint_test.gd.uid`
- `tools/map_editor/tests/npc_editor_test.gd.uid`

Modified:

- `.gitignore` — allow the two new test sources and their UID companions while continuing to ignore generated fixtures and other untracked tests.
- `tools/map_editor/map_editor.gd` — Add NPC, inspector, companion state, placement extraction, paired save/Save As/rename, companion-aware history and instance-safe deletion/duplication.
- `tools/map_editor/ui/editor_canvas.gd` — accept an already resolved texture in the existing draw path.
- `world/npc_sprite_library.gd` — four explicit idle-sheet entries and an optional game-root argument for the standalone editor's source-image access. Existing legacy sprite entries and grid/frame algorithms are preserved.
- `world/map_data_loader.gd` — resolve companion data once when reading each map and reuse already loaded authored map files.
- `world/main.gd` — instantiate resolved placements during the existing universal-object build, maintain the runtime instance registry, and route new NPC facing updates through the visual resolver.

No artwork or authored gameplay maps were edited for this checkpoint. Tests regenerate their existing generated fixtures and write diagnostic logs.

## Investigation and integration

1. Editor JSON belongs to `MapDocument.load_file()`, `from_text()`, `deterministic_json()` and `save_atomic()` in `tools/map_editor/core/map_document.gd`. The encoder preserves untouched numeric tokens and unknown fields. NPC saves use this same encoder and backup mechanism.
2. Runtime map assembly belongs to `MapDataLoader.load_world()` and `_load_json_object()` in `world/map_data_loader.gd`. NPC data is attached under private `_resolved_npcs`, `_npc_issues` and `_npc_map_file` keys, which are never part of an editor save.
3. The editor's `_extract_objects()` now calls `_append_npcs()`. `EditorCanvas._hit_test()`, `select_object()` and `_gui_input()` continue to handle selecting and dragging. Their existing signals reach `_on_canvas_moved()` / `_on_canvas_objects_moved()` and `_write_object_position()`.
4. `MapCoordinateConverter` maps X/Z onto canvas X/Y. NPC position uses the existing three-number array. Runtime adds the map origin; the clearing uses origin zero.
5. `EditorCanvas._draw_depth()` sorts by map Z. Runtime adds NPCs to `npc_sort_entries`; `_build_sort_canvas()` and `_update_sort_canvas()` put their art under `WorldYSortRoot` and sort at their feet. Existing visual-region/collision handling remains in use.
6. `NpcSpriteLibrary.texture_for()` owns human frame selection. New entries provide explicit directional `Rect2i` regions for the four specified idle sheets. The resolver requests `walk_frame = -1`, the existing idle path. Gameplay uses imported `res://` textures; the standalone editor uses its established absolute source-image access. Young Boy/Girl use that same crop path and Human visual height, with no child-specific mode. No replacement parser or PNG extraction was introduced.
7. Runtime `_unhandled_input()` handles left clicks with a physics raycast against `Area3D` instances. New NPCs participate through the same `npc_dialogues` dictionary as existing talking NPCs.
8. `_start_dialogue()` calls `_update_dialogue()` to populate the existing speaker/text panel. Raw `interaction_text` becomes one page, preserving embedded line breaks. Existing interaction-facing changes update only the live node.
9. `MapValidator.validate()` remains unchanged. Editor refresh/save appends `npc_map_data.gd::issues()` using the established severity/path/message shape. Runtime uses `push_warning()` diagnostics and skips invalid instances. Duplicate IDs skip both ambiguous instances. Invalid authored records are retained for repair, rather than rewritten.
10. The reliable species data is split between `data/battle_data.json` and `data/evolved_fakemon.json`, as used by the battle and Fakemon editor systems. The selector uses their names/art IDs and requires all four existing follow files. Currently all 30 species qualify. No directory scan or duplicate species list is used.

## Storage and runtime ownership

Map `npcs` records contain exactly `id`, `position`, `facing`. `npc_map_data.gd::companion_path()` resolves `<MapName>_NPC_Data.json`; its root dictionary is keyed by integer-ID strings, with `type`, `sprite` and `interaction_text` definitions.

`load_for_map()` reads that companion once per map read. `_save_npc_pair()` writes it through `MapDocument.save_atomic()`, followed by the map. Validation blocks replacement on errors. If the map write fails, the companion is restored to its previous content. Save As and rename carry definitions to the new companion name. Rename excludes companion files from map-reference rewriting, so dialogue text is preserved.

`world/main.gd::_build_placed_npcs()` calls `_add_talking_npc()` and stores each mutable `Area3D` in `runtime_npcs[map_filename][integer_id]`. Definitions and placements are copied during resolution. Multiple IDs may share art while retaining independent position, facing and interaction text. The existing world builds map regions up front; this registry includes built instances in inactive regions as well as the active region.

## Data flow

`map_editor.gd::_add_npc()` → `npc_map_data.gd::add_default()` → `document.data.npcs` + `npc_data.definitions` → `map_editor.gd::_save_npc_pair()` → `MapDocument.save_atomic()` → `MapDataLoader._load_json_object()` → `load_for_map()` / `resolve()` → `_resolved_npcs` → `main.gd::_build_universal_objects()` / `_build_placed_npcs()` → `runtime_npcs[map_filename][id]` → `npc_visual_resolver.gd::texture_for()` → `NpcSpriteLibrary.texture_for()` or the semantic follow PNG → existing `npc_sort_entries` / `WorldYSortRoot` → `_unhandled_input()` raycast → `npc_dialogues` → `_start_dialogue()` → `_update_dialogue()` → existing text panel.

## Automated verification

All Godot commands use `--headless --rendering-driver opengl3` and explicit `--log-file` paths to avoid the Windows user-directory logging problem.

Captured verification and baseline logs are archived in the ignored `tests/generated/npc_verification_logs/editor/` and `tests/generated/npc_verification_logs/runtime/` directories.

The two new scripts passed:

```powershell
godot --headless --rendering-driver opengl3 --path tools/map_editor --script res://tests/npc_editor_test.gd --log-file npc_editor_test.log
godot --headless --rendering-driver opengl3 --path . --script res://tests/npc_checkpoint_test.gd --log-file npc_checkpoint_test.log
```

Run the editor test first: it produces the runtime fixture under `tools/map_editor/tests/generated/`.

- `npc_editor_test.gd`: exact defaults; human catalog; base/evolved Fakemon availability; immediate facing selector updates; text editing; full mouse press/motion/release drag; placement-only changes; undo/redo; human/Fakemon save and reload; three-field placement/definition separation; IDs 1/3 after deleting 2; next ID 4; duplication with a new ID; independent instances sharing Young Man; rejected saves preserving existing files.
- `npc_checkpoint_test.gd`: all four facings of all four humans through the existing parser; exact semantic Sylvafin filenames/pixels; absent/empty NPC arrays; missing companion/definition; unknown sprite; invalid facing/ID types; malformed companion JSON; duplicate IDs; runtime creation through the universal-object path; authored position/facing and textures; actual click raycasts reaching the existing text panel; mutable live state leaving authored placement unchanged.

The existing tests were run using the same command form, with `--path tools/map_editor` for editor scripts and `--path .` for runtime scripts.

Passed existing editor scripts:

- `map_editor_ui_test.gd`
- `attached_overlay_ui_test.gd`
- `bridge_editor_ui_test.gd`
- `polygon_collision_ui_test.gd`
- `texture_animation_catalog_test.gd`

Passed existing runtime scripts:

- `npc_sprite_test.gd`
- `npc_behavior_test.gd`
- `player_cardinal_animation_test.gd`
- `player_diagonal_test.gd`
- `player_palette_test.gd`
- `wall_filler_bounds_test.gd`
- `attached_overlay_runtime_test.gd`
- `swimming_test.gd`
- `terrain_editor_roundtrip_runtime_test.gd`
- `overworld_texture_animation_test.gd`
- `overworld_texture_animation_runtime_test.gd`

Existing failures were investigated with the NPC integration disabled temporarily and the source files restored byte for byte afterward. The same failures occur without NPC integration:

- Editor `map_editor_test_runner.gd`: terrain-stream rotated collision footprint expectation.
- Runtime `world_smoke_test.gd:21`: current clearing encounter data differs from its Moach-only expectation.
- Runtime `bridge_traversal_test.gd:15`: current water collision-layer expectation.
- Runtime `terrain_transition_test.gd:41`: current route terrain does not produce the expected transition at the fixture coordinate.
- Runtime `terrain_stream_tile_test.gd:17`: expects a BoxShape where the current collision shape has no box `size`.
- Runtime `map_editor_runtime_test.gd:26`: current Jalovea warp arrival differs from its hardcoded expectation.

Tests that stop on assertions were terminated after recording the failure, rather than left running. Tests were not edited to accept those failures. Relevant code/fixtures outside NPC scope were left unchanged.

Godot import and scene checks were also run with `--editor --quit` and `--quit-after 2` for the gameplay and standalone editor projects. The environment reports certificate-store errors and sandbox restrictions on global editor-settings writes; NPC script/scene validation and the new automated tests pass.

## Manual checkpoint

1. Open the standalone Map Editor and a playable map. Click **Add NPC**; note its ID and Young Man facing down at the origin.
2. Select each facing in the inspector and confirm the idle pose changes. Drag the NPC and enter interaction text.
3. Add another NPC, choose **Fakemon**, select **Sylvafin**, and change its facing. Note the second ID and position.
4. Save. Close/reopen the map and verify both IDs, positions, facings, sprites and text.
5. Use the editor's existing **Test Map** action. Confirm both appear and sort with the world. Left-click the human, then the Fakemon, and confirm their text in the existing panel.
6. Optionally delete one NPC and add another; surviving IDs must remain unchanged. Undo/redo restores both placements and definitions.

## Limits deliberately retained

- This is stationary checkpoint-one NPC placement. Existing legacy NPC/trainer systems and their behavior remain unchanged; new NPCs are not added to walking/AI lists.
- Invalid placements/definitions are diagnosed and skipped at runtime, and block editor saves until repaired. Missing or unavailable editor art uses the existing colored point fallback; no replacement art is needed for the supplied valid catalog.
- Human idle regions are explicit authored-sheet metadata, using the existing parser. Extending the human catalog requires a catalog entry plus idle regions in that library.
- File writes are individually atomic with backups and rollback for reported errors. The two-file save is not a crash-proof filesystem transaction if the process or machine stops between writes.
- Visual verification of the interactive manual procedure remains a user checkpoint; the automated tests exercise its editor/runtime paths.
- Existing map schema, coordinate conversion, selection, dragging, terrain, transitions, overlays, fences, player frame parsing, collision implementation and dialogue renderer were left intact.
