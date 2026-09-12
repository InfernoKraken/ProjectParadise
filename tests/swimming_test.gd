extends SceneTree


func _initialize() -> void:
	var scene := load("res://world/main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	assert(main.bag_panel.find_child("SwimgearButton", true, false) is Button, "The Bag must contain Swimgear.")
	var swim_palette: Texture2D = main.PlayerPalette.create_texture("medium", "swim")
	var dive_palette: Texture2D = main.PlayerPalette.create_texture("medium", "dive")
	assert(swim_palette != null and dive_palette != null, "The swimming and diving sheets must produce runtime palette textures.")
	var swim_source := Image.new()
	var dive_source := Image.new()
	var dive_mask := Image.new()
	assert(swim_source.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/trainers/Player_Swimming Sprites.png")) == OK and dive_source.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/trainers/Diving In Sprite.png")) == OK)
	assert(dive_mask.load_png_from_buffer(FileAccess.get_file_as_bytes(main.PlayerPalette.DIVE_MASK_PATH)) == OK, "The authored diving sprite mask must remain available as the dive palette source of truth.")
	assert(dive_source.get_size() == dive_mask.get_size(), "The authored diving sprite and mask must remain pixel-aligned.")
	var male_swim_regions: Dictionary = main.SwimSpriteFrames.SWIM_REGIONS["Male"]
	assert((male_swim_regions["down"][0] as Rect2i).end.y <= (male_swim_regions["up"][0] as Rect2i).position.y, "Swimming frames must not crop pixels from the adjacent direction row.")
	assert((main.SwimSpriteFrames.DIVE_REGIONS["Male"]["down"][0] as Rect2i).size.y == 235, "Male dive frames must retain the full authored actor height.")
	assert(main.SWIM_VISUAL_HEIGHT < main.PLAYER_VISUAL_HEIGHT * 0.5, "The wide swimming wake must render at a waterline-relative scale rather than full actor height.")
	assert(swim_palette.get_image().get_pixel(337, 5) != swim_source.get_pixel(337, 5), "The swimming mask must recolor authored hair pixels.")
	assert(dive_palette.get_image().get_pixel(143, 106) != dive_source.get_pixel(143, 106), "The corrected diving mask must recolor authored hair pixels.")
	assert(dive_palette.get_image().get_pixel(0, 0).a == 0.0, "The diving sheet's green chroma background must remain transparent.")

	main.adventure_started = true
	main.player_gender = "Male"
	main.player_palette_preset = "medium"
	main.inside_route = true
	var grid: Dictionary = main.map_data["route"]["_terrain_grid"]
	var water_cell := Vector2i.ZERO
	var land_cell := Vector2i.ZERO
	var land_to_water := Vector2i.ZERO
	for value: Variant in grid.keys():
		var cell := value as Vector2i
		if String(grid[cell]) != "water":
			continue
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var outward := Vector3(offset.x, 0.0, offset.y)
			var first_land: Vector3 = main.route_origin + Vector3(cell.x + offset.x, 0.65, cell.y + offset.y)
			if grid.has(cell + offset) and String(grid[cell + offset]) != "water" and main._safe_shore_exit(first_land, outward) != Vector3.ZERO:
				water_cell = cell
				land_cell = cell + offset
				land_to_water = -offset
				break
		if land_to_water != Vector2i.ZERO:
			break
	assert(land_to_water != Vector2i.ZERO, "The route fixture needs an accessible water edge.")
	main.player.position = main.route_origin + Vector3(land_cell.x, 0.65, land_cell.y)
	main.player_animation = "idle_" + _direction_name(-land_to_water)
	var dry_position: Vector3 = main.player.position
	main._use_swimgear()
	assert(not main.swimming and not main.swim_transitioning and main.player.position == dry_position, "Swimgear must do nothing when the player is not facing nearby water.")
	main.player_animation = "idle_" + _direction_name(land_to_water)
	await main._start_swimming(main.route_origin + Vector3(water_cell.x, 0.65, water_cell.y), _direction_name(land_to_water))
	assert(main.swimming and main.player.position.is_equal_approx(main.route_origin + Vector3(water_cell.x, 0.65, water_cell.y)), "Using Swimgear beside faced water must enter that water cell.")
	assert(not main.follower.visible, "The follower must remain on shore while the player swims.")

	var water_to_land := -land_to_water
	main._swim_constrained_velocity(Vector3(water_to_land.x, 0.0, water_to_land.y) * main.MOVE_SPEED, 0.21)
	assert(not main.swimming and main._terrain_at(main.player.position) != "water" and not main._terrain_foot_blocked(main.player.position), "Swimming onto shore must restore walking on a collision-safe land cell.")

	var north_water := Vector2i.ZERO
	for value: Variant in grid.keys():
		var cell := value as Vector2i
		var north_land: Vector3 = main.route_origin + Vector3(cell.x, 0.65, cell.y - 1)
		if String(grid[cell]) == "water" and grid.has(cell + Vector2i.UP) and String(grid[cell + Vector2i.UP]) != "water" and main._safe_shore_exit(north_land, Vector3.FORWARD) != Vector3.ZERO:
			north_water = cell
			break
	assert(north_water != Vector2i.ZERO, "The route fixture needs a north-facing shore exit.")
	main.swimming = true
	main.player.position = main.route_origin + Vector3(north_water.x, 0.65, north_water.y)
	main._swim_constrained_velocity(Vector3.FORWARD * main.MOVE_SPEED, 0.21)
	assert(not main.swimming and main._terrain_at(main.player.position) != "water" and not main._terrain_foot_blocked(main.player.position), "A north-facing exit must place the player beyond the shoreline apron before restoring walking.")
	main.queue_free()
	quit()


func _direction_name(direction: Vector2i) -> String:
	if direction == Vector2i.LEFT:
		return "left"
	if direction == Vector2i.RIGHT:
		return "right"
	if direction == Vector2i.UP:
		return "up"
	return "down"
