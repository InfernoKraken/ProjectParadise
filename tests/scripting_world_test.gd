extends SceneTree

class SaveWorld extends "res://world/main.gd":
	func _manual_save_path(_slot: int) -> String: return "res://.godot/header_save_test.json"
	func _auto_save() -> bool: return false

var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _initialize() -> void:
	create_timer(30).timeout.connect(func():push_error("SCRIPTING_WORLD_TEST_TIMEOUT");quit(2))
	call_deferred("test_world")

func test_world() -> void:
	var game: Node = load("res://world/main.tscn").instantiate()
	game.set_script(SaveWorld)
	root.add_child(game); await process_frame
	game._start_map_test("tropical_research_lab.json")
	var data: Dictionary = game.map_data._map_files["tropical_research_lab.json"]
	# Header fixtures own their source; isolate them from authored map headers.
	data.erase("map_script_header"); data.erase("map_script_headers")
	var parrot: Area3D = game.runtime_npcs["tropical_research_lab.json"][2]
	check(data.script_interactions.get("npc:2") == "ParrotScript", "Authored Scorchick interaction is bound")
	check(parrot.get_meta("script_movement_owned", false), "Assigned Move command suppresses Scorchick idle preset at load")
	var placed := parrot.position
	for step in 120: game._update_placed_npcs(0.1)
	check(parrot.position == placed, "Scripted NPC stays at authored start before interaction")
	game._interact_placed_npc(parrot)
	check(game.script_runner.running and game.active_dialogue == ["Squawk!"], "NPC script overrides companion interaction text despite unrelated draft path")
	game._advance_dialogue()
	check(game.npc_script_movement.controls(parrot) and game.script_runner.waiting, "Scripted movement overrides random idle preset")
	var bird_mode: Dictionary = game.npc_script_movement.modes[parrot.get_instance_id()]
	var map_origin: Vector3 = parrot.get_meta("map_origin")
	var authored_path: Dictionary = data.script_paths[0]
	for index in bird_mode.nodes.size():
		var point: Array = authored_path.nodes[index]
		check(bird_mode.nodes[index].is_equal_approx(Vector3(map_origin.x + point[0], parrot.position.y, map_origin.z + point[1])), "Actual Scorchick target matches saved map path at node %d" % index)
	game.script_runner.stop()
	game.npc_script_movement.clear()
	data.script_interactions.erase("npc:2")
	game._interact_placed_npc(parrot)
	check(game.dialog_open and game.active_dialogue == game.npc_dialogues[parrot.get_instance_id()].pages, "Blank association restores companion dialogue")
	game._advance_dialogue()
	data.script_source = FileAccess.get_file_as_string("res://tests/fixtures/research_institute.paradise")
	var id: int = game.runtime_npcs["tropical_research_lab.json"].keys()[0]
	data.script_interactions = {"npc:" + str(id):"ProfessorIntroduction"}
	check(game._try_script_npc(game.runtime_npcs["tropical_research_lab.json"][id]), "NPC starts associated Block")
	check(game.script_runner.waiting and game.dialog_open and game.script_input_locked, "Dialogue delegates and Lock applied")
	game._advance_dialogue(); game._advance_dialogue()
	check(game.game_flags.has_flag("MetProfessor") and game.active_dialogue[0].contains("Jalovea"), "Call reaches explanation after dialogue")
	game._advance_dialogue()
	check(not game.script_runner.running and not game.script_input_locked, "Return, Unlock and End complete")
	game.script_host.execute("Lock", [], func():pass); game.script_host.execute("Lock", [], func():pass)
	game.script_host.execute("Unlock", [], func():pass); game.script_host.execute("Unlock", [], func():pass)
	check(not game.script_input_locked, "Lock/Unlock idempotent")
	data.script_source = 'Block A:\nLock\nShowSpritePicture missing_fixture.png 0 0\nEnd'
	game.run_map_block("tropical_research_lab.json", "A")
	check(not game.script_runner.running and not game.script_input_locked, "Missing picture fails safely and unlocks")
	data.script_source = 'Block A:\nLock\nTextBox "cancel"\nEnd'
	game.run_map_block("tropical_research_lab.json", "A")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true; game._input(escape)
	check(not game.script_runner.running and not game.dialog_open and not game.script_input_locked, "Escape cancels dialogue safely")
	var header_location: String = game._current_location()
	var header_position: Vector3 = game.player.position
	var prior_source: String = data.script_source
	var prior_interactions: Dictionary = data.script_interactions.duplicate(true)
	var prior_definition: Dictionary = parrot.get_meta("npc_definition").duplicate(true)
	var foot: StaticBody3D = parrot.get_node("FootCollision")
	var layer := foot.collision_layer
	var mask := foot.collision_mask
	data.script_source = 'Block Present:\nShowSprite NPC2\nFaceSprite NPC2 East\nSetFlag HeaderRan\nEnd\nBlock Absent:\nHideSprite NPC2\nClearFlag HeaderRan\nEnd\nBlock Talk:\nTextBox "Visible professor"\nEnd'
	data.script_interactions = {"npc:2":"Talk"}
	data.map_script_header = {"flag":"StarterChosen", "true_block":"Present", "false_block":"Absent"}
	game._set_route_location(header_location, header_position, "Header fixture", "")
	check(game.script_host.sprite_hidden(parrot) and not game.script_runner.running and not game.dialog_open, "False/unset header executes immediately on entry")
	check(foot.collision_layer == 0 and foot.collision_mask == 0 and parrot.collision_layer == 0, "Hidden NPC has no body or interaction collision")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = foot.get_child(0).shape; query.transform = foot.get_child(0).global_transform; query.collision_mask = layer
	check(not parrot.get_world_3d().direct_space_state.intersect_shape(query).any(func(hit):return hit.collider == foot), "Physics queries cannot hit hidden NPC foot body")
	check(not game._try_script_npc(parrot), "Hidden NPC cannot directly activate its script")
	game._interact_placed_npc(parrot); check(not game.dialog_open, "Hidden NPC cannot use interaction dispatcher")
	game.script_host.map_file = "tropical_research_lab.json"
	game.script_host.execute("HideSprite", ["NPC2"], func():pass)
	check(foot.collision_layer == 0 and game.runtime_npcs["tropical_research_lab.json"][2] == parrot, "Repeated hide retains NPC registration")
	game._set_route_location("route", game.route_origin + Vector3(0,0.65,0), "Away", "")
	game.game_flags.set_flag("StarterChosen", true)
	game._set_route_location(header_location, header_position, "Return", "")
	check(not game.script_host.sprite_hidden(parrot) and game.game_flags.has_flag("HeaderRan") and parrot.get_meta("facing") == "right", "Re-entry evaluates true branch after flag change elsewhere")
	game.script_host.execute("ShowSprite", ["NPC2"], func():pass)
	check(foot.collision_layer == layer and foot.collision_mask == mask, "Repeated show restores authored body collision")
	await process_frame
	check(parrot.monitoring and parrot.monitorable, "Show restores interaction Area configuration")
	query.transform = foot.get_child(0).global_transform
	check(parrot.get_world_3d().direct_space_state.intersect_shape(query).any(func(hit):return hit.collider == foot), "Physics queries hit restored NPC foot body")
	game._interact_placed_npc(parrot); check(game.dialog_open, "Shown NPC interaction script is restored"); game._advance_dialogue()
	game.game_flags.set_flag("StarterChosen", false)
	game._set_route_location(header_location, header_position, "Again", "")
	check(game.script_host.sprite_hidden(parrot) and not game.game_flags.has_flag("HeaderRan"), "Same-map reload establishes false state after true state")
	check(game._save_game(), "Save hidden outcome with persistent flags")
	game.game_flags.set_flag("StarterChosen", true); game._run_map_headers(header_location)
	check(game._load_game(1) and game.script_host.sprite_hidden(parrot) and foot.collision_layer == 0, "Actual save/load re-evaluates false header and collision")
	game.game_flags.set_flag("StarterChosen", true); game._run_map_headers(header_location); check(game._save_game(), "Save visible outcome")
	game.script_host.execute("HideSprite", ["NPC2"], func():pass)
	check(game._load_game(1) and not game.script_host.sprite_hidden(parrot) and foot.collision_layer == layer, "Actual save/load re-evaluates true header and collision")
	parrot.set_meta("authored_hidden", true)
	game.script_host.reset_sprites()
	check(game.script_host.sprite_hidden(parrot), "Authored hidden default is restored before load/header overrides")
	game._run_map_headers(header_location)
	check(not game.script_host.sprite_hidden(parrot), "Map header ShowSprite activates authored-hidden NPC")
	check(game._save_game(), "Save flags with authored-hidden NPC shown by header")
	game.script_host.execute("HideSprite", ["NPC2"], func():pass)
	check(game._load_game(1) and not game.script_host.sprite_hidden(parrot), "Save load restores authored default then applies Show header")
	game.game_flags.set_flag("StarterChosen", false); game._run_map_headers(header_location)
	check(game._save_game(), "Save false outcome for authored-hidden NPC")
	game.script_host.execute("ShowSprite", ["NPC2"], func():pass)
	check(game._load_game(1) and game.script_host.sprite_hidden(parrot) and foot.collision_layer == 0, "Save load reapplies Hide header to authored-hidden NPC")
	parrot.set_meta("authored_hidden", false); game.game_flags.set_flag("StarterChosen", true); game._run_map_headers(header_location)
	DirAccess.remove_absolute("res://.godot/header_save_test.json")
	var safe_source: String = data.script_source
	data.script_source = safe_source.replace("HideSprite NPC2", 'TextBox "No header dialogue"')
	game.game_flags.set_flag("HeaderRan", false)
	game._run_map_headers(header_location)
	check(not game.dialog_open and not game.game_flags.has_flag("HeaderRan"), "Unsafe false branch rejects entire header before true branch side effects")
	data.script_source = safe_source
	check(parrot.get_meta("npc_definition") == prior_definition, "Show/hide never mutates original NPC definition")
	DirAccess.remove_absolute("res://.godot/header_save_test.json")
	data.script_source += "\nBlock HeaderLaterTrue:\nSetFlag HeaderLater\nEnd\nBlock HeaderLaterFalse:\nClearFlag HeaderLater\nEnd"
	data.map_script_headers = [{"flag":"HeaderRan","true_block":"HeaderLaterTrue","false_block":"HeaderLaterFalse"}]
	game.game_flags.set_flag("StarterChosen",true); game._run_map_headers(header_location)
	check(game.game_flags.has_flag("HeaderLater"), "Second map header sees first header flag changes")
	game.game_flags.set_flag("StarterChosen",false); game._set_route_location(header_location,header_position,"Again","")
	check(not game.game_flags.has_flag("HeaderLater"), "Multiple headers establish both outcomes on re-entry")
	check(game._save_game(), "Save multiple-header state")
	game.game_flags.set_flag("StarterChosen",true); game._run_map_headers(header_location)
	check(game._load_game(1) and not game.game_flags.has_flag("HeaderLater"), "Multiple headers rerun in order on save restoration")
	data.erase("map_script_headers"); DirAccess.remove_absolute("res://.godot/header_save_test.json")
	data.erase("map_script_header"); data.script_source = prior_source; data.script_interactions = prior_interactions
	data.script_source = "Block Timed:\nWait 0.05\nSetFlag WaitDone\nEnd"
	game.run_map_block("tropical_research_lab.json", "Timed")
	check(game.script_runner.waiting and not game.game_flags.has_flag("WaitDone"), "Wait pauses subsequent commands")
	await create_timer(0.08).timeout
	check(game.game_flags.has_flag("WaitDone") and not game.script_runner.running, "Wait resumes after requested seconds")
	game.game_flags.set_flag("WaitDone", false); game.run_map_block("tropical_research_lab.json", "Timed"); game.script_runner.stop()
	await create_timer(0.08).timeout
	check(not game.game_flags.has_flag("WaitDone"), "Cancelled Wait callback cannot resume script")
	data.script_paths.append({"name":"GuidePlayer", "type":"FOLLOW", "nodes":[[100,100],[104,100],[104,102]]})
	var guide: Area3D = game.runtime_npcs["tropical_research_lab.json"][3]
	var guide_original := guide.position
	var origin: Vector3 = guide.get_meta("map_origin")
	game.set_physics_process(false)
	guide.position = origin + Vector3(104,0,102); game.player.position = origin + Vector3(100,0.65,100)
	await physics_frame
	game.script_host.map_file = "tropical_research_lab.json"
	check(game.script_host.execute("FollowSprite", ["Player","NPC3","GuidePlayer"], func():pass).is_empty(), "Player accepts FollowSprite guide")
	var before_follow: Vector3 = game.player.position
	for tick in 6:
		await physics_frame
		game.npc_script_movement.update(1.0/60.0)
	check(game.player.position.x > before_follow.x and game.player.position.distance_to(guide.position) > 1.0, "Player follows corridor with normal physics and spacing")
	game._add_static_collision("PlayerGuideWall",origin + Vector3(101,0.65,100),Vector3(0.2,2,2))
	await physics_frame
	for tick in 90:
		await physics_frame
		game.npc_script_movement.update(1.0/60.0)
	check(game.player.position.x < origin.x + 100.9, "Guided Player obeys real body collision")
	game.world.get_node("PlayerGuideWall").queue_free()
	await physics_frame
	game.script_host.execute("StopFollowing", ["Player"], func():pass)
	check(not game.npc_script_movement.controls(game.player) and game.player.velocity == Vector3.ZERO, "StopFollowing Player restores manual control")
	guide.position = game.player.position+Vector3(2.5,0,0)
	check(game.script_host.execute("FollowSprite",["Player","NPC3"],func():pass).is_empty(), "Player accepts direct Follow without a path")
	for tick in 90:
		await physics_frame; game.npc_script_movement.update(1.0/60.0)
	var separation: float = game.player.position.distance_to(guide.position)
	check(separation >= 1.24 and separation <= 1.3, "Direct Player Follow catches guide and keeps close distance")
	guide.position += Vector3(0,0,1.5)
	for tick in 90:
		await physics_frame; game.npc_script_movement.update(1.0/60.0)
	separation = game.player.position.distance_to(guide.position)
	check(separation >= 1.24 and separation <= 1.3, "Direct Player Follow tracks guide after direction changes")
	game.script_host.execute("StopFollowing",["Player"],func():pass)
	game.script_host.execute("FollowSprite", ["Player","NPC3","GuidePlayer"], func():pass)
	game._input(escape)
	check(not game.npc_script_movement.controls(game.player), "Escape releases guided player control")
	guide.position = guide_original; game.player.position = header_position
	game.set_physics_process(true)
	data.script_paths.pop_back(); data.script_source = prior_source
	data.script_source = "Block FollowFailure:\nFollowSprite Player NPC3\nShowSpritePicture missing_fixture.png 0 0\nEnd"
	game.run_map_block("tropical_research_lab.json","FollowFailure")
	check(not game.script_runner.running and not game.npc_script_movement.controls(game.player), "Runtime script failure releases guided Player control")
	data.script_source = prior_source
	var species: String = game.battle.battle_data.fakemon[0].name
	var previous: int = game.party.size()
	check(game.script_host.execute("GiveFakemon", [species, 8], func():pass).is_empty() and game.party.size() == previous + 1 and game.party[-1].level == 8, "Existing party/Fakemon creation")
	game.game_flags.set_flag("SavedFlag", true)
	var path := "res://.godot/script_save_fixture.json"
	check(game._write_save(path, false, ""), "Existing save service accepts flags")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved.game_flags.SavedFlag == true and not saved.has("script_runner"), "Flags persisted without execution state")
	DirAccess.remove_absolute(path)
	game.script_host.map_file = "tropical_research_lab.json"
	check(game.script_host.execute("HideSprite", [str(id)], func():pass).is_empty(), "HideSprite finds map-local NPC")
	game._update_sort_canvas()
	check(game.script_host.sprite_hidden(game.runtime_npcs["tropical_research_lab.json"][id]), "NPC hidden state applied")
	game.script_host.execute("ShowSprite", [str(id)], func():pass)
	check(not game.script_host.sprite_hidden(game.runtime_npcs["tropical_research_lab.json"][id]), "ShowSprite restores")
	var entry: Dictionary = {}
	for candidate: Dictionary in game.object_sort_entries + game.tree_sort_entries + game.background_object_sort_entries:
		if not str(candidate.get("instance_id", "")).is_empty() and game._sort_entry_layer(candidate, candidate.placement) == game._active_visual_layer(): entry = candidate; break
	check(not entry.is_empty(), "Map has a registered instance visual")
	if not entry.is_empty():
		check(game.script_host.execute("HideObject", [entry.instance_id], func():pass).is_empty(), "HideObject delegates to registered visual")
		game._update_sort_canvas(); check(not entry.sort_root.visible, "HideObject survives sort update")
		game.script_host.execute("ShowObject", [entry.instance_id], func():pass); game._update_sort_canvas(); check(entry.sort_root.visible, "ShowObject restores visual")
	check(game.script_host.execute("ShowSpritePicture", ["indoor_aquarium_long.png", 10.0, 20.0], func():pass).is_empty() and game.script_host.pictures.size() == 1, "Picture uses existing PNG asset")
	game.script_host.execute("HideSpritePicture", ["indoor_aquarium_long.png"], func():pass); check(game.script_host.pictures.is_empty(), "HideSpritePicture removes UI art")
	game.adventure_started = false
	check(game.script_host.execute("SaveGame", [], func():pass).has("error"), "SaveGame surfaces service rejection without writing a slot")
	game.adventure_started = true
	data.script_source = 'Block A:\nFadeOut\nFadeIn\nSetFlag Faded\nEnd'
	game.run_map_block("tropical_research_lab.json", "A")
	await create_timer(0.7).timeout
	check(game.game_flags.has_flag("Faded") and not game.script_runner.running, "Fade sequential completion")
	data.script_source = 'Block A:\nWarp rainforest_clearing 2 3\nSetFlag Unreachable\nEnd'
	game.run_map_block("tropical_research_lab.json", "A")
	check(game._current_location() == "rainforest" and not game.script_runner.running and not game.game_flags.has_flag("Unreachable"), "Warp delegates and terminates at map boundary")
	game.queue_free(); await process_frame
	print("SCRIPTING_WORLD_TEST: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
