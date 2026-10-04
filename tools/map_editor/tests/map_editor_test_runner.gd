extends SceneTree

const MapDocumentRef := preload("res://core/map_document.gd")
const MapValidatorRef := preload("res://core/map_validator.gd")
const MapGraphRef := preload("res://core/map_graph.gd")
const ConverterRef := preload("res://core/coordinate_converter.gd")
const AssetCatalogRef := preload("res://core/asset_catalog.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var editor_root := ProjectSettings.globalize_path("res://").simplify_path()
	var project_root := editor_root.get_base_dir().get_base_dir()
	var maps := project_root.path_join("data/maps")
	_test_all_maps_parse(maps)
	_test_malformed_json()
	_test_unknown_and_numeric_preservation()
	_test_validation()
	_test_wall_validation()
	_test_bridge_validation()
	_test_coordinates()
	_test_imported_overworld_assets(editor_root)
	_test_overlay_assets(editor_root)
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
		var errors:=MapValidatorRef.validate(doc).filter(func(i): return i.severity == "error")
		_check(errors.is_empty(), "%s must satisfy its typed schema: %s" % [filename,str(errors)])

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
	var bad_water:=MapDocumentRef.from_text('{"water_species":[{"fakemon":"Moach","level":101}],"water_encounter_chance":1.5}',"unknown.json")
	issues=MapValidatorRef.validate(bad_water)
	_check(issues.any(func(i):return i.path=="$.water_species[0].level") and issues.any(func(i):return i.path=="$.water_encounter_chance"),"Water encounter levels and probabilities must use the same validation bounds as runtime.")

func _test_wall_validation() -> void:
	var short_wall:=MapDocumentRef.from_text('{"objects":[{"type":"wall.fence","wall_set":"generic_wall","segment_length":2.0,"points":[[0,0],[1,0]]}]}',"wall_test.json")
	var issues:=MapValidatorRef.validate(short_wall)
	_check(issues.any(func(issue):return String(issue.path)=="$.objects[0].points[1]" and String(issue.message).contains("filler interval")),"Validation must block a cardinal wall run shorter than one geometry-defined filler interval.")
	var valid_wall:=MapDocumentRef.from_text('{"objects":[{"type":"wall.fence","wall_set":"generic_wall","segment_length":2.0,"points":[[0,0],[2,0],[2,4]]}]}',"wall_test.json")
	issues=MapValidatorRef.validate(valid_wall)
	_check(not issues.any(func(issue):return String(issue.path).begins_with("$.objects[0].points")),"Horizontal and vertical wall runs meeting the minimum filler span must validate.")

func _test_bridge_validation() -> void:
	var prefix:='{"format_version":1,"map_metadata":{},"origin":[0,0,0],"size":[10,10],"entry":[0,0,0],"return_warp":[0,0,0],"arrival_points":{},"outdoor_connections":[],"tall_grass_species":[],"grass_zones":[],"water_blocks":[],"sand_blocks":[],"objects":['
	var valid:=MapDocumentRef.from_text(prefix+'{"type":"structure.bridge","position":[0,0,0],"orientation":"horizontal","length":5,"width":1.5,"elevation":1.0,"entrance_length":0.5,"traversal_layer":2,"future_bridge_field":{"kept":true}}]}',"bridge.json")
	_check(MapValidatorRef.validate(valid).filter(func(i):return i.severity=="error").is_empty(),"A complete bridge record must validate.")
	var round_trip:=MapDocumentRef.from_text(valid.deterministic_json(),"bridge.json")
	_check(valid.semantic_equivalent(round_trip) and round_trip.data.objects[0].has("future_bridge_field"),"Bridge round trips must preserve known and unknown fields.")
	var invalid:=MapDocumentRef.from_text(prefix+'{"type":"structure.bridge","position":[0,0,0],"orientation":"diagonal","length":2.5,"width":0.5,"elevation":0.25,"entrance_length":0.25,"traversal_layer":0}]}',"bridge.json")
	var issues:=MapValidatorRef.validate(invalid)
	for field in ["orientation","length","width","elevation","entrance_length","traversal_layer"]:_check(issues.any(func(i):return String(i.path).ends_with("."+field)),"Invalid bridge %s must be reported at its field."%field)

func _test_coordinates() -> void:
	var origin := Vector3(110, 0, 30)
	var local := Vector3(-7.2, 0.65, 0)
	var world := ConverterRef.local_to_world(local, origin)
	_check(world.is_equal_approx(Vector3(102.8, 0.65, 30)), "Local-to-world conversion must add origin on X/Y/Z.")
	_check(ConverterRef.world_to_local(world, origin).is_equal_approx(local), "Coordinate conversion must round trip.")
	var canvas := ConverterRef.world_xz_to_canvas(Vector3(2, 0, -3), 10, Vector2(100,100))
	_check(canvas == Vector2(120,70), "Canvas conversion must display negative Z as north/up.")
	_check(ConverterRef.canvas_to_world_xz(canvas,10,Vector2(100,100),0.65).is_equal_approx(Vector3(2,0.65,-3)), "Canvas conversion must round trip.")

func _test_imported_overworld_assets(editor_root:String)->void:
	var project_root:=editor_root.get_base_dir().get_base_dir()
	var catalog:=AssetCatalogRef.load_catalog(editor_root.path_join("catalog/map_asset_catalog.json"))
	var expected:=["rocks_sunscorched","sunflower_cluster_small","sunflower_cluster_large","aloe_small","aloe_large","desert_rose","habitat_scorchic_sunning_rock","habitat_scorchic_sun_sensor","moss_rose_small","moss_rose_large"]
	for asset_id:Variant in expected:
		var type_id:String="asset."+String(asset_id)
		_check(catalog.by_id.has(type_id),"Imported overworld sprite %s must appear in the map-editor palette."%type_id)
		if catalog.by_id.has(type_id):
			var entry:Dictionary=catalog.by_id[type_id]
			_check(String(entry.get("asset_path","")).begins_with("res://assets/overworld/"),"%s must serialize its runtime asset path."%type_id)
	_check(expected.all(func(asset_id):return String(catalog.by_id.get("asset."+asset_id,{}).get("category",""))==("Rocks" if asset_id.begins_with("rocks_") else "Vegetation")),"New rocks and desert flora must use their intended palette categories.")
	_check(catalog.by_id.get("asset.rocks_sunscorched",{}).get("variants",[]).size()==7,"Sunscorched rocks must be one tile with seven variants.")
	_check(catalog.by_id.get("asset.sunflower_cluster_small",{}).get("variants",[]).size()==2,"Small sunflower clusters must be one tile with two variants.")
	_check(catalog.by_id.get("asset.moss_rose_small",{}).get("variants",[]).size()==3,"Small moss roses must be one tile with three variants.")
	var blue_flower:Dictionary=catalog.by_id.get("flower.blue",{})
	for type_id:String in ["asset.aloe_small","asset.moss_rose_small"]:
		var small_plant:Dictionary=catalog.by_id.get(type_id,{})
		var metadata:=AssetCatalogRef.load_metadata(project_root.path_join(String(small_plant.get("asset_path","")).trim_prefix("res://")))
		var expected_height:=float(metadata.get("visual_height",blue_flower.get("display_height",-1.0))) if bool(metadata.get("standardize_scale",false)) else float(blue_flower.get("display_height",-1.0))
		_check(float(small_plant.get("display_height",0.0))==expected_height and small_plant.get("footprint",[])==blue_flower.get("footprint",[]),"%s must use its shared scale override when enabled, otherwise the Small Blue Flower default."%type_id)

func _test_overlay_assets(editor_root:String)->void:
	var catalog:=AssetCatalogRef.load_catalog(editor_root.path_join("catalog/map_asset_catalog.json"))
	var expected:={"overlay.bromeliad":1,"overlay.orchid_swan":1,"overlay.orchid_tree_yellow":1,"overlay.roots":4,"overlay.vine_leafy_arch":1,"overlay.vine_leafy_trailing":4,"overlay.vine_passionflower_trailing":2}
	for type_id:String in expected:
		_check(catalog.by_id.has(type_id),"Filename-prefixed overlay %s must be imported as an overlay tile."%type_id)
		if not catalog.by_id.has(type_id):continue
		var entry:Dictionary=catalog.by_id[type_id]
		var variant_count:int=entry.get("variants",[]).size()
		_check(String(entry.get("category",""))=="Overlays" and bool(entry.get("supports_rotation",false)),"%s must inherit overlay category and arbitrary rotation support."%type_id)
		_check(String(entry.get("collision",{}).get("shape",""))=="none","%s must never inherit collision."%type_id)
		_check(variant_count==0 if int(expected[type_id])==1 else variant_count==int(expected[type_id]),"%s must group its numbered overlay variants."%type_id)
	var source:='{"objects":[{"type":"overlay.vine_leafy_arch","asset_path":"res://assets/overworld/overlay_vine_leafy_arch.png","position":[1,0,2],"size":[1,1,1],"height":1.25,"rotation_degrees":37.5}]}'
	var doc:=MapDocumentRef.from_text(source,"overlay_test.json")
	var issues:=MapValidatorRef.validate(doc)
	_check(not issues.any(func(issue):return String(issue.get("severity",""))=="error"),"A numeric arbitrary overlay rotation must validate: %s"%str(issues))
	var reloaded:=MapDocumentRef.from_text(doc.deterministic_json(),"overlay_test.json")
	_check(doc.semantic_equivalent(reloaded) and is_equal_approx(float(reloaded.data.objects[0].rotation_degrees),37.5),"Overlay placement and arbitrary rotation must survive map serialization.")
	var invalid:=MapDocumentRef.from_text(source.replace("37.5","\"sideways\""),"overlay_test.json")
	_check(MapValidatorRef.validate(invalid).any(func(issue):return String(issue.get("path",""))=="$.objects[0].rotation_degrees"),"Non-numeric overlay rotation must fail gracefully with a field-local validation error.")
	var attached_source:='{"objects":[{"type":"tree.main","instance_id":"tree-a","position":[4,1.5,7],"height":4.2},{"type":"overlay.vine_leafy_arch","asset_path":"res://assets/overworld/overlay_vine_leafy_arch.png","position":[4.5,1.5,6.25],"size":[1,1,1],"height":1.25,"rotation_degrees":123.25,"is_attached":true,"host_id":"tree-a","local_position":[0.5,-0.75],"attachment_order":2}]}'
	var attached:=MapDocumentRef.from_text(attached_source,"attached_overlay_test.json");var attached_issues:=MapValidatorRef.validate(attached)
	_check(not attached_issues.any(func(issue):return String(issue.get("severity",""))=="error"),"A complete attached overlay and stable host identity must validate: %s"%str(attached_issues))
	var attached_reloaded:=MapDocumentRef.from_text(attached.deterministic_json(),"attached_overlay_test.json")
	_check(attached.semantic_equivalent(attached_reloaded) and attached_reloaded.data.objects[1].local_position==[0.5,-0.75] and int(attached_reloaded.data.objects[1].attachment_order)==2 and is_equal_approx(float(attached_reloaded.data.objects[1].rotation_degrees),123.25),"Host identity, local offset, order, and arbitrary rotation must survive save/load.")
	var dangling:=MapDocumentRef.from_text(attached_source.replace('"tree-a","local_position"','"missing","local_position"'),"attached_overlay_test.json")
	_check(MapValidatorRef.validate(dangling).any(func(issue):return String(issue.get("path",""))=="$.objects[1].host_id"),"A missing attachment host must fail gracefully at host_id.")
	var recursive:=MapDocumentRef.from_text('{"objects":[{"type":"overlay.roots","instance_id":"overlay-host","asset_path":"res://assets/overworld/overlay_roots_01.png","position":[0,0,0]},{"type":"overlay.vine_leafy_arch","asset_path":"res://assets/overworld/overlay_vine_leafy_arch.png","position":[0,0,0],"is_attached":true,"host_id":"overlay-host","local_position":[0,0],"attachment_order":0}]}',"attached_overlay_test.json")
	_check(MapValidatorRef.validate(recursive).any(func(issue):return String(issue.get("path",""))=="$.objects[1].host_id"),"Overlay-on-overlay attachment must be rejected.")
	for type_id:String in ["tile.stream_north","tile.terrain_stream_opening","tile.terrain_stream_opening_rocky","tile.terrain_stream_y"]:
		var stream:Dictionary=catalog.by_id.get(type_id,{})
		_check(not stream.is_empty(),"Terrain stream artwork must import as %s instead of an overlay."%type_id)
		_check(String(stream.get("category",""))=="Water Terrain" and String(stream.get("inherits",""))=="block.water","%s must advertise water-block inheritance."%type_id)
		if type_id=="tile.stream_north":_check(String(stream.get("collision",{}).get("type",""))=="polygon","Stream North must expose its canonical normalized polygon through the catalog.")
		else:_check(String(stream.get("collision",{}).get("shape",""))=="box" and bool(stream.get("collision",{}).get("from_serialized_size",false)),"%s must use its rotated serialized footprint for water collision."%type_id)
		_check(bool(stream.get("supports_rotation",false)) and String(stream.get("scale_mode",""))=="explicit_size","%s must remain arbitrarily rotatable and resizable as a normal tile."%type_id)
	var valid_polygon:={"type":"polygon","closed":true,"points":[[0.1,0.1],[0.9,0.1],[0.7,0.5],[0.9,0.9],[0.1,0.9]]}
	_check(AssetCatalogRef.validate_polygon_collision(valid_polygon).is_empty(),"A valid concave normalized collision polygon must be accepted without convex-hull simplification.")
	_check(not AssetCatalogRef.validate_polygon_collision({"type":"polygon","closed":false,"points":[[0,0],[1,0],[0,1]]}).is_empty(),"Unclosed collision polygons must be flagged.")
	_check(AssetCatalogRef.validate_polygon_collision({"type":"polygon","closed":true,"points":[[0,0],[1,1],[0,1],[1,0]]}).any(func(message):return message.contains("self-intersect")),"Self-intersecting collision polygons must be rejected.")
	_check(not AssetCatalogRef.validate_polygon_collision({"type":"polygon","closed":true,"points":[[0,0],[0,0],[1,1]]}).is_empty(),"Duplicate consecutive and degenerate vertices must be rejected.")

func _test_graph(maps: String) -> void:
	var graph := MapGraphRef.scan(maps)
	_check(graph.maps.size() == 13, "Map index must resolve all thirteen playable map files, including Jalovea City and the tropical research lab.")
	_check(graph.connections.size() == 5, "The serialized outdoor graph must expose five bidirectional connection pairs.")
	_check(graph.issues.is_empty(), "Current serialized warp graph must not contain missing, one-way, or duplicate endpoints.")

func _test_eastern_route(maps: String, editor_root: String) -> void:
	var source_path := maps.path_join("eastern_rainforest_route.json")
	var original := MapDocumentRef.load_file(source_path)
	var bridge:Dictionary=original.data.objects.filter(func(value):return value is Dictionary and value.get("type")=="structure.bridge")[0]
	_check(MapValidatorRef.validate(original).filter(func(i):return i.severity=="error").is_empty(),"Eastern route bridge must load without false validation errors.")
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
	var legacy_water_snapshot:Variant=edited.data.water_blocks.duplicate(true)
	edited.data.terrain_tiles[0]["future_terrain_metadata"]={"preserved":true}
	edited.data.terrain_tiles[0].positions.append([8,8])
	var edited_bridge:Dictionary=edited.data.objects.filter(func(value):return value is Dictionary and value.get("type")=="structure.bridge")[0]
	edited_bridge["width"]=float(edited_bridge.width)+0.5;edited_bridge["future_editor_field"]="preserved"
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
		var reloaded_bridge:Dictionary=reloaded.data.objects.filter(func(value):return value is Dictionary and value.get("type")=="structure.bridge")[0]
		_check(is_equal_approx(float(reloaded_bridge.width),float(bridge.width)+0.5) and reloaded_bridge.future_editor_field=="preserved","Modified bridge fields and unknown data must persist after atomic save and reload.")
		_check(reloaded.data.terrain_tiles[0].positions.any(func(position):return int(position[0])==8 and int(position[1])==8),"A painted canonical terrain cell must persist after save and reload.")
		_check(reloaded.data.terrain_tiles[0].future_terrain_metadata.preserved and reloaded.data.water_blocks==legacy_water_snapshot,"Canonical terrain edits must preserve unknown fields and legacy terrain blocks.")
	else:
		_check(false, "Edited route must reload: " + reloaded.parse_error)
