class_name AssetCatalog
extends RefCounted

var entries: Array = []
var by_id: Dictionary = {}
var error := ""
var water_decoration: Script

static func load_catalog(path: String) -> AssetCatalog:
	var catalog := AssetCatalog.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: catalog.error = "Could not open asset catalog."; return catalog
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		catalog.error = "Invalid asset catalog JSON."; return catalog
	catalog.entries = json.data.get("entries", [])
	catalog._append_imported_overworld_sprites(path)
	catalog._apply_animation_previews(path)
	for entry in catalog.entries: catalog.by_id[String(entry.get("type_id", ""))] = entry
	return catalog

func _append_imported_overworld_sprites(catalog_path: String) -> void:
	# The editor is its own Godot project, so scan the game project's files rather
	# than relying on its res:// import database.  A sibling .import file is the
	# project's explicit signal that Godot has accepted the source image.
	var project_root := catalog_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	var asset_root := project_root.path_join("assets/overworld")
	water_decoration = load(project_root.path_join("world/water_decoration.gd"))
	_append_imported_directory(asset_root, project_root)

func _append_imported_directory(directory_path: String, project_root: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null: return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if not directory.current_is_dir() and name.get_extension().to_lower() in ["png", "webp", "jpg", "jpeg"]:
			var absolute_path := directory_path.path_join(name)
			var relative_path := absolute_path.trim_prefix(project_root.path_join(""))
			if relative_path.begins_with("/") or relative_path.begins_with("\\"): relative_path = relative_path.substr(1)
			if not relative_path.contains("terrain_masks/") and not relative_path.begins_with("assets/overworld/anim/") and not entries.any(func(entry): return String(entry.get("preview_texture", "")) == relative_path):
				_append_imported_sprite(relative_path,name.get_basename(),project_root)
		name = directory.get_next()
	directory.list_dir_end()
	# Include imported sprites in nested folders such as terrain_masks as well.
	directory = DirAccess.open(directory_path)
	if directory == null: return
	directory.list_dir_begin()
	name = directory.get_next()
	while not name.is_empty():
		if directory.current_is_dir() and not name.begins_with("."):
			_append_imported_directory(directory_path.path_join(name), project_root)
		name = directory.get_next()
	directory.list_dir_end()

func _append_imported_sprite(relative_path:String,filename:String,project_root:String)->void:
	# These assets need a separate future split-surface implementation.
	if filename.begins_with("semi_submerged_"): return
	var relative_id:=relative_path.trim_prefix("assets/overworld/").get_basename().replace("/","_").replace(" ","_").to_lower()
	var family_id:=relative_id;var variant_value:=-1
	if relative_id.length()>3 and relative_id.substr(relative_id.length()-3,1)=="_" and relative_id.right(2).is_valid_int():
		family_id=relative_id.left(relative_id.length()-3);variant_value=int(relative_id.right(2))
	if family_id in ["moss_rose","sunflower_cluster"] and variant_value>=0:family_id+="_small"
	var is_building:=family_id=="building_tropical_research_lab"
	var is_stream_tile:=family_id.begins_with("overlay_terrain_stream") or family_id=="overlay_stream_north"
	var is_overlay:=family_id.begins_with("overlay_") and not is_stream_tile
	var type_id:=("building." if is_building else ("tile." if is_stream_tile else ("overlay." if is_overlay else "asset.")))+family_id.trim_prefix("overlay_")
	var variant_record:={"value":variant_value,"name":"Variant %02d"%variant_value,"preview_texture":relative_path,"asset_path":"res://"+relative_path}
	if variant_value>=0:
		for existing:Variant in entries:
			if existing is Dictionary and String(existing.get("type_id",""))==type_id:
				existing.variants.append(variant_record);existing.variants.sort_custom(func(a,b):return int(a.value)<int(b.value));existing.preview_texture=existing.variants[0].preview_texture;existing.asset_path=existing.variants[0].asset_path;return
	var label_id:=family_id
	var labels:=_palette_labels_for(relative_path,label_id)
	var is_small_plant:=family_id in ["aloe_small","moss_rose_small"]
	var stream_size:=[1.0,0.2,1.0]
	if is_stream_tile:
		var image:=Image.load_from_file(project_root.path_join(relative_path))
		if image!=null and not image.is_empty():stream_size=[float(image.get_width())/maxf(float(image.get_height()),1.0),0.2,1.0]
	var entry:={"type_id":type_id,"display_name":labels.name.trim_prefix("Overlay "),"category":"Water Terrain" if is_stream_tile else ("Overlays" if is_overlay else labels.category),"preview_texture":relative_path,"asset_path":"res://"+relative_path,"scale_mode":"explicit_size" if is_stream_tile else ("target_width" if is_building else "target_height"),"display_height":0.45 if is_small_plant else 1.0,"default_size":stream_size if is_stream_tile else null,"default_y":1.5 if is_building else (0.2 if is_small_plant else 0.0),"footprint":"serialized size.xz" if is_building or is_stream_tile else ([0.4,0.3] if is_small_plant else [0.8,0.8]),"front_depth_extension":0.0,"snap":0.5 if is_small_plant else 0.1,"collision":{"shape":"box","from_serialized_size":true,"terrain_layer":"water"} if is_stream_tile else ({"shape":"box","from_serialized_size":true,"anchor":"front"} if is_building else {"shape":"none"}),"supports_rotation":is_overlay or is_stream_tile,"inherits":"block.water" if is_stream_tile else "","variants":[variant_record] if variant_value>=0 else [],"serialization":{"kind":"object","fields":["objects"],"object_type":type_id},"coordinate_space":"map_local"}
	if not is_stream_tile:entry.erase("default_size")
	var metadata:=load_metadata(project_root.path_join(relative_path))
	if metadata.get("collision") is Dictionary and String(metadata.collision.get("type",""))=="polygon":entry["collision"]=metadata.collision.duplicate(true)
	if bool(metadata.get("standardize_scale",false)):
		entry["display_height"]=float(metadata.get("visual_height",entry.display_height))
		var shared_size:Variant=metadata.get("size",[])
		if shared_size is Array and shared_size.size()>=3:entry["default_size"]=shared_size.duplicate()
	var water_kind: String = water_decoration.kind(relative_path)
	if not water_kind.is_empty():
		entry["water_kind"] = water_kind
		entry["render_band"] = water_decoration.render_band(water_kind)
		entry["category"] = "Water Floaters" if water_kind == "floater" else "Water Submerged"
		entry["collision"] = {"shape":"none"}
		entry["supports_rotation"] = true
	entries.append(entry)

func _palette_labels_for(relative_path:String, filename:String)->Dictionary:
	var words:=filename.replace("_"," ").replace("-"," ").capitalize()
	var lower:=filename.to_lower()
	var category:="Props"
	if lower.begins_with("building") or lower.begins_with("citybuilding"): category="Buildings"
	elif lower.begins_with("boat") or lower.begins_with("canal"): category="Watercraft & Canal"
	elif lower.begins_with("rocks_"): category="Rocks"
	elif lower.begins_with("tree") or lower.begins_with("flower") or lower.begins_with("vines") or lower.begins_with("habitat") or lower.begins_with("sunflower") or lower.begins_with("aloe") or lower.begins_with("desert_rose") or lower.begins_with("moss_rose"): category="Vegetation"
	elif lower.begins_with("tile") or relative_path.contains("terrain_masks/"): category="Terrain"
	elif lower.begins_with("wall"): category="Walls & Fences"
	elif lower.begins_with("warp") or lower.begins_with("sign"): category="Markers"
	elif lower.begins_with("indoor") or lower.begins_with("bed") or lower.begins_with("table") or lower.begins_with("dresser") or lower.begins_with("hutch") or lower.begins_with("lampstand"): category="Interior Furniture"
	return {"category":category,"name":words}

static func metadata_path(asset_path:String)->String:
	return asset_path.trim_suffix(".png")+".json"

static func load_metadata(asset_path:String)->Dictionary:
	var target:=metadata_path(asset_path)
	var file:=FileAccess.open(target if target.is_absolute_path() else ProjectSettings.globalize_path(target),FileAccess.READ)
	if file==null:return {"collision_boxes":[]}
	var json:=JSON.new()
	return json.data if json.parse(file.get_as_text())==OK and json.data is Dictionary else {"collision_boxes":[]}

static func validate_polygon_collision(collision:Variant)->Array[String]:
	var errors:Array[String]=[]
	if not collision is Dictionary or String(collision.get("type",""))!="polygon":return errors
	var raw:Variant=collision.get("points",[])
	if not raw is Array or raw.size()<3:errors.append("Polygon collision requires at least 3 vertices.");return errors
	if not bool(collision.get("closed",false)):errors.append("Polygon collision is not closed.")
	var points:=PackedVector2Array()
	for index in raw.size():
		var point:Variant=raw[index]
		if not point is Array or point.size()!=2 or not (point[0] is int or point[0] is float) or not (point[1] is int or point[1] is float):errors.append("Vertex %d must contain two numbers."%(index+1));continue
		var parsed:=Vector2(float(point[0]),float(point[1]));points.append(parsed)
		if parsed.x<0.0 or parsed.x>1.0 or parsed.y<0.0 or parsed.y>1.0:errors.append("Vertex %d must stay within normalized 0–1 sprite coordinates."%(index+1))
		if index>0 and parsed.distance_squared_to(points[index-1])<0.000001:errors.append("Consecutive polygon vertices must not be duplicates.")
	if points.size()!=raw.size():return errors
	if points[0].distance_squared_to(points[-1])<0.000001:errors.append("The closing vertex is implicit; do not duplicate the first vertex at the end.")
	var twice_area:=0.0
	for index in points.size():twice_area+=points[index].cross(points[(index+1)%points.size()])
	if absf(twice_area)<0.0002:errors.append("Polygon collision area is degenerate or near zero.")
	for a in points.size():
		var a_next:=(a+1)%points.size()
		for b in range(a+1,points.size()):
			var b_next:=(b+1)%points.size()
			if a==b or a_next==b or b_next==a:continue
			if Geometry2D.segment_intersects_segment(points[a],points[a_next],points[b],points[b_next])!=null:errors.append("Polygon edges self-intersect.");return errors
	if Geometry2D.triangulate_polygon(points).is_empty():errors.append("Polygon could not be decomposed without changing its concave outline.")
	return errors

static func save_metadata(asset_path:String,data:Dictionary)->Error:
	var target:=metadata_path(asset_path)
	var file:=FileAccess.open(target if target.is_absolute_path() else ProjectSettings.globalize_path(target),FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data,"\t")+"\n")
	return OK

func for_field(field: String) -> Dictionary:
	for entry in entries:
		for candidate in entry.get("serialization", {}).get("fields", []):
			if String(candidate) == field: return entry
	return {}

func _apply_animation_previews(catalog_path: String) -> void:
	var project_root := catalog_path.get_base_dir().get_base_dir().get_base_dir().get_base_dir()
	var file := FileAccess.open(project_root.path_join("assets/overworld/anim/animations.json"), FileAccess.READ)
	if file == null: return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary: return
	for entry: Dictionary in entries:
		var id := String(entry.get("animation", ""))
		if id.is_empty(): continue
		var record: Variant = data.get("animations", {}).get(id, {})
		if not record is Dictionary: continue
		var count := int(record.get("frame_count", 0))
		var valid := count > 0 and count <= 256 and float(record.get("frame_duration", 0)) > 0.0
		var size := Vector2i.ZERO
		for i in count if valid else 0:
			var path := project_root.path_join("assets/overworld/anim/%s_%02d.png" % [id, i])
			if not FileAccess.file_exists(path):
				valid = false
				break
			var image := Image.load_from_file(path)
			if image == null or image.is_empty():
				valid = false
				break
			if i == 0: size = image.get_size()
			if image.get_size() != size: valid = false
		if valid: entry.preview_texture = "assets/overworld/anim/%s_00.png" % id
		else: push_warning("Invalid overworld animation preview: " + id)
