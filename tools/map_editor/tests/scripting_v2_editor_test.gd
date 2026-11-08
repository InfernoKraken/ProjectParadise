extends SceneTree

const Document = preload("res://core/map_document.gd")
const Collision = preload("res://core/script_path_collision.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _initialize() -> void:
	create_timer(20).timeout.connect(func():push_error("SCRIPT_V2_EDITOR_TIMEOUT");quit(2))
	call_deferred("test_editor")

func test_editor() -> void:
	var editor: Node = load("res://map_editor.tscn").instantiate(); root.add_child(editor); await process_frame
	editor._load_path(editor.map_directory.path_join("tropical_research_lab.json"))
	# These tests create their own header source without touching the authored file.
	editor.document.data.erase("map_script_header"); editor.document.data.erase("map_script_headers")
	# Entity-edit tests need an unassigned fish and dialogue in the selected Block.
	# Keep that fixture independent of the Institute's new starter interactions.
	editor.document.data.script_source = 'Block ParrotScript:\nTextBox "Squawk!"\nMoveSprite NPC2 ParrotMove\nEnd'
	editor.document.data.script_interactions = {"npc:2":"ParrotScript"}
	editor._refresh_all(); editor._set_activity(3)
	check("TextBoxYesNo" in editor.script_panel.registry.completions("TextBoxY",{},{}), "Editor exposes yes/no dialogue completion")
	check("ParrotScript" in editor.script_panel.registry.completions("IfYes ",editor.script_panel.parsed.blocks,{}), "Editor completes yes/no Block references")
	var parrot: Dictionary = {}
	for object: Dictionary in editor.editor_objects:
		if object.field == "npcs" and int(object.npc_id) == 2: parrot = object; break
	editor.canvas.select_object(str(parrot.id))
	var block_field: LineEdit = editor.inspector.get_node("NpcOnInteractBlock")
	check(block_field.text == "ParrotScript" and editor.script_panel.association.text == "ParrotScript", "Inspector and Script share NPC interaction assignment")
	check(not editor.inspector.get_node("NpcInteractionText").editable, "Script interaction disables fallback text editing")
	block_field.text = ""; block_field.text_submitted.emit("")
	check(not editor.document.data.script_interactions.has("npc:2") and editor.script_panel.association.text.is_empty() and editor.inspector.get_node("NpcInteractionText").editable, "Clearing Inspector assignment restores text fallback and syncs Script")
	editor._script_association_changed("npc:2", "ParrotScript")
	check(editor.inspector.get_node("NpcOnInteractBlock").text == "ParrotScript", "Script assignment refreshes Inspector")
	check(not editor.canvas._show_editor_geometry() and editor.canvas._ground_projection().is_equal_approx(Vector2(1, sqrt(0.5))), "Script hides decorations and matches gameplay ground projection")
	check(is_equal_approx(editor.canvas.script_preview_elevation, 3.5), "Flying preview includes mode height plus authored offset")
	var camera := Camera3D.new(); root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 24
	camera.position = Vector3(0,18,18); camera.rotation_degrees = Vector3(-45,0,0)
	var origin_screen := camera.unproject_position(Vector3.ZERO)
	var camera_scale := camera.unproject_position(Vector3.RIGHT).x - origin_screen.x
	var canvas_scale: float = editor.canvas.pixels_per_unit * editor.canvas.zoom
	for height in [0.0, 3.5, -0.7]:
		editor.canvas.script_preview_elevation = height
		for type in ["MOVE", "FOLLOW"]:
			var ground := Vector2(-2,4)
			var expected := (camera.unproject_position(Vector3(ground.x,height,ground.y)) - origin_screen) / camera_scale
			var actual: Vector2 = (editor.canvas._script_node_screen(ground, "ProjectionFixture") - editor.canvas.world_to_screen(Vector2.ZERO)) / canvas_scale
			check(actual.is_equal_approx(expected), type + " preview matches actual Camera3D for ground/flying/swimming")
			check(editor.canvas._script_point(editor.canvas._script_node_screen(ground, "ProjectionFixture"), "ProjectionFixture").is_equal_approx(ground), type + " inverse picking preserves ground coordinates")
	camera.queue_free(); editor._select_script_association()
	var anchor: Vector2 = editor.canvas._object_anchor_screen(parrot)
	check(anchor.is_equal_approx(editor.canvas._script_node_screen(Vector2(parrot.position.x, parrot.position.z))), "NPC art anchor matches trail at identical X/Z")
	check(editor.canvas._hit_test(editor.canvas._screen_rect(parrot).get_center()).get("id", "") == parrot.id, "Elevated NPC selection follows visible artwork")
	var zoom_node := Vector2(-2, 4)
	var before_zoom: Vector2 = editor.canvas._script_node_screen(zoom_node)
	editor.canvas._zoom_at(before_zoom, 1.15)
	check(editor.canvas._script_node_screen(zoom_node).is_equal_approx(before_zoom), "Zoom keeps elevated path node under cursor with compressed ground projection")
	var saved_source: String = editor.document.data.script_source
	var saved_associations: Dictionary = editor.document.data.script_interactions.duplicate(true)
	var fish: Dictionary = {}
	for object: Dictionary in editor.editor_objects:
		if object.field == "npcs" and int(object.npc_id) == 1: fish = object; break
	editor.canvas.select_object(str(fish.id))
	check(editor.script_panel.code.text.is_empty(), "Unassigned NPC shows blank source instead of previous NPC script")
	editor.script_panel.code.text = 'Block FishInteract:\n    TextBox "Splash!"\n    End\n'
	editor.script_panel.code.text_changed.emit()
	check(editor.document.data.script_interactions.get("npc:1") == "FishInteract", "Writing entity Block automatically assigns interaction")
	check(editor.document.data.script_source.contains('TextBox "Squawk!"') and editor.document.data.script_source.contains('TextBox "Splash!"'), "New entity script preserves other entity source")
	editor.canvas.select_object(str(parrot.id))
	check(editor.script_panel.code.text.contains("ParrotScript") and not editor.script_panel.code.text.contains("FishInteract"), "Switching back restores only selected NPC Block")
	editor.script_panel.code.text = editor.script_panel.code.text.replace("Squawk!", "Squawk again!")
	editor.script_panel.code.text_changed.emit()
	check(editor.document.data.script_source.contains("Splash!") and editor.document.data.script_source.contains("Squawk again!"), "Editing selected entity preserves another Block")
	editor.canvas.select_object(str(fish.id))
	check(editor.script_panel.code.text.contains("Splash!") and not editor.script_panel.code.text.contains("Squawk"), "Second NPC restores its own script")
	editor.script_panel.show_map.button_pressed = true
	check(editor.script_panel.code.text.contains("FishInteract") and editor.script_panel.code.text.contains("ParrotScript"), "Explicit full-map view exposes shared source")
	editor.script_panel.show_map.button_pressed = false
	editor.document.data.script_source = saved_source; editor.document.data.script_interactions = saved_associations
	editor.canvas.select_object(str(parrot.id)); editor._refresh_script_panel()
	var authored_node := Vector2(-6, -5)
	var bird_preview: Vector2 = editor.canvas._script_node_screen(authored_node, "ParrotMove")
	editor.canvas.select_object(str(fish.id))
	check(editor.canvas._script_node_screen(authored_node, "ParrotMove").is_equal_approx(bird_preview), "Selecting another NPC preserves command actor trail height")
	editor.canvas.select_object("")
	check(editor.canvas._script_node_screen(authored_node, "ParrotMove").is_equal_approx(bird_preview), "Clearing selection cannot lower flying path to ground")
	check(editor.canvas._script_point(bird_preview, "ParrotMove").is_equal_approx(authored_node), "Bound route picking uses command actor height without selection")
	editor.canvas.select_object(str(parrot.id))
	# Keep path CRUD assertions independent of the user's authored paths.
	editor.document.data.script_paths = []; editor._refresh_script_panel()
	var original_objects: Array = editor.document.data.objects.duplicate(true)
	var npc_id: int = int(editor.document.data.npcs[0].id)
	editor._script_alias_changed("npc:" + str(npc_id), "Professor")
	check("Professor" in editor.script_panel.references.sprite, "Editor alias enters sprite completion pool")
	var panel: VBoxContainer = editor.script_panel.path_editor
	panel.name_edit.text = "Approach"; panel.create_path("MOVE")
	check(editor.document.data.script_paths[0].nodes.is_empty() and not editor.script_panel.path_diagnostics.is_empty(), "Empty created path gets diagnostic")
	panel.add_node(Vector2(0,0)); panel.add_node(Vector2(2,0))
	panel.selected_node = 0; panel.insert_node()
	check(editor.document.data.script_paths[0].nodes == [[0.0,0.0],[1.0,0.0],[2.0,0.0]], "Insert midpoint keeps ordering")
	panel.edit_node("Approach",1,Vector2(1,1))
	check(editor.document.data.script_paths[0].nodes[1] == [1.0,1.0], "Move node through editor")
	editor._undo(); check(editor.document.data.script_paths[0].nodes[1] == [1.0,0.0], "Path edit map undo")
	editor._redo(); check(editor.document.data.script_paths[0].nodes[1] == [1.0,1.0], "Path edit map redo")
	panel.selected_name = "Approach"; panel.selected_node = 1; panel.delete_node()
	check(editor.document.data.script_paths[0].nodes.size() == 2, "Delete node")
	panel.name_edit.text = "Tour"; panel.create_path("FOLLOW"); panel.add_node(Vector2(0,2)); panel.add_node(Vector2(2,2))
	check(editor.canvas.script_paths.size() == 2 and editor.canvas.script_paths[0].type == "MOVE" and editor.canvas.script_paths[1].type == "FOLLOW", "Canvas exposes distinct path types")
	check(editor.document.data.objects == original_objects, "Paths never enter object placements")
	check("Approach" in editor.script_panel.references.move_path and not "Tour" in editor.script_panel.references.move_path and "Tour" in editor.script_panel.references.follow_path, "Typed path completion pools")
	var file := ProjectSettings.globalize_path("res://.godot/script_v2_map.json")
	check(editor.document.save_atomic(file) == OK, "Atomic map save with paths")
	var loaded := Document.load_file(file)
	check(loaded.data.script_paths == editor.document.data.script_paths and loaded.data.script_sprite_names.Professor == npc_id, "Save/load preserves MOVE/FOLLOW paths and alias")
	DirAccess.remove_absolute(file); DirAccess.remove_absolute(file + ".bak")
	editor._script_source_changed("Block A:\nMoveSprite Professor Approach\nEnd"); editor._refresh_script_panel()
	check(editor.script_panel.parsed.valid, "Move source validates against editor resources")
	panel.selected_name = "Approach"; panel.refresh(); panel.name_edit.text = "Renamed"; panel.rename_path()
	check(not editor.script_panel.parsed.valid and editor.document.data.script_source.contains("Approach"), "Rename leaves source intact and detects stale reference")
	editor._script_source_changed("Block A:\nMoveSprite Professor Renamed\nEnd"); editor._refresh_script_panel()
	panel.selected_name = "Renamed"; panel.refresh(); panel.delete_path()
	check(not editor.script_panel.parsed.valid, "Deleting referenced path gives error")
	var invalid := Collision.segments({"Blocked":{"type":"MOVE", "nodes":[[-2,0],[2,0]]}}, [{"field":"asset_collision","position":Vector3.ZERO,"size":Vector3(1,1,1)}])
	check(invalid.has("Blocked:0"), "Known static collision segment warning")
	invalid = Collision.segments({"Blocked":{"type":"FOLLOW", "nodes":[[-2,0],[2,0]]}}, [{"shape":"wall","collision":[{"from":[0,-1],"to":[0,1],"thickness":0.22}]}])
	check(invalid.has("Blocked:0"), "Existing baked wall strips used for path warning")
	panel.selected_name = "Tour"; panel.refresh()
	editor.canvas.script_path_add_mode = true
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = editor.canvas._script_node_screen(Vector2(3,2)); editor.canvas._gui_input(click)
	check(editor.document.data.script_paths[0].nodes.size() == 3, "Canvas click appends script node")
	editor.canvas.script_path_add_mode = false
	click.position = editor.canvas._script_node_screen(Vector2(3,2)); editor.canvas._gui_input(click)
	var motion := InputEventMouseMotion.new(); motion.position = editor.canvas._script_node_screen(Vector2(4,2)); motion.button_mask = MOUSE_BUTTON_MASK_LEFT; editor.canvas._gui_input(motion)
	click.pressed = false; click.position = motion.position; editor.canvas._gui_input(click)
	check(editor.document.data.script_paths[0].nodes[-1] == [4.0,2.0], "Dragging path handle updates only path data")
	editor._set_activity(0)
	check(not editor.canvas.script_read_only and editor.canvas._show_editor_geometry() and editor.document.data.objects == original_objects, "Leaving SCRIPT hides path drawing and restores placement")
	var header_source := 'Block Present:\nShowSprite NPC2\nFaceSprite NPC2 East\nEnd\nBlock Absent:\nHideSprite NPC2\nEnd'
	editor._script_source_changed(header_source); editor._refresh_script_panel(); editor._set_activity(2)
	check(editor.map_header_code is CodeEdit and editor.map_header_code.text == header_source, "Map tab exposes shared Map Script source")
	editor._set_map_header({"flag":"StarterChosen", "true_block":"Present", "false_block":"Absent"})
	check(editor._header_issues().is_empty(), "Editor accepts both immediate header outcomes")
	var filename := ProjectSettings.globalize_path("res://.godot/header_editor_map.json")
	check(editor.document.save_atomic(filename) == OK, "Header persists through existing atomic JSON save")
	var round_trip := Document.load_file(filename)
	check(round_trip.data.map_script_header == editor.document.data.map_script_header and round_trip.data.script_source == header_source, "Header and Blocks round-trip unchanged")
	DirAccess.remove_absolute(filename); DirAccess.remove_absolute(filename + ".bak")
	editor._set_map_header({"flag":"StarterChosen", "true_block":"Present", "false_block":"Missing"})
	check(not editor._header_issues().is_empty(), "Editor rejects missing false branch")
	editor._save_to(filename)
	check(not FileAccess.file_exists(filename), "Invalid header blocks normal editor save before replacing output")
	editor._undo(); check(editor._header_issues().is_empty(), "Header assignment is undoable")
	editor._script_source_changed(header_source.replace("ShowSprite NPC2", 'TextBox "Forbidden"')); editor._refresh_script_panel()
	check(not editor._header_issues().is_empty(), "Editor rejects dialogue in header")
	editor._script_source_changed(header_source); editor._refresh_script_panel()
	check(editor.editor_objects.any(func(object):return object.get("npc_id", -1) == 2), "Runtime Hide header never removes selectable editor NPC")
	editor._set_map_header({}, false)
	check(not editor.document.data.has("map_script_header"), "Disabling header removes optional field")
	editor.canvas.select_object(str(parrot.id)); editor._set_activity(1)
	var original_definition: Dictionary = editor.npc_data.definitions["2"].duplicate(true)
	var hidden_field: CheckBox = editor.inspector.get_node("NpcHidden")
	check(not hidden_field.button_pressed, "Legacy NPC Hidden checkbox defaults false")
	hidden_field.button_pressed = true
	check(editor.npc_data.definitions["2"].hidden and editor.canvas.objects.any(func(object):return object.get("npc_id", -1) == 2), "Hidden persists in definition while NPC stays selectable in editor")
	editor._undo(); check(not editor.npc_data.definitions["2"].get("hidden", false), "Hidden checkbox supports undo")
	editor._redo(); check(editor.npc_data.definitions["2"].hidden, "Hidden checkbox supports redo")
	var hidden_file := ProjectSettings.globalize_path("res://.godot/hidden_npc_editor.json")
	check(editor._save_npc_pair(hidden_file, []) == OK, "Hidden saves through existing map/NPC companion pair")
	var npc_reload: RefCounted = editor.npc_data.get_script().new(); npc_reload.load_for_map(hidden_file)
	check(npc_reload.definitions["2"].hidden and npc_reload.definitions["2"].sprite == original_definition.sprite, "Companion reload preserves hidden and other definition fields")
	DirAccess.remove_absolute(hidden_file); DirAccess.remove_absolute(hidden_file + ".bak")
	DirAccess.remove_absolute(editor.npc_data.companion_path(hidden_file)); DirAccess.remove_absolute(editor.npc_data.companion_path(hidden_file) + ".bak")
	editor.npc_data.definitions["2"].hidden = "yes"
	check(editor.npc_data.issues(editor.document.data, editor.npc_visuals).any(func(issue):return str(issue.message).contains("hidden must be a boolean")), "Hidden rejects malformed nonboolean values")
	editor.npc_data.definitions["2"] = original_definition
	editor._add_map_script(); await process_frame
	check(editor.document.data.map_script_headers.size() == 1 and editor._header_issues().is_empty(), "Plus adds a valid map script with both Blocks")
	editor._add_map_script(); await process_frame
	check(editor.document.data.map_script_headers.size() == 2, "Plus supports multiple map entry scripts")
	var outcome_code: CodeEdit = editor.metadata_box.get_node("MapScript0/HeaderOutcome_0_true_block")
	check(outcome_code.code_completion_enabled and outcome_code.gutters_draw_line_numbers, "Map outcome editors have native multiline completion")
	outcome_code.text = "ShowSprite NPC1\nShowSprite NPC2"; outcome_code.text_changed.emit()
	check(editor.document.data.script_source.contains("ShowSprite NPC1") and editor.document.data.script_source.contains("ShowSprite NPC2") and editor._header_issues().is_empty(), "One header outcome can update multiple sprites")
	var legacy := {"flag":"PlayerIsPicking", "true_block":"HideSprite Professor", "false_block":"ShowSprite Professor"}
	editor._set_map_header(legacy)
	check(editor._header_issues().any(func(issue):return str(issue.message).contains("Block name, not a command")), "Screenshot mistake gets actionable diagnostic")
	editor.script_edit_checkpoint = false; editor._edit_header_body(editor.document.data.map_script_header, "true_block", "HideSprite Professor")
	editor.script_edit_checkpoint = false; editor._edit_header_body(editor.document.data.map_script_header, "false_block", "ShowSprite Professor")
	check(editor._header_issues().is_empty() and editor.script_panel.registry.identifier(editor.document.data.map_script_header.true_block), "Multiline editor repairs command-in-Block-field mistake")
	check(editor.script_panel.code.syntax_highlighter.number_color.get_luminance() > 0.4, "Script numbers use visible highlighter color")
	editor.queue_free(); await process_frame
	print("SCRIPTING_V2_EDITOR_TEST: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
