extends "res://ui/editor_canvas.gd"

var cells: Dictionary = {}

func show_border(dimensions: Vector2i, new_cells: Dictionary, frame: bool = false) -> void:
	cells = new_cells
	set_document_objects([], Vector2(dimensions), (Vector2(dimensions) - Vector2.ONE) * 0.5)
	if frame: frame_all()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#151a20"))
	var bounds := _map_bounds_rect()
	draw_rect(bounds, Color("#233037"))
	_draw_border_strip(Rect2(map_center - map_size * 0.5, map_size), Vector2.ONE * -0.5, Vector2i(map_size), cells)
	var tile_size := pixels_per_unit * zoom * _ground_projection()
	if not placement_preview:
		var spacing := tile_size.x
		if spacing >= 4:
			for x in range(int(map_size.x) + 1):
				var pixel := bounds.position.x + x * spacing
				draw_line(Vector2(pixel, bounds.position.y), Vector2(pixel, bounds.end.y), Color("#93a8ad55"))
			for z in range(int(map_size.y) + 1):
				var pixel := bounds.position.y + z * spacing
				draw_line(Vector2(bounds.position.x, pixel), Vector2(bounds.end.x, pixel), Color("#93a8ad55"))
		draw_rect(bounds, Color("#7dab85"), false, 2)
