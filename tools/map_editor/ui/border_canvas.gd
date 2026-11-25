extends "res://ui/editor_canvas.gd"

signal element_move_requested(source: String, point: Vector2, layer: String)

signal art_point_changed(point: Vector2, erase: bool)

var cells: Dictionary = {}
var precise_art := false
var move_mode := false
var _drag_key := ""
var _drag_origin := Vector2.ZERO
var _drag_mouse := Vector2.ZERO
var _drag_point := Vector2.ZERO

func cancel_move() -> void:
	_drag_key = ""
	queue_redraw()

func _pick_art(screen: Vector2) -> String:
	var keys: Array = cells.keys().filter(func(key): return cells[key] is Dictionary and cells[key].get("art") is Dictionary)
	keys.sort_custom(func(a, b): return BorderLayout.art_priority(cells[a].art) < BorderLayout.art_priority(cells[b].art))
	keys.reverse()
	var strip := Rect2(map_center - map_size * 0.5, map_size)
	for key: String in keys:
		var art: Dictionary = cells[key].art
		var anchor := BorderLayout.art_anchor(Vector2(BorderLayout.cell_position(key)), art)
		if not strip.has_point(anchor): continue
		var dimensions := BorderLayout.art_size(art) * pixels_per_unit * zoom
		var flat: bool = art.get("flat") == true
		var offset := dimensions * Vector2(-0.5, -0.5 if flat else -1.0)
		var transform := Transform2D(0, _ground_projection() if flat else Vector2.ONE, 0, world_to_screen(anchor)) * Transform2D(deg_to_rad(float(art.get("rotation", 0))), Vector2.ZERO)
		var local := transform.affine_inverse() * screen
		if not Rect2(offset, dimensions).has_point(local): continue
		var texture := visual_texture(BorderLayout.texture_path(art), String(art.get("animation", "")))
		if texture != null:
			var image := texture.get_image()
			if image != null and not image.is_empty():
				var pixel := Vector2i((local - offset) / dimensions * Vector2(image.get_size()))
				if image.get_pixelv(pixel).a < 0.1: continue
		return key
	return ""

func _gui_input(event: InputEvent) -> void:
	if not move_mode:
		super._gui_input(event)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_move(); accept_event(); return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_mouse = screen_to_world(event.position)
			_drag_key = _pick_art(event.position) if precise_art else BorderLayout.cell_key(Vector2i(_drag_mouse.round()))
			var layer := "art" if precise_art else "terrain"
			if not cells.get(_drag_key, {}).has(layer): _drag_key = ""
			if not _drag_key.is_empty():
				_drag_origin = Vector2(BorderLayout.cell_position(_drag_key))
				if precise_art: _drag_origin = BorderLayout.art_anchor(_drag_origin, cells[_drag_key].art)
				_drag_point = _drag_origin
		else:
			if not _drag_key.is_empty() and not _drag_point.is_equal_approx(_drag_origin):
				element_move_requested.emit(_drag_key, _drag_point, "art" if precise_art else "terrain")
			cancel_move()
		accept_event(); return
	if event is InputEventMouseMotion and not _drag_key.is_empty():
		_drag_point = _drag_origin + screen_to_world(event.position) - _drag_mouse
		if precise_art:
			if snapping: _drag_point = _drag_point.snapped(Vector2.ONE * grid_size)
		else: _drag_point = _drag_point.round()
		queue_redraw(); accept_event(); return
	super._gui_input(event)

var _last_art_point := Vector2.INF

func _emit_brush_cell(screen_position: Vector2) -> void:
	if not precise_art:
		super._emit_brush_cell(screen_position)
		return
	var point := screen_to_world(screen_position)
	if snapping: point = point.snapped(Vector2.ONE * grid_size)
	if point == _last_art_point: return
	_last_art_point = point
	art_point_changed.emit(point, terrain_brush_mode == "erase")


func show_border(dimensions: Vector2i, new_cells: Dictionary, frame: bool = false) -> void:
	cells = new_cells
	set_document_objects([], Vector2(dimensions), (Vector2(dimensions) - Vector2.ONE) * 0.5)
	if frame: frame_all()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#151a20"))
	var bounds := _map_bounds_rect()
	draw_rect(bounds, Color("#233037"))
	var displayed := cells
	if not _drag_key.is_empty() and precise_art:
		displayed = cells.duplicate(true)
		var offset := _drag_point - Vector2(BorderLayout.cell_position(_drag_key))
		displayed[_drag_key].art["anchor_offset"] = [offset.x, offset.y]
	_draw_border_strip(Rect2(map_center - map_size * 0.5, map_size), Vector2.ONE * -0.5, Vector2i(map_size), displayed)
	if not placement_preview:
		var spacing := grid_size * pixels_per_unit * zoom * _ground_projection()
		if minf(spacing.x, spacing.y) >= 4:
			var world_bounds := Rect2(map_center - map_size * 0.5, map_size)
			for x in range(ceili(world_bounds.position.x / grid_size), floori(world_bounds.end.x / grid_size) + 1):
				var pixel := world_to_screen(Vector2(x * grid_size, 0)).x
				draw_line(Vector2(pixel, bounds.position.y), Vector2(pixel, bounds.end.y), Color("#93a8ad55"))
			for z in range(ceili(world_bounds.position.y / grid_size), floori(world_bounds.end.y / grid_size) + 1):
				var pixel := world_to_screen(Vector2(0, z * grid_size)).y
				draw_line(Vector2(bounds.position.x, pixel), Vector2(bounds.end.x, pixel), Color("#93a8ad55"))
		draw_rect(bounds, Color("#7dab85"), false, 2)
