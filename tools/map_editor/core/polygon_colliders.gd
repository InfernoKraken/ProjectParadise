extends RefCounted

static func read(collision: Variant) -> Array:
	if not collision is Dictionary:
		return []
	match collision.get("type", ""):
		"polygon":
			return [collision.duplicate(true)]
		"polygons":
			var polygons: Variant = collision.get("polygons", [])
			if polygons is Array:
				return polygons.filter(func(polygon): return polygon is Dictionary and polygon.get("type") == "polygon").duplicate(true)
	return []

static func reference_size(polygon: Dictionary, fallback: Vector2) -> Vector2:
	var raw: Variant = polygon.get("reference_size")
	if raw is Array and raw.size() == 2 and (raw[0] is int or raw[0] is float) and (raw[1] is int or raw[1] is float):
		var reference := Vector2(float(raw[0]), float(raw[1]))
		if reference.is_finite() and reference.x > 0 and reference.y > 0:
			return reference
	return fallback

static func write(metadata: Dictionary, polygons: Array) -> void:
	match polygons.size():
		0:
			metadata.erase("collision")
		1:
			metadata["collision"] = polygons[0]
		_:
			metadata["collision"] = {"type": "polygons", "polygons": polygons}
