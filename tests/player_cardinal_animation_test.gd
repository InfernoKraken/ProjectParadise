extends SceneTree

const Frames := preload("res://world/player_sprite_frames.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_physics_process(false)
	var directions := {
		"down": Vector2.DOWN, "up": Vector2.UP,
		"left": Vector2.LEFT, "right": Vector2.RIGHT,
	}
	for gender: String in ["Male", "Female"]:
		main.player_gender = gender
		main._apply_player_appearance()
		for direction: String in directions:
			var strides := Frames.frames(gender, "walk_" + direction, main.player_atlas)
			var neutral := Frames.frames(gender, "idle_" + direction, main.player_atlas)[0]
			var expected := [strides[0].region, neutral.region, strides[1].region, neutral.region]
			main._update_player_animation(Vector2.ZERO, 0.0)
			main._update_player_animation(directions[direction], 0.0)
			# Exercise playback, not just the assembled list: both rendered nodes
			# must show both neutral beats over repeated complete walk cycles.
			for beat in 12:
				var visual: Sprite2D = main.player_sort_root.get_node("Visual")
				assert(main.player_frame_index == beat % 4)
				assert(main.player_sprite.texture.region == expected[beat % 4])
				assert(visual.texture.region == expected[beat % 4])
				assert(visual.flip_h == (gender == "Male" and direction == "left"))
				for tick in 10:
					main._update_player_animation(directions[direction], 1.0 / 60.0)
			main._update_player_animation(Vector2.ZERO, 0.0)
			assert(main.player_sprite.texture.region == neutral.region)
	main.queue_free()
	await process_frame
	print("PLAYER_CARDINAL_ANIMATION_TEST_PASSED: both genders, all four directions, three full cycles each")
	quit()
