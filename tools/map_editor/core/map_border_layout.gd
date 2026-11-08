extends RefCounted

const Bounds := preload("map_bounds.gd")
const SIDES := ["north", "south", "east", "west"]
const CORNER_PRIORITIES := ["north_south", "east_west"]
const MAX_DIMENSION := 128
const MAX_ART_SIZE := 64.0

static func depth(border: Dictionary, side: String) -> int:
	var legacy_key := "height" if horizontal(side) else "width"
	return _dimension(border.get("depth", border.get(legacy_key, 4)))

static func dimensions(map: Dictionary, side: String, border: Dictionary) -> Vector2i:
	var span := Bounds.rect(map).size
	var outward := depth(border, side)
	if horizontal(side): return Vector2i(maxi(1, ceili(span.x)), outward)
	return Vector2i(outward, maxi(1, ceili(span.y)))

static func repeat_dimensions(map: Dictionary, side: String, border: Dictionary) -> Vector2i:
	var result := dimensions(map, side, border)
	# Old maps can keep their shorter repeat until the side is edited.
	if not border.has("depth"):
		var axis := 0 if horizontal(side) else 1
		var legacy_key := "width" if axis == 0 else "height"
		if border.has(legacy_key): result[axis] = _dimension(border[legacy_key])
	return result

static func editable_cells(map: Dictionary, side: String, border: Dictionary) -> Dictionary:
	var value: Variant = border.get("cells")
	if not value is Dictionary: return {}
	var axis := 0 if horizontal(side) else 1
	var span := dimensions(map, side, border)[axis]
	var period := repeat_dimensions(map, side, border)[axis]
	if period >= span: return value
	var expanded := {}
	for key: String in value:
		var point := cell_position(key)
		if point[axis] < 0 or point[axis] >= period: continue
		while point[axis] < span:
			expanded[cell_key(point)] = value[key]
			point[axis] += period
	return expanded

static func _dimension(value: Variant) -> int:
	return clampi(int(value), 1, MAX_DIMENSION) if value is float or value is int else 4

static func definition(map: Dictionary, side: String) -> Dictionary:
	var borders: Variant = map.get("borders")
	var value: Variant = borders.get(side) if borders is Dictionary else null
	return value if value is Dictionary else {}

static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func cell_position(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))

static func horizontal(side: String) -> bool:
	return side == "north" or side == "south"

static func extent(map: Dictionary, side: String) -> float:
	var border := definition(map, side)
	if border.get("enabled") != true: return 0.0
	return depth(border, side)

static func has_enabled_border(map: Dictionary) -> bool:
	for side in SIDES:
		if extent(map, side) > 0: return true
	return false

static func corner_priority(map: Dictionary) -> String:
	return "east_west" if map.get("border_corner_priority") == "east_west" else "north_south"

# Only the priority pair extends into the corner wings.
static func region(map: Dictionary, bounds: Rect2, side: String) -> Rect2:
	var outward := extent(map, side)
	var horizontal_priority := corner_priority(map) == "north_south"
	var west := extent(map, "west") if horizontal_priority else 0.0
	var north := extent(map, "north") if not horizontal_priority else 0.0
	var width := bounds.size.x + west + (extent(map, "east") if horizontal_priority else 0.0)
	var height := bounds.size.y + north + (extent(map, "south") if not horizontal_priority else 0.0)
	match side:
		"north": return Rect2(bounds.position - Vector2(west, outward), Vector2(width, outward))
		"south": return Rect2(Vector2(bounds.position.x - west, bounds.end.y), Vector2(width, outward))
		"east": return Rect2(Vector2(bounds.end.x, bounds.position.y - north), Vector2(outward, height))
		"west": return Rect2(bounds.position - Vector2(outward, north), Vector2(outward, height))
	return Rect2()

static func repeat_origin(bounds: Rect2, strip: Rect2, side: String) -> Vector2:
	return Vector2(bounds.position.x, strip.position.y) if horizontal(side) else Vector2(strip.position.x, bounds.position.y)

# Canonical terrain keeps only whole tiles centered at integer coordinates.
# Carry the adjacent border tile across the leftover fraction at the map edge.
static func seam_region(map: Dictionary, bounds: Rect2, side: String) -> Rect2:
	var first := (bounds.position + Vector2.ONE * 0.5).ceil() - Vector2.ONE * 0.5
	var last := (bounds.end - Vector2.ONE * 0.5).floor() + Vector2.ONE * 0.5
	if first.x >= last.x or first.y >= last.y: return Rect2()
	var span_start := bounds.position
	var span_end := bounds.end
	if corner_priority(map) == "north_south" and not horizontal(side):
		if extent(map, "north") > 0: span_start.y = first.y
		if extent(map, "south") > 0: span_end.y = last.y
	if corner_priority(map) == "east_west" and horizontal(side):
		if extent(map, "west") > 0: span_start.x = first.x
		if extent(map, "east") > 0: span_end.x = last.x
	match side:
		"north": return Rect2(span_start, Vector2(span_end.x - span_start.x, first.y - bounds.position.y))
		"south": return Rect2(Vector2(span_start.x, last.y), Vector2(span_end.x - span_start.x, bounds.end.y - last.y))
		"west": return Rect2(span_start, Vector2(first.x - bounds.position.x, span_end.y - span_start.y))
		"east": return Rect2(Vector2(last.x, span_start.y), Vector2(bounds.end.x - last.x, span_end.y - span_start.y))
	return Rect2()

static func seam_patch(clipped: Rect2, seam: Rect2, along_x: bool) -> Rect2:
	if not seam.has_area() or not clipped.intersects(seam, true): return Rect2()
	if along_x:
		return seam.intersection(Rect2(clipped.position.x, seam.position.y, clipped.size.x, seam.size.y))
	return seam.intersection(Rect2(seam.position.x, clipped.position.y, seam.size.x, clipped.size.y))

static func building_footprint(art: Dictionary) -> Vector2:
	return _art_vector(art, "footprint")

static func art_anchor(center: Vector2, art: Dictionary) -> Vector2:
	return center + _art_vector(art, "anchor_offset")

static func fits_building(anchor: Vector2, footprint: Vector2, bounds: Rect2) -> bool:
	return bounds.grow(0.001).encloses(Rect2(anchor - Vector2(footprint.x * 0.5, footprint.y), footprint))

static func _art_vector(art: Dictionary, field: String) -> Vector2:
	var value: Variant = art.get(field)
	if value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

static func tile_window(rect: Rect2, origin: Vector2) -> Rect2i:
	var first := Vector2i((rect.position - origin).floor())
	var end := Vector2i((rect.end - origin).ceil())
	return Rect2i(first, end - first)

static func art_size(art: Dictionary) -> Vector2:
	var size: Variant = art.get("size", [1, 1])
	if not size is Array or size.size() != 2: return Vector2.ONE
	if not (size[0] is float or size[0] is int) or not (size[1] is float or size[1] is int):
		return Vector2.ONE
	return Vector2(float(size[0]), float(size[1])).clamp(Vector2.ONE * 0.05, Vector2.ONE * MAX_ART_SIZE)

static func texture_path(art: Dictionary) -> String:
	var path: Variant = art.get("texture")
	if not path is String or not path.begins_with("assets/") or path.simplify_path() != path:
		return ""
	return path if path.get_extension().to_lower() in ["png", "webp", "jpg", "jpeg"] else ""

static func animation_spec(id: String, definitions: Dictionary) -> Dictionary:
	# Keep the gate's visual cycle without instantiating its gameplay scene.
	if id == "canal_lock":
		return {"paths": [0, 1, 2, 1, 0].map(func(frame): return "assets/animations/canal_locks_main_frame_%d.png" % frame), "duration": 1.0}
	var record: Variant = definitions.get(id)
	if not record is Dictionary or not id.is_valid_identifier(): return {}
	var count := int(record.get("frame_count", 0))
	var duration := float(record.get("frame_duration", 0))
	if count < 2 or count > 256 or duration <= 0.0: return {}
	var paths: Array[String] = []
	for index in count:
		paths.append("assets/overworld/anim/%s_%02d.png" % [id, index])
	return {"paths": paths, "duration": duration}
