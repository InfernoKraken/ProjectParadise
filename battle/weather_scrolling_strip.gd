class_name WeatherScrollingStrip
extends Control

var config: Dictionary = {}
var textures: Array[Texture2D] = []
var viewport_bounds := Vector2(960, 540)
var _cursor := 0
var _finished := false


func configure(p_config: Dictionary, paths: Array[String], bounds: Vector2) -> void:
	config = p_config.duplicate(true)
	viewport_bounds = bounds
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for path: String in paths:
		var texture := load(path) as Texture2D
		if texture != null:
			textures.append(texture)
	if textures.is_empty():
		return
	_build_initial_strip()
	set_process(true)


func _process(delta: float) -> void:
	var direction := -1.0 if String(config.get("scroll_direction", "left")) == "left" else 1.0
	var movement := direction * maxf(0.0, float(config.get("scroll_speed", 30.0))) * delta
	for sprite: TextureRect in get_children():
		sprite.position.x += movement
	_remove_exited(direction)
	_fill_entry_edge(direction)


func _build_initial_strip() -> void:
	var direction := -1.0 if String(config.get("scroll_direction", "left")) == "left" else 1.0
	if direction < 0.0:
		var x := -_estimated_width()
		while x < viewport_bounds.x + _estimated_width() and not _finished:
			var sprite := _create_next_sprite()
			if sprite == null: break
			sprite.position.x = x
			x += _advance(sprite)
	else:
		var x := viewport_bounds.x + _estimated_width()
		while x > -_estimated_width() and not _finished:
			var sprite := _create_next_sprite()
			if sprite == null: break
			x -= _advance(sprite)
			sprite.position.x = x


func _create_next_sprite() -> TextureRect:
	if textures.is_empty() or (_cursor >= textures.size() and not bool(config.get("loop", true))):
		_finished = true
		return null
	var texture := textures[_cursor % textures.size()]
	_cursor += 1
	var sprite := TextureRect.new()
	sprite.name = "ScrollingSprite_%d" % _cursor
	sprite.texture = texture
	sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.size = texture.get_size()
	var scale_value := maxf(0.01, float(config.get("scale", 1.0)))
	sprite.scale = Vector2(-scale_value if bool(config.get("mirror_x", false)) else scale_value, -scale_value if bool(config.get("mirror_y", false)) else scale_value)
	sprite.modulate.a = clampf(float(config.get("opacity", 1.0)), 0.0, 1.0)
	var visual_size := texture.get_size() * scale_value
	sprite.position.y = _vertical_position(visual_size.y)
	add_child(sprite)
	return sprite


func _remove_exited(direction: float) -> void:
	for sprite: TextureRect in get_children():
		var width := sprite.size.x * absf(sprite.scale.x)
		if (direction < 0.0 and sprite.position.x + width < 0.0) or (direction > 0.0 and sprite.position.x > viewport_bounds.x):
			sprite.free()


func _fill_entry_edge(direction: float) -> void:
	if _finished and not bool(config.get("loop", true)):
		return
	if direction < 0.0:
		var right_edge := 0.0
		for sprite: TextureRect in get_children(): right_edge = maxf(right_edge, sprite.position.x + sprite.size.x * absf(sprite.scale.x))
		while right_edge < viewport_bounds.x + _estimated_width():
			var next := _create_next_sprite()
			if next == null: break
			next.position.x = right_edge + _join_offset()
			right_edge = next.position.x + next.size.x * absf(next.scale.x)
	else:
		var left_edge := viewport_bounds.x
		for sprite: TextureRect in get_children(): left_edge = minf(left_edge, sprite.position.x)
		while left_edge > -_estimated_width():
			var next := _create_next_sprite()
			if next == null: break
			next.position.x = left_edge - next.size.x * absf(next.scale.x) - _join_offset()
			left_edge = next.position.x


func _advance(sprite: TextureRect) -> float:
	return maxf(1.0, sprite.size.x * absf(sprite.scale.x) + _join_offset())


func _join_offset() -> float:
	return float(config.get("spacing", 0.0)) - maxf(0.0, float(config.get("transition_overlap", 0.0)))


func _estimated_width() -> float:
	return maxf(1.0, textures[0].get_width() * maxf(0.01, float(config.get("scale", 1.0)))) if not textures.is_empty() else 1.0


func _vertical_position(height: float) -> float:
	var anchor := String(config.get("anchor", "SCREEN_CENTER"))
	var y := (viewport_bounds.y - height) * 0.5
	if anchor == "SCREEN_TOP": y = 20.0
	elif anchor == "SCREEN_BOTTOM": y = viewport_bounds.y - height - 20.0
	return y + float(config.get("y_offset", 0.0))
