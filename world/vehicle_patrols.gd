extends RefCounted

const DEFAULT_MAX_ACTIVE := 8
const BLOCKED_RETRY := 0.25
const View = preload("terrain_camera_view.gd")
var game: Node
var states: Array[Dictionary] = []
var next_id := -1

func _init(world: Node) -> void:
	game = world

static func validation_error(config: Variant, visuals: RefCounted) -> String:
	if not config is Dictionary: return "Patrol must be an object."
	if config.get("type") not in ["finite", "traffic"]: return "Choose finite or traffic."
	var interval: Variant = config.get("creation_interval")
	if not (interval is int or interval is float) or not is_finite(float(interval)) or interval <= 0: return "Creation interval must be positive and finite."
	if not config.get("repeat", false) is bool: return "Repeat must be a boolean."
	if config.type == "traffic":
		var limit: Variant = config.get("max_active_vehicles", DEFAULT_MAX_ACTIVE)
		if not (limit is int or limit is float) or not is_finite(float(limit)) or limit < 1 or limit != floorf(float(limit)):
			return "Maximum active vehicles must be a positive whole number."
	var path: Variant = config.get("path")
	if not path is Array or path.size() < 2: return "Path needs at least two X/Z waypoints."
	for point: Variant in path:
		if not point is Array or point.size() != 2: return "Waypoints need X and Z."
		for value: Variant in point:
			if not (value is int or value is float) or not is_finite(float(value)): return "Waypoint coordinates must be finite."
	var vehicles: Variant = config.get("vehicles", []) if config.type == "finite" else [config.get("traffic_vehicle")]
	if not vehicles is Array: return "Vehicles must be an array."
	for vehicle: Variant in vehicles:
		if not vehicle is Dictionary or vehicle.get("type") != "vehicle" or not visuals.available("vehicle", str(vehicle.get("sprite", ""))): return "Choose an available vehicle definition."
		var error := preload("npc_movement.gd").traversal_error(vehicle)
		if not error.is_empty(): return error
	return ""

static func issues(map: Dictionary, visuals: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var configs: Variant = map.get("patrols", [])
	if not configs is Array:
		return [{"severity":"error", "path":"$.patrols", "message":"Patrols must be an array."}]
	for index in configs.size():
		var error := validation_error(configs[index], visuals)
		if not error.is_empty(): result.append({"severity":"error", "path":"$.patrols[%d]" % index, "message":error})
	return result

func register(region: Dictionary, origin: Vector3) -> void:
	var configs: Variant = region.get("patrols", [])
	if not configs is Array:
		push_warning("Patrols must be an array."); return
	for config: Variant in configs:
		var error := validation_error(config, game.npc_visual_resolver)
		if not error.is_empty(): push_warning(error); continue
		var nodes: Array[Vector3] = []
		for point: Array in config.path: nodes.append(origin + Vector3(point[0], 0, point[1]))
		var bounds := Rect2(Vector2(nodes[0].x, nodes[0].z), Vector2.ZERO)
		for node in nodes: bounds = bounds.expand(Vector2(node.x, node.z))
		states.append({"config":config.duplicate(true), "region":region, "origin":origin, "nodes":nodes, "bounds":bounds.grow(8), "timer":0.0, "spawned":0, "actors":[], "active":false})

func update(delta: float) -> void:
	var running: bool = game.adventure_started and not game.in_battle and not game.dialog_open and not game.swim_transitioning and not game.script_input_locked
	for state: Dictionary in states:
		var active: bool = running and game._location_for_map_file(str(state.region._npc_map_file)) == game._current_location()
		if active and game.camera != null: active = state.bounds.intersects(View.ground_rect(game.camera, state.origin.y))
		state.active = active
		for actor: Dictionary in state.actors:
			actor.npc.set_meta("patrol_active", active)
			if active and not actor.done and not game.npc_script_movement.controls(actor.npc): _assign(state, actor)
		if not active: continue
		var config: Dictionary = state.config
		if config.type == "finite" and state.spawned >= config.vehicles.size(): continue
		state.timer = maxf(0.0, state.timer - delta)
		if state.timer > 0: continue
		if config.type == "traffic" and state.actors.size() >= config.get("max_active_vehicles", DEFAULT_MAX_ACTIVE): continue
		var definition: Dictionary = config.vehicles[state.spawned] if config.type == "finite" else config.traffic_vehicle
		var record := definition.duplicate(true)
		record.merge({"id":next_id, "position":[state.nodes[0].x-state.origin.x, 0, state.nodes[0].z-state.origin.z], "facing":game.npc_script_movement.direction(state.nodes[1]-state.nodes[0], "down"), "hidden":false, "movement":{"preset":"stationary", "range":[0,0]}}, true)
		var footprint: Rect2 = game.npc_visual_resolver.hull_footprint(str(record.sprite), str(record.facing))
		var anchor: Vector3 = state.nodes[0]
		if not game._water_covers_footprint(state.region.get("_terrain_grid", {}), anchor - state.origin, footprint) or _occupied(anchor, footprint) or not game._vehicle_spawn_clear(anchor, footprint):
			state.timer = BLOCKED_RETRY
			continue
		var npc: Area3D = game._spawn_placed_npc(state.region, state.origin, record, true)
		if npc == null:
			state.timer = BLOCKED_RETRY
			continue
		if game.sort_canvas != null:
			var entry: Dictionary = game.npc_sort_entries[-1]
			entry["visual_layer"] = game._active_visual_layer()
			entry["sort_root"] = game._create_sorted_sprite(str(entry.name), entry.visual.texture)
			entry.visual.hide()
		game._assign_visual_region(npc, game._active_visual_layer())
		game._track_patrol_collision(npc, true)
		next_id -= 1
		npc.set_meta("patrol_active", true)
		npc.set_meta("script_movement_owned", true)
		var actor := {"npc":npc, "reverse":false, "done":false}
		state.actors.append(actor)
		state.spawned += 1
		state.timer = float(config.creation_interval)
		_assign(state, actor)

func _assign(state: Dictionary, actor: Dictionary) -> void:
	var nodes: Array[Vector3] = state.nodes.duplicate()
	if actor.reverse: nodes.reverse()
	game.npc_script_movement.patrol_route(actor.npc, str(state.region._npc_map_file), nodes, func(): _arrived(state, actor))

func _arrived(state: Dictionary, actor: Dictionary) -> void:
	if state.config.type == "traffic":
		state.actors.erase(actor)
		_remove(actor.npc)
	elif state.config.get("repeat", false):
		actor.reverse = not actor.reverse
		_assign(state, actor)
	else: actor.done = true

func _remove(npc: Area3D) -> void:
	var key := npc.get_instance_id()
	game.npc_script_movement.modes.erase(key)
	game.npc_script_movement.route_history.erase(npc)
	game.npc_movement_states.erase(key)
	game.npc_dialogues.erase(key)
	game.runtime_npcs[str(npc.get_meta("script_map"))].erase(int(npc.get_meta("npc_id")))
	for index in range(game.npc_sort_entries.size()-1, -1, -1):
		if game.npc_sort_entries[index].node == npc:
			if game.npc_sort_entries[index].has("sort_root"): game.npc_sort_entries[index].sort_root.queue_free()
			game.npc_sort_entries.remove_at(index)
	if npc.has_meta("visual_layer"): game._track_patrol_collision(npc, false)
	npc.free()

# Physics registration is deferred: also cover two patrols spawning in one tick.
func _occupied(position: Vector3, hull: Rect2) -> bool:
	hull.position += Vector2(position.x, position.z)
	var size: Vector3 = preload("npc_movement.gd").FOOT_SIZE
	for instances: Dictionary in game.runtime_npcs.values():
		for other: Area3D in instances.values():
			if game.script_host.sprite_hidden(other) or absf(float(other.get_meta("base_elevation", other.position.y))-position.y) > 1.0: continue
			var footprint: Rect2 = other.get_meta("hull_footprint", Rect2(Vector2(-size.x,-size.z)*0.5, Vector2(size.x,size.z)))
			footprint.position += Vector2(other.position.x, other.position.z)
			if hull.grow(0.002).intersects(footprint): return true
	return false
