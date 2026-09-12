extends SceneTree


func _initialize() -> void:
	var scene := load("res://world/main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	assert(main.traversal_surfaces.size() >= 2, "Authored vertical and horizontal bridges must build traversal surfaces.")
	var surface: Dictionary = main.traversal_surfaces.filter(func(item: Dictionary) -> bool: return String(item.name).begins_with("EastRoute"))[0]
	assert(main.world.get_node_or_null("EastRouteUniversalObject0DeckTile0") != null, "Bridge deck tiles must render separately from terrain.")
	assert(main.world.find_child("EastRouteCanonicalBase_*_water",false,false) != null, "Canonical water visuals must remain present beneath the bridge.")
	var east_water_collision:=main.world.find_child("EastRouteCanonicalWaterCollision*",false,false) as StaticBody3D
	assert(east_water_collision != null, "Underlying canonical terrain collision must remain independently functional.")
	assert(east_water_collision.collision_layer == main.TERRAIN_OBSTACLE_LAYER, "Water must use the filterable terrain-obstacle layer.")
	assert(is_equal_approx(float(surface.width),1.3),"The shared bridge asset must widen traversal and art by 30 percent.")
	assert(is_equal_approx(float(((main.world.get_node("EastRouteUniversalObject0DeckTile0") as MeshInstance3D).mesh as PlaneMesh).size.x),1.3),"Vertical bridge deck art must use the widened reusable width.")
	var deck_material := (main.world.get_node("EastRouteUniversalObject0DeckTile0") as MeshInstance3D).material_override as StandardMaterial3D
	assert(deck_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Transparent bridge pixels must reveal the independently rendered terrain below.")

	var center: Vector3 = surface.center
	main.player.position = Vector3(center.x, 0.65, center.z)
	main.active_traversal_layer = 0
	main._update_traversal_surface(main.player.position)
	assert(is_equal_approx(main.player.position.y, 0.65) and main.active_traversal_layer == 0, "An actor beneath a bridge must stay at terrain elevation.")
	var under_position := Vector2(main.player.position.x, main.player.position.z)

	# Enter from the north end, then advance onto the deck at real world elevation.
	main.player.position = center - Vector3(0, 0, float(surface.length) * 0.5 + 0.9)
	main.player.position.y = 0.65
	main._update_traversal_surface(main.player.position, Vector2(0, 1))
	main.player.position = center - Vector3(0, 0, float(surface.length) * 0.5)
	main._update_traversal_surface(main.player.position, Vector2(0, 1))
	main.player.position = center
	main._update_traversal_surface(main.player.position, Vector2(0, 1))
	assert(main.active_traversal_layer == 1 and is_equal_approx(main.player.position.y, 1.65), "Walking across a bridge must use its elevated world-space deck.")
	assert(Vector2(main.player.position.x, main.player.position.z) == under_position, "Under and on-deck actors may share X/Z while differing in world Y.")
	assert((main.player.collision_mask & main.TERRAIN_OBSTACLE_LAYER) == 0, "Deck traversal must ignore only underlying terrain obstacles.")
	assert(main.player_sort_root.z_index > main.bridge_sort_entries[0].sort_root.z_index, "A player on the deck must render over bridge art.")
	main.player.position += (surface.side_axis as Vector3) * 2.0
	main._update_traversal_surface(main.player.position, Vector2(-1, 0))
	var constrained: Vector2 = main._surface_coordinates(surface, main.player.position)
	assert(absf(constrained.y) <= float(surface.width) * 0.5 - 0.4 + 0.001 and main.active_traversal_layer == 1, "An elevated actor must not walk off either long side of the deck.")

	# A ground actor approaching the long side cannot jump to bridge elevation.
	main.active_traversal_layer = 0
	main.player.position = center + Vector3(float(surface.width) * 0.5 + 0.1, 0.65, 0)
	main._update_traversal_surface(main.player.position, Vector2(-1, 0))
	assert(main.active_traversal_layer == 0 and is_equal_approx(main.player.position.y, 0.65), "Bridge sides must not become accidental entrances.")
	assert(main.player_sort_root.z_index < main.bridge_sort_entries[0].sort_root.z_index, "Bridge art must occlude a player passing underneath.")
	assert(main.world.get_node_or_null("EastRouteUniversalObject0RailingA") != null and main.world.get_node_or_null("EastRouteUniversalObject0RailingB") != null, "Bridge railings must use permanent structure collision.")

	# The western map authors a horizontal bridge with the dedicated texture set.
	var horizontal: Dictionary = main.traversal_surfaces.filter(func(item: Dictionary) -> bool: return String(item.name).begins_with("WestRoute"))[0]
	assert(horizontal.axis == Vector3.RIGHT and horizontal.side_axis == Vector3.FORWARD, "Horizontal bridges must reuse orientation-driven traversal math.")
	assert(is_equal_approx(float(horizontal.width),1.3),"Horizontal bridges must share the same widened asset width.")
	assert(main.world.get_node_or_null("WestRouteUniversalObject0DeckTile4") != null, "Horizontal bridge end art must be generated from the dedicated textures.")
	assert((main.world.get_node("WestRouteUniversalObject0DeckTile0") as MeshInstance3D).material_override.albedo_texture.resource_path.ends_with("tile_bridge_horizontal_l.png"), "Horizontal bridges must use their horizontal start texture.")
	assert(main.world.find_child("WestRouteCanonicalBase_*_water",false,false) != null, "Horizontal bridge placement must preserve canonical water beneath it.")
	assert(main.world.get_node_or_null("CanopyRouteUniversalObject0") != null and (main.world.get_node("CanopyRouteUniversalObject0") as Sprite3D).texture.resource_path.ends_with("vines_horizontal_flower_passion.png"), "Outdoor maps must render authored horizontal passion vines.")
	print("BRIDGE_TRAVERSAL_TEST_PASSED")
	quit()
