# Boats: first checkpoint

In the Map Editor, add an NPC and choose Type **Vehicle**, then **Cargo**, **Luxury**, or **Tug**. Place its ground anchor in water and choose an existing movement preset and ranges. Existing scripted NPC move paths also work with its map-local NPC ID. Vehicles have no dialogue or interaction controls.

Boats always use swimming traversal, including older definitions without a movement_mode. Every water cell covered by the hull footprint must remain in canonical water. Boats share NPC pause gates, collision, map activation, save/undo and movers. They push a player obstructing their motion using the player's physics; solid obstructions can stop the push and boat. Each boat has directional hull bounds configured in npc_visual_resolver.gd. These exclude wakes and superstructure and project the normalized art into the map plane. Physical collision and movement queries share the same hull box at water level; boarding remains future work.

The supplied normal and stopped images switch according to actual displacement. Side art faces right and is mirrored for left. Images retain their full authored canvas and are fitted to a consistent directional canvas at load time, preserving the source files. Normal/stopped states must share canvas dimensions and hull registration; transparent padding and wakes never drive independent resizing. Cargo uses the boat_container files. Display lengths are configured in npc_visual_resolver.gd: Cargo 4, Luxury 3, Tug 2.5 map units. Each state currently has one supplied image; additional frames would be needed for animated wakes.

No existing canal placements are changed. Use the editor to choose routes and starting positions for this checkpoint.

Validation: tests/vehicle_test.gd checks all boats and directions, state canvas consistency, water traversal, no dialogue, patrol movement, and player pushing. The existing NPC movement regression and Map Editor import are also checked using headless Godot with the OpenGL driver.

Floating vehicle art uses the ordinary above-water draw layer (z=0), above the shared water surface (z=-1). Swimming creatures retain the submerged layer (z=-2). Water-only movement and hull collision remain independent of this draw policy.
