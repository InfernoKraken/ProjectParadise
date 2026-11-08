extends RefCounted

# Editor warning overlay only: consumes existing extracted collision boxes.
# Runtime authority remains the NPC physics shape sweep (including polygons).
static func segments(paths: Dictionary, objects: Array, footprint := Vector2.ZERO) -> Dictionary:
	if paths.is_empty(): return {}
	var boxes: Array[Rect2] = []
	for object: Dictionary in objects:
		if object.get("shape") == "wall":
			for segment: Variant in object.get("collision", []):
				if not segment is Dictionary: continue
				var a: Variant = segment.get("from", []); var b: Variant = segment.get("to", [])
				if not a is Array or not b is Array or a.size() != 2 or b.size() != 2: continue
				var start := Vector2(a[0], a[1]); var finish := Vector2(b[0], b[1]); var delta := finish - start
				if delta.length() <= 0.001 or not (is_zero_approx(delta.x) or is_zero_approx(delta.y)): continue
				var offset := Vector2(-delta.y, delta.x).normalized() * float(segment.get("offset", 0.0))
				var box := Rect2(start+offset, Vector2.ZERO).expand(finish+offset).grow(float(segment.get("thickness", 0.22))*0.5)
				boxes.append(box.grow_individual(footprint.x*0.5,footprint.y*0.5,footprint.x*0.5,footprint.y*0.5))
			continue
		if object.field == "wall_blocks" and not object.get("wall_collision", {}).get("enabled", true): continue
		if object.field not in ["asset_collision", "wall_blocks", "rocks", "water_blocks"]: continue
		var center: Vector3 = object.position; var extent: Vector3 = object.size
		if object.field == "wall_blocks":
			var config: Dictionary = object.get("wall_collision", {})
			var offset: Array = config.get("offset", [0,0,0]); var dimensions: Array = config.get("size", [extent.x,extent.y,extent.z])
			center += Vector3(offset[0],offset[1],offset[2]); extent = Vector3(dimensions[0],dimensions[1],dimensions[2])
		boxes.append(Rect2(Vector2(center.x, center.z) - Vector2(extent.x,extent.z)*0.5, Vector2(extent.x,extent.z)).grow_individual(footprint.x*0.5,footprint.y*0.5,footprint.x*0.5,footprint.y*0.5))
	var invalid := {}
	for name: String in paths:
		var nodes: Array = paths[name].nodes
		for i in nodes.size() - 1:
			var a := Vector2(nodes[i][0],nodes[i][1]); var b := Vector2(nodes[i+1][0],nodes[i+1][1])
			for box in boxes:
				var corners := [box.position, box.position + Vector2(box.size.x,0), box.end, box.position + Vector2(0,box.size.y)]
				var hit := box.has_point(a) or box.has_point(b)
				for edge in 4:
					if Geometry2D.segment_intersects_segment(a,b,corners[edge],corners[(edge+1)%4]) != null: hit = true
				if hit: invalid[name + ":" + str(i)] = true; break
	return invalid
