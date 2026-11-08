extends SceneTree

func _initialize() -> void:
	var game = load("res://world/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.adventure_started = false
	for filename in ["jalovea_city_house_standard.json", "tropical_research_institute_indoor.json"]:
		var data: Dictionary = game.map_data._map_files[filename]
		var location: String = game._location_for_map_file(filename)
		game._complete_editor_authored_warp({"entrance_map":filename,"entrance_map_warp_id":1})
		assert(game._current_location() == location)
		assert(game.player.position.is_equal_approx(game._array_to_vector3(data.origin) + game._array_to_vector3(data.return_warp)))
		game.player.position = Vector3.ZERO
		game._apply_loaded_location(location)
		assert(game.player.position.is_equal_approx(game._array_to_vector3(data.origin) + game._array_to_vector3(data.entry)), "A save at the old origin must recover at the relocated room entry.")
		game._complete_editor_authored_warp(data.warp_metadata.return_warp)
		assert(game._current_location() == game._location_for_map_file(data.warp_metadata.return_warp.entrance_map))
	var city: Dictionary = game.map_data._map_files["jalovea_city.json"]
	for number in [1, 2]:
		var field := "warp_%d" % (number + 3)
		var key := "jalovea_city_house_standard.json#house_%d" % number
		var instance: Dictionary = game.map_data._map_files[key]
		game._complete_editor_authored_warp(city.warp_metadata[field])
		assert(game._current_location() == game._location_for_map_file(key), "City entrance must open its named instance.")
		assert(game.runtime_npcs[key].size() == (1 if number == 1 else 0), "Only house_1 may contain NPC1.")
		var layer: int = game._active_visual_layer()
		var rugs: Array = game.world.find_children("WarpRugArt", "MeshInstance3D", true, false)
		assert(rugs.any(func(rug): return int(rug.get_meta("visual_layer", 0)) == layer), "Each interior instance needs a visible entrance rug.")
		game._complete_editor_authored_warp(instance.warp_metadata.return_warp)
		assert(game._current_location() == game._location_for_map_file("jalovea_city.json"))
		assert(game.player.position.is_equal_approx(game._array_to_vector3(city.origin) + game._array_to_vector3(city[field])), "Each exit must return to the house it belongs to.")
	assert(game.runtime_npcs["jalovea_city_house_standard.json"].is_empty(), "The base layout must not duplicate NPC1.")
	print("MAP_NAVIGATION_RUNTIME_TESTS_PASSED")
	game.queue_free()
	quit()
