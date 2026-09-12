extends SceneTree

const WEATHER_RENDERER_SCRIPT := preload("res://battle/weather_visual_renderer.gd")


func _initialize() -> void:
	var scene := load("res://battle/battle.tscn") as PackedScene
	assert(scene != null, "Battle scene must load with weather visuals.")
	var battle := scene.instantiate()
	root.add_child(battle)
	await process_frame
	var renderer: Control = battle.weather_visuals
	assert(renderer != null and renderer.definitions.size() >= 5, "Weather visual definitions must load.")

	renderer.show_weather("Rootmind", 3)
	await process_frame
	assert(renderer.current_weather == "Rootmind", "Weather must start when no prior visual exists.")
	assert(renderer.visual_root.get_child_count() > 0 and renderer.badge.visible, "Weather must create visuals and a HUD badge.")
	var network := renderer.visual_root.get_node_or_null("WeatherSprite_rootmind_fungal_network") as TextureRect
	assert(network != null and network.has_meta("thought_id") and String(network.get_meta("thought_id")) == "A", "Rootmind must register persistent mycelial nodes for authored thought sequences.")
	var animated_orchid: TextureRect = null
	for child: Node in renderer.visual_root.get_children():
		if child.name == "WeatherSprite_rootmind_orchid1":
			animated_orchid = child as TextureRect
			break
	assert(animated_orchid != null and animated_orchid.has_node("FrameAnimation"), "Rootmind orchids must open and close as animated upper-field blooms.")
	assert(is_instance_valid(renderer._thought_timer), "Rootmind must schedule quiet, authored cognition events.")
	var rootmind_emitter: Control = renderer._particle_emitters.get(0) as Control
	assert(rootmind_emitter != null and (rootmind_emitter.get("live_particles") as Array).is_empty(), "Rootmind spores must remain quiet until a thought sequence releases them.")
	renderer._emit_thought_particles({"particle_effect":0, "particle_count":4})
	assert((rootmind_emitter.get("live_particles") as Array).size() == 4, "A thought sequence must be able to release a local spore burst.")
	var persistent_count: int = renderer.visual_root.get_child_count()
	renderer.show_weather("Rootmind", 2)
	assert(renderer.visual_root.get_child_count() == persistent_count, "Reactivating the same weather must not duplicate persistent visuals.")
	assert(renderer.badge.text.contains("2"), "The badge must update remaining turns.")

	renderer.show_weather("Blood Moon", 3)
	await process_frame
	assert(renderer.current_weather == "Blood Moon", "A weather may directly replace another weather.")
	assert(renderer.resolve_sprite_variants("sprite_example").size() == 4, "Indexed sprite families must resolve every available variant.")
	assert(renderer.resolve_sprite_variants("missing_family").is_empty(), "Missing sprite families must fail gracefully.")
	assert(WeatherVisualRenderer.is_element_active_on_turn({}, 1) == false)
	assert(WeatherVisualRenderer.is_element_active_on_turn({"type":"pulse"}, 2), "Omitted turns must mean all.")
	assert(WeatherVisualRenderer.is_element_active_on_turn({"turns":"all"}, 3), "Explicit all must match omitted turns.")
	assert(WeatherVisualRenderer.is_element_active_on_turn({"turns":2}, 2) and not WeatherVisualRenderer.is_element_active_on_turn({"turns":2}, 1), "Single-turn eligibility must be exact.")
	assert(WeatherVisualRenderer.is_element_active_on_turn({"turns":[1,3]}, 1) and not WeatherVisualRenderer.is_element_active_on_turn({"turns":[1,3]}, 2) and WeatherVisualRenderer.is_element_active_on_turn({"turns":[1,3]}, 3), "Turn-list eligibility must be exact.")
	assert(not WeatherVisualRenderer.is_element_active_on_turn({"turns":[0,"bad"]}, 1), "Malformed turn data must fail gracefully.")
	renderer.definitions["Turn Test"] = {
		"lighting_effects":[{"type":"wash","turns":[1,3]}],
		"sprite_effects":[{"asset_family":"sprite_example","mode":"persistent","scale":1.5,"turns":1}],
		"turn_effects":[{"type":"pulse","turns":2,"duration":0.1}]
	}
	renderer.show_weather("Turn Test", 3); await process_frame
	assert(renderer.visual_root.get_child_count()==2, "Persistent turn-1 elements must appear.")
	var scaled_sprite := renderer.visual_root.get_node("WeatherSprite_sprite_example") as TextureRect
	assert(scaled_sprite != null and scaled_sprite.scale.is_equal_approx(Vector2(1.5,1.5)), "Weather sprite scale must reach runtime rendering.")
	renderer.update_turns(2); await process_frame
	assert(renderer.visual_root.get_child_count()==0, "Persistent elements must leave on an inactive turn.")
	var spawned_before: int = renderer.spawned_root.get_child_count();renderer.pulse_turn();assert(renderer.spawned_root.get_child_count()==spawned_before+1,"Matching pulse must trigger.")
	renderer.update_turns(1); await process_frame
	assert(renderer.visual_root.get_child_count()==1,"Persistent elements must return on a later active turn.")
	spawned_before=renderer.spawned_root.get_child_count();renderer.pulse_turn();assert(renderer.spawned_root.get_child_count()==spawned_before,"Non-matching pulse must not trigger.")
	renderer.show_weather("Unknown Weather", 1)
	assert(renderer.current_weather == "Unknown Weather" and renderer.badge.visible, "A missing optional definition must preserve battle flow and its badge.")
	renderer.clear_weather()
	await process_frame
	assert(renderer.current_weather.is_empty() and not renderer.badge.visible, "Weather expiry must clear its GUI.")
	assert(renderer.visual_root.get_child_count() == 0, "Clearing weather must not leak persistent nodes.")

	# Canonical extension schema: offsets, modulation, looping, and procedural primitives.
	renderer.definitions["Graphics Extension"] = {
		"lighting_effects": [
			{"type":"orb", "anchor":"FIELD_CENTER", "x_offset":17, "y_offset":-9, "size":80, "opacity":0.4, "flicker_enabled":true, "flicker_min_alpha":0.1, "flicker_max_alpha":0.4, "flicker_interval":0.05, "turns":1},
			{"type":"beam", "start_anchor":"SCREEN_TOP", "end_anchor":"ENEMY_FIELD", "start_x_offset":11, "end_y_offset":13, "start_width":24, "end_width":96, "edge_softness":0.8, "turns":1},
			{"type":"heat_shimmer", "anchor":"ALLY_FIELD", "x_offset":3, "y_offset":4, "width":140, "height":55, "strength":0.005, "speed":1.2, "turns":1},
			{"type":"particles", "anchor":"FIELD_CENTER", "x_offset":5, "y_offset":6, "width":160, "height":70, "count":7, "size":2, "turns":1}
		],
		"sprite_effects": [{"asset_family":"sprite_example", "anchor":"FIELD_CENTER", "x_offset":19, "y_offset":-7, "mode":"persistent", "turns":1}],
		"turn_effects": [{"type":"pulse", "opacity":0.1, "duration":0.05, "loop":true, "interval":0.08, "turns":1}]
	}
	renderer.show_weather("Graphics Extension", 2)
	await process_frame
	var expected_orb_center: Vector2 = renderer.resolve_anchor_point("FIELD_CENTER") + Vector2(17, -9)
	var orb: Control = renderer.visual_root.get_node("Lighting_orb") as Control
	assert((orb.position + orb.size * 0.5).is_equal_approx(expected_orb_center), "Orb offsets must apply after anchor resolution.")
	assert(orb.get_class() != "ColorRect" and is_equal_approx(orb.rotation, 0.0), "The radial orb must use procedural circular falloff without a rotated square boundary.")
	var beam: Control = renderer.visual_root.get_node("Lighting_beam_0") as Control
	assert(beam.get("start_width") == 24.0 and beam.get("end_width") == 96.0, "Beam geometry must preserve independent taper widths.")
	assert(beam.position.is_equal_approx(renderer.resolve_anchor_point("SCREEN_TOP") + Vector2(11, 0)), "Beam start offsets must resolve from the start anchor.")
	assert((beam.position + (beam.get("beam_end") as Vector2)).is_equal_approx(renderer.resolve_anchor_point("ENEMY_FIELD") + Vector2(0, 13)), "Beam end offsets must resolve from the end anchor.")
	var shimmer := renderer.visual_root.get_node("Lighting_heat_shimmer") as ColorRect
	assert(shimmer != null and shimmer.size == Vector2(140, 55) and shimmer.material is ShaderMaterial, "Heat shimmer must be a localized shader region.")
	var particles: Control = renderer.visual_root.get_node("Lighting_particles") as Control
	assert(particles.size == Vector2(160, 70) and (particles.get("_particles") as Array).size() == 7, "Procedural particles must remain inside their configured spawn region.")
	var offset_sprite := renderer.visual_root.get_node("WeatherSprite_sprite_example") as TextureRect
	var unoffset_sprite_position: Vector2 = renderer._anchor_position("FIELD_CENTER", offset_sprite.texture.get_size())
	assert(offset_sprite.position.is_equal_approx(unoffset_sprite_position + Vector2(19, -7)), "Sprite offsets must apply after anchor resolution.")
	assert(renderer._pulse_timers.size() == 1, "An eligible looping pulse must own exactly one timer.")
	var loop_timer: Timer = renderer._pulse_timers[0] as Timer
	renderer.update_turns(2)
	assert(renderer._pulse_timers.size() == 1 and renderer._pulse_timers[0] == loop_timer, "Refreshing the same turn must not duplicate or restart its loop timer.")
	renderer.update_turns(1)
	await process_frame
	assert(renderer._pulse_timers.is_empty(), "A looping pulse must stop as soon as its eligible turn changes.")
	assert(renderer.visual_root.get_child_count() == 0, "All new persistent primitives must respect per-element turns.")
	renderer.show_weather("Blood Moon", 2)
	await process_frame
	assert(not is_instance_valid(loop_timer), "Weather replacement must dispose the prior pulse timer.")
	renderer.show_weather("Graphics Extension", 2)
	await process_frame
	var flickering_orb: Control = renderer.visual_root.get_node("Lighting_orb") as Control
	await create_timer(0.06).timeout
	assert(flickering_orb.modulate.a < 0.99, "Enabled light flicker must modulate alpha over time.")
	renderer.clear_weather()
	await process_frame
	assert(not is_instance_valid(flickering_orb) and renderer._pulse_timers.is_empty(), "Weather cleanup must stop flicker and remove every new runtime node.")

	battle._set_weather("Harsh Sunlight")
	await process_frame
	assert(battle.weather_visuals.visual_root.has_node("Lighting_heat_shimmer") and battle.weather_visuals.visual_root.has_node("Lighting_particles"), "Harsh Sunlight must use the extended runtime schema.")
	assert(renderer.current_weather == "Harsh Sunlight", "Battle weather changes must reach the renderer.")
	battle._end_battle("Test complete")
	assert(renderer.current_weather.is_empty(), "Battle end must clear active weather visuals.")
	assert(renderer.visual_root.get_child_count() == 0 and renderer.spawned_root.get_child_count() == 0, "Battle end must remove all weather runtime nodes.")
	print("WEATHER_VISUALS_TEST_PASSED")
	quit()
