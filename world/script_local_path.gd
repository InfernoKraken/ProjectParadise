extends RefCounted

const DIRECTIONS := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]

# Find the nearest reachable sampled forward point on this required segment.
# Budgets include both grid-edge sweeps and exact route-rejoin sweeps.
static func find(start: Vector3, segment_start: Vector3, destination: Vector3, clear_segment: Callable, settings: Dictionary) -> Dictionary:
	var radius := clampf(float(settings.get("radius",2.5)),0.5,6.0)
	var step := clampf(float(settings.get("step",0.5)),0.25,1.0)
	var max_nodes := clampi(int(settings.get("max_nodes",160)),1,256)
	var max_checks := clampi(int(settings.get("max_checks",1200)),1,2048)
	var out := {"route":[],"nodes":0,"checks":0,"reason":"No reachable forward rejoin within local radius."}
	var a := Vector2(segment_start.x,segment_start.z)
	var b := Vector2(destination.x,destination.z)
	var origin := Vector2(start.x,start.z)
	var projection := Geometry2D.get_closest_point_to_segment(origin,a,b)
	var remaining := projection.distance_to(b)
	var candidates: Array[Vector3] = []
	var forward := (b-projection).normalized()
	var distance := minf(step,remaining)
	for iteration in 32:
		if distance > remaining: break
		var point := projection+forward*distance
		if point.distance_to(origin) <= radius: candidates.append(Vector3(point.x,start.y,point.y))
		if distance == remaining: break
		distance = minf(remaining,distance+step)
	for point:Vector3 in settings.get("rejoin_points",[]):
		if flat_distance(point,start) <= radius:candidates.append(Vector3(point.x,start.y,point.z))
	if candidates.is_empty(): return out
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var parents := {Vector2i.ZERO:Vector2i.ZERO}
	var cursor := 0
	var edge_budget := maxi(0,max_checks-candidates.size())
	while cursor < queue.size() and out.checks < edge_budget:
		var current := queue[cursor]; cursor += 1
		for offset: Vector2i in DIRECTIONS:
			var next := current+offset
			if Vector2(next).length()*step > radius or parents.has(next): continue
			if parents.size() >= max_nodes or out.checks >= edge_budget: break
			var from := start+Vector3(current.x*step,0,current.y*step)
			var to := start+Vector3(next.x*step,0,next.y*step)
			out.checks += 1
			if not clear_segment.call(from,to): continue
			parents[next] = current; queue.append(next)
	out.nodes = parents.size()
	for candidate: Vector3 in candidates:
		var nearest := Vector2i(roundi((candidate.x-start.x)/step),roundi((candidate.z-start.z)/step))
		var joins:Array[Vector2i] = [nearest]
		if bool(settings.get("neighbor_rejoins",false)):
			for offset:Vector2i in DIRECTIONS:joins.append(nearest+offset)
		# A clear exact rejoin may sit beside a blocked grid cell (stair rails
		# and actor corners). Check neighboring reachable cells before rejecting it.
		for join:Vector2i in joins:
			if not parents.has(join) or out.checks >= max_checks: continue
			var point := start+Vector3(join.x*step,0,join.y*step)
			out.checks += 1
			if not clear_segment.call(point,candidate): continue
			var route: Array = []
			var cell := join
			while cell != Vector2i.ZERO:
				route.push_front(start+Vector3(cell.x*step,0,cell.y*step)); cell = parents[cell]
			if route.is_empty() and start.distance_to(candidate) <= 0.03: continue
			route.append(candidate); out.route = route; out.reason = ""; return out
	return out

static func flat_distance(a:Vector3,b:Vector3)->float:
	return Vector2(a.x-b.x,a.z-b.z).length()
