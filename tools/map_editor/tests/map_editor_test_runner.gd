extends SceneTree

const MapDocumentRef := preload("res://core/map_document.gd")
const MapValidatorRef := preload("res://core/map_validator.gd")
const MapGraphRef := preload("res://core/map_graph.gd")
const ConverterRef := preload("res://core/coordinate_converter.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var editor_root := ProjectSettings.globalize_path("res://").simplify_path()
	var project_root := editor_root.get_base_dir().get_base_dir()
	var maps := project_root.path_join("data/maps")
	_test_all_maps_parse(maps)
	_test_malformed_json()
	_test_unknown_and_numeric_preservation()
	_test_validation()
	_test_coordinates()
	_test_graph(maps)
	_test_eastern_route(maps, editor_root)
	if failures.is_empty():
		print("MAP_EDITOR_TESTS_PASSED")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _test_all_maps_parse(maps: String) -> void:
	for filename in MapSchema.REGION_FILES:
		var doc := MapDocumentRef.load_file(maps.path_join(filename))
		_check(doc.parse_error.is_empty(), "%s must parse: %s" % [filename, doc.parse_error])
		_check(MapValidatorRef.validate(doc).filter(func(i): return i.severity == "error").is_empty(), "%s must satisfy its typed schema." % filename)

func _test_malformed_json() -> void:
	var doc := MapDocumentRef.from_text('{"origin": [1, 2,}')
	_check(not doc.parse_error.is_empty(), "Malformed JSON must be rejected with a parse error.")

func _test_unknown_and_numeric_preservation() -> void:
	var source := '{"origin":[1.2500,0,2e1],"size":[10,10],"entry":[0,0.65,1],"return_warp":[0,0.12,2],"tall_grass_species":[],"grass_zones":[],"water_blocks":[],"tall_flowers":[],"trees":[],"future":{"untouched":5.000}}'
	var doc := MapDocumentRef.from_text(source, "western_rainforest_route.json")
	var output := doc.deterministic_json()
	_check(output.contains("1.2500") and output.contains("2e1") and output.contains("5.000"), "Untouched number lexemes must retain precision/exponent spelling.")
	_check(output.contains('"future"'), "Unknown fields must survive serialization.")
	var reparsed := MapDocumentRef.from_text(output, "western_rainforest_route.json")
	_check(doc.semantic_equivalent(reparsed), "Deterministic serialization must preserve JSON semantics.")

func _test_validation() -> void:
	var doc := MapDocumentRef.from_text('{"origin":[0,0],"size":[10,10]}', "western_rainforest_route.json")
	var issues := MapValidatorRef.validate(doc)
	_check(issues.any(func(i): return i.severity == "error" and i.path == "$.origin"), "Validation must locate malformed positional arrays.")
	_check(issues.any(func(i): return i.severity == "error" and i.path == "$.entry"), "Validation must locate missing required fields.")
	var links := MapDocumentRef.from_text('{"origin":[0,0,0],"size":[10,10],"entry":[0,0.65,1],"return_warp":[0,0.12,2],"tall_grass_species":[],"grass_zones":[],"water_blocks":[],"tall_flowers":[],"trees":[],"arrival_points":{"entry":[0,1]},"outdoor_connections":[{"id":"same","warp":"return_warp","destination_map":"x.json","arrival":"entry","reverse":"back"},{"id":"same","warp":"return_warp","destination_map":"x.json","arrival":"entry","reverse":"back"}]}', "western_rainforest_route.json")
	issues = MapValidatorRef.validate(links)
	_check(issues.any(func(i): return i.path == "$.arrival_points.entry"), "Validation must reject malformed serialized arrival points.")
	_check(issues.any(func(i): return i.message.contains("Duplicate connection id")), "Validation must reject duplicate connection ids.")
	_check(issues.any(func(i): return i.message.contains("Duplicate link")), "Validation must reject duplicate warp links.")

func _test_coordinates() -> void:
	var origin := Vector3(110, 0, 30)
	var local := Vector3(-7.2, 0.65, 0)
	var world := ConverterRef.local_to_world(local, origin)
	_check(world.is_equal_approx(Vector3(102.8, 0.65, 30)), "Local-to-world conversion must add origin on X/Y/Z.")
	_check(ConverterRef.world_to_local(world, origin).is_equal_approx(local), "Coordinate conversion must round trip.")
	var canvas := ConverterRef.world_xz_to_canvas(Vector3(2, 0, -3), 10, Vector2(100,100))
	_check(canvas == Vector2(120,70), "Canvas conversion must display negative Z as north/up.")
	_check(ConverterRef.canvas_to_world_xz(canvas,10,Vector2(100,100),0.65).is_equal_approx(Vector3(2,0.65,-3)), "Canvas conversion must round trip.")

func _test_graph(maps: String) -> void:
	var graph := MapGraphRef.scan(maps)
	_check(graph.maps.size() == 11, "Map index must resolve all eleven authored map files.")
	_check(graph.connections.size() == 5, "The serialized outdoor graph must expose five bidirectional connection pairs.")
	_check(graph.issues.is_empty(), "Current serialized warp graph must not contain missing, one-way, or duplicate endpoints.")

func _test_eastern_route(maps: String, editor_root: String) -> void:
	var source_path := maps.path_join("eastern_rainforest_route.json")
	var original := MapDocumentRef.load_file(source_path)
	_check(original.data.get("trees", []) is Array, "Eastern route tree data must remain readable after user edits.")
	var original_flower_count: int = original.data.get("tall_flowers", []).size()
	_check(original_flower_count >= 0, "Eastern route tall-flower data must be readable after user edits.")
	_check(original.data.get("rare_torch_ginger", []) is Array, "Eastern route torch-ginger data must remain readable after user edits.")
	_check(original.data.get("water_blocks", []) is Array, "Eastern route water-block data must remain readable after user edits.")
	_check(original.data.get("grass_zones", []) is Array, "Eastern route grass-zone data must remain readable after user edits.")
	for marker in ["entry", "return_warp", "cave_warp", "cave_return"]: _check(original.data.has(marker), "Eastern route must show %s." % marker)
	var generated_dir := editor_root.path_join("tests/generated")
	DirAccess.make_dir_recursive_absolute(generated_dir)
	var no_edit_path := generated_dir.path_join("eastern_no_edit.json")
	var error := original.save_atomic(no_edit_path, MapValidatorRef.validate(original))
	_check(error == OK, "No-edit eastern route save must succeed atomically.")
	var no_edit := MapDocumentRef.load_file(no_edit_path)
	_check(original.semantic_equivalent(no_edit), "No-edit save must be semantically equivalent.")
	var edited := MapDocumentRef.load_file(source_path)
	var old_x := float(edited.data.trees[0][0])
	edited.set_value("$.trees[0][0]", old_x + 0.5)
	edited.data.tall_flowers.append([3.0, 0.35, 7.0])
	edited.dirty = true
	var edited_path := generated_dir.path_join("eastern_edited.json")
	error = edited.save_atomic(edited_path, MapValidatorRef.validate(edited))
	if error != OK:
		print("EDITED_SAVE_ERROR=", error, " parse=", edited.parse_error, " validation=", MapValidatorRef.validate(edited), " json=", edited.deterministic_json())
	_check(error == OK, "Edited eastern route save must succeed.")
	var reloaded := MapDocumentRef.load_file(edited_path)
	if reloaded.parse_error.is_empty():
		_check(is_equal_approx(float(reloaded.data.trees[0][0]), old_x + 0.5), "Moved tree must persist after reload.")
		_check(reloaded.data.tall_flowers.size() == original_flower_count + 1 and reloaded.data.tall_flowers[-1] == [3.0,0.35,7.0], "Added flower must persist after reload.")
	else:
		_check(false, "Edited route must reload: " + reloaded.parse_error)
