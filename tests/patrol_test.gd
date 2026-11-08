extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var main = load("res://world/main.gd").new()
	main.world = Node3D.new(); root.add_child(main.world)
	main.player = CharacterBody3D.new(); main.world.add_child(main.player); main.player.position = Vector3(100,0,100)
	main.adventure_started = true
	main.sort_canvas = CanvasLayer.new(); main.world.add_child(main.sort_canvas)
	main.sort_root = Node2D.new(); main.sort_canvas.add_child(main.sort_root)
	var water := {}
	for x in range(-20,30):
		for z in range(-20,21): water[Vector2i(x,z)] = "water"
	var config := {"type":"finite", "creation_interval":0.2, "path":[[0,0],[8,0]], "vehicles":[{"type":"vehicle","sprite":"Tug"},{"type":"vehicle","sprite":"Tug"}], "repeat":false}
	var region := {"_npc_map_file":"rainforest_clearing.json", "_terrain_grid":water, "_resolved_npcs":[], "patrols":[config]}
	main._build_placed_npcs(region, Vector3.ZERO)
	var state: Dictionary = main.patrols.states[0]
	await physics_frame
	water.erase(Vector2i.ZERO)
	var added := {"count": 0}
	var count_nodes := func(_node): added.count += 1
	main.world.child_entered_tree.connect(count_nodes)
	for tick in 60: main.patrols.update(0.05)
	assert(added.count == 0, "Blocked water must not instantiate any trial vehicles.")
	main.world.child_entered_tree.disconnect(count_nodes)
	water[Vector2i.ZERO] = "water"
	main.patrols.update(0.25)
	assert(state.spawned == 1)
	assert(main.npc_sort_entries[0].sort_root.get_node("Visual").texture != null)
	var first: Area3D = state.actors[0].npc
	var identity := first.get_instance_id()
	await physics_frame
	# Start remains occupied: elapsed interval cannot spawn overlapping hulls.
	main.patrols.update(0.3)
	assert(state.spawned == 1)
	for frame in 160:
		main.patrols.update(0.05); main.npc_script_movement.update(0.05)
		await physics_frame
	assert(state.spawned == 2)
	assert(state.actors[0].done and first.position.x > 7.9)
	# The second vehicle waits behind the parked first vehicle.
	var following: Area3D = state.actors[1].npc
	var lead_hull: Rect2 = first.get_meta("hull_footprint")
	var following_hull: Rect2 = following.get_meta("hull_footprint")
	var hull_gap := first.position.x + lead_hull.position.x - following.position.x - following_hull.end.x
	assert(hull_gap >= 0.025, "A waiting ship must leave enough clearance for the lead hull to move away.")
	main.patrols.update(100)
	assert(state.spawned == 2)
	var second: Area3D = state.actors[1].npc
	var before := second.position
	var timer: float = state.timer
	main.in_battle = true
	main.patrols.update(100); main.npc_script_movement.update(100)
	assert(second.position == before and state.timer == timer)
	main.in_battle = false
	# Repeating uses the same actor and reverses the existing MOVE route.
	main.patrols._remove(second); state.actors.remove_at(1)
	state.config.repeat = true; state.actors[0].done = false
	main.patrols._arrived(state, state.actors[0])
	assert(state.actors[0].reverse)
	main.patrols.update(0.1)
	main.npc_script_movement.update(0.1)
	assert(first.position.x < 8 and first.get_instance_id() == identity)
	var mode: Dictionary = main.npc_script_movement.modes[identity]
	var cursor: int = mode.index
	main.npc_script_movement.cancel_moves()
	assert(main.npc_script_movement.modes[identity].type == "MOVE")
	main.npc_script_movement.clear()
	assert(main.npc_script_movement.modes[identity].index == cursor)
	main.patrols._remove(first); state.actors.clear()
	# Traffic cleanup removes runtime registries and resumes spawning.
	state.config.creation_interval = 10.0
	state.config.type = "traffic"; state.config.traffic_vehicle = {"type":"vehicle","sprite":"Tug"}; state.timer = 0
	main.patrols.update(0.1)
	assert(state.actors.size() == 1)
	var traffic: Area3D = state.actors[0].npc
	var traffic_key := traffic.get_instance_id()
	for frame in 60:
		main.patrols.update(0.05); main.npc_script_movement.update(0.05)
		await physics_frame
	assert(not is_instance_valid(traffic))
	assert(not main.npc_movement_states.has(traffic_key))
	assert(not main.npc_script_movement.modes.has(traffic_key))
	assert(state.actors.is_empty())
	await physics_frame
	state.timer = 0
	main.patrols.update(0.3)
	assert(state.actors.size() == 1)
	state.config.max_active_vehicles = 1
	var capped_actor: Area3D = state.actors[0].npc
	capped_actor.position.x += 6
	await physics_frame
	state.timer = 0
	var spawned: int = state.spawned
	main.patrols.update(3.0)
	assert(state.spawned == spawned, "Traffic must wait at the active ship cap even when the start is clear.")
	capped_actor.position.x -= 6
	await physics_frame
	# A route remains active with its start outside the camera viewport.
	main.camera = Camera3D.new(); main.world.add_child(main.camera)
	main.camera.projection = Camera3D.PROJECTION_ORTHOGONAL; main.camera.size = 4
	main.camera.position = Vector3(8,30,30); main.camera.look_at(Vector3(8,0,0))
	assert(not preload("res://world/terrain_camera_view.gd").ground_rect(main.camera).has_point(Vector2.ZERO))
	main.patrols.update(0.05)
	assert(state.active)
	var offscreen_actor: Area3D = state.actors[0].npc
	var offscreen_position := offscreen_actor.position
	main.npc_script_movement.update(0.05)
	assert(offscreen_actor.position != offscreen_position)
	main.camera.position += Vector3(1000,0,0)
	main.patrols.update(0.05)
	assert(not state.active)
	offscreen_position = offscreen_actor.position
	var paused_timer: float = state.timer
	main.patrols.update(100); main.npc_script_movement.update(100)
	assert(offscreen_actor.position == offscreen_position and state.timer == paused_timer)
	main.camera.position -= Vector3(1000,0,0)
	main.patrols.update(0.05); main.npc_script_movement.update(0.05)
	assert(state.active and offscreen_actor.position != offscreen_position)
	main.patrols._remove(state.actors[0].npc); state.actors.clear()
	main.world.free(); main.free()
	print("PATROL_TEST_PASSED")
	quit()
