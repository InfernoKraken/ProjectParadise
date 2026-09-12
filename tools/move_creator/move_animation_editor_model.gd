class_name MoveAnimationEditorModel
extends RefCounted

const CONTEXTUAL_ASSETS := preload("res://battle/move_animation/contextual_move_effect_resolver.gd")

const EFFECT_DIR := "res://assets/move_effects"
const WEATHER_DIR := "res://assets/battle/weather"
const IMPORT_DIRS := [EFFECT_DIR, WEATHER_DIR]
const TYPES := ["spawn_sprite", "impact_sprite", "beam", "vertical_sprite", "move_sprite", "fade_sprite", "destroy_sprite", "shake_battler", "move_battler", "scale_battler", "background_tint", "restore_background", "marker"]
const TYPE_LABELS := {"spawn_sprite":"Spawn Sprite", "impact_sprite":"Impact Sprite", "beam":"Beam", "vertical_sprite":"Vertical Sprite", "move_sprite":"Move Sprite", "fade_sprite":"Fade Sprite", "destroy_sprite":"Destroy Sprite", "shake_battler":"Shake Battler", "move_battler":"Move Battler", "scale_battler":"Scale Battler", "background_tint":"Background Tint", "restore_background":"Restore Background", "marker":"Marker"}

var document := MoveAnimationDefinition.from_dictionary({"format_version": 1, "id": "new_animation", "duration": 0.5, "events": []})
var selected_event: Dictionary = {}

func load_document(source: MoveAnimationDefinition) -> void:
	document = MoveAnimationDefinition.from_dictionary(source.data)
	sort_events()
	selected_event = document.data["events"][0] if not document.data["events"].is_empty() else {}

func add_event(type: String) -> Dictionary:
	var event := default_event(type, document.duration())
	document.data["events"].append(event)
	selected_event = event
	sort_events()
	return event

func delete_selected() -> bool:
	if selected_event.is_empty(): return false
	var events: Array = document.data["events"]
	var index := events.find(selected_event)
	if index < 0: return false
	events.remove_at(index)
	selected_event = events[mini(index, events.size() - 1)] if not events.is_empty() else {}
	_recalculate_duration()
	return true

func copy_selected_event_json() -> String:
	return "" if selected_event.is_empty() else JSON.stringify(selected_event)

func paste_event_json(text: String) -> bool:
	if not text.strip_edges().begins_with("{"): return false
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not TYPES.has(String(parsed.get("type", ""))): return false
	var event := (parsed as Dictionary).duplicate(true)
	document.data["events"].append(event)
	selected_event = event
	sort_events()
	return true

func import_effect_asset(source_path: String) -> Dictionary:
	if source_path.get_extension().to_lower() != "png": return {"error": ERR_INVALID_PARAMETER, "message": "Only PNG files can be imported."}
	var source_absolute := ProjectSettings.globalize_path(source_path)
	var image := Image.load_from_file(source_absolute)
	if image == null or image.is_empty(): return {"error": ERR_FILE_CORRUPT, "message": "The selected file is not a readable PNG."}
	var destination := "%s/%s" % [EFFECT_DIR, source_path.get_file()]
	var destination_absolute := ProjectSettings.globalize_path(destination)
	if source_absolute.simplify_path().to_lower() != destination_absolute.simplify_path().to_lower():
		if FileAccess.file_exists(destination): return {"error": ERR_ALREADY_EXISTS, "message": "%s already exists; rename the source PNG to avoid overwriting it." % destination.get_file()}
		var copy_error := DirAccess.copy_absolute(source_absolute, destination_absolute)
		if copy_error != OK: return {"error": copy_error, "message": "Could not copy the PNG: %s" % error_string(copy_error)}
	return {"error": OK, "message": "Imported %s" % destination.get_file(), "path": destination}

func effect_import_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for path: String in import_asset_paths():
		if not path.to_lower().ends_with(".png"): continue
		var has_metadata := FileAccess.file_exists(path + ".import")
		var loadable := has_metadata and ResourceLoader.exists(path, "Texture2D") and ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE) is Texture2D
		var status := "Imported" if loadable else ("Import Error" if has_metadata else "Missing Import")
		result.append({"filename":path.get_file(),"path":path,"status":status,"warning":asset_naming_warning(path),"imported":loadable})
	return result

func import_asset_paths() -> PackedStringArray:
	var result := PackedStringArray()
	for directory_path: String in IMPORT_DIRS:
		var directory := DirAccess.open(directory_path)
		if directory == null: continue
		directory.list_dir_begin()
		var filename := directory.get_next()
		while not filename.is_empty():
			if not directory.current_is_dir() and filename.to_lower().ends_with(".png"): result.append("%s/%s" % [directory_path, filename])
			filename = directory.get_next()
		directory.list_dir_end()
	result.sort()
	return result

func asset_naming_warning(path: String) -> String:
	if path.begins_with(WEATHER_DIR + "/"):
		var filename := path.get_file()
		var warnings := PackedStringArray()
		if " " in filename: warnings.append("Contains spaces")
		for character in filename:
			if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.- ": warnings.append("Contains suspicious characters");break
		return "; ".join(warnings)
	return effect_naming_warning(path.get_file())

func effect_naming_warning(filename: String) -> String:
	var warnings := PackedStringArray()
	if not filename.begins_with("Attack_") and not filename.begins_with("Orb_"): warnings.append("Does not begin with Attack_ or Orb_")
	if " " in filename: warnings.append("Contains spaces")
	for character in filename:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.- ": warnings.append("Contains suspicious characters");break
	return "; ".join(warnings)

func trigger_godot_import() -> Dictionary:
	var output: Array = []
	var arguments := PackedStringArray(["--headless","--editor","--path",ProjectSettings.globalize_path("res://"),"--import"])
	var exit_code := OS.execute(OS.get_executable_path(),arguments,output,true)
	return {"error":OK if exit_code==0 else FAILED,"exit_code":exit_code,"output":"\n".join(output)}

func set_event_time(event: Dictionary, time: float) -> void:
	event["time"] = maxf(0.0, time)
	selected_event = event
	sort_events()

func sort_events() -> void:
	var events: Array = document.data["events"]
	events.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("time", 0.0)) < float(b.get("time", 0.0)))
	_recalculate_duration()

func spawn_instance_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for event: Dictionary in document.data.get("events", []):
		if String(event.get("type", "")) in ["spawn_sprite", "impact_sprite", "beam", "vertical_sprite"] and not String(event.get("instance_id", "")).is_empty(): result.append(String(event["instance_id"]))
	return result

func effect_assets() -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(EFFECT_DIR)
	if directory == null: return result
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.to_lower().ends_with(".png"): result.append("%s/%s" % [EFFECT_DIR, filename])
		filename = directory.get_next()
	directory.list_dir_end(); result.append_array(CONTEXTUAL_ASSETS.aliases()); result.sort(); return result

func discover_animations(directory_path := "res://data/move_animations") -> Dictionary:
	var result := {"ids": PackedStringArray(), "paths": {}, "warnings": PackedStringArray()}
	var directory := DirAccess.open(directory_path)
	if directory == null:
		result["warnings"].append("Animation directory is unavailable: %s" % directory_path)
		return result
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.to_lower().ends_with(".json"):
			var path := "%s/%s" % [directory_path, filename]
			var definition := MoveAnimationDefinition.load_file(path)
			if definition == null:
				result["warnings"].append("Could not parse animation file: %s" % filename)
			else:
				var errors := definition.validation_errors()
				if errors.is_empty():
					var animation_id := String(definition.data["id"])
					result["ids"].append(animation_id); result["paths"][animation_id] = path
				else: result["warnings"].append("Invalid animation file %s: %s" % [filename, errors[0]])
		filename = directory.get_next()
	directory.list_dir_end(); result["ids"].sort(); return result

func event_summary(event: Dictionary) -> String:
	var detail := ""
	match String(event.get("type", "")):
		"spawn_sprite", "move_sprite", "fade_sprite", "destroy_sprite": detail = String(event.get("instance_id", ""))
		"impact_sprite": detail = String(event.get("instance_id", event.get("position", {}).get("battler", "target")))
		"beam", "vertical_sprite": detail = String(event.get("instance_id", ""))
		"marker": detail = String(event.get("name", ""))
		"shake_battler", "move_battler", "scale_battler": detail = String(event.get("battler", ""))
	return "%5.2f  %-20s %s" % [float(event.get("time", 0.0)), TYPE_LABELS.get(String(event.get("type", "")), "Unknown"), detail]

func validation_text() -> String:
	var errors := document.validation_errors()
	return "Valid — ready to preview/save." if errors.is_empty() else "Error\n" + "\n".join(errors)

func preview_anchor_warnings(repository: GeneratedAnchorRepository, profiles: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for event: Dictionary in document.data.get("events", []):
		var positions: Array = []
		if String(event.get("type", "")) in ["spawn_sprite", "impact_sprite", "vertical_sprite"]: positions.append(event.get("position", {}))
		elif String(event.get("type", "")) == "beam": positions.append(event.get("from", {})); positions.append(event.get("to", {}))
		elif String(event.get("type", "")) == "move_sprite": positions.append(event.get("to", {}))
		for position: Dictionary in positions:
			var battler := String(position.get("battler", "user")); var anchor := String(position.get("anchor", "origin")); var profile: Dictionary = profiles.get(battler, {}); var art := String(profile.get("art_id", "")); var side := String(profile.get("side", "Player"))
			if repository.has_battle_anchor(art, side, anchor): continue
			var message := "Preview: %s.%s unavailable on %s; using origin." % [battler, anchor, art] if repository.has_battle_anchor(art, side, "origin") else "Preview warning: %s has no origin; using processed sprite center." % art
			if not result.has(message): result.append(message)
	return result

static func default_event(type: String, time := 0.0) -> Dictionary:
	match type:
		"spawn_sprite": return {"time":time,"type":type,"instance_id":"effect","asset":"res://assets/move_effects/TestAirBlast.png","sprite_sheet":null,"position":{"battler":"user","anchor":"origin","offset":[0,0]},"scale":1.0,"rotation":0.0,"opacity":1.0,"tint":"#FFFFFF","is_behind":false}
		"impact_sprite": return {"time":time,"type":type,"instance_id":"impact","asset":"res://assets/move_effects/TestFlame.png","sprite_sheet":null,"position":{"battler":"target","anchor":"origin","offset":[0,0]},"scale":1.0,"rotation":0.0,"opacity":1.0,"tint":"#FFFFFF","is_behind":false,"duration":0.3}
		"beam": return {"time":time,"type":type,"instance_id":"beam","from":{"battler":"user","anchor":"origin","offset":[0,0]},"to":{"battler":"target","anchor":"origin","offset":[0,0]},"width":20.0,"asset":"res://assets/move_effects/Attack_Beam_Light.png","opacity":1.0,"tint":"#FFFFFF","duration":0.5,"layer":"above_battlers"}
		"vertical_sprite": return {"time":time,"type":type,"instance_id":"vertical_effect","asset":"res://assets/move_effects/Attack_Particle_Leaf_Fall.png","position":{"battler":"target","anchor":"origin","offset":[0,0]},"mode":"fall_to_anchor","distance":120.0,"duration":0.6,"scale":1.0,"rotation":0.0,"opacity":1.0,"tint":"#FFFFFF","is_behind":false}
		"move_sprite": return {"time":time,"type":type,"instance_id":"","to":{"battler":"target","anchor":"origin","offset":[0,0]},"duration":0.3,"easing":"linear"}
		"fade_sprite": return {"time":time,"type":type,"instance_id":"","opacity":0.0,"duration":0.25}
		"destroy_sprite": return {"time":time,"type":type,"instance_id":""}
		"shake_battler": return {"time":time,"type":type,"battler":"target","duration":0.2,"magnitude":8.0}
		"move_battler": return {"time":time,"type":type,"battler":"user","direction":"toward_target","distance":60.0,"duration":0.2}
		"scale_battler": return {"time":time,"type":type,"battler":"user","mode":"stretch","scale_delta_percent":50.0,"loops":1,"loop_duration":0.4}
		"background_tint": return {"time":time,"type":type,"color":"#663399","opacity":0.4,"duration":0.15}
		"restore_background": return {"time":time,"type":type,"duration":0.2}
		"marker": return {"time":time,"type":type,"name":"impact"}
	return {"time":time,"type":type}

func _recalculate_duration() -> void:
	var duration := float(document.data.get("duration", 0.0))
	for event: Dictionary in document.data.get("events", []):
		var event_duration := float(event.get("loop_duration", 0.0)) * int(event.get("loops", 0)) if String(event.get("type", "")) == "scale_battler" else maxf(float(event.get("duration", 0.0)), 0.0)
		duration = maxf(duration, float(event.get("time", 0.0)) + event_duration)
	document.data["duration"] = duration
