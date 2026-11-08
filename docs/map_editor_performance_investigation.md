# Large-map editor performance investigation — 2026-11-01

## Conclusion

Terrain contributes mainly by expanding the editor's object list and triggering
repeated whole-document work. The dominant measured canvas cost is sorting every
object on every redraw, not just drawing terrain. Painting is dominated by
regenerating the Raw JSON text/widget and rebuilding derived document/UI state.
The runtime chunk/animation optimizations do not apply to this standalone 2D
Control drawing path. No editor production code or map files were changed for
this investigation; the diagnostic performs edits only in memory.

## Reproduction and scope

`tools/map_editor/tests/large_map_performance_probe.gd` loads Jalovea through the
normal editor and uses an instrumented canvas subclass to time real redraws and
temporary drawing ablations. It also profiles extraction, validation, sorting,
hit testing, refreshes and eight unique terrain-cell changes. It never calls Save.

```powershell
godot --rendering-method gl_compatibility --rendering-driver opengl3 --path tools/map_editor --script res://tests/large_map_performance_probe.gd --log-file editor_large_map_probe.log
```

For CPU/detail timings without opening a rendered window:

```powershell
godot --headless --rendering-driver opengl3 --path tools/map_editor --script res://tests/large_map_performance_probe.gd --log-file editor_detail_probe.log -- --detail-only
```

Measured on Godot 4.7.1, OpenGL Compatibility, Intel Iris Xe. The rendered canvas
was 1588×1010, map-fit zoom about 0.479; zoom-1 comparisons use that same canvas.
The detail-only run used a 600×500 headless canvas and fit zoom 0.2. CPU sorting,
serialization and refresh timings are not GPU/frame timings. Draw samples include
14 requested redraws; detail operations usually use 15 samples or 5 for expensive
refreshes. Warm caches, hardware, current map contents and background activity
influence absolute times. The reported draw counts include the editor UI.

## Findings

The loaded map is 85×47 units. Its document becomes 1290 editor objects, including
1146 canonical terrain cells and 531 water cells. This is a substantially larger
editable-object list than its 126 ordinary authored objects. Canonical terrain
is expanded one cell at a time in `_append_terrain_entry/_append_terrain_cell`.
The runtime base/transition mesh batching is not used by the editor canvas.

### Canvas redraws

| Diagnostic configuration | Median CPU draw ms | Approx. draw submissions |
| --- | ---: | ---: |
| Normal edit mode, fit map | 128.8 | 5303 |
| Labels/bounds suppressed, otherwise normal | 108.5 | 218 |
| Terrain drawing skipped, all objects still sorted | 90.3 | 718 |
| Normal edit mode, zoom 1 | 126.1 | 5303 |
| Zoom 1, terrain drawing culled to view + 128px | 99.9 | 2018 |
| Placement Preview, zoom 1 | 197.8 | 1341 |

These are `_draw` CPU times, not idle editor FPS or isolated GPU times. The editor
has event-driven redraws rather than a continuously running tile animation loop.
The culling ablation deliberately culls terrain only, so it does not test the
complete future asset-overhang/selection behavior. Suppressing geometry removes
both labels and outlines; it does not isolate text cost from outlines. Placement
Preview changes projection, wall art and water clipping as well as labels.

`EditorCanvas._draw` rebuilds water lookup/wall arrays, duplicates the full object
list, sorts it through GDScript callbacks, then draws every object without a
viewport filter. Normal-mode terrain cells each receive artwork, bounds and a
label. Zooming in does not reduce how many cells are processed. The clipping
renderer may reject offscreen pixels, but the CPU still does all that work.

Sorting alone measured 89.5 ms in the rendered probe and 86.6 ms in the detail
probe. Precomputed rank/depth/path/overlay keys reduced a normal-mode sort to
11.3 ms (key preparation outside the timed sort). This is a diagnostic, not a
production replacement: Preview's special wall tie-order rules still need to be
preserved. The real fix should cache the sorted order, not sort even cheap keys
again on every pan/zoom. Rank/depth/path helpers are repeatedly recomputed by the
current comparator, and preview wall-overlay depth can scan all objects from
inside the comparator. Skipping only terrain drawing leaves the sort bottleneck.

### Editing and refresh

| Operation | Median CPU ms |
| --- | ---: |
| Extract editor objects | 29–32 |
| Validate current map | 3.4–3.5 |
| Serialize document alone | 43–45 |
| Refresh Raw JSON widget, including serialization | 205 |
| Scan connection graph from disk | 156 |
| Full editor refresh | 550–579 |
| Hit-test object mode | 48–53 |
| Hit-test terrain mode | 55–57 |
| Apply one new painted terrain cell | 222–247 |

The detail run had zero validation issues. Canvas error highlighting took about
0.002 ms, and script-panel refresh about 2.5 ms, so neither explains this sample's
stall. It would be misleading to blame validation generally: full validator
execution was only around 3.5 ms.

`_terrain_cell_changed` scans terrain ownership, extracts every editor object,
replaces canvas data, validates the document, rebuilds validation display and
regenerates Raw JSON on every distinct painted cell. Undo serialization also
occurs on the first change in a stroke. Stroke completion then calls the full
refresh. Thus a normal drag can pay a multi-hundred-ms cost for every grid cell.

`_refresh_all` calls `MapGraph.scan` for layout warnings, then `_refresh_graph`
calls it again. Each scan reloads indexed map JSON documents and computes graph
information. The roughly 312 ms for two scans plus 205 ms Raw JSON refresh and
31 ms object extraction account for most of the 579 ms full refresh. Paint-cell
updates do not scan the graph, but still pay for the expensive Raw JSON widget.

`_hit_test` also copies and sorts the full object list before applying the
selection-mode filter. Terrain mode could usually query a grid cell directly;
object mode should exclude terrain before sorting or reuse a cached hit order.

## Recommended checkpoints

1. **Cache canvas sort order and hit-test candidates.** Precompute rank/depth/tie
   keys and a stable ordered list when document contents, relevant object
   transforms or display/selection modes change. Pan/zoom should reuse it.
   During object dragging, update the dirty object's depth rather than rebuilding
   all static keys. Preserve current wall, render-band, stable-path and marker
   ordering. Terrain lookup should use a cell index; non-terrain hit candidates
   should be filtered before ordering. Verify selection remains identical to the
   current code on overlapping objects, floors, NPCs and walls.
2. **Move expensive UI work out of per-cell painting.** Keep the authoritative
   terrain grid and dirty cells responsive during a stroke, retain one undo
   checkpoint, and defer full object extraction, Raw JSON/widget regeneration,
   validation display and graph work to stroke completion or an idle debounce.
   Raw JSON should regenerate on opening its tab or when needed for save, not
   every cell while hidden. Cache one graph result and reuse it for warnings and
   graph display; invalidate on relevant map/warp/index/file changes. Keep full
   save validation and the existing atomic save/backup behavior.
3. **Viewport culling and terrain presentation.** After the first two fixes,
   cull to the canvas plus the established 128px margin. Use full artwork and
   attachment bounds for props; retain selected/hovered handles near the view.
   Draw terrain labels only for selected/hovered cells or at useful zoom levels.
   Cull before submitting textures/outlines/text, not merely at renderer clipping.
   Preserve cell-level painting, erase, fill, selection and Undo/Redo.
4. **Dirty terrain draw chunks if needed.** Separate static terrain drawing from
   dynamic handles/grid/path overlays; cache 16×16 terrain draw chunks and rebuild
   only touched chunks plus shoreline neighbors. Cache water clipping by terrain
   and wall revisions. Reuse gameplay's geometry/clipping rules where feasible,
   but the standalone editor has its own resource root and a 2D canvas, so its
   rendering cache should not simply instantiate gameplay 3D meshes. Do not
   change authored data into merged shapes just to optimize display.

Suggested acceptance checks: sort count stays unchanged during pure pan/zoom;
paint-cell drag does not rebuild Raw JSON or graph state; untouched terrain
chunks do not rebuild; culling preserves large artwork and selection; brush,
fill, resize, Undo/Redo, save/reload and warp graph results remain correct. Measure
normal mode and Placement Preview separately, fit-map and zoomed-in views, and
both stationary and dragging interactions. Full chunk streaming is not needed
as the first step for the current roughly 1300-object editor workload.

## Implemented checkpoint: draw order and selection cache

`EditorCanvas` now precomputes sort keys once per relevant change and keeps the
ordered object list. Document replacement and in-place drag, wall-anchor and
resize edits invalidate it. Draw-mode changes rebuild the appropriate order;
pan, zoom and selection-highlight redraws reuse it. Selection stores ordered,
mode-filtered candidates and preserves the previous sort's equal-rank overlap
behavior by sorting before filtering. Cached entries retain references to the
editable object records, so screen-space hit geometry still follows the camera.
Other code performing in-place object edits should call `invalidate_order_cache`;
normal editor edits already use document replacement or the instrumented canvas
mutation paths. Array replacement invalidates automatically.

No production changes were made to terrain drawing, labels, water clipping,
Raw JSON refresh, validation or graph scanning in this checkpoint.

The updated probe includes a diagnostic legacy-order override, allowing the old
sort-on-every-redraw implementation and the cache to be compared during the same
process, with the same map, canvas and artwork. Final rendered results:

| Same-run comparison | Old order path | Cached order path |
| --- | ---: | ---: |
| Normal fit-map `_draw` median | 108.044 ms | 36.982 ms |
| Normal fit-map `_draw` p95 | 113.219 ms | 48.695 ms |
| Object hit test median | 45.639 ms | 0.255 ms |
| Draw submissions in normal mode | 5303 | 5303 |

Cached order lookup was approximately 0.001 ms median. Its p95 included a cold
rebuild of about 13.8 ms. Fifty pan/zoom changes caused zero additional sorts.
Terrain-mode hit testing measured 1.438 ms median; it still checks candidates
rather than using the future direct grid lookup. Raw JSON, graph and painting
costs remain, with painting about 175 ms median in this run; differences from
prior runs are not attributed to an optimization of those unchanged paths.

`tests/canvas_order_cache_test.gd` compares cached and old ordering for normal,
Preview and SCRIPT modes; object/terrain selection; fence editing; equal-rank
overlap; and mutation invalidation. It checks that pan/zoom and repeated hit
queries do not rebuild the order. Directional terrain expansion, terrain fill
with Undo/Redo, and map resize regression checks also pass in Godot.

## Implemented checkpoint: deferred refresh and graph reuse

Terrain strokes now change authoritative JSON data and update only the affected
canvas cell while the brush is down. Full extraction, validation and panel
refresh occur once on completion. One Undo snapshot is retained per stroke;
Undo/Redo and saving flush pending stroke work. Replacing/opening a document
resets pending stroke state. Transient preview paths are replaced by real JSON
paths at completion. Paint and erase both preview immediately.

Raw JSON requests mark the view dirty. Serialization and TextEdit replacement
are skipped while that view is hidden or a terrain stroke is active. Opening the
Raw JSON tab (including revealing its parent MAP tab) renders the latest data;
if visible during painting it refreshes on stroke completion. Saving serializes
and validates the document independently of the view.

Both layout warnings and Warp Graph display use one cached MapGraph result.
The cache fingerprints the map directory's JSON filenames and content hashes,
so external edits, same-size changes within the same timestamp tick, additions,
deletions, saves and directory switches invalidate it. This retains existing
disk-graph semantics and avoids repeated lossless JSON parsing. Hashing remains
a small cache-check cost; it is not done on every painted cell.

Jalovea CPU/detail probe after this checkpoint: painted-cell median 1.062 ms,
first/maximum cell 36.148 ms (the one Undo snapshot), stroke completion 43.746 ms,
full refresh with hidden Raw JSON 43.639 ms. Earlier ordering-only probe measured
paint median 174.834 ms and full refresh 401.814 ms. Those earlier results came
from the rendered probe; these are short CPU/detail measurements rather than a
controlled FPS comparison. Raw hidden refresh requests cost about 0.001 ms;
cached graph checks about 3.244 ms versus a direct graph scan at 111.389 ms.

The new deferred-refresh test covers live paint/erase preview, one Undo per
stroke, no-op strokes, Undo/Redo, hidden/visible Raw JSON, opening the tab, graph
cache reuse and same-size external changes, full save rejection for missing
required fields, and a validated save/reload round trip. Existing canvas-order,
terrain-fill and directional-expansion checks pass as well. Save validation and
atomic map/NPC writing remain in place.

## Implemented checkpoint: editor culling and terrain label density

The canvas now draws only objects intersecting the viewport plus a 128-pixel
margin. Bounds include footprints and full sprite art, width/height overrides,
rotated artwork, wall routes and preview-wall sprite overhang. Attached overlays
are tested on their own resolved artwork bounds, independently of host anchors.
Selected handles are retained during editing, and document objects/hit testing
are not removed by culling. Terrain error outlines are also filtered to the view.
Static local artwork bounds and the resulting visible ordered list are cached;
mutation, camera/mode changes and selection/validation state invalidate the
relevant caches. Pure repeated redraws do not repeat the culling pass.

Ordinary terrain labels are hidden below a 24-pixel grid-cell width (zoom 0.75
at the default 32 pixels/unit). Selected, multi-selected and validation-error
terrain retain their labels. Non-terrain labels and inspector text are unchanged.
Preview and SCRIPT modes retain their existing label suppression.

Same-process Jalovea comparisons using diagnostic switches to restore the old
unculled/all-label behavior (while retaining the previous sort cache):

| View | Before redraw median | After redraw median | Before / after draws |
| --- | ---: | ---: | ---: |
| Frame map | 30.182 ms | 30.012 ms | 5303 / 4156 |
| Zoom 1 | 36.890 ms | 12.793 ms | 5303 / 2014 |

The fit-map label reduction lowers submissions but did not establish a CPU-time
improvement in this sample. Most of that view remains inside the viewport, so
culling cannot eliminate much artwork. Zoomed-in views show a larger reduction.
These are canvas CPU redraw measurements and whole-editor draw submission
counts, not a guaranteed FPS improvement. Cold cache rebuilds contribute tail
latency; normal frame-map p95 was about 47.9 ms and zoom-1 p95 about 38.0 ms.

`tests/canvas_view_culling_test.gd` checks near-margin cells, offscreen removal,
panning/re-entry, tall buildings, rotated sprites, attached overlays, crossing
walls, selected handles, normal/Preview/SCRIPT modes, unchanged hit testing and
label-threshold/selection/error exceptions. Previous canvas-order and deferred
refresh tests also pass. No save-format or runtime-rendering changes are needed.
