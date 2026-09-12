class_name BattleSceneAnchorCanvas
extends Control

signal document_changed(before: Dictionary)

const Repository := preload("res://battle/battle_scene_anchor_repository.gd")

var background: Texture2D
var document: Dictionary = {}
var selected_anchor := "BACKGROUND_CENTER"
var dragging := false
var resizing := false


func _ready() -> void:
	custom_minimum_size = Vector2(700, 620)
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func set_document(texture: Texture2D, value: Dictionary) -> void:
	background = texture
	document = value.duplicate(true)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("20242b"))
	if background == null:
		return
	var image_rect := _background_rect()
	draw_texture_rect(background, image_rect, false)
	for anchor_name: String in Repository.POINT_ANCHORS:
		var point := _point_to_screen(_point(anchor_name), image_rect)
		var color := Color("56e0ff") if selected_anchor == anchor_name else Color("ffdf5d")
		draw_circle(point, 7, Color(color, 0.35))
		draw_arc(point, 8, 0, TAU, 20, color, 2)
		draw_string(ThemeDB.fallback_font, point + Vector2(12, -8), anchor_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
	for region_name: String in Repository.REGION_ANCHORS:
		var region := _region_to_screen(_region(region_name), image_rect)
		var color := Color("56e0ff") if selected_anchor == region_name else Color("ff9f5d")
		draw_rect(region, Color(color, 0.12), true)
		draw_rect(region, color, false, 2)
		draw_rect(Rect2(region.end - Vector2(6, 6), Vector2(12, 12)), color, true)
		draw_string(ThemeDB.fallback_font, region.position + Vector2(8, 20), region_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
	for viewport_name: String in Repository.VIEWPORT_ANCHORS:
		var point := _viewport_point(viewport_name, image_rect)
		draw_circle(point, 4, Color(0.8, 0.85, 0.9, 0.7))
		draw_string(ThemeDB.fallback_font, point + Vector2(7, -5), "%s (auto)" % viewport_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 0.9, 0.8))


func _gui_input(event: InputEvent) -> void:
	if background == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _background_rect().has_point(event.position):
			document_changed.emit(document.duplicate(true))
			dragging = true
			if Repository.REGION_ANCHORS.has(selected_anchor):
				var shown := _region_to_screen(_region(selected_anchor), _background_rect())
				resizing = event.position.distance_to(shown.end) <= 18.0
			_apply_pointer(event.position)
		else:
			dragging = false
			resizing = false
	elif event is InputEventMouseMotion and dragging:
		_apply_pointer(event.position)


func _apply_pointer(screen_position: Vector2) -> void:
	var image_rect := _background_rect()
	var point := _screen_to_point(screen_position, image_rect)
	var reference := _reference_size()
	point = point.clamp(Vector2.ZERO, reference)
	if Repository.POINT_ANCHORS.has(selected_anchor):
		document.anchors[selected_anchor] = [roundi(point.x), roundi(point.y)]
	else:
		var region := _region(selected_anchor)
		if resizing:
			region.size = Vector2(maxf(1, point.x - region.position.x), maxf(1, point.y - region.position.y))
		else:
			region.position = (point - region.size * 0.5).clamp(Vector2.ZERO, reference - region.size)
		document.regions[selected_anchor] = {"x": roundi(region.position.x), "y": roundi(region.position.y), "width": roundi(region.size.x), "height": roundi(region.size.y)}
	queue_redraw()


func _background_rect() -> Rect2:
	var available := size - Vector2(32, 32)
	var reference := _reference_size()
	var scale_factor := minf(available.x / reference.x, available.y / reference.y)
	var draw_size := reference * scale_factor
	return Rect2((size - draw_size) * 0.5, draw_size)


func _reference_size() -> Vector2:
	var values: Array = document.get("reference_size", [960, 540])
	return Vector2(float(values[0]), float(values[1]))


func _point(name: String) -> Vector2:
	var values: Array = document.get("anchors", {}).get(name, [0, 0])
	return Vector2(float(values[0]), float(values[1]))


func _region(name: String) -> Rect2:
	var value: Dictionary = document.get("regions", {}).get(name, {})
	return Rect2(float(value.get("x", 0)), float(value.get("y", 0)), float(value.get("width", 1)), float(value.get("height", 1)))


func _point_to_screen(point: Vector2, image_rect: Rect2) -> Vector2:
	return image_rect.position + point * image_rect.size / _reference_size()


func _screen_to_point(point: Vector2, image_rect: Rect2) -> Vector2:
	return (point - image_rect.position) * _reference_size() / image_rect.size


func _region_to_screen(region: Rect2, image_rect: Rect2) -> Rect2:
	return Rect2(_point_to_screen(region.position, image_rect), region.size * image_rect.size / _reference_size())


func _viewport_point(name: String, image_rect: Rect2) -> Vector2:
	match name:
		"SCREEN_TOP": return Vector2(image_rect.get_center().x, image_rect.position.y + 20 * image_rect.size.y / _reference_size().y)
		"SCREEN_BOTTOM": return Vector2(image_rect.get_center().x, image_rect.end.y - 20 * image_rect.size.y / _reference_size().y)
		"SCREEN_LEFT": return Vector2(image_rect.position.x + 20 * image_rect.size.x / _reference_size().x, image_rect.get_center().y)
		"SCREEN_RIGHT": return Vector2(image_rect.end.x - 20 * image_rect.size.x / _reference_size().x, image_rect.get_center().y)
		_: return image_rect.get_center()
