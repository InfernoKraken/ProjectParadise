Current features:
Added starter, wilds, demo moves, player movement, basic overworld, trainers, npc dialog, dex, special conditions, gender and other stats, as well as a medical center and a basic type system.
Save state added 8/9/2026.

Map data lives in `data/maps/`. Edit an individual JSON file to change that map;
`map_index.json` declares how those files are assembled into the current world.
Positions are `[x, y, z]`, sizes are generally `[width, height, depth]`, and map
`origin` values keep simultaneously loaded 2.5D regions separated in 3D space.
