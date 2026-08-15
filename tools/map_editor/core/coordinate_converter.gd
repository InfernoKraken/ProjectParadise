class_name MapCoordinateConverter
extends RefCounted

static func local_to_world(local_position: Vector3, origin: Vector3) -> Vector3:
	return origin + local_position

static func world_to_local(world_position: Vector3, origin: Vector3) -> Vector3:
	return world_position - origin

static func world_xz_to_canvas(world_position: Vector3, pixels_per_unit: float, canvas_origin: Vector2) -> Vector2:
	return canvas_origin + Vector2(world_position.x, world_position.z) * pixels_per_unit

static func canvas_to_world_xz(canvas_position: Vector2, pixels_per_unit: float, canvas_origin: Vector2, y := 0.0) -> Vector3:
	var relative := (canvas_position - canvas_origin) / pixels_per_unit
	return Vector3(relative.x, y, relative.y)
