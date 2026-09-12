class_name WeatherAlphaModulation
extends RefCounted


static func interval(config: Dictionary) -> float:
	return maxf(0.025, float(config.get("flicker_interval", 0.8)))


static func bounds(config: Dictionary, default_min: float, default_max: float) -> Vector2:
	var low := clampf(float(config.get("flicker_min_alpha", default_min)), 0.0, 1.0)
	var high := clampf(float(config.get("flicker_max_alpha", default_max)), low, 1.0)
	return Vector2(low, high)


static func sample(config: Dictionary, elapsed: float, phase := 0.0, default_min := 0.7, default_max := 1.0) -> float:
	var limits := bounds(config, default_min, default_max)
	var leg := interval(config)
	var cycle_position := fposmod(elapsed + phase, leg * 2.0) / leg
	var blend := cycle_position if cycle_position <= 1.0 else 2.0 - cycle_position
	# Match the light tween's smooth sine transition from maximum to minimum.
	blend = 0.5 - cos(blend * PI) * 0.5
	return lerpf(limits.y, limits.x, blend)


static func start_light_tween(node: CanvasItem, config: Dictionary, base_alpha: float) -> void:
	if not bool(config.get("flicker_enabled", false)):
		return
	var limits := bounds(config, base_alpha * 0.7, base_alpha)
	var divisor := maxf(0.001, base_alpha)
	node.modulate.a = limits.y / divisor
	var tween := node.create_tween().set_loops()
	tween.tween_property(node, "modulate:a", limits.x / divisor, interval(config)).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "modulate:a", limits.y / divisor, interval(config)).set_trans(Tween.TRANS_SINE)
