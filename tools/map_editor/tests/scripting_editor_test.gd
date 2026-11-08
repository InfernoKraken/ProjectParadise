extends SceneTree

const Document = preload("res://core/map_document.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _initialize() -> void:
	create_timer(15).timeout.connect(func():push_error("SCRIPTING_EDITOR_TEST_TIMEOUT");quit(2))
	call_deferred("test_editor")

func test_editor() -> void:
	var editor: Node = load("res://map_editor.tscn").instantiate()
	root.add_child(editor); await process_frame
	check(editor.activity_tabs.get_tab_count() == 4, "SCRIPT joins activity tabs")
	check(editor.script_panel.code is CodeEdit and editor.script_panel.code.gutters_draw_line_numbers, "Native CodeEdit with line numbers")
	var source := FileAccess.get_file_as_string(editor.project_root.path_join("tests/fixtures/research_institute.paradise"))
	var original_path: String = editor.document.path
	editor._load_path(editor.map_directory.path_join("tropical_research_lab.json"))
	# Isolate the legacy case from the user-authored map script data.
	for field in ["script_source", "script_interactions", "map_script_header", "map_script_headers"]: editor.document.data.erase(field)
	editor._refresh_script_panel()
	check(not editor.document.data.has("script_source"), "Legacy map has no script")
	check(editor.script_panel.parsed.valid, "Legacy map loads")
	editor._script_source_changed(source); editor._refresh_script_panel()
	check(editor.script_panel.parsed.valid, "Fixture opens and validates")
	var key := "npc:" + str(int(editor.document.data.npcs[0].id))
	editor._script_association_changed(key, "ProfessorIntroduction")
	var destination := ProjectSettings.globalize_path("res://.godot/script_persistence_test.json")
	check(editor.document.save_atomic(destination) == OK, "Existing atomic save stores script")
	var reloaded := Document.load_file(destination)
	check(reloaded.data.script_source == source and reloaded.data.script_interactions[key] == "ProfessorIntroduction", "Source and named association round-trip")
	DirAccess.remove_absolute(destination); DirAccess.remove_absolute(destination + ".bak")
	editor._script_association_changed(key, "Missing")
	check(range(editor.script_panel.diagnostics.item_count).any(func(index):return editor.script_panel.diagnostics.get_item_text(index).contains("Block does not exist")), "Association diagnostics")
	editor._script_association_changed(key, "ProfessorIntroduction")
	editor._set_activity(3)
	check(editor.canvas.script_read_only, "SCRIPT canvas is read-only")
	var npc: Dictionary = {}
	for object: Dictionary in editor.editor_objects:
		if object.field == "npcs": npc = object; break
	var before: String = editor.document.deterministic_json()
	editor.canvas.select_object(npc.id)
	check(editor.activity_tabs.current_tab == 3 and editor.script_panel.selected_key == key, "Selection stays in SCRIPT and exposes association")
	var point: Vector2 = editor.canvas.world_to_screen(Vector2(npc.position.x, npc.position.z))
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = point
	editor.canvas._gui_input(click)
	var motion := InputEventMouseMotion.new(); motion.button_mask = MOUSE_BUTTON_MASK_LEFT; motion.position = point + Vector2(80,80); motion.relative = Vector2(80,80)
	editor.canvas._gui_input(motion)
	check(before == editor.document.deterministic_json(), "Selecting/dragging in SCRIPT never mutates placement")
	editor._script_source_changed('Block Broken:\nSetFlg Foo\nEnd'); editor._refresh_script_panel()
	check(not editor.script_panel.parsed.valid and editor.script_panel.diagnostics.item_count > 0, "Malformed source displays diagnostics")
	editor._script_source_changed(source); editor._refresh_script_panel()
	var code: CodeEdit = editor.script_panel.code
	code.text = "Tex"; code.set_caret_column(3); editor.script_panel._complete()
	var options: Array = code.get_code_completion_options()
	check(options.any(func(option):return option.display_text == "TextBox"), "Native completion receives registry candidates")
	code.confirm_code_completion()
	check(code.text == "TextBox", "Native acceptance replaces only the command prefix")
	editor.script_panel.show_map.button_pressed = true
	code.text = "Block Professor:\nEnd\nBlock Test:\n Call Prof\nEnd"; code.set_caret_line(3); code.set_caret_column(10); code.text_changed.emit(); editor.script_panel.validate_source(); editor.script_panel._complete()
	check(code.get_code_completion_options().any(func(option):return option.display_text == "Professor"), "Native Block completion")
	editor._set_activity(0); check(not editor.canvas.script_read_only, "Placement mode restored")
	editor._load_path(original_path)
	editor.queue_free(); await process_frame
	print("SCRIPTING_EDITOR_TEST: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
