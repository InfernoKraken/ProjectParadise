extends RefCounted

static func make(source: MeshInstance3D, strip: Rect2, billboard: bool, clip: bool, priority: int) -> MeshInstance2D:
	var arrays := source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var points := PackedVector2Array()
	for vertex in vertices:
		points.append(Vector2(vertex.x, -vertex.y if billboard else vertex.z))
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var elevation := 0.0 if billboard else vertices[0].y
	# Only decorative quads need clipping. Terrain triangles are already clipped.
	if clip:
		var anchor := Vector2(source.position.x, source.position.z)
		var bounds := Rect2(strip.position - anchor, strip.size)
		if billboard:
			var top := minf(points[0].y, minf(points[1].y, minf(points[2].y, points[5].y)))
			var bottom := maxf(points[0].y, maxf(points[1].y, maxf(points[2].y, points[5].y)))
			bounds = Rect2(bounds.position.x, top, bounds.size.x, bottom - top)
		var quad := PackedVector2Array([points[0], points[1], points[2], points[5]])
		var mask := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
		var uv_transform := Transform2D(quad[1] - quad[0], quad[3] - quad[0], quad[0]).affine_inverse()
		points.clear()
		uvs.clear()
		for polygon in Geometry2D.intersect_polygons(quad, mask):
			for index in Geometry2D.triangulate_polygon(polygon):
				var point: Vector2 = polygon[index]
				points.append(point)
				uvs.append(uv_transform * point)
	if points.is_empty(): return null
	var mesh_arrays := []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = points
	mesh_arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	var item := MeshInstance2D.new()
	item.mesh = mesh
	item.texture = source.material_override.get_shader_parameter("albedo_texture")
	item.z_index = priority
	item.set_meta("anchor", source.position + Vector3.UP * elevation)
	item.set_meta("billboard", billboard)
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	item.use_parent_material = true
	return item

static func project(item: MeshInstance2D, camera: Camera3D) -> void:
	var anchor: Vector3 = item.get_meta("anchor")
	var billboard: bool = item.get_meta("billboard")
	var basis := camera.global_basis
	var right := basis.x if billboard else Vector3.RIGHT
	var down := -basis.y if billboard else Vector3.BACK
	var position := camera.unproject_position(anchor)
	item.transform = Transform2D(camera.unproject_position(anchor + right) - position,
		camera.unproject_position(anchor + down) - position, position)
