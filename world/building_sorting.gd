extends RefCounted

# Use the rear collision edge as the facade's sorting line so traversable
# entrance artwork stays behind approaching actors. Explicit offsets win.
static func offset(asset_path:String,metadata:Dictionary)->float:
	if metadata.has("sort_offset_y"):return float(metadata.sort_offset_y)
	if not asset_path.get_file().begins_with("building_"):return 0.0
	var collision:Dictionary=metadata.get("collision",{})
	var reference:Variant=collision.get("reference_size",[1.0,1.0])
	var depth:float=float(reference[1]) if reference is Array and reference.size()==2 else 1.0
	var rear:float=INF
	if collision.get("type","")=="polygon" and bool(collision.get("closed",false)):
		for point in collision.get("points",[]):
			if point is Array and point.size()==2:rear=minf(rear,(float(point[1])-0.5)*depth)
	return rear if is_finite(rear) else 0.0
