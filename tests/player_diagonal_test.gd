extends SceneTree

const Palette := preload("res://world/player_palette.gd")
const Frames := preload("res://world/player_sprite_frames.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := Palette._load_png(Palette.DIAGONAL_SOURCE_PATH)
	var mask := Palette._load_png(Palette.DIAGONAL_MASK_PATH)
	assert(source.get_size() == mask.get_size())
	for preset_name: String in Palette.PRESETS:
		var atlas := Palette.create_texture(preset_name, "diagonal")
		assert(atlas == Palette.create_texture(preset_name, "diagonal"))
		assert(atlas != Palette.create_texture(preset_name))
		var result := atlas.get_image()
		for y in source.get_height():
			for x in source.get_width():
				var before := source.get_pixel(x,y)
				var expected := before
				var rgb := before.to_html(false)
				var category := mask.get_pixel(x,y).to_html(false)
				if category == "ff0000" and Palette.HAIR_SOURCE_ROLES.has(rgb):
					expected = Palette.PRESETS[preset_name]["hair"][Palette.HAIR_SOURCE_ROLES[rgb]]
				elif category == "00ff00" and Palette.SKIN_SOURCE_ROLES.has(rgb):
					expected = Palette.PRESETS[preset_name]["skin"][Palette.SKIN_SOURCE_ROLES[rgb]]
				elif category == "ffffff" and rgb in ["000000","010000"]:
					expected.a = 0.0
				assert(result.get_pixel(x,y) == expected, "Diagonal palette must sample the matching source-sheet mask pixel.")
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# Lock down visually identified female neutral/stride poses; distinct
	# rectangles alone do not prove that a neutral pose was assigned correctly.
	var female_front_cycles := {
		"down_right":[Rect2i(780,13,179,270),Rect2i(835,309,153,272),Rect2i(1011,10,147,276),Rect2i(835,309,153,272)],
		"down_left":[Rect2i(1883,15,151,275),Rect2i(1686,17,161,271),Rect2i(1704,315,162,271),Rect2i(1686,17,161,271)],
	}
	main.player_gender = "Female"
	for direction: String in female_front_cycles:
		var expected: Array = female_front_cycles[direction]
		var cycle: Array = main._player_animation_frames("walk_" + direction)
		for index in 4:
			assert(cycle[index].region == Rect2(expected[index]), "Female front diagonals must alternate actual strides and standing poses.")
	for gender in ["Male","Female"]:
		main.player_gender = gender
		for direction: String in ["up_left","up_right","down_left","down_right"]:
			var cycle: Array = main._player_animation_frames("walk_" + direction)
			assert(cycle.size() == 4)
			assert(cycle[0].region != cycle[2].region)
			assert(cycle[1].region == cycle[3].region and cycle[0].region != cycle[1].region and cycle[2].region != cycle[1].region)
			for frame: AtlasTexture in cycle:
				assert(Rect2(Vector2.ZERO,source.get_size()).encloses(frame.region))
			var movement := Vector2(-1 if direction.ends_with("left") else 1, -1 if direction.begins_with("up") else 1).normalized()
			main._update_player_animation(movement,0.0)
			assert(main.player_animation == "walk_" + direction)
			main._update_player_animation(movement,0.16)
			assert(main.player_frame_index == 1 and main.player_sprite.texture.region == cycle[1].region)
			main._update_player_animation(Vector2.ZERO,0.0)
			assert(main.player_animation == "idle_" + direction)
			var visual: Sprite2D = main.player_sort_root.get_node("Visual")
			assert(visual.flip_h == (gender == "Male" and direction.ends_with("left")))
	main.queue_free()
	await process_frame
	print("PLAYER_DIAGONAL_TEST_PASSED")
	quit()
