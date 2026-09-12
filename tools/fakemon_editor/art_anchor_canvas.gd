class_name ArtAnchorCanvas
extends Control

signal anchor_changed(name: String, point: Vector2i)

var image: Image
var texture: ImageTexture
var anchors: Dictionary = {}
var selected := "origin"
var dragging := false

func _ready() -> void:
	custom_minimum_size = Vector2(620, 420)
	mouse_default_cursor_shape = Control.CURSOR_CROSS

func set_document(source: Image, points: Dictionary) -> void:
	image = source
	texture = ImageTexture.create_from_image(source) if source != null and not source.is_empty() else null
	anchors = points.duplicate(true)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("20242b"))
	if image == null or image.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(24, 42), "Add a Player or Wild battle image to place anchors.", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		return
	var rect := _image_rect()
	draw_texture_rect(texture, rect, false)
	for name: String in anchors:
		var point: Vector2 = anchors[name]
		var screen := rect.position + point * rect.size / Vector2(image.get_size())
		var color := Color("56e0ff") if name == selected else Color("ffdf5d")
		draw_circle(screen, 7, Color(color, 0.3)); draw_arc(screen, 8, 0, TAU, 20, color, 2)
		draw_line(screen-Vector2(11,0), screen+Vector2(11,0), color); draw_line(screen-Vector2(0,11), screen+Vector2(0,11), color)
		draw_string(ThemeDB.fallback_font, screen+Vector2(12,-7), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

func _gui_input(event: InputEvent) -> void:
	if image == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging: _place(event.position)
	elif event is InputEventMouseMotion and dragging: _place(event.position)

func _place(mouse: Vector2) -> void:
	var rect := _image_rect()
	if not rect.has_point(mouse): return
	var point := Vector2i((mouse-rect.position)/rect.size*Vector2(image.get_size()))
	point.x=clampi(point.x,0,image.get_width()-1); point.y=clampi(point.y,0,image.get_height()-1)
	anchors[selected]=point; anchor_changed.emit(selected,point); queue_redraw()

func _image_rect() -> Rect2:
	var available:=size-Vector2(24,24); var scale:=minf(available.x/image.get_width(),available.y/image.get_height())
	var draw_size:=Vector2(image.get_size())*scale; return Rect2((size-draw_size)*0.5,draw_size)
