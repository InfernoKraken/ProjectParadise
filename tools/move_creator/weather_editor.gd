class_name WeatherEditor
extends VBoxContainer

const RENDERER_SCRIPT := preload("res://battle/weather_visual_renderer.gd")
var model := WeatherEditorModel.new()
var weather_select: OptionButton
var duration_spin: SpinBox
var element_list: ItemList
var properties: VBoxContainer
var preview: Control
var renderer: WeatherVisualRenderer
var turn_label: Label
var status_label: Label
var move_select: OptionButton
var new_weather_edit: LineEdit
var current_turn := 1

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL; size_flags_vertical = Control.SIZE_EXPAND_FILL
	if model.load_data() != OK: return
	_build_ui(); _refresh_weathers()

func _build_ui() -> void:
	var toolbar := HBoxContainer.new(); add_child(toolbar)
	toolbar.add_child(_label("Weather:")); weather_select = OptionButton.new(); weather_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL; toolbar.add_child(weather_select)
	weather_select.item_selected.connect(func(_index): _select_weather())
	new_weather_edit = LineEdit.new(); new_weather_edit.placeholder_text = "New weather name"; toolbar.add_child(new_weather_edit); _button(toolbar, "New Weather", _new_weather)
	_button(toolbar, "Save Weather", _save)
	var duration_row := HBoxContainer.new(); add_child(duration_row); duration_row.add_child(_label("Duration (turns):")); duration_spin = SpinBox.new(); duration_spin.min_value = 1; duration_spin.max_value = 99; duration_spin.step = 1; duration_row.add_child(duration_spin); duration_spin.value_changed.connect(func(value): model.set_duration(int(value)); current_turn = mini(current_turn, model.duration()); _sync_preview())
	var assignment := HBoxContainer.new(); add_child(assignment); assignment.add_child(_label("Assign to weather-setting move:")); move_select = OptionButton.new(); move_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL; assignment.add_child(move_select); _button(assignment, "Assign to Move", _assign)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(split)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 320; split.add_child(left)
	var actions := HBoxContainer.new(); left.add_child(actions)
	var add_menu := MenuButton.new(); add_menu.text = "Add Element"; actions.add_child(add_menu)
	for item in [["Background Overlay", "background_overlay"], ["Sprite", "sprite_effect"], ["Light", "lighting_effect"], ["Particle", "particle_effect"], ["Pulse / Burst", "turn_effect"], ["Thought Sequence", "thought_sequence"]]: add_menu.get_popup().add_item(item[0]); add_menu.get_popup().set_item_metadata(add_menu.get_popup().item_count - 1, item[1])
	add_menu.get_popup().id_pressed.connect(func(id): _add_element(String(add_menu.get_popup().get_item_metadata(add_menu.get_popup().get_item_index(id)))))
	_button(actions, "Copy", _copy_element)
	_button(actions, "Paste", _paste_element)
	_button(actions, "Undo", _undo_element)
	_button(actions, "Delete Element", _delete_element)
	element_list = ItemList.new(); element_list.custom_minimum_size.y = 170; left.add_child(element_list); element_list.item_selected.connect(func(index): _select_element(index))
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; left.add_child(scroll); properties = VBoxContainer.new(); properties.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(properties)
	var right := VBoxContainer.new(); right.custom_minimum_size.x = 540; split.add_child(right)
	var preview_controls := HBoxContainer.new(); right.add_child(preview_controls); _button(preview_controls, "Previous Turn", _previous_turn); _button(preview_controls, "Next Turn", _next_turn); _button(preview_controls, "Play First Active Turn", _play_turn); _button(preview_controls, "Stop", _stop)
	turn_label = _label("Turn 1"); preview_controls.add_child(turn_label)
	var background_toggle := CheckBox.new(); background_toggle.text = "Sample Background"; background_toggle.button_pressed = true; preview_controls.add_child(background_toggle)
	preview = Control.new(); preview.custom_minimum_size = Vector2(540, 304); preview.clip_contents = true; preview.size_flags_vertical = Control.SIZE_EXPAND_FILL; right.add_child(preview)
	var sample := TextureRect.new(); sample.name = "SampleBattleBackground"; sample.texture = load("res://assets/battle/battle_background.png"); sample.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; sample.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; sample.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); preview.add_child(sample); background_toggle.toggled.connect(func(value): sample.visible = value)
	renderer = RENDERER_SCRIPT.new(); renderer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); preview.add_child(renderer)
	status_label = _label(""); status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; right.add_child(status_label)

func _refresh_weathers() -> void:
	weather_select.clear()
	for name: String in model.weather_names(): weather_select.add_item(name)
	if weather_select.item_count > 0: _select_weather()

func _new_weather() -> void:
	var errors: PackedStringArray = model.create_weather(new_weather_edit.text)
	if not errors.is_empty(): _status("New weather: " + "; ".join(errors), true); return
	var created := model.selected_weather; weather_select.clear()
	for name: String in model.weather_names(): weather_select.add_item(name); if name == created: weather_select.select(weather_select.item_count - 1)
	new_weather_edit.clear(); _select_weather(); _status("New weather created in memory. Add any combination of elements, then save.", false)

func _select_weather() -> void:
	if weather_select.item_count == 0: return
	model.select_weather(weather_select.get_item_text(weather_select.selected)); duration_spin.set_value_no_signal(model.duration()); current_turn = 1; _refresh_moves(); _refresh_elements(); _sync_preview()

func _refresh_moves() -> void:
	move_select.clear()
	for move_id: String in model.eligible_move_ids(): move_select.add_item("%s — %s" % [move_id, model.battle_data["moves"][move_id].get("name", move_id)]); move_select.set_item_metadata(move_select.item_count - 1, move_id)

func _refresh_elements() -> void:
	element_list.clear()
	for entry: Dictionary in model.elements():
		var element: Dictionary = entry["element"]; element_list.add_item("%s  ·  %s  ·  turns %s" % [String(entry["category"]).replace("_", " ").capitalize(), element.get("type", element.get("asset_family", element.get("asset", ""))), JSON.stringify(element.get("turns", "all"))]); element_list.set_item_metadata(element_list.item_count - 1, entry)
	_rebuild_properties(); _validate()

func _select_element(index: int) -> void:
	var entry: Dictionary = element_list.get_item_metadata(index); model.selected_category = entry["category"]; model.selected_element = entry["element"]; _rebuild_properties()

func _add_element(category: String) -> void:
	if category in ["background_overlay", "thought_sequence"] and not model.definition().get(category, {}).is_empty(): _status("Only one %s is supported." % category.replace("_", " "), true); return
	var added := model.add_element(category); _refresh_elements(); _select_element_reference(added); _sync_preview()

func _delete_element() -> void:
	if model.delete_selected(): _refresh_elements(); _sync_preview()

func _copy_element() -> void:
	var copied := model.copy_selected(); _status("Copied selected weather element." if copied else "Select an element to copy.", not copied)

func _paste_element() -> void:
	if not model.paste_copied(): _status("Nothing can be pasted here. A weather can only have one background overlay.", true); return
	var pasted := model.selected_element; _refresh_elements(); _select_element_reference(pasted)
	_sync_preview(); _status("Pasted an independent copy of the weather element.", false)

func _select_element_reference(element: Dictionary) -> void:
	for index in range(element_list.item_count - 1, -1, -1):
		var entry: Dictionary = element_list.get_item_metadata(index)
		if is_same(entry["element"], element): element_list.select(index); _select_element(index); return

func _undo_element() -> void:
	if not model.undo_element_change(): _status("There are no element changes to undo.", true); return
	_refresh_elements(); _sync_preview(); _status("Undid the latest weather element change.", false)

func _rebuild_properties() -> void:
	for child: Node in properties.get_children(): child.queue_free()
	var element: Dictionary = model.selected_element
	if element.is_empty(): properties.add_child(_label("Select an element to edit.")); return
	if model.selected_category != "thought_sequence": _text("Turns (all, 2, or [1, 3])", WeatherEditorModel.turns_text(element.get("turns", "all")), func(value): model.set_element_field("turns", value); _changed())
	match model.selected_category:
		"background_overlay":
			_searchable_choice("Weather overlay asset", model.overlay_assets(), element.get("asset", ""), func(value): model.set_element_field("asset", value); _changed()); _color("Modulate", element.get("modulate", "#ffffff"), func(value): model.set_element_field("modulate", value); _changed()); _number("Opacity", element.get("opacity", 1.0), 0, 1, 0.01, func(value): model.set_element_field("opacity", value); _changed()); _number("Scale", element.get("scale", 1.0), 0.01, 20, 0.05, func(value): model.set_element_field("scale", value); _changed()); _check("Mirror horizontally", element.get("mirror_x", false), func(value): model.set_element_field("mirror_x", value); _changed()); _check("Mirror vertically", element.get("mirror_y", false), func(value): model.set_element_field("mirror_y", value); _changed()); _offsets(element)
		"sprite_effect":
			_build_sprite_properties(element)
		"lighting_effect":
			_choice("Light type", WeatherEditorModel.LIGHT_TYPES, element.get("type", "wash"), _light_type_changed)
			_build_light_properties(element)
		"particle_effect":
			_build_particle_properties(element)
		"thought_sequence":
			_number("Initial delay", element.get("initial_delay", element.get("interval", 5.0)), .1, 300, .1, func(value): model.set_element_field("initial_delay", value); _changed())
			_number("Repeat interval", element.get("interval", 5.0), .1, 300, .1, func(value): model.set_element_field("interval", value); _changed())
			_json_field("Sequences", element.get("sequences", []), func(value): model.set_element_field("sequences", value); _changed())
		"turn_effect":
			_choice("Effect type", ["pulse", "sprite_burst"], element.get("type", "pulse"), func(value): model.set_element_field("type", value); _rebuild_properties(); _changed()); if String(element.get("type", "pulse")) == "pulse": _color("Color", element.get("color", "#ffffff"), func(value): model.set_element_field("color", value); _changed()); _number("Opacity", element.get("opacity", .15), 0, 1, .01, func(value): model.set_element_field("opacity", value); _changed()); _number("Duration", element.get("duration", .5), .1, 10, .1, func(value): model.set_element_field("duration", value); _changed()); _check("Loop", element.get("loop", false), func(value): model.set_element_field("loop", value); _changed()); if bool(element.get("loop", false)): _number("Interval", element.get("interval", 1.0), .05, 30, .05, func(value): model.set_element_field("interval", value); _changed())
			else: _searchable_choice("Weather asset family", model.sprite_families(), element.get("asset_family", ""), func(value): model.set_element_field("asset_family", value); _changed()); _choice("Anchor", WeatherEditorModel.ANCHORS, element.get("anchor", "RANDOM_GROUND"), func(value): model.set_element_field("anchor", value); _changed()); _offsets(element); _number("Scale", element.get("scale", 1.0), .01, 20, .05, func(value): model.set_element_field("scale", value); _changed()); _number("Spawn count", element.get("spawn_count", 1), 1, 99, 1, func(value): model.set_element_field("spawn_count", int(value)); _changed()); _number("Lifetime", element.get("lifetime", 1.5), .1, 30, .1, func(value): model.set_element_field("lifetime", value); _changed())

func _changed() -> void:
	_update_selected_list_item()
	_sync_preview()

func _update_selected_list_item() -> void:
	var selected := element_list.get_selected_items()
	if selected.is_empty() or model.selected_element.is_empty(): return
	var element := model.selected_element
	element_list.set_item_text(selected[0], "%s  ·  %s  ·  turns %s" % [model.selected_category.replace("_", " ").capitalize(), element.get("type", element.get("asset_family", element.get("asset", ""))), JSON.stringify(element.get("turns", "all"))])

func _offsets(element: Dictionary) -> void:
	_number("X Offset", element.get("x_offset", 0.0), -4096, 4096, 1, func(value): model.set_element_field("x_offset", value); _changed())
	_number("Y Offset", element.get("y_offset", 0.0), -4096, 4096, 1, func(value): model.set_element_field("y_offset", value); _changed())

func _build_sprite_properties(element: Dictionary) -> void:
	_searchable_choice("Weather asset family", model.sprite_families(), element.get("asset_family", ""), func(value): model.set_element_field("asset_family", value); _changed())
	_choice("Sprite mode", WeatherEditorModel.SPRITE_MODES, element.get("sprite_mode", "static"), func(value): model.set_element_field("sprite_mode", value); _rebuild_properties(); _changed())
	_choice("Anchor", WeatherEditorModel.ANCHORS, element.get("anchor", "SCREEN_CENTER"), func(value): model.set_element_field("anchor", value); _changed())
	_offsets(element)
	_number("Scale", element.get("scale", 1.0), 0.01, 20, 0.05, func(value): model.set_element_field("scale", value); _changed())
	_number("Opacity", element.get("opacity", 1.0), 0, 1, 0.01, func(value): model.set_element_field("opacity", value); _changed())
	_number("Rotation", element.get("rotation", 0.0), -360, 360, 1, func(value): model.set_element_field("rotation", value); _changed())
	_check("Mirror horizontally", element.get("mirror_x", false), func(value): model.set_element_field("mirror_x", value); _changed())
	_check("Mirror vertically", element.get("mirror_y", false), func(value): model.set_element_field("mirror_y", value); _changed())
	if String(element.get("sprite_mode", "static")) == "animated":
		_number("Frame duration", element.get("frame_duration", 0.25), 0.05, 10, 0.05, func(value): model.set_element_field("frame_duration", value); _changed())
		_check("Ping-pong frames", element.get("animation_ping_pong", false), func(value): model.set_element_field("animation_ping_pong", value); _changed())
	if String(element.get("sprite_mode", "static")) == "scrolling":
		_choice("Scroll direction", ["left", "right"], element.get("scroll_direction", "left"), func(value): model.set_element_field("scroll_direction", value); _changed())
		_number("Scroll speed", element.get("scroll_speed", 30.0), 0, 10000, 1, func(value): model.set_element_field("scroll_speed", value); _changed())
		_number("Spacing", element.get("spacing", 0.0), -4096, 4096, 1, func(value): model.set_element_field("spacing", value); _changed())
		_number("Transition overlap", element.get("transition_overlap", 0.0), 0, 4096, 1, func(value): model.set_element_field("transition_overlap", value); _changed())
		_check("Loop strip", element.get("loop", true), func(value): model.set_element_field("loop", value); _changed())
	else:
		_choice("Behavior", WeatherEditorModel.SPRITE_BEHAVIORS, element.get("mode", "persistent"), func(value): model.set_element_field("mode", value); _rebuild_properties(); _changed())
		_choice("Variant", ["random", "sequential", "fixed"], element.get("variant_mode", "random"), func(value): model.set_element_field("variant_mode", value); _changed())
		_number("Spawn count", element.get("spawn_count", 1), 1, 99, 1, func(value): model.set_element_field("spawn_count", int(value)); _changed())
		if String(element.get("mode", "persistent")) == "ambient_spawn":
			_number("Spawn interval", element.get("spawn_interval", 1), 0.1, 30, 0.1, func(value): model.set_element_field("spawn_interval", value); _changed())
			_number("Lifetime", element.get("lifetime", 1.5), 0.1, 30, 0.1, func(value): model.set_element_field("lifetime", value); _changed())
		else:
			_check("Thought target", element.has("thought_id"), func(enabled): model.set_element_field("thought_id", String(element.get("thought_id", "THOUGHT")) if enabled else null); _rebuild_properties(); _changed())
			if element.has("thought_id"):
				_text("Thought ID", element.get("thought_id", "THOUGHT"), func(value): model.set_element_field("thought_id", value); _changed()); _number("Thought low alpha", element.get("thought_low_alpha", .08), 0, 1, .01, func(value): model.set_element_field("thought_low_alpha", value); _changed()); _number("Thought high alpha", element.get("thought_high_alpha", element.get("opacity", .55)), 0, 1, .01, func(value): model.set_element_field("thought_high_alpha", value); _changed())
			_check("Signal pulse", element.get("signal_enabled", false), func(value): model.set_element_field("signal_enabled", value); _rebuild_properties(); _changed())
			if bool(element.get("signal_enabled", false)):
				_number("Signal low alpha", element.get("signal_min_alpha", 0.12), 0, 1, 0.01, func(value): model.set_element_field("signal_min_alpha", value); _changed())
				_number("Signal high alpha", element.get("signal_max_alpha", element.get("opacity", 0.5)), 0, 1, 0.01, func(value): model.set_element_field("signal_max_alpha", value); _changed())
				_number("Signal rise time", element.get("signal_rise_time", 0.3), 0.05, 30, 0.05, func(value): model.set_element_field("signal_rise_time", value); _changed())
				_number("Signal fall time", element.get("signal_fall_time", 0.6), 0.05, 30, 0.05, func(value): model.set_element_field("signal_fall_time", value); _changed())
				_number("Signal interval", element.get("signal_interval", 2.5), 0, 30, 0.1, func(value): model.set_element_field("signal_interval", value); _changed())
				_number("Signal delay", element.get("signal_delay", 0.0), 0, 30, 0.1, func(value): model.set_element_field("signal_delay", value); _changed())
	_number("Fade-out duration", element.get("fade_out_duration", 0.0), 0, 30, 0.05, func(value): model.set_element_field("fade_out_duration", value); _rebuild_properties(); _changed())
	if float(element.get("fade_out_duration", 0.0)) > 0.0:
		var causes: Array = element.get("fade_out_causes", [String(element.get("fade_out_trigger", "weather_ends"))])
		for cause: String in WeatherEditorModel.FADE_OUT_CAUSES:
			_check("Fade on %s" % cause.replace("_", " "), causes.has(cause), func(enabled, selected_cause=cause): model.set_sprite_fade_cause(selected_cause, enabled); _changed())
		if causes.has("duration"): _number("Visible duration", element.get("visible_duration", 1.0), 0.01, 300, 0.05, func(value): model.set_element_field("visible_duration", value); _changed())

func _build_light_properties(element: Dictionary) -> void:
	var type := String(element.get("type", "wash"))
	if type == "beam":
		_choice("Start Anchor", WeatherEditorModel.ANCHORS, element.get("start_anchor", element.get("anchor", "SCREEN_TOP")), func(value): model.set_element_field("start_anchor", value); _changed())
		_choice("End Anchor", WeatherEditorModel.ANCHORS, element.get("end_anchor", "FIELD_CENTER"), func(value): model.set_element_field("end_anchor", value); _changed())
		_number("Start X Offset", element.get("start_x_offset", element.get("x_offset", 0.0)), -4096, 4096, 1, func(value): model.set_element_field("start_x_offset", value); _changed())
		_number("Start Y Offset", element.get("start_y_offset", element.get("y_offset", 0.0)), -4096, 4096, 1, func(value): model.set_element_field("start_y_offset", value); _changed())
		_number("End X Offset", element.get("end_x_offset", 0.0), -4096, 4096, 1, func(value): model.set_element_field("end_x_offset", value); _changed())
		_number("End Y Offset", element.get("end_y_offset", 0.0), -4096, 4096, 1, func(value): model.set_element_field("end_y_offset", value); _changed())
		_number("Start Width", element.get("start_width", 70.0), 1, 4096, 1, func(value): model.set_element_field("start_width", value); _changed()); _number("End Width", element.get("end_width", 130.0), 1, 4096, 1, func(value): model.set_element_field("end_width", value); _changed()); _number("Spacing", element.get("spacing", 120.0), 0, 4096, 1, func(value): model.set_element_field("spacing", value); _changed())
	elif type in ["orb", "heat_shimmer", "particles"]:
		_choice("Anchor", WeatherEditorModel.ANCHORS, element.get("anchor", "RANDOM_SCREEN" if type == "orb" else "FIELD_CENTER" if type == "heat_shimmer" else "SCREEN_CENTER"), func(value): model.set_element_field("anchor", value); _changed()); _offsets(element)
	if type in ["wash", "beam", "orb", "particles"]:
		_color("Color", element.get("color", "#ffffff"), func(value): model.set_element_field("color", value); _changed()); _number("Opacity", element.get("opacity", .2), 0, 1, .01, func(value): model.set_element_field("opacity", value); _changed())
	if type in ["beam", "orb"]: _number("Edge Softness", element.get("edge_softness", .7 if type == "beam" else .75), 0, 1, .01, func(value): model.set_element_field("edge_softness", value); _changed())
	if type == "orb": _number("Size", element.get("size", 70.0), 2, 4096, 1, func(value): model.set_element_field("size", value); _changed())
	if type in ["heat_shimmer", "particles"]:
		_number("Width", element.get("width", 180.0 if type == "heat_shimmer" else 960.0), 1, 4096, 1, func(value): model.set_element_field("width", value); _changed()); _number("Height", element.get("height", 90.0 if type == "heat_shimmer" else 540.0), 1, 4096, 1, func(value): model.set_element_field("height", value); _changed()); _number("Speed", element.get("speed", 1.0), -100, 100, .05, func(value): model.set_element_field("speed", value); _changed())
	if type == "heat_shimmer": _number("Strength", element.get("strength", .006), 0, 1, .001, func(value): model.set_element_field("strength", value); _changed())
	if type == "particles": _number("Particle Size", element.get("size", 2.0), .1, 100, .1, func(value): model.set_element_field("size", value); _changed()); _number("Horizontal Drift", element.get("horizontal_drift", 0.0), -1000, 1000, 1, func(value): model.set_element_field("horizontal_drift", value); _changed()); _number("Vertical Drift", element.get("vertical_drift", 0.0), -1000, 1000, 1, func(value): model.set_element_field("vertical_drift", value); _changed())
	if type != "heat_shimmer": _number("Count", element.get("count", 1), 1, 999, 1, func(value): model.set_element_field("count", int(value)); _changed())
	if type in ["wash", "beam", "orb"]:
		_check("Flicker", element.get("flicker_enabled", false), func(value): model.set_element_field("flicker_enabled", value); _rebuild_properties(); _changed())
		if bool(element.get("flicker_enabled", false)): _number("Flicker Min Alpha", element.get("flicker_min_alpha", float(element.get("opacity", .2)) * .7), 0, 1, .01, func(value): model.set_element_field("flicker_min_alpha", value); _changed()); _number("Flicker Max Alpha", element.get("flicker_max_alpha", element.get("opacity", .2)), 0, 1, .01, func(value): model.set_element_field("flicker_max_alpha", value); _changed()); _number("Flicker Interval", element.get("flicker_interval", .8), .025, 30, .025, func(value): model.set_element_field("flicker_interval", value); _changed())

func _build_particle_properties(element: Dictionary) -> void:
	_searchable_choice("Particle Sprite Family", model.sprite_families(), element.get("particle_sprite", ""), func(value): model.set_element_field("particle_sprite", value); _changed())
	_number("Emit Rate", element.get("emit_rate", 1.0), 0, 10000, .1, func(value): model.set_element_field("emit_rate", value); _changed())
	_number("Maximum Live Count", element.get("emit_max_count", 32), 0, 10000, 1, func(value): model.set_element_field("emit_max_count", int(value)); _changed())
	_number("Particle Lifetime", element.get("particle_lifetime", 1.0), .01, 300, .05, func(value): model.set_element_field("particle_lifetime", value); _changed())
	var emitter_mode := WeatherEditorModel.particle_emitter_mode(element)
	_choice("Emitter Mode", ["anchored", "screen"], emitter_mode, func(value): model.set_particle_emitter_mode(value); _rebuild_properties(); _changed())
	if emitter_mode == "anchored":
		_choice("Emitter Anchor", WeatherEditorModel.ANCHORS, element.get("emitter_anchor", "SCREEN_CENTER"), func(value): model.set_element_field("emitter_anchor", value); _changed())
		_number("Emitter X Offset", element.get("emitter_offset_x", 0.0), -4096, 4096, 1, func(value): model.set_element_field("emitter_offset_x", value); _changed())
		_number("Emitter Y Offset", element.get("emitter_offset_y", 0.0), -4096, 4096, 1, func(value): model.set_element_field("emitter_offset_y", value); _changed())
		_number("Emitter Width", element.get("emitter_width", 0.0), 0, 4096, 1, func(value): model.set_element_field("emitter_width", value); _changed())
		_number("Emitter Height", element.get("emitter_height", 0.0), 0, 4096, 1, func(value): model.set_element_field("emitter_height", value); _changed())
	_choice("Movement", ["fall", "rise", "right", "left"], WeatherEditorModel.particle_movement_mode(element), func(value): model.set_element_field("movement_mode", value); _changed())
	_number("Speed", element.get("speed", 100.0), -10000, 10000, 1, func(value): model.set_element_field("speed", value); _changed())
	_number("Horizontal Drift", element.get("horizontal_drift", 0.0), -10000, 10000, 1, func(value): model.set_element_field("horizontal_drift", value); _changed())
	_number("Minimum Scale", element.get("scale_min", 1.0), .01, 100, .05, func(value): model.set_element_field("scale_min", value); _changed())
	_number("Maximum Scale", element.get("scale_max", 1.0), .01, 100, .05, func(value): model.set_element_field("scale_max", value); _changed())
	_number("Minimum Opacity", element.get("opacity_min", 1.0), 0, 1, .01, func(value): model.set_element_field("opacity_min", value); _changed())
	_number("Maximum Opacity", element.get("opacity_max", 1.0), 0, 1, .01, func(value): model.set_element_field("opacity_max", value); _changed())
	_choice("Rotation Mode", ["fixed", "random", "align_to_velocity"], element.get("rotation_mode", "fixed"), func(value): model.set_element_field("rotation_mode", value); _rebuild_properties(); _changed())
	if String(element.get("rotation_mode", "fixed")) == "fixed": _number("Rotation", element.get("rotation", 0.0), -360, 360, 1, func(value): model.set_element_field("rotation", value); _changed())
	_number("Rotation Speed", element.get("rotation_speed", 0.0), -10000, 10000, 1, func(value): model.set_element_field("rotation_speed", value); _changed())
	_number("Offscreen Margin", element.get("offscreen_margin", 32.0), 0, 4096, 1, func(value): model.set_element_field("offscreen_margin", value); _changed())
	_check("Flicker", element.get("flicker_enabled", false), func(value): model.set_element_field("flicker_enabled", value); _rebuild_properties(); _changed())
	if bool(element.get("flicker_enabled", false)):
		_choice("Flicker type", WeatherEditorModel.FLICKER_TYPES, element.get("flicker_type", "all"), func(value): model.set_element_field("flicker_type", value); _changed())
		_number("Flicker min alpha", element.get("flicker_min_alpha", 0.7), 0, 1, 0.01, func(value): model.set_element_field("flicker_min_alpha", value); _changed())
		_number("Flicker max alpha", element.get("flicker_max_alpha", 1.0), 0, 1, 0.01, func(value): model.set_element_field("flicker_max_alpha", value); _changed())
		_number("Flicker interval", element.get("flicker_interval", 0.8), 0.025, 30, 0.025, func(value): model.set_element_field("flicker_interval", value); _changed())
func _sync_preview() -> void:
	if renderer == null or model.selected_weather.is_empty(): return
	renderer.definitions = {model.selected_weather:model.definition()}
	if renderer.current_weather == model.selected_weather: renderer.clear_weather()
	renderer.show_weather(model.selected_weather, model.duration())
	if current_turn > 1:
		renderer.update_turns(model.duration() - current_turn + 1)
	turn_label.text = "Turn %d / %d" % [current_turn, model.duration()]
	_validate()
func _previous_turn() -> void: current_turn = maxi(1, current_turn - 1); _sync_preview()
func _next_turn() -> void: current_turn = mini(model.duration(), current_turn + 1); _sync_preview()
func _light_type_changed(value: String) -> void:
	model.set_element_field("type", value)
	if value == "orb" and not model.selected_element.has("anchor"): model.set_element_field("anchor", "RANDOM_SCREEN")
	if value == "beam" and not model.selected_element.has("anchor"): model.set_element_field("anchor", "SCREEN_TOP")
	_rebuild_properties()
	_changed()
func _play_turn() -> void: _sync_preview(); renderer.pulse_turn()
func _stop() -> void: renderer.clear_weather(); turn_label.text = "Stopped — turn %d selected" % current_turn
func _assign() -> void:
	if move_select.item_count == 0: _status("No moves with non-null sets_weather are available.", true); return
	_status("Assigned weather to move. Save Weather to persist both files.", false) if model.assign_to_move(String(move_select.get_item_metadata(move_select.selected))) else _status("Assignment was blocked.", true)
func _save() -> void:
	var error: Error = model.save(); _status("Saved canonical weather visuals and duration data." if error == OK else "Save blocked: %s" % ("validation errors" if error == ERR_INVALID_DATA else error_string(error)), error != OK)
func _validate() -> void:
	var errors: PackedStringArray = model.validation_errors(); _status("Weather definition valid%s" % (" — unsaved" if model.dirty else "") if errors.is_empty() else "Weather errors: " + "; ".join(errors), not errors.is_empty())
func _status(text: String, error: bool) -> void: status_label.text = text; status_label.modulate = Color("#ff7777") if error else Color("#7ce38b")
func _label(text: String) -> Label: var value := Label.new(); value.text = text; return value
func _button(parent: Node, text: String, callback: Callable) -> Button: var value := Button.new(); value.text = text; value.pressed.connect(callback); parent.add_child(value); return value
func _row(label_text: String) -> HBoxContainer: var row := HBoxContainer.new(); properties.add_child(row); var label := _label(label_text); label.custom_minimum_size.x = 155; row.add_child(label); return row
func _text(label_text: String, value: Variant, callback: Callable) -> void: var row := _row(label_text); var edit := LineEdit.new(); edit.text = String(value); edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; edit.text_changed.connect(callback); row.add_child(edit)
func _json_field(label_text: String, value: Variant, callback: Callable) -> void:
	var row := _row(label_text); var edit := TextEdit.new(); edit.text = JSON.stringify(value, "  "); edit.custom_minimum_size.y = 180; edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(edit)
	edit.focus_exited.connect(func() -> void:
		var parsed: Variant = JSON.parse_string(edit.text)
		if parsed is Array:
			callback.call(parsed)
		else:
			_status("Sequences must be valid JSON containing an array.", true)
	)
func _searchable_choice(label_text: String, values: PackedStringArray, current: Variant, callback: Callable) -> void:
	var row := _row(label_text)
	var search := LineEdit.new(); search.text = String(current); search.placeholder_text = "Type to filter assets"; search.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(search)
	var menu := MenuButton.new(); menu.text = "Select…"; row.add_child(menu)
	var popup := menu.get_popup()
	var rebuild := func(filter_text: String):
		popup.clear()
		for item: String in values:
			if filter_text.is_empty() or filter_text.to_lower() in item.to_lower(): popup.add_item(item); popup.set_item_metadata(popup.item_count - 1, item)
	rebuild.call("")
	search.text_changed.connect(func(text): rebuild.call(text); callback.call(text))
	popup.id_pressed.connect(func(id): var value := String(popup.get_item_metadata(popup.get_item_index(id))); search.set_text(value); search.caret_column = value.length(); callback.call(value))
func _number(label_text: String, value: Variant, minimum: float, maximum: float, step: float, callback: Callable) -> void: var row := _row(label_text); var spin := SpinBox.new(); spin.min_value = minimum; spin.max_value = maximum; spin.step = step; spin.value = float(value); spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; spin.value_changed.connect(callback); row.add_child(spin)
func _check(label_text: String, value: bool, callback: Callable) -> void: var row := _row(label_text); var check := CheckBox.new(); check.button_pressed = value; check.toggled.connect(callback); row.add_child(check)
func _choice(label_text: String, values: Array, current: Variant, callback: Callable) -> void:
	var row := _row(label_text)
	var option := OptionButton.new(); option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: Variant in values:
		option.add_item(String(item))
		if String(item) == String(current): option.select(option.item_count - 1)
	option.item_selected.connect(func(index): callback.call(option.get_item_text(index)))
	row.add_child(option)
func _color(label_text: String, value: Variant, callback: Callable) -> void: var row := _row(label_text); var picker := ColorPickerButton.new(); picker.color = Color(String(value)); picker.color_changed.connect(func(color): callback.call("#" + color.to_html(false))); row.add_child(picker)
