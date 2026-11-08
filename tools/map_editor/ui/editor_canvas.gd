class_name EditorCanvas
extends Control

const BorderLayout := preload("res://core/map_border_layout.gd")

const VIEWPORT_MARGIN_PIXELS := 128.0
const TERRAIN_LABEL_MIN_CELL_PIXELS := 24.0

const WallGeometryRef := preload("res://core/wall_geometry.gd")

# Keep placement preview in the same visual scale as the runtime's billboard
# wall sprites. These values intentionally mirror world/main.gd.
const WALL_PIXELS_TO_WORLD := 2.0 / 166.0
const WALL_FILLER_INTERVAL := 2.0
const WALL_POST_TEXTURE_PATH := "assets/overworld/wall_post_generic.png"
const WALL_HORIZONTAL_TEXTURE_PATH := "assets/overworld/wall_horizontal_generic.png"
const WALL_VERTICAL_TEXTURE_PATH := "assets/overworld/wall_vertical_generic.png"
const RUNTIME_TERRAIN_TEXTURES := {
	"dark_museum_floor":"assets/overworld/tile_dark_museum_floor.png",
	"dark_museum_floor_corner":"assets/overworld/tile_dark_museum_floor_corner.png",
	"dark_museum_floor_icon":"assets/overworld/tile_dark_museum_floor_icon.png",
	"earthy_museum_floor":"assets/overworld/tile_earthy_museum_floor.png",
	"pale_museum_floor":"assets/overworld/tile_pale_museum_floor.png",

	"indoor_floor_tile":"assets/overworld/tile_interior_floor_tiles.png",
	"indoor_floor_tile_00":"assets/overworld/tile_interior_floor_tiles_00.png",
	"warm_honey_limestone_paving":"assets/overworld/tile_warm_honey_limestone_paving.png",
	"water":"assets/overworld/tile_water_generic.png",
	"sand":"assets/overworld/tile_sand_generic.png",
	"mud":"assets/overworld/tile_dirt_generic.png",
	"forest_floor":"assets/overworld/grass_main.png",
	"stone":"assets/overworld/stone_main.png",
	"rock":"assets/overworld/stone_main.png",
}

signal object_selected(object_id: String)
signal object_activated(object_id: String)
signal object_moved(object_id: String, old_position: Vector3, new_position: Vector3)
signal objects_moved(moves: Array)
signal object_resized(object_id: String, old_size: Vector3, new_size: Vector3)
signal map_resized(old_size: Vector2, new_size: Vector2)
signal map_bounds_resized(new_size:Vector2,new_center:Vector2)
signal terrain_fill_requested(cell: Vector2i)
signal terrain_stroke_started()
signal terrain_cell_changed(cell: Vector2i, erase: bool)
signal terrain_stroke_finished()
signal wall_anchor_requested(point: Vector2)
signal wall_vertex_requested(object_id: String, segment_index: int, point: Vector2)
signal wall_finished()
signal wall_anchor_moved(object_id: String, anchor_index: int, point: Vector2)
signal wall_anchors_moved(anchor_keys: Array, delta: Vector2)
signal host_picked(object_id: String)
signal collision_polygon_changed(points: Array, closed: bool, action: String)
signal script_node_changed(path_name: String, index: int, point: Vector2)
signal script_node_added(point: Vector2)
signal script_node_picked(path_name: String, index: int)
var script_preview_elevation := 0.0
var script_path_elevations: Dictionary = {}
var script_paths: Array = []
var script_path_selected := ""
var script_node_selected := -1
var script_invalid_segments: Dictionary = {}
var script_path_add_mode := false
var script_drag_node := -1
var script_drag_path := ""
var script_drag_point := Vector2.ZERO

var objects: Array[Dictionary] = []:
	set(value):
		objects=value
		invalidate_order_cache()
var order_revision:=0
var draw_order_rebuilds:=0
var selection_order_rebuilds:=0
var _draw_order_signature:Array=[]
var _draw_order:Array[Dictionary]=[]
var _selection_orders:Dictionary={}
var _drawing_bounds_cache:Dictionary={}
var _drawing_bounds_signature:Array=[]
var _visible_draw_order:Array[Dictionary]=[]
var _visible_draw_signature:Array=[]
var selected_id := ""
var selected_ids: Dictionary = {}
var selected_wall_anchors: Dictionary = {}
var map_size := Vector2(20, 20)
var map_center := Vector2.ZERO
var grid_size := 1.0
var snapping := true
var zoom := 1.0
var pan := Vector2.ZERO
var pixels_per_unit := 32.0
var texture_cache: Dictionary = {}
var project_root := ""
var dragging := false
var resizing := false
var map_resizing := false
var map_resize_enabled := false
var map_resize_edge := ""
var panning := false
var drag_start_mouse := Vector2.ZERO
var drag_start_position := Vector3.ZERO
var drag_start_size := Vector3.ZERO
var drag_start_positions: Dictionary = {}
var map_drag_start_size := Vector2.ZERO
var map_drag_start_center := Vector2.ZERO
var script_read_only := false
var terrain_brush_mode := "select"
var selection_mode := "objects"
var terrain_error_cells: Dictionary = {}
var validation_error_ids: Dictionary = {}
var last_brush_cell := Vector2i(999999,999999)
var wall_tool_active := false
var fence_edit_mode := false
var wall_preview := Vector2.ZERO
var wall_drag_anchor := -1
var wall_drag_id := ""
var wall_drag_start_points: Dictionary = {}
var last_wall_anchor_click_id := ""
var last_wall_anchor_click_position := Vector2.INF
var wall_anchor_click_cycle := 0
var debug_geometry := false
var placement_preview := false
var _border_preview_map: Dictionary = {}
var _border_animations_loaded := false
var _border_animations: Dictionary = {}
var _border_animated_textures: Dictionary = {}
var base_terrain_texture_path := ""
var base_terrain_type := "forest_floor"
var water_clip_grid:Dictionary={}
var water_clip_walls:Array=[]
var marquee_selecting := false
var marquee_start := Vector2.ZERO
var marquee_rect := Rect2()
var host_picker_active := false
var collision_polygon_active:=false
var collision_polygon_points:=PackedVector2Array()
var collision_polygon_closed:=false
var collision_polygon_selected_vertex:=-1
var collision_polygon_drag_vertex:=-1
var collision_polygon_drag_before:=PackedVector2Array()

func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	set_process_unhandled_key_input(true)

func set_document_objects(new_objects: Array[Dictionary], new_map_size: Vector2, new_map_center:Vector2=Vector2.ZERO) -> void:
	objects = new_objects
	map_size = new_map_size
	map_center = new_map_center
	if not objects.any(func(o): return String(o.id) == selected_id): selected_id = ""
	for id in selected_ids.keys(): if not objects.any(func(o): return String(o.id) == String(id)): selected_ids.erase(id)
	queue_redraw()

func select_object(id: String) -> void:
	if not id.is_empty():
		var candidate:=_object_by_id(id)
		if candidate.is_empty() or not _selection_mode_allows(candidate):id=""
	selected_id = id
	if not id.is_empty(): grab_focus()
	queue_redraw()
	object_selected.emit(id)

func selected_object_ids() -> Array[String]:
	var result:Array[String]=[]
	for id in selected_ids:result.append(String(id))
	if result.is_empty() and not selected_id.is_empty():result.append(selected_id)
	return result

func frame_all() -> void:
	zoom = clampf(minf(size.x / maxf(map_size.x * pixels_per_unit, 1.0), size.y / maxf(map_size.y * pixels_per_unit, 1.0)) * 0.82, 0.2, 4.0)
	pan = -map_center*pixels_per_unit*zoom*_ground_projection()
	queue_redraw()

func _show_editor_geometry() -> bool:
	return not placement_preview and not script_read_only

func _draw() -> void:
	water_clip_grid.clear();water_clip_walls.clear()
	for object in objects:
		if String(object.get("shape",""))=="terrain":water_clip_grid[Vector2i(roundi(object.position.x),roundi(object.position.z))]=String(object.get("label",""))
		elif String(object.get("shape",""))=="wall":
			var points:Array=[]
			for point:Vector2 in object.get("wall_points",[]):points.append([point.x,point.y])
			water_clip_walls.append({"type":"wall.fence","points":points,"disabled_segments":object.get("disabled_segments",[])})
	draw_rect(Rect2(Vector2.ZERO, size), Color("#151a20"))
	var bounds := _map_bounds_rect()
	if placement_preview or script_read_only:
		_draw_ground(bounds)
		if placement_preview: _draw_map_borders()
	else:
		_draw_grid()
		draw_rect(bounds, Color("#29433288"), true)
		draw_rect(bounds, Color("#7dab85"), false, 2.0)
		if map_resize_enabled:
			draw_rect(_resize_handle(bounds), Color("#a6f06c"), true)
			draw_rect(_resize_handle(bounds), Color("#eaffd8"), false, 2.0)
	for object in _visible_draw_objects():_draw_object(object)
	if map_resize_enabled:_draw_map_resize_arrows()
	if script_read_only: _draw_script_paths()
	if collision_polygon_active and _show_editor_geometry():_draw_collision_polygon()
	if _show_editor_geometry():
		for cell in terrain_error_cells:
			var center:=world_to_screen(Vector2(cell));var rect:=Rect2(center-Vector2.ONE*pixels_per_unit*zoom*0.5,Vector2.ONE*pixels_per_unit*zoom)
			if not rect.intersects(Rect2(Vector2.ZERO,size).grow(VIEWPORT_MARGIN_PIXELS)):continue
			draw_rect(rect,Color("#ff334466"),true);draw_rect(rect,Color("#ff3344"),false,3.0)
	if marquee_selecting and _show_editor_geometry():
		draw_rect(marquee_rect,Color("#72d7ff33"),true)
		draw_rect(marquee_rect,Color("#72d7ff"),false,2.0)
	if _show_editor_geometry():
		draw_string(get_theme_default_font(), Vector2(size.x * 0.5 - 24, 20), "N  (-Z)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#b8c9d8"))
		if terrain_brush_mode!="select":draw_string(get_theme_default_font(),Vector2(14,size.y-16),"Terrain %s Â· 1Ã—1 snapped cells"%terrain_brush_mode.capitalize(),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#ffe16b"))

func set_border_preview(map: Dictionary) -> void:
	_border_preview_map = map

func _draw_map_borders() -> void:
	var bounds := Rect2(map_center - map_size * 0.5, map_size)
	var canonical := _border_preview_map.has("terrain_tiles") or _border_preview_map.has("objects") or _border_preview_map.has("water_blocks") or _border_preview_map.has("sand_blocks")
	for side: String in BorderLayout.SIDES:
		var strip := BorderLayout.region(_border_preview_map, bounds, side)
		if not strip.has_area(): continue
		var definition := BorderLayout.definition(_border_preview_map, side)
		var cells: Variant = definition.get("cells")
		if not cells is Dictionary or cells.is_empty(): continue
		var anchor := BorderLayout.repeat_origin(bounds, strip, side)
		var seam := BorderLayout.seam_region(_border_preview_map, bounds, side) if canonical else Rect2()
		_draw_border_strip(strip, anchor, BorderLayout.repeat_dimensions(_border_preview_map, side, definition), cells, seam, BorderLayout.horizontal(side))

func _draw_border_strip(strip: Rect2, anchor: Vector2, dimensions: Vector2i, cells: Dictionary, seam := Rect2(), along_x := false) -> void:
	var view := Rect2(screen_to_world(Vector2.ZERO), screen_to_world(size) - screen_to_world(Vector2.ZERO))
	var padding := 0.0
	for cell in cells.values():
		if cell is Dictionary and cell.get("art") is Dictionary:
			padding = maxf(padding, BorderLayout.art_size(cell.art).length() / _ground_projection().y)
	var visible := strip.intersection(view.grow(maxf(padding, 1.0 if seam.has_area() else 0.0)))
	if not visible.has_area(): return
	var window := BorderLayout.tile_window(visible, anchor)
	var art_cells: Array[Dictionary] = []
	for z in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			var key := BorderLayout.cell_key(Vector2i(posmod(x, dimensions.x), posmod(z, dimensions.y)))
			var cell: Variant = cells.get(key)
			if not cell is Dictionary: continue
			var tile := Rect2(anchor + Vector2(x, z), Vector2.ONE)
			var clipped := tile.intersection(strip)
			var terrain := String(cell.get("terrain", ""))
			if tile.intersects(view):
				_draw_border_tile(tile, clipped, terrain)
			var patch := BorderLayout.seam_patch(clipped, seam, along_x)
			if patch.has_area() and patch.intersects(view):
				var uv_offset := patch.position - tile.position
				var source := Rect2(patch.position - Vector2(fposmod(uv_offset.x, 1), fposmod(uv_offset.y, 1)), Vector2.ONE)
				_draw_border_tile(source, patch, terrain)
			if cell.get("art") is Dictionary:
				var art_anchor := BorderLayout.art_anchor(tile.get_center(), cell.art)
				var footprint := BorderLayout.building_footprint(cell.art)
				var fits: bool = cell.art.get("flat") == true or strip.has_point(art_anchor)
				if footprint != Vector2.ZERO: fits = BorderLayout.fits_building(art_anchor, footprint, strip)
				if fits:
					art_cells.append({"center": world_to_screen(art_anchor), "art": cell.art})
	var screen_strip := Rect2(world_to_screen(strip.position), strip.size * pixels_per_unit * zoom * _ground_projection())
	for item in art_cells:
		_draw_border_art(item.center, item.art, screen_strip)

func _draw_border_tile(tile: Rect2, clipped: Rect2, terrain: String) -> void:
	var animation := "water_generic_glisten" if terrain == "water" else ""
	var texture := visual_texture(String(RUNTIME_TERRAIN_TEXTURES.get(terrain, "")), animation)
	if texture == null: return
	var scale := pixels_per_unit * zoom * _ground_projection()
	var destination := Rect2(world_to_screen(clipped.position), clipped.size * scale)
	var source := Rect2((clipped.position - tile.position) * texture.get_size(), clipped.size * texture.get_size())
	var tint := Color("#777970") if terrain == "rock" else _runtime_terrain_tint(terrain)
	if terrain == "forest_floor":
		source.position = texture.get_size() - source.end
		draw_set_transform(destination.get_center(), PI)
		draw_texture_rect_region(texture, Rect2(-destination.size * 0.5, destination.size), source, tint)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect_region(texture, destination, source, tint)

func _draw_border_art(center: Vector2, art: Dictionary, strip: Rect2) -> void:
	var texture := visual_texture(BorderLayout.texture_path(art), String(art.get("animation", "")))
	if texture == null: return
	var flat: bool = art.get("flat") == true
	var dimensions := BorderLayout.art_size(art) * pixels_per_unit * zoom
	var offset := dimensions * Vector2(-0.5, -0.5 if flat else -1.0)
	var projection := Transform2D(0, _ground_projection() if flat else Vector2.ONE, 0, center)
	var transform := projection * Transform2D(deg_to_rad(float(art.get("rotation", 0))), Vector2.ZERO)
	if BorderLayout.building_footprint(art) != Vector2.ZERO:
		draw_set_transform_matrix(transform)
		draw_texture_rect(texture, Rect2(offset, dimensions), false)
		draw_set_transform(Vector2.ZERO)
		return
	var corners := PackedVector2Array([offset, offset + Vector2(dimensions.x, 0), offset + dimensions, offset + Vector2(0, dimensions.y)])
	var clip := strip if flat else Rect2(strip.position.x, 0, strip.size.x, size.y)
	var clip_corners := PackedVector2Array([clip.position, Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)])
	var inverse := transform.affine_inverse()
	for polygon in Geometry2D.intersect_polygons(transform * corners, clip_corners):
		var uvs := PackedVector2Array()
		for point in polygon: uvs.append((inverse * point - offset) / dimensions)
		draw_colored_polygon(polygon, Color.WHITE, uvs, texture)

func visual_texture(path: String, animation: String) -> Texture2D:
	if not animation.is_empty():
		if not _border_animated_textures.has(animation):
			if not _border_animations_loaded:
				_border_animations_loaded = true
				var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(project_root.path_join("assets/overworld/anim/animations.json")))
				if manifest is Dictionary: _border_animations = manifest.get("animations", {})
			var spec := BorderLayout.animation_spec(animation, _border_animations)
			var proxy: AnimatedTexture
			if not spec.is_empty():
				var frames: Array[Texture2D] = []
				for frame_path in spec.paths:
					var frame := _texture_for(frame_path)
					if frame == null: break
					frames.append(frame)
				if frames.size() == spec.paths.size():
					proxy = AnimatedTexture.new()
					proxy.frames = frames.size()
					for index in frames.size():
						proxy.set_frame_texture(index, frames[index])
						proxy.set_frame_duration(index, spec.duration)
			_border_animated_textures[animation] = proxy
		if _border_animated_textures[animation] != null: return _border_animated_textures[animation]
	return _texture_for(path) if not path.is_empty() else null

func _draw_ground(bounds: Rect2) -> void:
	# The standalone editor reads gameplay assets directly. It cannot preload a
	# gameplay script because that project is intentionally outside this editor's
	# resource root.
	var texture := _runtime_terrain_texture(base_terrain_type)
	if texture == null: texture = _texture_for(base_terrain_texture_path)
	if texture != null:
		_draw_preview_tiled_texture(texture,bounds,_runtime_terrain_tint(base_terrain_type))
	else:
		draw_rect(bounds, Color("#294332"), true)

func _ground_projection()->Vector2:
	return Vector2(1.0,sqrt(0.5)) if placement_preview or script_read_only else Vector2.ONE

func _draw_preview_tiled_texture(texture:Texture2D,rect:Rect2,tint:Color=Color.WHITE)->void:
	var tile_scale:=Vector2.ONE*pixels_per_unit*zoom*_ground_projection()/texture.get_size()
	draw_set_transform(rect.position,0.0,tile_scale)
	draw_texture_rect(texture,Rect2(Vector2.ZERO,rect.size/tile_scale),true,tint)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

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

func begin_collision_polygon_editor(points:Array,closed:bool)->void:
	collision_polygon_points=PackedVector2Array()
	for point:Variant in points:
		if point is Array and point.size()==2:collision_polygon_points.append(Vector2(float(point[0]),float(point[1])))
	collision_polygon_closed=closed;collision_polygon_active=true;collision_polygon_selected_vertex=-1;queue_redraw();grab_focus()

func end_collision_polygon_editor()->void:
	collision_polygon_active=false;collision_polygon_drag_vertex=-1;collision_polygon_selected_vertex=-1;queue_redraw()

func clear_collision_polygon()->void:
	if not collision_polygon_active:return
	collision_polygon_points.clear();collision_polygon_closed=false;collision_polygon_selected_vertex=-1;_emit_collision_polygon("Clear polygon")

func delete_collision_polygon_vertex()->bool:
	if not collision_polygon_active or collision_polygon_selected_vertex<0 or collision_polygon_selected_vertex>=collision_polygon_points.size():return false
	collision_polygon_points.remove_at(collision_polygon_selected_vertex);collision_polygon_selected_vertex=-1
	if collision_polygon_points.size()<3:collision_polygon_closed=false
	_emit_collision_polygon("Delete polygon vertex");return true

func _collision_polygon_array()->Array:
	var result:Array=[]
	for point in collision_polygon_points:result.append([point.x,point.y])
	return result

func _emit_collision_polygon(action:String)->void:
	collision_polygon_changed.emit(_collision_polygon_array(),collision_polygon_closed,action);queue_redraw()

func _polygon_screen_point(point:Vector2)->Vector2:
	var object:=_selected();if object.is_empty():return Vector2.ZERO
	var rect:=_screen_rect(object);var local:=(point-Vector2(0.5,0.5))*rect.size
	return rect.get_center()+local.rotated(deg_to_rad(float(object.get("rotation_degrees",0.0))))

func _polygon_normalized_point(screen_point:Vector2)->Vector2:
	var object:=_selected();if object.is_empty():return Vector2.ZERO
	var rect:=_screen_rect(object);var local:=(screen_point-rect.get_center()).rotated(-deg_to_rad(float(object.get("rotation_degrees",0.0))))
	# Keep footprint-relative coordinates unbounded so colliders can surround large sprite bases.
	return Vector2(local.x/maxf(rect.size.x,0.001)+0.5,local.y/maxf(rect.size.y,0.001)+0.5)

func _polygon_vertex_at(screen_point:Vector2)->int:
	for index in collision_polygon_points.size():
		if _polygon_screen_point(collision_polygon_points[index]).distance_to(screen_point)<=9.0:return index
	return -1

func _polygon_edge_at(screen_point:Vector2)->int:
	if collision_polygon_points.size()<2:return -1
	var edge_count:=collision_polygon_points.size() if collision_polygon_closed else collision_polygon_points.size()-1
	for index in edge_count:
		if Geometry2D.get_closest_point_to_segment(screen_point,_polygon_screen_point(collision_polygon_points[index]),_polygon_screen_point(collision_polygon_points[(index+1)%collision_polygon_points.size()])).distance_to(screen_point)<=7.0:return index
	return -1

func _draw_collision_polygon()->void:
	if collision_polygon_points.is_empty():return
	var screen_points:=PackedVector2Array();for point in collision_polygon_points:screen_points.append(_polygon_screen_point(point))
	if collision_polygon_closed and screen_points.size()>=3:draw_colored_polygon(screen_points,Color("#ef334455"))
	for index in range(1,screen_points.size()):draw_line(screen_points[index-1],screen_points[index],Color("#ff3344"),3.0)
	if collision_polygon_closed and screen_points.size()>=3:draw_line(screen_points[-1],screen_points[0],Color("#ff3344"),3.0)
	for index in screen_points.size():draw_circle(screen_points[index],7.0,Color("#ffe16b") if index==collision_polygon_selected_vertex else Color("#ff3344"));draw_circle(screen_points[index],2.0,Color.WHITE)

func _visible_draw_objects()->Array[Dictionary]:
	var signature:Array=[order_revision,objects.size(),placement_preview,script_read_only,pan,zoom,size,pixels_per_unit,selected_id,selected_ids.hash(),validation_error_ids.hash()]
	if signature==_visible_draw_signature:return _visible_draw_order
	_visible_draw_order.clear()
	for object in _ordered_draw_objects():
		if _object_in_draw_view(object):_visible_draw_order.append(object)
	_visible_draw_signature=signature
	return _visible_draw_order

func _terrain_label_visible(object:Dictionary)->bool:
	if not _is_terrain_object(object):return true
	var id:=String(object.get("id",""))
	return pixels_per_unit*zoom>=TERRAIN_LABEL_MIN_CELL_PIXELS or id==selected_id or selected_ids.has(id) or validation_error_ids.has(id)

func _object_in_draw_view(object:Dictionary)->bool:
	if (placement_preview or script_read_only) and (not bool(object.get("preview_visible",true)) or String(object.get("field",""))=="asset_collision"):return false
	# A selected edit handle or collision outline remains available during drags.
	var id:=String(object.get("id",""))
	if _show_editor_geometry() and (id==selected_id or selected_ids.has(id)):return true
	return _object_draw_bounds(object).intersects(Rect2(Vector2.ZERO,size).grow(VIEWPORT_MARGIN_PIXELS),true)

func _object_draw_bounds(object:Dictionary)->Rect2:
	var origin:=size*0.5+pan
	var signature:Array=[placement_preview,script_read_only,pixels_per_unit]
	if signature!=_drawing_bounds_signature:
		_drawing_bounds_cache.clear();_drawing_bounds_signature=signature
	var key:String=object.id
	if not _drawing_bounds_cache.has(key):
		var bounds:=_uncached_object_draw_bounds(object)
		_drawing_bounds_cache[key]=Rect2((bounds.position-origin)/zoom,bounds.size/zoom)
	var local:Rect2=_drawing_bounds_cache[key]
	var bounds:=Rect2(origin+local.position*zoom,local.size*zoom).grow(12)
	if _show_editor_geometry() and _terrain_label_visible(object):
		var center:=_object_anchor_screen(object)
		if String(object.get("shape",""))=="wall" and not object.get("wall_points",[]).is_empty():center=world_to_screen(object.wall_points[0])
		var label:=String(object.get("label",object.get("field","object")))
		bounds=bounds.merge(Rect2(center+Vector2(7,-24),Vector2(maxf(12,label.length()*12),22)))
	return bounds

func _uncached_object_draw_bounds(object:Dictionary)->Rect2:
	if String(object.get("shape",""))=="wall":
		var points:Array=object.get("wall_points",[])
		if points.is_empty():return Rect2()
		var bounds:=Rect2(world_to_screen(points[0]),Vector2.ZERO)
		for point in points:bounds=bounds.expand(world_to_screen(point))
		if placement_preview or script_read_only:
			var reach:=0.0
			for path in [WALL_POST_TEXTURE_PATH,WALL_HORIZONTAL_TEXTURE_PATH,WALL_VERTICAL_TEXTURE_PATH]:
				var texture:=_texture_for(path)
				if texture!=null:reach=maxf(reach,maxf(texture.get_width(),texture.get_height())*WALL_PIXELS_TO_WORLD*pixels_per_unit*zoom)
			if String(object.get("wall_set","generic_wall"))=="canal_wall":reach=maxf(reach,3.0*pixels_per_unit*zoom)
			bounds=bounds.grow(reach)
		return bounds
	var center:=_object_anchor_screen(object)
	var footprint:Vector2=object.get("footprint",Vector2(0.8,0.8))
	if _is_scalable(object):footprint=Vector2(object.size.x,object.size.z)
	var offset:Vector2=object.get("footprint_offset",Vector2.ZERO)
	var dimensions:=footprint*pixels_per_unit*zoom*_ground_projection()
	var bounds:=Rect2(center+offset*pixels_per_unit*zoom*_ground_projection()-dimensions*0.5,dimensions)
	if String(object.get("shape","point")) in ["rectangle","terrain"]:
		if String(object.get("universal_type","")).begins_with("tile."):
			bounds=bounds.merge(Transform2D(deg_to_rad(float(object.get("rotation_degrees",0))),center)*Rect2(-dimensions*0.5,dimensions))
		return bounds
	var texture:Texture2D=object.get("resolved_texture") if object.has("resolved_texture") else _texture_for(String(object.get("texture","")))
	if texture!=null:
		var aspect:=float(texture.get_width())/maxf(float(texture.get_height()),1)
		var art_size:Vector2
		if object.has("display_width"):art_size=Vector2(float(object.display_width),float(object.display_width)/aspect)*pixels_per_unit*zoom
		else:
			var height:=float(object.get("display_height",footprint.y))
			art_size=Vector2(height*aspect,height)*pixels_per_unit*zoom
		bounds=bounds.merge(Transform2D(deg_to_rad(float(object.get("rotation_degrees",0))),center)*Rect2(Vector2(-art_size.x*0.5,-art_size.y),art_size))
	return bounds

func _draw_object(object: Dictionary) -> void:
	if (placement_preview or script_read_only) and (not bool(object.get("preview_visible",true)) or String(object.get("field","")) == "asset_collision"):return
	if String(object.get("shape",""))=="wall":
		_draw_wall(object)
		return
	var position: Vector3 = object.position
	var center := _object_anchor_screen(object)
	var footprint: Vector2 = object.get("footprint", Vector2(0.8, 0.8))
	if _is_scalable(object): footprint = Vector2(object.size.x, object.size.z)
	var footprint_offset:Vector2=object.get("footprint_offset",Vector2.ZERO)
	var projected_footprint:=footprint*pixels_per_unit*zoom*_ground_projection()
	var rect := Rect2(center+footprint_offset*pixels_per_unit*zoom*_ground_projection()-projected_footprint*0.5,projected_footprint)
	if String(object.get("shape",""))=="terrain" and String(object.get("label",""))=="water":
		var clipped:=preload("res://core/wall_water_clip.gd").bounds(Vector2i(roundi(position.x),roundi(position.z)),water_clip_grid,water_clip_walls)
		rect=Rect2(world_to_screen(clipped.position),clipped.size*pixels_per_unit*zoom*_ground_projection())
	var color: Color = object.get("color", Color("#dce6ee"))
	if object.get("shape", "point") in ["rectangle","terrain"]:
		var texture:Texture2D = object.get("resolved_texture") if object.has("resolved_texture") else _texture_for(String(object.get("texture", "")))
		# Canonical painted cells use the same terrain source as the runtime base,
		# rather than the catalog thumbnail. Transition seams remain runtime-derived
		# data, but every authored terrain identity is now previewed faithfully.
		if String(object.get("shape", ""))=="terrain" and (placement_preview or script_read_only):
			var runtime_texture:=_runtime_terrain_texture(String(object.get("label", "")))
			if runtime_texture!=null:texture=runtime_texture
		if texture != null:
			if String(object.get("shape",""))=="terrain" and String(object.get("label",""))=="water" and (placement_preview or script_read_only):
				var regions:=preload("res://core/wall_water_clip.gd").regions(Vector2i(roundi(position.x),roundi(position.z)),water_clip_grid,water_clip_walls)
				for region:Rect2 in regions:_draw_preview_tiled_texture(texture,Rect2(world_to_screen(region.position),region.size*pixels_per_unit*zoom*_ground_projection()))
				return
			# Gameplay repeats block textures across the serialized X/Z dimensions.
			# Tile the same source art here so large interior floors and thin wall
			# strips read like their in-game counterparts instead of flat overlays.
			if String(object.get("universal_type","")).begins_with("tile."):
				draw_set_transform(center,deg_to_rad(float(object.get("rotation_degrees",0.0))),Vector2.ONE)
				draw_texture_rect(texture,Rect2(-rect.size*0.5,rect.size),false,Color(1,1,1,0.96))
				draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
			elif placement_preview or script_read_only:_draw_preview_tiled_texture(texture,rect,_runtime_terrain_tint(String(object.get("label", ""))))
			else:draw_texture_rect(texture, rect, true, Color(1,1,1,0.92))
			if _show_editor_geometry(): draw_rect(rect, Color(color, 0.12), true)
		else:
			draw_rect(rect, Color(color, 0.32), true)
		if _show_editor_geometry(): draw_rect(rect, color, false, 2.0)
	else:
		var texture:Texture2D = object.get("resolved_texture") if object.has("resolved_texture") else _texture_for(String(object.get("texture", "")))
		if texture != null:
			var aspect := float(texture.get_width()) / maxf(float(texture.get_height()), 1.0)
			var draw_size: Vector2
			if object.has("display_width"):
				var display_width := float(object.display_width)
				draw_size = Vector2(display_width, display_width / aspect) * pixels_per_unit * zoom
			else:
				var display_height := float(object.get("display_height", footprint.y))
				draw_size = Vector2(display_height * aspect, display_height) * pixels_per_unit * zoom
			var rotation_radians:=deg_to_rad(float(object.get("rotation_degrees",0.0)))
			draw_set_transform(center,rotation_radians,Vector2.ONE)
			draw_texture_rect(texture,Rect2(Vector2(-draw_size.x*0.5,-draw_size.y),draw_size),false,Color(1,1,1,0.9))
			draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
		else:
			draw_circle(center, maxf(7.0, footprint.x * pixels_per_unit * zoom * 0.35), Color(color, 0.8))
			draw_line(center + Vector2(-6, 0), center + Vector2(6, 0), Color.WHITE, 2)
			draw_line(center + Vector2(0, -6), center + Vector2(0, 6), Color.WHITE, 2)
		if _show_editor_geometry():
			draw_rect(rect, Color(color, 0.18), true)
			draw_rect(rect, color, false, 1.0)
	if String(object.id) == selected_id and _show_editor_geometry():
		draw_rect(rect.grow(3), Color("#ffe16b"), false, 3.0)
		if _is_scalable(object): draw_rect(_resize_handle(rect), Color("#ffe16b"), true)
	elif selected_ids.has(String(object.id)) and _show_editor_geometry():
		draw_rect(rect.grow(2), Color("#72d7ff"), false, 2.0)
	if validation_error_ids.has(String(object.id)) and _show_editor_geometry():draw_rect(rect.grow(2),Color("#ff3344"),false,3.0)
	if _show_editor_geometry() and object.has("wall_collision") and String(object.id)==selected_id:
		var config:Dictionary=object.wall_collision
		if bool(config.get("enabled",true)):
			var offset:Array=config.get("offset",[0,0,0]);var dimensions:Array=config.get("size",[object.size.x,object.size.y,object.size.z])
			var collider_size:=Vector2(float(dimensions[0]),float(dimensions[2]))*pixels_per_unit*zoom
			var collider_center:=center+Vector2(float(offset[0]),float(offset[2]))*pixels_per_unit*zoom
			draw_rect(Rect2(collider_center-collider_size*0.5,collider_size),Color("#ff5577"),false,3.0)
	var label := String(object.get("label", object.get("field", "object")))
	if _show_editor_geometry() and _terrain_label_visible(object): draw_string(get_theme_default_font(), center + Vector2(7, -7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _draw_wall(object:Dictionary)->void:
	var points:Array=object.get("wall_points",[]);if points.is_empty():return
	var disabled:Dictionary={};var disabled_source:Variant=object.get("disabled_segments",[])
	if disabled_source is Array:
		for index:Variant in disabled_source:
			if index is int or index is float:disabled[int(index)]=true
	var color:Color=object.get("color",Color("#dce6ee"));var bounds:=Rect2(world_to_screen(points[0]),Vector2.ZERO)
	if placement_preview or script_read_only:_draw_runtime_wall_preview(points,disabled,String(object.get("wall_set","generic_wall"))=="canal_wall")
	for i in range(1,points.size()):
		var a:=world_to_screen(points[i-1]);var b:=world_to_screen(points[i])
		if not (placement_preview or script_read_only):
			if disabled.has(i-1):draw_dashed_line(a,b,Color("#ff596499"),2.0,7.0)
			else:draw_line(a,b,Color(color,0.9),maxf(3.0,8.0*zoom));draw_line(a,b,Color("#303942"),1.0)
		bounds=bounds.expand(a).expand(b)
	if _show_editor_geometry():
		for point in points:
			var screen:=world_to_screen(point);var anchor_key:="%s:%d"%[String(object.id),points.find(point)];draw_circle(screen,6.0,Color("#72d7ff") if selected_wall_anchors.has(anchor_key) else (Color("#ffe16b") if String(object.id)==selected_id else color));draw_circle(screen,2.5,Color.WHITE)
		if String(object.id)==selected_id:draw_rect(bounds.grow(8),Color("#ffe16b"),false,2.0)
		if debug_geometry and String(object.id)==selected_id:_draw_wall_debug_geometry(object)
		if wall_tool_active and String(object.id)==selected_id and points.size()>0:_draw_wall_route_preview(points[-1],wall_preview)
		draw_string(get_theme_default_font(),world_to_screen(points[0])+Vector2(7,-9),String(object.get("label","Wall / Fence")),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)

func _draw_runtime_wall_preview(points:Array,disabled:Dictionary,canal:bool=false)->void:
	var horizontal:=_texture_for(WALL_HORIZONTAL_TEXTURE_PATH);var vertical:=_texture_for(WALL_VERTICAL_TEXTURE_PATH)
	if canal:
		horizontal=_texture_for("assets/overworld/canal_wall_close.png");vertical=_texture_for("assets/overworld/canal_wall_vertical.png")
	for index in range(1,points.size()):
		if disabled.has(index-1):continue
		var start:Vector2=points[index-1];var finish:Vector2=points[index];var delta:=finish-start;var length:=delta.length()
		if length<=0.001 or (not is_zero_approx(delta.x) and not is_zero_approx(delta.y)):continue
		var texture:Texture2D=vertical if is_zero_approx(delta.x) else horizontal
		if texture==null:continue
		var direction:=delta/length;var count:=floori((length+0.0001)/WALL_FILLER_INTERVAL)
		for repeat_index in count:_draw_runtime_wall_sprite(texture,start+direction*(WALL_FILLER_INTERVAL*(float(repeat_index)+0.5)),canal,is_zero_approx(delta.x))
	var post:=_texture_for(WALL_POST_TEXTURE_PATH)
	if post==null:return
	var posted:Dictionary={}
	for point:Vector2 in points:
		var key:="%.6f,%.6f"%[point.x,point.y]
		if posted.has(key):continue
		posted[key]=true;_draw_runtime_wall_sprite(post,point)

func _draw_runtime_wall_sprite(texture:Texture2D,ground_position:Vector2,canal:bool=false,vertical:bool=false)->void:
	var draw_size:=Vector2(texture.get_width(),texture.get_height())*WALL_PIXELS_TO_WORLD*pixels_per_unit*zoom
	if canal:
		var height:=2.0*sqrt(0.5) if vertical else 2.0*float(texture.get_height())/float(texture.get_width())
		draw_size=Vector2(height*float(texture.get_width())/float(texture.get_height()),height)*pixels_per_unit*zoom
		if not vertical:draw_size=Vector2(2.0,1.6)*pixels_per_unit*zoom
	var ground:=world_to_screen(ground_position)
	if canal and vertical:ground.y+=draw_size.y*0.5-1.2*pixels_per_unit*zoom
	draw_texture_rect(texture,Rect2(ground-Vector2(draw_size.x*0.5,draw_size.y),draw_size),false,Color.WHITE)

func _draw_wall_route_preview(origin:Vector2,target:Vector2)->void:
	target=origin+Vector2(snappedf(target.x-origin.x,WallGeometryRef.MIN_FILLER_SPAN),snappedf(target.y-origin.y,WallGeometryRef.MIN_FILLER_SPAN))
	var delta:=target-origin;var route:Array[Vector2]=[]
	if is_zero_approx(delta.x) or is_zero_approx(delta.y):
		if WallGeometryRef.segment_is_valid(origin,target):route.append(target)
	else:
		var horizontal_first:=absf(delta.x)>=absf(delta.y)
		var dominant_distance:=absf(delta.x) if horizontal_first else absf(delta.y)
		var dominant_steps:=roundi(dominant_distance/WallGeometryRef.MIN_FILLER_SPAN)
		if dominant_steps>=2 and is_equal_approx(dominant_distance,float(dominant_steps)*WallGeometryRef.MIN_FILLER_SPAN):
			var first_steps:=floori(float(dominant_steps)*0.5)
			if horizontal_first:
				var split_x:=origin.x+signf(delta.x)*float(first_steps)*WallGeometryRef.MIN_FILLER_SPAN
				route.assign([Vector2(split_x,origin.y),Vector2(split_x,target.y),target])
			else:
				var split_y:=origin.y+signf(delta.y)*float(first_steps)*WallGeometryRef.MIN_FILLER_SPAN
				route.assign([Vector2(origin.x,split_y),Vector2(target.x,split_y),target])
	var route_previous:=origin
	for route_point in route:
		if not WallGeometryRef.segment_is_valid(route_previous,route_point):route.clear();break
		route_previous=route_point
	if route.is_empty():
		draw_line(world_to_screen(origin),world_to_screen(target),Color("#ff596499"),3.0)
		return
	var previous:=origin
	for point in route:
		draw_line(world_to_screen(previous),world_to_screen(point),Color("#ffe16b99"),3.0)
		previous=point

func _draw_wall_debug_geometry(object:Dictionary)->void:
	var points:Array=object.get("wall_points",[]);var segments:Variant=object.get("wall_segments",[]);var collisions:Variant=object.get("collision",[])
	for point in points:
		var screen:=world_to_screen(point);draw_circle(screen,7,Color("#ffe16b"));draw_string(get_theme_default_font(),screen+Vector2(8,16),"(%.1f, %.1f)"%[point.x,point.y],HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#ffe16b"))
	for index in segments.size():
		var segment:Variant=segments[index];if not segment is Dictionary:continue
		var from:Variant=segment.get("from",[]);var to:Variant=segment.get("to",[]);if not from is Array or not to is Array or from.size()<2 or to.size()<2:continue
		var a:=Vector2(float(from[0]),float(from[1]));var b:=Vector2(float(to[0]),float(to[1]));var delta:=b-a;var length:=delta.length();if length<=0.001:continue
		var direction:=delta/length;var normal:=Vector2(-direction.y,direction.x);var thickness:=float(collisions[index].get("thickness",0.22)) if index<collisions.size() and collisions[index] is Dictionary else 0.22
		var c:=PackedVector2Array([world_to_screen(a+normal*thickness*.5),world_to_screen(b+normal*thickness*.5),world_to_screen(b-normal*thickness*.5),world_to_screen(a-normal*thickness*.5)]);draw_colored_polygon(c,Color("#27e6ff33"));draw_polyline(PackedVector2Array([c[0],c[1],c[2],c[3],c[0]]),Color("#27e6ff"),2)
		for piece in maxi(1,ceili(length)):
			var piece_length:=minf(1.0,length-float(piece));var origin:=a+direction*(float(piece)+piece_length*.5);var r:=PackedVector2Array([world_to_screen(origin-direction*piece_length*.5-normal*.18),world_to_screen(origin+direction*piece_length*.5-normal*.18),world_to_screen(origin+direction*piece_length*.5+normal*.18),world_to_screen(origin-direction*piece_length*.5+normal*.18)]);draw_polyline(PackedVector2Array([r[0],r[1],r[2],r[3],r[0]]),Color("#ff4fd8"),1.5);draw_string(get_theme_default_font(),world_to_screen(origin)+Vector2(2,-3),"Ã—",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("#ff4fd8"))
		draw_string(get_theme_default_font(),world_to_screen((a+b)*.5)+Vector2(8,-9),"%s %.2fu"%[String(segment.get("direction","")),length],HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color.WHITE)
	var first:=world_to_screen(points[0]);draw_line(first-Vector2(9,0),first+Vector2(9,0),Color("#ff9d4d"),2);draw_line(first-Vector2(0,9),first+Vector2(0,9),Color("#ff9d4d"),2)
	draw_string(get_theme_default_font(),Vector2(14,42),"Debug: white=path Â· cyan=collision Â· magenta=sprite pieces Â· yellow=anchors Â· orange=origin",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("#f1f4f8"))

func _texture_for(relative_path: String) -> Texture2D:
	if relative_path.is_empty() or project_root.is_empty(): return null
	if texture_cache.has(relative_path): return texture_cache[relative_path]
	var image := Image.load_from_file(project_root.path_join(relative_path))
	if image == null or image.is_empty(): texture_cache[relative_path] = null; return null
	var texture := ImageTexture.create_from_image(image)
	texture_cache[relative_path] = texture
	return texture

func _runtime_terrain_texture(terrain_type:String)->Texture2D:
	return _texture_for(String(RUNTIME_TERRAIN_TEXTURES.get(terrain_type,"")))

func _runtime_terrain_tint(terrain_type:String)->Color:
	# Keep the forest floor's runtime color treatment in the preview. Other
	# canonical terrain currently uses its source texture unchanged.
	return Color("376b42") if terrain_type=="forest_floor" else Color.WHITE

# Document replacement invalidates automatically. In-place canvas drag/resize
# edits call this explicitly; camera and selection highlights need no new order.
func invalidate_order_cache()->void:
	order_revision+=1
	_draw_order_signature=[]
	_selection_orders.clear()
	_drawing_bounds_cache.clear()

func _ordered_draw_objects()->Array[Dictionary]:
	var signature:Array=[order_revision,objects.size(),placement_preview,script_read_only]
	if signature==_draw_order_signature:return _draw_order
	var keys:Array[Dictionary]=[]
	for object in objects:
		keys.append({"object":object,"rank":_draw_rank(object),"depth":_draw_depth(object),"wall":String(object.get("field",""))=="wall_blocks","overlay":String(object.get("universal_type","")).begins_with("overlay."),"path":String(object.get("path",""))})
	keys.sort_custom(func(a:Dictionary,b:Dictionary):
		if a.rank!=b.rank:return a.rank<b.rank
		if not is_equal_approx(a.depth,b.depth):return a.depth<b.depth
		if placement_preview and a.wall!=b.wall:return a.wall
		if a.overlay!=b.overlay:return not a.overlay
		return a.path<b.path)
	_draw_order.clear()
	for key in keys:_draw_order.append(key.object)
	_draw_order_signature=signature;draw_order_rebuilds+=1
	return _draw_order

func _ordered_selection_candidates()->Array[Dictionary]:
	var key:="%d:%d:%s:%s:%s:%s"%[order_revision,objects.size(),selection_mode,str(fence_edit_mode),str(placement_preview),str(script_read_only)]
	if _selection_orders.has(key):return _selection_orders[key]
	var keys:Array[Dictionary]=[]
	for object in objects:keys.append({"object":object,"rank":_selection_rank(object)})
	# Preserve the existing sort's equal-rank ordering before filtering. Filtering
	# first could change which overlapping equal-rank object wins a click.
	keys.sort_custom(func(a:Dictionary,b:Dictionary):return a.rank>b.rank)
	var candidates:Array[Dictionary]=[]
	for item in keys:
		if _selection_mode_allows(item.object):candidates.append(item.object)
	_selection_orders[key]=candidates;selection_order_rebuilds+=1
	return candidates

func _draw_rank(object:Dictionary)->int:
	# Navigation handles stay accessible over roofs in editing mode. Preview
	# retains runtime depth ordering (including hidden warp sprites).
	if _show_editor_geometry() and String(object.get("role", "")) == "marker": return 100
	if int(object.get("render_band",0))>0:return 5
	if _is_terrain_object(object):return 0
	if placement_preview and String(object.get("field","")) in ["wall_blocks","furnishings"]:return 4
	if String(object.get("universal_type","")).begins_with("background.citybuilding"):return 1
	if String(object.get("field",""))=="wall_blocks":return 1
	if object.get("shape","")=="rectangle":return 2
	if String(object.get("water_kind",""))=="submerged":return 3
	if String(object.get("field",""))=="furnishings":return 3
	return 4

func _draws_before(a:Dictionary,b:Dictionary)->bool:
	var rank_a:=_draw_rank(a);var rank_b:=_draw_rank(b)
	if rank_a!=rank_b:return rank_a<rank_b
	var depth_a:=_draw_depth(a);var depth_b:=_draw_depth(b)
	if not is_equal_approx(depth_a,depth_b):return depth_a<depth_b
	if placement_preview:
		var wall_a:=String(a.get("field",""))=="wall_blocks"
		var wall_b:=String(b.get("field",""))=="wall_blocks"
		if wall_a!=wall_b:return wall_a
	var overlay_a:=String(a.get("universal_type","")).begins_with("overlay.")
	var overlay_b:=String(b.get("universal_type","")).begins_with("overlay.")
	if overlay_a!=overlay_b:return not overlay_a
	# Godot's runtime Y-sort retains a stable scene order for equal ground depth.
	# The map path is likewise stable across redraws and JSON save/load cycles.
	return String(a.get("path",""))<String(b.get("path",""))

func _draw_depth(object:Dictionary)->float:
	if object.has("sort_depth"):return float(object.sort_depth)
	if String(object.get("shape",""))=="wall":
		var points:Array=object.get("wall_points",[])
		if not points.is_empty():
			var southernmost:float=points[0].y
			for point:Vector2 in points:southernmost=maxf(southernmost,point.y)
			return southernmost
	var position:Vector3=object.get("position",Vector3.ZERO)
	if placement_preview and bool(object.get("wall_overlay",false)):
		var depth:=position.z+float(object.get("sort_offset_y",0.0))
		for wall:Dictionary in objects:
			if String(wall.get("field",""))!="wall_blocks":continue
			var bounds:=Rect2(Vector2(wall.position.x,wall.position.z)-Vector2(wall.size.x,wall.size.z)*0.5,Vector2(wall.size.x,wall.size.z))
			if bounds.has_point(Vector2(position.x,position.z)):depth=maxf(depth,wall.position.z+wall.size.z*0.5+0.001)
		return depth
	if placement_preview and String(object.get("field",""))=="wall_blocks":return position.z+float(object.size.z)*0.5
	return position.z+float(object.get("sort_offset_y",0.0))

# Paths store ground X/Z; preview their actor's anchor at its runtime height.
func _script_elevation(path_name: String = "") -> float:
	return float(script_path_elevations.get(path_name if not path_name.is_empty() else script_path_selected, script_preview_elevation))

func _script_node_screen(point: Vector2, path_name: String = "") -> Vector2:
	return world_to_screen(point) - Vector2(0, _script_elevation(path_name) * sqrt(0.5) * pixels_per_unit * zoom)

func _script_point(screen: Vector2, path_name: String = "") -> Vector2:
	var point := screen_to_world(screen + Vector2(0, _script_elevation(path_name) * sqrt(0.5) * pixels_per_unit * zoom))
	return Vector2(snappedf(point.x, grid_size), snappedf(point.y, grid_size)) if snapping else point

func _script_node_at(screen: Vector2) -> Dictionary:
	for path: Dictionary in script_paths:
		for index in path.nodes.size():
			var point := _script_node_screen(Vector2(path.nodes[index][0], path.nodes[index][1]), str(path.name))
			if point.distance_to(screen) <= 9: return {"path":path.name, "index":index}
	return {}

func _draw_script_paths() -> void:
	for path: Dictionary in script_paths:
		var color := Color("#ff9f43") if path.type == "MOVE" else Color("#48dbfb")
		var points: Array[Vector2] = []
		for index in path.nodes.size():
			var point := Vector2(path.nodes[index][0], path.nodes[index][1])
			if script_drag_node == index and script_drag_path == path.name: point = script_drag_point
			points.append(_script_node_screen(point, str(path.name)))
		for index in points.size() - 1:
			var segment_color := Color("#ff3344") if script_invalid_segments.has(str(path.name) + ":" + str(index)) else color
			if path.type == "FOLLOW": draw_dashed_line(points[index], points[index+1], segment_color, 2.5, 8.0)
			else: draw_line(points[index], points[index+1], segment_color, 2.5)
			var direction := (points[index+1] - points[index]).normalized(); var center := (points[index+1] + points[index])*0.5
			if direction.length() > 0: draw_line(center, center-direction.rotated(0.5)*9,segment_color,2); draw_line(center,center-direction.rotated(-0.5)*9,segment_color,2)
		for index in points.size():
			draw_circle(points[index],7,Color.WHITE if path.name == script_path_selected and index == script_node_selected else color)
			draw_string(get_theme_default_font(),points[index]+Vector2(8,-8),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
		if not points.is_empty(): draw_string(get_theme_default_font(),points[0]+Vector2(8,18),str(path.type)+" Â· "+str(path.name),HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)

func _gui_input(event: InputEvent) -> void:
	if _map_resize_input(event):accept_event();return
	if script_read_only:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					grab_focus()
					if script_path_add_mode: script_node_added.emit(_script_point(event.position))
					else:
						var hit := _script_node_at(event.position)
						if not hit.is_empty():
							script_drag_path = hit.path; script_drag_node = hit.index; script_drag_point = _script_point(event.position, script_drag_path); script_node_picked.emit(hit.path, hit.index)
						else: select_object(String(_hit_test(event.position).get('id', '')))
				elif script_drag_node >= 0:
					var index := script_drag_node; script_drag_node = -1; script_node_changed.emit(script_drag_path, index, _script_point(event.position, script_drag_path))
			elif event.button_index == MOUSE_BUTTON_MIDDLE: panning = event.pressed
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: _zoom_at(event.position, 1.15)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: _zoom_at(event.position, 1.0 / 1.15)
		elif event is InputEventMouseMotion:
			if panning: pan += event.relative; queue_redraw()
			elif script_drag_node >= 0: script_drag_point = _script_point(event.position, script_drag_path); queue_redraw()
		accept_event(); return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: _zoom_at(event.position, 1.15); accept_event(); return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: _zoom_at(event.position, 1.0 / 1.15); accept_event(); return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed; drag_start_mouse = event.position; accept_event(); return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if wall_tool_active:
				if event.pressed:wall_finished.emit()
				accept_event();return
			if event.pressed:
				var selected:=_selected()
				if not selected.is_empty() and _is_scalable(selected) and _resize_handle(_screen_rect(selected)).has_point(event.position):
					resizing=true;drag_start_mouse=event.position;drag_start_size=selected.size
					if String(selected.get("field",""))=="terrain_tiles":selected["terrain_expansion_origin"]=selected.position
				elif map_resize_enabled and _resize_handle(_map_bounds_rect()).has_point(event.position):
					map_resizing=true;drag_start_mouse=event.position;map_drag_start_size=map_size;map_drag_start_center=map_center
				else:
					marquee_selecting=true;marquee_start=event.position;marquee_rect=Rect2(event.position,Vector2.ZERO);queue_redraw()
			else:
				if resizing:
					var object:=_selected();if not object.is_empty() and object.size!=drag_start_size:object_resized.emit(selected_id,drag_start_size,object.size)
				if map_resizing and map_size!=map_drag_start_size:map_bounds_resized.emit(map_size,map_center)
				if marquee_selecting:_apply_marquee_selection();marquee_selecting=false;queue_redraw()
				resizing=false;map_resizing=false
			accept_event();return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if collision_polygon_active:
				if event.pressed:
					var vertex:=_polygon_vertex_at(event.position)
					if vertex>=0:
						if not collision_polygon_closed and vertex==0 and collision_polygon_points.size()>=3:collision_polygon_closed=true;collision_polygon_selected_vertex=0;_emit_collision_polygon("Close polygon")
						else:collision_polygon_selected_vertex=vertex;collision_polygon_drag_vertex=vertex;collision_polygon_drag_before=collision_polygon_points.duplicate()
					elif collision_polygon_closed:
						var edge:=_polygon_edge_at(event.position)
						if edge>=0:collision_polygon_points.insert(edge+1,_polygon_normalized_point(event.position));collision_polygon_selected_vertex=edge+1;_emit_collision_polygon("Insert polygon vertex")
					else:collision_polygon_points.append(_polygon_normalized_point(event.position));collision_polygon_selected_vertex=collision_polygon_points.size()-1;_emit_collision_polygon("Add polygon vertex")
				else:
					if collision_polygon_drag_vertex>=0 and collision_polygon_points!=collision_polygon_drag_before:_emit_collision_polygon("Move polygon vertex")
					collision_polygon_drag_vertex=-1
				queue_redraw();accept_event();return
			if host_picker_active and event.pressed:
				var host_hit:=_hit_test(event.position)
				host_picker_active=false
				host_picked.emit(String(host_hit.get("id","")))
				accept_event();return
			if wall_tool_active:
				if event.pressed: wall_anchor_requested.emit(screen_to_world(event.position));wall_preview=screen_to_world(event.position)
				accept_event();return
			if terrain_brush_mode!="select":
				if event.pressed:
					last_brush_cell=Vector2i(999999,999999);terrain_stroke_started.emit();_emit_brush_cell(event.position)
				else:terrain_stroke_finished.emit();last_brush_cell=Vector2i(999999,999999)
				accept_event();return
			if event.pressed:
				var anchor_hit:=_wall_anchor_hit(event.position)
				if not anchor_hit.is_empty():
					var anchor_key:="%s:%d"%[String(anchor_hit.object.id),int(anchor_hit.index)]
					if not selected_wall_anchors.has(anchor_key):selected_wall_anchors.clear();selected_wall_anchors[anchor_key]=true;selected_ids.clear();selected_ids[String(anchor_hit.object.id)]=true
					select_object(String(anchor_hit.object.id));wall_drag_id=String(anchor_hit.object.id);wall_drag_anchor=int(anchor_hit.index);wall_drag_start_points=_selected_anchor_points()
					accept_event();return
				var hit := _hit_test(event.position)
				if hit.is_empty():
					if event.double_click and selection_mode=="terrain":
						var point:=screen_to_world(event.position)
						terrain_fill_requested.emit(Vector2i(roundi(point.x),roundi(point.y)))
					select_object(""); return
				if event.double_click and fence_edit_mode and String(hit.get("shape",""))=="wall":
					var segment_index:=_wall_segment_at(hit,event.position)
					if segment_index>=0:
						wall_vertex_requested.emit(String(hit.id),segment_index,screen_to_world(event.position));accept_event();return
				if not selected_ids.has(String(hit.id)):selected_ids.clear();selected_ids[String(hit.id)]=true;selected_wall_anchors.clear()
				select_object(String(hit.id))
				if String(hit.get("shape",""))=="wall":
					var nearest:=_wall_anchor_at(hit,event.position)
					if nearest>=0:wall_drag_id=String(hit.id);wall_drag_anchor=nearest
					accept_event();return
				if event.double_click:
					object_activated.emit(String(hit.id)); accept_event(); return
				if bool(hit.get("locked",false)):
					accept_event(); return
				drag_start_mouse = event.position; drag_start_position = hit.position; drag_start_size = hit.size;drag_start_positions={}
				for id in selected_object_ids():var selected_object:=_object_by_id(id);if not selected_object.is_empty():drag_start_positions[id]=selected_object.position
				dragging = true
			else:
				if wall_drag_anchor>=0:
					var delta:=Vector2.ZERO
					if wall_drag_start_points.has("%s:%d"%[wall_drag_id,wall_drag_anchor]):delta=_wall_anchor_current_point(wall_drag_id,wall_drag_anchor)-wall_drag_start_points["%s:%d"%[wall_drag_id,wall_drag_anchor]]
					wall_anchors_moved.emit(selected_wall_anchors.keys(),delta)
					wall_drag_anchor=-1;wall_drag_id=""
				if dragging:
					var moves:Array=[];for id in drag_start_positions:var object:=_object_by_id(String(id));if not object.is_empty() and object.position!=drag_start_positions[id]:moves.append({"id":String(id),"old":drag_start_positions[id],"new":object.position})
					if moves.size()==1:object_moved.emit(String(moves[0].id),moves[0].old,moves[0].new)
					elif moves.size()>1:objects_moved.emit(moves)
				dragging = false
			accept_event()
	elif event is InputEventMouseMotion:
		if collision_polygon_active and collision_polygon_drag_vertex>=0:
			collision_polygon_points[collision_polygon_drag_vertex]=_polygon_normalized_point(event.position);queue_redraw();accept_event();return
		if wall_tool_active:
			wall_preview=screen_to_world(event.position);queue_redraw();accept_event();return
		if panning:
			pan += event.relative; queue_redraw(); accept_event()
		elif marquee_selecting:
			marquee_rect=Rect2(marquee_start,event.position-marquee_start).abs();queue_redraw();accept_event()
		elif dragging:
			var delta := Vector2(event.position.x - drag_start_mouse.x, event.position.y - drag_start_mouse.y) / (pixels_per_unit * zoom)
			for id in drag_start_positions:
				var object:=_object_by_id(String(id));if object.is_empty():continue
				var pos:Vector3=drag_start_positions[id]+Vector3(delta.x,0,delta.y)
				var snap_step:=0.1 if String(object.get("field",""))=="asset_collision" else grid_size
				if snapping:pos=Vector3(snappedf(pos.x,snap_step),pos.y,snappedf(pos.z,snap_step))
				object.position=pos
			invalidate_order_cache();queue_redraw()
		elif wall_drag_anchor>=0:
			var point:=screen_to_world(event.position);if snapping:point=Vector2(snappedf(point.x,grid_size),snappedf(point.y,grid_size))
			var start:Vector2=wall_drag_start_points.get("%s:%d"%[wall_drag_id,wall_drag_anchor],point);var delta:Vector2=point-start
			for key in wall_drag_start_points:
				var parts:=String(key).split(":");var wall:=_object_by_id(parts[0]);if not wall.is_empty():wall.wall_points[int(parts[1])]=wall_drag_start_points[key]+delta
			invalidate_order_cache();queue_redraw()
		elif resizing:
			var object := _selected()
			if not object.is_empty():
				var delta := Vector2(event.position.x - drag_start_mouse.x, event.position.y - drag_start_mouse.y) / (pixels_per_unit * zoom)
				if String(object.get("field",""))=="terrain_tiles":
					_preview_terrain_expansion(object,delta);queue_redraw();return
				var snap_step:=0.1 if String(object.get("field",""))=="asset_collision" else grid_size
				var new_size := Vector3(maxf(snap_step, drag_start_size.x + delta.x * 2.0), drag_start_size.y, maxf(snap_step, drag_start_size.z + delta.y * 2.0))
				if snapping: new_size = Vector3(snappedf(new_size.x, snap_step), new_size.y, snappedf(new_size.z, snap_step))
				object.size = new_size; invalidate_order_cache();queue_redraw()
		elif map_resizing:
			var delta:=Vector2(event.position.x-drag_start_mouse.x,event.position.y-drag_start_mouse.y)/(pixels_per_unit*zoom*_ground_projection())
			var new_map_size:=Vector2(maxf(grid_size,map_drag_start_size.x+delta.x),maxf(grid_size,map_drag_start_size.y+delta.y))
			if snapping:new_map_size=Vector2(snappedf(new_map_size.x,grid_size),snappedf(new_map_size.y,grid_size))
			map_size=new_map_size;map_center=map_drag_start_center+(map_size-map_drag_start_size)*0.5;queue_redraw()
		elif terrain_brush_mode!="select" and (event.button_mask&MOUSE_BUTTON_MASK_LEFT)!=0:_emit_brush_cell(event.position)

func _apply_marquee_selection()->void:
	selected_ids.clear();selected_wall_anchors.clear()
	for object in objects:
		if not _selection_mode_allows(object):continue
		if String(object.get("shape",""))=="wall":
			var points:Array=object.get("wall_points",[])
			for index in points.size():
				if marquee_rect.has_point(world_to_screen(points[index])):selected_wall_anchors["%s:%d"%[String(object.id),index]]=true;selected_ids[String(object.id)]=true
		elif marquee_rect.intersects(_screen_rect(object),true): selected_ids[String(object.id)]=true
	if selected_ids.is_empty():select_object("");return
	var first_id:=String(selected_ids.keys()[0]);select_object(first_id)

func _object_by_id(id:String)->Dictionary:
	for object in objects:if String(object.id)==id:return object
	return {}

func _selected_anchor_points()->Dictionary:
	var result:Dictionary={}
	for key in selected_wall_anchors:
		var parts:=String(key).split(":");var wall:=_object_by_id(parts[0]);var index:=int(parts[1])
		if not wall.is_empty() and index>=0 and index<wall.wall_points.size():result[String(key)]=wall.wall_points[index]
	return result

func _wall_anchor_current_point(id:String,index:int)->Vector2:
	var wall:=_object_by_id(id)
	return wall.wall_points[index] if not wall.is_empty() and index>=0 and index<wall.wall_points.size() else Vector2.ZERO

func _emit_brush_cell(screen_position:Vector2)->void:
	var world:=screen_to_world(screen_position);var cell:=Vector2i(roundi(world.x),roundi(world.y))
	if cell==last_brush_cell:return
	last_brush_cell=cell;terrain_cell_changed.emit(cell,terrain_brush_mode=="erase")

func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_position)
	zoom = clampf(zoom * factor, 0.15, 6.0)
	var after := screen_to_world(screen_position)
	pan += (after - before) * pixels_per_unit * zoom * _ground_projection()
	queue_redraw()

func world_to_screen(world: Vector2) -> Vector2:
	# The editable plane is world X/Z. Godot gameplay treats negative Z as
	# north/up, so screen Y must increase with Z (not with -Z).
	return size * 0.5 + pan + Vector2(world.x, world.y) * pixels_per_unit * zoom * _ground_projection()

func screen_to_world(screen: Vector2) -> Vector2:
	var value := (screen - size * 0.5 - pan) / (pixels_per_unit * zoom * _ground_projection())
	return Vector2(value.x, value.y)

func _object_anchor_screen(object: Dictionary) -> Vector2:
	var point := world_to_screen(Vector2(object.position.x, object.position.z))
	if script_read_only and object.get("field", "") == "npcs":
		point.y -= float(object.get("visual_elevation", 0.0)) * sqrt(0.5) * pixels_per_unit * zoom
	return point

func _screen_rect(object: Dictionary) -> Rect2:
	if String(object.get("shape",""))=="wall":
		var points:Array=object.get("wall_points",[]);if points.is_empty():return Rect2()
		var result:=Rect2(world_to_screen(points[0]),Vector2.ZERO)
		for point in points:result=result.expand(world_to_screen(point))
		return result.grow(7)
	if script_read_only and object.get("field", "") == "npcs":
		var texture: Texture2D = object.get("resolved_texture")
		var height := float(object.get("display_height", 0.9)) * pixels_per_unit * zoom
		var width := height * (float(texture.get_width()) / texture.get_height() if texture != null else 1.0)
		return Rect2(_object_anchor_screen(object) - Vector2(width * 0.5, height), Vector2(width, height))
	var fp: Vector2 = object.get("footprint", Vector2(0.8,0.8))
	if _is_scalable(object): fp = Vector2(object.size.x, object.size.z)
	var offset:Vector2=object.get("footprint_offset",Vector2.ZERO)
	return Rect2(world_to_screen(Vector2(object.position.x,object.position.z))+offset*pixels_per_unit*zoom-fp*pixels_per_unit*zoom*0.5,fp*pixels_per_unit*zoom)

func _map_bounds_rect()->Rect2:
	return Rect2(world_to_screen(map_center-map_size*0.5),map_size*pixels_per_unit*zoom*_ground_projection())

func _map_resize_handles()->Dictionary:
	var bounds:=_map_bounds_rect();var center:=bounds.get_center()
	var positions:={"west":Vector2(bounds.position.x-22,center.y),"east":Vector2(bounds.end.x+22,center.y),"north":Vector2(center.x,bounds.position.y-22),"south":Vector2(center.x,bounds.end.y+22)}
	var handles:Dictionary={}
	for edge:String in positions:
		var point:Vector2=positions[edge]
		point=point.clamp(Vector2(20,32),size-Vector2(20,32))
		handles[edge]=Rect2(point-Vector2(16,16),Vector2(32,32))
	return handles

func _draw_map_resize_arrows()->void:
	var directions:={"west":Vector2.LEFT,"east":Vector2.RIGHT,"north":Vector2.UP,"south":Vector2.DOWN}
	for edge:String in _map_resize_handles():
		var rect:Rect2=_map_resize_handles()[edge];var point:=rect.get_center();var direction:Vector2=directions[edge]
		var color:=Color("#ffe16b") if map_resize_edge==edge else Color("#a6f06c")
		draw_style_box(get_theme_stylebox("normal","Button"),rect)
		draw_line(point-direction*9,point+direction*9,color,3,true)
		draw_line(point+direction*9,point+direction*2+direction.orthogonal()*6,color,3,true)
		draw_line(point+direction*9,point+direction*2-direction.orthogonal()*6,color,3,true)
	draw_string(get_theme_default_font(),Vector2(14,size.y-16),"Drag an arrow to move only that edge · %.1f × %.1f"%[map_size.x,map_size.y],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#a6f06c"))

func cancel_map_resize()->void:
	if map_resizing:map_size=map_drag_start_size;map_center=map_drag_start_center
	map_resizing=false;map_resize_edge="";queue_redraw()

func _map_resize_input(event:InputEvent)->bool:
	if not map_resize_enabled:return false
	if not map_resize_edge.is_empty():
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:cancel_map_resize();return true
		if event is InputEventMouseMotion:
			var delta:Vector2=(event.position-drag_start_mouse)/(pixels_per_unit*zoom*_ground_projection())
			var step:=grid_size if snapping else 0.1
			map_size=map_drag_start_size
			map_center=map_drag_start_center
			if map_resize_edge in ["east","west"]:
				var sign_x:=1 if map_resize_edge=="east" else -1
				map_size.x=maxf(step,map_drag_start_size.x+delta.x*sign_x)
				if snapping:map_size.x=maxf(step,snappedf(map_size.x,step))
				map_center.x=map_drag_start_center.x+(map_size.x-map_drag_start_size.x)*sign_x*0.5
			else:
				var sign_y:=1 if map_resize_edge=="south" else -1
				map_size.y=maxf(step,map_drag_start_size.y+delta.y*sign_y)
				if snapping:map_size.y=maxf(step,snappedf(map_size.y,step))
				map_center.y=map_drag_start_center.y+(map_size.y-map_drag_start_size.y)*sign_y*0.5
			queue_redraw();return true
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			map_resizing=false;map_resize_edge=""
			if not map_size.is_equal_approx(map_drag_start_size):map_bounds_resized.emit(map_size,map_center)
			queue_redraw();return true
		return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		for edge:String in _map_resize_handles():
			if _map_resize_handles()[edge].has_point(event.position):
				map_resize_edge=edge;map_resizing=true;map_drag_start_size=map_size;map_drag_start_center=map_center;drag_start_mouse=event.position;grab_focus();return true
	return false

func _resize_handle(rect:Rect2)->Rect2:
	return Rect2(rect.end-Vector2(12,12),Vector2(12,12))

func _preview_terrain_expansion(object:Dictionary,delta:Vector2)->void:
	# Canonical terrain is a grid of cells: keep the original cell anchored and
	# grow only toward the drag, independently on each axis.
	var cells:=Vector2i(roundi(delta.x),roundi(delta.y))
	var origin:Vector3=object.get("terrain_expansion_origin",object.position)
	object["terrain_expansion_min"]=Vector2i(roundi(origin.x)+mini(0,cells.x),roundi(origin.z)+mini(0,cells.y))
	object.position=origin+Vector3(cells.x*0.5,0,cells.y*0.5)
	object.size=Vector3(absi(cells.x)+1,1,absi(cells.y)+1)
	invalidate_order_cache()

func _is_scalable(object:Dictionary)->bool:
	return String(object.get("shape","point")) in ["rectangle","building","terrain"]

func _hit_test(screen_position: Vector2) -> Dictionary:
	for object in _ordered_selection_candidates():
		if String(object.get("shape",""))=="wall":
			if not fence_edit_mode:continue
			for point in object.get("wall_points",[]):if world_to_screen(point).distance_to(screen_position)<10:return object
			for i in range(1,object.get("wall_points",[]).size()):
				if Geometry2D.get_closest_point_to_segment(screen_position,world_to_screen(object.wall_points[i-1]),world_to_screen(object.wall_points[i])).distance_to(screen_position)<8:return object
		if _screen_rect(object).grow(5).has_point(screen_position): return object
	return {}

func _wall_anchor_hit(screen_position:Vector2)->Dictionary:
	if selection_mode!="objects" or not fence_edit_mode:return {}
	var wall_candidates:Array[Dictionary]=[]
	var selected:=_selected()
	if not selected.is_empty() and String(selected.get("shape",""))=="wall":wall_candidates.append(selected)
	for object in objects:
		if String(object.get("shape",""))=="wall" and (selected.is_empty() or String(object.id)!=String(selected.id)):wall_candidates.append(object)
	for wall in wall_candidates:
		var indices:Array[int]=[];var points:Array=wall.get("wall_points",[])
		for index in points.size():
			if world_to_screen(points[index]).distance_to(screen_position)<=14.0:indices.append(index)
		if indices.is_empty():continue
		indices.sort_custom(func(a:int,b:int):return world_to_screen(points[a]).distance_squared_to(screen_position)<world_to_screen(points[b]).distance_squared_to(screen_position))
		var same_click:=last_wall_anchor_click_id==String(wall.id) and last_wall_anchor_click_position.distance_to(screen_position)<=3.0
		wall_anchor_click_cycle=(wall_anchor_click_cycle+1)%indices.size() if same_click else 0
		last_wall_anchor_click_id=String(wall.id);last_wall_anchor_click_position=screen_position
		return {"object":wall,"index":indices[wall_anchor_click_cycle]}
	last_wall_anchor_click_id="";wall_anchor_click_cycle=0
	return {}

func _selection_rank(object:Dictionary)->int:
	if String(object.get("role", "")) == "marker": return 100
	if fence_edit_mode and String(object.get("shape",""))=="wall":return 90
	if _is_terrain_object(object):return -100
	return _draw_rank(object)

func set_selection_mode(mode:String)->void:
	if terrain_brush_mode!="select":terrain_stroke_finished.emit()
	terrain_brush_mode="select"
	last_brush_cell=Vector2i(999999,999999)
	selection_mode=mode if mode in ["terrain","objects"] else "objects"
	var selected:=_selected()
	if not selected.is_empty() and not _selection_mode_allows(selected):select_object("")
	selected_ids.clear();selected_wall_anchors.clear();queue_redraw()

func _selection_mode_allows(object:Dictionary)->bool:
	return _is_terrain_object(object) if selection_mode=="terrain" else not _is_terrain_object(object)

func _is_terrain_object(object:Dictionary)->bool:
	var field:=String(object.get("field",""))
	var type_id:=String(object.get("universal_type",""))
	return String(object.get("role",""))=="terrain" or field in ["terrain_tiles","water_blocks","sand_blocks","floor_blocks"] or type_id.begins_with("tile.") or type_id.begins_with("terrain.") or type_id=="block.water"

func _wall_anchor_at(object:Dictionary,screen_position:Vector2)->int:
	var points:Array=object.get("wall_points",[])
	for i in points.size():
		if world_to_screen(points[i]).distance_to(screen_position)<=10:return i
	return -1

func _wall_segment_at(object:Dictionary,screen_position:Vector2)->int:
	var points:Array=object.get("wall_points",[])
	for index in range(1,points.size()):
		var start:=world_to_screen(points[index-1]);var finish:=world_to_screen(points[index])
		if Geometry2D.get_closest_point_to_segment(screen_position,start,finish).distance_to(screen_position)<=8.0:return index-1
	return -1

func _selected() -> Dictionary:
	for object in objects:
		if String(object.id) == selected_id: return object
	return {}
