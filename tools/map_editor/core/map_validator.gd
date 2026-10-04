class_name MapValidator
extends RefCounted

const MapSchemaRef := preload("res://core/map_schema.gd")
const WallGeometryRef := preload("res://core/wall_geometry.gd")

static func validate(doc: MapDocument) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if not doc.parse_error.is_empty():
		issues.append(_issue("error", "$", doc.parse_error))
		return issues
	var expected := MapSchemaRef.expected_fields(doc.kind)
	if expected.is_empty(): issues.append(_issue("warning", "$", "Unsupported filename/schema; content will be preserved but typed editing is limited."))
	for field in expected:
		if not doc.data.has(field):
			issues.append(_issue("error", "$." + field, "Missing required field."))
			continue
		_validate_shape(doc.data[field], String(expected[field]), "$." + field, issues)
	for encounter_field in ["tall_grass_species","water_species"]:
		if not doc.data.has(encounter_field):continue
		if not doc.data[encounter_field] is Array:
			issues.append(_issue("error","$."+encounter_field,"Expected an encounter array."));continue
		for i in doc.data[encounter_field].size():
			var encounter:Variant=doc.data[encounter_field][i]
			var encounter_path:="$.%s[%d]"%[encounter_field,i]
			if encounter is String:
				if String(encounter).is_empty():issues.append(_issue("error",encounter_path,"Species must be non-empty."))
			elif encounter is Dictionary:
				if String(encounter.get("fakemon","")).is_empty():issues.append(_issue("error",encounter_path+".fakemon","Fakemon name is required."))
				if not encounter.get("level") is int and not encounter.get("level") is float:issues.append(_issue("error",encounter_path+".level","Encounter level must be numeric."))
				elif int(encounter.level)<1 or int(encounter.level)>100:issues.append(_issue("error",encounter_path+".level","Encounter level must be 1 to 100."))
			else:issues.append(_issue("error",encounter_path,"Expected a species name or Fakemon/level record."))
	if doc.data.has("water_encounter_chance"):
		_validate_shape(doc.data.water_encounter_chance,"chance","$.water_encounter_chance",issues)
	_validate_bounds(doc, issues)
	_validate_dangerous_overlaps(doc, issues)
	_validate_connections(doc, issues)
	_validate_warp_metadata(doc, issues)
	_validate_universal_objects(doc, issues)
	_validate_canonical_terrain(doc,issues)
	return issues

static func _validate_warp_metadata(doc: MapDocument, issues: Array[Dictionary]) -> void:
	if not doc.data.has("warp_metadata"): return
	if not doc.data.warp_metadata is Dictionary: issues.append(_issue("error", "$.warp_metadata", "Expected an object keyed by warp field.")); return
	var ids := {}
	for field: Variant in doc.data.warp_metadata:
		var path := "$.warp_metadata.%s" % String(field); var value: Variant = doc.data.warp_metadata[field]
		if not value is Dictionary: issues.append(_issue("error", path, "Expected a warp record.")); continue
		var warp_id: Variant = value.get("id")
		if not (warp_id is int or warp_id is float) or int(warp_id) < 1 or not is_equal_approx(float(warp_id),floorf(float(warp_id))): issues.append(_issue("error", path + ".id", "Warp ID must be a positive whole number."))
		elif ids.has(int(warp_id)): issues.append(_issue("error", path + ".id", "Warp ID must be unique within this map."))
		else: ids[int(warp_id)] = true
		if not value.get("entrance_map", "") is String: issues.append(_issue("error", path + ".entrance_map", "Entrance Map must be a filename."))
		var target_id: Variant = value.get("entrance_map_warp_id")
		if not (target_id is int or target_id is float) or int(target_id) < 1 or not is_equal_approx(float(target_id),floorf(float(target_id))): issues.append(_issue("error", path + ".entrance_map_warp_id", "Entrance Map Warp ID must be a positive whole number."))

static func _validate_canonical_terrain(doc:MapDocument,issues:Array[Dictionary])->void:
	var valid_types:=["water","sand","mud","forest_floor","stone","rock"]
	if doc.data.has("base_terrain_type") and String(doc.data.get("base_terrain_type","")) not in valid_types:issues.append(_issue("error","$.base_terrain_type","Unknown canonical base terrain type."))
	if not doc.data.has("terrain_tiles"):return
	var entries:Variant=doc.data.terrain_tiles
	if not entries is Array:issues.append(_issue("error","$.terrain_tiles","Expected an array of canonical terrain entries."));return
	var claimed:={}
	for index in entries.size():
		var entry:Variant=entries[index];var path:="$.terrain_tiles[%d]"%index
		if not entry is Dictionary:issues.append(_issue("error",path,"Expected a terrain entry object."));continue
		if String(entry.get("terrain_type","")) not in valid_types:issues.append(_issue("error",path+".terrain_type","Unknown canonical terrain type."))
		var positions:Array=[]
		var paths:Array[String]=[]
		if entry.get("positions",[]) is Array:
			positions.append_array(entry.get("positions",[]));for i in entry.get("positions",[]).size():paths.append("%s.positions[%d]"%[path,i])
		if entry.has("position"):positions.append(entry.position);paths.append(path+".position")
		for position_index in positions.size():
			var position:Variant=positions[position_index];var position_path:=paths[position_index]
			if not position is Array or position.size()!=2 or not (position[0] is int or position[0] is float) or not (position[1] is int or position[1] is float):issues.append(_issue("error",position_path,"Expected exactly two numeric tile coordinates."));continue
			if not is_equal_approx(float(position[0]),roundf(float(position[0]))) or not is_equal_approx(float(position[1]),roundf(float(position[1]))):issues.append(_issue("error",position_path,"Canonical terrain coordinates must align to the 1×1 tile grid."));continue
			var key:="%d,%d"%[int(position[0]),int(position[1])]
			if claimed.has(key):issues.append(_issue("error",position_path,"Canonical terrain coordinate is already owned by %s."%claimed[key]))
			else:claimed[key]=position_path

static func _validate_universal_objects(doc: MapDocument, issues: Array[Dictionary]) -> void:
	if not doc.data.has("objects"): return
	if not doc.data.objects is Array: issues.append(_issue("error", "$.objects", "Expected an array of universal map objects.")); return
	var supported := ["tree.main","tree.palm","flower.red_ginger","flower.torch_ginger","flower.blue","flower.orchid","flower.passion_vine_horizontal","cave.vine","structure.bridge","block.water","block.sand","block.rock","building.house","building.medical_ward","background.citybuilding_00","background.citybuilding_01","background.citybuilding_02","background.citybuilding_03","background.citybuilding_04","background.citybuilding_apartment_00","background.citybuilding_apartment_01","background.citybuilding_apartment_02","background.citybuilding_apartment_03","background.citybuilding_apartment_04","npc.generic","npc.opponent","wall.fence"]
	var instance_ids:Dictionary={};var valid_hosts:Dictionary={}
	for i in doc.data.objects.size():
		var candidate:Variant=doc.data.objects[i]
		if not candidate is Dictionary:continue
		var instance_id:=String(candidate.get("instance_id",""))
		if not instance_id.is_empty():
			if instance_ids.has(instance_id):issues.append(_issue("error","$.objects[%d].instance_id"%i,"Placed-object instance IDs must be unique within a map."))
			else:instance_ids[instance_id]=true
			var candidate_type:=String(candidate.get("type",""))
			if not candidate_type.begins_with("overlay.") and not candidate_type.begins_with("npc.") and candidate_type not in ["wall.fence","structure.bridge","block.water","block.sand","block.rock"]:valid_hosts[instance_id]=true
	for i in doc.data.objects.size():
		var path := "$.objects[%d]" % i; var value: Variant = doc.data.objects[i]
		if not value is Dictionary: issues.append(_issue("error", path, "Expected an object record.")); continue
		var type_id := String(value.get("type", ""))
		if not type_id in supported and not type_id.begins_with("asset.") and not type_id.begins_with("overlay.") and not type_id.begins_with("tile.") and not type_id.begins_with("building."): issues.append(_issue("error", path + ".type", "Unsupported universal object type."))
		if (type_id.begins_with("asset.") or type_id.begins_with("overlay.") or type_id.begins_with("tile.")) and (not value.get("asset_path") is String or not String(value.get("asset_path","")).begins_with("res://assets/overworld/")):
			issues.append(_issue("error", path + ".asset_path", "Imported overworld objects require an assets/overworld resource path."))
		if type_id.begins_with("overlay.") and value.has("rotation_degrees") and not (value.rotation_degrees is int or value.rotation_degrees is float):
			issues.append(_issue("error", path + ".rotation_degrees", "Overlay rotation must be a number of degrees."))
		if type_id.begins_with("tile.") and value.has("rotation_degrees") and not (value.rotation_degrees is int or value.rotation_degrees is float):issues.append(_issue("error",path+".rotation_degrees","Tile rotation must be a number of degrees."))
		if type_id.begins_with("overlay.") and bool(value.get("is_attached",false)):
			var host_id:=String(value.get("host_id",""))
			if host_id.is_empty() or not valid_hosts.has(host_id):issues.append(_issue("error",path+".host_id","Attached overlays require an existing renderable placed-object host."))
			_numeric_array(value.get("local_position",null),2,path+".local_position",issues)
			var attachment_order:Variant=value.get("attachment_order",null)
			if not (attachment_order is int or attachment_order is float) or float(attachment_order)<0.0 or not is_equal_approx(float(attachment_order),floorf(float(attachment_order))):issues.append(_issue("error",path+".attachment_order","Attachment order must be a non-negative integer."))
		if type_id=="wall.fence":
			if String(value.get("wall_set",""))!="generic_wall":issues.append(_issue("error",path+".wall_set","Unknown Wall/Fence asset."))
			var points:Variant=value.get("points",[])
			if not points is Array or points.size()<2:issues.append(_issue("error",path+".points","Walls require at least two anchor points."))
			else:
				for point_index in points.size():
					_numeric_array(points[point_index],2,"%s.points[%d]"%[path,point_index],issues)
					if point_index>0 and points[point_index] is Array and points[point_index-1] is Array and points[point_index].size()>=2 and points[point_index-1].size()>=2:
						var delta:=Vector2(float(points[point_index][0])-float(points[point_index-1][0]),float(points[point_index][1])-float(points[point_index-1][1]))
						if delta.length_squared()<0.0001:issues.append(_issue("error","%s.points[%d]"%[path,point_index],"Consecutive wall anchors must not overlap."))
						elif not is_zero_approx(delta.x) and not is_zero_approx(delta.y):issues.append(_issue("error","%s.points[%d]"%[path,point_index],"Walls support horizontal and vertical segments only; diagonal gestures must be converted by the editor."))
						elif not WallGeometryRef.segment_is_valid(Vector2(float(points[point_index-1][0]),float(points[point_index-1][1])),Vector2(float(points[point_index][0]),float(points[point_index][1]))):issues.append(_issue("error","%s.points[%d]"%[path,point_index],"Wall segment length must be a positive multiple of the %.1f-map-unit filler interval."%WallGeometryRef.MIN_FILLER_SPAN))
			continue
		_numeric_array(value.get("position", null), 3, path + ".position", issues)
		if value.has("size"): _numeric_array(value.size, 3, path + ".size", issues)
		if type_id == "structure.bridge":
			if String(value.get("orientation", "")) not in ["horizontal", "vertical"]: issues.append(_issue("error", path + ".orientation", "Bridge orientation must be horizontal or vertical."))
			_validate_bridge_number(value,"length",path,issues,3.0,true)
			_validate_bridge_number(value,"width",path,issues,1.0,false)
			_validate_bridge_number(value,"elevation",path,issues,0.5,false)
			_validate_bridge_number(value,"entrance_length",path,issues,0.5,false)
			_validate_bridge_number(value,"traversal_layer",path,issues,1.0,true)
		if type_id in ["npc.generic","npc.opponent"]:
			var catalog_trainer:=type_id=="npc.opponent" and not String(value.get("trainer_id","")).is_empty()
			var speaker_field := "name" if type_id=="npc.opponent" else "speaker"
			if not catalog_trainer and String(value.get(speaker_field,"")).is_empty():issues.append(_issue("error",path+"."+speaker_field,"Expected a non-empty display name."))
			if not catalog_trainer and (not value.get("dialogue") is Array or value.get("dialogue",[]).is_empty()):issues.append(_issue("error",path+".dialogue","Expected at least one dialogue page."))
		if type_id=="npc.opponent" and String(value.get("trainer_id","")).is_empty():
			var team:Variant=value.get("team",[])
			if not team is Array or team.is_empty() or team.size()>7:issues.append(_issue("error",path+".team","Trainer teams must contain 1 to 7 Fakemon."))
			else:
				for member_index in team.size():
					var member:Variant=team[member_index];var member_path:="%s.team[%d]"%[path,member_index]
					if not member is Dictionary:issues.append(_issue("error",member_path,"Expected a Fakemon/level record."));continue
					if not member.has("fakemon") or (not member.fakemon is String and not member.fakemon is int and not member.fakemon is float):issues.append(_issue("error",member_path+".fakemon","Expected a Fakemon name or index."))
					var level:=int(member.get("level",0));if level<1 or level>100:issues.append(_issue("error",member_path+".level","Level must be between 1 and 100."))

static func _validate_connections(doc: MapDocument, issues: Array[Dictionary]) -> void:
	if doc.data.has("arrival_points"):
		if not doc.data.arrival_points is Dictionary: issues.append(_issue("error", "$.arrival_points", "Expected an object of named arrival positions."))
		else:
			for name in doc.data.arrival_points: _numeric_array(doc.data.arrival_points[name], 3, "$.arrival_points.%s" % name, issues)
	if not doc.data.has("outdoor_connections"): return # Legacy maps remain valid during incremental migration.
	if not doc.data.outdoor_connections is Array: issues.append(_issue("error", "$.outdoor_connections", "Expected an array of connections.")); return
	var ids := {}; var warps := {}
	for i in doc.data.outdoor_connections.size():
		var path := "$.outdoor_connections[%d]" % i; var value: Variant = doc.data.outdoor_connections[i]
		if not value is Dictionary: issues.append(_issue("error", path, "Expected a connection object.")); continue
		for field in ["id", "warp", "destination_map", "arrival", "reverse"]:
			if not value.get(field) is String or String(value.get(field, "")).is_empty(): issues.append(_issue("error", path + "." + field, "Expected a non-empty string."))
		var id := String(value.get("id", "")); var warp := String(value.get("warp", ""))
		if not id.is_empty() and ids.has(id): issues.append(_issue("error", path + ".id", "Duplicate connection id."))
		else: ids[id] = true
		if not warp.is_empty() and warps.has(warp): issues.append(_issue("error", path + ".warp", "Duplicate link for the same warp marker."))
		else: warps[warp] = true
		if not warp.is_empty() and not doc.data.has(warp): issues.append(_issue("error", path + ".warp", "Referenced warp marker is missing."))

static func _validate_shape(value: Variant, shape: String, path: String, issues: Array[Dictionary]) -> void:
	match shape:
		"number":
			if not (value is int or value is float):issues.append(_issue("error",path,"Expected a number."))
		"chance":
			if not (value is int or value is float):issues.append(_issue("error",path,"Expected a numeric probability."))
			elif float(value)<0.0 or float(value)>1.0:issues.append(_issue("error",path,"Probability must be between 0 and 1."))
		"position3", "size3": _numeric_array(value, 3, path, issues)
		"size2": _numeric_array(value, 2, path, issues)
		"strings":
			if not value is Array: issues.append(_issue("error", path, "Expected an array of strings."))
		"string":
			if not value is String or String(value).is_empty(): issues.append(_issue("error", path, "Expected a non-empty string."))
		"object", "zone":
			if not value is Dictionary: issues.append(_issue("error", path, "Expected an object."))
		"objects":
			if not value is Array:issues.append(_issue("error",path,"Expected a universal object array."))
		"connections":
			if not value is Array:issues.append(_issue("error",path,"Expected a connection array."))
		"points", "trees", "blocks", "zones", "furnishings", "trainers":
			if not value is Array: issues.append(_issue("error", path, "Expected an array.")); return
			for i in value.size():
				if shape == "points":
					# Family-house children carry their sprite selection beside the
					# editable placement.  Keep accepting the legacy bare coordinate
					# rows used by other point collections.
					if path == "$.children" and value[i] is Dictionary:
						_numeric_array(value[i].get("position", null), 3, "%s[%d].position" % [path, i], issues)
					else:
						_numeric_array(value[i], 3, "%s[%d]" % [path, i], issues)
				elif shape == "trees": _numeric_array(value[i], 4, "%s[%d]" % [path, i], issues)
				elif shape == "blocks": _numeric_array(value[i], 6, "%s[%d]" % [path, i], issues)
				elif shape == "furnishings":
					if not value[i] is Dictionary:issues.append(_issue("error","%s[%d]"%[path,i],"Expected a furnishing object."))
					else:
						if not value[i].get("type") is String or String(value[i].get("type","")).is_empty():issues.append(_issue("error","%s[%d].type"%[path,i],"Expected a furnishing type."))
						_numeric_array(value[i].get("position",null),3,"%s[%d].position"%[path,i],issues)
						if value[i].has("footprint"):_numeric_array(value[i].footprint,2,"%s[%d].footprint"%[path,i],issues)
				elif shape == "trainers":
					if not value[i] is Dictionary: issues.append(_issue("error", "%s[%d]" % [path, i], "Expected a trainer object."))
					else:
						_numeric_array(value[i].get("position", null), 3, "%s[%d].position" % [path, i], issues)
						if String(value[i].get("trainer_id","")).is_empty():
							if not value[i].get("name") is String or String(value[i].get("name", "")).is_empty(): issues.append(_issue("error", "%s[%d].name" % [path, i], "Expected a trainer name or trainer_id."))
							if not value[i].get("party") is Array or value[i].get("party", []).is_empty(): issues.append(_issue("error", "%s[%d].party" % [path, i], "Expected at least one Fakemon index."))
				elif not value[i] is Dictionary: issues.append(_issue("error", "%s[%d]" % [path, i], "Expected a grass-zone object."))
	if shape == "zone" and value is Dictionary:
		for key in ["position", "size", "encounter_chance"]:
			if not value.has(key): issues.append(_issue("error", path + "." + key, "Missing required zone field."))
	if shape == "zones" and value is Array:
		for i in value.size():
			if value[i] is Dictionary:
				for key in ["position", "size", "encounter_chance"]:
					if not value[i].has(key): issues.append(_issue("error", "%s[%d].%s" % [path, i, key], "Missing required zone field."))

static func _numeric_array(value: Variant, count: int, path: String, issues: Array[Dictionary]) -> void:
	if not value is Array or value.size() != count:
		issues.append(_issue("error", path, "Expected exactly %d numeric elements." % count)); return
	for i in count:
		if not (value[i] is int or value[i] is float): issues.append(_issue("error", "%s[%d]" % [path, i], "Expected a number."))

static func _validate_bridge_number(value:Dictionary,field:String,path:String,issues:Array[Dictionary],minimum:float,integer_only:bool)->void:
	var property_path:=path+"."+field;var number:Variant=value.get(field,null)
	if not (number is int or number is float):issues.append(_issue("error",property_path,"Bridge %s must be numeric."%field.replace("_"," ")));return
	if integer_only and float(number)!=floorf(float(number)):issues.append(_issue("error",property_path,"Bridge %s must be a whole number."%field.replace("_"," ")))
	if float(number)<minimum:issues.append(_issue("error",property_path,"Bridge %s must be at least %s."%[field.replace("_"," "),str(minimum)]))

static func _validate_bounds(doc: MapDocument, issues: Array[Dictionary]) -> void:
	var size: Variant = doc.data.get("map_size", doc.data.get("size", doc.data.get("interior_size", null)))
	if not size is Array or size.size() < 2: return
	var limit_x := float(size[0]) * 0.5 + 2.5
	var limit_z := float(size[1]) * 0.5 + 2.5
	for field in doc.data:
		if MapSchemaRef.is_marker_field(String(field)) and doc.data[field] is Array and doc.data[field].size() >= 3 and MapSchemaRef.coordinate_space(doc.kind, String(field)) == "map_local":
			var p: Array = doc.data[field]
			if absf(float(p[0])) > limit_x or absf(float(p[2])) > limit_z: issues.append(_issue("warning", "$." + String(field), "Marker is well outside the nominal map bounds."))

static func _validate_dangerous_overlaps(doc: MapDocument, issues: Array[Dictionary]) -> void:
	var markers: Array[Dictionary] = []
	for field in doc.data:
		if MapSchemaRef.is_marker_field(String(field)) and doc.data[field] is Array and doc.data[field].size() >= 3:
			markers.append({"path":"$." + String(field), "position":Vector2(float(doc.data[field][0]), float(doc.data[field][2]))})
	for i in markers.size():
		for j in range(i + 1, markers.size()):
			if markers[i].position.is_equal_approx(markers[j].position): issues.append(_issue("warning", markers[j].path, "Marker is coincident with %s." % markers[i].path))
	for marker in markers:
		for field in ["water_blocks", "rocks"]:
			for index in doc.data.get(field, []).size():
				var block: Variant = doc.data.get(field, [])[index]
				if block is Array and block.size() >= 6:
					var rect := Rect2(Vector2(float(block[0]),float(block[2])) - Vector2(float(block[3]),float(block[5])) * 0.5, Vector2(float(block[3]),float(block[5])))
					if rect.has_point(marker.position): issues.append(_issue("warning", marker.path, "Marker overlaps solid %s[%d]." % [field,index]))

static func _issue(severity: String, path: String, message: String) -> Dictionary:
	return {"severity": severity, "path": path, "message": message}
