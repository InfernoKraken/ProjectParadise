class_name WeatherEditorModel
extends RefCounted

const VISUALS_PATH := "res://data/weather_visuals.json"
const BATTLE_PATH := "res://data/battle_data.json"
const WEATHER_ASSET_DIR := "res://assets/battle/weather"
const ELEMENT_TYPES := ["background_overlay", "sprite_effect", "lighting_effect", "particle_effect", "turn_effect", "thought_sequence"]
const ANCHORS := ["SCREEN_TOP", "SCREEN_BOTTOM", "SCREEN_LEFT", "SCREEN_RIGHT", "SCREEN_CENTER", "BACKGROUND_CENTER", "FIELD_CENTER", "ALLY_FIELD", "ENEMY_FIELD", "RANDOM_SCREEN", "RANDOM_GROUND"]
const LIGHT_TYPES := ["wash", "beam", "orb", "heat_shimmer", "particles"]
const SPRITE_MODES := ["static", "animated", "scrolling"]
const SPRITE_BEHAVIORS := ["persistent", "ambient_spawn"]
const FADE_OUT_CAUSES := ["weather_ends", "element_not_on_turn", "duration"]
const FLICKER_TYPES := ["all", "individual"]

var visuals: Dictionary = {}
var battle_data: Dictionary = {}
var selected_weather := ""
var selected_element: Dictionary = {}
var selected_category := ""
var dirty := false
var copied_element: Dictionary = {}
var copied_category := ""
var element_undo_history: Array[Dictionary] = []

func load_data(visuals_path := VISUALS_PATH, battle_path := BATTLE_PATH) -> Error:
	var visual_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(visuals_path))
	var battle_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(battle_path))
	if not visual_value is Dictionary or not battle_value is Dictionary:
		return ERR_PARSE_ERROR
	visuals = (visual_value as Dictionary).duplicate(true)
	battle_data = (battle_value as Dictionary).duplicate(true)
	visuals["format_version"] = int(visuals.get("format_version", 1))
	if not visuals.get("weathers") is Dictionary: visuals["weathers"] = {}
	if not battle_data.get("weather") is Dictionary: battle_data["weather"] = {}
	_normalize_loaded_turns()
	return OK

func _normalize_loaded_turns() -> void:
	for weather: Dictionary in visuals.get("weathers", {}).values():
		var overlay: Variant = weather.get("background_overlay")
		if overlay is Dictionary and overlay.has("turns"): overlay["turns"] = normalize_turns(overlay["turns"])
		for category: String in ["sprite_effects", "lighting_effects", "particle_effects", "turn_effects"]:
			for element: Dictionary in weather.get(category, []):
				if element.has("turns"): element["turns"] = normalize_turns(element["turns"])

func weather_names() -> PackedStringArray:
	var names := PackedStringArray()
	for key: Variant in visuals.get("weathers", {}).keys(): names.append(String(key))
	for key: Variant in battle_data.get("weather", {}).keys():
		if not names.has(String(key)): names.append(String(key))
	names.sort(); return names

func select_weather(name: String) -> bool:
	if not weather_names().has(name): return false
	selected_weather = name; selected_element = {}; selected_category = ""; element_undo_history.clear(); return true

func create_weather(name: String) -> PackedStringArray:
	var errors := PackedStringArray(); var cleaned := name.strip_edges()
	if cleaned.is_empty(): errors.append("Weather name is required.")
	if weather_names().has(cleaned): errors.append("Weather already exists.")
	if not errors.is_empty(): return errors
	visuals["weathers"][cleaned] = {}
	battle_data["weather"][cleaned] = {"duration":3}
	selected_weather = cleaned; selected_element = {}; selected_category = ""; dirty = true
	return errors

func definition() -> Dictionary:
	if selected_weather.is_empty(): return {}
	var weathers: Dictionary = visuals["weathers"]
	if not weathers.has(selected_weather): weathers[selected_weather] = {}
	return weathers[selected_weather]

func duration() -> int:
	return maxi(1, int(battle_data.get("weather", {}).get(selected_weather, {}).get("duration", 3)))

func set_duration(value: int) -> void:
	var weather_table: Dictionary = battle_data["weather"]
	if not weather_table.has(selected_weather): weather_table[selected_weather] = {}
	weather_table[selected_weather]["duration"] = maxi(1, value); dirty = true

func elements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []; var definition_value := definition()
	var overlay: Dictionary = definition_value.get("background_overlay", {})
	if not overlay.is_empty(): result.append({"category":"background_overlay", "element":overlay})
	for element: Dictionary in definition_value.get("sprite_effects", []): result.append({"category":"sprite_effect", "element":element})
	for element: Dictionary in definition_value.get("lighting_effects", []): result.append({"category":"lighting_effect", "element":element})
	for element: Dictionary in definition_value.get("particle_effects", []): result.append({"category":"particle_effect", "element":element})
	for element: Dictionary in definition_value.get("turn_effects", []): result.append({"category":"turn_effect", "element":element})
	var thought_sequence: Dictionary = definition_value.get("thought_sequence", {})
	if not thought_sequence.is_empty(): result.append({"category":"thought_sequence", "element":thought_sequence})
	return result

func add_element(category: String) -> Dictionary:
	_record_element_undo()
	var element: Dictionary
	match category:
		"background_overlay":
			element = {"asset":"res://assets/battle/weather/overlay_example.png", "opacity":0.3, "modulate":"#ffffff", "scale":1.0, "x_offset":0.0, "y_offset":0.0, "turns":"all"}; definition()["background_overlay"] = element
		"sprite_effect":
			element = {"asset_family":"sprite_example", "anchor":"RANDOM_GROUND", "x_offset":0.0, "y_offset":0.0, "mode":"ambient_spawn", "variant_mode":"random", "spawn_count":1, "spawn_interval":1.0, "lifetime":1.5, "scale":1.0, "turns":"all"}
			if not definition().has("sprite_effects"): definition()["sprite_effects"] = []
			definition()["sprite_effects"].append(element)
		"lighting_effect":
			element = {"type":"wash", "color":"#ffffff", "opacity":0.2, "count":1, "turns":"all"}
			if not definition().has("lighting_effects"): definition()["lighting_effects"] = []
			definition()["lighting_effects"].append(element)
		"particle_effect":
			element = {"type":"particle", "particle_sprite":"particle_example", "emit_rate":1.0, "emit_max_count":32, "particle_lifetime":1.0, "emitter_mode":"anchored", "emitter_anchor":"SCREEN_CENTER", "emitter_offset_x":0.0, "emitter_offset_y":0.0, "emitter_width":0.0, "emitter_height":0.0, "movement_mode":"fall", "speed":100.0, "horizontal_drift":0.0, "scale_min":1.0, "scale_max":1.0, "opacity_min":1.0, "opacity_max":1.0, "rotation_mode":"fixed", "rotation":0.0, "rotation_speed":0.0, "offscreen_margin":32.0, "turns":"all"}
			if not definition().has("particle_effects"): definition()["particle_effects"] = []
			definition()["particle_effects"].append(element)
		"thought_sequence":
			element = {"initial_delay":5.0, "interval":5.0, "sequences":[]}; definition()["thought_sequence"] = element
		_:
			element = {"type":"pulse", "color":"#ffffff", "opacity":0.15, "duration":0.5, "turns":"all"}
			if not definition().has("turn_effects"): definition()["turn_effects"] = []
			definition()["turn_effects"].append(element)
			category = "turn_effect"
	selected_element = element; selected_category = category; dirty = true; return element

func delete_selected() -> bool:
	if selected_element.is_empty(): return false
	_record_element_undo()
	var def: Dictionary = definition()
	if selected_category in ["background_overlay", "thought_sequence"]: def.erase(selected_category)
	else:
		var key: String = String({"sprite_effect":"sprite_effects", "lighting_effect":"lighting_effects", "particle_effect":"particle_effects", "turn_effect":"turn_effects"}.get(selected_category, ""))
		if key.is_empty(): return false
		var array: Array = def.get(key, []); var index := array.find(selected_element)
		if index < 0: return false
		array.remove_at(index)
	selected_element = {}; selected_category = ""; dirty = true; return true

func set_element_field(key: String, value: Variant) -> void:
	if selected_element.is_empty(): return
	if key == "thought_id" and value == null:
		_record_element_undo(); selected_element.erase("thought_id"); selected_element.erase("thought_low_alpha"); selected_element.erase("thought_high_alpha"); dirty = true; return
	if key == "turns": value = normalize_turns(value)
	if selected_category == "lighting_effect" and String(selected_element.get("type", "")) == "beam":
		if key == "start_x_offset": selected_element.erase("x_offset")
		elif key == "start_y_offset": selected_element.erase("y_offset")
	var existing: Variant = selected_element.get(key)
	if typeof(existing) == typeof(value) and existing == value: return
	_record_element_undo()
	selected_element[key] = value; dirty = true

func set_sprite_fade_cause(cause: String, enabled: bool) -> void:
	if selected_category != "sprite_effect" or not FADE_OUT_CAUSES.has(cause): return
	var causes: Array = selected_element.get("fade_out_causes", [String(selected_element.get("fade_out_trigger", "weather_ends"))]).duplicate()
	if enabled and not causes.has(cause): causes.append(cause)
	elif not enabled: causes.erase(cause)
	_record_element_undo(); selected_element["fade_out_causes"] = causes; selected_element.erase("fade_out_trigger"); dirty = true

func set_particle_emitter_mode(value: String) -> void:
	if selected_category != "particle_effect" or not value in ["anchored", "screen"]: return
	_record_element_undo(); selected_element["emitter_mode"] = value; selected_element.erase("emitter_space"); dirty = true

static func particle_emitter_mode(element: Dictionary) -> String:
	if element.has("emitter_mode"): return "screen" if String(element["emitter_mode"]) == "screen" else "anchored"
	return "screen" if String(element.get("emitter_space", "position")) == "global" else "anchored"

static func particle_movement_mode(element: Dictionary) -> String:
	return "right" if String(element.get("movement_mode", "fall")) == "horizontal" else String(element.get("movement_mode", "fall"))

func copy_selected() -> bool:
	if selected_element.is_empty(): return false
	copied_element = selected_element.duplicate(true); copied_category = selected_category; return true

func paste_copied() -> bool:
	if copied_element.is_empty() or copied_category.is_empty(): return false
	if copied_category in ["background_overlay", "thought_sequence"] and not definition().get(copied_category, {}).is_empty(): return false
	_record_element_undo()
	var pasted := copied_element.duplicate(true)
	if copied_category in ["background_overlay", "thought_sequence"]: definition()[copied_category] = pasted
	else:
		var key := String({"sprite_effect":"sprite_effects", "lighting_effect":"lighting_effects", "particle_effect":"particle_effects", "turn_effect":"turn_effects"}.get(copied_category, ""))
		if key.is_empty(): return false
		if not definition().has(key): definition()[key] = []
		definition()[key].append(pasted)
	selected_element = pasted; selected_category = copied_category; dirty = true; return true

func undo_element_change() -> bool:
	if element_undo_history.is_empty() or selected_weather.is_empty(): return false
	visuals["weathers"][selected_weather] = element_undo_history.pop_back()
	selected_element = {}; selected_category = ""; dirty = true; return true

func _record_element_undo() -> void:
	if selected_weather.is_empty(): return
	var snapshot := definition().duplicate(true)
	if not element_undo_history.is_empty() and element_undo_history[-1] == snapshot: return
	element_undo_history.append(snapshot)
	if element_undo_history.size() > 100: element_undo_history.pop_front()

func normalize_turns(value: Variant) -> Variant:
	if value is int: return value
	if value is float and value == floor(value): return int(value)
	if value is Array:
		var result: Array[int] = []
		for item: Variant in value:
			if item is int: result.append(item)
			elif item is float and item == floor(item): result.append(int(item))
			else: return value
		return result
	var cleaned := String(value).strip_edges()
	if cleaned.to_lower() == "all": return "all"
	if cleaned.is_valid_int(): return int(cleaned)
	var parsed: Variant = JSON.parse_string(cleaned)
	return normalize_turns(parsed) if parsed is Array else cleaned

func parse_turns(text: String) -> Variant:
	return normalize_turns(text)

static func turns_text(value: Variant) -> String:
	return JSON.stringify(value) if value is Array else str(value)

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray(); var maximum := duration()
	for entry: Dictionary in elements():
		var element: Dictionary = entry["element"]; var label := String(entry["category"])
		if element.has("turns") and not _valid_turns(element["turns"], maximum): errors.append("%s has invalid turns for duration %d: %s" % [label, maximum, JSON.stringify(element["turns"])])
		if label == "background_overlay":
			if not ResourceLoader.exists(String(element.get("asset", ""))): errors.append("Overlay asset is missing.")
			if float(element.get("scale", 1.0)) <= 0.0: errors.append("Overlay scale must be greater than zero.")
		if label == "sprite_effect" and sprite_variants(String(element.get("asset_family", ""))).is_empty(): errors.append("Sprite family has no indexed weather assets.")
		if label == "sprite_effect" and not ANCHORS.has(String(element.get("anchor", ""))): errors.append("Sprite anchor is unsupported.")
		if label == "sprite_effect":
			if not SPRITE_MODES.has(String(element.get("sprite_mode", "static"))): errors.append("Sprite mode is unsupported.")
			if not SPRITE_BEHAVIORS.has(String(element.get("mode", "persistent"))): errors.append("Sprite behavior is unsupported.")
			if String(element.get("sprite_mode", "static")) == "animated" and float(element.get("frame_duration", 0.25)) < 0.05: errors.append("Animated sprite frame duration must be at least 0.05 seconds.")
			if String(element.get("sprite_mode", "static")) == "scrolling" and not String(element.get("scroll_direction", "left")) in ["left", "right"]: errors.append("Scroll direction is unsupported.")
			if bool(element.get("signal_enabled", false)):
				var signal_low := float(element.get("signal_min_alpha", 0.12)); var signal_high := float(element.get("signal_max_alpha", element.get("opacity", 0.5)))
				if signal_low < 0.0 or signal_high > 1.0 or signal_high < signal_low: errors.append("Sprite signal alpha range is invalid.")
				if float(element.get("signal_rise_time", 0.3)) < 0.05 or float(element.get("signal_fall_time", 0.6)) < 0.05 or float(element.get("signal_interval", 2.5)) < 0.0 or float(element.get("signal_delay", 0.0)) < 0.0: errors.append("Sprite signal timing is invalid.")
			if float(element.get("fade_out_duration", 0.0)) < 0.0: errors.append("Sprite fade-out duration must be zero or greater.")
			if element.has("thought_id"):
				if String(element.get("thought_id", "")).strip_edges().is_empty(): errors.append("Sprite thought ID cannot be empty when enabled.")
				if float(element.get("thought_low_alpha", 0.08)) < 0.0 or float(element.get("thought_high_alpha", element.get("opacity", 0.55))) > 1.0 or float(element.get("thought_high_alpha", element.get("opacity", 0.55))) < float(element.get("thought_low_alpha", 0.08)): errors.append("Sprite thought alpha range is invalid.")
			for cause: Variant in element.get("fade_out_causes", [String(element.get("fade_out_trigger", "weather_ends"))]):
				if not FADE_OUT_CAUSES.has(String(cause)): errors.append("Sprite fade-out cause is unsupported.")
		if label in ["sprite_effect", "turn_effect"] and element.has("asset_family") and float(element.get("scale", 1.0)) <= 0.0: errors.append("Sprite scale must be greater than zero.")
		if label == "lighting_effect" and not LIGHT_TYPES.has(String(element.get("type", ""))): errors.append("Light type is unsupported.")
		if label == "lighting_effect" and String(element.get("type", "")) in ["orb", "heat_shimmer", "particles"] and not ANCHORS.has(String(element.get("anchor", ""))): errors.append("Spatial light anchor is unsupported.")
		if label == "lighting_effect" and String(element.get("type", "")) == "beam" and (not ANCHORS.has(String(element.get("start_anchor", element.get("anchor", "SCREEN_TOP")))) or not ANCHORS.has(String(element.get("end_anchor", "FIELD_CENTER")))): errors.append("Beam anchor is unsupported.")
		if label == "particle_effect":
			if String(element.get("type", "particle")) != "particle": errors.append("Particle type is unsupported.")
			if sprite_variants(String(element.get("particle_sprite", ""))).is_empty(): errors.append("Particle sprite family has no indexed weather assets.")
			if element.has("emitter_mode") and not String(element["emitter_mode"]) in ["anchored", "screen"]: errors.append("Particle emitter mode is unsupported.")
			elif not element.has("emitter_mode") and not String(element.get("emitter_space", "position")) in ["position", "global"]: errors.append("Particle emitter mode is unsupported.")
			if particle_emitter_mode(element) == "anchored" and not ANCHORS.has(String(element.get("emitter_anchor", ""))): errors.append("Particle emitter anchor is unsupported.")
			if not String(element.get("movement_mode", "fall")) in ["fall", "rise", "right", "left", "horizontal"]: errors.append("Particle movement mode is unsupported.")
			if not String(element.get("rotation_mode", "fixed")) in ["fixed", "random", "align_to_velocity"]: errors.append("Particle rotation mode is unsupported.")
			if float(element.get("emit_rate", 1.0)) < 0.0 or int(element.get("emit_max_count", 32)) < 0 or float(element.get("particle_lifetime", 1.0)) <= 0.0: errors.append("Particle emission values are invalid.")
			if float(element.get("scale_min", 1.0)) <= 0.0 or float(element.get("scale_max", 1.0)) < float(element.get("scale_min", 1.0)): errors.append("Particle scale range is invalid.")
			if float(element.get("opacity_min", 1.0)) < 0.0 or float(element.get("opacity_max", 1.0)) > 1.0 or float(element.get("opacity_max", 1.0)) < float(element.get("opacity_min", 1.0)): errors.append("Particle opacity range is invalid.")
			if float(element.get("offscreen_margin", 32.0)) < 0.0: errors.append("Particle offscreen margin must be zero or greater.")
			if not FLICKER_TYPES.has(String(element.get("flicker_type", "all"))): errors.append("Particle flicker type is unsupported.")
		if label == "turn_effect" and not String(element.get("type", "")) in ["pulse", "sprite_burst"]: errors.append("Turn effect type is unsupported.")
		if label == "thought_sequence":
			if float(element.get("initial_delay", element.get("interval", 5.0))) < 0.1 or float(element.get("interval", 5.0)) < 0.1: errors.append("Thought sequence timing must be at least 0.1 seconds.")
			var sequences: Variant = element.get("sequences", [])
			if not sequences is Array: errors.append("Thought sequences must be an array.")
			else:
				for sequence: Variant in sequences:
					if not sequence is Array: errors.append("Each thought sequence must be an array of steps."); continue
					for step: Variant in sequence:
						if not step is Dictionary or not step.get("targets", []) is Array or float(step.get("duration", 0.0)) < 0.05: errors.append("Thought sequence steps require target arrays and positive durations.")
	return errors

func _valid_turns(value: Variant, maximum: int) -> bool:
	if value is String and value == "all": return true
	if value is int or value is float: return float(value) == float(int(value)) and int(value) >= 1 and int(value) <= maximum
	if value is Array:
		if value.is_empty(): return false
		for item: Variant in value:
			if not (item is int or item is float) or float(item) != float(int(item)) or int(item) < 1 or int(item) > maximum: return false
		return true
	return false

func sprite_variants(family: String) -> PackedStringArray:
	var result := PackedStringArray(); var directory := DirAccess.open(WEATHER_ASSET_DIR)
	if directory == null or family.is_empty(): return result
	var regex := RegEx.new(); regex.compile("^%s_[0-9][0-9]\\.png$" % family.replace(".", "\\."))
	for filename: String in directory.get_files():
		if regex.search(filename) != null: result.append("%s/%s" % [WEATHER_ASSET_DIR, filename])
	result.sort(); return result

func overlay_assets() -> PackedStringArray:
	var result := PackedStringArray(); var directory := DirAccess.open(WEATHER_ASSET_DIR)
	if directory == null: return result
	for filename: String in directory.get_files():
		if filename.to_lower().ends_with(".png"): result.append("%s/%s" % [WEATHER_ASSET_DIR, filename])
	result.sort(); return result

func sprite_families() -> PackedStringArray:
	var result := PackedStringArray(); var directory := DirAccess.open(WEATHER_ASSET_DIR)
	if directory == null: return result
	var regex := RegEx.new(); regex.compile("^(.+)_([0-9][0-9])\\.png$")
	for filename: String in directory.get_files():
		var matched := regex.search(filename)
		if matched != null:
			var family := matched.get_string(1)
			if not result.has(family): result.append(family)
	result.sort(); return result

func eligible_move_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for move_id: Variant in battle_data.get("moves", {}).keys():
		if not String(battle_data["moves"][move_id].get("sets_weather", "")).is_empty(): result.append(String(move_id))
	result.sort(); return result

func assign_to_move(move_id: String) -> bool:
	if not eligible_move_ids().has(move_id) or selected_weather.is_empty(): return false
	battle_data["moves"][move_id]["sets_weather"] = selected_weather; dirty = true; return true

func save(visuals_path := VISUALS_PATH, battle_path := BATTLE_PATH) -> Error:
	var errors := validation_errors(); if not errors.is_empty(): return ERR_INVALID_DATA
	var visual_file := FileAccess.open(visuals_path, FileAccess.WRITE); if visual_file == null: return FileAccess.get_open_error()
	visual_file.store_string(JSON.stringify(visuals, "  ") + "\n"); visual_file.close()
	var battle_file := FileAccess.open(battle_path, FileAccess.WRITE); if battle_file == null: return FileAccess.get_open_error()
	battle_file.store_string(JSON.stringify(battle_data, "  ") + "\n"); battle_file.close(); dirty = false; return OK
