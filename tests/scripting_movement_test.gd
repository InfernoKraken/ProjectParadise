extends SceneTree

var checks := 0
var failures := 0
const FILE := "script_movement_fixture.json"

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _initialize() -> void:
	create_timer(30).timeout.connect(func():push_error("SCRIPT_MOVEMENT_TIMEOUT");quit(2))
	call_deferred("test_movement")

func test_movement() -> void:
	var game: Node = load("res://world/main.gd").new()
	game.world = Node3D.new(); root.add_child(game.world)
	game.player = CharacterBody3D.new(); game.player.position = Vector3(503,0,500); game.world.add_child(game.player)
	game.dialog_panel = PanelContainer.new(); game.dialog_speaker = Label.new(); game.dialog_label = Label.new(); game.dialog_button = Button.new()
	game.adventure_started = true; game.active_authored_map_id = "fixture"
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/script_tour.json"))
	map.origin = [500,0,500]; map.npcs = [{"id":1}, {"id":2}]
	map._npc_map_file = FILE
	map._resolved_npcs = [{"id":1,"position":[0,0,0],"facing":"down","type":"fakemon","sprite":"Sylvafin","interaction_text":""},{"id":2,"position":[8,0,8],"facing":"down","type":"fakemon","sprite":"Sylvafin","interaction_text":""}]
	game.map_data = {"_map_files":{FILE:map}, "_authored_file_ids":{FILE:"fixture"}, "authored_maps":{"fixture":map}}
	game._build_placed_npcs(map, Vector3(500,0,500)); await physics_frame
	# Both command types use map-local ground nodes while preserving actor height.
	var flyer_map := map.duplicate(true); flyer_map._npc_map_file = "flying_fixture.json"
	flyer_map.npcs = [{"id":3}]
	flyer_map._resolved_npcs = [{"id":3,"position":[0,0.25,0],"facing":"down","type":"fakemon","sprite":"Scorchick","interaction_text":"","movement_mode":"flying","height_offset":1.5,"hidden":true}]
	game.map_data._map_files["flying_fixture.json"] = flyer_map
	game._build_placed_npcs(flyer_map, Vector3(500,0,500))
	var flyer: Area3D = game.runtime_npcs["flying_fixture.json"][3]
	var ignore := func():pass
	check(game.script_host.sprite_hidden(flyer) and flyer.get_node("FootCollision").collision_layer == 0, "Authored Hidden applies on NPC registration before any interaction")
	check(not game._try_script_npc(flyer), "Initially hidden NPC cannot activate its script")
	game.script_host.map_file = "flying_fixture.json"; game.script_host.execute("ShowSprite", ["NPC3"], ignore)
	check(not game.script_host.sprite_hidden(flyer) and flyer.get_node("FootCollision").collision_layer != 0, "ShowSprite overrides authored Hidden and restores collision")
	game.script_host.reset_sprites()
	check(game.script_host.sprite_hidden(flyer) and flyer.get_node("FootCollision").collision_layer == 0, "New game/save reset restores authored Hidden before headers")
	game.script_host.execute("ShowSprite", ["NPC3"], ignore)
	for command in ["MoveSprite", "FollowSprite"]:
		var args := ["NPC3", "ProfessorApproach"] if command == "MoveSprite" else ["NPC3", "Player", "InstituteTour"]
		game.npc_script_movement.request("flying_fixture.json", command, args, ignore, ignore)
		var mode: Dictionary = game.npc_script_movement.modes[flyer.get_instance_id()]
		var path_name: String = args[-1]
		var inspected: Dictionary = load("res://world/scripting/script_paths.gd").inspect(flyer_map)
		check(is_equal_approx(flyer.position.y, 3.75), command + " actor preserves placement and flying height")
		for index in mode.nodes.size():
			var point: Array = inspected.paths[path_name].nodes[index]
			check(mode.nodes[index].is_equal_approx(Vector3(500+point[0],3.75,500+point[1])), command + " nodes use origin once and preserve elevation")
	game.npc_script_movement.clear()
	var npc: Area3D = game.runtime_npcs[FILE][1]
	var foot: StaticBody3D = npc.get_node("FootCollision"); var collision_layer := foot.collision_layer
	game.script_runner.failed.connect(func(_details):pass)
	check(game.run_map_block(FILE,"BeginTour"), "Tour starts")
	check(game.dialog_open and game.script_input_locked, "Tour dialogue and lock")
	game._advance_dialogue()
	check(game.script_runner.waiting and game.script_input_locked, "Move blocks interpreter despite Lock")
	game._physics_process(0.1)
	check(game.script_runner.running and game.script_input_locked and npc.position.x > 500, "Next command not premature; NPC advances")
	for i in 100: game.npc_script_movement.update(0.1)
	check(not game.script_runner.running and not game.script_input_locked and npc.position.distance_to(Vector3(502,0,500)) < 0.03, "Move completes in order, resumes and unlocks")
	check(game.npc_script_movement.modes[npc.get_instance_id()].type == "FOLLOW", "Follow survives End and is nonblocking")
	check(foot.collision_layer == collision_layer and foot.get_child(0).disabled == false, "Collision remained enabled")
	check(npc.get_meta("facing") == "right", "Face Player uses existing cardinal pose")
	var stationary := npc.position
	for i in 20: game.npc_script_movement.update(0.1)
	check(npc.position == stationary, "Follower stops at desired distance")
	game.player.position = Vector3(502,0,504)
	for i in 80: game.npc_script_movement.update(0.1)
	check(npc.position.z > 501 and npc.position.distance_to(game.player.position) >= 1.24, "Follower pursues route without occupying Player")
	var callbacks := func():pass
	for direction in ["North","South","East","West"]:
		game.npc_script_movement.request(FILE,"FaceSprite",["Professor",direction],callbacks,callbacks)
		check(npc.get_meta("facing") == {"North":"up","South":"down","East":"right","West":"left"}[direction], "Face direction: " + direction)
	check(game.npc_script_movement.request(FILE,"FaceSprite",["Professor","NPC2"],callbacks,callbacks).is_empty(), "Face another NPC")
	check(game.npc_script_movement.request(FILE,"FaceSprite",["Professor","Missing"],callbacks,callbacks).has("error"), "Face missing target safely")
	for args in [["Missing","ProfessorApproach"],["Professor","Missing"],["Professor","InstituteTour"]]: check(game.npc_script_movement.request(FILE,"MoveSprite",args,callbacks,callbacks).has("error"), "Move invalid references")
	for args in [["Missing","Player","InstituteTour"],["Professor","Missing","InstituteTour"],["Professor","Player","ProfessorApproach"],["Professor","Professor","InstituteTour"]]: check(game.npc_script_movement.request(FILE,"FollowSprite",args,callbacks,callbacks).has("error"), "Follow invalid references/self")
	game.npc_script_movement.request(FILE,"StopFollowing",["Professor"],callbacks,callbacks)
	game.npc_script_movement.request(FILE,"StopFollowing",["Professor"],callbacks,callbacks)
	stationary = npc.position; game.player.position.z += 2
	for i in 10: game.npc_script_movement.update(0.1)
	check(npc.position == stationary, "Repeated StopFollowing holds position")
	check(game.run_map_block(FILE,"StopAtExhibit"), "Exhibit Block resumes movement after StopFollowing")
	for i in 120: game.npc_script_movement.update(0.1)
	check(game.dialog_open and game.script_runner.waiting and npc.position.distance_to(Vector3(502,0,501)) < 0.03, "Exhibit speaks only after reaching path end")
	game._advance_dialogue(); check(not game.script_runner.running and game.npc_script_movement.modes[npc.get_instance_id()].type == "FOLLOW", "Exhibit resumes persistent following")
	game.active_authored_map_id = "other"; game.npc_script_movement.update(0.1); check(game.npc_script_movement.modes.is_empty(), "Leaving map clears modes")
	game.active_authored_map_id = "fixture"; npc.position = Vector3(500,0,500)
	game._add_static_collision("ScriptWall", Vector3(501,0.3,500), Vector3(0.2,1,20)); await physics_frame
	map.script_source = "Block A:\nLock\nMoveSprite Professor ProfessorApproach\nSetFlag PassedWall\nEnd"
	game.run_map_block(FILE,"A")
	for i in 90: game.npc_script_movement.update(0.1)
	check(not game.script_runner.running and not game.script_input_locked and not game.game_flags.has_flag("PassedWall"), "Blocked Move fails safely and releases lock")
	check(npc.position.x < 500.9 and foot.collision_layer == collision_layer, "Static wall stops real physics sweep")
	game.run_map_block(FILE,"A"); game.script_runner.stop(); stationary = npc.position
	for i in 10: game.npc_script_movement.update(0.1)
	check(not game.script_input_locked and npc.position == stationary, "Cancellation stops pending Move and ignores completion")
	game.world.get_node("ScriptWall").queue_free(); await physics_frame; await physics_frame
	npc.position = Vector3(500,0,500); game.player.position = Vector3(502,0,504)
	game.npc_script_movement.request(FILE,"FollowSprite",["Professor","Player","InstituteTour"],callbacks,callbacks)
	game._add_static_collision("FollowWall",Vector3(501,0.3,500),Vector3(0.2,1,2)); await physics_frame
	for i in 60: game.npc_script_movement.update(0.1)
	check(npc.position.x < 500.9 and game.npc_script_movement.modes[npc.get_instance_id()].type == "FOLLOW", "Blocked Follow waits without failing/teleporting")
	game.world.get_node("FollowWall").queue_free(); await physics_frame; await physics_frame
	for i in 100: game.npc_script_movement.update(0.1)
	check(npc.position.x > 501.5 and npc.position.z > 501, "Follow resumes when corridor becomes reachable")
	game.script_host.map_file = FILE
	game.script_host.execute("HideSprite", ["Professor"], callbacks)
	stationary = npc.position
	for tick in 30: game.npc_script_movement.update(0.1)
	check(npc.position == stationary and game.npc_script_movement.modes[npc.get_instance_id()].type == "HOLD", "Hide cancels Follow safely")
	game.script_host.execute("ShowSprite", ["Professor"], callbacks)
	for tick in 10: game.npc_script_movement.update(0.1)
	check(npc.position == stationary, "Show does not resume cancelled Follow")
	game.script_host.execute("HideSprite", ["Professor"], callbacks); game.script_host.execute("ShowSprite", ["Professor"], callbacks)
	map.script_source = "Block Moving:\nLock\nMoveSprite Professor ProfessorApproach\nEnd"
	npc.position = Vector3(500,0,500); game.run_map_block(FILE, "Moving")
	check(game.script_runner.waiting, "Move is pending before hide")
	game.script_host.execute("HideSprite", ["Professor"], callbacks)
	check(not game.script_runner.running and not game.script_input_locked and game.npc_script_movement.modes[npc.get_instance_id()].type == "HOLD", "Hide pending Move fails safely and unlocks interpreter")
	game.script_host.execute("ShowSprite", ["Professor"], callbacks); game.npc_script_movement.clear()
	var npc2: Area3D = game.runtime_npcs[FILE][2]
	var waiting_state := {"done":false}
	npc2.position = Vector3(510,0,510)
	game.npc_movement_states[npc2.get_instance_id()] = load("res://world/npc_movement.gd").new(npc2.position, {"preset":"left_right", "range":[0.5,0]}, 1)
	var outcome: Dictionary = game.npc_script_movement.request(FILE,"WaitMovement",["NPC2"],func():waiting_state.done=true,callbacks)
	check(outcome.get("pending", false) and not waiting_state.done, "Loop WaitMovement initially waits")
	for tick in 150:
		game._update_placed_npcs(0.05); game.npc_script_movement._update_waiters()
		if waiting_state.done: break
	check(waiting_state.done, "WaitMovement resumes after looping preset returns to start after leaving")
	game.npc_script_movement.clear(); npc2.position = Vector3(510,0,510)
	game.npc_movement_states[npc2.get_instance_id()] = load("res://world/npc_movement.gd").new(npc2.position, {"preset":"stationary", "range":[0,0]}, 1)
	check(game.npc_script_movement.request(FILE,"WaitMovement",["NPC2"],callbacks,callbacks).is_empty(), "Stationary actor does not deadlock WaitMovement")
	# Follow waits use real modes; position samples isolate completion from collision.
	map.script_paths.append({"name":"Cycle","type":"FOLLOW","nodes":[[0,0],[2,0],[2,2],[0,0]]})
	npc.position = Vector3(500,0,500)
	game.npc_script_movement.request(FILE,"FollowSprite",["Professor","Player","Cycle"],callbacks,callbacks)
	waiting_state.done = false
	game.npc_script_movement.request(FILE,"WaitMovement",["Professor"],func():waiting_state.done=true,callbacks)
	game.npc_script_movement._update_waiters()
	check(not waiting_state.done, "Closed Follow wait cannot finish at initial start")
	npc.position.x += 0.2; game.npc_script_movement._update_waiters()
	npc.position.x -= 0.2; game.npc_script_movement._update_waiters()
	check(not waiting_state.done, "Short return is not a successful full Follow cycle")
	for point in [Vector3(502,0,500),Vector3(502,0,502),Vector3(500,0,500)]:
		npc.position = point; game.npc_script_movement._update_waiters()
	check(waiting_state.done, "Closed Follow resumes after every node and return to start")
	waiting_state.done = false; npc.position = Vector3(502,0,502)
	game.npc_script_movement.request(FILE,"WaitMovement",["Professor"],func():waiting_state.done=true,callbacks)
	game.npc_script_movement._update_waiters()
	for point in [Vector3(500,0,500),Vector3(502,0,500),Vector3(500,0,500)]:
		npc.position = point; game.npc_script_movement._update_waiters()
	check(not waiting_state.done, "Partial lap before first start does not satisfy full cycle")
	game.npc_script_movement.clear()
	npc.position = Vector3(500,0,500); game.player.position = Vector3(502,0,504)
	game.npc_script_movement.request(FILE,"FollowSprite",["Professor","Player","InstituteTour"],callbacks,callbacks)
	waiting_state.done = false
	game.npc_script_movement.request(FILE,"WaitMovement",["Professor"],func():waiting_state.done=true,callbacks)
	npc.position = Vector3(502,0,502.8); game.npc_script_movement._update_waiters()
	check(waiting_state.done, "Open Follow wait completes on catch-up")
	waiting_state.done = false; waiting_state.failed = false
	npc.position = Vector3(500,0,500)
	game.npc_script_movement.request(FILE,"WaitMovement",["Professor"],func():waiting_state.done=true,func(_message):waiting_state.failed=true)
	game.script_host.execute("HideSprite",["Professor"],callbacks)
	game.npc_script_movement._update_waiters()
	check(waiting_state.failed and not waiting_state.done, "Hiding awaited follower fails wait safely")
	game.script_host.execute("ShowSprite",["Professor"],callbacks); game.npc_script_movement.clear()
	game.player.position = Vector3(510,0,510); npc.position = Vector3(500,0,500)
	check(game.npc_script_movement.request(FILE,"FollowSprite",["Professor","Player"],callbacks,callbacks).is_empty(), "Direct Follow does not require a path")
	game.player.position = Vector3(503,0,500)
	for tick in 30: game.npc_script_movement.update(0.05)
	check(npc.position.distance_to(game.player.position) >= 1.24 and npc.position.distance_to(game.player.position) <= 1.28, "Direct Follow reaches close distance without overlapping target")
	waiting_state.done = false
	check(game.npc_script_movement.request(FILE,"WaitMovement",["Professor"],func():waiting_state.done=true,callbacks).get("pending",false), "Direct Follow wait can await catch-up")
	game.npc_script_movement._update_waiters()
	check(waiting_state.done, "Direct Follow WaitMovement finishes after catch-up")
	game.npc_script_movement.clear(); npc.position = Vector3(500,0,500); game.player.position = Vector3(510,0,510)
	game._add_static_collision("SmallBlocker",Vector3(501,0.3,500),Vector3(0.5,1,0.5)); await physics_frame
	waiting_state.done = false
	game.npc_script_movement.request(FILE,"MoveSprite",["Professor","ProfessorApproach"],func():waiting_state.done=true,callbacks)
	var detoured := false
	for tick in 100:
		await physics_frame; game.npc_script_movement.update(0.05)
		detoured = detoured or absf(npc.position.z-500) > 0.3
		if waiting_state.done: break
	check(waiting_state.done and detoured and npc.position.distance_to(Vector3(502,0,500)) < 0.03, "Move detours around small real collider and still reaches authored node")
	game.world.get_node("SmallBlocker").queue_free(); await physics_frame; await physics_frame
	game.npc_script_movement.clear(); npc.position = Vector3(500,0,500); game.player.position = Vector3(501,0,500)
	var player_shape := CollisionShape3D.new(); var player_box := BoxShape3D.new()
	player_box.size = Vector3(0.55,0.3,0.45); player_shape.shape = player_box; player_shape.position.y = 0.15
	game.player.add_child(player_shape); await physics_frame; await physics_frame
	waiting_state.done = false
	game.npc_script_movement.request(FILE,"MoveSprite",["Professor","ProfessorApproach"],func():waiting_state.done=true,callbacks)
	var player_detour := false
	for tick in 100:
		await physics_frame; game.npc_script_movement.update(0.05)
		player_detour = player_detour or absf(npc.position.z-500)>0.3
		if waiting_state.done: break
	check(waiting_state.done and player_detour and npc.position.distance_to(Vector3(502,0,500))<0.03, "NPC detours around actual Player collider and reaches required node")
	check(not player_shape.disabled and game.player.collision_layer == 1 and foot.collision_layer == collision_layer, "Player/NPC collisions remain enabled throughout detour")
	check(game.npc_script_movement._travel_fraction(game.player,npc.position,Vector3.ZERO)<0.999,"Follower probes still reject an occupied waypoint.")
	var platform_entry := {"placement":npc.position,"visual_layer":game._active_visual_layer(),"foreground_masks":[],"navigation_polygon":PackedVector2Array([Vector2(npc.position.x-1,npc.position.z-1),Vector2(npc.position.x+1,npc.position.z-1),Vector2(npc.position.x+1,npc.position.z+1),Vector2(npc.position.x-1,npc.position.z+1)])}
	game.object_sort_entries.append(platform_entry)
	check(game.npc_script_movement._travel_fraction(game.player,npc.position+Vector3(0.555,0,0),Vector3(0.1,0,0))>=0.999,"Follower can move away from a close non-overlapping actor contact.")
	check(not game.npc_script_movement._follow_hint_blocked(game.player,npc.position,npc),"Guide occupancy does not discard a platform approach turn.")
	check(game.npc_script_movement._follow_hint_blocked(game.player,npc.position),"Other actor occupancy still rejects inaccessible approach samples.")
	game.npc_script_movement.clear()
	game.player.position = Vector3(500,0,500)
	game._add_static_collision("FollowerRetryRail",Vector3(500.35,0.15,500),Vector3(0.1,1,2),game.PLATFORM_WALL_LAYER)
	await physics_frame;await physics_frame
	var saved_avoidance:Dictionary = game.npc_script_movement.avoidance.duplicate()
	game.npc_script_movement.avoidance.max_retries = 1
	game.npc_script_movement.avoidance.max_nodes = 1
	game.npc_script_movement.avoidance.max_checks = 1
	game.npc_script_movement.request(FILE,"FollowSprite",["Player","Professor"],ignore,ignore)
	var retry_mode:Dictionary = game.npc_script_movement.modes[game.player.get_instance_id()]
	retry_mode.attempts = 1
	retry_mode.detour_goal = Vector3(500.75,0,500)
	game.npc_script_movement.update(0.05)
	check(retry_mode.attempts == 0 and retry_mode.replan > 0,"Following resets exhausted retries after a cooldown rather than stopping permanently.")
	game.npc_script_movement.update(0.05)
	check(game.player.position.is_equal_approx(Vector3(500,0,500)),"Blocked platform following does not slide sideways while waiting to replan.")
	game.npc_script_movement.update(0.5)
	check(retry_mode.attempts == 1,"Following retries its collision-checked search after the cooldown.")
	game.npc_script_movement.clear()
	game.npc_script_movement.avoidance = saved_avoidance
	game.world.get_node("FollowerRetryRail").queue_free()
	var original_size:Variant = map.get("size")
	map.size = [1,1]
	check(game.npc_script_movement._local_walkable(FILE,game.player,npc.position),"Authored platform floor supports Player detours beyond ground-grid bounds.")
	check(game.npc_script_movement._local_walkable(FILE,npc,npc.position),"NPC and Player share platform support beyond ground-grid bounds.")
	game.object_sort_entries.erase(platform_entry)
	check(not game.npc_script_movement._local_walkable(FILE,game.player,npc.position),"Ground-grid bounds still apply without platform support.")
	if original_size == null:map.erase("size")
	else:map.size = original_size
	game.player.position = Vector3(510,0,510); player_shape.queue_free(); await physics_frame
	var original_paths: Array = map.script_paths.duplicate(true)
	map.size = [4,4]; map._terrain_grid = {Vector2i(0,0):"grass",Vector2i(1,0):"water"}
	check(not game.npc_script_movement._local_walkable(FILE,npc,Vector3(502.1,0,500)), "Local avoidance rejects footprint outside authored map bounds")
	check(not game.npc_script_movement._local_walkable(FILE,npc,Vector3(501,0,500)), "Ground detours reject water")
	check(not game.npc_script_movement._local_walkable(FILE,npc,Vector3(500,0,501)), "Local avoidance rejects missing terrain cells")
	check(game.npc_script_movement._local_walkable(FILE,npc,Vector3(500,0,500)), "Existing ground tile remains walkable")
	map.erase("size"); map.erase("_terrain_grid")
	map.script_paths.append({"name":"LongApproach","type":"MOVE","nodes":[[0,0],[8,0]]})
	game.npc_script_movement.clear(); npc.position = Vector3(500,0,500)
	game._add_static_collision("IntermittentWall",Vector3(500.42,0.3,500),Vector3(0.2,1,20)); await physics_frame
	var obstacle: Node3D = game.world.get_node("IntermittentWall")
	var result := {"done":false,"failed":false,"reason":""}
	game.npc_script_movement.avoidance.timeout = 0.5
	game.npc_script_movement.request(FILE,"MoveSprite",["Professor","LongApproach"],func():result.done=true,func(reason):result.failed=true;result.reason=reason)
	for tick in 100:
		obstacle.position = npc.position+Vector3(0.42,0.3,0) if tick%2 == 0 else Vector3(500,0.3,520)
		await physics_frame; game.npc_script_movement.update(0.1)
		if result.failed or result.done: break
	check(result.failed and not result.done and npc.position.x>500.5 and npc.position.x<508, "Intermittent progress cannot reset bounded avoidance indefinitely")
	check(result.reason.contains("deadline") or result.reason.contains("retry limit"), "Bounded failure reports progress/retry diagnostic and unreached waypoint")
	game.world.get_node("IntermittentWall").queue_free(); map.script_paths.pop_back()
	check(map.script_paths == original_paths, "Avoidance never changes authored path nodes")
	game.world.queue_free(); game.dialog_panel.free(); game.dialog_speaker.free(); game.dialog_label.free(); game.dialog_button.free(); game.free(); await process_frame
	print("SCRIPTING_MOVEMENT_TEST: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
