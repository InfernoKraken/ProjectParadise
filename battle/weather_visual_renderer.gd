class_name WeatherVisualRenderer
extends Control

const DEFINITIONS_PATH := "res://data/weather_visuals.json"
const WEATHER_ASSET_DIR := "res://assets/battle/weather"
const PROCEDURAL_VISUAL := preload("res://battle/weather_procedural_visual.gd")
const PARTICLE_EMITTER := preload("res://battle/weather_particle_emitter.gd")
const SCROLLING_STRIP := preload("res://battle/weather_scrolling_strip.gd")
const ALPHA_MODULATION := preload("res://battle/weather_alpha_modulation.gd")
const SCENE_ANCHORS := preload("res://battle/battle_scene_anchor_repository.gd")

var current_weather := ""
var weather_duration := 0
var current_turn := 0
var definitions: Dictionary = {}
var visual_root: Control
var spawned_root: Control
var badge: Label
var _ambient_timers: Array[Timer] = []
var _pulse_timers: Array[Timer] = []
var _pulse_loop_signature := ""
var _variant_cursors: Dictionary = {}
var _particle_emitters: Dictionary = {}
var _thought_timer: Timer
var _thought_sequence_cursor := 0
var _thought_generation := 0
var fading_root: Control
var _expired_sprite_keys: Dictionary = {}
var _fading_sprites: Array[Dictionary] = []
var _scene_anchors := SCENE_ANCHORS.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_definitions()
	visual_root = Control.new()
	visual_root.name = "PersistentWeatherVisuals"
	visual_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(visual_root)
	visual_root.resized.connect(_layout_current_overlay)
	spawned_root = Control.new()
	spawned_root.name = "SpawnedWeatherVisuals"
	spawned_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spawned_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(spawned_root)
	fading_root = Control.new()
	fading_root.name = "FadingWeatherVisuals"
	fading_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fading_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fading_root)
	badge = Label.new()
	badge.name = "WeatherBadge"
	badge.position = Vector2(690, 16)
	badge.size = Vector2(240, 34)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 17)
	badge.add_theme_color_override("font_color", Color("#fff7dd"))
	badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	badge.add_theme_constant_override("shadow_offset_x", 2)
	badge.add_theme_constant_override("shadow_offset_y", 2)
	badge.hide()
	add_child(badge)


func show_weather(weather_name: String, turns_remaining: int) -> void:
	if weather_name.is_empty():
		clear_weather()
		return
	if current_weather == weather_name:
		update_turns(turns_remaining)
		return
	clear_weather()
	current_weather = weather_name
	weather_duration = maxi(1, turns_remaining)
	current_turn = 1
	update_turns(turns_remaining)
	var definition: Dictionary = definitions.get(weather_name, {})
	if definition.is_empty():
		push_warning("No visual definition exists for weather '%s'." % weather_name)
		return


func update_turns(turns_remaining: int) -> void:
	if weather_duration <= 0:
		weather_duration = maxi(1, turns_remaining)
	current_turn = clampi(weather_duration - turns_remaining + 1, 1, weather_duration)
	badge.text = "☁  %s  ·  %d" % [current_weather, turns_remaining]
	badge.visible = not current_weather.is_empty()
	if not current_weather.is_empty():
		_rebuild_persistent_visuals()
		_sync_looping_pulses()
		_sync_particle_emitters()
		_sync_thought_sequences()


func pulse_turn() -> void:
	if current_weather.is_empty():
		return
	var definition: Dictionary = definitions.get(current_weather, {})
	for effect: Dictionary in definition.get("turn_effects", []):
		if not is_element_active_on_turn(effect, current_turn):
			continue
		if String(effect.get("type", "")) == "sprite_burst":
			_spawn_sprite_effect(effect)
		elif String(effect.get("type", "")) == "pulse" and not bool(effect.get("loop", false)):
			_create_pulse(effect)
	_sync_looping_pulses()


func clear_weather(immediate := false) -> void:
	_clear_thought_sequences()
	_clear_pulse_timers()
	_clear_particle_emitters()
	current_weather = ""
	weather_duration = 0
	current_turn = 0
	_clear_persistent_visuals(false, "weather_ends", immediate)
	if spawned_root != null:
		for child: Node in spawned_root.get_children():
			child.free()
	if badge != null:
		badge.hide()
	_expired_sprite_keys.clear()
	if immediate and fading_root != null:
		for child: Node in fading_root.get_children(): child.free()
		_fading_sprites.clear()


func _clear_persistent_visuals(preserve_active_sprites := false, cause := "immediate", immediate := false) -> void:
	for timer: Timer in _ambient_timers:
		if is_instance_valid(timer):
			timer.stop()
			timer.free()
	_ambient_timers.clear()
	if visual_root != null:
		for child: Node in visual_root.get_children():
			if child.has_meta("weather_sprite_config"):
				var sprite_config: Dictionary = child.get_meta("weather_sprite_config")
				if preserve_active_sprites and is_element_active_on_turn(sprite_config, current_turn):
					continue
				_retire_sprite_node(child as CanvasItem, sprite_config, cause, immediate)
			else:
				child.free()


func _retire_sprite_node(node: CanvasItem, config: Dictionary, cause: String, immediate := false) -> void:
	if not is_instance_valid(node): return
	var fade_duration := maxf(0.0, float(config.get("fade_out_duration", 0.0)))
	var configured_causes: Array = config.get("fade_out_causes", [String(config.get("fade_out_trigger", "weather_ends"))])
	if immediate or fade_duration <= 0.0 or not configured_causes.has(cause):
		node.free()
		return
	node.reparent(fading_root, true)
	_fading_sprites.append({"node":node, "elapsed":0.0, "duration":fade_duration, "start_alpha":node.modulate.a})


func _process(delta: float) -> void:
	for entry: Dictionary in _fading_sprites.duplicate():
		var node: CanvasItem = entry["node"] as CanvasItem
		if not is_instance_valid(node):
			_fading_sprites.erase(entry)
			continue
		entry["elapsed"] = float(entry["elapsed"]) + delta
		var progress := clampf(float(entry["elapsed"]) / float(entry["duration"]), 0.0, 1.0)
		node.modulate.a = lerpf(float(entry["start_alpha"]), 0.0, progress)
		if progress >= 1.0:
			_fading_sprites.erase(entry)
			node.free()


func _clear_pulse_timers() -> void:
	for timer: Timer in _pulse_timers:
		if is_instance_valid(timer):
			timer.stop()
			timer.free()
	_pulse_timers.clear()
	_pulse_loop_signature = ""


func _clear_particle_emitters() -> void:
	for emitter: Node in _particle_emitters.values():
		if is_instance_valid(emitter):
			emitter.free()
	_particle_emitters.clear()


func _clear_thought_sequences() -> void:
	_thought_generation += 1
	_thought_sequence_cursor = 0
	if is_instance_valid(_thought_timer):
		_thought_timer.stop()
		_thought_timer.free()
	_thought_timer = null


func _sync_thought_sequences() -> void:
	if is_instance_valid(_thought_timer):
		return
	var config: Dictionary = definitions.get(current_weather, {}).get("thought_sequence", {})
	if config.get("sequences", []).is_empty():
		return
	_thought_timer = Timer.new()
	_thought_timer.name = "WeatherThoughtSequence"
	_thought_timer.one_shot = true
	_thought_timer.wait_time = maxf(0.1, float(config.get("initial_delay", config.get("interval", 5.0))))
	_thought_timer.timeout.connect(_play_next_thought_sequence)
	add_child(_thought_timer)
	_thought_timer.start()


func _play_next_thought_sequence() -> void:
	var weather_name := current_weather
	var generation := _thought_generation
	var config: Dictionary = definitions.get(weather_name, {}).get("thought_sequence", {})
	var sequences: Array = config.get("sequences", [])
	if sequences.is_empty():
		return
	var sequence: Array = sequences[_thought_sequence_cursor % sequences.size()]
	_thought_sequence_cursor += 1
	for step: Dictionary in sequence:
		if generation != _thought_generation or weather_name != current_weather:
			return
		_activate_thought_targets(step)
		_emit_thought_particles(step)
		await get_tree().create_timer(maxf(0.05, float(step.get("duration", 0.3)))).timeout
	if generation == _thought_generation and weather_name == current_weather and is_instance_valid(_thought_timer):
		_thought_timer.wait_time = maxf(0.1, float(config.get("interval", 5.0)))
		_thought_timer.start()


func _activate_thought_targets(step: Dictionary) -> void:
	var requested: Array = step.get("targets", [])
	for child: Node in visual_root.get_children():
		if not child is CanvasItem or not child.has_meta("thought_id") or not requested.has(String(child.get_meta("thought_id"))):
			continue
		var item := child as CanvasItem
		var low := float(child.get_meta("thought_low_alpha", 0.08))
		var high := float(child.get_meta("thought_high_alpha", 0.55))
		var duration := maxf(0.05, float(step.get("duration", 0.3)))
		var tween := item.create_tween()
		tween.tween_property(item, "modulate:a", high, duration * 0.35).set_trans(Tween.TRANS_SINE)
		tween.tween_property(item, "modulate:a", low, duration * 0.65).set_trans(Tween.TRANS_SINE)


func _emit_thought_particles(step: Dictionary) -> void:
	if not step.has("particle_effect"):
		return
	var emitter: Node = _particle_emitters.get(int(step["particle_effect"]))
	if emitter == null:
		return
	for unused in maxi(1, int(step.get("particle_count", 3))):
		emitter.call("spawn_particle")


func _sync_particle_emitters() -> void:
	var definition: Dictionary = definitions.get(current_weather, {})
	var effects: Array = definition.get("particle_effects", [])
	for key: Variant in _particle_emitters.keys():
		var index := int(key)
		if index >= effects.size():
			var stale: Node = _particle_emitters[key]
			stale.free()
			_particle_emitters.erase(key)
	for index in effects.size():
		var effect: Dictionary = effects[index]
		var active := String(effect.get("type", "particle")) == "particle" and is_element_active_on_turn(effect, current_turn)
		var emitter: Control = _particle_emitters.get(index) as Control
		if emitter == null and active:
			emitter = _create_particle_emitter(effect, index)
		if emitter != null:
			emitter.call("set_emitting", active)


func _create_particle_emitter(config: Dictionary, index: int) -> Control:
	var family := String(config.get("particle_sprite", ""))
	var variants := resolve_sprite_variants(family)
	if variants.is_empty():
		push_warning("Weather particle family has no valid variants: %s" % family)
		return null
	var emitter := PARTICLE_EMITTER.new()
	emitter.name = "WeatherParticleEmitter_%d" % index
	var bounds := size if size.x > 0.0 else Vector2(960, 540)
	var region_size := Vector2(maxf(0.0, float(config.get("emitter_width", 0.0))), maxf(0.0, float(config.get("emitter_height", 0.0))))
	var origin := Vector2.ZERO
	var emitter_mode: String = PARTICLE_EMITTER.resolve_emitter_mode(config)
	if emitter_mode == "anchored":
		origin = _anchor_position(String(config.get("emitter_anchor", "SCREEN_CENTER")), region_size)
		origin += Vector2(float(config.get("emitter_offset_x", 0.0)), float(config.get("emitter_offset_y", 0.0)))
	emitter.configure(config, variants, Rect2(origin, region_size), bounds)
	spawned_root.add_child(emitter)
	_particle_emitters[index] = emitter
	return emitter


func _sync_looping_pulses() -> void:
	var definition: Dictionary = definitions.get(current_weather, {})
	var eligible: Array[Dictionary] = []
	for effect: Dictionary in definition.get("turn_effects", []):
		if String(effect.get("type", "")) == "pulse" and bool(effect.get("loop", false)) and is_element_active_on_turn(effect, current_turn):
			eligible.append(effect)
	var signature := "%s:%d:%s" % [current_weather, current_turn, JSON.stringify(eligible)]
	if signature == _pulse_loop_signature:
		return
	_clear_pulse_timers()
	_pulse_loop_signature = signature
	for effect: Dictionary in eligible:
		_create_pulse(effect)
		var timer := Timer.new()
		timer.name = "WeatherPulseLoop"
		timer.wait_time = maxf(0.05, float(effect.get("interval", 1.0)))
		timer.timeout.connect(_create_pulse.bind(effect))
		add_child(timer)
		timer.start()
		_pulse_timers.append(timer)


func _rebuild_persistent_visuals() -> void:
	if visual_root == null:
		return
	_clear_persistent_visuals(true, "element_not_on_turn")
	var definition: Dictionary = definitions.get(current_weather, {})
	var overlay: Dictionary = definition.get("background_overlay", {})
	if is_element_active_on_turn(overlay, current_turn):
		_create_overlay(overlay)
	for effect: Dictionary in definition.get("lighting_effects", []):
		if is_element_active_on_turn(effect, current_turn):
			_create_lighting(effect)
	var sprite_effects: Array = definition.get("sprite_effects", [])
	for element_index in sprite_effects.size():
		var effect: Dictionary = sprite_effects[element_index]
		var duration_key := "%s:%d:%d" % [current_weather, current_turn, element_index]
		if is_element_active_on_turn(effect, current_turn) and not _expired_sprite_keys.has(duration_key):
			var found := false
			for child: Node in visual_root.get_children():
				if child.has_meta("weather_sprite_config") and child.get_meta("weather_sprite_index") == element_index: found = true
			if not found: _create_sprite_behavior(effect, element_index)


static func is_element_active_on_turn(element: Dictionary, turn: int) -> bool:
	if element.is_empty() or turn < 1:
		return false
	if not element.has("turns"):
		return true
	var turns: Variant = element["turns"]
	if turns is String and turns == "all":
		return true
	if turns is int or turns is float:
		return int(turns) == turn and int(turns) > 0 and float(turns) == float(int(turns))
	if turns is Array:
		for value: Variant in turns:
			if (value is int or value is float) and int(value) > 0 and float(value) == float(int(value)) and int(value) == turn:
				return true
	return false


func _load_definitions() -> void:
	var file := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		push_warning("Weather visuals could not load %s." % DEFINITIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		definitions = (parsed as Dictionary).get("weathers", {})
	else:
		push_warning("Weather visual definitions are invalid JSON.")


func _create_overlay(config: Dictionary) -> void:
	if config.is_empty():
		return
	var path := String(config.get("asset", ""))
	if not ResourceLoader.exists(path):
		push_warning("Weather overlay asset is missing: %s" % path)
		return
	var overlay := TextureRect.new()
	overlay.name = "BackgroundOverlay"
	overlay.texture = load(path)
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_SCALE
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.modulate = Color(String(config.get("modulate", "#ffffff")), float(config.get("opacity", 1.0)))
	overlay.flip_h = bool(config.get("mirror_x", false))
	overlay.flip_v = bool(config.get("mirror_y", false))
	overlay.set_meta("weather_overlay_config", config.duplicate(true))
	visual_root.add_child(overlay)
	_layout_overlay(overlay, config)


func _layout_current_overlay() -> void:
	if visual_root == null:
		return
	var overlay := visual_root.get_node_or_null("BackgroundOverlay") as TextureRect
	if overlay != null and overlay.has_meta("weather_overlay_config"):
		_layout_overlay(overlay, overlay.get_meta("weather_overlay_config"))


func _layout_overlay(overlay: TextureRect, config: Dictionary) -> void:
	if not is_instance_valid(overlay) or overlay.texture == null or visual_root == null:
		return
	var texture_size := overlay.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var cover_scale := maxf(visual_root.size.x / texture_size.x, visual_root.size.y / texture_size.y)
	var rendered_size := texture_size * cover_scale * float(config.get("scale", 1.0))
	overlay.size = rendered_size
	overlay.position = (visual_root.size - rendered_size) * 0.5 + _config_offset(config)


func _create_lighting(config: Dictionary) -> void:
	var count := maxi(1, int(config.get("count", 1)))
	for index in count:
		var type := String(config.get("type", "wash"))
		if type == "beam":
			_create_beam(config, index, count)
			continue
		if type == "orb":
			_create_orb(config)
			continue
		if type == "heat_shimmer":
			_create_heat_shimmer(config)
			continue
		if type == "particles":
			_create_particles(config)
			continue
		var light := ColorRect.new()
		light.name = "Lighting_%s_%d" % [config.get("type", "wash"), index]
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var color := Color(String(config.get("color", "#ffffff")), float(config.get("opacity", 0.2)))
		light.color = color
		light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visual_root.add_child(light)
		_start_flicker(light, config, color.a)


func _create_beam(config: Dictionary, index: int, count: int) -> void:
	var start_anchor := String(config.get("start_anchor", config.get("anchor", "SCREEN_TOP")))
	var end_anchor := String(config.get("end_anchor", "FIELD_CENTER"))
	var start := resolve_anchor_point(start_anchor) + Vector2(float(config.get("start_x_offset", config.get("x_offset", 0.0))), float(config.get("start_y_offset", config.get("y_offset", 0.0))))
	var finish := resolve_anchor_point(end_anchor) + Vector2(float(config.get("end_x_offset", 0.0)), float(config.get("end_y_offset", 0.0)))
	if not start_anchor.begins_with("RANDOM_"):
		var spread := (float(index) - float(count - 1) * 0.5) * float(config.get("spacing", 120.0))
		start.x += spread
		finish.x += spread
	var beam := PROCEDURAL_VISUAL.new()
	beam.name = "Lighting_beam_%d" % index
	var color := Color(String(config.get("color", "#ffffff")), float(config.get("opacity", 0.2)))
	beam.configure_beam(start, finish, float(config.get("start_width", 70.0)), float(config.get("end_width", 130.0)), color, float(config.get("edge_softness", 0.7)))
	visual_root.add_child(beam)
	_start_flicker(beam, config, color.a)


func _create_orb(config: Dictionary) -> void:
	var diameter := maxf(2.0, float(config.get("size", 70.0)))
	var center := resolve_anchor_point(String(config.get("anchor", "RANDOM_SCREEN"))) + _config_offset(config)
	var orb := PROCEDURAL_VISUAL.new()
	orb.name = "Lighting_orb"
	var color := Color(String(config.get("color", "#ffffff")), float(config.get("opacity", 0.2)))
	orb.configure_orb(center, diameter, color, float(config.get("edge_softness", 0.75)))
	visual_root.add_child(orb)
	_start_flicker(orb, config, color.a)


func _create_heat_shimmer(config: Dictionary) -> void:
	var region_size := Vector2(maxf(1.0, float(config.get("width", 180.0))), maxf(1.0, float(config.get("height", 90.0))))
	var shimmer := ColorRect.new()
	shimmer.name = "Lighting_heat_shimmer"
	shimmer.position = _anchor_position(String(config.get("anchor", "FIELD_CENTER")), region_size) + _config_offset(config)
	shimmer.size = region_size
	shimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap; uniform float strength = 0.006; uniform float speed = 1.0; void fragment(){ vec2 uv=SCREEN_UV; float wave=sin((uv.y*90.0)+TIME*speed*5.0)*strength; COLOR=textureLod(screen_texture,uv+vec2(wave,0.0),0.0); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("strength", maxf(0.0, float(config.get("strength", 0.006))))
	material.set_shader_parameter("speed", float(config.get("speed", 1.0)))
	shimmer.material = material
	visual_root.add_child(shimmer)


func _create_particles(config: Dictionary) -> void:
	var region_size := Vector2(maxf(1.0, float(config.get("width", size.x if size.x > 0 else 960.0))), maxf(1.0, float(config.get("height", size.y if size.y > 0 else 540.0))))
	var particles := PROCEDURAL_VISUAL.new()
	particles.name = "Lighting_particles"
	particles.configure_particles(_anchor_position(String(config.get("anchor", "SCREEN_CENTER")), region_size) + _config_offset(config), region_size, config)
	visual_root.add_child(particles)


func _start_flicker(node: CanvasItem, config: Dictionary, base_alpha: float) -> void:
	ALPHA_MODULATION.start_light_tween(node, config, base_alpha)


func _create_sprite_behavior(config: Dictionary, element_index := -1) -> void:
	if String(config.get("sprite_mode", "static")) == "scrolling":
		_create_scrolling_sprite(config, element_index)
		return
	match String(config.get("mode", "persistent")):
		"ambient_spawn":
			_spawn_sprite_effect(config)
			var timer := Timer.new()
			timer.wait_time = maxf(0.1, float(config.get("spawn_interval", 1.0)))
			timer.timeout.connect(_spawn_sprite_effect.bind(config))
			add_child(timer)
			timer.start()
			_ambient_timers.append(timer)
		"burst":
			pass
		_:
			var sprite := _spawn_sprite_effect(config, true)
			if sprite != null: _register_sprite_element(sprite, config, element_index)


func _create_scrolling_sprite(config: Dictionary, element_index: int) -> void:
	var family := String(config.get("asset_family", ""))
	var variants := resolve_sprite_variants(family)
	if variants.is_empty():
		push_warning("Weather scrolling family has no valid variants: %s" % family)
		return
	var strip := SCROLLING_STRIP.new()
	strip.name = "WeatherScrolling_%s" % family
	strip.configure(config, variants, size if size.x > 0.0 else Vector2(960, 540))
	visual_root.add_child(strip)
	_register_sprite_element(strip, config, element_index)


func _register_sprite_element(node: CanvasItem, config: Dictionary, element_index: int) -> void:
	node.set_meta("weather_sprite_config", config.duplicate(true))
	node.set_meta("weather_sprite_index", element_index)
	if not config.has("thought_id") and maxf(0.0, float(config.get("fade_out_duration", 0.0))) > 0.0 and _fade_causes(config).has("duration"):
		var timer := get_tree().create_timer(maxf(0.01, float(config.get("visible_duration", 1.0))))
		timer.timeout.connect(_expire_sprite_duration.bind(node, config, element_index, current_weather, current_turn))


func _expire_sprite_duration(node: CanvasItem, config: Dictionary, element_index: int, weather_name: String, turn: int) -> void:
	if not is_instance_valid(node): return
	_expired_sprite_keys["%s:%d:%d" % [weather_name, turn, element_index]] = true
	_retire_sprite_node(node, config, "duration", false)


static func _fade_causes(config: Dictionary) -> Array:
	return config.get("fade_out_causes", [String(config.get("fade_out_trigger", "weather_ends"))])


func _spawn_sprite_effect(config: Dictionary, persistent := false) -> TextureRect:
	var family := String(config.get("asset_family", ""))
	var variants := resolve_sprite_variants(family)
	if variants.is_empty():
		push_warning("Weather sprite family has no valid variants: %s" % family)
		return null
	var count := maxi(1, int(config.get("spawn_count", 1)))
	var first_sprite: TextureRect = null
	for index in count:
		var path := _choose_variant(family, variants, String(config.get("variant_mode", "random")))
		var sprite := TextureRect.new()
		sprite.name = "WeatherSprite_%s" % family
		sprite.texture = load(path)
		sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var scale_value := maxf(0.01, float(config.get("scale", 1.0)))
		var texture_size := sprite.texture.get_size()
		sprite.size = texture_size
		sprite.scale = Vector2.ONE * scale_value
		sprite.position = _anchor_position(String(config.get("anchor", "SCREEN_CENTER")), texture_size * scale_value)
		sprite.position += _config_offset(config)
		sprite.pivot_offset = texture_size * 0.5
		sprite.rotation_degrees = float(config.get("rotation", 0.0))
		sprite.modulate.a = 0.0 if not persistent else 1.0
		sprite.modulate.a *= clampf(float(config.get("opacity", 1.0)), 0.0, 1.0)
		if bool(config.get("mirror_x", false)): sprite.scale.x *= -1.0
		if bool(config.get("mirror_y", false)): sprite.scale.y *= -1.0
		(visual_root if persistent else spawned_root).add_child(sprite)
		if persistent and config.has("thought_id"):
			sprite.set_meta("thought_id", String(config["thought_id"]))
			sprite.set_meta("thought_low_alpha", clampf(float(config.get("thought_low_alpha", 0.08)), 0.0, 1.0))
			sprite.set_meta("thought_high_alpha", clampf(float(config.get("thought_high_alpha", config.get("opacity", 0.55))), 0.0, 1.0))
			sprite.modulate.a = float(sprite.get_meta("thought_low_alpha"))
		if String(config.get("sprite_mode", "static")) == "animated":
			_start_sprite_frame_animation(sprite, variants, config)
		if persistent and bool(config.get("signal_enabled", false)):
			_start_sprite_signal(sprite, config)
		if first_sprite == null: first_sprite = sprite
		if not persistent:
			var lifetime := maxf(0.1, float(config.get("lifetime", 1.5)))
			var target_opacity := clampf(float(config.get("opacity", 1.0)), 0.0, 1.0)
			var tween := sprite.create_tween()
			tween.tween_property(sprite, "modulate:a", target_opacity, minf(0.2, lifetime * 0.2))
			tween.tween_interval(maxf(0.0, lifetime - 0.45))
			tween.tween_property(sprite, "modulate:a", 0.0, 0.25)
			tween.tween_callback(sprite.queue_free)
	return first_sprite


func _start_sprite_frame_animation(sprite: TextureRect, variants: Array[String], config: Dictionary) -> void:
	if variants.size() < 2:
		return
	var frame_paths := variants.duplicate()
	if bool(config.get("animation_ping_pong", false)) and frame_paths.size() > 2:
		for index in range(frame_paths.size() - 2, 0, -1):
			frame_paths.append(frame_paths[index])
	sprite.texture = load(frame_paths[0])
	var timer := Timer.new()
	timer.name = "FrameAnimation"
	timer.wait_time = maxf(0.05, float(config.get("frame_duration", 0.25)))
	var state := {"frame": 0}
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(sprite):
			return
		state["frame"] = (int(state["frame"]) + 1) % frame_paths.size()
		sprite.texture = load(frame_paths[int(state["frame"])])
	)
	sprite.add_child(timer)
	timer.start()


func _start_sprite_signal(sprite: TextureRect, config: Dictionary) -> void:
	var low := clampf(float(config.get("signal_min_alpha", 0.12)), 0.0, 1.0)
	var high := clampf(float(config.get("signal_max_alpha", config.get("opacity", 0.5))), low, 1.0)
	var rise_time := maxf(0.05, float(config.get("signal_rise_time", 0.3)))
	var fall_time := maxf(0.05, float(config.get("signal_fall_time", 0.6)))
	var interval := maxf(0.0, float(config.get("signal_interval", 2.5)))
	var delay := maxf(0.0, float(config.get("signal_delay", 0.0)))
	sprite.modulate.a = low
	var tween := sprite.create_tween().set_loops()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(sprite, "modulate:a", high, rise_time).set_trans(Tween.TRANS_SINE)
	tween.tween_property(sprite, "modulate:a", low, fall_time).set_trans(Tween.TRANS_SINE)
	var trailing_hold := maxf(0.0, interval - delay)
	if trailing_hold > 0.0:
		tween.tween_interval(trailing_hold)


func resolve_sprite_variants(family: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(WEATHER_ASSET_DIR)
	if directory == null or family.is_empty():
		return result
	var matcher := RegEx.new()
	matcher.compile("^%s_[0-9][0-9]\\.png$" % family.replace(".", "\\."))
	for filename: String in directory.get_files():
		if matcher.search(filename) != null:
			result.append("%s/%s" % [WEATHER_ASSET_DIR, filename])
	result.sort()
	return result


func _choose_variant(family: String, variants: Array[String], mode: String) -> String:
	if mode == "fixed":
		return variants[0]
	if mode == "sequential":
		var cursor := int(_variant_cursors.get(family, 0)) % variants.size()
		_variant_cursors[family] = cursor + 1
		return variants[cursor]
	return variants.pick_random()


func _anchor_position(anchor: String, item_size: Vector2) -> Vector2:
	var bounds := size if size.x > 0.0 else Vector2(960, 540)
	return _scene_anchors.resolve(anchor, bounds, item_size)


func resolve_anchor_point(anchor: String) -> Vector2:
	return _anchor_position(anchor, Vector2.ZERO)


static func _config_offset(config: Dictionary) -> Vector2:
	return Vector2(float(config.get("x_offset", 0.0)), float(config.get("y_offset", 0.0)))


func _create_pulse(config: Dictionary) -> void:
	var pulse := ColorRect.new()
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse.color = Color(String(config.get("color", "#ffffff")), 0.0)
	pulse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	spawned_root.add_child(pulse)
	var opacity := float(config.get("opacity", 0.15))
	var duration := maxf(0.1, float(config.get("duration", 0.5)))
	var tween := pulse.create_tween()
	tween.tween_property(pulse, "color:a", opacity, duration * 0.4)
	tween.tween_property(pulse, "color:a", 0.0, duration * 0.6)
	tween.tween_callback(pulse.queue_free)
