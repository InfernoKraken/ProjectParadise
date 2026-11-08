# Jalovea City performance investigation — 2026-10-31

## Conclusion

Prioritize the NPC/decorative water overlay update, not a new base-tile chunk
renderer. Base terrain already uses 16×16 mesh batches. A rendered ablation that
keeps all 516 water polygons visible but stops rewriting their vertices reduced
median live frame time from 172.641 ms to 13.959 ms with the same 380 draw calls.
This identifies repeated water geometry submission as the strongest measured
cause of the severe slowdown at the city's entry. It is not proof that collision
or transitions have zero cost, or a forecast of performance on every machine.

## Method

Godot 4.7.1, OpenGL Compatibility, Intel Iris Xe, project 960×540 viewport.
`tests/jalovea_performance_probe.gd` loads the ordinary world and starts Jalovea
using the existing Test Map path. No production behavior was modified. The
probe profiles CPU calls and temporary in-memory ablations; it never saves maps.
Rendered comparisons disable VSync and the frame cap, warm for eight frames and
sample 40 frames at the authored entry, idle. All maps are still resident.
Live comparisons leave physics enabled. Frozen-update comparisons disable the
main script physics callback, not the physics server. Frame times are end-to-end
wall-clock intervals, not isolated GPU timings. Direct-call CPU timings and
rendered ablations should not be added together. Background load, shader caching
and thermal conditions can affect the numbers; comparisons are diagnostic.

Run from the game project:

```powershell
godot --rendering-method gl_compatibility --rendering-driver opengl3 --path . --script res://tests/jalovea_performance_probe.gd --log-file jalovea_probe.log
```

Add `--headless` for CPU-only measurements. On this Windows setup, invoke via a
waiting subprocess if the GUI executable detaches before returning output.
Read the PROBE lines in the log. Error messages elsewhere in the log matter too.

## Counts

Jalovea is 85×47 map units and contains 126 authored objects. Its built world
children include 20 terrain-base batches, 579 terrain-transition meshes and
723 static collision bodies (including water/aprons and ordinary objects).
A separate sorted 2D water overlay creates 516 Polygon2D nodes. Entire-world
counts are 7,357 scene nodes, 38 base batches, 882 transition meshes and 1,155
static bodies. Sorted-entry registries span the loaded world: 532 objects,
113 trees, 52 NPCs and 11 backgrounds. These are resident counts, not all
simultaneously rendered. Existing map layers already cull other maps and disable
their collision layers.

## Rendered results

Final run, entry camera, one active light:

| Temporary configuration | Median frame ms | P95 ms | Draw calls |
| --- | ---: | ---: | ---: |
| Main script physics disabled, normal visuals | 7.794 | 9.728 | 380 |
| Same, transition meshes hidden | 5.386 | 6.907 | 265 |
| Same, water polygons hidden | 5.950 | 7.959 | 173 |
| Same, lighting shader source loop disabled | 7.491 | 9.022 | 380 |
| Normal live physics and visuals | 172.641 | 222.392 | 380 |
| Live physics, water vertices frozen but still drawn | 13.959 | 19.049 | 380 |
| Live physics, entire sort/projection update frozen | 8.404 | 12.685 | 380 |

The normal live segment averaged about 9.78 ms per script physics callback and
accumulated multiple physics ticks per rendered frame. The large rendered cost
is not explained by script CPU timing alone: changing hundreds of polygons also
invalidates/submits renderer geometry, and physics catch-up can amplify it.
Freezing water geometry preserves its draw count and appearance at this idle
camera, providing a stronger isolation than merely hiding it.

Direct-call medians in this run: idle physics 6.90 ms, sort/projection 6.73 ms,
water vertex projection 1.48 ms, lights 0.60 ms, platform art 0.12 ms, traversal
0.09 ms. Removing water from the projection registry reduced sort work to
3.97 ms; omitting objects/trees reduced it to 2.44 ms. These isolated loop
measurements omit later renderer consumption and are sensitive to scheduling.

## Code findings

- `world/terrain_mesh_batcher.gd`: base terrain is already batched by terrain
  identity per 16×16 chunk; creating a second base-tile chunk system duplicates it.
- `world/main.gd::_update_npc_water_surfaces`: creates one polygon per water
  cell, projects four corners and assigns `polygon` every sort update, including
  unchanged cameras and distant cells. This water effect is separate from the
  batched 3D water texture.
- `_update_sort_canvas` runs in the physics callback, scans global registries,
  and reprojects all active-map art even when off screen or unchanged.
- `_build_terrain_transition_overlays` still creates individual meshes with
  composite textures/materials; base batching does not cover these.
- `_build_canonical_water_collision` creates a body per water cell and additional
  shoreline aprons. The count is a future consolidation target, not yet proven
  to be the main frame bottleneck.
- Startup produced 220 `format != p_src->format` errors at
  `TerrainTransitionTextureCache._apply_slice`. This is a separate transition
  image-format correctness/startup problem. Full-world diagnostic startup took
  roughly 18 seconds in the final run; it includes loading/baking all maps and
  logging errors, not just Jalovea creation.

## Recommended checkpoints

1. **Water overlay:** cache static projected-local geometry and move a common
   parent when the camera translates. Rebuild only on grid, projection/zoom or
   viewport changes. Combine water polygons into chunk meshes or merged regions
   to also reduce draws. Preserve the overlay's intended masking of swimming NPCs
   and semi-submerged decorations, layer order, map visibility and shoreline
   behavior. Removing the effect is only a diagnostic, not the proposed fix.
2. **Projection/sorting:** index entries by map and spatial chunk; update only
   visible chunks plus an artwork overhang margin. Cache static placements;
   update moving actors separately. Ensure interaction and scripted movement
   continue to work outside the visible region. Consider render-frame projection
   rather than repeating renderer geometry submissions during physics catch-up.
3. **Transition batching:** reuse the existing chunk coordinates, batching by
   texture/material/render height. Composite/animated transitions require shared
   textures or an atlas before many differently textured cells can share a draw.
   Preserve animation, clipped water edges, lighting and transition priorities.
4. **Collision:** profile the physics server and movement near water separately;
   if needed merge interior water rectangles while retaining shoreline aprons.
5. **Streaming:** defer whole-map loading/unloading until memory, initial load or
   transition stalls justify it. Current measurements do not require an entirely
   new streaming architecture to address the worst live slowdown.

Normalize source/destination image formats in the transition texture cache as a
separate small correctness fix. Validate each rendering checkpoint at entry,
dense city center and shoreline, moving and stationary, at multiple zooms and
with swimming NPCs/decorations. Re-run the same baseline and ablations; retain
visual behavior while checking median and tail frame times.

## Implemented checkpoint: cached water and camera-gated animation

The water overlay now stores local polygon vertices. Orthographic camera movement
translates its common parent; zoom, camera basis/projection and viewport changes
invalidate geometry. A conservative ground-space camera rectangle expanded by
128 screen pixels controls polygon visibility. Offscreen polygons retain cached
geometry, so returning does not require a new build. Perspective cameras use the
more conservative full-camera invalidation path. Terrain grids are static during
normal play; this cache is built per loaded surface rather than per paint stroke.

Animated base terrain and transition textures register their mesh consumers with
OverworldTextureAnimation. Existing frames and shared texture variants remain
cached. A managed variant only submits frame changes when at least one consumer
on the active map intersects the expanded camera range. All variants retain the
shared logical clock, and re-entry synchronizes the texture immediately, even
between ticks. One visible consumer can keep a shared variant advancing for all
of its users; no per-tile animation timers or duplicate frame textures are added.
Unregistered consumers keep the original animation behavior for compatibility.

Verification: `tests/terrain_camera_cache_test.gd` covers cached pan alignment,
zoom/viewport invalidation, visibility/map changes, animation pause, prewarming
outside the viewport and phase synchronization. Existing texture-animation and
water-decoration tests pass. The broader NPC movement suite fails at its existing
swimmer-collision expectation (fraction 0.25 versus expected 0); a fixture with
all new rendering hooks disabled reproduces that result before the water-cache
checks. It was not changed by this checkpoint.

Same-machine rendered probe after this change: idle live median 2.739 ms, p95
6.896 ms; camera-pan median 2.548 ms, p95 7.915 ms. Stationary water-update CPU
median 0.007 ms. Draw count remains 380 at the entry. These are short diagnostic
samples, with different scheduling/thermal conditions from the original run,
not a guaranteed FPS target or a measurement of every city area. The earlier
transition texture-format errors remain outside this checkpoint.

## Implemented checkpoint: static artwork projection cache

Static trees, props, walls, backgrounds, bridges and overlays now cache their
projected shapes. Orthographic camera pans translate cached Y-sort positions;
stationary camera/map/visibility frames skip the whole static projection pass.
The existing 128-pixel warm margin applies to full screen-space artwork bounds,
including cropped/rotated sprites. Attached artwork extends its host's culling
bounds, and attachment-local transforms are cached. Light-source reach extends
the bounds when larger than the sprite. Invisible platform art skips its actor
compositing work. Collision, NPC simulation and script execution stay active.

Zoom, viewport, camera rotation/projection, map switching, script hide/show and
collection changes invalidate the appropriate view/geometry caches. A runtime
system that directly changes static placements or sprite geometry should clear
`static_art_view_signature` to request another static pass. Editor map reloads
build new entries/roots. Within that pass, individual source/geometry keys detect
placement, texture, crop, rotation, scale and related changes. Moving actors stay
on their existing dynamic path.

`tests/static_art_cache_test.gd` verifies stationary reuse, pan alignment,
visibility re-entry, hide/show, zoom, resize, authored changes, warm margin,
tall artwork with offscreen anchors, rotation, and attachment overhang. The
Jalovea probe also checks that stationary/pan updates preserve static rebuild
counts. Runtime map-isolation checks pass. Broader map-editor/navigation suites
stop at warp expectations unrelated to projection; disabling the entire sorted
artwork update reproduces those warp expectations as false.

In the rendered final probe, stationary sort CPU median was 0.504 ms (previous
water-only checkpoint about 1.93 ms), idle script physics 0.839 ms, and live
physics callback mean 1.306 ms. End-to-end rendered median was 2.772 ms idle and
2.984 ms panning; pan p95 was 14.842 ms. The entry still submits 380 draws:
this checkpoint removes projection/transform work rather than rebatching
terrain-transition meshes. Short samples vary with scheduling and thermal state;
there is no claim of equivalent gains in every view or lower GPU work.

## Implemented checkpoint: terrain transition batching

Transition construction still resolves the same per-cell composite textures,
filters water patches near authored walls, and computes the same clipped plane
rectangles and priority heights. The existing TerrainMeshBatcher now combines
transition quads by 16×16 chunk, shared texture identity and priority. Materials,
alpha transparency, per-cell UVs and animation proxies are retained. Batch nodes
register with the same camera-range animation manager. Collision, navigation and
authored map data do not change. Per-tile debug metadata is retained in each
batch's `transition_cells` rather than on individual scene nodes.

Jalovea transition mesh count: 579 → 319 (260 fewer, about 45%). Entire-world
transition mesh count: 882 → 590. A rendered entry probe submitted 329 total
draws, including 64 transition draws (265 with transitions hidden). Earlier
pre-batch probes submitted 380 total / 115 transition draws. These short probes
are diagnostic, with differing scheduling/light visibility conditions; the
stable node-count reduction is the primary evidence, not an FPS guarantee.

`tests/terrain_transition_batch_test.gd` checks that matching cells share a draw,
texture/height/chunk boundaries remain separate, and batched vertices and UVs
match the original clipped PlaneMesh geometry. Existing base batching checks
pass. The 4096-water-cell runtime animation stress check passes with the base
chunk count corrected to sixteen (its previous expectation of 4096 nodes predated
base batching). `tests/beach_transition_batch_runtime_test.gd` builds a real
128×64 sand/water map: 254 shoreline cells become 80 animated batches, with no
collision/elevation effect or authored-data mutation. Further atlas work could
combine different texture variants, but is deliberately outside this checkpoint.

## Fenced shoreline corrections — 2026-11-04

The cached NPC/decorative water tint overlay now uses the same fence-clipped
regions as the 3D water base, including two-piece corner regions. Region geometry
is computed once and retains translation-only camera caching. Previously the
full-cell tint could cover the dry side of a clipped water tile.

When a fence-clipped dry remainder borders sand on that side, the base batcher
fills only that dry region with sand. Water/sand rectangles do not overlap. Sand
cells next to hard boundaries or at mixed water/other-land junctions retain solid
sand instead of conflicting half-cell overlays. Ordinary two-terrain shorelines
keep their existing masks. These are disposable rendering decisions; authored
terrain, collision and traversal identity do not change.

Transition texture slicing now converts source images to the destination format
before blitting. This resolves the prior format-mismatch errors that could
silently discard transition slices. A rendered Jalovea capture at the canal
endpoint is saved by `tests/shoreline_visual_check.gd`; this diagnostic disables
autosave. Focused shoreline tests cover straight and corner clipping, dry-side
sand fills, disabled fence segments, no-fill cases, cached overlay panning,
solid-sand policy and mixed RGB/RGBA compositing. Existing camera-cache, base
mesh, animation and water-decoration checks pass. The older terrain-transition
suite stops at its route-data assertion on line 41; its resolver generation path
was not changed by these rendering corrections.
