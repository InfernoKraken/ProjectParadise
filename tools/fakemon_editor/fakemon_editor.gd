extends Control

const Model := preload("res://fakemon_editor_model.gd")
const ArtTab := preload("res://art_tab.gd")
const EvolutionPreview:=preload("res://evolution_visual_preview.gd")
const STAT_LABELS := {"max_hp":"HP", "attack":"Attack", "defense":"Defense", "special_attack":"Sp. Attack", "special_defense":"Sp. Defense", "speed":"Speed"}

var model := Model.new()
var browser: ItemList
var search: LineEdit
var title: Label
var dirty_label: Label
var status: RichTextLabel
var tabs: TabContainer
var fields: Dictionary = {}
var stat_spins: Dictionary = {}
var bst_label: Label
var egg_boxes: Array[OptionButton] = []
var type_boxes: Array[OptionButton] = []
var move_rows: VBoxContainer
var starting_moves: LineEdit
var moveset_source_box: OptionButton
var art_tab: FakemonArtTab
var evolution_box: OptionButton
var evolution_search: LineEdit
var evolution_level: SpinBox
var evolution_from_label: Label
var found_list: VBoxContainer
var evolution_preview:EvolutionVisualPreview
var suppress := false
var quit_dialog: ConfirmationDialog
var color_picker: ColorPickerButton

func _ready() -> void:
	_build_ui()
	if not model.load_all(): _message(model.error, true); return
	_refresh_browser()
	if not model.species_names().is_empty(): _select(model.species_names()[0])

func _build_ui() -> void:
	var background := ColorRect.new(); background.color = Color("10151f"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var root := VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14); root.add_theme_constant_override("separation", 10); add_child(root)
	var header := HBoxContainer.new(); root.add_child(header)
	var app_title := Label.new(); app_title.text = "FAKEMON EDITOR"; app_title.add_theme_font_size_override("font_size", 24); app_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(app_title)
	dirty_label = Label.new(); header.add_child(dirty_label)
	var save := Button.new(); save.text = "Save Fakemon"; save.pressed.connect(_save); header.add_child(save)
	var body := HSplitContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.split_offset = 300; root.add_child(body)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 270; body.add_child(left)
	search = LineEdit.new(); search.placeholder_text = "Search Fakemon…"; search.text_changed.connect(func(_v): _refresh_browser()); left.add_child(search)
	browser = ItemList.new(); browser.size_flags_vertical = Control.SIZE_EXPAND_FILL; browser.item_selected.connect(func(i): _attempt_select(browser.get_item_text(i))); left.add_child(browser)
	var browser_buttons := HBoxContainer.new(); left.add_child(browser_buttons)
	var add := Button.new(); add.text = "+ Add"; add.pressed.connect(_show_add_dialog); browser_buttons.add_child(add)
	var remove := Button.new(); remove.text = "Remove"; remove.pressed.connect(_confirm_remove); browser_buttons.add_child(remove)
	var right := VBoxContainer.new(); body.add_child(right)
	title = Label.new(); title.add_theme_font_size_override("font_size", 22); right.add_child(title)
	tabs = TabContainer.new(); tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL; right.add_child(tabs)
	_build_general_tab(); _build_stats_tab(); _build_art_tab(); _build_moves_tab(); _build_evolution_tab(); _build_found_tab()
	status = RichTextLabel.new(); status.fit_content = true; status.custom_minimum_size.y = 58; status.bbcode_enabled = true; root.add_child(status)
	quit_dialog=ConfirmationDialog.new();quit_dialog.dialog_text="Unsaved Fakemon or staged Art Package changes remain. Close and discard them?";quit_dialog.confirmed.connect(func():get_tree().quit());add_child(quit_dialog)

func _notification(what:int)->void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if model.is_dirty() or model.encounters_dirty() or (art_tab!=null and art_tab.has_unsaved()):quit_dialog.popup_centered()
		else:get_tree().quit()

func _tab(name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new(); scroll.name = name; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; tabs.add_child(scroll)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation", 8); scroll.add_child(box); return box

func _row(parent: Control, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new(); parent.add_child(row)
	var label := Label.new(); label.text = label_text; label.custom_minimum_size.x = 160; row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(control)

func _line(parent: Control, key: String, label_text: String, multiline := false) -> Control:
	var control: Control = TextEdit.new() if multiline else LineEdit.new()
	if multiline:
		control.custom_minimum_size.y = 150
		control.text_changed.connect(func(): _field_changed(key, control))
	else:
		control.text_changed.connect(func(_text: String): _field_changed(key, control))
	fields[key] = control; _row(parent, label_text, control); return control

func _build_general_tab() -> void:
	var box := _tab("General")
	_line(box, "name", "Name / runtime ID")
	_line(box, "art_id", "Art ID")
	_line(box, "description", "Dex description", true)
	_line(box, "size", "Size")
	var color_row := HBoxContainer.new(); box.add_child(color_row); var color_label := Label.new(); color_label.text = "Display color (hex)"; color_label.custom_minimum_size.x = 160; color_row.add_child(color_label)
	var color_input := LineEdit.new(); color_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; color_input.text_changed.connect(func(_text): _field_changed("color", color_input); _sync_color_picker()); fields["color"] = color_input; color_row.add_child(color_input)
	color_picker = ColorPickerButton.new(); color_picker.text = "Sample"; color_picker.edit_alpha = false; color_picker.custom_minimum_size.x = 90; color_picker.color_changed.connect(_sample_display_color); color_row.add_child(color_picker)
	for spec in [["level","Species level default"],["catch_rate","Catch rate"],["base_exp","Base experience"],["male_ratio","Male ratio (blank = genderless)"]]:
		var input := LineEdit.new(); input.text_changed.connect(_number_text_changed.bind(spec[0], input)); fields[spec[0]] = input; _row(box, spec[1], input)
	var types_row := HBoxContainer.new(); box.add_child(types_row); var types_label := Label.new(); types_label.text = "Types"; types_label.custom_minimum_size.x = 160; types_row.add_child(types_label)
	for i in 2:
		var option := OptionButton.new(); option.size_flags_horizontal = Control.SIZE_EXPAND_FILL; option.item_selected.connect(_types_changed); type_boxes.append(option); types_row.add_child(option)
	var eggs_row := HBoxContainer.new(); box.add_child(eggs_row); var eggs_label := Label.new(); eggs_label.text = "Egg groups"; eggs_label.custom_minimum_size.x = 160; eggs_row.add_child(eggs_label)
	for i in 2:
		var option := OptionButton.new(); option.size_flags_horizontal = Control.SIZE_EXPAND_FILL; option.item_selected.connect(_eggs_changed); egg_boxes.append(option); eggs_row.add_child(option)
	_line(box, "flowerType", "Flower type (optional)")

func _build_stats_tab() -> void:
	var box := _tab("Stats")
	var heading := HBoxContainer.new(); box.add_child(heading); var label := Label.new(); label.text = "Base Stats"; label.add_theme_font_size_override("font_size", 20); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; heading.add_child(label)
	bst_label = Label.new(); bst_label.add_theme_font_size_override("font_size", 22); heading.add_child(bst_label)
	for key in STAT_LABELS:
		var spin := SpinBox.new(); spin.min_value = 1; spin.max_value = 999; spin.step = 1; spin.value_changed.connect(_stat_changed.bind(key)); stat_spins[key] = spin; _row(box, STAT_LABELS[key], spin)

func _build_art_tab() -> void:
	var scroll:=ScrollContainer.new();scroll.name="Art";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;tabs.add_child(scroll)
	art_tab=ArtTab.new();art_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL;art_tab.setup(model.game_root);art_tab.changed.connect(_art_changed);art_tab.message.connect(_message);scroll.add_child(art_tab)

func _build_moves_tab() -> void:
	var box := _tab("Moves")
	moveset_source_box = OptionButton.new(); moveset_source_box.item_selected.connect(_moveset_source_changed); _row(box, "Shared moveset source", moveset_source_box)
	starting_moves = LineEdit.new(); starting_moves.placeholder_text = "move_id, move_id (base species only)"; starting_moves.text_changed.connect(_starting_moves_changed); _row(box, "Starting moves", starting_moves)
	var hint := Label.new(); hint.text = "Learnset move boxes search by display name or runtime ID. Invalid references cannot be saved."; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(hint)
	move_rows = VBoxContainer.new(); box.add_child(move_rows)
	var add := Button.new(); add.text = "+ Add learned move"; add.pressed.connect(func(): model.draft.get_or_add("learnset", []).append({"level":1,"move":""}); _render_moves(); _dirty()); box.add_child(add)

func _build_evolution_tab() -> void:
	var box := _tab("Evolution")
	var note := Label.new(); note.text = "The runtime stores evolution on the target as evolves_from + evolution_level. This view edits that existing relationship."; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(note)
	evolution_search = LineEdit.new(); evolution_search.placeholder_text = "Search evolution target…"; evolution_search.text_changed.connect(func(text): _fill_evolution_options(text)); _row(box, "Find target", evolution_search)
	evolution_box = OptionButton.new(); evolution_box.item_selected.connect(_evolution_changed); _row(box, "Evolves To", evolution_box)
	evolution_level = SpinBox.new(); evolution_level.min_value = 1; evolution_level.max_value = 100; evolution_level.value_changed.connect(_evolution_level_changed); _row(box, "Level condition", evolution_level)
	var go := Button.new(); go.text = "→ Open evolution target"; go.pressed.connect(func(): if not model.evolution_target_name.is_empty(): _attempt_select(model.evolution_target_name)); box.add_child(go)
	var play:=Button.new();play.text="Play Visual Evolution Preview";play.pressed.connect(_play_evolution_preview);box.add_child(play)
	evolution_preview=EvolutionPreview.new();box.add_child(evolution_preview)
	evolution_from_label = Label.new(); box.add_child(evolution_from_label)

func _build_found_tab() -> void:
	var box := _tab("Found In")
	var note := Label.new(); note.text = "Assign this Fakemon to existing Tall Grass or Water encounter tables at one exact level. These are the same map files used by runtime and the Map Editor.";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(note)
	found_list = VBoxContainer.new(); box.add_child(found_list)
	var buttons:=HBoxContainer.new();box.add_child(buttons)
	var save:=Button.new();save.text="Save Encounter Assignments";save.pressed.connect(_save_encounters);buttons.add_child(save)
	var discard:=Button.new();discard.text="Discard Encounter Changes";discard.pressed.connect(func():model.discard_encounters();_render_found();_dirty());buttons.add_child(discard)

func _refresh_browser() -> void:
	if browser == null or model.battle_data.is_empty(): return
	var current := model.selected_name; browser.clear(); var needle := search.text.strip_edges().to_lower()
	for name in model.species_names():
		if needle.is_empty() or name.to_lower().contains(needle): browser.add_item(name)
	for i in browser.item_count:
		if browser.get_item_text(i) == current: browser.select(i)

func _attempt_select(name: String) -> void:
	if model.is_dirty() or model.encounters_dirty() or art_tab.has_unsaved(): _message("Unsaved Fakemon, encounter, or staged Art Package changes remain. Save/write or revert them before changing selection.", true); _refresh_browser(); return
	_select(name)

func _select(name: String) -> void:
	if not model.select_species(name): return
	suppress = true; title.text = "%s  ·  %s" % [name, "Evolved data" if model.selected_source.ends_with("evolved_fakemon.json") else "Base data"]
	for key in fields:
		var value: Variant = model.draft.get(key, "")
		if key == "male_ratio" and value == null: value = ""
		fields[key].text = str(value)
	_populate_options(); _sync_color_picker(); _render_moves(); art_tab.load_art(String(model.draft.get("art_id","")),String(model.draft.get("name",""))); _render_evolution(); _render_found()
	for key in stat_spins: stat_spins[key].value = float(model.draft.get(key, 1))
	_update_bst(); suppress = false; _dirty(); _message("Loaded without changing the source schema.")

func _populate_options() -> void:
	var values := model.types_catalog(); var current: Array = model.draft.get("types", [model.draft.get("type", "")])
	for i in 2:
		type_boxes[i].clear(); if i == 1: type_boxes[i].add_item("— None —")
		for value in values: type_boxes[i].add_item(value)
		var index := type_boxes[i].get_item_index(type_boxes[i].get_item_id(maxi(0, type_boxes[i].item_count - 1)))
		for n in type_boxes[i].item_count:
			if n < type_boxes[i].item_count and type_boxes[i].get_item_text(n) == String(current[i] if i < current.size() else "— None —"): index = n
		type_boxes[i].select(index)
	var groups := model.egg_groups_for(); var catalog: Array = model.egg_data.get("groups", [])
	for i in 2:
		egg_boxes[i].clear(); for group in catalog: egg_boxes[i].add_item(String(group))
		var selected := catalog.find(groups[i] if i < groups.size() else ""); egg_boxes[i].select(maxi(0, selected))

func _render_moves() -> void:
	for child in move_rows.get_children(): child.queue_free()
	moveset_source_box.clear(); moveset_source_box.add_item("— Own learnset —"); moveset_source_box.set_item_metadata(0, "")
	for source_name in model.species_names():
		moveset_source_box.add_item(source_name); moveset_source_box.set_item_metadata(moveset_source_box.item_count - 1, source_name)
		if source_name == String(model.draft.get("moveset_source", "")): moveset_source_box.select(moveset_source_box.item_count - 1)
	moveset_source_box.disabled = model.selected_source.ends_with("battle_data.json")
	starting_moves.editable = model.selected_source.ends_with("battle_data.json")
	starting_moves.text = ", ".join(model.draft.get("moves", [])) if starting_moves.editable else "Inherited from %s" % model.draft.get("moveset_source", "")
	var catalog := model.move_catalog()
	for index in model.draft.get("learnset", []).size():
		var entry: Dictionary = model.draft.learnset[index]; var row := HBoxContainer.new(); move_rows.add_child(row)
		var level := SpinBox.new(); level.min_value = 1; level.max_value = 100; level.value = int(entry.get("level", 1)); level.custom_minimum_size.x = 90; level.value_changed.connect(func(v): entry["level"] = int(v); _dirty()); row.add_child(level)
		var move := LineEdit.new(); move.text = String(entry.get("move", "")); move.placeholder_text = "Search move…"; move.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(move)
		var suggestions := OptionButton.new(); suggestions.custom_minimum_size.x = 260; row.add_child(suggestions)
		_fill_move_suggestions(suggestions, move.text)
		move.text_changed.connect(func(text): _fill_move_suggestions(suggestions, text))
		suggestions.get_popup().id_pressed.connect(func(id): _choose_move_suggestion(suggestions, suggestions.get_popup().get_item_index(id), move, entry))
		var up := Button.new(); up.text = "↑"; up.disabled = index == 0; up.pressed.connect(_move_entry.bind(index, -1)); row.add_child(up)
		var down := Button.new(); down.text = "↓"; down.disabled = index == model.draft.learnset.size()-1; down.pressed.connect(_move_entry.bind(index, 1)); row.add_child(down)
		var remove := Button.new(); remove.text = "×"; remove.pressed.connect(func(): model.draft.learnset.remove_at(index); _render_moves(); _dirty()); row.add_child(remove)

func _fill_move_suggestions(box: OptionButton, query: String) -> void:
	box.clear(); var needle := query.to_lower(); var matches := 0
	for id in model.move_catalog():
		var data: Dictionary = model.move_catalog()[id]; var display := String(data.get("name", String(id).capitalize()))
		if needle.is_empty() or String(id).to_lower().contains(needle) or display.to_lower().contains(needle): box.add_item("%s  [%s]" % [display, id]); box.set_item_metadata(box.item_count-1, id); matches += 1
		if matches >= 20: break

func _choose_move_suggestion(box: OptionButton, index: int, search_box: LineEdit, entry: Dictionary) -> void:
	if index < 0 or index >= box.item_count: return
	var move_id := String(box.get_item_metadata(index)); entry["move"] = move_id; search_box.text = move_id; box.select(index); _dirty()

func _render_evolution() -> void:
	evolution_search.text = ""
	_fill_evolution_options("")
	evolution_level.value = maxi(1, model.evolution_level)
	var from_name := String(model.draft.get("evolves_from", "")); evolution_from_label.text = "Evolves From: %s" % (from_name if not from_name.is_empty() else "—")

func _fill_evolution_options(query: String) -> void:
	evolution_box.clear(); evolution_box.add_item("— No evolution target —"); evolution_box.set_item_metadata(0, "")
	var needle := query.strip_edges().to_lower()
	for mon in model.all_species():
		var name := String(mon.get("name", "")); evolution_box.add_item(name); evolution_box.set_item_metadata(evolution_box.item_count-1, name)
		if name == model.selected_name: evolution_box.remove_item(evolution_box.item_count - 1); continue
		if not needle.is_empty() and not name.to_lower().contains(needle): evolution_box.remove_item(evolution_box.item_count - 1); continue
		if name == model.evolution_target_name: evolution_box.select(evolution_box.item_count-1)

func _render_found() -> void:
	for child in found_list.get_children(): child.queue_free()
	var any:=false
	for map in model.encounter_maps():
		var encounter:=model.encounter_for(map.file,"",map.kind);var row:=HBoxContainer.new();found_list.add_child(row)
		var assigned:=CheckBox.new();assigned.text=map.label;assigned.button_pressed=encounter.assigned;assigned.custom_minimum_size.x=420;row.add_child(assigned)
		var level:=SpinBox.new();level.min_value=1;level.max_value=100;level.value=encounter.level;level.prefix="Lv. ";level.editable=assigned.button_pressed;row.add_child(level)
		assigned.toggled.connect(func(on):level.editable=on;model.set_encounter(map.file,on,int(level.value),map.kind);_render_found_warning();_dirty())
		level.value_changed.connect(func(value):if assigned.button_pressed:model.set_encounter(map.file,true,int(value),map.kind);_dirty())
		if encounter.assigned:any=true
	var warning:=Label.new();warning.name="NoWilds";warning.text="" if any else "NO WILDS!";warning.add_theme_font_size_override("font_size",30);warning.add_theme_color_override("font_color",Color("ff6b6b"));found_list.add_child(warning)

func _render_found_warning()->void:
	var any:=false
	for map in model.encounter_maps():
		if model.encounter_for(map.file,"",map.kind).assigned:any=true
	var warning:=found_list.get_node_or_null("NoWilds") as Label
	if warning!=null:warning.text="" if any else "NO WILDS!"

func _save_encounters()->void:
	if model.save_encounters():_message("Encounter assignments saved atomically with per-map .bak backups.");_dirty()
	else:_message(model.error,true)

func _play_evolution_preview()->void:
	if model.evolution_target_name.is_empty():_message("Select an evolution target first.",true);return
	var target:Dictionary={}
	for mon in model.all_species():
		if String(mon.get("name",""))==model.evolution_target_name:target=mon;break
	if target.is_empty():_message("Evolution target is missing.",true);return
	var from_image:=Image.new();if from_image.load(model.sprite_paths(model.draft).player)!=OK:from_image=null
	var to_image:=Image.new();if to_image.load(model.sprite_paths(target).player)!=OK:to_image=null
	evolution_preview.play(String(model.draft.name),String(target.name),from_image,to_image)

func _field_changed(key: String, control: Control) -> void:
	if suppress: return
	model.draft[key] = control.text
	if key == "art_id" and art_tab.package.art_id != control.text: art_tab.load_art(control.text,String(model.draft.get("name","")))
	if key == "name" and control.text != model.selected_name: _message("Renaming changes the runtime identifier. Trainer, map, evolution, and moveset references are not silently rewritten.", true)
	_dirty()
func _sync_color_picker() -> void:
	if color_picker == null: return
	var value := String(model.draft.get("color", "")).strip_edges().trim_prefix("#")
	if value.length() in [6, 8] and value.is_valid_html_color(): color_picker.color = Color.from_string("#" + value, color_picker.color)
func _sample_display_color(value: Color) -> void:
	if suppress: return
	var hex := value.to_html(false)
	model.draft["color"] = hex; suppress = true; fields["color"].text = hex; suppress = false; _dirty()
func _number_text_changed(text: String, key: String, _control: Control) -> void:
	if suppress: return
	model.draft[key] = null if key == "male_ratio" and text.strip_edges().is_empty() else float(text) if text.is_valid_float() else text; _dirty()
func _stat_changed(value: float, key: String) -> void:
	if suppress: return
	model.draft[key] = int(value); _update_bst(); _dirty()
func _update_bst() -> void: bst_label.text = "BST  %d" % model.bst()
func _types_changed(_index: int) -> void:
	if suppress: return
	var values: Array = [type_boxes[0].get_item_text(type_boxes[0].selected)]; var secondary := type_boxes[1].get_item_text(type_boxes[1].selected); if secondary != "— None —": values.append(secondary)
	if values.size() == 1: model.draft.erase("types"); model.draft["type"] = values[0]
	else: model.draft.erase("type"); model.draft["types"] = values
	_dirty()
func _eggs_changed(_index: int) -> void:
	if suppress: return
	model.set_egg_groups([egg_boxes[0].get_item_text(egg_boxes[0].selected), egg_boxes[1].get_item_text(egg_boxes[1].selected)]); _dirty()
func _starting_moves_changed(text: String) -> void:
	if suppress or not starting_moves.editable: return
	model.draft["moves"] = Array(text.split(",", false)).map(func(v): return String(v).strip_edges()); _dirty()
func _moveset_source_changed(index: int) -> void:
	if suppress or moveset_source_box.disabled: return
	model.draft["moveset_source"] = String(moveset_source_box.get_item_metadata(index)); _dirty()
func _evolution_changed(index: int) -> void:
	if suppress: return
	var requested := String(evolution_box.get_item_metadata(index))
	if not model.original_evolution_target_name.is_empty() and requested != model.original_evolution_target_name:
		_message("This runtime requires every evolved entry to retain evolves_from. Replace/remove is blocked because it would orphan the current target; edit the target's Evolves From relationship instead.", true)
		_render_evolution()
		return
	model.evolution_target_name = requested; _dirty()
func _move_entry(index: int, direction: int) -> void:
	var entry = model.draft.learnset.pop_at(index); model.draft.learnset.insert(index + direction, entry); _render_moves(); _dirty()

func _art_changed()->void:
	if suppress:return
	model.draft["art_id"]=art_tab.package.art_id
	fields["art_id"].text=art_tab.package.art_id
	_dirty()
func _dirty() -> void:
	var dirty:=model.is_dirty() or model.encounters_dirty() or (art_tab!=null and art_tab.has_unsaved());dirty_label.text = "● UNSAVED" if dirty else "Saved"; dirty_label.add_theme_color_override("font_color", Color("ffbd69") if dirty else Color("78dba9"))
func _save() -> void:
	if model.save_selected(): _refresh_browser(); _dirty(); _message("Saved to the engine-owned data files. Sprite warnings remain informational.")
	else: _message(model.error, true)
func _message(text: String, bad := false) -> void: status.text = ("[color=#ff7777]" if bad else "[color=#9fb8d8]") + text + "[/color]"

func _show_add_dialog() -> void:
	if model.is_dirty() or model.encounters_dirty() or art_tab.has_unsaved(): _message("Save/write or discard current changes before creating another Fakemon.",true); return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Add Fakemon"
	var form := VBoxContainer.new(); form.custom_minimum_size = Vector2(390, 150); form.add_theme_constant_override("separation", 10); dialog.add_child(form)
	var name_label := Label.new(); name_label.text = "Unique Fakemon name"; form.add_child(name_label)
	var input := LineEdit.new()
	input.placeholder_text = "Example: Bravarb"
	form.add_child(input)
	var evolved := CheckBox.new(); evolved.text = "Create as evolved form"; form.add_child(evolved)
	var parent_label := Label.new(); parent_label.text = "Evolves from"; parent_label.visible = false; form.add_child(parent_label)
	var parent := OptionButton.new(); parent.visible = false; parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL; form.add_child(parent)
	for species_name in model.species_names(): parent.add_item(species_name); parent.set_item_metadata(parent.item_count - 1, species_name)
	evolved.toggled.connect(func(enabled): parent_label.visible = enabled; parent.visible = enabled)
	add_child(dialog)
	dialog.confirmed.connect(_add_confirmed.bind(dialog, input, evolved, parent))
	dialog.popup_centered(Vector2i(440, 260))

func _add_confirmed(dialog: ConfirmationDialog, input: LineEdit, evolved: CheckBox, parent: OptionButton) -> void:
	var evolves_from := String(parent.get_item_metadata(parent.selected)) if evolved.button_pressed and parent.item_count > 0 else ""
	if model.add_species(input.text, evolves_from):
		_select(model.selected_name)
		model.original = {}
		_dirty()
		_refresh_browser()
		_message("New %s Fakemon is unsaved; complete its fields and save." % ("evolved" if evolved.button_pressed else "base"))
	else:
		_message("Enter a unique name.", true)
	dialog.queue_free()

func _confirm_remove() -> void:
	if model.selected_name.is_empty(): return
	if model.is_dirty() or model.encounters_dirty() or art_tab.has_unsaved(): _message("Save/write or discard current changes before removing this Fakemon.",true); return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Permanently remove %s from its source data and egg assignments?\nReferences elsewhere will only be warned about, not rewritten." % model.selected_name
	add_child(dialog)
	dialog.confirmed.connect(_remove_confirmed.bind(dialog))
	dialog.popup_centered()

func _remove_confirmed(dialog: ConfirmationDialog) -> void:
	if model.remove_selected():
		_refresh_browser()
		if not model.species_names().is_empty(): _select(model.species_names()[0])
	dialog.queue_free()

func _evolution_level_changed(value: float) -> void:
	if suppress: return
	model.evolution_level = int(value)
	_dirty()
