# Map startup performance checkpoint

Investigated October 9, 2026 using Godot 4.7.1 on Windows.

## Findings and changes

- Test Map launches the gameplay scene, not a test suite. The world builder
  constructs all maps before selecting the requested map.
- The process inventory contained Codex Node helpers, with no lingering Godot
  or Python test runners. Nothing unrelated was terminated.
- Terrain baking repeatedly loaded identical masks and recomputed tinted source
  images. The existing terrain cache now retains CPU source images and prepared
  terrain images per animation frame. Each caller receives a copy so resizing,
  tinting, and orientation cannot corrupt subsequent recipes. `clear()` also
  releases these additional caches.
- Map tests skip player selection, Fakemon selection, and save-prompt
  construction. Normal new-game appearance selection is unchanged. Fakemon
  selection is available on demand if explicitly requested later.
- The test player is initialized as Male/Medium through the normal appearance
  routine. Previously its gender remained empty: atlas selection fell back to
  male frames, but the male-only left-mirroring check did not activate.
- Test Map tracks its launched process and rejects another launch while that
  game is running. Close the test game before launching another map.
- Verbose resource logging is disabled by default. Use Godot's `--verbose`
  option when detailed loading diagnostics are needed.

## Measurements

With the real OpenGL3 renderer on Intel Iris Xe, a two-frame Test Map launch
fell from **18.66 seconds to 11.16 seconds** (about 40% less wall time).
Its `_ready()` initialization fell from 14.50 seconds to 6.50 seconds.
Both launches used the tropical research lab, the same renderer, and the same
exit-after-two-frames setting. Wall time includes process startup and shutdown;
it is not an exact measurement of when the first visible frame appears.

Headless OpenGL3 runs with the current authored maps:

| Stage | Before | After |
| --- | ---: | ---: |
| Map data loading | 74 ms | 82 ms |
| World construction | 6,122 ms | 3,118 ms |
| Startup UI during Test Map | 3,446 ms | 2 ms |
| Total `_ready()` during Test Map | 9,643 ms | 3,202 ms |

This reduces map-test initialization by approximately 67%. The final benchmark,
including scene loading and the first process frame, took 4,326 ms. Normal game
startup also improved: the comparable benchmark fell from 10,565 to 7,635 ms.
These are local timing samples, not guarantees; headless runs do not measure
graphics-device initialization or first-render shader compilation.

Run the explicit benchmark from the repository root:

```powershell
godot --headless --rendering-driver opengl3 --path . --script res://tests/map_startup_performance_test.gd -- --profile-startup --test-map=tropical_research_lab.json
```

Omit `--test-map=...` to measure ordinary startup. Add `-- --profile-startup`
to an ordinary game launch to print data/world/UI timing. This instrumentation
does not run any test suites in normal gameplay.

## Validation and remaining work

Passed: startup benchmark (including requested-map spawn), left walking/idle
mirroring and diagonal checks, omitted selection screens, battle entry without
selection, selection on demand, normal startup selection construction, terrain
cache-order check, overworld animation/pixel checks, and map-editor script parsing.

The full terrain-transition test fails at line 41 on an authored eastern-route
shoreline expectation. The indoor runtime test fails its exterior-return and
wall-disable checks. Both failures were reproduced with the original startup
implementation and original terrain cache; they are separate from this change.

All maps still build at startup. Loading regions on demand could improve this
further, but requires a separate checkpoint covering warps, NPC references,
visual layers, and save/load behavior. Source-image caching trades a small amount
of retained CPU image memory for less disk I/O and processing; the number of
entries is bounded by terrain definitions, masks, and animation frames.
