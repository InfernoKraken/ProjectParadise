# Map isolation and runtime performance fixes

The clearing's invisible center blocker was a foreign traversal surface: Tropical Lab has a vertical bridge near X 0.22 / Z -1. Its collider and artwork were inactive, but `_update_traversal_surface` still considered every loaded bridge and could raise or laterally clamp the player. Bridge surfaces now carry their map's visual-region ownership, including an explicit authored-map assignment, and movement ignores inactive-map surfaces. Any stale active surface is cleared before containment runs.

The active-region setter was scanning the full shared world and writing every collider's collision layer and monitoring flags on every physics tick. A headless real-scene benchmark measured 12.69 ms per call before the fix. It now applies the region only when the location changes. `_configure_visual_regions` invalidates the cache when collision ownership is rebuilt. Actual transitions still perform the necessary activation work; repeated ticks do not.

F3 toggles collision diagnostics during gameplay. When movement hits a physical collider or shoreline constraint, the hint and Godot output show the collider node path, map layer, and world position. Reporting is deduplicated and disabled by default. This lets remaining authored collision-shape mismatches be identified rather than guessing which object blocks the player.

The runtime regression loads the actual world scene, checks foreign bridge isolation at overlapping coordinates, asserts that all foreign-map colliders are inactive in the clearing, and times repeated same-map activation calls. The NPC movement regression checks mode collision behavior and interaction restoration across maps. Headless CPU timings do not measure rendered FPS or GPU lighting cost; the fix removes a measured CPU hotspot, without claiming that it resolves every possible frame-time issue.

## Second performance pass

A repeated-call CPU profile of the real world scene (120 calls per method, OpenGL3 headless) identified lighting preparation as the largest remaining sampled cost, even without an emitting follower. `_update_sort_canvas`, which includes `_update_fakemon_lights`, took 14.31 ms initially; lighting alone took 11.02 ms. After caching, the same measurements were 1.06 ms and 0.38 ms respectively. These nested times must not be added together.

The day/night controller now registers terrain materials and world sprites instead of discovering them every update, shares updates across registered materials, and refreshes uniforms only when quantized tint, light count/texture binding, map lighting mode, or viewport size changes. Moving lights still update the light-data texture in place. Visible world sprite texture changes remain supported. New world render nodes invalidate registration, and new canvas nodes trigger lighting installation. NPC/follower emission changes explicitly switch their materials so choosing a different follower does not leave a stale light exemption.

Sprite sorting caches each entry's map ownership and reuses the active map layer for a pass, avoiding repeated nearest-region searches even when ownership was already available.

Validation: the existing Fakemon lighting test passes with added assertions that repeated stable updates leave the material generation unchanged and that changing clock time refreshes it. The OpenGL pixel rendering test passes for terrain/canvas illumination, emitter exemption, moving light, and source removal. Runtime map isolation also passes. Remaining choppiness may require rendered frame-time and GPU measurements; this CPU profile does not establish rendered FPS.
