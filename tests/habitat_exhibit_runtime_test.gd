extends SceneTree

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://world/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game._start_map_test("challenger_1_interior_jalovea_city.json")
	var exhibits = game.exhibits
	check(exhibits.slots.size() == 10, "Ten lecterns must have distinct exhibit slots.")
	var rims: Array = game.object_sort_entries.filter(func(entry): return String(entry.name).ends_with("SortRootRear"))
	check(rims.size() == 10 and rims.all(func(entry): return entry.sort_root.z_index == 0 and entry.texture.get_size() == entry.texture.atlas.get_size()), "Each rear rim must preserve sprite alignment and share the normal Y-sort layer.")
	var rear: Dictionary = rims[0]
	var rim_anchor: Vector3 = rear.placement
	var arrival: Vector3 = game.player.position
	var camera_start: Vector3 = game.camera.position
	game.player.position = rim_anchor + Vector3(0, 0.65, -5.25)
	game.camera.position = game.player.position + Vector3(0, 7, 7)
	game._update_sort_canvas()
	check(game.player_sort_root.position.y < rear.sort_root.position.y and game.player_sort_root.z_index == rear.sort_root.z_index, "A player behind the pen must sort below the rear rim.")
	game.player.position = rim_anchor + Vector3(0, 0.65, -4.5)
	game._update_sort_canvas()
	check(game.player_sort_root.position.y > rear.sort_root.position.y and game.player_sort_root.z_index == 0, "A player south of the rear rim must sort in front of it.")
	var front: Dictionary = game.object_sort_entries.filter(func(entry): return entry.name == String(rear.name).trim_suffix("Rear"))[0]
	game.player.position = rim_anchor + Vector3(0, 0.65, 0.5)
	game._update_sort_canvas()
	check(game.player_sort_root.position.y > front.sort_root.position.y and game.player_sort_root.z_index == front.sort_root.z_index, "A player south of the pen must sort in front of its front rim.")
	var lectern: Dictionary = exhibits.slots["exhibit_01"].lectern
	game.player.position = lectern.placement + Vector3(0, 0.65, -0.2)
	game.camera.position = game.player.position + Vector3(0, 7, 7)
	game._update_sort_canvas()
	check(game.player_sort_root.position.y < lectern.sort_root.position.y and game.player_sort_root.z_index == lectern.sort_root.z_index, "A player behind the lectern must sort below it.")
	game.player.position = arrival
	game.camera.position = camera_start
	var first := "exhibit_01"
	var second := "exhibit_02"
	exhibits.record({"name": "Keklid"})
	game.cloud.append(game.battle.create_fakemon(game._find_species("Phaloa"), 25))
	exhibits.record({"name": "Sylvafin"})
	for species in ["Skeeter", "Scorchick"]:
		exhibits.record({"name": species})
		var flying: Dictionary = exhibits.prepare(first, species)
		check(flying.get("npc", {}).get("movement_mode") == "flying", species + " must use existing flying NPC movement.")
	var flight: Dictionary = exhibits.prepare(first, "Scorchick")
	if exhibits.install(first, "Scorchick", flight):
		var flier: Area3D = exhibits.instances[first].npc
		var boundary: Rect2 = flier.get_meta("border_playable_bounds")
		flier.position.z = boundary.position.y + 0.24
		var art_entry: Dictionary = game.npc_sort_entries.back()
		var art: Sprite2D = art_entry.sort_root.get_node("Visual")
		game._update_sort_canvas()
		var frame: Rect2 = flier.get_meta("habitat_flight_frame")
		var north: Vector2 = game.camera.unproject_position(Vector3(frame.position.x, flier.get_meta("base_elevation"), frame.position.y))
		check(art.to_global(art.get_rect().position).y >= north.y - 0.01, "Flying artwork must remain inside the north rim.")
		check(exhibits.instances[first].nodes.any(func(node): return node.get_meta("canonical_terrain_type", "") == "forest_floor"), "Exhibits must render their forest floor base.")
		exhibits.install(first, "", {})
	else:
		check(false, "Scorchick exhibit should install.")
	var initial: Dictionary = exhibits.prepare(first, "Keklid")
	check(initial.get("habitat_type") == "rainforest", "Keklid should resolve the rainforest template: " + str(initial.get("error")))
	if not exhibits.install(first, "Keklid", initial):
		push_error("Could not install rainforest exhibit.")
		quit(1)
		return
	check(not exhibits.available(second).has("Keklid"), "An assigned species must be hidden from other slots.")
	game._open_habitat_exhibit(second)
	check(game.exhibit_menu.get_item_index(0) >= 0 and not range(game.exhibit_menu.item_count).any(func(i): return game.exhibit_menu.get_item_text(i) == "Keklid"), "The menu must omit species assigned elsewhere.")
	game.exhibit_menu.hide()
	check(not exhibits.install(second, "Keklid", initial), "Runtime assignment must reject a duplicate.")
	check(exhibits.install(second, "Phaloa", exhibits.prepare(second, "Phaloa")), "An evolved species in the Cloud should be eligible independently.")
	var unrelated: Node = exhibits.instances[second].npc
	var previous: Node = exhibits.instances[first].npc
	var fresh: Dictionary = exhibits.prepare(first, "Sylvafin")
	check(fresh.get("npc", {}).get("movement_mode") == "swimming", "Sylvafin must use existing swimming NPC movement.")
	check(fresh.get("habitat_type") == "freshwater", "Sylvafin should resolve freshwater.")
	check(exhibits.install(first, "Sylvafin", fresh), "Replacement failed.")
	var outline: PackedVector2Array = fresh._habitat_floor_clip
	var terrain_count := 0
	for node in exhibits.instances[first].nodes:
		if not node is MeshInstance3D or not (node.has_meta("canonical_terrain_type") or node.has_meta("terrain_transition")):
			continue
		terrain_count += 1
		for surface in node.mesh.get_surface_count():
			for vertex: Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point := Vector2(vertex.x, vertex.z).move_toward(Vector2.ZERO, 0.001)
				check(Geometry2D.is_point_in_polygon(point, outline), "Exhibit terrain must stay inside the pen outline.")
	check(terrain_count > 0, "The freshwater exhibit must render clipped terrain.")
	var north_tint := false
	var water_surface: Dictionary = game.npc_water_surfaces[exhibits.instances[first].key]
	for patch in water_surface.node.get_children():
		for point: Vector2 in patch.get_meta("region_polygon"):
			north_tint = north_tint or point.y < -1.8
			check(absf(point.x) <= 2.021, "Water tint must stay off the side rails.")
	check(north_tint, "The water tint must reach the lower rear wall.")
	check(previous.get_parent() == null and exhibits.instances[second].npc == unrelated, "Replacement must detach the old NPC and preserve neighbors.")
	var count: int = game.world.get_child_count()
	var dialogue_count: int = game.npc_dialogues.size()
	var motion_count: int = game.npc_movement_states.size()
	var sort_count: int = game.npc_sort_entries.size()
	for repeat in 3:
		check(exhibits.install(first, "Sylvafin", exhibits.prepare(first, "Sylvafin")), "Repeated replacement failed.")
		check(game.world.get_child_count() == count, "Replacement accumulated world nodes.")
		check(game.npc_dialogues.size() == dialogue_count and game.npc_movement_states.size() == motion_count and game.npc_sort_entries.size() == sort_count, "Replacement accumulated NPC records.")
	check(exhibits.prepare(first, "Not a species").has("error"), "Unknown species must be rejected.")
	var definition: Dictionary = game._find_species("Keklid")
	var original_type: String = definition.habitat
	definition.habitat = "missing_habitat"
	check(exhibits.prepare(first, "Keklid").has("error"), "A missing template must preserve a working exhibit.")
	var fallback: Dictionary = exhibits.prepare("exhibit_03", "Keklid")
	check(fallback.has("npc") and not fallback.has("habitat_type"), "An empty exhibit should accept a species without a template.")
	definition.habitat = original_type
	var art_id: String = game.npc_visual_resolver.species["Keklid"]
	game.npc_visual_resolver.species.erase("Keklid")
	check(exhibits.prepare(first, "Keklid").has("error") and exhibits.assignments[first] == "Sylvafin", "Missing art must preserve an existing exhibit.")
	game.npc_visual_resolver.species["Keklid"] = art_id
	var save_path := "res://habitat-exhibit-test-save.tmp"
	check(game._write_save(save_path, false, ""), "Existing save writer should save the exhibit.")
	var save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var saved: Dictionary = save.habitat_exhibits
	check(game._restore_save(save_path), "Existing save loader should load the exhibit.")
	DirAccess.remove_absolute(save_path)
	check(exhibits.assignments == saved, "Saved slots should reconstruct.")
	var npc: Area3D = exhibits.instances[first].npc
	var location: String = game._current_location()
	game._apply_loaded_location("city")
	game._apply_loaded_location(location)
	check(exhibits.instances[first].npc == npc, "Leaving and re-entering should preserve the exhibit.")
	await physics_frame
	var bounds: Rect2 = npc.get_meta("wander_bounds")
	var start := npc.position
	var moved := false
	for tick in 90:
		game._update_placed_npcs(0.1)
		moved = moved or not start.is_equal_approx(npc.position)
		check(bounds.has_point(Vector2(npc.position.x, npc.position.z)), "NPC wandered outside its exhibit.")
	check(moved, "The exhibit NPC should actually wander.")
	check(exhibits.install(first, "", {}), "Clear should succeed.")
	check(not exhibits.assignments.has(first) and not exhibits.instances.has(first), "Clearing should remove the assignment and generated content.")
	check(exhibits.install(first, "Keklid", exhibits.prepare(first, "Keklid")), "A cleared exhibit should accept another species.")
	if not failed:
		print("Habitat exhibit runtime passed.")
	quit(1 if failed else 0)
