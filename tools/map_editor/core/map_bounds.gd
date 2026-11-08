extends RefCounted

# Bounds can move independently of the map origin. Existing files omit this
# optional center and keep their original centered bounds and local coordinates.
static func center(data:Dictionary)->Vector2:
	var value:Variant=data.get("bounds_center",[0,0])
	return Vector2(float(value[0]),float(value[1])) if value is Array and value.size()==2 else Vector2.ZERO

static func offset(data:Dictionary)->Vector3:
	var point:=center(data)
	return Vector3(point.x,0,point.y)

static func rect(data:Dictionary)->Rect2:
	var value:Variant=data.get("map_size",data.get("interior_size",data.get("size",[20,20])))
	if not value is Array or value.size()<2:return Rect2()
	var dimensions:=Vector2(float(value[0]),float(value[1]))
	return Rect2(center(data)-dimensions*0.5,dimensions)
