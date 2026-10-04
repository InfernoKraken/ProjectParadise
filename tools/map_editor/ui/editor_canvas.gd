class_name EditorCanvas
extends Control

const WallGeometryRef := preload("res://core/wall_geometry.gd")

signal object_selected(object_id: String)
signal object_activated(object_id: String)
signal object_moved(object_id: String, old_position: Vector3, new_position: Vector3)
signal objects_moved(moves: Array)
signal object_resized(object_id: String, old_size: Vector3, new_size: Vector3)
signal map_resized(old_size: Vector2, new_size: Vector2)
signal terrain_stroke_started()
signal terrain_cell_changed(cell: Vector2i, erase: bool)
signal terrain_stroke_finished()
signal wall_anchor_requested(point: Vector2)
signal wall_finished()
signal wall_anchor_moved(object_id: String, anchor_index: int, point: Vector2)
signal wall_anchors_moved(anchor_keys: Array, delta: Vector2)
signal host_picked(object_id: String)
signal collision_polygon_changed(points: Array, closed: bool, action: String)

var objects: Array[Dictionary] = []
var selected_id := ""
var selected_ids: Dictionary = {}
var selected_wall_anchors: Dictionary = {}
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
var map_resizing := false
var panning := false
var drag_start_mouse := Vector2.ZERO
var drag_start_position := Vector3.ZERO
var drag_start_size := Vector3.ZERO
var drag_start_positions: Dictionary = {}
var map_drag_start_size := Vector2.ZERO
var terrain_brush_mode := "select"
var selection_mode := "objects"
var terrain_error_cells: Dictionary = {}
var validation_error_ids: Dictionary = {}
var last_brush_cell := Vector2i(999999,999999)
var wall_tool_active := false
var wall_preview := Vector2.ZERO
var wall_drag_anchor := -1
var wall_drag_id := ""
var wall_drag_start_points: Dictionary = {}
var last_wall_anchor_click_id := ""
var last_wall_anchor_click_position := Vector2.INF
var wall_anchor_click_cycle := 0
var debug_geometry := false
var placement_preview := false
var base_terrain_texture_path := ""
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

func set_document_objects(new_objects: Array[Dictionary], new_map_size: Vector2) -> void:
	objects = new_objects
	map_size = new_map_size
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
	pan = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#151a20"))
	var bounds := Rect2(world_to_screen(Vector2(-map_size.x * 0.5, -map_size.y * 0.5)), Vector2(map_size.x, map_size.y) * pixels_per_unit * zoom)
	if placement_preview:
		_draw_ground(bounds)
	else:
		_draw_grid()
		draw_rect(bounds, Color("#29433288"), true)
		draw_rect(bounds, Color("#7dab85"), false, 2.0)
		draw_rect(_resize_handle(bounds), Color("#a6f06c"), true)
		draw_rect(_resize_handle(bounds), Color("#eaffd8"), false, 2.0)
	var draw_objects:=objects.duplicate()
	# Match the runtime's Node2D Y-sort model: fixed world layers first, then
	# ground-contact depth. Screen Y increases with world Z in this top-down
	# canvas, so objects farther south must be painted later/in front.
	draw_objects.sort_custom(func(a,b):return _draws_before(a,b))
	for object in draw_objects: _draw_object(object)
	if collision_polygon_active:_draw_collision_polygon()
	if not placement_preview:
		for cell in terrain_error_cells:
			var center:=world_to_screen(Vector2(cell));var rect:=Rect2(center-Vector2.ONE*pixels_per_unit*zoom*0.5,Vector2.ONE*pixels_per_unit*zoom)
			draw_rect(rect,Color("#ff334466"),true);draw_rect(rect,Color("#ff3344"),false,3.0)
	if marquee_selecting and not placement_preview:
		draw_rect(marquee_rect,Color("#72d7ff33"),true)
		draw_rect(marquee_rect,Color("#72d7ff"),false,2.0)
	if not placement_preview:
		draw_string(get_theme_default_font(), Vector2(size.x * 0.5 - 24, 20), "N  (-Z)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#b8c9d8"))
		if terrain_brush_mode!="select":draw_string(get_theme_default_font(),Vector2(14,size.y-16),"Terrain %s · 1×1 snapped cells"%terrain_brush_mode.capitalize(),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#ffe16b"))

func _draw_ground(bounds: Rect2) -> void:
	var texture := _texture_for(base_terrain_texture_path)
	if texture != null:
		draw_texture_rect(texture, bounds, true, Color.WHITE)
	else:
		draw_rect(bounds, Color("#294332"), true)

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
	return Vector2(clampf(local.x/maxf(rect.size.x,0.001)+0.5,0.0,1.0),clampf(local.y/maxf(rect.size.y,0.001)+0.5,0.0,1.0))

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

func _draw_object(object: Dictionary) -> void:
	if String(object.get("shape",""))=="wall":
		_draw_wall(object)
		return
	var position: Vector3 = object.position
	var center := world_to_screen(Vector2(position.x, position.z))
	var footprint: Vector2 = object.get("footprint", Vector2(0.8, 0.8))
	if _is_scalable(object): footprint = Vector2(object.size.x, object.size.z)
	var footprint_offset:Vector2=object.get("footprint_offset",Vector2.ZERO)
	var rect := Rect2(center+footprint_offset*pixels_per_unit*zoom-footprint*pixels_per_unit*zoom*0.5,footprint*pixels_per_unit*zoom)
	var color: Color = object.get("color", Color("#dce6ee"))
	if object.get("shape", "point") in ["rectangle","terrain"]:
		var texture:Texture2D = object.get("resolved_texture") if object.has("resolved_texture") else _texture_for(String(object.get("texture", "")))
		if texture != null:
			# Gameplay repeats block textures across the serialized X/Z dimensions.
			# Tile the same source art here so large interior floors and thin wall
			# strips read like their in-game counterparts instead of flat overlays.
			if String(object.get("universal_type","")).begins_with("tile."):
				draw_set_transform(center,deg_to_rad(float(object.get("rotation_degrees",0.0))),Vector2.ONE)
				draw_texture_rect(texture,Rect2(-rect.size*0.5,rect.size),false,Color(1,1,1,0.96))
				draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
			else:draw_texture_rect(texture, rect, true, Color(1,1,1,0.92))
			if not placement_preview: draw_rect(rect, Color(color, 0.12), true)
		else:
			draw_rect(rect, Color(color, 0.32), true)
		if not placement_preview: draw_rect(rect, color, false, 2.0)
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
		if not placement_preview:
			draw_rect(rect, Color(color, 0.18), true)
			draw_rect(rect, color, false, 1.0)
	if String(object.id) == selected_id and not placement_preview:
		draw_rect(rect.grow(3), Color("#ffe16b"), false, 3.0)
		if _is_scalable(object): draw_rect(_resize_handle(rect), Color("#ffe16b"), true)
	elif selected_ids.has(String(object.id)) and not placement_preview:
		draw_rect(rect.grow(2), Color("#72d7ff"), false, 2.0)
	if validation_error_ids.has(String(object.id)) and not placement_preview:draw_rect(rect.grow(2),Color("#ff3344"),false,3.0)
	var label := String(object.get("label", object.get("field", "object")))
	if not placement_preview: draw_string(get_theme_default_font(), center + Vector2(7, -7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _draw_wall(object:Dictionary)->void:
	var points:Array=object.get("wall_points",[]);if points.is_empty():return
	var color:Color=object.get("color",Color("#dce6ee"));var bounds:=Rect2(world_to_screen(points[0]),Vector2.ZERO)
	for i in range(1,points.size()):
		var a:=world_to_screen(points[i-1]);var b:=world_to_screen(points[i]);draw_line(a,b,Color(color,0.9),maxf(3.0,8.0*zoom));draw_line(a,b,Color("#303942"),1.0);bounds=bounds.expand(a).expand(b)
	if not placement_preview:
		for point in points:
			var screen:=world_to_screen(point);var anchor_key:="%s:%d"%[String(object.id),points.find(point)];draw_circle(screen,6.0,Color("#72d7ff") if selected_wall_anchors.has(anchor_key) else (Color("#ffe16b") if String(object.id)==selected_id else color));draw_circle(screen,2.5,Color.WHITE)
		if String(object.id)==selected_id:draw_rect(bounds.grow(8),Color("#ffe16b"),false,2.0)
		if debug_geometry and String(object.id)==selected_id:_draw_wall_debug_geometry(object)
		if wall_tool_active and String(object.id)==selected_id and points.size()>0:_draw_wall_route_preview(points[-1],wall_preview)
		draw_string(get_theme_default_font(),world_to_screen(points[0])+Vector2(7,-9),String(object.get("label","Wall / Fence")),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)

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
			var piece_length:=minf(1.0,length-float(piece));var origin:=a+direction*(float(piece)+piece_length*.5);var r:=PackedVector2Array([world_to_screen(origin-direction*piece_length*.5-normal*.18),world_to_screen(origin+direction*piece_length*.5-normal*.18),world_to_screen(origin+direction*piece_length*.5+normal*.18),world_to_screen(origin-direction*piece_length*.5+normal*.18)]);draw_polyline(PackedVector2Array([r[0],r[1],r[2],r[3],r[0]]),Color("#ff4fd8"),1.5);draw_string(get_theme_default_font(),world_to_screen(origin)+Vector2(2,-3),"×",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("#ff4fd8"))
		draw_string(get_theme_default_font(),world_to_screen((a+b)*.5)+Vector2(8,-9),"%s %.2fu"%[String(segment.get("direction","")),length],HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color.WHITE)
	var first:=world_to_screen(points[0]);draw_line(first-Vector2(9,0),first+Vector2(9,0),Color("#ff9d4d"),2);draw_line(first-Vector2(0,9),first+Vector2(0,9),Color("#ff9d4d"),2)
	draw_string(get_theme_default_font(),Vector2(14,42),"Debug: white=path · cyan=collision · magenta=sprite pieces · yellow=anchors · orange=origin",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("#f1f4f8"))

func _texture_for(relative_path: String) -> Texture2D:
	if relative_path.is_empty() or project_root.is_empty(): return null
	if texture_cache.has(relative_path): return texture_cache[relative_path]
	var image := Image.load_from_file(project_root.path_join(relative_path))
	if image == null or image.is_empty(): texture_cache[relative_path] = null; return null
	var texture := ImageTexture.create_from_image(image)
	texture_cache[relative_path] = texture
	return texture

func _draw_rank(object:Dictionary)->int:
	if _is_terrain_object(object):return 0
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
	return position.z+float(object.get("sort_offset_y",0.0))

func _gui_input(event: InputEvent) -> void:
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
				elif _resize_handle(_map_bounds_rect()).has_point(event.position):
					map_resizing=true;drag_start_mouse=event.position;map_drag_start_size=map_size
				else:
					marquee_selecting=true;marquee_start=event.position;marquee_rect=Rect2(event.position,Vector2.ZERO);queue_redraw()
			else:
				if resizing:
					var object:=_selected();if not object.is_empty() and object.size!=drag_start_size:object_resized.emit(selected_id,drag_start_size,object.size)
				if map_resizing and map_size!=map_drag_start_size:map_resized.emit(map_drag_start_size,map_size)
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
				if hit.is_empty(): select_object(""); return
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
			queue_redraw()
		elif wall_drag_anchor>=0:
			var point:=screen_to_world(event.position);if snapping:point=Vector2(snappedf(point.x,grid_size),snappedf(point.y,grid_size))
			var start:Vector2=wall_drag_start_points.get("%s:%d"%[wall_drag_id,wall_drag_anchor],point);var delta:Vector2=point-start
			for key in wall_drag_start_points:
				var parts:=String(key).split(":");var wall:=_object_by_id(parts[0]);if not wall.is_empty():wall.wall_points[int(parts[1])]=wall_drag_start_points[key]+delta
			queue_redraw()
		elif resizing:
			var object := _selected()
			if not object.is_empty():
				var delta := Vector2(event.position.x - drag_start_mouse.x, event.position.y - drag_start_mouse.y) / (pixels_per_unit * zoom)
				var snap_step:=0.1 if String(object.get("field",""))=="asset_collision" else grid_size
				var new_size := Vector3(maxf(snap_step, drag_start_size.x + delta.x * 2.0), drag_start_size.y, maxf(snap_step, drag_start_size.z + delta.y * 2.0))
				if snapping: new_size = Vector3(snappedf(new_size.x, snap_step), new_size.y, snappedf(new_size.z, snap_step))
				object.size = new_size; queue_redraw()
		elif map_resizing:
			var delta:=Vector2(event.position.x-drag_start_mouse.x,event.position.y-drag_start_mouse.y)/(pixels_per_unit*zoom)
			var new_map_size:=Vector2(maxf(grid_size,map_drag_start_size.x+delta.x*2.0),maxf(grid_size,map_drag_start_size.y+delta.y*2.0))
			if snapping:new_map_size=Vector2(snappedf(new_map_size.x,grid_size),snappedf(new_map_size.y,grid_size))
			map_size=new_map_size;queue_redraw()
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
	if String(object.get("shape",""))=="wall":
		var points:Array=object.get("wall_points",[]);if points.is_empty():return Rect2()
		var result:=Rect2(world_to_screen(points[0]),Vector2.ZERO)
		for point in points:result=result.expand(world_to_screen(point))
		return result.grow(7)
	var fp: Vector2 = object.get("footprint", Vector2(0.8,0.8))
	if _is_scalable(object): fp = Vector2(object.size.x, object.size.z)
	var offset:Vector2=object.get("footprint_offset",Vector2.ZERO)
	return Rect2(world_to_screen(Vector2(object.position.x,object.position.z))+offset*pixels_per_unit*zoom-fp*pixels_per_unit*zoom*0.5,fp*pixels_per_unit*zoom)

func _map_bounds_rect()->Rect2:
	return Rect2(world_to_screen(Vector2(-map_size.x*0.5,-map_size.y*0.5)),map_size*pixels_per_unit*zoom)

func _resize_handle(rect:Rect2)->Rect2:
	return Rect2(rect.end-Vector2(12,12),Vector2(12,12))

func _is_scalable(object:Dictionary)->bool:
	return String(object.get("shape","point")) in ["rectangle","building","terrain"]

func _hit_test(screen_position: Vector2) -> Dictionary:
	var hit_objects:=objects.duplicate()
	# Selection mirrors visual stacking. Broad floor rectangles are deliberately
	# last so furniture, NPCs, markers, and walls remain clickable above them.
	hit_objects.sort_custom(func(a,b):return _selection_rank(a)>_selection_rank(b))
	for object in hit_objects:
		if not _selection_mode_allows(object):continue
		if String(object.get("shape",""))=="wall":
			for point in object.get("wall_points",[]):if world_to_screen(point).distance_to(screen_position)<10:return object
			for i in range(1,object.get("wall_points",[]).size()):
				if Geometry2D.get_closest_point_to_segment(screen_position,world_to_screen(object.wall_points[i-1]),world_to_screen(object.wall_points[i])).distance_to(screen_position)<8:return object
		if _screen_rect(object).grow(5).has_point(screen_position): return object
	return {}

func _wall_anchor_hit(screen_position:Vector2)->Dictionary:
	if selection_mode!="objects":return {}
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
	if _is_terrain_object(object):return -100
	return _draw_rank(object)

func set_selection_mode(mode:String)->void:
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

func _selected() -> Dictionary:
	for object in objects:
		if String(object.id) == selected_id: return object
	return {}
