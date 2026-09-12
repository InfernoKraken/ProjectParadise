class_name WeatherParticleEmitter
extends Control

const ALPHA_MODULATION := preload("res://battle/weather_alpha_modulation.gd")

var config: Dictionary = {}
var variants: Array[String] = []
var textures: Array[Texture2D] = []
var emitting := false
var region := Rect2()
var emitter_mode := "anchored"
var viewport_bounds := Vector2(960, 540)
var live_particles: Array[Dictionary] = []
var total_emitted := 0
var _emission_accumulator := 0.0
var _flicker_elapsed := 0.0


func configure(p_config: Dictionary, p_variants: Array[String], p_region: Rect2, p_viewport_bounds: Vector2) -> void:
	config = p_config.duplicate(true)
	variants = p_variants.duplicate()
	textures.clear()
	for path: String in variants:
		var texture := load(path) as Texture2D
		if texture != null:
			textures.append(texture)
	region = p_region
	viewport_bounds = p_viewport_bounds
	emitter_mode = resolve_emitter_mode(config)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func set_emitting(value: bool) -> void:
	emitting = value and not textures.is_empty()
	if emitting:
		set_process(true)
	else:
		_emission_accumulator = 0.0


func spawn_particle() -> TextureRect:
	if textures.is_empty() or live_particles.size() >= maxi(0, int(config.get("emit_max_count", 32))):
		return null
	var particle := TextureRect.new()
	particle.name = "WeatherParticle"
	particle.texture = textures.pick_random()
	particle.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	particle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	particle.size = particle.texture.get_size()
	var scale_low := maxf(0.01, float(config.get("scale_min", 1.0)))
	var scale_high := maxf(scale_low, float(config.get("scale_max", scale_low)))
	var scale_value := randf_range(scale_low, scale_high)
	particle.scale = Vector2.ONE * scale_value
	var opacity_low := clampf(float(config.get("opacity_min", 1.0)), 0.0, 1.0)
	var opacity_high := clampf(float(config.get("opacity_max", opacity_low)), opacity_low, 1.0)
	particle.modulate.a = randf_range(opacity_low, opacity_high)
	var base_opacity := particle.modulate.a
	particle.position = _spawn_position()
	var velocity := resolve_velocity(config)
	match String(config.get("rotation_mode", "fixed")):
		"random": particle.rotation = randf_range(0.0, TAU)
		"align_to_velocity": particle.rotation = velocity.angle()
		_: particle.rotation_degrees = float(config.get("rotation", 0.0))
	add_child(particle)
	live_particles.append({
		"node": particle,
		"age": 0.0,
		"lifetime": maxf(0.01, float(config.get("particle_lifetime", 1.0))),
		"velocity": velocity,
		"rotation_speed": deg_to_rad(float(config.get("rotation_speed", 0.0))),
		"base_opacity": base_opacity,
		"flicker_phase": randf_range(0.0, ALPHA_MODULATION.interval(config) * 2.0)
	})
	total_emitted += 1
	return particle


static func resolve_velocity(p_config: Dictionary) -> Vector2:
	var speed := float(p_config.get("speed", 100.0))
	var drift := float(p_config.get("horizontal_drift", 0.0))
	match String(p_config.get("movement_mode", "fall")):
		"rise": return Vector2(drift, -absf(speed))
		"left": return Vector2(-absf(speed), 0.0)
		"right", "horizontal": return Vector2(absf(speed), 0.0)
		_: return Vector2(drift, absf(speed))


static func resolve_emitter_mode(p_config: Dictionary) -> String:
	if p_config.has("emitter_mode"):
		return "screen" if String(p_config["emitter_mode"]) == "screen" else "anchored"
	# Legacy aliases from the initial runtime schema.
	return "screen" if String(p_config.get("emitter_space", "position")) == "global" else "anchored"


func _spawn_position() -> Vector2:
	if emitter_mode != "screen":
		return Vector2(
			randf_range(region.position.x, region.end.x) if region.size.x > 0.0 else region.position.x,
			randf_range(region.position.y, region.end.y) if region.size.y > 0.0 else region.position.y
		)
	match String(config.get("movement_mode", "fall")):
		"rise": return Vector2(randf_range(0.0, viewport_bounds.x), viewport_bounds.y)
		"left": return Vector2(viewport_bounds.x, randf_range(0.0, viewport_bounds.y))
		"right", "horizontal": return Vector2(0.0, randf_range(0.0, viewport_bounds.y))
		_: return Vector2(randf_range(0.0, viewport_bounds.x), 0.0)


func _is_outside_viewport(point: Vector2) -> bool:
	var margin := maxf(0.0, float(config.get("offscreen_margin", 32.0)))
	return point.x < -margin or point.y < -margin or point.x > viewport_bounds.x + margin or point.y > viewport_bounds.y + margin


func _process(delta: float) -> void:
	_flicker_elapsed += delta
	var flicker_enabled := bool(config.get("flicker_enabled", false))
	var individual_flicker := String(config.get("flicker_type", "all")) == "individual"
	modulate.a = ALPHA_MODULATION.sample(config, _flicker_elapsed) if flicker_enabled and not individual_flicker else 1.0
	if emitting:
		_emission_accumulator += maxf(0.0, float(config.get("emit_rate", 1.0))) * delta
		while _emission_accumulator >= 1.0 and live_particles.size() < maxi(0, int(config.get("emit_max_count", 32))):
			spawn_particle()
			_emission_accumulator -= 1.0
	for entry: Dictionary in live_particles.duplicate():
		var particle: TextureRect = entry["node"] as TextureRect
		if not is_instance_valid(particle):
			live_particles.erase(entry)
			continue
		entry["age"] = float(entry["age"]) + delta
		particle.position += (entry["velocity"] as Vector2) * delta
		particle.rotation += float(entry["rotation_speed"]) * delta
		if flicker_enabled and individual_flicker:
			particle.modulate.a = float(entry["base_opacity"]) * ALPHA_MODULATION.sample(config, _flicker_elapsed, float(entry["flicker_phase"]))
		else:
			particle.modulate.a = float(entry["base_opacity"])
		if float(entry["age"]) >= float(entry["lifetime"]) or _is_outside_viewport(particle.position):
			live_particles.erase(entry)
			particle.free()
	if not emitting and live_particles.is_empty():
		set_process(false)
