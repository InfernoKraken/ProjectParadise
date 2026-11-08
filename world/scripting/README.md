# Scripting system

The current checkpoint is **V2**, with MoveSprite, FollowSprite, StopFollowing,
FaceSprite, and map-owned paths. Start with the generated
[command reference](../../docs/scripting_reference.md), also available in SCRIPT →
Reference. The [V2 implementation report](../../docs/scripting_v2_implementation.md)
describes movement, collision, authoring, and validation.

The sections below record the original V1 foundation and its checkpoint results.

Open the map editor, open an individual map, and select **SCRIPT**. Edit the source,
then Save normally. The sidebar divider can be dragged to widen the editor. Native
Godot CodeEdit provides line numbers, coloring, and completion (including Ctrl+Space).
Suggestions use its normal arrow/accept/cancel behavior. Diagnostics select the source
line. Invalid source can be saved as a draft; gameplay rejects it before executing.

Select an NPC or an object with an existing instance ID while in SCRIPT, then enter
the **OnInteract Block** name and press Enter or leave the field. Blank clears it.
Selection does not place, move, resize, paint, or activate warps. Return to OBJECTS
or INSPECTOR to edit placement. In game, clicking the associated NPC or registered
object visual runs the Block through the existing interaction path.

## Storage

There is one optional `script_source` string on the owning map JSON root, separate
from placement records. Optional `script_interactions` maps stable references to
Block names, for example `{"npc:1":"ProfessorIntroduction","object:instance_4":"Inspect"}`.
NPC IDs are the existing map-local numeric IDs; object IDs are existing `instance_id`
strings. Scripts are never embedded in NPC companion definitions. Legacy maps need
neither field. Existing MapDocument serialization, atomic save, backups, Save As,
rename, and map snapshot undo preserve the fields without a format migration or
another companion-file transaction. Deleting a referenced object produces a stale
association diagnostic; clear or reassign it explicitly.
Renaming a map preserves its source; Warp targets written inside other scripts
must be updated manually. Their stale map names are reported during validation.

The standalone editor loads the shared DSL modules from the gameplay project using
its existing `project_root` convention. There is no duplicated parser/registry.

## Language and interfaces

`Block Name:` introduces a named sequence, terminated by `End`. Whitespace and `//`
comments are ignored outside quoted strings. Strings support escaped quote,
backslash, newline, and tab. Commands are case sensitive. Flag and Block names use
ASCII identifiers: letter/underscore followed by letters/digits/underscores.

`command_registry.gd:DEFINITIONS` is authoritative: each key is a command name and
its array gives argument types/count. Parser validation and completion use these
definitions. Block argument types also drive target validation/completion. Typos use
deterministic Levenshtein distance; only close matches (at most two edits, scaled to
input length) are suggested. Suggestions never change source or execute.

`script_parser.gd:parse(source, references = {})` returns `{valid, blocks, diagnostics}`.
Instructions preserve command, typed arguments, and 1-based source line. Optional
reference pools let the editor validate existing species, map filenames/basenames,
NPC IDs, and object instance IDs. Direct recursive calls produce warnings; runtime
guards also cover indirect recursion. There are no expressions, loops, variables,
movement commands, custom commands, or executable Godot resources.

`script_runner.gd:start(source, block, map_name, flags, handler, cleanup)` validates
before executing. Call and satisfied flag conditions push a frame; Return resumes
the caller or exits safely. End terminates the entire execution. The maximum stack
depth is 32. A 4096-instruction budget between UI completions also bounds pathological
scripts. The runner's public `context` identifies map, Block, instruction index, line,
and command; `failed(details)` supplies the reason. It emits `finished` on cleanup.

The trusted host callback takes `(command, arguments, resume)` and returns `{}`, an
`{error: reason}`, or `{pending: true}`. Pending engine UI operations call `resume`;
generation tickets discard stale callbacks. This is sequential event orchestration,
not asynchronous/parallel language syntax. `stop()` cancels execution and performs
defensive cleanup. No instruction pointer, stack, UI state, or host state is saved.

`main.gd:run_map_block(filename, block)` accepts only loaded, currently active maps
and refuses to replace an existing run. `world_script_host.gd:execute` delegates:

| Commands | Existing integration |
| --- | --- |
| TextBox | `_start_dialogue`, completion callback, existing Enter/Space/Escape |
| SetFlag / ClearFlag / IfFlag / IfNotFlag | `game_flags.gd` state owned by the game, outside interpreter |
| Call / Return / End | Runner's transient stack |
| ShowSprite / HideSprite | Placed NPC registry and sorted visual visibility |
| ShowObject / HideObject | Existing object/tree/background instance-ID sort entries |
| FadeOut / FadeIn | Small viewport overlay/tween adapter; fixed 0.25 seconds |
| GiveFakemon | `battle.create_fakemon` and existing seven-member party/menu |
| Warp | `_set_route_location`, loaded-map registry, map-local X/Z plus origin |
| Lock / Unlock | Existing movement/input gates with an idempotent script lock |
| ShowSpritePicture / HideSpritePicture | Small TextureRect adapter for PNGs in `assets/overworld` |
| SaveGame | Existing `_save_game`, current selected manual slot |

All 21 requested commands have handlers. There is no PC/storage service for a full
party, so GiveFakemon fails safely rather than inventing one. Show/Hide is visual
visibility, not collision removal; hidden NPCs cannot be clicked for interaction.
Only visuals already registered by the map renderer can be targeted. Coordinates
for pictures are viewport pixels; PNGs must be supplied in `assets/overworld`.
Warp terminates execution at the map boundary. Flags persist in the existing manual
and auto-save payload as `game_flags`; absent flags in older saves restore empty.
Flags reset on starting a new party. Visibility changes are session-only.

Completion/failure/cancellation releases the script lock and clears script-owned
dialogue, fades, and pictures. Flags and session visibility changes already executed
are not rolled back. Failures log map/Block/line/command/reason through a warning.

## Files and validation report

Added: `world/scripting/{command_registry,script_parser,script_runner,game_flags,
world_script_host}.gd`, this README, `tools/map_editor/ui/script_panel.gd`,
`tests/scripting_test.gd`, `tests/scripting_world_test.gd`,
`tools/map_editor/tests/scripting_editor_test.gd`, and
`tests/fixtures/research_institute.paradise` (plus Godot-generated UID sidecars).

Modified: `world/main.gd` (host/interaction/save/input/visibility integration),
`tools/map_editor/map_editor.gd` (SCRIPT activity/source/association wiring),
`tools/map_editor/ui/editor_canvas.gd` (selection-only SCRIPT input),
`tools/map_editor/tests/map_editor_ui_test.gd` (four activity expectation),
`tools/map_editor/README.md`, and `.gitignore` (retain scripting tests/fixture).
No existing map JSON, NPC companion, placement schema, or catalog was changed by
this scripting checkpoint. Those files already had local changes in the workspace.

Validated with Godot 4.7.1, OpenGL3, headless CLI:

- Parser/runtime/completion/flags: **51 checks passed**.
- Editor/native completion/legacy map/draft diagnostics/read-only selection/atomic
  source and association persistence: **16 checks passed**.
- Actual NPC fixture/dialogue/party/save flags/lock cleanup/fades/warp integration:
  **22 checks passed**.
- Both Godot projects imported and parsed successfully.

Run the first two gameplay suites with `godot --headless --rendering-driver opengl3
--path . --script res://tests/scripting_test.gd` (or `scripting_world_test.gd`).
Run the editor suite with `--path tools/map_editor --script
res://tests/scripting_editor_test.gd`. Tests save temporary fixtures under `.godot`
and do not overwrite manual or auto-save slots.

Existing regression suites also ran, but their current workspace expectations fail:
`map_editor_test_runner.gd` expects 13 maps, an issue-free warp graph, and a different
stream-opening collision catalog entry; `map_editor_ui_test.gd` expects six terrain
options; `world_smoke_test.gd` expects a Moach-only encounter table;
`npc_checkpoint_test.gd` expects the older `Young Man` sprite catalog key;
`map_editor_runtime_test.gd` expects a different Jalovea warp endpoint. These areas
were already modified locally and are outside this scripting checkpoint. They were
not repaired or rewritten to make an unrelated test green.

Map entry headers use map_script_header {flag,true_block,false_block}; see scripting_reference.md for setup and restrictions. HideSprite/ShowSprite now disable/restore runtime NPC collision and interaction as well as artwork. NPC definitions remain intact and movement is safely cancelled when hidden.

## Medical ward interaction

The map editor's **Add Medical Ward Attendant** template installs a normal placed
NPC and a map-owned `MedicalWardCare` block. `HealParty` takes no arguments and
calls the existing ward service to restore HP, clear conditions, refresh the
party UI and autosave. Dialogue and input locking are authored with the existing
TextBox, Lock and Unlock commands. Cancel before HealParty leaves the party
unchanged; normal script cleanup releases the lock.
