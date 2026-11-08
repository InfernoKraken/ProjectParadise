extends RefCounted

const Paths = preload("scripting/script_paths.gd")
const Movement = preload("npc_movement.gd")
const LocalPath = preload("script_local_path.gd")
const RouteHistory = preload("script_route_history.gd")
var route_history := RouteHistory.new()
const FOLLOW_DISTANCE := 1.25
const CORRIDOR_DISTANCE := 3.0
const BLOCKED_TIMEOUT := 2.0
var game: Node
# Game-owned transient NPC modes. FOLLOW survives script cleanup; none are saved.
var modes: Dictionary = {}
var waiters: Dictionary = {}
var yield_hint := ""
var showing_yield_hint := false
# World-unit configuration; collider sweeps determine usable clearance.
var avoidance := {"radius":2.5,"step":0.5,"max_nodes":160,"max_checks":1200,"max_retries":5,"timeout":5.0}

func _init(world: Node) -> void:
	game = world

func actor(map_file: String, token: String) -> Node3D:
	if token == "Player": return game.player
	var map: Dictionary = game.map_data.get("_map_files", {}).get(map_file, {})
	var id := Paths.actor_id(map, token)
	return game.runtime_npcs.get(map_file, {}).get(id) as Node3D

func request(map_file: String, command: String, args: Array, complete: Callable, failed: Callable) -> Dictionary:
	var npc := actor(map_file, str(args[0]))
	if npc == null: return {"error":"Unknown map-local NPC: " + str(args[0])}
	var key := npc.get_instance_id()
	if command == "WaitMovement": return wait_movement(map_file, npc, complete, failed)
	if npc == game.player and not command in ["FollowSprite", "StopFollowing", "FaceSprite"]: return {"error":"Player supports FollowSprite, StopFollowing, FaceSprite and WaitMovement only."}
	if command in ["MoveSprite", "FollowSprite"] and npc != game.player and game.script_host.sprite_hidden(npc): return {"error":"Show the hidden NPC before moving it."}
	if command == "FaceSprite":
		var directions := {"North":"up", "South":"down", "East":"right", "West":"left"}
		var facing := str(directions.get(args[1], ""))
		if facing.is_empty():
			var target := actor(map_file, str(args[1]))
			if target == null: return {"error":"Unknown facing target: " + str(args[1])}
			var fallback := str(game.player_animation).trim_prefix("idle_").trim_prefix("walk_") if npc == game.player else str(npc.get_meta("facing", "down"))
			facing = direction(target.position - npc.position, fallback)
		if npc == game.player: game._face_script_player(facing)
		else: _pose(npc, facing)
		return {}
	if command == "ResumeMovement":
		var state: Variant = game.npc_movement_states.get(key)
		if state == null: return {"error":"NPC has no authored movement configuration."}
		if not modes.has(key) and not npc.get_meta("script_movement_owned",false): return {}
		var previous: Dictionary = modes.get(key,{})
		modes.erase(key)
		npc.set_meta("script_movement_owned",false)
		state.resume(npc.position)
		_pose(npc,str(npc.get_meta("facing","down")))
		_restore_yield_hint()
		if waiters.has(key):
			var waiter: Dictionary = waiters[key]; waiters.erase(key)
			waiter.failed.call("WaitMovement cancelled by ResumeMovement.")
		if previous.get("type", "") == "MOVE": previous.failed.call("MoveSprite cancelled by ResumeMovement before arrival.")
		return {}
	if command == "StopFollowing":
		if modes.has(key) and modes[key].type == "FOLLOW": modes[key] = {"type":"HOLD", "map":map_file, "npc":npc}; _pose(npc, str(npc.get_meta("facing", "down")))
		if npc == game.player: modes.erase(key); game.player.velocity = Vector3.ZERO
		return {}
	var map: Dictionary = game.map_data.get("_map_files", {}).get(map_file, {})
	var required := "MOVE" if command == "MoveSprite" else "FOLLOW"
	var direct := required == "FOLLOW" and args.size() == 2
	var target: Node3D
	if required == "FOLLOW":
		target = actor(map_file, str(args[1]))
		if target == null or target == npc: return {"error":"Missing target or self-follow is not allowed."}
	var nodes: Array[Vector3] = []
	if not direct:
		var inspected := Paths.inspect(map)
		var name := str(args[-1])
		if not inspected.paths.has(name): return {"error":"Missing or invalid path: " + name}
		var path: Dictionary = inspected.paths[name]
		if path.type != required: return {"error":"Path %s must be %s." % [name, required]}
		var origin: Vector3 = game._array_to_vector3(map.get("origin", [0,0,0])) if npc == game.player else npc.get_meta("map_origin", Vector3.ZERO)
		for point: Array in path.nodes: nodes.append(Vector3(origin.x + float(point[0]), npc.position.y, origin.z + float(point[1])))
	modes[key] = _route_mode(npc, map_file, required, nodes, direct, target, complete, failed)
	if required == "MOVE": route_history.begin(npc,map_file)
	elif direct:
		route_history.record(target,map_file)
		_route_destination(modes[key])
	return {"pending":true} if required == "MOVE" else {}

func cancel_moves() -> void:
	for key in modes.keys():
		if modes[key].type == "MOVE" and not modes[key].get("patrol", false):
			var npc: Area3D = modes[key].npc
			modes[key] = {"type":"HOLD", "map":modes[key].map, "npc":npc}
			if is_instance_valid(npc): _pose(npc, str(npc.get_meta("facing", "down")))

	_restore_yield_hint()

func cancel_actor(npc: Node) -> void:
	route_history.erase(npc)
	for other_key in modes.keys():
		var other: Dictionary = modes[other_key]
		if other.get("target") == npc:
			if other.npc == game.player: release_player()
			else: modes[other_key] = {"type":"HOLD", "map":other.map, "npc":other.npc}
	var key := npc.get_instance_id()
	if not modes.has(key): return
	var previous: Dictionary = modes[key]
	modes[key] = {"type":"HOLD", "map":previous.map, "npc":npc}
	_pose(npc, str(npc.get_meta("facing", "down")))
	if previous.type == "MOVE": previous.failed.call("NPC hidden during MoveSprite.")
	_restore_yield_hint()

func clear() -> void:
	# Location changes pause patrols without losing their route cursors.
	for key in modes.keys():
		if not modes[key].get("patrol", false): modes.erase(key)
	route_history.clear(); cancel_waits(); _restore_yield_hint()
	if game.player != null: game.player.velocity = Vector3.ZERO

func controls(npc: Node) -> bool:
	return modes.has(npc.get_instance_id())

func update(delta: float) -> void:
	_update_waiters()
	for key in modes.keys():
		if not modes.has(key): continue
		var mode: Dictionary = modes[key]
		if mode.get("patrol", false) and (not is_instance_valid(mode.npc) or not mode.npc.get_meta("patrol_active", false)): continue
		if not is_instance_valid(mode.npc) or (not mode.get("patrol", false) and game._location_for_map_file(mode.map) != game._current_location()):
			modes.erase(key)
			if is_instance_valid(mode.npc): route_history.erase(mode.npc)
			if mode.type == "MOVE": mode.failed.call("MoveSprite actor left the active map.")
			continue
		if mode.type == "HOLD" or game.script_host.sprite_hidden(mode.npc): continue
		if not game.adventure_started or game.in_battle or game.swim_transitioning or game.dialog_open: continue
		# Script locks stop manual input; guided following must keep progressing.
		var npc: Node3D = mode.npc
		if mode.type == "MOVE" and npc != game.player:
			var player_follow:Dictionary = modes.get(game.player.get_instance_id(),{})
			if player_follow.get("type","") == "FOLLOW" and player_follow.get("target") == npc and flat(npc.position).distance_to(flat(game.player.position)) > FOLLOW_DISTANCE*2.0 and not game._platform_at_position(npc.position,npc,FOLLOW_DISTANCE).is_empty():
				_pose(npc,str(npc.get_meta("facing","down"))); continue
		var destination: Vector3
		if mode.type == "MOVE":
			if mode.get("waiting_player",false):
				if game.player.position.distance_to(mode.wait_player_position) < 0.02: continue
				mode.wait_player_position = game.player.position
				if _player_obstruction(mode): continue
				mode.waiting_player = false; mode.attempts = 0; mode.avoid_elapsed = 0.0; mode.blocked = 0.0; mode.replan = 0.0
				_restore_yield_hint()
			while mode.index < mode.nodes.size() and flat(npc.position).distance_to(flat(mode.nodes[mode.index])) <= 0.02:
				route_history.record(npc,mode.map,true)
				mode.segment_start = mode.nodes[mode.index]; mode.index += 1
				mode.attempts = 0; mode.avoid_elapsed = 0.0; mode.avoid_budget = 0.0; mode.detour.clear()
			if mode.attempts > 0:
				mode.avoid_elapsed += delta
				if mode.avoid_elapsed >= mode.avoid_budget:
					_fail_move(key,mode,"Local detour exceeded its progress deadline."); continue
			if mode.index >= mode.nodes.size():
				route_history.record(npc,mode.map,true)
				modes[key] = {"type":"HOLD", "map":mode.map, "npc":npc}
				_pose(npc, str(npc.get_meta("facing", "down")))
				mode.complete.call(); continue
			destination = mode.nodes[mode.index]
		else:
			if not is_instance_valid(mode.target): modes.erase(key); continue
			if mode.direct:
				route_history.record(mode.target,mode.map)
				destination = _route_destination(mode)
				if mode.route_available:
					if mode.route_remaining <= FOLLOW_DISTANCE:
						_pose(npc,str(npc.get_meta("facing","down"))); continue
				else:
					if flat(npc.position).distance_to(flat(mode.target.position)) <= FOLLOW_DISTANCE:
						_pose(npc,str(npc.get_meta("facing","down"))); continue
					destination = mode.target.position-(mode.target.position-npc.position).normalized()*FOLLOW_DISTANCE
			else:
				if flat(npc.position).distance_to(flat(mode.target.position)) <= FOLLOW_DISTANCE:
					_pose(npc,str(npc.get_meta("facing","down"))); continue
				destination = follow_destination(npc.position,mode.target.position,mode.nodes)
		# Use the existing traversal surface's low ramp before turning off its side.
		if npc == game.player and mode.type == "FOLLOW":
			for surface: Dictionary in game.traversal_surfaces:
				if int(surface.get("visual_layer",-1)) != game._active_visual_layer(): continue
				var here: Vector2 = game._surface_coordinates(surface,npc.position)
				var coordinate: Vector2 = game._surface_coordinates(surface,destination)
				var half := float(surface.length)*0.5
				var ramp := float(surface.entrance_length)
				if absf(here.x)>half+ramp or absf(here.y)>float(surface.width)*0.5: continue
				var upper := float(surface.get("lateral_max",float(surface.width)*0.5))-0.4
				var lower := float(surface.get("lateral_min",-float(surface.width)*0.5))+0.4
				if coordinate.y >= lower and coordinate.y <= upper: break
				var height := float(surface.elevation)*clampf(1.0-maxf(0.0,absf(here.x)-half)/maxf(ramp,0.001),0,1)
				if height <= 0.35:
					var side := -1.0 if coordinate.y < lower else 1.0
					destination = npc.position+surface.side_axis*(side*(float(surface.width)*0.5+0.45)-here.y)
				else:
					var extent := half+ramp*0.8
					var end_a: Vector3 = surface.center+surface.axis*extent
					var end_b: Vector3 = surface.center-surface.axis*extent
					destination = end_a if flat(end_a).distance_squared_to(flat(mode.target.position)) < flat(end_b).distance_squared_to(flat(mode.target.position)) else end_b
				break
		mode.replan = maxf(0.0, float(mode.replan)-delta)
		var detours_allowed: bool = not mode.get("patrol", false) and (mode.type == "MOVE" or mode.direct)
		var platform_follower:bool = npc == game.player and mode.type == "FOLLOW" and not game._platform_at_position(npc.position,npc,FOLLOW_DISTANCE).is_empty()
		if detours_allowed:
			if mode.detour_goal.distance_to(destination) > 0.5:
				mode.detour.clear()
				if mode.type == "FOLLOW": mode.attempts = 0
			while not mode.detour.is_empty() and flat(npc.position).distance_to(flat(mode.detour[0])) <= 0.03: mode.detour.pop_front()
			if not mode.detour.is_empty(): destination = mode.detour[0]
		var motion := destination - npc.position; motion.y = 0
		if motion.length() <= 0.01: _pose(npc, str(npc.get_meta("facing", "down"))); continue
		motion = motion.limit_length((game.MOVE_SPEED if npc == game.player else Movement.SPEED) * minf(delta, 0.1))
		if mode.type == "FOLLOW" and mode.direct and mode.route_available:
			motion = motion.limit_length(maxf(0.0,float(mode.route_remaining)-FOLLOW_DISTANCE))
		# Followers must never advance into the player's personal space, even at bends.
		if mode.type == "FOLLOW" and not (mode.direct and mode.route_available) and flat(npc.position + motion).distance_to(flat(mode.target.position)) < FOLLOW_DISTANCE:
			motion = motion.limit_length(maxf(0.0, flat(npc.position).distance_to(flat(mode.target.position)) - FOLLOW_DISTANCE))
		if mode.type == "FOLLOW" and npc != game.player and flat(npc.position + motion).distance_to(flat(game.player.position)) < FOLLOW_DISTANCE:
			_pose(npc, str(npc.get_meta("facing", "down"))); continue
		if motion.length() <= 0.001: _pose(npc, str(npc.get_meta("facing", "down"))); continue
		if detours_allowed and mode.detour.is_empty() and mode.replan <= 0 and _travel_fraction(npc,npc.position,motion) < 0.999:
			mode.detour_goal = destination
			if mode.attempts >= clampi(int(avoidance.max_retries),1,10):
				if mode.type == "MOVE": _fail_move(key,mode,"Local detour retry limit reached. " + str(mode.search_reason))
				else:
					# A follower can wait for its guide or a moving blocker to clear.
					mode.attempts = 0; mode.replan = 0.4
					_pose(npc,str(npc.get_meta("facing","down")))
				continue
			if mode.attempts == 0: mode.avoid_budget = clampf(float(avoidance.timeout),0.5,10.0)+flat(npc.position).distance_to(flat(destination))/Movement.SPEED
			mode.attempts += 1
			var anchor: Vector3 = mode.segment_start if mode.type == "MOVE" else npc.position
			var search_settings := avoidance.duplicate()
			search_settings.neighbor_rejoins = platform_follower
			var recorded:Dictionary = {}
			if search_settings.neighbor_rejoins and mode.type == "FOLLOW" and mode.route_available:
				recorded = route_history.get_route(mode.target,mode.map)
				var rejoins:Array[Vector3] = []
				for index in range(maxi(0,int(mode.route_cursor)-int(recorded.base)+1),recorded.points.size()):
					var point:Vector3 = recorded.points[index]
					if flat(point).distance_to(flat(npc.position)) > float(avoidance.radius):continue
					if not rejoins.is_empty() and flat(point).distance_to(flat(rejoins[-1])) < 0.25:continue
					rejoins.append(point)
				search_settings.rejoin_points = rejoins
			var search := LocalPath.find(npc.position,anchor,destination,func(start,end): return _clear_local_segment(mode,npc,start,end),search_settings)
			mode.detour = search.route; mode.search_reason = search.reason
			if not search.route.is_empty() and not recorded.is_empty():
				var rejoin:Vector3 = search.route[-1]
				for index in range(maxi(0,int(mode.route_cursor)-int(recorded.base)),recorded.points.size()):
					if flat(recorded.points[index]).distance_to(flat(rejoin)) < 0.01:
						mode.route_cursor = recorded.base+index
						mode.detour_goal = recorded.points[index]
						break
			mode.replan = 0.4
			if not mode.detour.is_empty(): continue
			if search_settings.neighbor_rejoins and mode.type == "FOLLOW":
				# Do not slide away from the recorded approach after a failed plan.
				_pose(npc,str(npc.get_meta("facing","down"))); continue
		if platform_follower and _travel_fraction(npc,npc.position,motion) < 0.999:
			mode.detour.clear()
			_pose(npc,str(npc.get_meta("facing","down"))); continue
		var previous := npc.position
		var fraction := 1.0
		if npc == game.player:
			game._move_script_player(motion, delta)
		else:
			fraction = game._move_vehicle_fraction(npc, motion)
			npc.position += motion * fraction
			game._animate_placed_npc(npc, previous, direction(motion, str(npc.get_meta("facing", "down"))), delta)
		if mode.type == "MOVE": route_history.record(npc,mode.map)
		if fraction < 0.999 and detours_allowed: mode.detour.clear()
		if mode.type == "MOVE":
			mode.blocked = float(mode.blocked) + delta if fraction < 0.999 else 0.0
			if mode.blocked >= BLOCKED_TIMEOUT and not mode.get("patrol", false):
				_fail_move(key,mode,"MoveSprite blocked by collision. " + str(mode.search_reason))

func _route_destination(mode: Dictionary) -> Vector3:
	var npc: Node3D = mode.npc
	var route := route_history.get_route(mode.target,mode.map)
	mode.route_available = not route.is_empty() and route.points.size() >= 2
	if not mode.route_available: return mode.target.position
	if mode.route_id != route.id or mode.route_cursor < route.base:
		var joined := project(npc.position,route.points)
		mode.route_id = route.id; mode.route_cursor = route.base+int(joined.segment)+1
		mode.route_join = joined.point; mode.joining_route = flat(npc.position).distance_to(flat(joined.point)) > 0.04
	if mode.joining_route:
		if flat(npc.position).distance_to(flat(mode.route_join)) <= 0.04 or (npc == game.player and _follow_hint_blocked(npc,mode.route_join,mode.target)):
			mode.joining_route = false
	var end: int = route.base+route.points.size()-1
	while not mode.joining_route and mode.route_cursor < end:
		var point: Vector3 = route.points[mode.route_cursor-route.base]
		if flat(npc.position).distance_to(flat(point)) > 0.04 and not (npc == game.player and game.active_traversal_layer <= 0 and _follow_hint_blocked(npc,point,mode.target)): break
		mode.route_cursor += 1
	var index: int = clampi(mode.route_cursor-route.base,0,route.points.size()-1)
	var next: Vector3 = route.points[index]
	var remaining := flat(npc.position).distance_to(flat(next))+float(route.lengths[-1])-float(route.lengths[index])
	if mode.joining_route:
		remaining = flat(npc.position).distance_to(flat(mode.route_join))+flat(mode.route_join).distance_to(flat(next))+float(route.lengths[-1])-float(route.lengths[index])
	mode.route_remaining = remaining
	return mode.route_join if mode.joining_route else next

func _fail_move(key: int, mode: Dictionary, reason: String) -> void:
	if _player_obstruction(mode):
		mode.waiting_player = true; mode.wait_player_position = game.player.position; mode.detour.clear()
		_pose(mode.npc,str(mode.npc.get_meta("facing","down")))
		# Guided input must be returned so the player can resolve the obstruction.
		release_player()
		if game.hint_label != null and not showing_yield_hint:
			yield_hint = game.hint_label.text; showing_yield_hint = true
			game.hint_label.text = "Please step aside so the NPC can finish walking."
		return
	modes[key] = {"type":"HOLD","map":mode.map,"npc":mode.npc}
	_pose(mode.npc,str(mode.npc.get_meta("facing","down")))
	mode.failed.call("%s Required node %d was not reached." % [reason,mode.index+1])

func player_can_yield() -> bool:
	for mode: Dictionary in modes.values():
		if mode.get("waiting_player",false): return true
	return false

func _player_obstruction(mode: Dictionary) -> bool:
	if mode.npc.get_meta("npc_definition", {}).get("type") == "vehicle": return false
	if game.player == null or mode.index >= mode.nodes.size(): return false
	var npc: Area3D = mode.npc
	var probe: Vector3 = mode.nodes[mode.index]-npc.position; probe.y = 0
	probe = probe.limit_length(0.5)
	var ignored: Array[RID] = [game.player.get_rid()]
	return game._npc_motion_fraction(npc,probe) < 0.999 and game._npc_motion_fraction(npc,probe,null,ignored) >= 0.999

func _restore_yield_hint() -> void:
	if player_can_yield(): return
	if showing_yield_hint and game.hint_label != null: game.hint_label.text = yield_hint
	showing_yield_hint = false

func _clear_local_segment(mode: Dictionary, npc: Node3D, start: Vector3, end: Vector3) -> bool:
	var samples := maxi(1,ceili(start.distance_to(end)/0.2))
	for index in samples+1:
		if not _local_walkable(mode.map,npc,start.lerp(end,float(index)/samples)): return false
	return _travel_fraction(npc,start,end-start) >= 0.999

func _local_walkable(map_file: String, npc: Node3D, point: Vector3) -> bool:
	# A foot touching the entrance is supported even where the ground grid ends.
	# Segment sweeps still enforce rails and actors.
	var support_size:Vector3 = game.TERRAIN_FOOTPRINT_SIZE if npc == game.player else game.NPC_FOOT_COLLISION_SIZE
	if not game._platform_at_position(point,npc,maxf(support_size.x,support_size.z)*0.5).is_empty():return true
	var map: Dictionary = game.map_data.get("_map_files",{}).get(map_file,{})
	var origin: Vector3 = game._array_to_vector3(map.get("origin",[0,0,0]))
	var size: Variant = map.get("size",map.get("map_size",[]))
	var footprint: Vector2 = Vector2(game.NPC_FOOT_COLLISION_SIZE.x,game.NPC_FOOT_COLLISION_SIZE.z)*0.5
	if npc == game.player: footprint = Vector2(game.TERRAIN_FOOTPRINT_SIZE.x,game.TERRAIN_FOOTPRINT_SIZE.z)*0.5
	var grid: Variant = map.get("_terrain_grid")
	for dx in [-footprint.x,footprint.x]:
		for dz in [-footprint.y,footprint.y]:
			var local := point-origin+Vector3(dx,0,dz)
			if size is Array and size.size() >= 2 and (absf(local.x)>float(size[0])*0.5 or absf(local.z)>float(size[1])*0.5): return false
			if grid is Dictionary:
				var terrain := str(grid.get(Vector2i(roundi(local.x),roundi(local.z)),""))
				if terrain.is_empty(): return false
				var movement: String = "swimming" if npc == game.player and game.swimming else str(npc.get_meta("movement_mode","ground"))
				if movement == "swimming" and terrain != "water": return false
				if movement == "ground" and terrain == "water": return false
	return true

func _follow_hint_blocked(npc: Node3D, point: Vector3, guide:Node3D = null) -> bool:
	# Ground-only guides can pass under deck edges. Do not steer the player onto
	# a raised deck to chase that ground-level sample, then back off it repeatedly.
	for surface: Dictionary in game.traversal_surfaces:
		if int(surface.get("visual_layer",-1)) != game._active_visual_layer(): continue
		var coordinate: Vector2 = game._surface_coordinates(surface,point)
		var half := float(surface.length)*0.5
		var ramp := float(surface.entrance_length)
		if absf(coordinate.y)>float(surface.width)*0.5 or absf(coordinate.x)>half+ramp: continue
		var height := float(surface.elevation)*clampf(1.0-maxf(0.0,absf(coordinate.x)-half)/maxf(ramp,0.001),0,1)
		if height>0.35 and point.y+0.05<height: return true
	# A guide occupying its own fresh trail is temporary, not an inaccessible
	# waypoint. Keep the turn; normal movement still collides with the guide.
	var ignored:Array[RID] = []
	if guide != null and not game._platform_at_position(point,npc,FOLLOW_DISTANCE).is_empty():
		if guide is CollisionObject3D:ignored.append(guide.get_rid())
		for child in guide.get_children():
			if child is CollisionObject3D:ignored.append(child.get_rid())
	return _travel_fraction(npc,Vector3(point.x,npc.position.y,point.z),Vector3.ZERO,ignored)<0.999

func _travel_fraction(npc: Node3D, start: Vector3, motion: Vector3, ignored:Array[RID] = []) -> float:
	if npc != game.player:
		# Vehicles push players during movement. Do not route around them before
		# _move_vehicle_fraction can attempt the collision-limited push.
		var obstacles := ignored.duplicate()
		if npc.get_meta("npc_definition", {}).get("type") == "vehicle" and game.player != null:
			obstacles.append(game.player.get_rid())
		return game._npc_motion_fraction(npc,motion,start,obstacles)
	var steps := maxi(1,ceili(motion.length()/0.05))
	for index in steps:
		var fraction := _player_floor_travel_fraction(npc,start+motion*float(index)/steps,motion/steps,ignored)
		if fraction < 0.999:return (float(index)+fraction)/steps
	return 1.0

func _player_floor_travel_fraction(npc:Node3D, start:Vector3, motion:Vector3, ignored:Array[RID] = [])->float:
	if not game.swimming and game.active_traversal_layer <= 0:
		var samples := maxi(1,ceili(motion.length()/0.1))
		for index in samples+1:
			if game._terrain_foot_blocked(start+motion*float(index)/samples): return 0.0
	var shapes := npc.find_children("*", "CollisionShape3D", true, false)
	if shapes.is_empty(): return 0.0
	var shape: CollisionShape3D = shapes[0]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape; query.transform = shape.global_transform
	query.transform.origin += start-npc.position; query.motion = motion
	# move_and_slide already leaves safe_margin at contacts. Inflating the
	# planning shape beyond that gap makes every escape/detour start overlap.
	query.margin = 0.0
	query.collision_mask = game._floor_collision_mask(npc,start,game.active_traversal_layer <= 0)
	query.exclude = [npc.get_rid()]
	query.exclude += ignored
	var space := npc.get_world_3d().direct_space_state
	query.motion = Vector3.ZERO
	if not space.intersect_shape(query,1).is_empty(): return 0.0
	query.motion = motion
	var fraction := space.cast_motion(query)
	return float(fraction[0]) if fraction.size() == 2 else 0.0

func _pose(npc: Node3D, facing: String) -> void:
	if npc != game.player: game._set_npc_pose(npc, facing)
	else: game.player.velocity = Vector3.ZERO

func release_player() -> void:
	if game.player != null: modes.erase(game.player.get_instance_id()); game.player.velocity = Vector3.ZERO

func cancel_waits() -> void:
	waiters.clear()

func wait_movement(map_file: String, npc: Node3D, complete: Callable, failed: Callable) -> Dictionary:
	var key := npc.get_instance_id()
	if npc != game.player and game.script_host.sprite_hidden(npc): return {"error":"Cannot wait for a hidden NPC."}
	var mode: Dictionary = modes.get(key, {})
	var state: Variant = game.npc_movement_states.get(key)
	if mode.get("type", "") == "HOLD": return {}
	if mode.is_empty() and (state == null or state.preset in ["stationary", "look_around"] or state.extent == Vector2.ZERO): return {}
	var start := npc.position
	var loop := false
	if not mode.is_empty():
		if mode.type == "FOLLOW" and not mode.direct: start = mode.nodes[0]; loop = flat(mode.nodes[0]).distance_to(flat(mode.nodes[-1])) <= 0.03
	elif state.preset == "random":
		start = state.target
	else:
		loop = true; start = state.anchor
		match state.preset:
			"left_right": start.x += state.extent.x
			"up_down": start.z += state.extent.y
			"clockwise", "counterclockwise": start += Vector3(-state.extent.x,0,-state.extent.y)
	waiters[key] = {"npc":npc,"map":map_file,"start":start,"previous":npc.position,"armed":flat(npc.position).distance_to(flat(start)) <= 0.03,"left":false,"loop":loop,"complete":complete,"failed":failed,"scripted":not mode.is_empty(), "random":mode.is_empty() and state != null and state.preset == "random", "waypoint":state.waypoint if state != null else 0, "seen":{}}
	return {"pending":true}

func _update_waiters() -> void:
	for key in waiters.keys():
		if not waiters.has(key): continue
		var waiter: Dictionary = waiters[key]
		if not is_instance_valid(waiter.npc) or game._location_for_map_file(waiter.map) != game._current_location():
			waiters.erase(key); waiter.failed.call("WaitMovement actor left the map."); continue
		if waiter.npc != game.player and game.script_host.sprite_hidden(waiter.npc):
			waiters.erase(key); waiter.failed.call("WaitMovement actor was hidden."); continue
		var mode: Dictionary = modes.get(key, {})
		var finished: bool = waiter.scripted and mode.get("type", "HOLD") == "HOLD"
		var current: Vector3 = waiter.npc.position
		if mode.get("type", "") == "FOLLOW" and not waiter.loop:
			if not is_instance_valid(mode.target):
				waiters.erase(key); waiter.failed.call("WaitMovement guide left the map."); continue
			if mode.direct: _route_destination(mode)
			var target_mode: Dictionary = modes.get(mode.target.get_instance_id(), {})
			finished = target_mode.get("type", "") != "MOVE" and flat(current).distance_to(flat(mode.target.position)) <= FOLLOW_DISTANCE + 0.03 and (not mode.get("route_available",false) or float(mode.route_remaining) <= FOLLOW_DISTANCE+0.03)
		var near := Geometry2D.get_closest_point_to_segment(flat(waiter.start), flat(waiter.previous), flat(current)).distance_to(flat(waiter.start)) <= 0.03
		var all_nodes := true
		if mode.get("type", "") == "FOLLOW":
			for index in mode.nodes.size():
				if Geometry2D.get_closest_point_to_segment(flat(mode.nodes[index]), flat(waiter.previous), flat(current)).distance_to(flat(mode.nodes[index])) <= 0.03: waiter.seen[index] = true
			all_nodes = waiter.seen.size() == mode.nodes.size()
		if waiter.loop:
			if not waiter.armed and near:
				waiter.armed = true
				# A partial lap before reaching the start cannot satisfy this cycle.
				waiter.seen.clear()
				if mode.get("type", "") == "FOLLOW":
					for index in mode.nodes.size():
						if flat(mode.nodes[index]).distance_to(flat(waiter.start)) <= 0.03: waiter.seen[index] = true
			elif waiter.left and near and all_nodes: finished = true
			elif waiter.armed and flat(current).distance_to(flat(waiter.start)) > 0.06: waiter.left = true
		else:
			if not waiter.scripted:
				var state: Variant = game.npc_movement_states.get(key)
				finished = state != null and state.waypoint > waiter.waypoint and state.timer > 0 and current.distance_to(state.target) <= 0.03
		waiter.previous = current
		if finished: waiters.erase(key); waiter.complete.call()

static func flat(position: Vector3) -> Vector2:
	return Vector2(position.x, position.z)

static func direction(motion: Vector3, fallback: String) -> String:
	if absf(motion.x) + absf(motion.z) < 0.00001: return fallback
	if absf(motion.x) > absf(motion.z): return "right" if motion.x > 0 else "left"
	return "down" if motion.z > 0 else "up"

static func project(position: Vector3, nodes: Array) -> Dictionary:
	var best := {"point":nodes[0], "progress":0.0, "segment":0, "distance":INF}
	var progress := 0.0
	for i in nodes.size() - 1:
		var start: Vector2 = flat(nodes[i]); var end: Vector2 = flat(nodes[i + 1])
		var point := Geometry2D.get_closest_point_to_segment(flat(position), start, end)
		var distance := point.distance_squared_to(flat(position))
		if distance < best.distance: best = {"point":Vector3(point.x, position.y, point.y), "progress":progress + start.distance_to(point), "segment":i, "distance":distance}
		progress += start.distance_to(end)
	return best

static func follow_destination(position: Vector3, target: Vector3, nodes: Array) -> Vector3:
	var current := project(position, nodes); var goal := project(target, nodes)
	if goal.distance > CORRIDOR_DISTANCE * CORRIDOR_DISTANCE: return position
	if current.distance > 0.0025: return current.point
	var progress := 0.0
	var boundaries: Array = [{"point":nodes[0], "progress":0.0}]
	for i in nodes.size() - 1:
		progress += flat(nodes[i]).distance_to(flat(nodes[i + 1])); boundaries.append({"point":nodes[i + 1], "progress":progress})
	if goal.progress < current.progress: boundaries.reverse()
	for boundary: Dictionary in boundaries:
		if goal.progress > current.progress and boundary.progress > current.progress + 0.02 and boundary.progress < goal.progress: return boundary.point
		if goal.progress < current.progress and boundary.progress < current.progress - 0.02 and boundary.progress > goal.progress: return boundary.point
	return goal.point

# Shared route state for script commands and patrols.
func _route_mode(npc: Node3D, map_file: String, required: String, nodes: Array[Vector3], direct: bool, target: Node3D, complete: Callable, failed: Callable) -> Dictionary:
	return {"type":required, "map":map_file, "npc":npc, "nodes":nodes, "direct":direct, "index":0, "target":target, "complete":complete, "failed":failed, "blocked":0.0, "detour":[], "replan":0.0, "detour_goal":Vector3.ZERO, "segment_start":npc.position, "attempts":0, "avoid_elapsed":0.0, "avoid_budget":0.0, "search_reason":"", "route_id":-1,"route_cursor":0,"route_join":Vector3.ZERO,"joining_route":false,"route_available":false,"route_remaining":0.0}

# Patrols use MOVE's route cursor, speed, animation and collision application.
func patrol_route(npc: Area3D, map_file: String, nodes: Array[Vector3], complete: Callable) -> void:
	var mode := _route_mode(npc, map_file, "MOVE", nodes, false, null, complete, func(_message): pass)
	mode["patrol"] = true
	modes[npc.get_instance_id()] = mode
