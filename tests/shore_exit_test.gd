extends SceneTree


func _initialize() -> void:
	var main := (load("res://world/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.adventure_started = false
	main.inside_route = true
	var grid: Dictionary = main.map_data["route"]["_terrain_grid"]
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var found := false
		for value: Variant in grid.keys():
			var water := value as Vector2i
			var land: Vector2i = water + offset
			if String(grid[water]) != "water" or not grid.has(land) or String(grid[land]) == "water":
				continue
			main.player.position = main.route_origin + Vector3(water.x, 0.65, water.y)
			main.swimming = true
			var outward := Vector3(offset.x, 0.0, offset.y)
			main._swim_constrained_velocity(outward * main.MOVE_SPEED, 0.21)
			if not main.swimming:
				assert(main._terrain_at(main.player.position) != "water" and not main._terrain_foot_blocked(main.player.position), "Shore exit must restore walking on clear land for %s." % offset)
				found = true
				break
		assert(found, "A collision-safe shore exit must exist for fixture direction %s." % offset)
	main.queue_free()
	quit()
