extends Node3D

const Layout := preload("res://tools/map_editor/core/map_border_layout.gd")
const Bounds := preload("res://tools/map_editor/core/map_bounds.gd")
const CameraView := preload("res://world/terrain_camera_view.gd")
const TerrainTextures := preload("res://world/terrain_transition_texture_cache.gd")
const LightShader := preload("res://world/overworld_light_terrain.gdshader")
const Foreground := preload("res://world/map_border_foreground.gd")
const WINDOW_STEP := 4.0

var _overlay_shader:Shader

var _layer := 1
var _states: Dictionary = {}
var _textures: Dictionary = {}
var _art_meshes: Dictionary = {}
var _view_signature: Array = []
var _light_generation := -1
var _foreground: Node2D

func configure(map: Dictionary, origin: Vector3, layer: int, canvas: CanvasLayer = null) -> void:
	var bounds := Bounds.rect(map)
	var local_bounds := bounds
	var offset := Vector2(origin.x, origin.z)
	bounds.position += offset
	var canonical: bool = not map.get("_terrain_grid", {}).is_empty()
	_layer = layer
	_view_signature.clear()
	_art_meshes.clear()
	_light_generation = -1
	for child in get_children(): child.free()
	_clear_foreground()
	_states.clear()
	if not bounds.has_area(): return
	for side in Layout.SIDES:
		var strip := Layout.region(map, bounds, side)
		if not strip.has_area(): continue
		var definition := Layout.definition(map, side)
		var cells: Variant = definition.get("cells")
		if not cells is Dictionary or cells.is_empty(): continue
		var covers: bool = canvas != null and definition.get("covers_player") == true
		if covers and _foreground == null:
			_foreground = Node2D.new()
			_foreground.name = "ForegroundMapBorders"
			_foreground.z_index = 100
			_foreground.y_sort_enabled = true
			canvas.add_child(_foreground)
		var root := Node3D.new()
		root.name = side.capitalize()
		add_child(root)
		var padding := 0.0
		for cell in cells.values():
			if cell is Dictionary and cell.get("art") is Dictionary:
				padding = maxf(padding, Layout.art_size(cell.art).length())
		var seam := Layout.seam_region(map, local_bounds, side) if canonical else Rect2()
		seam.position += offset
		var anchor := Layout.repeat_origin(bounds, strip, side)
		var tile_phase := anchor - offset + Vector2.ONE * 0.5
		var uv_phase := Vector2(fposmod(tile_phase.x, 1), fposmod(tile_phase.y, 1)) if canonical else Vector2.ZERO
		_states[side] = {"strip": strip, "anchor": anchor, "uv_phase": uv_phase,
			"dimensions": Layout.repeat_dimensions(map, side, definition), "cells": cells, "root": root,
			"seam": seam, "along_x": Layout.horizontal(side),
			"covers_player": covers, "foreground_items": [],
			"padding": padding, "height": origin.y + (0.401 if canonical else 0.001),
			"materials": {}, "terrain_window": Rect2i(), "art_window": Rect2i()}

func update_view(camera: Camera3D, lighting: Node) -> void:
	if _states.is_empty(): return
	var signature := CameraView.signature(camera)
	if signature != _view_signature:
		_view_signature = signature
		for state in _states.values():
			var view := CameraView.ground_rect(camera, state.height)
			var terrain_window := _window(view.grow(1.0) if state.seam.has_area() else view, state)
			var art_window := _window(view.grow(state.padding), state) if state.padding > 0.0 else Rect2i()
			if terrain_window != state.terrain_window or art_window != state.art_window:
				state.terrain_window = terrain_window
				state.art_window = art_window
				_rebuild(state)
				_light_generation = -1
			for item in state.foreground_items: Foreground.project(item, camera)
	if lighting != null and _light_generation != lighting.material_update_generation:
		_light_generation = lighting.material_update_generation
		if _foreground != null: _foreground.material = lighting.canvas_light_material
		for state in _states.values():
			for material in state.materials.values():
				lighting.apply_world_material_lighting(material)

func _exit_tree() -> void:
	_clear_foreground()

func _clear_foreground() -> void:
	if is_instance_valid(_foreground):
		_foreground.hide()
		_foreground.queue_free()
	_foreground = null

func _window(view: Rect2, state: Dictionary) -> Rect2i:
	var visible := view.intersection(state.strip)
	if not visible.has_area(): return Rect2i()
	var first := (visible.position / WINDOW_STEP).floor() * WINDOW_STEP
	var end := (visible.end / WINDOW_STEP).ceil() * WINDOW_STEP
	return Layout.tile_window(Rect2(first, end - first).intersection(state.strip), state.anchor)

func _rebuild(state: Dictionary) -> void:
	for child in state.root.get_children(): child.free()
	for item in state.foreground_items: item.free()
	state.foreground_items.clear()
	var terrain_window: Rect2i = state.terrain_window
	var art_window: Rect2i = state.art_window
	var window := art_window.merge(terrain_window) if art_window.has_area() and terrain_window.has_area() else (art_window if art_window.has_area() else terrain_window)
	var anchor: Vector2 = state.anchor
	var dimensions: Vector2i = state.dimensions
	var batches := {}
	for z in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			var point := Vector2i(x, z)
			var key := Layout.cell_key(Vector2i(posmod(x, dimensions.x), posmod(z, dimensions.y)))
			var cell: Variant = state.cells.get(key)
			if not cell is Dictionary: continue
			var tile := Rect2(anchor + Vector2(x, z), Vector2.ONE)
			var terrain := String(cell.get("terrain", ""))
			if not terrain.is_empty() and terrain_window.has_point(point):
				var clipped := tile.intersection(state.strip)
				if not batches.has(terrain):
					var surface := SurfaceTool.new()
					surface.begin(Mesh.PRIMITIVE_TRIANGLES)
					batches[terrain] = surface
				_ground_quad(batches[terrain], clipped, clipped.position - tile.position + state.uv_phase, state.height)
				var seam := Layout.seam_patch(clipped, state.seam, state.along_x)
				if seam.has_area():
					_ground_quad(batches[terrain], seam, seam.position - tile.position + state.uv_phase, state.height)
			if art_window.has_point(point) and cell.get("art") is Dictionary:
				_add_art(state, Layout.art_anchor(tile.get_center(), cell.art), cell.art)
	for terrain in batches:
		var texture := TerrainTextures.base_texture(terrain)
		if texture == null: continue
		var mesh := _add_mesh(state, batches[terrain].commit(), texture, false, false)
		mesh.set_meta("border_terrain", terrain)
		OverworldTextureAnimation.register_terrain(texture, mesh)
		_add_foreground(state, mesh, false, false, 0)

func _ground_quad(surface: SurfaceTool, rect: Rect2, uv_start: Vector2, height: float) -> void:
	for point: Vector2 in [Vector2.ZERO, Vector2(rect.size.x, 0), rect.size, Vector2.ZERO, rect.size, Vector2(0, rect.size.y)]:
		surface.set_uv(uv_start + point)
		surface.add_vertex(Vector3(rect.position.x + point.x, height, rect.position.y + point.y))

func _add_art(state: Dictionary, anchor: Vector2, art: Dictionary) -> void:
	var footprint := Layout.building_footprint(art)
	if footprint != Vector2.ZERO:
		if not Layout.fits_building(anchor, footprint, state.strip): return
	elif art.get("flat") != true and not state.strip.has_point(anchor): return
	var texture := _art_texture(art)
	if texture == null: return
	var dimensions := Layout.art_size(art)
	var flat: bool = art.get("flat") == true
	var angle := deg_to_rad(float(art.get("rotation", 0)))
	var key := [dimensions, flat, angle]
	if not _art_meshes.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pivot := Vector2(0.5, 0.5 if flat else 1.0)
		for uv: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.ZERO, Vector2.ONE, Vector2.DOWN]:
			var point := ((uv - pivot) * dimensions).rotated(angle)
			surface.set_uv(uv)
			surface.add_vertex(Vector3(point.x, 0.003, point.y) if flat else Vector3(point.x, -point.y, 0))
		_art_meshes[key] = surface.commit()
	var mesh := _add_mesh(state, _art_meshes[key], texture, not flat, footprint == Vector2.ZERO, Layout.art_priority(art))
	mesh.position = Vector3(anchor.x, state.height, anchor.y)
	mesh.set_meta("border_art", Layout.texture_path(art))
	# The shader billboards upright art. Give its rotated quad conservative bounds.
	if not flat:
		var reach := dimensions.length()
		mesh.custom_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2)
	if texture is AnimatedTexture:
		OverworldTextureAnimation.register_terrain(texture, mesh)
	_add_foreground(state, mesh, not flat, footprint == Vector2.ZERO, 1 + Layout.art_priority(art))

func _add_foreground(state: Dictionary, source: MeshInstance3D, billboard: bool, clip: bool, priority: int) -> void:
	if not state.covers_player: return
	source.layers = 0
	source.set_meta("border_foreground_source", true)
	var item := Foreground.make(source, state.strip, billboard, clip, priority)
	if item == null: return
	_foreground.add_child(item)
	state.foreground_items.append(item)

func _add_mesh(state: Dictionary, geometry: Mesh, texture: Texture2D, billboard: bool, clip: bool, priority:int=0) -> MeshInstance3D:
	var key := [texture, billboard, clip, priority]
	var material: ShaderMaterial = state.materials.get(key)
	if material == null:
		material = ShaderMaterial.new()
		if priority>0:
			if _overlay_shader==null:
				_overlay_shader=Shader.new()
				_overlay_shader.code=LightShader.code.replace("render_mode unshaded, cull_disabled;","render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;")
			material.shader=_overlay_shader
			material.render_priority=priority
		else:material.shader = LightShader
		material.set_shader_parameter("albedo_texture", texture)
		material.set_shader_parameter("billboard_enabled", billboard)
		material.set_shader_parameter("clip_to_border", clip)
		var strip: Rect2 = state.strip
		material.set_shader_parameter("border_rect", Vector4(strip.position.x, strip.position.y, strip.end.x, strip.end.y))
		state.materials[key] = material
	var node := MeshInstance3D.new()
	node.mesh = geometry
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = 1 << (mini(_layer, 19) - 1)
	node.set_meta("visual_layer", _layer)
	state.root.add_child(node)
	return node

func _art_texture(art: Dictionary) -> Texture2D:
	var path := Layout.texture_path(art)
	var animation := String(art.get("animation", ""))
	var key := [path, animation]
	if _textures.has(key): return _textures[key]
	var texture: Texture2D
	if animation == "canal_lock":
		var spec := Layout.animation_spec(animation, {})
		var proxy := AnimatedTexture.new()
		proxy.frames = spec.paths.size()
		for index in proxy.frames:
			var frame := load("res://" + String(spec.paths[index])) as Texture2D
			proxy.set_frame_texture(index, frame)
			proxy.set_frame_duration(index, spec.duration)
		texture = proxy
	elif not animation.is_empty():
		var definition := OverworldTextureAnimation.definition(animation)
		if not definition.is_empty():
			texture = OverworldTextureAnimation.shared_texture("border|" + animation, animation, func(index): return definition.frames[index])
	if texture == null and not path.is_empty() and ResourceLoader.exists("res://" + path):
		texture = load("res://" + path) as Texture2D
	_textures[key] = texture
	return texture
