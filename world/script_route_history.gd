extends RefCounted

# Transient ground-plane routes, recorded from actual positions (including detours).
# Keeping routes independently of follow modes also supports following after Move.
const MAX_POINTS := 512
const MAX_ACTORS := 64
const SAMPLE_DISTANCE := 0.15
const DISCONTINUITY_DISTANCE := 1.0
var routes: Dictionary = {}
var serial := 0

func begin(actor: Node3D, map_file: String) -> void:
	var route := get_route(actor,map_file)
	if route.is_empty() or flat(route.last_observed).distance_to(flat(actor.position)) > 0.5:
		_reset(actor,map_file)
	else:
		record(actor,map_file,true)

func record(actor: Node3D, map_file: String, force := false) -> void:
	var route := get_route(actor,map_file)
	if route.is_empty() or flat(route.last_observed).distance_to(flat(actor.position)) > DISCONTINUITY_DISTANCE:
		_reset(actor,map_file); return
	route.last_observed = actor.position
	var previous: Vector3 = route.points[-1]
	var distance := flat(previous).distance_to(flat(actor.position))
	if distance < 0.00001 or (not force and distance < SAMPLE_DISTANCE): return
	route.points.append(actor.position); route.lengths.append(float(route.lengths[-1])+distance)
	if route.points.size() > MAX_POINTS:
		route.points.pop_front(); route.lengths.pop_front(); route.base += 1

func get_route(actor: Node3D, map_file: String) -> Dictionary:
	var route: Dictionary = routes.get(actor.get_instance_id(),{})
	if route.get("actor") != actor or str(route.get("map","")) != map_file: return {}
	return route

func erase(actor: Node) -> void:
	routes.erase(actor.get_instance_id())

func clear() -> void:
	routes.clear()

func _reset(actor: Node3D, map_file: String) -> void:
	if not routes.has(actor.get_instance_id()) and routes.size() >= MAX_ACTORS: routes.erase(routes.keys()[0])
	serial += 1
	routes[actor.get_instance_id()] = {"actor":actor,"map":map_file,"id":serial,"base":0,"points":[actor.position],"lengths":[0.0],"last_observed":actor.position}

static func flat(point: Vector3) -> Vector2:
	return Vector2(point.x,point.z)
