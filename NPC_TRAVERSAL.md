# NPC traversal checkpoint

NPC companion definitions may add `movement_mode` (`ground`, `flying`, `swimming`) and a finite `height_offset`. Both are optional: ground and zero preserve old definitions. The map placement remains `{id, position, facing}`.

```json
{
  "type": "fakemon",
  "sprite": "Keklid",
  "interaction_text": "",
  "movement_mode": "flying",
  "height_offset": 0.0,
  "movement": {"preset": "left_right", "range": [2.0, 1.0]}
}
```

For Sylvafin use `movement_mode: swimming`; `height_offset: -0.8` puts its anchor at placement Y minus 1.3. The editor exposes mode and offset beside movement presets. Definition edits share undo/redo and companion saving. Invalid modes or nonfinite offsets are reported through existing validation and skipped safely at runtime.

## Elevation and collision

Runtime Y is authored placement Y plus map origin Y plus mode offset (ground 0, flying 2, swimming -0.5) plus manual offset. Bounded movement preserves that height. Sprite projection now uses the placed NPC's actual elevation, while depth sorting keeps its ground X/Z anchor.

NPCs use the existing 0.3-unit-high foot collision span. Godot shape casts compare that volume against actual obstacle geometry; flying does not ignore solid collision. Box colliders constructed through `_add_static_collision` expose world `elevation_span` metadata derived from position and size. Physics geometry remains authoritative, including other existing collider types. Tall art still requires appropriately authored collision geometry; this checkpoint does not regenerate trees/buildings from sprite dimensions.

Water's existing two-unit collision walls represent ground traversal restrictions, not physical walls. Flying excludes that terrain-only collision layer while retaining solid and platform wall collision. Swimming likewise excludes water barriers, checks its entire rectangular footprint against canonical water cells at each sampled motion step (at most 0.1 units apart), and checks solid obstacles at the authored shore-level collision span. This keeps submerged entities from slipping underneath ordinary walls. Swimming is horizontal traversal, not underwater volumetric navigation.

## Shared water surface and graceful limits

Maps containing swimming NPCs receive a shared translucent blue placeholder surface over canonical water cells. The existing water base is retained. Swimming sprites use render band -2, the shared surface -1, and ordinary sprites retain band 0 with their existing depth sorting. The surface follows camera projection and active map visibility. No species-specific sprite, mask, or shader is needed.

The surface is static and cell-shaped; animated water and refined shoreline appearance remain future work. Its construction is tested headlessly, but artistic appearance still needs an interactive Test Map review. Canonical water is required: unsupported legacy water or placement outside water produces a warning and pauses swimmer movement rather than permitting land traversal. This conservative fallback leaves existing player swimming and terrain rendering intact.

## Verification

The NPC movement test covers old presets plus mode defaults, offsets, invalid fields, live flying height, low-fence clearance, tall-wall collision, water footprint boundaries, submerged solid collision, and shared surface geometry/render band. The editor test covers mode/offset edits, undo/redo, paired save/reload, and unchanged placement schema. The existing NPC checkpoint test is also run. Godot command-line checks use OpenGL3; Windows certificate-store errors are environmental and recorded separately from script errors.

Map isolation follow-up: water surfaces retain the owning authored map render layer rather than inferring it from map origin. Inactive Area3D collision layers are disabled as well as monitoring, preventing raycast interactions with hidden NPCs in overlapping maps. Regression checks cover surface visibility and interaction restoration on map changes.
