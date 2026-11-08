extends SceneTree
class SaveWorld extends "res://world/main.gd":
	func _manual_save_path(_slot: int) -> String: return "res://.godot/yesno_starter_save.json"
	func _auto_save() -> bool: return false
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	create_timer(55).timeout.connect(func():push_error("YES_NO_STARTER_TIMEOUT");quit(2))
	call_deferred("test_choices")
func test_choices() -> void:
	var game: Node = load("res://world/main.tscn").instantiate()
	game.set_script(SaveWorld); root.add_child(game); await process_frame; game.set_physics_process(false)
	if game.startup_panel != null: game.startup_panel.hide()
	game._on_player_choice_selected(0)
	check(game.adventure_started and not game.battle.visible and game.party.is_empty() and not game.game_flags.has_flag("Starter"),"Appearance selection starts exploration without starter screen or party")
	check(not game.follower.visible,"No placeholder follower before starter selection")
	game._open_battle(0)
	check(not game.in_battle,"No battle crash before a starter is chosen")
	check(game._save_game(),"Can save pre-starter adventure")
	check(game._load_game() and game.party.is_empty() and not game.follower.visible and not game.game_flags.has_flag("Starter"),"Can load empty party before starter choice")
	var file := "tropical_research_lab.json"
	var map: Dictionary = game.map_data._map_files[file]
	game._set_route_location(game._location_for_map_file(file),game._array_to_vector3(map.origin)+game._array_to_vector3(map.entry),"Institute","")
	game.game_flags.set_flag("PlayerIsPicking",true)
	game._run_map_headers(game._current_location())
	var parrot: Area3D = game.runtime_npcs[file][2]
	var authored_source: String = map.script_source
	map.script_source = 'Block Choices:\nTextBoxYesNo "First?"\nIfYes MarkYes\nTextBoxYesNo "Second?"\nIfNo MarkNo\nEnd\nBlock MarkYes:\nSetFlag FirstYes\nReturn\nEnd\nBlock MarkNo:\nSetFlag SecondNo\nReturn\nEnd'
	game.run_map_block(file,"Choices")
	game.dialog_yes_button.grab_focus()
	var enter := InputEventKey.new(); enter.pressed = true; enter.keycode = KEY_ENTER
	game._input(enter)
	check(game.game_flags.has_flag("FirstYes") and game.dialog_choosing and game.script_runner.last_answer == -1,"Keyboard Yes branches and next question clears previous answer")
	game.dialog_no_button.pressed.emit()
	check(game.game_flags.has_flag("SecondNo") and not game.script_runner.running,"Second question uses its own No answer")
	map.script_source = authored_source
	check(game.run_map_block(file,"ParrotScript") and game.dialog_choosing,"Parrot interaction opens yes/no confirmation")
	check(game.dialog_choice_row.visible and not game.dialog_button.visible and game.dialog_no_button.has_focus(),"Question shows both choices with No initially focused")
	game._advance_dialogue()
	check(game.dialog_choosing and game.party.is_empty(),"Ordinary dialogue advance cannot dismiss question or grant starter")
	game.dialog_no_button.pressed.emit()
	check(game.party.is_empty() and not game.game_flags.has_flag("Starter") and not game.script_host.sprite_hidden(parrot),"No grants nothing and preserves NPC")
	game.script_runner.stop()
	game.run_map_block(file,"ParrotScript")
	var stale: Callable = game.dialogue_choice_action
	var escape := InputEventKey.new(); escape.pressed = true; escape.keycode = KEY_ESCAPE; game._input(escape)
	stale.call(true)
	check(not game.script_runner.running and not game.dialog_open and not game.dialog_choosing and game.party.is_empty(),"Escape cancels question and ignores stale Yes callback")
	game.run_map_block(file,"ParrotScript")
	game.dialog_yes_button.pressed.emit()
	check(game.party.size() == 1 and game.party[0].name == "Scorchick" and int(game.party[0].level) == 5,"Yes grants exactly one level-five Scorchick")
	check(game.game_flags.has_flag("Starter") and game.game_flags.has_flag("StarterFire") and game.script_host.sprite_hidden(parrot),"Yes sets persistent starter flags and hides chosen NPC")
	check(game.follower.visible,"Receiving first Fakemon initializes visible follower")
	game._advance_dialogue()
	check(not game.script_runner.running and not game.dialog_choosing,"Starter receipt finishes cleanly")
	check(game._save_game(),"Chosen starter can be saved")
	game.game_flags.restore({}); game.party.clear(); game.script_host.set_sprite_hidden(parrot,false)
	check(game._load_game() and game.party.size()==1 and game.game_flags.has_flag("Starter") and game.script_host.sprite_hidden(parrot),"Save/load restores starter, flag and header visibility")
	for block in ["StarterFire","AngelfishScript","OrchidScript"]:
		game.run_map_block(file,block)
		check(not game.dialog_choosing and game.party.size()==1,"Starter flag blocks another offer: "+block)
		game.script_runner.stop()
	for choice: Array in [["StarterWater","Sylvafin",1],["StarterGrass","Keklid",3]]:
		game.party.clear(); game.game_flags.restore({}); game.game_flags.set_flag("PlayerIsPicking",true)
		game._run_map_headers(game._current_location())
		check(game.run_map_block(file,str(choice[0])) and game.dialog_choosing,"Other starter prompt: "+str(choice[0]))
		game._answer_dialogue_choice(true)
		check(game.party.size()==1 and game.party[0].name == choice[1] and game.game_flags.has_flag("Starter") and game.script_host.sprite_hidden(game.runtime_npcs[file][choice[2]]),"Other starter choice uses same guarded flow: "+str(choice[1]))
		game._advance_dialogue()
	# Full-party service failure must not mark a choice or hide the NPC.
	game.game_flags.restore({}); game.game_flags.set_flag("PlayerIsPicking",true); game._run_map_headers(game._current_location())
	while game.party.size()<7: game.party.append(game.party[0].duplicate(true))
	game.run_map_block(file,"StarterFire"); game._answer_dialogue_choice(true)
	check(not game.game_flags.has_flag("Starter") and not game.script_host.sprite_hidden(parrot) and game.party.size()==7,"Rejected reward cannot set Starter or hide choice")
	# v1 saves always began with a selected Fakemon; migrate that implicit state.
	game._save_game()
	var save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.godot/yesno_starter_save.json")); save.version = 1; save.game_flags = {}
	var output := FileAccess.open("res://.godot/yesno_starter_save.json",FileAccess.WRITE); output.store_string(JSON.stringify(save)); output.close()
	check(game._load_game() and game.game_flags.has_flag("Starter"),"Legacy party save migrates starter-chosen state")
	game.queue_free(); await process_frame
	print("YES_NO_STARTER_TEST: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
