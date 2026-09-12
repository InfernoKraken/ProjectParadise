class_name FakemonEditorModel
extends RefCounted

const BASE_FILE := "data/battle_data.json"
const EVOLVED_FILE := "data/evolved_fakemon.json"
const EGGS_FILE := "data/egg_groups.json"
const MAPS_DIR := "data/maps"
const STAT_KEYS := [&"max_hp", &"attack", &"defense", &"special_attack", &"special_defense", &"speed"]

var game_root: String
var battle_data: Dictionary = {}
var evolved_data: Array = []
var egg_data: Dictionary = {}
var selected_name := ""
var draft: Dictionary = {}
var original: Dictionary = {}
var selected_source := ""
var error := ""
var evolution_target_name := ""
var evolution_level := 0
var original_evolution_target_name := ""
var original_evolution_level := 0
var original_egg_groups: Array = []
var encounter_documents: Dictionary = {}
var original_encounter_documents: Dictionary = {}

func _init(root := "") -> void:
	game_root = root if not root.is_empty() else ProjectSettings.globalize_path("res://../..").simplify_path()

func load_all() -> bool:
	error = ""
	var base_value: Variant = _read_json(BASE_FILE)
	var evolved_value: Variant = _read_json(EVOLVED_FILE)
	var eggs_value: Variant = _read_json(EGGS_FILE)
	if not base_value is Dictionary or not base_value.get("fakemon", []) is Array:
		error = "battle_data.json has no Fakemon array."
		return false
	if not evolved_value is Array:
		error = "evolved_fakemon.json must contain an array."
		return false
	if not eggs_value is Dictionary:
		error = "egg_groups.json must contain an object."
		return false
	battle_data = base_value
	evolved_data = evolved_value
	egg_data = eggs_value
	_load_encounter_documents()
	return true

func all_species() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in battle_data.get("fakemon", []):
		if value is Dictionary: result.append(value)
	for value: Variant in evolved_data:
		if value is Dictionary: result.append(value)
	return result

func species_names() -> Array[String]:
	var result: Array[String] = []
	for mon in all_species(): result.append(String(mon.get("name", "")))
	return result

func select_species(species_name: String) -> bool:
	for mon in all_species():
		if String(mon.get("name", "")) == species_name:
			selected_name = species_name
			selected_source = EVOLVED_FILE if evolved_data.has(mon) else BASE_FILE
			original = mon.duplicate(true)
			draft = mon.duplicate(true)
			var target := evolution_target()
			evolution_target_name = String(target.get("name", ""))
			evolution_level = int(target.get("evolution_level", 0))
			original_evolution_target_name = evolution_target_name
			original_evolution_level = evolution_level
			original_egg_groups = egg_groups_for(species_name)
			return true
	return false

func is_dirty() -> bool:
	return draft != original or evolution_target_name != original_evolution_target_name or evolution_level != original_evolution_level or egg_groups_for() != original_egg_groups

func bst(mon := {}) -> int:
	var source: Dictionary = draft if mon.is_empty() else mon
	var total := 0
	for key in STAT_KEYS: total += int(source.get(key, 0))
	return total

func types_catalog() -> Array[String]:
	var result: Array[String] = []
	for attack_type: Variant in battle_data.get("type_chart", {}).keys():
		result.append(String(attack_type))
	if result.is_empty():
		for move: Variant in battle_data.get("moves", {}).values():
			if move is Dictionary:
				var type_name := String(move.get("type", ""))
				if not type_name.is_empty() and not result.has(type_name): result.append(type_name)
	result.sort()
	return result

func move_catalog() -> Dictionary:
	return battle_data.get("moves", {})

func egg_groups_for(species_name := "") -> Array:
	var name := selected_name if species_name.is_empty() else species_name
	return egg_data.get("assignments", {}).get(name, egg_data.get("default_groups", [])).duplicate()

func set_egg_groups(groups: Array) -> void:
	if not egg_data.has("assignments"): egg_data["assignments"] = {}
	egg_data["assignments"][selected_name] = groups.duplicate()

func evolution_target() -> Dictionary:
	for mon in evolved_data:
		if String(mon.get("evolves_from", "")) == selected_name: return mon
	return {}

func validate() -> Array[String]:
	var issues: Array[String] = []
	var name := String(draft.get("name", "")).strip_edges()
	if name.is_empty(): issues.append("Name is required.")
	var occurrences := 0
	for mon in all_species():
		if String(mon.get("name", "")).to_lower() == name.to_lower(): occurrences += 1
	if name.to_lower() != selected_name.to_lower() and occurrences > 0: issues.append("Duplicate Fakemon name: %s." % name)
	for key in STAT_KEYS:
		if int(draft.get(key, 0)) < 1: issues.append("%s must be positive." % String(key))
	var types := _types_of(draft)
	if types.is_empty() or types.size() > 2: issues.append("A Fakemon must have one or two types.")
	var known_moves: Dictionary = move_catalog()
	for entry: Variant in draft.get("learnset", []):
		if not entry is Dictionary or not known_moves.has(String(entry.get("move", ""))): issues.append("Learnset contains a missing move reference.")
		elif int(entry.get("level", 0)) < 1: issues.append("Learnset levels must be positive.")
	if selected_source == BASE_FILE:
		var moves: Array = draft.get("moves", [])
		if moves.is_empty() or moves.size() > 6: issues.append("Starting moves must contain 1 to 6 moves.")
		for move_id in moves:
			if not known_moves.has(String(move_id)): issues.append("Starting moves contain missing move '%s'." % move_id)
	else:
		var source := String(draft.get("moveset_source", ""))
		if source.is_empty() or not species_names().has(source): issues.append("Moveset source is missing or invalid.")
	var groups := egg_groups_for()
	if groups.size() != 2: issues.append("Exactly two egg groups are required by runtime validation.")
	for group in groups:
		if not egg_data.get("groups", []).has(group): issues.append("Unknown egg group '%s'." % group)
	for path in sprite_paths(draft).values():
		if not FileAccess.file_exists(path): issues.append("Missing sprite: %s" % path)
	return issues

func save_selected() -> bool:
	if not is_dirty(): return true
	var blocking := validate().filter(func(issue: String): return not issue.begins_with("Missing sprite:"))
	if not blocking.is_empty():
		error = "\n".join(blocking)
		return false
	var collection: Array = battle_data["fakemon"] if selected_source == BASE_FILE else evolved_data
	var index := -1
	for i in collection.size():
		if String(collection[i].get("name", "")) == selected_name: index = i; break
	if index < 0: error = "Selected Fakemon no longer exists."; return false
	var old_name := selected_name
	collection[index] = draft.duplicate(true)
	var evolution_changed := evolution_target_name != original_evolution_target_name or evolution_level != original_evolution_level
	if evolution_target_name != original_evolution_target_name:
		if not original_evolution_target_name.is_empty():
			var old_target := _species_dictionary(original_evolution_target_name)
			if not old_target.is_empty(): old_target.erase("evolves_from"); old_target.erase("evolution_level")
		if not evolution_target_name.is_empty():
			var new_target := _species_dictionary(evolution_target_name)
			if new_target.is_empty() or not evolved_data.has(new_target): error = "Evolution targets must be species stored in evolved_fakemon.json."; return false
			new_target["evolves_from"] = String(draft.name)
			new_target["evolution_level"] = evolution_level
	elif not evolution_target_name.is_empty():
		var same_target := _species_dictionary(evolution_target_name)
		if not same_target.is_empty(): same_target["evolution_level"] = evolution_level
	if old_name != String(draft.name):
		var assignments: Dictionary = egg_data.get("assignments", {})
		var groups: Array = assignments.get(old_name, original_egg_groups).duplicate()
		assignments.erase(old_name)
		assignments[String(draft.name)] = groups
	var eggs_changed := egg_groups_for(old_name) != original_egg_groups or old_name != String(draft.name)
	if selected_source == BASE_FILE and not _write_json(BASE_FILE, battle_data): return false
	if (selected_source == EVOLVED_FILE or evolution_changed) and not _write_json(EVOLVED_FILE, evolved_data): return false
	if eggs_changed and not _write_json(EGGS_FILE, egg_data): return false
	selected_name = String(draft.name)
	original = draft.duplicate(true)
	original_evolution_target_name = evolution_target_name
	original_evolution_level = evolution_level
	original_egg_groups = egg_groups_for()
	return true

func add_species(species_name: String) -> bool:
	var clean := species_name.strip_edges()
	if clean.is_empty() or species_names().map(func(v): return v.to_lower()).has(clean.to_lower()): return false
	var starter_move := String(move_catalog().keys()[0]) if not move_catalog().is_empty() else ""
	var created := {"name":clean,"art_id":clean,"male_ratio":0.5,"type":types_catalog()[0] if not types_catalog().is_empty() else "Normal","level":5,"max_hp":50,"attack":50,"defense":50,"special_attack":50,"special_defense":50,"speed":50,"color":"7ebf78","size":"1 m","description":"","catch_rate":75,"base_exp":64,"moves":[starter_move],"learnset":[{"level":1,"move":starter_move}]}
	battle_data["fakemon"].append(created)
	if not egg_data.has("assignments"): egg_data["assignments"] = {}
	egg_data.assignments[clean] = egg_data.get("default_groups", ["Mineral", "Mineral"]).duplicate()
	select_species(clean)
	return true

func remove_selected() -> bool:
	var collection: Array = battle_data["fakemon"] if selected_source == BASE_FILE else evolved_data
	for i in collection.size():
		if String(collection[i].get("name", "")) == selected_name:
			collection.remove_at(i)
			egg_data.get("assignments", {}).erase(selected_name)
			selected_name = ""; draft = {}; original = {}
			return _write_json(BASE_FILE, battle_data) and _write_json(EVOLVED_FILE, evolved_data) and _write_json(EGGS_FILE, egg_data)
	return false

func found_in(species_name := "") -> Array[Dictionary]:
	var wanted := selected_name if species_name.is_empty() else species_name
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(_absolute(MAPS_DIR))
	if directory == null: return result
	for filename in directory.get_files():
		if not filename.ends_with(".json") or filename.ends_with(".bak") or filename == "map_index.json": continue
		var data: Variant = _read_json(MAPS_DIR + "/" + filename)
		if not data is Dictionary: continue
		_scan_encounters(data, filename.get_basename(), wanted, result)
	return result

func encounter_maps() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for filename in encounter_documents:
		var data: Dictionary = encounter_documents[filename]
		if data.get("grass_zones", []).is_empty() and not data.get("wild_zone") is Dictionary: continue
		var metadata: Dictionary = data.get("map_metadata", {})
		result.append({"file":filename,"name":String(metadata.get("display_name",filename.get_basename())).replace("_"," ").capitalize()})
	result.sort_custom(func(a,b):return a.name<b.name)
	return result

func encounter_for(filename:String,species_name:="")->Dictionary:
	var wanted:=selected_name if species_name.is_empty() else species_name
	var data:Dictionary=encounter_documents.get(filename,{})
	for value:Variant in data.get("tall_grass_species",[]):
		if value is Dictionary and String(value.get("fakemon",""))==wanted:return {"assigned":true,"level":int(value.get("level",5))}
		if value is String and String(value)==wanted:return {"assigned":true,"level":int(draft.get("level",5))}
	return {"assigned":false,"level":int(draft.get("level",5))}

func set_encounter(filename:String,assigned:bool,level:int)->void:
	var data:Dictionary=encounter_documents.get(filename,{})
	var entries:Array=data.get("tall_grass_species",[])
	for i in range(entries.size()-1,-1,-1):
		var value:Variant=entries[i];var name:=String(value.get("fakemon","")) if value is Dictionary else String(value)
		if name==selected_name:entries.remove_at(i)
	if assigned:entries.append({"fakemon":selected_name,"level":clampi(level,1,100)})
	data["tall_grass_species"]=entries

func encounters_dirty()->bool:return encounter_documents!=original_encounter_documents

func save_encounters()->bool:
	for filename in encounter_documents:
		if encounter_documents[filename]==original_encounter_documents.get(filename,{}):continue
		var path:=_absolute(MAPS_DIR+"/"+filename);var temp:=path+".tmp";var backup:=path+".bak"
		var file:=FileAccess.open(temp,FileAccess.WRITE)
		if file==null:error="Could not stage map %s."%filename;return false
		file.store_string(JSON.stringify(encounter_documents[filename],"  ")+"\n");file.close()
		if JSON.parse_string(FileAccess.get_file_as_string(temp))==null:DirAccess.remove_absolute(temp);error="Map validation failed for %s."%filename;return false
		if FileAccess.file_exists(path):
			if FileAccess.file_exists(backup):DirAccess.remove_absolute(backup)
			if DirAccess.copy_absolute(path,backup)!=OK:DirAccess.remove_absolute(temp);error="Could not back up %s."%filename;return false
		if DirAccess.rename_absolute(temp,path)!=OK:error="Could not replace %s."%filename;return false
	original_encounter_documents=encounter_documents.duplicate(true);return true

func discard_encounters()->void:encounter_documents=original_encounter_documents.duplicate(true)

func sprite_paths(mon := {}) -> Dictionary:
	var source: Dictionary = draft if mon.is_empty() else mon
	var art := String(source.get("art_id", ""))
	return {"player":_absolute("assets/fakemon/battle/%s_Player.png" % art),"wild":_absolute("assets/fakemon/battle/%s_Wild.png" % art),"follow":_absolute("assets/fakemon/overworld/%s_Follow_Down.png" % art)}

func _scan_encounters(value: Variant, map_name: String, wanted: String, output: Array[Dictionary], inherited_species: Array = []) -> void:
	if value is Dictionary:
		var defaults: Array = value.get("tall_grass_species", inherited_species)
		if value.has("grass_zones"):
			for zone: Variant in value.grass_zones:
				if zone is Dictionary:
					var species: Array = zone.get("species", defaults)
					for entry:Variant in species:
						var entry_name:=String(entry.get("fakemon","")) if entry is Dictionary else String(entry)
						if entry_name==wanted:output.append({"map":map_name,"terrain":"Tall Grass","level":int(entry.get("level",5)) if entry is Dictionary else int(draft.get("level",5)),"chance":float(zone.get("encounter_chance",0.2))});break
		for child in value.values():
			if child is Dictionary or child is Array: _scan_encounters(child, map_name, wanted, output, defaults)
	elif value is Array:
		for child in value:
			if child is Dictionary or child is Array: _scan_encounters(child, map_name, wanted, output, inherited_species)

func _types_of(mon: Dictionary) -> Array:
	if mon.get("types") is Array: return mon.types
	var one := String(mon.get("type", "")); return [] if one.is_empty() else [one]

func _species_dictionary(species_name: String) -> Dictionary:
	for mon in all_species():
		if String(mon.get("name", "")) == species_name: return mon
	return {}

func _absolute(relative: String) -> String: return game_root.path_join(relative).simplify_path()
func _load_encounter_documents()->void:
	encounter_documents.clear();var directory:=DirAccess.open(_absolute(MAPS_DIR));if directory==null:return
	for filename in directory.get_files():
		if not filename.ends_with(".json") or filename=="map_index.json":continue
		var value:Variant=_read_json(MAPS_DIR+"/"+filename)
		if value is Dictionary:encounter_documents[filename]=value
	original_encounter_documents=encounter_documents.duplicate(true)
func _read_json(relative: String) -> Variant:
	var path := _absolute(relative)
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
func _write_json(relative: String, value: Variant) -> bool:
	var file := FileAccess.open(_absolute(relative), FileAccess.WRITE)
	if file == null: error = "Could not write %s." % relative; return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	return true
