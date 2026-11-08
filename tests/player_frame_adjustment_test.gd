extends SceneTree

# Run with --headless --script tests/player_frame_adjustment_test.gd.
# Also writes a before/after contact sheet for the male side-facing cycle.
func _initialize() -> void:
	var main := (load("res://world/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.set_physics_process(false)
	main.player_gender = "Male"
	main._apply_player_appearance()
	var visual: Sprite2D = main.player_sort_root.get_node("Visual")
	var pixels_per_unit: float = main.get_viewport().get_visible_rect().size.y / main.camera.size
	var preview := Image.create(720, 460, false, Image.FORMAT_RGBA8)
	preview.fill(Color("24323c"))
	for direction: String in ["right", "left"]:
		main.player_animation = "walk_" + direction
		var frames: Array = main._player_animation_frames(main.player_animation)
		for phase in 4:
			main.player_frame_index = phase
			visual.texture = frames[phase]
			visual.flip_h = direction == "left"
			main._update_sort_canvas()
			var first_scale := visual.scale
			var first_position := visual.position
			main._update_sort_canvas()
			assert(visual.scale.is_equal_approx(first_scale) and visual.position.is_equal_approx(first_position), "Frame corrections must not accumulate between projections.")
			var adjustment: Dictionary = main.PlayerSpriteFrames.frame_adjustment("Male", main.player_animation, phase)
			var contact: Vector2 = main.camera.unproject_position(Vector3(main.player.position.x, 0.0, main.player.position.z))
			var bottom: float = main.player_sort_root.position.y + visual.position.y + visual.texture.get_height() * visual.scale.y * 0.5
			assert(is_equal_approx(bottom, contact.y), "Frame scaling must preserve foot contact.")
			var right: Dictionary = main.PlayerSpriteFrames.frame_adjustment("Male", "walk_right", phase)
			assert(adjustment.scale == right.scale, "Mirrored strides must retain the same size.")
			assert(is_equal_approx(adjustment.offset.x, right.offset.x * (-1.0 if direction == "left" else 1.0)), "Left-facing offsets must mirror with the artwork.")
			if phase % 2 == 1:
				assert(adjustment.scale == Vector2.ONE and adjustment.offset == Vector2.ZERO, "Neutral phases must use their own calibration.")
			if direction == "right":
				var source: Image = frames[phase].atlas.get_image().get_region(frames[phase].region)
				for row in 2:
					var crop := source.duplicate() as Image
					var scale_factor: Vector2 = adjustment.scale if row == 1 else Vector2.ONE
					var offset: Vector2 = adjustment.offset if row == 1 else Vector2.ZERO
					var size := Vector2(source.get_width(), source.get_height()) * (180.0 / source.get_height()) * scale_factor
					crop.resize(roundi(size.x), roundi(size.y), Image.INTERPOLATE_NEAREST)
					var bottom_y := 210 + row * 230
					preview.blend_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(roundi(90 + phase * 180 - size.x * 0.5 + offset.x * 180), roundi(bottom_y - size.y + offset.y * 180)))
					preview.fill_rect(Rect2i(phase * 180, bottom_y + 1, 180, 1), Color("6b8992"))
	for animation: String in ["idle_right", "walk_down", "walk_up_right"]:
		assert(main.PlayerSpriteFrames.frame_adjustment("Male", animation, 0).scale == Vector2.ONE, "Uncalibrated poses must retain their normal size.")
	assert(main.PlayerSpriteFrames.frame_adjustment("Female", "walk_right", 0).scale == Vector2.ONE)
	# Returning to swimming must discard land-frame corrections.
	main.swimming = true
	main.swim_atlas = main.PlayerPalette.create_texture("medium", "swim")
	main._update_swim_animation(Vector2.ZERO, 0.0)
	main._update_sort_canvas()
	assert(is_equal_approx(visual.scale.y * visual.texture.get_height(), main.SWIM_VISUAL_HEIGHT * pixels_per_unit))
	assert(preview.save_png("res://.godot/player_walk_calibration.png") == OK)
	print("PLAYER_FRAME_ADJUSTMENT_TEST_PASSED")
	main.queue_free()
	quit()
