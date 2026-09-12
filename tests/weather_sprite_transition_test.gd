extends SceneTree


func _initialize() -> void:
	var battle := (load("res://battle/battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	var renderer: Control = battle.weather_visuals

	renderer.definitions["Overlay Controls"] = {"background_overlay": {
		"asset":"res://assets/battle/weather/overlay_example.png", "opacity":0.37,
		"modulate":"#ffffff", "mirror_x":true, "mirror_y":true, "scale":0.5
	}}
	renderer.show_weather("Overlay Controls", 1)
	var overlay := renderer.visual_root.get_node("BackgroundOverlay") as TextureRect
	assert(overlay != null and is_equal_approx(overlay.modulate.a, 0.37), "Background overlay opacity must reach the renderer.")
	assert(overlay.flip_h and overlay.flip_v, "Background overlay mirror controls must reach the renderer.")
	var source_ratio := overlay.texture.get_size().x / overlay.texture.get_size().y
	assert(is_equal_approx(overlay.size.x / overlay.size.y, source_ratio), "Scaled overlays must preserve the complete source aspect ratio instead of cropping inside a reduced control.")

	var fade_config := {
		"asset_family":"sprite_example", "anchor":"FIELD_CENTER", "mode":"persistent", "turns":1,
		"fade_out_duration":0.3, "fade_out_causes":["element_not_on_turn"]
	}
	renderer.definitions["Turn Fade"] = {"sprite_effects":[fade_config]}
	renderer.show_weather("Turn Fade", 2)
	var turn_sprite := renderer.visual_root.get_node("WeatherSprite_sprite_example") as TextureRect
	renderer.update_turns(1)
	assert(turn_sprite.get_parent() == renderer.fading_root, "An ineligible turn must move a configured sprite into fade-out lifecycle.")
	await create_timer(0.05).timeout
	assert(is_instance_valid(turn_sprite) and turn_sprite.modulate.a < 1.0, "Turn fade must transition opacity smoothly.")
	await create_timer(0.3).timeout
	assert(not is_instance_valid(turn_sprite), "Turn fade must remove the sprite after its configured duration.")

	var weather_fade := fade_config.merged({"turns":"all", "fade_out_causes":["weather_ends"]}, true)
	renderer.definitions["Weather Fade"] = {"sprite_effects":[weather_fade]}
	renderer.show_weather("Weather Fade", 1)
	var weather_sprite := renderer.visual_root.get_node("WeatherSprite_sprite_example") as TextureRect
	renderer.clear_weather()
	assert(weather_sprite.get_parent() == renderer.fading_root, "Weather end must preserve a configured sprite for its fade.")
	await create_timer(0.35).timeout
	assert(not is_instance_valid(weather_sprite), "Weather-end fade must clean itself up.")

	var duration_fade := fade_config.merged({"turns":"all", "fade_out_causes":["duration"], "visible_duration":0.03}, true)
	renderer.definitions["Duration Fade"] = {"sprite_effects":[duration_fade]}
	renderer.show_weather("Duration Fade", 1)
	var duration_sprite := renderer.visual_root.get_node("WeatherSprite_sprite_example") as TextureRect
	await create_timer(0.04).timeout
	assert(duration_sprite.get_parent() == renderer.fading_root, "Visible-duration trigger must begin fading after its per-turn delay.")
	renderer.update_turns(1)
	assert(not renderer.visual_root.has_node("WeatherSprite_sprite_example"), "Refreshing a turn must not recreate a duration-expired sprite.")
	renderer.clear_weather(true)

	var scrolling_config := {
		"asset_family":"sprite_example", "sprite_mode":"scrolling", "anchor":"SCREEN_TOP",
		"scroll_direction":"left", "scroll_speed":120.0, "spacing":8.0,
		"loop":true, "transition_overlap":3.0, "opacity":0.6
	}
	renderer.definitions["Scrolling Strip"] = {"sprite_effects":[scrolling_config]}
	renderer.show_weather("Scrolling Strip", 1)
	var strip: Control = renderer.visual_root.get_node("WeatherScrolling_sprite_example") as Control
	assert(strip != null and strip.get_child_count() >= 2, "Scrolling mode must maintain enough family instances to cover the viewport.")
	var first: TextureRect = strip.get_child(1) as TextureRect
	var initial_x := first.position.x
	strip.call("_process", 0.1)
	assert(first.position.x < initial_x, "Left scrolling must continuously move strip instances left.")
	for child: TextureRect in strip.get_children(): child.position.x = -child.size.x * absf(child.scale.x) - 10.0
	strip.call("_process", 0.01)
	assert(strip.get_child_count() > 0, "Looping strips must destroy exited sprites and spawn replacements beyond the entry edge.")
	renderer.clear_weather(true)
	assert(renderer.fading_root.get_child_count() == 0, "Immediate battle teardown must remove pending fades.")
	print("WEATHER_SPRITE_TRANSITION_TEST_PASSED")
	quit()
