extends SceneTree

const Paths = preload("res://world/scripting/script_paths.gd")
const Registry = preload("res://world/scripting/command_registry.gd")
const Parser = preload("res://world/scripting/script_parser.gd")
const Reference = preload("res://world/scripting/command_reference.gd")
const Motion = preload("res://world/npc_script_movement.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _initialize() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/script_tour.json"))
	map.npcs = [{"id":1}, {"id":3}]
	var inspection := Paths.inspect(map)
	check(inspection.diagnostics.is_empty() and inspection.paths.size() == 3, "Fixture paths valid")
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(map))
	check(encoded.script_paths == map.script_paths, "Ordered MOVE/FOLLOW nodes serialize")
	check(Paths.inspect({}).diagnostics.is_empty(), "Legacy maps without paths")
	check(not Paths.inspect({"script_paths":[{"name":"A", "type":"FOLLOW", "nodes":[[0,0],[0,0]]}]}).diagnostics.is_empty(), "FOLLOW needs distinct guidance nodes")
	check(not Paths.inspect({"script_paths":[{"name":"A", "type":"MOVE", "nodes":[[1e30,0]]}]}).diagnostics.is_empty(), "Engine-safe coordinate range")
	check(not Paths.inspect({"npcs":[{"id":1}], "script_sprite_names":{"NPC1":1}}).diagnostics.is_empty(), "Reserved alias rejected")
	check(not Paths.inspect({"npcs":[{"id":1}], "script_sprite_names":{"Professor":5}}).diagnostics.is_empty(), "Missing alias actor rejected")
	for invalid: Variant in [null, {}, [null], [{"name":"A", "type":"BAD", "nodes":[[0,0]]}], [{"name":"A", "type":"MOVE", "nodes":[]}], [{"name":"A", "type":"FOLLOW", "nodes":[[0,0]]}], [{"name":"A", "type":"MOVE", "nodes":[["bad",0]]}], [{"name":"A", "type":"MOVE", "nodes":[[INF,0]]}], [{"name":"A", "type":"MOVE", "nodes":[[0,0]]}, {"name":"A", "type":"MOVE", "nodes":[[1,1]]}]]:
		check(not Paths.inspect({"script_paths":invalid}).diagnostics.is_empty(), "Reject invalid path: " + str(invalid))
	var refs := Paths.actor_references(map); refs.move_path = inspection.move_path; refs.follow_path = inspection.follow_path
	check(Parser.parse(map.script_source, refs).valid, "Tour commands validate with typed pools")
	for pair in [["MoveSprite Professor InstituteTour", false], ["MoveSprite Missing ProfessorApproach", false], ["MoveSprite Professor Missing", false], ["FollowSprite Professor Missing InstituteTour", false], ["FollowSprite Professor Player ProfessorApproach", false], ["FaceSprite Professor Northeast", false], ["FaceSprite Professor NPC3", true]]:
		check(Parser.parse("Block A:\n" + pair[0] + "\nEnd", refs).valid == pair[1], "Typed reference validation: " + pair[0])
	for pair in [["Mov", "MoveSprite"], ["FollowSprite Professor ", "Player"], ["MoveSprite ", "Professor"], ["MoveSprite Professor Prof", "ProfessorApproach"], ["FollowSprite Professor Player Inst", "InstituteTour"], ["FaceSprite Professor N", "North"], ["StopFollowing ", "NPC3"]]:
		check(pair[1] in Registry.completions(pair[0], {}, refs), "Context completion: " + pair[0])
	for sample in ["FollowSprite Player Professor", "FollowSprite NPC3 Player", "FollowSprite Player Professor InstituteTour", "WaitMovement NPC3", "WaitMovement Player", "Wait 15", "Wait 0.25", "StopFollowing Player"]:
		check(Parser.parse("Block A:\n" + sample + "\nEnd", refs).valid, "New command syntax: " + sample)
	for sample in ["Wait -1", "Wait nope", "Wait 1e309", "MoveSprite Player ProfessorApproach"]:
		check(not Parser.parse("Block A:\n" + sample + "\nEnd", refs).valid, "Reject invalid wait/player command: " + sample)
	check("Player" in Registry.completions("FollowSprite ", {}, refs) and "NPC3" in Registry.completions("WaitMovement ", {}, refs), "Completion exposes player following and wait actors")
	var generated := Reference.render()
	check(generated == FileAccess.get_file_as_string("res://docs/scripting_reference.md"), "Reference is exact registry-generated output")
	check(Registry.HELP.size() == Registry.DEFINITIONS.size(), "No metadata-only command")
	for name: String in Registry.DEFINITIONS:
		check(Registry.HELP.has(name), "Command has metadata: " + name)
		var meta := Registry.metadata(name)
		check(meta.argument_names.size() == meta.argument_types.size() and not meta.description.is_empty() and not meta.category.is_empty(), "Complete signature metadata: " + name)
		check(generated.contains("### " + name + "\n") and generated.contains("Blocking: **" + ("Yes" if meta.blocking else "No") + "**"), "Command documented: " + name)
		check(Parser.parse("Block A:\n" + meta.example + ("" if name == "End" else "\nEnd") + "\nBlock Explanation:\nReturn\nEnd\nBlock Greeting:\nReturn\nEnd\nBlock Introduction:\nReturn\nEnd\nBlock ReceiveStarter:\nReturn\nEnd\nBlock DeclineStarter:\nReturn\nEnd").valid, "Example syntax: " + name)
	check(not Parser.parse("Block A:\nFollowSprite Player\nEnd",refs).valid, "Follow still requires actor and target")
	check(not Parser.parse("Block A:\nFollowSprite Player Professor Missing\nEnd",refs).valid, "Optional explicit Follow path remains validated")
	var owned_map := {"npcs":[{"id":1},{"id":2},{"id":3}], "script_sprite_names":{"Bird":2}, "script_interactions":{"npc:1":"Start"}, "script_source":'Block Start:\nCall Helper\nEnd\nBlock Helper:\nMoveSprite Bird Route\nIfFlag Ready Follow\nEnd\nBlock Follow:\nFollowSprite NPC3 Player Trail\nCall Start\nEnd\nBlock Unassigned:\nMoveSprite NPC1 Route\nEnd'}
	var owned := Paths.movement_actors(owned_map)
	check(owned.has(2) and owned.has(3) and not owned.has(1), "Assigned call/conditional graph owns moved actors, not trigger or unassigned Blocks")
	owned_map.script_interactions = {}
	check(Paths.movement_actors(owned_map).is_empty(), "Unassigned movement source leaves presets active")
	owned_map.script_interactions = {"npc:1":"TextOnly"}; owned_map.script_source = 'Block TextOnly:\nTextBox "Hello"\nFaceSprite NPC1 Player\nEnd'
	check(Paths.movement_actors(owned_map).is_empty(), "Text and facing scripts do not suppress idle presets")
	var header_schema := preload("res://world/scripting/map_header.gd")
	var header_map := {"map_script_header":{"flag":"Ready","true_block":"Yes","false_block":"No"}, "script_source":'Block Yes:\nShowSprite NPC2\nSetFlag Visible\nEnd\nBlock No:\nHideSprite NPC2\nClearFlag Visible\nEnd'}
	check(header_schema.inspect(header_map).valid, "Both immediate header outcomes validate")
	header_map.map_script_header.erase("false_block")
	check(not header_schema.inspect(header_map).valid, "Header requires false outcome")
	header_map.map_script_header.false_block = "Missing"
	check(not header_schema.inspect(header_map).valid, "Both header target references validated")
	header_map.map_script_header.false_block = "No"
	for command in ['TextBox "No"', "MoveSprite NPC2 Route", "FollowSprite NPC2 Player Route", "Warp rainforest 0 0", "FadeOut", "SaveGame", "GiveFakemon Sylvafin 5"]:
		header_map.script_source = 'Block Yes:\nCall Unsafe\nEnd\nBlock No:\nHideSprite NPC2\nEnd\nBlock Unsafe:\n' + command + '\nEnd'
		check(not header_schema.inspect(header_map).valid, "Reject indirect header command: " + command)
	header_map.script_source = 'Block Yes:\nCall Yes\nEnd\nBlock No:\nHideSprite NPC2\nEnd'
	check(not header_schema.inspect(header_map).valid, "Recursive header is rejected before side effects")
	var multi_headers := {"map_script_headers":[{"flag":"First","true_block":"Yes","false_block":"No"},{"flag":"Second","true_block":"No","false_block":"Yes"}], "script_source":'Block Yes:\nShowSprite NPC2\nShowSprite NPC3\nEnd\nBlock No:\nHideSprite NPC2\nHideSprite NPC3\nEnd'}
	check(header_schema.inspect(multi_headers).valid and header_schema.inspect(multi_headers).headers.size() == 2, "Multiple immediate map headers validate")
	for command in ["Wait 15", "WaitMovement NPC3", "FollowSprite Player NPC3 Route", 'TextBoxYesNo "Choose?"', "IfYes Yes", "IfNo No"]:
		multi_headers.script_source = "Block Yes:\n" + command + "\nEnd\nBlock No:\nEnd"
		check(not header_schema.inspect(multi_headers).valid, "Map header rejects blocking/guided command: " + command)
	var route: Array = [Vector3(0,0,0), Vector3(2,0,0), Vector3(2,0,4)]
	check(Motion.follow_destination(Vector3(1,0,0),Vector3(2,0,4),route) == Vector3(2,0,0), "Follow uses intervening bend")
	check(Motion.follow_destination(Vector3(2,0,0),Vector3(2,0,4),route) == Vector3(2,0,4), "Follow progresses past bend without sticking")
	check(Motion.follow_destination(Vector3(2,0,4),Vector3(0,0,0),route) == Vector3(2,0,0), "Follow reverses ordered corridor")
	check(Motion.follow_destination(Vector3.ZERO,Vector3(50,0,50),route) == Vector3.ZERO, "Unreachable target pauses without teleport")
	print("SCRIPTING_V2_TEST: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
