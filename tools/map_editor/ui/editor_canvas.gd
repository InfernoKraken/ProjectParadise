class_name EditorCanvas
extends Control

signal object_selected(object_id: String)
signal object_activated(object_id: String)
signal object_moved(object_id: String, old_position: Vector3, new_position: Vector3)
signal object_resized(object_id: String, old_size: Vector3, new_size: Vector3)

var objects: Array[Dictionary] = []
var selected_id := ""
var map_size := Vector2(20, 20)
var grid_size := 1.0
var snapping := true
var zoom := 1.0
var pan := Vector2.ZERO
var pixels_per_unit := 32.0
var texture_cache: Dictionary = {}
var project_root := ""
var dragging := false
var resizing := false
var panning := false
var drag_start_mouse := Vector2.ZERO
var drag_start_position := Vector3.ZERO
var drag_start_size := Vector3.ZERO

func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	set_process_unhandled_key_input(true)

func set_document_objects(new_objects: Array[Dictionary], new_map_size: Vector2) -> void:
	objects = new_objects
	map_size = new_map_size
	if not objects.any(func(o): return String(o.id) == selected_id): selected_id = ""
	queue_redraw()

func select_object(id: String) -> void:
	selected_id = id
	if not id.is_empty(): grab_focus()
	queue_redraw()
	object_selected.emit(id)

func frame_all() -> void:
	zoom = clampf(minf(size.x / maxf(map_size.x * pixels_per_unit, 1.0), size.y / maxf(map_size.y * pixels_per_unit, 1.0)) * 0.82, 0.2, 4.0)
	pan = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#151a20"))
	_draw_grid()
	var bounds := Rect2(world_to_screen(Vector2(-map_size.x * 0.5, -map_size.y * 0.5)), Vector2(map_size.x, map_size.y) * pixels_per_unit * zoom)
	draw_rect(bounds, Color("#29433288"), true)
	draw_rect(bounds, Color("#7dab85"), false, 2.0)
	var draw_objects:=objects.duplicate()
	draw_objects.sort_custom(func(a,b):return _draw_rank(a)<_draw_rank(b))
	for object in draw_objects: _draw_object(object)
	draw_string(get_theme_default_font(), Vector2(size.x * 0.5 - 24, 20), "N  (-Z)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#b8c9d8"))

func _draw_grid() -> void:
	var spacing := grid_size * pixels_per_unit * zoom
	if spacing < 4.0: return
	var center := size * 0.5 + pan
	var x := fposmod(center.x, spacing)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("#34404b"), 1.0); x += spacing
	var y := fposmod(center.y, spacing)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("#34404b"), 1.0); y += spacing
	draw_line(Vector2(center.x, 0), Vector2(center.x, size.y), Color("#6c8296"), 1.5)
	draw_line(Vector2(0, center.y), Vector2(size.x, center.y), Color("#6c8296"), 1.5)

func _draw_object(object: Dictionary) -> void:
	var position: Vector3 = object.position
	var center := world_to_screen(Vector2(position.x, position.z))
	var footprint: Vector2 = object.get("footprint", Vector2(0.8, 0.8))
	if object.get("shape", "point") == "rectangle": footprint = Vector2(object.size.x, object.size.z)
	var rect := Rect2(center - footprint * pixels_per_unit * zoom * 0.5, footprint * pixels_per_unit * zoom)
	var color: Color = object.get("color", Color("#dce6ee"))
	if object.get("shape", "point") == "rectangle":
		var texture := _texture_for(String(object.get("texture", "")))
		if texture != null:
			# Gameplay repeats block textures across the serialized X/Z dimensions.
			# Tile the same source art here so large interior floors and thin wall
			# strips read like their in-game counterparts instead of flat overlays.
			draw_texture_rect(texture, rect, true, Color(1,1,1,0.92))
			draw_rect(rect, Color(color, 0.12), true)
		else:
			draw_rect(rect, Color(color, 0.32), true)
		draw_rect(rect, color, false, 2.0)
	else:
		var texture := _texture_for(String(object.get("texture", "")))
		if texture != null:
			var aspect := float(texture.get_width()) / maxf(float(texture.get_height()), 1.0)
			var draw_size: Vector2
			if object.has("display_width"):
				var display_width := float(object.display_width)
				draw_size = Vector2(display_width, display_width / aspect) * pixels_per_unit * zoom
			else:
				var display_height := float(object.get("display_height", footprint.y))
				draw_size = Vector2(display_height * aspect, display_height) * pixels_per_unit * zoom
			draw_texture_rect(texture, Rect2(center - Vector2(draw_size.x * 0.5, draw_size.y), draw_size), false, Color(1,1,1,0.9))
		else:
			draw_circle(center, maxf(7.0, footprint.x * pixels_per_unit * zoom * 0.35), Color(color, 0.8))
			draw_line(center + Vector2(-6, 0), center + Vector2(6, 0), Color.WHITE, 2)
			draw_line(center + Vector2(0, -6), center + Vector2(0, 6), Color.WHITE, 2)
		draw_rect(rect, Color(color, 0.18), true)
		draw_rect(rect, color, false, 1.0)
	if String(object.id) == selected_id:
		draw_rect(rect.grow(3), Color("#ffe16b"), false, 3.0)
		if object.get("shape", "point") == "rectangle": draw_rect(Rect2(rect.end - Vector2(10,10), Vector2(10,10)), Color("#ffe16b"), true)
	var label := String(object.get("label", object.get("field", "object")))
	draw_string(get_theme_default_font(), center + Vector2(7, -7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _texture_for(relative_path: String) -> Texture2D:
	if relative_path.is_empty() or project_root.is_empty(): return null
	if texture_cache.has(relative_path): return texture_cache[relative_path]
	var image := Image.load_from_file(project_root.path_join(relative_path))
	if image == null or image.is_empty(): texture_cache[relative_path] = null; return null
	var texture := ImageTexture.create_from_image(image)
	texture_cache[relative_path] = texture
	return texture

func _draw_rank(object:Dictionary)->int:
	if String(object.get("field",""))=="floor_blocks":return 0
	if String(object.get("field",""))=="wall_blocks":return 1
	if object.get("shape","")=="rectangle":return 2
	if String(object.get("field",""))=="furnishings":return 3
	return 4

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: _zoom_at(event.position, 1.15); accept_event(); return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: _zoom_at(event.position, 1.0 / 1.15); accept_event(); return
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			panning = event.pressed; drag_start_mouse = event.position; accept_event(); return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit := _hit_test(event.position)
				if hit.is_empty(): select_object(""); return
				select_object(String(hit.id))
				if event.double_click:
					object_activated.emit(String(hit.id)); accept_event(); return
				if bool(hit.get("locked",false)):
					accept_event(); return
				drag_start_mouse = event.position; drag_start_position = hit.position; drag_start_size = hit.size
				var rect := _screen_rect(hit)
				resizing = hit.get("shape", "point") == "rectangle" and Rect2(rect.end - Vector2(16,16), Vector2(16,16)).has_point(event.position)
				dragging = not resizing
			else:
				if dragging:
					var object := _selected(); if not object.is_empty() and object.position != drag_start_position: object_moved.emit(selected_id, drag_start_position, object.position)
				if resizing:
					var object := _selected(); if not object.is_empty() and object.size != drag_start_size: object_resized.emit(selected_id, drag_start_size, object.size)
				dragging = false; resizing = false
			accept_event()
	elif event is InputEventMouseMotion:
		if panning:
			pan += event.relative; queue_redraw(); accept_event()
		elif dragging:
			var object := _selected()
			if not object.is_empty():
				var delta := Vector2(event.position.x - drag_start_mouse.x, event.position.y - drag_start_mouse.y) / (pixels_per_unit * zoom)
				var pos := drag_start_position + Vector3(delta.x, 0, delta.y)
				if snapping: pos = Vector3(snappedf(pos.x, grid_size), pos.y, snappedf(pos.z, grid_size))
				object.position = pos; queue_redraw()
		elif resizing:
			var object := _selected()
			if not object.is_empty():
				var delta := Vector2(event.position.x - drag_start_mouse.x, event.position.y - drag_start_mouse.y) / (pixels_per_unit * zoom)
				var new_size := Vector3(maxf(grid_size, drag_start_size.x + delta.x * 2.0), drag_start_size.y, maxf(grid_size, drag_start_size.z + delta.y * 2.0))
				if snapping: new_size = Vector3(snappedf(new_size.x, grid_size), new_size.y, snappedf(new_size.z, grid_size))
				object.size = new_size; queue_redraw()

func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_position)
	zoom = clampf(zoom * factor, 0.15, 6.0)
	var after := screen_to_world(screen_position)
	pan += (after - before) * pixels_per_unit * zoom
	queue_redraw()

func world_to_screen(world: Vector2) -> Vector2:
	# The editable plane is world X/Z. Godot gameplay treats negative Z as
	# north/up, so screen Y must increase with Z (not with -Z).
	return size * 0.5 + pan + Vector2(world.x, world.y) * pixels_per_unit * zoom

func screen_to_world(screen: Vector2) -> Vector2:
	var value := (screen - size * 0.5 - pan) / (pixels_per_unit * zoom)
	return Vector2(value.x, value.y)

func _screen_rect(object: Dictionary) -> Rect2:
	var fp: Vector2 = object.get("footprint", Vector2(0.8,0.8))
	if object.get("shape", "point") == "rectangle": fp = Vector2(object.size.x, object.size.z)
	return Rect2(world_to_screen(Vector2(object.position.x, object.position.z)) - fp * pixels_per_unit * zoom * 0.5, fp * pixels_per_unit * zoom)

func _hit_test(screen_position: Vector2) -> Dictionary:
	var hit_objects:=objects.duplicate()
	hit_objects.sort_custom(func(a,b):return _draw_rank(a)>_draw_rank(b))
	for object in hit_objects:
		if _screen_rect(object).grow(5).has_point(screen_position): return object
	return {}

func _selected() -> Dictionary:
	for object in objects:
		if String(object.id) == selected_id: return object
	return {}
