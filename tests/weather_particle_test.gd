extends SceneTree


func _initialize() -> void:
	var scene := load("res://battle/battle.tscn") as PackedScene
	assert(scene != null, "Battle scene must load for particle testing.")
	var battle := scene.instantiate()
	root.add_child(battle)
	await process_frame
	var renderer: Control = battle.weather_visuals
	var original_definitions := JSON.stringify(renderer.definitions)
	assert(renderer.resolve_sprite_variants("particle_example").size() == 3, "Particle sprites must use indexed weather asset-family resolution.")
	assert(renderer.is_element_active_on_turn({"type":"particle"}, 2), "Omitted particle turns must mean all turns.")

	var particle_config := {
		"type":"particle", "turns":1, "particle_sprite":"particle_example",
		"emit_rate":100.0, "emit_max_count":2, "particle_lifetime":0.08,
		"emitter_mode":"anchored", "emitter_anchor":"FIELD_CENTER",
		"emitter_offset_x":13.0, "emitter_offset_y":-6.0,
		"emitter_width":120.0, "emitter_height":40.0,
		"movement_mode":"fall", "speed":90.0, "horizontal_drift":7.0,
		"scale_min":0.6, "scale_max":1.4, "opacity_min":0.25, "opacity_max":0.75,
		"rotation_mode":"random", "rotation":0.0, "rotation_speed":30.0
	}
	renderer.definitions["Particle Test"] = {"particle_effects":[particle_config]}
	renderer.show_weather("Particle Test", 2)
	await process_frame
	assert(renderer._particle_emitters.size() == 1, "An active particle element must create one emitter.")
	var emitter: Control = renderer._particle_emitters[0] as Control
	var expected_origin: Vector2 = renderer._anchor_position("FIELD_CENTER", Vector2(120, 40)) + Vector2(13, -6)
	var region: Rect2 = emitter.get("region") as Rect2
	assert(region.position.is_equal_approx(expected_origin), "Emitter anchors and offsets must resolve before spawning.")
	assert(region.size == Vector2(120, 40), "Emitter width and height must define its spawn region.")
	renderer.show_weather("Particle Test", 2)
	assert(renderer._particle_emitters.size() == 1 and renderer._particle_emitters[0] == emitter, "Repeated activation must not duplicate emitters.")

	await create_timer(0.04).timeout
	var live: Array = emitter.get("live_particles") as Array
	assert(emitter.get("total_emitted") >= 2, "emit_rate must repeatedly create particles.")
	assert(live.size() <= 2, "emit_max_count must cap simultaneously living particles.")
	for entry: Dictionary in live:
		var particle: TextureRect = entry["node"] as TextureRect
		assert(region.has_point(particle.position), "Emitter width and height must bound initial spawn positions.")
		assert(particle.scale.x >= 0.6 and particle.scale.x <= 1.4, "Random scale must remain within configured bounds.")
		assert(particle.modulate.a >= 0.25 and particle.modulate.a <= 0.75, "Random opacity must remain within configured bounds.")

	assert((emitter.call("resolve_velocity", {"movement_mode":"fall", "speed":10, "horizontal_drift":2}) as Vector2) == Vector2(2, 10), "Fall movement must travel downward with horizontal drift.")
	assert((emitter.call("resolve_velocity", {"movement_mode":"rise", "speed":10, "horizontal_drift":2}) as Vector2) == Vector2(2, -10), "Rise movement must travel upward with horizontal drift.")
	assert((emitter.call("resolve_velocity", {"movement_mode":"right", "speed":10}) as Vector2) == Vector2(10, 0), "Right movement must travel rightward.")
	assert((emitter.call("resolve_velocity", {"movement_mode":"left", "speed":10}) as Vector2) == Vector2(-10, 0), "Left movement must travel leftward.")

	renderer.update_turns(1)
	assert(not bool(emitter.get("emitting")), "Turn filtering must stop new emission immediately.")
	var emitted_when_stopped := int(emitter.get("total_emitted"))
	await create_timer(0.12).timeout
	assert(int(emitter.get("total_emitted")) == emitted_when_stopped, "Inactive emitters must not create particles.")
	assert((emitter.get("live_particles") as Array).is_empty(), "Stopped particles must finish their configured lifetime.")

	var screen_config: Dictionary = particle_config.merged({"turns":"all", "emitter_mode":"screen", "movement_mode":"fall", "particle_lifetime":10.0, "emit_rate":0.0, "emit_max_count":10}, true)
	renderer.definitions["Screen Particle Test"] = {"particle_effects":[screen_config]}
	renderer.show_weather("Screen Particle Test", 1)
	await process_frame
	var old_emitter: Control = renderer._particle_emitters[0] as Control
	assert(old_emitter.get("emitter_mode") == "screen", "Screen must be the canonical viewport-wide emitter mode.")
	var screen_particle: TextureRect = old_emitter.call("spawn_particle") as TextureRect
	assert(screen_particle.position.y == 0.0 and screen_particle.position.x >= 0.0 and screen_particle.position.x <= renderer.size.x, "Falling screen particles must spawn across the viewport top edge.")
	old_emitter.set("config", screen_config.merged({"movement_mode":"rise"}, true))
	var rising_particle: TextureRect = old_emitter.call("spawn_particle") as TextureRect
	assert(rising_particle.position.y == renderer.size.y, "Rising screen particles must spawn across the viewport bottom edge.")
	old_emitter.set("config", screen_config.merged({"movement_mode":"right"}, true))
	var right_particle: TextureRect = old_emitter.call("spawn_particle") as TextureRect
	assert(right_particle.position.x == 0.0 and right_particle.position.y >= 0.0 and right_particle.position.y <= renderer.size.y, "Right-moving screen particles must spawn across the viewport left edge.")
	old_emitter.set("config", screen_config.merged({"movement_mode":"left"}, true))
	var left_particle: TextureRect = old_emitter.call("spawn_particle") as TextureRect
	assert(left_particle.position.x == renderer.size.x, "Left-moving screen particles must spawn across the viewport right edge.")
	left_particle.position = Vector2(renderer.size.x + 40.0, renderer.size.y * 0.5)
	old_emitter.call("_process", 0.001)
	assert(not is_instance_valid(left_particle), "Particles must be removed after crossing the viewport margin.")
	assert(old_emitter.call("resolve_emitter_mode", {"emitter_space":"global"}) == "screen", "Legacy global emitters must safely alias to screen mode.")
	assert(old_emitter.call("resolve_emitter_mode", {"emitter_space":"position"}) == "anchored", "Legacy position emitters must safely alias to anchored mode.")
	renderer.show_weather("Blood Moon", 2)
	assert(not is_instance_valid(old_emitter) and renderer._particle_emitters.is_empty(), "Weather replacement must remove old particle state.")

	var flicker_config: Dictionary = particle_config.merged({
		"turns":"all", "emit_rate":0.0, "emit_max_count":4, "particle_lifetime":10.0,
		"speed":0.0, "opacity_min":1.0, "opacity_max":1.0,
		"flicker_enabled":true, "flicker_min_alpha":0.2, "flicker_max_alpha":0.8,
		"flicker_interval":0.5, "flicker_type":"all"
	}, true)
	renderer.definitions["Particle Flicker"] = {"particle_effects":[flicker_config]}
	renderer.show_weather("Particle Flicker", 1)
	var flicker_emitter: Control = renderer._particle_emitters[0] as Control
	var synchronized_particle: TextureRect = flicker_emitter.call("spawn_particle") as TextureRect
	flicker_emitter.set("_flicker_elapsed", 0.0)
	flicker_emitter.call("_process", 0.5)
	assert(is_equal_approx(flicker_emitter.modulate.a, 0.2), "All-particle flicker must modulate the emitter as one synchronized group.")
	assert(is_equal_approx(synchronized_particle.modulate.a, 1.0), "Synchronized flicker must preserve each particle's own opacity.")

	var individual_config := flicker_config.merged({"flicker_type":"individual"}, true)
	renderer.definitions["Individual Particle Flicker"] = {"particle_effects":[individual_config]}
	renderer.show_weather("Individual Particle Flicker", 1)
	var individual_emitter: Control = renderer._particle_emitters[0] as Control
	individual_emitter.call("spawn_particle")
	individual_emitter.call("spawn_particle")
	var individual_live: Array = individual_emitter.get("live_particles") as Array
	individual_live[0]["flicker_phase"] = 0.0
	individual_live[1]["flicker_phase"] = 0.5
	individual_emitter.set("_flicker_elapsed", 0.0)
	individual_emitter.call("_process", 0.001)
	var alpha_a: float = (individual_live[0]["node"] as TextureRect).modulate.a
	var alpha_b: float = (individual_live[1]["node"] as TextureRect).modulate.a
	assert(individual_emitter.modulate.a == 1.0 and absf(alpha_a - alpha_b) > 0.5, "Individual flicker must use inexpensive per-particle phase offsets.")
	renderer.show_weather("Particle Test", 2)
	var expiry_emitter: Control = renderer._particle_emitters[0] as Control
	renderer.clear_weather()
	assert(not is_instance_valid(expiry_emitter) and renderer._particle_emitters.is_empty(), "Weather expiry must remove particle emitter state.")

	renderer.show_weather("Particle Test", 2)
	battle._end_battle("Particle test complete")
	assert(renderer._particle_emitters.is_empty() and renderer.spawned_root.get_child_count() == 0, "Battle end must remove every particle and emitter.")
	renderer.definitions.erase("Particle Test")
	renderer.definitions.erase("Screen Particle Test")
	renderer.definitions.erase("Particle Flicker")
	renderer.definitions.erase("Individual Particle Flicker")
	assert(JSON.stringify(renderer.definitions) == original_definitions, "Existing weather definitions must remain unchanged.")
	print("WEATHER_PARTICLE_TEST_PASSED")
	quit()
