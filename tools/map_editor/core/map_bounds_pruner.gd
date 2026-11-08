extends RefCounted

const Schema := preload("res://core/map_schema.gd")

# Placement anchors decide whether objects belong to the map. Sprite pixels and
# collision footprints may overhang an edge without deleting an in-bounds object.
static func prune(data:Dictionary,dimensions:Vector2)->int:
	var bounds:=Rect2(preload("res://core/map_bounds.gd").center(data)-dimensions*0.5,dimensions)
	var removed:=0
	var removed_hosts:Dictionary={}
	var fields:Array=["objects","npcs","trainers","furnishings","grass_zones","water_blocks","sand_blocks","rocks","floor_blocks","wall_blocks","trees"]
	fields.append_array(Schema.POINT_ARRAY_FIELDS)
	for field:String in fields:
		var records:Variant=data.get(field)
		if not records is Array:continue
		for index in range(records.size()-1,-1,-1):
			var record:Variant=records[index]
			var position:Variant=record.get("position") if record is Dictionary else record
			var outside:=false
			if record is Dictionary and record.get("points") is Array:
				outside=not _wall_overlaps(bounds,record.points)
			elif position is Array and position.size()>=3:outside=not _contains(bounds,Vector2(float(position[0]),float(position[2])))
			else:continue
			if not outside:continue
			if record is Dictionary and not String(record.get("instance_id","")).is_empty():removed_hosts[String(record.instance_id)]=true
			records.remove_at(index);removed+=1
	# An attachment must not retain a dangling host reference after a crop.
	var objects:Variant=data.get("objects",[])
	if objects is Array:
		for index in range(objects.size()-1,-1,-1):
			var record:Variant=objects[index]
			if record is Dictionary and bool(record.get("is_attached",false)) and removed_hosts.has(String(record.get("host_id",""))):objects.remove_at(index);removed+=1
	var terrain:Variant=data.get("terrain_tiles")
	if terrain is Array:
		for index in range(terrain.size()-1,-1,-1):
			var entry:Variant=terrain[index]
			if not entry is Dictionary:continue
			if entry.get("position") is Array and not _cell_inside(bounds,entry.position):entry.erase("position");removed+=1
			if entry.get("positions") is Array:
				for cell_index in range(entry.positions.size()-1,-1,-1):
					if not _cell_inside(bounds,entry.positions[cell_index]):entry.positions.remove_at(cell_index);removed+=1
			if not entry.has("position") and (not entry.get("positions") is Array or entry.positions.is_empty()):terrain.remove_at(index)
	var required:=Schema.expected_fields(Schema.kind_for_data(data))
	for field:String in data.keys():
		if not Schema.is_marker_field(field):continue
		var position:Variant=data[field]
		if not position is Array or position.size()<3 or _contains(bounds,Vector2(float(position[0]),float(position[2]))):continue
		# Keep schema-required markers valid when cropping, including return warps.
		if field in ["entry","player_spawn"] or required.has(field):
			position[0]=clampf(float(position[0]),bounds.position.x,bounds.end.x)
			position[2]=clampf(float(position[2]),bounds.position.y,bounds.end.y)
			if data.get("arrival_points") is Dictionary and data.arrival_points.has(field):data.arrival_points[field]=position.duplicate()
		else:
			data.erase(field);removed+=1
			if data.get("warp_metadata") is Dictionary:data.warp_metadata.erase(field)
			if data.get("arrival_points") is Dictionary:data.arrival_points.erase(field)
	if data.get("wild_zone") is Dictionary:
		var position:Variant=data.wild_zone.get("position")
		if position is Array and position.size()>=3 and not _contains(bounds,Vector2(float(position[0]),float(position[2]))):data.erase("wild_zone");removed+=1
	return removed

static func _contains(bounds:Rect2,point:Vector2)->bool:
	return point.x>=bounds.position.x-0.00001 and point.y>=bounds.position.y-0.00001 and point.x<=bounds.end.x+0.00001 and point.y<=bounds.end.y+0.00001

static func _cell_inside(bounds:Rect2,value:Variant)->bool:
	return not value is Array or value.size()<2 or _contains(bounds,Vector2(float(value[0]),float(value[1])))

static func _wall_overlaps(bounds:Rect2,points:Array)->bool:
	var previous:=Vector2.ZERO;var have_previous:=false
	for raw:Variant in points:
		if not raw is Array or raw.size()<2:continue
		var point:=Vector2(float(raw[0]),float(raw[1]))
		if _contains(bounds,point):return true
		if have_previous:
			var corners:=[bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]
			for index in 4:
				if Geometry2D.segment_intersects_segment(previous,point,corners[index],corners[(index+1)%4])!=null:return true
		previous=point;have_previous=true
	return false
