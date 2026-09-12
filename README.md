Current features:
Added starter, wilds, demo moves, player movement, basic overworld, trainers, npc dialog, dex, special conditions, gender and other stats, as well as a medical center and a basic type system.
Save state added 8/9/2026.

Move animation fields are resolved centrally by `MoveAnimationResolver`. `animation_id`
is the optional ID of a custom authored animation in `data/move_animations/`.
`fallback_animation` is the optional generic engine animation used when no custom
animation can be played. `animation_kind` is a deprecated compatibility alias;
when both fallback fields exist, `fallback_animation` takes precedence. A valid
custom animation always takes precedence over the generic fallback.

Battle animation anchors use the universal resolution rule: requested semantic
anchor -> `origin` -> processed sprite center. Missing optional anatomy silently
uses `origin`; missing `origin` warns and safely uses the processed center.

Map data lives in `data/maps/`. Edit an individual JSON file to change that map;
`map_index.json` declares how those files are assembled into the current world.
Positions are `[x, y, z]`, sizes are generally `[width, height, depth]`, and map
`origin` values keep simultaneously loaded 2.5D regions separated in 3D space.
