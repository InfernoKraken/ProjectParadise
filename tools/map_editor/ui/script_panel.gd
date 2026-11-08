extends VBoxContainer

signal source_changed(source: String)
signal association_changed(key: String, block: String)
signal alias_changed(key: String, alias_name: String)
var path_editor: VBoxContainer
var path_schema: Script
var aliases: Dictionary = {}
var alias_edit: LineEdit
var path_diagnostics: Array = []
var collision_segments: Dictionary = {}
var header_schema: Script
var parser: Script
var registry: Script
var code: CodeEdit
var diagnostics: ItemList
var association: LineEdit
var association_label: Label
var associations: Dictionary = {}
var references: Dictionary = {}
var selected_key := ""
var parsed: Dictionary = {"blocks":{}}
var map_source := ""
var fragment_start := 0
var fragment_end := 0
var fragment_line := 0
var displayed_block := ""
var show_map: CheckButton
var syncing := false
var malformed_fields: Array[String] = []
var map_header_data: Dictionary = {}

func configure(project_root: String) -> void:
	header_schema = load(project_root.path_join("world/scripting/map_header.gd"))
	parser = load(project_root.path_join("world/scripting/script_parser.gd"))
	registry = load(project_root.path_join("world/scripting/command_registry.gd"))
	path_schema = load(project_root.path_join("world/scripting/script_paths.gd"))
	name = "Script"
	var title := Label.new(); title.text = "SCRIPT · V2"; add_child(title)
	var pages := TabContainer.new(); pages.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(pages)
	var authoring := VBoxContainer.new(); authoring.name = "Source"; pages.add_child(authoring)
	association_label = Label.new(); association_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; authoring.add_child(association_label)
	association = LineEdit.new(); association.name = "OnInteractBlock"; association.placeholder_text = "OnInteract Block name (blank clears)"; authoring.add_child(association)
	alias_edit = LineEdit.new(); alias_edit.placeholder_text = "NPC script alias (e.g. Professor)"; alias_edit.name = "ScriptSpriteAlias"; authoring.add_child(alias_edit)
	alias_edit.text_submitted.connect(func(_text):_commit_alias()); alias_edit.focus_exited.connect(_commit_alias)
	association.text_submitted.connect(func(_value):_commit_association())
	association.focus_exited.connect(_commit_association)
	show_map = CheckButton.new(); show_map.text = "Show full map script"; authoring.add_child(show_map)
	show_map.toggled.connect(func(_enabled): _show_selected_source())
	code = CodeEdit.new(); code.name = "ScriptSource"; code.custom_minimum_size = Vector2(310, 300); code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.gutters_draw_line_numbers = true; code.code_completion_enabled = true; code.code_completion_prefixes = [" ", "\t"]
	code.add_comment_delimiter("//", "", true); code.add_string_delimiter('"', '"')
	var colors := CodeHighlighter.new()
	colors.number_color = Color("#f5c27a")
	colors.symbol_color = Color("#cad3f5")
	for command: String in registry.DEFINITIONS: colors.add_keyword_color(command, Color("#8bd5ee"))
	colors.add_keyword_color("Block", Color("#c6a0f6")); colors.add_keyword_color("End", Color("#c6a0f6"))
	colors.add_color_region('"', '"', Color("#a6da95")); colors.add_color_region("//", "", Color("#8087a2"), true)
	code.syntax_highlighter = colors; authoring.add_child(code)
	diagnostics = ItemList.new(); diagnostics.name = "ScriptDiagnostics"; diagnostics.custom_minimum_size.y = 160; add_child(diagnostics)
	path_editor = load("res://ui/script_path_panel.gd").new(); path_editor.name = "Paths"; path_editor.configure(registry); pages.add_child(path_editor)
	var reference := TextEdit.new(); reference.name = "Reference"; reference.editable = false; reference.text = FileAccess.get_file_as_string(project_root.path_join("docs/scripting_reference.md")); pages.add_child(reference)
	diagnostics.item_selected.connect(func(index):
		var line := maxi(0, int(diagnostics.get_item_metadata(index)) - 1)
		if not show_map.button_pressed and (line < fragment_line or line >= fragment_line + code.get_line_count()): show_map.button_pressed = true
		code.set_caret_line(maxi(0, line - (0 if show_map.button_pressed else fragment_line))); code.grab_focus())
	code.text_changed.connect(func():
		if syncing: return
		_commit_source(); code.request_code_completion(true))
	code.code_completion_requested.connect(_complete)

func set_map(data: Dictionary, pools: Dictionary) -> void:
	map_header_data = {}
	for field in ["map_script_header", "map_script_headers"]:
		if data.has(field): map_header_data[field] = data[field]
	references = pools
	var inspected: Dictionary = path_schema.inspect(data)
	path_diagnostics = inspected.diagnostics
	references.merge(path_schema.actor_references(data), true)
	references["move_path"] = inspected.move_path; references["follow_path"] = inspected.follow_path
	aliases = data.get("script_sprite_names", {}) if data.get("script_sprite_names", {}) is Dictionary else {}
	path_editor.set_paths(data.get("script_paths", []))
	malformed_fields.clear()
	var table: Variant = data.get("script_interactions", {})
	if not table is Dictionary: malformed_fields.append("script_interactions must be an object.")
	associations = table if table is Dictionary else {}
	var source: Variant = data.get("script_source", "")
	if not source is String: malformed_fields.append("script_source must be a string.")
	map_source = str(source)
	_show_selected_source()
	validate_source()

func select_association(key: String) -> void:
	selected_key = key; association.editable = not key.is_empty()
	association_label.text = "Interaction: " + key if not key.is_empty() else "Select an NPC or an object with an instance ID."
	association.text = str(associations.get(key, ""))
	_show_selected_source()
	alias_edit.editable = key.begins_with("npc:"); alias_edit.text = ""
	for alias_name: String in aliases:
		if str(aliases[alias_name]) == key.trim_prefix("npc:"): alias_edit.text = alias_name; break

# Keep storage map-local; entity view edits only the assigned Block's source range.
func _block_ranges(source: String) -> Array[Dictionary]:
	var ranges: Array[Dictionary] = []
	var offset := 0
	var line_number := 0
	for line: String in source.split("\n"):
		var lex: Dictionary = parser.tokenize(line)
		var tokens: Array = lex.tokens
		if tokens.size() >= 2 and tokens[0].value == "Block" and not tokens[0].quoted:
			var block_name := str(tokens[1].value).trim_suffix(":")
			if registry.identifier(block_name):
				if not ranges.is_empty(): ranges[-1].end = offset
				ranges.append({"name":block_name, "start":offset, "end":source.length(), "line":line_number})
		offset += line.length() + 1; line_number += 1
	return ranges

func _show_selected_source() -> void:
	displayed_block = str(associations.get(selected_key, ""))
	fragment_start = map_source.length(); fragment_end = fragment_start; fragment_line = 0
	var visible_source := ""
	if show_map.button_pressed:
		visible_source = map_source; fragment_start = 0; fragment_end = map_source.length()
	else:
		for span: Dictionary in _block_ranges(map_source):
			if span.name == displayed_block:
				fragment_start = span.start; fragment_end = span.end; fragment_line = span.line
				visible_source = map_source.substr(fragment_start, fragment_end - fragment_start); break
	code.editable = show_map.button_pressed or not selected_key.is_empty()
	code.placeholder_text = "Block NPC%sInteract:\n    TextBox \"Hello!\"\n    End" % selected_key.trim_prefix("npc:") if selected_key.begins_with("npc:") else "Write a Block to create this entity's interaction."
	if code.text != visible_source:
		syncing = true; code.text = visible_source; syncing = false

func _commit_source() -> void:
	var fragment := code.text
	if show_map.button_pressed:
		map_source = fragment; fragment_end = map_source.length()
	else:
		var prefix := map_source.left(fragment_start)
		if fragment_start == map_source.length() and not prefix.is_empty() and not prefix.ends_with("\n"):
			prefix += "\n"; fragment_start += 1
		var suffix := map_source.substr(fragment_end)
		if not suffix.is_empty() and not fragment.is_empty() and not fragment.ends_with("\n"): fragment += "\n"
		map_source = prefix + fragment + suffix
		fragment_end = fragment_start + fragment.length()
	source_changed.emit(map_source)
	validate_source()
	if not show_map.button_pressed and not selected_key.is_empty():
		var spans := _block_ranges(fragment)
		if not spans.is_empty() and spans[0].name != displayed_block:
			# Existing Blocks can be shared intentionally via the assignment field.
			var new_name: String = spans[0].name
			if _block_ranges(map_source).filter(func(span):return span.name == new_name).size() == 1:
				displayed_block = new_name
				association_changed.emit(selected_key, new_name)

func _commit_alias() -> void:
	if not alias_edit.editable: return
	var alias_name := alias_edit.text.strip_edges()
	if alias_name.is_empty() or registry.identifier(alias_name) and not alias_name in ["Player", "North", "South", "East", "West"]:
		alias_changed.emit(selected_key, alias_name)

func _commit_association() -> void:
	if not selected_key.is_empty() and association.text != str(associations.get(selected_key, "")):
		association_changed.emit(selected_key, association.text.strip_edges())

func validate_source() -> void:
	parsed = parser.parse(map_source, references)
	diagnostics.clear()
	for issue: Dictionary in parsed.diagnostics: _add_diagnostic(int(issue.line), String(issue.message), issue.severity == "warning")
	if not map_header_data.is_empty():
		var header_map := map_header_data.duplicate(); header_map.script_source = map_source
		for issue: Dictionary in header_schema.inspect(header_map, references).diagnostics: _add_diagnostic(0, str(issue.message))
	for message in malformed_fields: _add_diagnostic(0, message)
	for issue: Dictionary in path_diagnostics: _add_diagnostic(0, str(issue.message))
	for segment: String in collision_segments:
		var parts := segment.rsplit(":", true, 1); _add_diagnostic(0, "%s: Segment %d intersects known static collision." % [parts[0], int(parts[1]) + 1], true)
	for key: String in associations:
		if not associations[key] is String or not parsed.blocks.has(associations[key]): _add_diagnostic(0, "%s: OnInteract target Block does not exist." % key)
		if not key in references.get("interaction", []): _add_diagnostic(0, "%s: Interaction object does not exist." % key)
	if diagnostics.item_count == 0:
		var index := diagnostics.add_item("Valid · %d Blocks" % parsed.blocks.size()); diagnostics.set_item_metadata(index, 1); diagnostics.set_item_custom_fg_color(index, Color("#a6da95"))

func _add_diagnostic(line: int, message: String, warning := false) -> void:
	var index := diagnostics.add_item("%s · Line %d: %s" % ["Warning" if warning else "Error", line, message]); diagnostics.set_item_metadata(index, line); diagnostics.set_item_custom_fg_color(index, Color("#eed49f") if warning else Color("#ed8796"))

func _complete() -> void:
	var before := code.get_line(code.get_caret_line()).left(code.get_caret_column())
	if before.contains('"') or before.contains("//"): return
	for candidate: String in registry.completions(before, parsed.blocks, references): code.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, candidate, candidate)
	code.update_code_completion_options(true)
