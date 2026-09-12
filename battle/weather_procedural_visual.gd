class_name WeatherProceduralVisual
extends Control

enum Kind { BEAM, ORB, PARTICLES }

var kind := Kind.ORB
var visual_color := Color.WHITE
var edge_softness := 0.65
var start_width := 80.0
var end_width := 120.0
var beam_end := Vector2(0, 300)
var particle_count := 16
var particle_size := 3.0
var particle_drift := Vector2(8, -12)
var particle_speed := 1.0
var _particles: Array[Dictionary] = []


func configure_beam(from: Vector2, to: Vector2, from_width: float, to_width: float, color: Color, softness: float) -> void:
	kind = Kind.BEAM
	position = from
	beam_end = to - from
	start_width = maxf(1.0, from_width)
	end_width = maxf(1.0, to_width)
	visual_color = color
	edge_softness = clampf(softness, 0.0, 1.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func configure_orb(center: Vector2, diameter: float, color: Color, softness: float) -> void:
	kind = Kind.ORB
	var radius := maxf(1.0, diameter * 0.5)
	position = center - Vector2.ONE * radius
	size = Vector2.ONE * radius * 2.0
	visual_color = color
	edge_softness = clampf(softness, 0.05, 1.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func configure_particles(region_position: Vector2, region_size: Vector2, config: Dictionary) -> void:
	kind = Kind.PARTICLES
	position = region_position
	size = Vector2(maxf(1.0, region_size.x), maxf(1.0, region_size.y))
	particle_count = maxi(1, int(config.get("count", 16)))
	particle_size = maxf(0.5, float(config.get("size", 3.0)))
	particle_drift = Vector2(float(config.get("horizontal_drift", 8.0)), float(config.get("vertical_drift", -12.0)))
	particle_speed = maxf(0.01, float(config.get("speed", 1.0)))
	visual_color = Color(String(config.get("color", "#ffffff")), clampf(float(config.get("opacity", 0.5)), 0.0, 1.0))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_particles.clear()
	for index in particle_count:
		_particles.append({"position": Vector2(randf() * size.x, randf() * size.y), "phase": randf() * TAU, "scale": randf_range(0.55, 1.35)})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if kind != Kind.PARTICLES:
		set_process(false)
		return
	for particle: Dictionary in _particles:
		var point: Vector2 = particle["position"]
		point += particle_drift * particle_speed * delta
		point.x += sin(Time.get_ticks_msec() * 0.001 * particle_speed + float(particle["phase"])) * delta * 4.0
		point.x = fposmod(point.x, size.x)
		point.y = fposmod(point.y, size.y)
		particle["position"] = point
	queue_redraw()


func _draw() -> void:
	match kind:
		Kind.BEAM: _draw_beam()
		Kind.ORB: _draw_orb()
		Kind.PARTICLES: _draw_particles()


func _draw_beam() -> void:
	var length := beam_end.length()
	if length <= 0.01:
		return
	var normal := Vector2(-beam_end.y, beam_end.x).normalized()
	var layers := 12
	for layer in range(layers, 0, -1):
		var ratio := float(layer) / float(layers)
		var alpha_curve := pow(1.0 - ratio, 1.0 + edge_softness * 3.0)
		var c := visual_color
		c.a *= alpha_curve
		var sw := start_width * ratio * 0.5
		var ew := end_width * ratio * 0.5
		draw_colored_polygon(PackedVector2Array([-normal * sw, normal * sw, beam_end + normal * ew, beam_end - normal * ew]), c)


func _draw_orb() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var center := size * 0.5
	var rings := 20
	for ring in range(rings, 0, -1):
		var ratio := float(ring) / float(rings)
		var c := visual_color
		c.a *= pow(1.0 - ratio, 1.2 + edge_softness * 3.5)
		draw_circle(center, radius * ratio, c)


func _draw_particles() -> void:
	for particle: Dictionary in _particles:
		var radius := particle_size * float(particle["scale"])
		var outer := visual_color
		outer.a *= 0.18
		draw_circle(particle["position"], radius * 2.2, outer)
		draw_circle(particle["position"], radius, visual_color)
