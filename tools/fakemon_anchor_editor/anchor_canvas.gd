class_name FakemonAnchorCanvas
extends Control

signal anchor_changed(anchor_name: String, position: Vector2i)

var source_image: Image
var source_texture: ImageTexture
var anchors: Dictionary = {}
var selected_anchor := "origin"
var dragging := false
var processed_preview := false
var preview_image: Image
var preview_anchors: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(700, 620)
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func set_document(image: Image, new_anchors: Dictionary) -> void:
	source_image = image
	source_texture = ImageTexture.create_from_image(image)
	anchors = new_anchors.duplicate(true)
	processed_preview = false
	queue_redraw()


func set_preview(image: Image, points: Dictionary) -> void:
	preview_image = image
	preview_anchors = points.duplicate(true)
	processed_preview = true
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("20242b"))
	var image := preview_image if processed_preview else source_image
	if image == null:
		draw_string(ThemeDB.fallback_font, Vector2(30, 50), "Select a Fakemon sprite to begin.", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		return
	var texture := ImageTexture.create_from_image(image) if processed_preview else source_texture
	var rect := _image_rect(image)
	draw_texture_rect(texture, rect, false)
	var points := preview_anchors if processed_preview else anchors
	for anchor_name: String in points:
		var point: Vector2 = points[anchor_name]
		var screen_point := rect.position + point * rect.size / Vector2(image.get_size())
		var color := Color("56e0ff") if anchor_name == selected_anchor else Color("ffdf5d")
		draw_circle(screen_point, 7.0, Color(color, 0.3))
		draw_arc(screen_point, 8.0, 0, TAU, 20, color, 2.0)
		draw_line(screen_point - Vector2(11, 0), screen_point + Vector2(11, 0), color, 1.0)
		draw_line(screen_point - Vector2(0, 11), screen_point + Vector2(0, 11), color, 1.0)
		draw_string(ThemeDB.fallback_font, screen_point + Vector2(12, -8), anchor_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)


func _gui_input(event: InputEvent) -> void:
	if processed_preview or source_image == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging:
			_place(event.position)
	elif event is InputEventMouseMotion and dragging:
		_place(event.position)


func _place(mouse_position: Vector2) -> void:
	var rect := _image_rect(source_image)
	if not rect.has_point(mouse_position):
		return
	var normalized := (mouse_position - rect.position) / rect.size
	var point := Vector2i(normalized * Vector2(source_image.get_size()))
	point.x = clampi(point.x, 0, source_image.get_width() - 1)
	point.y = clampi(point.y, 0, source_image.get_height() - 1)
	anchors[selected_anchor] = point
	anchor_changed.emit(selected_anchor, point)
	queue_redraw()


func _image_rect(image: Image) -> Rect2:
	var available := size - Vector2(32, 32)
	var scale_factor := minf(available.x / image.get_width(), available.y / image.get_height())
	var draw_size := Vector2(image.get_size()) * scale_factor
	return Rect2((size - draw_size) * 0.5, draw_size)
