extends SceneTree

const Layout := preload("res://tools/map_editor/core/map_border_layout.gd")
const Bounds := preload("res://tools/map_editor/core/map_bounds.gd")
const Renderer := preload("res://world/map_border_renderer.gd")

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): push_error("Border runtime test timed out"); quit(2))
	call_deferred("_test")

func _test() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 35
	root.add_child(camera)
	camera.current = true
	var origin := Vector3(100, 0, 200)
	camera.position = origin + Vector3(0, 22, 22)
	camera.look_at(origin)
	var renderer := Renderer.new()
	root.add_child(renderer)
	var map := {"size": [8.5, 7.25], "bounds_center": [0.75, 1.25], "borders": {}}
	for i in 4:
		var cells := {}
		for z in i + 3:
			for x in i + 2:
				var terrain: String = ["water", "sand", "mud", "stone"][i]
				if i == 0 and x == 1: terrain = "sand"
				cells[Layout.cell_key(Vector2i(x, z))] = {"terrain": terrain}
		map.borders[Layout.SIDES[i]] = {"enabled": true, "width": i + 2, "height": i + 3, "cells": cells}
	map.borders.north.cells["0,0"]["art"] = {
		"texture": "assets/animations/canal_locks_main_frame_0.png", "animation": "canal_lock",
		"size": [2, 3], "rotation": 30, "collision": {"shape": "box"}, "script": "unused"}
	renderer.configure(map, origin, 3)
	renderer.update_view(camera, null)
	var bounds := Bounds.rect(map)
	bounds.position += Vector2(origin.x, origin.z)
	_verify_coverage(renderer, map, bounds)
	var seam_map := map.duplicate(true)
	seam_map["_terrain_grid"] = {Vector2i.ZERO: "forest_floor"}
	seam_map.borders.north.cells["1,2"].art = {"texture": "assets/overworld/citybuilding_00.png",
		"size": [6, 7], "footprint": [2, 3], "anchor_offset": [0, 0.5]}
	renderer.configure(seam_map, origin, 3)
	renderer.update_view(camera, null)
	var north_seam := Layout.seam_region(seam_map, Bounds.rect(seam_map), "north")
	north_seam.position += Vector2(origin.x, origin.z)
	assert(north_seam.has_area())
	var water_meshes := renderer.get_node("North").get_children().filter(func(node): return node.get_meta("border_terrain", "") == "water")
	assert(water_meshes.any(func(node): return is_equal_approx(node.mesh.get_aabb().end.z, north_seam.end.y)))
	var buildings := renderer.get_node("North").get_children().filter(func(node): return node.get_meta("border_art", "").ends_with("citybuilding_00.png"))
	assert(not buildings.is_empty())
	assert(buildings.all(func(node): return not node.material_override.get_shader_parameter("clip_to_border")))
	renderer.configure(map, origin, 3)
	renderer.update_view(camera, null)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var pixel_scale := Vector2(image.get_size()) / root.get_visible_rect().size
		var south := camera.unproject_position(Vector3(bounds.get_center().x, 0.001, bounds.end.y + 2))
		var outside := camera.unproject_position(Vector3(bounds.get_center().x, 0.001, bounds.end.y + 8))
		assert(image.get_pixelv(Vector2i(south * pixel_scale)) != image.get_pixelv(Vector2i(outside * pixel_scale)))
	var water: AnimatedTexture
	var decoration_count := 0
	for mesh in renderer.find_children("*", "MeshInstance3D", true, false):
		assert(mesh.layers == 4 and mesh.get_script() == null)
		var texture: Texture2D = mesh.material_override.get_shader_parameter("albedo_texture")
		if mesh.get_meta("border_terrain", "") == "water": water = texture
		if mesh.has_meta("border_art"):
			decoration_count += 1
			assert(texture is AnimatedTexture and texture.frames == 5)
	assert(decoration_count > 1)
	assert(renderer.find_children("*", "CollisionObject3D", true, false).is_empty())
	assert(water != null and water.frames == 4)
	OverworldTextureAnimation.update_visibility(camera, 3)
	var frame := water.current_frame
	OverworldTextureAnimation.advance(0.21)
	assert(water.current_frame != frame)
	map.border_corner_priority = "east_west"
	renderer.configure(map, origin, 3)
	renderer.update_view(camera, null)
	_verify_coverage(renderer, map, bounds)
	camera.position.x += 300
	renderer.update_view(camera, null)
	assert(renderer.find_children("*", "MeshInstance3D", true, false).is_empty())
	camera.position.x -= 300
	map.size = [11.5, 10.25]
	map.bounds_center = [2.25, -0.25]
	for side: String in Layout.SIDES:
		var definition: Dictionary = map.borders[side]
		definition.cells = Layout.editable_cells(map, side, definition)
		definition.depth = Layout.depth(definition, side)
		definition.erase("width")
		definition.erase("height")
	assert(Layout.repeat_dimensions(map, "north", map.borders.north) == Vector2i(12, 3))
	assert(Layout.repeat_dimensions(map, "east", map.borders.east) == Vector2i(4, 11))
	renderer.configure(map, origin, 3)
	renderer.update_view(camera, null)
	bounds = Bounds.rect(map)
	bounds.position += Vector2(origin.x, origin.z)
	_verify_coverage(renderer, map, bounds)
	map.borders.north.enabled = false
	renderer.configure(map, origin, 3)
	renderer.update_view(camera, null)
	assert(not renderer.has_node("North") and renderer.has_node("South"))
	renderer.configure({"size": [8, 8]}, origin, 3)
	assert(renderer.get_child_count() == 0)
	var game = load("res://world/main.gd").new()
	var npc := Area3D.new()
	var start := Vector3(bounds.end.x - 1, 0, bounds.get_center().y)
	assert(game._npc_playable_motion_fraction(npc, start, Vector3.RIGHT * 2) == 1.0)
	npc.set_meta("border_playable_bounds", bounds)
	var fraction: float = game._npc_playable_motion_fraction(npc, start, Vector3.RIGHT * 2)
	assert(fraction > 0 and fraction < 0.5)
	npc.free()
	game.camera = camera
	game.world = renderer
	map.origin = [origin.x, origin.y, origin.z]
	game.map_data = {"authored_maps": {"bordered": map, "plain": {"size": [8, 8]}}}
	game.active_authored_map_id = "bordered"
	game._update_map_borders(3)
	assert(game.map_border_renderer.has_node("South"))
	game.active_authored_map_id = "plain"
	game._update_map_borders(4)
	assert(game.map_border_renderer.get_child_count() == 0)
	game.free()
	print("MAP_BORDER_RUNTIME_PASSED")
	quit()

func _verify_coverage(renderer: Node3D, map: Dictionary, bounds: Rect2) -> void:
	var strips: Array[Rect2] = []
	for side in Layout.SIDES:
		var strip := Layout.region(map, bounds, side)
		for previous in strips: assert(not strip.intersects(previous))
		assert(not strip.intersects(bounds))
		strips.append(strip)
		var area := 0.0
		for node in renderer.get_node(side.capitalize()).get_children():
			if not node.has_meta("border_terrain"): continue
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for index in range(0, vertices.size(), 3):
				var a := vertices[index]
				var b := vertices[index + 1]
				var c := vertices[index + 2]
				for vertex in [a, b, c]:
					assert(strip.grow(0.001).has_point(Vector2(vertex.x, vertex.z)))
				area += (b - a).cross(c - a).length() * 0.5
		assert(is_equal_approx(area, strip.get_area()), "Every painted tile must fill its strip, including partial repeats.")
	var horizontal := Layout.corner_priority(map) == "north_south"
	for x in [bounds.position.x - 0.5, bounds.end.x + 0.5]:
		var vertical_owner := 3 if x < bounds.position.x else 2
		assert(strips[0 if horizontal else vertical_owner].has_point(Vector2(x, bounds.position.y - 0.5)))
		assert(strips[1 if horizontal else vertical_owner].has_point(Vector2(x, bounds.end.y + 0.5)))
