extends SceneTree

const MapGraphRef := preload("res://core/map_graph.gd")
const MapDocumentRef := preload("res://core/map_document.gd")
const WallGeometryRef := preload("res://core/wall_geometry.gd")

func _initialize() -> void:
	# Ensure assertion failures cannot leave a headless SceneTree running forever.
	create_timer(8.0).timeout.connect(func(): push_error("MAP_EDITOR_UI_TEST_TIMEOUT"); quit(2))
	var scene := load("res://map_editor.tscn") as PackedScene
	var editor := scene.instantiate()
	root.add_child(editor)
	await process_frame
	assert(editor._orthogonal_wall_route(Vector2.ZERO,Vector2(6,2),1.0)==[Vector2(2,0),Vector2(2,2),Vector2(6,2)],"A shallow diagonal wall gesture must become an interval-aligned H-V-H route.")
	assert(editor._orthogonal_wall_route(Vector2.ZERO,Vector2(5,2),1.0).is_empty(),"A route containing a non-integral 2-unit filler interval must be rejected.")
	assert(editor._orthogonal_wall_route(Vector2.ZERO,Vector2(2,-6),1.0)==[Vector2(0,-2),Vector2(2,-2),Vector2(2,-6)],"A steep diagonal wall gesture must become an interval-aligned V-H-V route.")
	assert(editor._orthogonal_wall_route(Vector2.ZERO,Vector2(1,1),1.0).is_empty(),"A diagonal gesture that cannot form two outer grid runs must be rejected.")
	assert(editor._orthogonal_wall_route(Vector2.ZERO,Vector2(0,1),1.0).is_empty(),"A cardinal wall gesture shorter than one filler interval must be rejected.")
	assert(editor._orthogonal_wall_route(Vector2.ZERO,Vector2(0,2),1.0)==[Vector2(0,2)],"A cardinal wall gesture spanning one filler interval must remain one run.")
	var normalized_wall:Dictionary=WallGeometryRef.normalize_points([[0,0],[4,0],[4.4,0],[8,0]])
	assert(normalized_wall.valid and normalized_wall.points==[[0.0,0.0],[4.0,0.0],[8.0,0.0]],"A legacy point collapsing onto the 2-unit wall lattice must merge without removing other valid anchors.")
	var manifest:=MapDocumentRef.load_file(editor.map_directory.path_join("map_index.json"))
	assert(editor._is_world_index_document(manifest),"World-manifest protection must be based on document structure, not only the map_index.json filename.")
	var disguised_manifest:=MapDocumentRef.from_text(manifest.deterministic_json(),"jalovea_city.json")
	assert(editor._is_world_index_document(disguised_manifest),"Manifest detection must survive an accidental filename change.")
	var active_document=editor.document;editor.document=disguised_manifest
	assert(not editor._rename_current_map("another_name.json"),"A disguised world manifest must be rejected by the ordinary map rename path.")
	editor.document=active_document
	assert(editor.canvas.get_parent() is HSplitContainer and editor.canvas.get_parent().get_child_count()==2 and editor.canvas.get_parent().get_child(0).name=="ActivitySidebar","The workspace must use one left activity sidebar and give the canvas the entire remaining width.")
	assert(editor.find_child("TestMapButton",true,false) is Button,"The toolbar must expose a Test Map launch action.")
	assert(editor.find_child("ImportSpritesButton",true,false) is Button,"The toolbar must expose a reusable overworld sprite importer.")
	assert(editor.find_child("ObjectSelectionMode",true,false) is Button and editor.find_child("TerrainSelectionMode",true,false) is Button,"The toolbar must expose mutually exclusive object and terrain selection modes.")
	assert(editor.activity_tabs.tabs_visible==false and editor.activity_buttons.size()==3 and editor.activity_buttons.map(func(button):return button.text)==["OBJECTS","INSPECTOR","MAP"],"The sidebar must expose three prominent custom activity controls instead of generic tabs.")
	# Selection and sidebar content must not change the canvas layout or view.
	await process_frame
	await process_frame
	# Check both the requested display size and the original smaller window.
	for window_size in [Vector2i(1920,1200),Vector2i(1440,900)]:
		root.size=window_size
		await process_frame
		await process_frame
		assert(editor.size.is_equal_approx(Vector2(window_size)),"The editor must fill the window without aspect-ratio margins.")
		var document_toolbar:=editor.find_child("DocumentToolbar",true,false) as HFlowContainer
		var editing_toolbar:=editor.find_child("EditingToolbar",true,false) as HFlowContainer
		assert(document_toolbar!=null and editing_toolbar!=null and editing_toolbar.position.y>=document_toolbar.position.y+document_toolbar.size.y,"Document actions and editing tools must occupy separate rows.")
		for toolbar in [document_toolbar,editing_toolbar]:
			for control in toolbar.get_children():
				assert(control.position.x>=0 and control.position.x+control.size.x<=editor.size.x+1,"Every toolbar control must fit within the window.")
		assert(editor.canvas.global_position.x+editor.canvas.size.x<=editor.size.x+1 and editor.canvas.global_position.y+editor.canvas.size.y<=editor.size.y+1,"The map canvas must fit the available workspace.")
	editor.canvas.pan=Vector2(137,-83);editor.canvas.zoom=1.3
	var canvas_position:Vector2=editor.canvas.global_position
	var canvas_size:Vector2=editor.canvas.size
	var world_screen:Vector2=editor.canvas.global_position+editor.canvas.world_to_screen(Vector2(3,-5))
	var first_object_id:String=String(editor.editor_objects[0].id);editor.canvas.select_object(first_object_id);await process_frame
	for activity in [0,1,2,0,1]:
		editor._set_activity(activity)
		editor.status_label.text="Selected "+"long object name ".repeat(40)
		await process_frame
		await process_frame
		assert(editor.canvas.global_position.is_equal_approx(canvas_position) and editor.canvas.size.is_equal_approx(canvas_size),"Selection and activity changes must preserve the canvas layout.")
		assert((editor.canvas.global_position+editor.canvas.world_to_screen(Vector2(3,-5))).is_equal_approx(world_screen) and is_equal_approx(editor.canvas.zoom,1.3),"Selection and activity changes must preserve the panned and zoomed map view.")
	assert(editor.activity_tabs.current_tab==1,"Selecting a map object must automatically reveal the Inspector activity.")
	editor.canvas.select_object("");assert(editor.activity_tabs.current_tab==1,"Clearing selection from empty canvas must preserve the current sidebar activity.")
	editor._set_activity(2);assert(editor.metadata_box.find_child("MapDisplayName",true,false)!=null and editor.metadata_box.find_child("BaseTerrainType",true,false)!=null,"The Map activity must contain named map properties and base terrain controls.")
	editor._set_activity(0)
	var north_screen: Vector2 = editor.canvas.world_to_screen(Vector2(0,-5))
	var south_screen: Vector2 = editor.canvas.world_to_screen(Vector2(0,5))
	assert(north_screen.y < south_screen.y, "The editor canvas must display negative Z north/up, matching gameplay.")
	var warps_before:=MapGraphRef.warp_fields(editor.document.data).size();editor._add_warp()
	var added_warp:Dictionary=editor._find_object(editor.canvas.selected_id)
	assert(MapGraphRef.warp_fields(editor.document.data).size()==warps_before+1 and String(added_warp.field).begins_with("warp_") and editor.document.data.warp_metadata[String(added_warp.field)].id is int,"Add Warp must create and select a uniquely numbered editor warp.")
	editor._delete_selected();assert(MapGraphRef.warp_fields(editor.document.data).size()==warps_before,"Newly authored warps must be deletable through the UI.")
	editor._undo();editor._undo()
	editor.canvas.frame_all()
	var original_map_size:Vector2=editor._map_size()
	var map_handle:Vector2=editor.canvas._resize_handle(editor.canvas._map_bounds_rect()).get_center()
	var map_press:=InputEventMouseButton.new();map_press.button_index=MOUSE_BUTTON_RIGHT;map_press.pressed=true;map_press.position=map_handle;editor.canvas._gui_input(map_press)
	var map_motion:=InputEventMouseMotion.new();map_motion.button_mask=MOUSE_BUTTON_MASK_RIGHT;map_motion.position=map_handle+Vector2(editor.canvas.pixels_per_unit*editor.canvas.zoom,0);editor.canvas._gui_input(map_motion)
	var map_release:=InputEventMouseButton.new();map_release.button_index=MOUSE_BUTTON_RIGHT;map_release.pressed=false;map_release.position=map_motion.position;editor.canvas._gui_input(map_release)
	assert(editor._map_size().x==original_map_size.x+2.0,"Right-dragging the map-bound resize handle must expand the serialized map dimensions.")
	editor._undo();assert(editor._map_size()==original_map_size,"Map-bound resizing must be undoable.")
	var scalable_object:Dictionary={}
	for candidate in editor.editor_objects:
		if candidate.shape=="rectangle":scalable_object=candidate;break
	assert(not scalable_object.is_empty(),"The resize interaction test requires an existing scalable map object.")
	editor.canvas.select_object(String(scalable_object.id));var original_object_size:Vector3=scalable_object.size
	var object_handle:Vector2=editor.canvas._resize_handle(editor.canvas._screen_rect(scalable_object)).get_center()
	var object_press:=InputEventMouseButton.new();object_press.button_index=MOUSE_BUTTON_RIGHT;object_press.pressed=true;object_press.position=object_handle;editor.canvas._gui_input(object_press)
	var object_motion:=InputEventMouseMotion.new();object_motion.button_mask=MOUSE_BUTTON_MASK_RIGHT;object_motion.position=object_handle+Vector2(editor.canvas.pixels_per_unit*editor.canvas.zoom,0);editor.canvas._gui_input(object_motion)
	var object_release:=InputEventMouseButton.new();object_release.button_index=MOUSE_BUTTON_RIGHT;object_release.pressed=false;object_release.position=object_motion.position;editor.canvas._gui_input(object_release)
	assert(editor._find_object(String(scalable_object.id)).size.x==original_object_size.x+2.0,"Object resize handles must scale with right-drag instead of the placement-bound left button.")
	editor._undo()
	var before: int = editor.document.data.trees.size()
	var universal_preview:Array[Dictionary]=[]
	editor._append_universal_object(universal_preview,"$.objects[0]",{"type":"tree.main","position":[0,1.5,0],"size":[1,1,1],"height":4.2})
	assert(universal_preview.size()==1 and not universal_preview[0].has("display_width") and is_equal_approx(float(universal_preview[0].display_height),4.2),"Universal tree previews must use the runtime height rather than a building-only width override.")
	# A palette drag owns the type captured on mouse-down. Moving across other
	# palette rows must neither replace that payload nor change the prior palette
	# selection used by the Add at Origin button.
	editor.selected_palette_entry="tree.main";editor.palette_press_entry="tree.palm"
	var palette_motion:=InputEventMouseMotion.new();palette_motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	editor._palette_gui_input(palette_motion)
	assert(editor.palette_drag_entry=="tree.palm" and editor.selected_palette_entry=="tree.main","Palette dragging must keep an immutable payload without changing selection.")
	editor._palette_gui_input(palette_motion)
	assert(editor.palette_drag_entry=="tree.palm","Crossing another palette row must not replace the active drag type.")
	editor._finish_palette_drag()
	editor.selected_palette_entry = "tree.palm"
	editor._add_palette_object_at(Vector2(2.4, -3.6))
	assert(editor.document.data.trees.size() == before + 1, "Dropping a palette tree must append it to the current map.")
	var placed: Array = editor.document.data.trees[-1]
	assert(placed == [2.0, 1.5, -4.0, 1], "Drop placement must use snapped X/Z, catalog Y, and selected tree variant.")
	assert(editor.canvas.selected_id != "", "A newly dropped object must become selected for immediate editing.")
	var city_choices:Array=editor.catalog.by_id["palette.city_buildings"].palette_choices
	var apartment_choices:Array=editor.catalog.by_id["palette.apartment_buildings"].palette_choices
	assert(city_choices.size()==5 and apartment_choices.size()==5,"The Buildings palette must expose five randomized city and apartment variants through two grouped brushes.")
	for concrete_type in city_choices+apartment_choices:
		assert(bool(editor.catalog.by_id[concrete_type].palette_hidden),"Concrete randomized building variants must remain serialization assets rather than cluttering the palette.")
	var objects_before_stroke:int=editor.document.data.objects.size()
	editor.selected_palette_entry="palette.city_buildings"
	var first_global:Vector2=editor.canvas.global_position+editor.canvas.world_to_screen(Vector2(0,0))
	var second_global:Vector2=editor.canvas.global_position+editor.canvas.world_to_screen(Vector2(2,0))
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=first_global;press.global_position=first_global
	editor._input(press)
	var paint_motion:=InputEventMouseMotion.new();paint_motion.button_mask=MOUSE_BUTTON_MASK_LEFT;paint_motion.position=second_global;paint_motion.global_position=second_global
	editor._input(paint_motion)
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=second_global;release.global_position=second_global
	editor._input(release)
	assert(editor.document.data.objects.size()==objects_before_stroke+2,"Holding and dragging a selected palette element must stamp each newly visited snapped location.")
	assert(editor.selected_palette_entry.is_empty() and editor.palette.get_selected_items().is_empty(),"Releasing a palette placement stroke must restore normal left-click selection behavior.")
	for record in editor.document.data.objects.slice(-2):
		assert(String(record.type) in city_choices and record.size==editor.catalog.by_id[String(record.type)].default_size,"Grouped city stamps must resolve to concrete random variants at their normalized City Building 03 scale.")
	editor._undo()
	assert(editor.document.data.objects.size()==objects_before_stroke,"One Undo must remove an entire continuous object-palette stroke.")
	var placed_id: String = editor.canvas.selected_id
	editor.selected_id = placed_id
	editor._delete_selected()
	assert(editor.document.data.trees.size() == before, "Delete must remove the selected object from the active document, not a snapshot.")
	editor._undo()
	assert(editor.document.data.trees.size() == before + 1, "Deleted objects must be recoverable with Undo.")
	var vine_entry: Dictionary = editor.catalog.by_id["cave.vine"]
	assert(editor._compatible_array_field(vine_entry)=="objects", "Cave vines must use the universal object collection when a legacy vines array is unavailable.")
	editor.selected_palette_entry="cave.vine";editor._add_palette_object_at(Vector2(1,2))
	assert(editor.document.data.objects[-1].type=="cave.vine", "Universal vegetation must serialize with an explicit reusable type.")
	var passion_vine_entry:Dictionary=editor.catalog.by_id["flower.passion_vine_horizontal"]
	assert(editor._compatible_array_field(passion_vine_entry)=="objects" and passion_vine_entry.preview_texture.ends_with("vines_horizontal_flower_passion.png"),"Horizontal passion vines must be available in the outdoor object palette with their authored preview.")
	editor.selected_palette_entry="flower.passion_vine_horizontal";editor._add_palette_object_at(Vector2(-2,3))
	assert(editor.document.data.objects[-1].type=="flower.passion_vine_horizontal" and is_equal_approx(float(editor.document.data.objects[-1].height),0.62),"Passion-vine drops must serialize as reusable outdoor vegetation at the catalog height.")
	editor.selected_palette_entry="building.house";editor._add_palette_object_at(Vector2(3,4))
	assert(editor.document.data.objects[-1].type=="building.house" and editor.document.data.objects[-1].size==[5.0,3.0,4.0], "House exteriors must be placeable on any outdoor map as universal objects.")
	editor.selected_palette_entry="building.medical_ward";editor._add_palette_object_at(Vector2(-3,4))
	assert(editor.document.data.objects[-1].type=="building.medical_ward", "Medical ward exteriors must be placeable on any outdoor map.")
	editor.selected_palette_entry="npc.generic";editor._add_palette_object_at(Vector2(0,1))
	assert(editor.document.data.objects[-1].type=="npc.generic" and editor.document.data.objects[-1].dialogue.size()==1,"Dialogue-only NPCs must be placeable on every map.")
	assert(editor.inspector.find_child("NpcSprite",true,false)!=null and editor.inspector.find_child("NpcColor",true,false)!=null,"NPC inspectors must expose the runtime sprite and fallback-color fields.")
	editor.selected_palette_entry="npc.opponent";editor._add_palette_object_at(Vector2(0,-1))
	var trainer_placement:Dictionary=editor.document.data.objects[-1];var trainer_definition:Dictionary=editor._trainer_definition(trainer_placement)
	assert(trainer_placement.type=="npc.opponent" and not String(trainer_placement.get("trainer_id","")).is_empty() and not trainer_placement.has("team"),"Trainer drops must serialize a stable trainer reference rather than duplicating roster data in the map.")
	assert(trainer_definition.team.size()==1 and trainer_definition.team[0].level==5 and editor._trainer_is_catalog_backed(trainer_placement),"New trainer definitions must provide an explicit editable Fakemon/level team in data/trainers.json.")
	var parsed_team:Array=editor._parse_team("Scorchick:8, 1:12")
	assert(parsed_team==[{"fakemon":"Scorchick","level":8},{"fakemon":1,"level":12}],"Trainer team text must accept Fakemon names or indices with levels.")
	var legacy_trainers:Array[Dictionary]=[];editor._append_trainer(legacy_trainers,"$.trainers[0]",{"name":"LEGACY","position":[0,0.65,0],"party":[1]})
	assert(legacy_trainers[0].path=="$.trainers[0]" and legacy_trainers[0].universal_type=="npc.opponent","Legacy trainers must expose their whole record to the team inspector.")
	editor._new_document()
	assert(editor.document.kind=="outdoor" and editor.document.data.map_metadata.id=="new_map" and editor.document.data.objects is Array and editor.document.data.outdoor_connections is Array,"New Map must create a complete metadata-driven universal map, not a filename-limited route fragment.")
	assert(editor.document.data.water_species is Array and is_equal_approx(float(editor.document.data.water_encounter_chance),0.0),"New outdoor maps must initialize the runtime water-encounter fields.")
	assert(editor._compatible_array_field(editor.catalog.by_id["tree.main"])=="objects" and editor._compatible_array_field(editor.catalog.by_id["npc.opponent"])=="objects","Universal new maps must accept vegetation and trainers immediately.")
	var refs:={"root":"old_map.json","maps":{"old_map":"old_map.json"},"connections":[{"destination_map":"old_map.json"}]}
	assert(editor._replace_filename_references(refs,"old_map.json","renamed_map.json") and refs.root=="renamed_map.json" and refs.maps.has("renamed_map") and refs.connections[0].destination_map=="renamed_map.json","Map rename must update index keys and nested destination references.")
	var index_doc:MapDocument=editor.MapDocumentRef.load_file(editor.map_directory.path_join("map_index.json"));assert(not String(index_doc.data.index_metadata.display_name).is_empty(),"The fixed runtime index file must expose editable logical naming metadata.")
	var cave: MapDocument = editor.MapDocumentRef.load_file(editor.map_directory.path_join("vinestone_cave.json"))
	editor.document=cave
	assert(editor._compatible_array_field(vine_entry)=="vines", "Cave vines must be placeable when editing Vinestone Cave.")
	# Restore the route and verify the two rectangle schemas are emitted exactly.
	editor.document=editor.MapDocumentRef.load_file(editor.map_directory.path_join("eastern_rainforest_route.json"))
	editor._refresh_all()
	assert(editor.metadata_box.find_child("WaterEncounterChance",true,false)!=null,"Outdoor metadata must expose the runtime water encounter probability.")
	var authored_cell_count:=0
	for terrain_entry in editor.document.data.terrain_tiles:authored_cell_count+=terrain_entry.get("positions",[]).size()+(1 if terrain_entry.has("position") else 0)
	assert(editor.editor_objects.filter(func(object):return object.field=="terrain_tiles").size()==authored_cell_count,"Grouped canonical terrain positions must expand into individually selectable canvas cells.")
	assert(editor.metadata_box.find_child("BaseTerrainType",true,false)!=null and editor.terrain_type_option.item_count==6,"The editor must expose canonical base terrain and a complete terrain type palette.")
	var legacy_water_snapshot:Variant=editor.document.data.water_blocks.duplicate(true);editor.document.data.terrain_tiles[0]["future_terrain_metadata"]={"preserve":true}
	editor.terrain_type_option.select(2);editor._terrain_stroke_started();editor._terrain_cell_changed(Vector2i(8,8),false);editor._terrain_stroke_finished()
	assert(editor.document.data.terrain_tiles.any(func(entry):return entry.terrain_type=="water" and entry.positions.has([8,8])),"The paint brush must write a snapped canonical cell to the selected terrain group.")
	assert(editor.document.data.water_blocks==legacy_water_snapshot and editor.document.data.terrain_tiles[0].future_terrain_metadata.preserve,"Terrain painting must preserve legacy visual blocks and unknown terrain-entry fields.")
	editor._undo();assert(not editor.document.data.terrain_tiles.any(func(entry):return entry.get("positions",[]).has([8,8])),"A complete paint stroke must be reversible with one Undo action.")
	editor._redo();editor._terrain_stroke_started();editor._terrain_cell_changed(Vector2i(8,8),true);editor._terrain_stroke_finished()
	assert(not editor.document.data.terrain_tiles.any(func(entry):return entry.get("positions",[]).has([8,8])),"The erase brush must remove a canonical cell without touching legacy terrain blocks.")
	var invalid_entry:={"terrain_type":"lava","position":[7,7]};editor.document.data.terrain_tiles.append(invalid_entry);editor.document.dirty=true;editor._refresh_all()
	assert(editor.canvas.terrain_error_cells.has(Vector2i(7,7)),"Coordinate-specific canonical terrain validation errors must be highlighted on the canvas.")
	editor.document.data.terrain_tiles.pop_back();editor._refresh_all()
	var bridge_object:Dictionary={}
	for object in editor.editor_objects:
		if object.get("universal_type","")=="structure.bridge":bridge_object=object;break
	assert(bridge_object.shape=="bridge" and bridge_object.footprint==Vector2(1,5),"A vertical bridge must render its width-by-length footprint, not a generic 1x1 size.")
	editor.selected_id=String(bridge_object.id);editor._refresh_inspector()
	for control_name in ["BridgeOrientation","BridgeLength","BridgeWidth","BridgeElevation","BridgeEntranceLength","BridgeTraversalLayer"]:assert(editor.inspector.find_child(control_name,true,false)!=null,"Bridge inspector must expose "+control_name.trim_prefix("Bridge")+".")
	var bridge_record:Dictionary=editor._get_path(String(bridge_object.path));bridge_record["future_ui_field"]=17
	editor._set_bridge_field(bridge_object,"orientation","horizontal");editor._set_bridge_field(bridge_object,"length",7);editor._set_bridge_field(bridge_object,"width",2.0)
	var updated_bridge:Dictionary=editor._find_object(String(bridge_object.id))
	assert(updated_bridge.footprint==Vector2(7,2) and bridge_record.future_ui_field==17,"Bridge edits must update the true oriented footprint while preserving unknown fields.")
	var water_before:int=editor.document.data.water_blocks.size()
	assert(editor.document.data.sand_blocks.size()>0,"Existing route water must have explicit sand-border blocks.")
	var sand_entry:Dictionary=editor.catalog.by_id["block.sand"]
	assert(editor._compatible_array_field(sand_entry)=="sand_blocks","Sand shore blocks must be placeable on outdoor maps.")
	editor.selected_palette_entry="block.water"
	editor._add_palette_object_at(Vector2(2,-3))
	var terrain_count:int=editor.document.data.terrain_tiles.size()
	editor.selected_palette_entry="terrain.mud";editor._add_palette_object_at(Vector2(2.2,-3.7))
	editor.selected_palette_entry="terrain.stone";editor._add_palette_object_at(Vector2(4.1,-5.1))
	assert(editor.document.data.terrain_tiles.size()==terrain_count+2 and editor.document.data.terrain_tiles[-2].terrain_type=="mud" and editor.document.data.terrain_tiles[-1].terrain_type=="stone","Mud and stone must be placeable as canonical terrain from the map editor palette.")
	var water:Array=editor.document.data.water_blocks[-1]
	assert(editor.document.data.water_blocks.size()==water_before+1 and water.size()==6, "Water drops must serialize as Block6 arrays.")
	var water_object:Dictionary={}
	for object in editor.editor_objects:
		if String(object.path)=="$.water_blocks[%d]"%water_before:water_object=object;break
	assert(not water_object.is_empty(),"New water must be represented by an editable rectangle.")
	editor._write_object_position(water_object,Vector3(4,0.15,-5))
	var moved_water:Array=editor.document.data.water_blocks[-1]
	assert(is_equal_approx(float(moved_water[0]),4.0) and is_equal_approx(float(moved_water[1]),0.15) and is_equal_approx(float(moved_water[2]),-5.0) and moved_water.slice(3)==[2,0.3,2],"Moving water must preserve its width, height, and depth.")
	var grass_before:int=editor.document.data.grass_zones.size()
	editor.selected_palette_entry="area.grass"
	editor._add_palette_object_at(Vector2(-2,3))
	var grass:Variant=editor.document.data.grass_zones[-1]
	assert(editor.document.data.grass_zones.size()==grass_before+1 and grass is Dictionary,"Grass drops must serialize as zone objects, not Block6 arrays.")
	assert(is_equal_approx(float(grass.position[0]),-2.0) and is_equal_approx(float(grass.position[1]),0.12) and is_equal_approx(float(grass.position[2]),3.0) and grass.size==[3,0.25,3] and is_equal_approx(float(grass.encounter_chance),0.2),"New grass zones must include position, size, and encounter chance.")
	# Tree movement must likewise retain its fourth variant element.
	var tree_object:Dictionary={}
	for object in editor.editor_objects:
		if object.field=="trees":tree_object=object;break
	var tree_path:String=tree_object.path;var old_variant:Variant=editor._get_path(tree_path)[3]
	editor._write_object_position(tree_object,Vector3(1,1.5,2))
	assert(editor._get_path(tree_path).size()==4 and editor._get_path(tree_path)[3]==old_variant,"Moving a tree must preserve its serialized variant.")
	# Current-schema interior floor/wall tiles must render and retain Block6 data.
	editor._load_path(editor.map_directory.path_join("rainforest_house.json"))
	assert(editor._compatible_array_field(editor.catalog.by_id["area.grass"])=="grass_zones" and editor._compatible_array_field(editor.catalog.by_id["terrain.water"])=="terrain_tiles","Encounter grass and canonical terrain must remain available even when a map has no pre-existing destination arrays.")
	editor.selected_palette_entry="area.grass";editor._add_palette_object_at(Vector2(2,2))
	editor.selected_palette_entry="terrain.water";editor._add_palette_object_at(Vector2(3,2))
	assert(editor.document.data.grass_zones.size()==1 and editor.document.data.terrain_tiles.size()==1 and editor.document.data.terrain_tiles[0].terrain_type=="water","Universal grass and canonical terrain placement must create their canonical arrays on demand.")
	var terrain_object:Dictionary={}
	for candidate in editor.editor_objects:
		if candidate.field=="terrain_tiles":terrain_object=candidate;break
	assert(not terrain_object.is_empty() and editor.canvas._is_scalable(terrain_object),"Placed canonical terrain cells must expose the same resize handle as other scalable tiles.")
	editor._on_canvas_resized(String(terrain_object.id),Vector3.ONE,Vector3(3,1,3))
	assert(editor.document.data.terrain_tiles[-1].positions.size()==9,"Resizing canonical terrain must paint the resized rectangular footprint as canonical cells.")
	editor._undo()
	var building_object:Dictionary={};var floor_object:Dictionary={};var wall_count:=0;var furnishing_count:=0
	for object in editor.editor_objects:
		if object.shape=="building":building_object=object
		elif object.field=="floor_blocks":floor_object=object
		elif object.field=="wall_blocks":wall_count+=1
		elif object.field=="furnishings":furnishing_count+=1
	assert(not building_object.is_empty() and is_equal_approx(float(building_object.display_width),4.6),"House exteriors must use the runtime's size-derived preview width.")
	var house_extension:=float(editor.catalog.by_id["building.house"].get("front_depth_extension",0.0))
	assert(building_object.footprint==Vector2(4,3.0+house_extension),"House exterior selection must show its serialized collision footprint plus the catalog-authored front interaction extension.")
	assert(not floor_object.is_empty() and wall_count==3,"Serialized interior floor and wall blocks must appear as editable building tiles.")
	assert(furnishing_count==editor.document.data.furnishings.size() and furnishing_count>=4,"Every serialized rainforest-house furnishing must appear in the editor.")
	assert(editor.canvas._draw_rank(floor_object)==0,"Floor blocks must remain below walls, props, markers, and cave objects.")
	var overlapping_prop:Dictionary={"id":"prop-over-floor","field":"furnishings","position":floor_object.position,"size":Vector3.ONE,"shape":"point","footprint":Vector2.ONE}
	var overlap_objects:Array[Dictionary]=[floor_object,overlapping_prop]
	editor.canvas.set_document_objects(overlap_objects,editor._map_size())
	assert(editor.canvas._hit_test(editor.canvas.world_to_screen(Vector2(floor_object.position.x,floor_object.position.z))).id=="prop-over-floor","Furniture and other foreground objects must be selected before an overlapping interior floor tile.")
	assert(editor.canvas._draw_rank(floor_object)<editor.canvas._draw_rank(overlapping_prop),"Terrain must render below NPCs and placed objects regardless of map depth.")
	editor.canvas.set_selection_mode("terrain");assert(editor.canvas._hit_test(editor.canvas.world_to_screen(Vector2(floor_object.position.x,floor_object.position.z))).id==String(floor_object.id),"Terrain mode must select terrain through overlapping objects.")
	editor.canvas.set_selection_mode("objects");assert(editor.canvas._hit_test(editor.canvas.world_to_screen(Vector2(floor_object.position.x,floor_object.position.z))).id=="prop-over-floor","Object mode must ignore overlapping terrain.")
	var old_floor:Array=editor._get_path(String(floor_object.path)).duplicate()
	assert(String(floor_object.texture).ends_with("tile_interior_floor_tiles.png"),"Interior floor rectangles must carry the real gameplay floor texture into the canvas renderer.")
	editor._write_object_position(floor_object,Vector3(1,-0.1,2))
	assert(editor._get_path(String(floor_object.path)).slice(3)==old_floor.slice(3),"Moving an interior tile must preserve its Block6 dimensions.")
	# Standard desktop editing shortcuts must invoke the same history used by the
	# toolbar. Test through the input handler, not by calling Undo directly.
	editor._push_undo()
	editor.document.set_value("$.entry",[2,0.65,1])
	var undo_event:=InputEventKey.new();undo_event.pressed=true;undo_event.ctrl_pressed=true;undo_event.keycode=KEY_Z
	editor._unhandled_key_input(undo_event)
	assert(editor.document.data.entry != [2,0.65,1],"Ctrl+Z must undo the most recent document edit.")
	# Clearing houses now use the same editable four-marker transition model as
	# wards: exterior trigger/return plus interior entry/exit.
	editor._load_path(editor.map_directory.path_join("rainforest_house.json"))
	var house_exit:Dictionary={};var house_return:Dictionary={}
	for object in editor.editor_objects:
		if object.path=="$.exit_door":house_exit=object
		elif object.path=="$.exterior_return":house_return=object
	assert(not house_exit.is_empty() and not house_return.is_empty(),"House exit and exterior return markers must both be editable.")
	editor.canvas.object_activated.emit(String(house_exit.id))
	assert(editor.document.path.get_file()=="rainforest_clearing.json","Double-clicking a house interior exit must open the outdoor clearing.")
	var house_arrival:Dictionary=editor._find_object(editor.canvas.selected_id)
	assert(not house_arrival.is_empty() and house_arrival.path=="$.exterior_return" and house_arrival.source_file=="rainforest_house.json","House exit navigation must select its linked outdoor arrival marker, not the exterior building or door.")
	# Double-click activation follows the hard-coded compatibility graph and selects
	# the destination arrival marker when that marker belongs to the target file.
	editor._load_path(editor.map_directory.path_join("eastern_rainforest_route.json"))
	var cave_warp_id:=""
	for object in editor.editor_objects:
		if object.path=="$.cave_warp":cave_warp_id=object.id;break
	assert(not cave_warp_id.is_empty(),"Eastern route cave warp must be present.")
	editor.selected_id=cave_warp_id;editor._refresh_inspector()
	var warp_id_control:=editor.inspector.find_child("WarpId",true,false) as SpinBox
	var warp_map_control:=editor.inspector.find_child("WarpEntranceMap",true,false) as OptionButton
	var warp_target_control:=editor.inspector.find_child("WarpEntranceMapWarpId",true,false) as SpinBox
	assert(warp_id_control!=null and warp_map_control!=null and warp_target_control!=null,"Warp Inspector must expose numeric ID, Entrance Map selector, and Entrance Map Warp ID controls alongside Position.")
	assert(warp_map_control.item_count>1 and range(warp_map_control.item_count).any(func(index):return String(warp_map_control.get_item_metadata(index))=="vinestone_cave.json"),"Entrance Map must list real map files instead of requiring an exact-name text entry.")
	assert(range(warp_map_control.item_count).any(func(index):return String(warp_map_control.get_item_metadata(index))=="jalovea_city.json" and not warp_map_control.is_item_disabled(index)),"Registered authored maps such as Jalovea City must appear as valid warp destinations.")
	assert(not range(warp_map_control.item_count).any(func(index):return String(warp_map_control.get_item_metadata(index))=="map_index.json" and not warp_map_control.is_item_disabled(index)),"The internal world manifest must not be offered as a playable warp destination.")
	editor._set_warp_metadata("cave_warp","entrance_map","vinestone_cave.json");editor._set_warp_metadata("cave_warp","entrance_map_warp_id",1)
	assert(editor.document.data.warp_metadata.cave_warp.id is int and MapGraphRef.metadata_destination(editor.document.data,"$.cave_warp",editor.map_directory).map=="vinestone_cave.json","Warp metadata must store numeric IDs and drive double-click navigation before the source map is saved.")
	editor._load_path(editor.map_directory.path_join("eastern_rainforest_route.json"))
	for object in editor.editor_objects:
		if object.path=="$.cave_warp":cave_warp_id=object.id;break
	editor.canvas.object_activated.emit(cave_warp_id)
	assert(editor.document.path.get_file()=="vinestone_cave.json","Double-clicking the cave warp must open Vinestone Cave.")
	var selected_destination:Dictionary=editor._find_object(editor.canvas.selected_id)
	assert(not selected_destination.is_empty() and selected_destination.path=="$.entry","Warp navigation must select the destination entry marker.")
	# Outdoor maps may show linked building context, but their own boundary warps
	# must remain editable in the current map document.
	editor._load_path(editor.map_directory.path_join("rainforest_clearing.json"))
	var north_warp:Dictionary={};var linked_house:Dictionary={};var linked_house_door:Dictionary={}
	for object in editor.editor_objects:
		if object.path=="$.north_warp":north_warp=object
		elif object.get("source_file","")=="rainforest_house.json" and object.path=="$.position":linked_house=object
		elif object.get("source_file","")=="rainforest_house.json" and object.path=="$.door":linked_house_door=object
	assert(not north_warp.is_empty() and not bool(north_warp.get("locked",false)),"The clearing must own its north warp.")
	assert(not linked_house.is_empty() and not linked_house_door.is_empty(),"The clearing must show the linked house exterior and door.")
	editor.canvas.object_activated.emit(String(north_warp.id))
	assert(editor.document.path.get_file()=="canopy_route.json","Double-clicking the linked north warp must open its owning route map.")
	assert(editor._find_object(editor.canvas.selected_id).path=="$.entry","The clearing north warp must navigate to Canopy Route's arrival marker.")
	editor._load_path(editor.map_directory.path_join("jalovea_city.json"))
	var apartment_preview:Dictionary=editor.editor_objects.filter(func(object):return String(object.get("universal_type",""))=="background.citybuilding_apartment_01")[0]
	assert(apartment_preview.footprint_offset==Vector2(0,-apartment_preview.size.z*0.5),"The editor must show the same back-anchored skyscraper collision footprint used by gameplay.")
	var index_terrain:Array=editor.editor_objects.filter(func(object):return object.field=="terrain_tiles")
	assert(not index_terrain.is_empty() and index_terrain.all(func(object):return editor.canvas._is_scalable(object)),"Canonical terrain placed in Jalovea City must retain visible resize handles.")
	var terrain_cells_before:=index_terrain.size();editor.selected_id=String(index_terrain[0].id);editor._delete_selected()
	assert(editor.document.data.terrain_tiles is Array and editor.editor_objects.filter(func(object):return object.field=="terrain_tiles").size()==terrain_cells_before-1,"Deleting selected water or sand must remove only that canonical cell while retaining the required terrain_tiles collection.")
	editor._undo()
	var wall_count_before:int=editor.document.data.objects.size();editor.active_wall_id=""
	editor._wall_anchor_requested(Vector2(20,10));editor._wall_anchor_requested(Vector2(26,12))
	assert(editor.document.data.objects.size()==wall_count_before+1 and editor.document.data.objects[-1].points==[[20.0,10.0],[22.0,10.0],[22.0,12.0],[26.0,12.0]],"Clicking a diagonal wall endpoint must serialize the complete interval-aligned H-V-H route instead of snapping the gesture back to one cardinal line.")
	assert(editor.document.data.objects[-1].baked_segments.size()==3 and editor.document.data.objects[-1].baked_collision.size()==3,"Every generated orthogonal run must bake matching artwork and collision data.")
	editor._load_path(editor.map_directory.path_join("mossvale_city.json"))
	var linked_city_buildings:=0
	for object in editor.editor_objects:
		if object.shape=="building" and bool(object.get("linked",false)):linked_city_buildings+=1
	assert(linked_city_buildings==3,"Mossvale City must show all three linked building exteriors.")
	assert(editor.palette_help.text.contains("shared 'objects' collection"),"The palette must explain how universal entries are serialized.")
	editor._add_palette_object_at(Vector2(8,8),"asset.moss_rose_small");await process_frame
	var variant_record:Dictionary=editor.document.data.objects[-1]
	assert(variant_record.type=="asset.moss_rose_small" and variant_record.variant==0 and String(variant_record.asset_path).ends_with("moss_rose_00.png"),"Placing a numbered sprite family must serialize one tile type plus its initial variant asset path.")
	var variant_object:Dictionary=editor.editor_objects.filter(func(object):return String(object.get("universal_type",""))=="asset.moss_rose_small")[-1]
	editor.selected_id=String(variant_object.id);editor._refresh_inspector();await process_frame
	var variant_selector:=editor.inspector.find_child("AssetVariant",true,false) as OptionButton
	assert(variant_selector!=null and variant_selector.item_count==3,"A grouped numbered sprite must expose all variants in one inspector selector.")
	var scale_standardizer:=editor.inspector.find_child("StandardizeAssetScale",true,false) as CheckBox
	assert(scale_standardizer!=null and scale_standardizer.text.contains("all instances"),"Imported assets must expose a persistent family-wide scale standardizer beside their scale controls.")
	var collision_edit:=editor.inspector.find_child("EditCollisionBox0",true,false) as Button
	assert(collision_edit!=null,"Shared collision rows must expose a direct numeric editor without requiring canvas selection.")
	collision_edit.pressed.emit();await process_frame
	var collision_dialog:=editor.find_child("CollisionBoxDataEditor",true,false) as ConfirmationDialog
	assert(collision_dialog!=null and collision_dialog.find_child("CollisionOffsetX",true,false) is SpinBox and collision_dialog.find_child("CollisionSizeZ",true,false) is SpinBox,"The collision editor must expose offset and three-dimensional size as numeric data fields.")
	collision_dialog.canceled.emit();await process_frame
	variant_selector.item_selected.emit(1);await process_frame
	assert(editor.document.data.objects[-1].variant==1 and String(editor.document.data.objects[-1].asset_path).ends_with("moss_rose_01.png"),"Changing an asset variant must update its serialized variant and runtime texture path together.")
	var anchor_test_wall:Dictionary={"id":"anchor-wall","shape":"wall","wall_points":[Vector2.ZERO,Vector2(2,0),Vector2.ZERO],"position":Vector3.ZERO,"size":Vector3.ONE}
	var anchor_test_building:Dictionary={"id":"anchor-building","shape":"building","position":Vector3.ZERO,"size":Vector3(4,1,4),"footprint":Vector2(4,4)}
	var anchor_test_objects:Array[Dictionary]=[anchor_test_building,anchor_test_wall]
	editor.canvas.set_document_objects(anchor_test_objects,Vector2(20,20));editor.canvas.select_object("anchor-wall")
	var anchor_screen:Vector2=editor.canvas.world_to_screen(Vector2.ZERO);var first_anchor_hit:Dictionary=editor.canvas._wall_anchor_hit(anchor_screen);var second_anchor_hit:Dictionary=editor.canvas._wall_anchor_hit(anchor_screen)
	assert(first_anchor_hit.object.id=="anchor-wall" and first_anchor_hit.index==0,"A selected wall anchor must win hit-testing over an overlapping building.")
	assert(second_anchor_hit.object.id=="anchor-wall" and second_anchor_hit.index==2,"Repeated clicks must cycle through coincident wall endpoints so each serialized point remains editable.")
	editor.document=MapDocumentRef.from_text('{"objects":[{"type":"wall.fence","wall_set":"generic_wall","segment_length":2.0,"points":[[0,0],[1,0],[1,4],[2,4],[2,8]]}]}',"incremental_wall_repair.json");editor.identity_by_path.clear();editor.next_identity=1;editor._refresh_all()
	var repair_wall:Dictionary=editor.editor_objects.filter(func(object):return String(object.get("universal_type",""))=="wall.fence")[0]
	editor._wall_anchor_moved(String(repair_wall.id),0,Vector2(-1,0))
	assert(editor.document.data.objects[0].points[0]==[-1.0,0.0] and WallGeometryRef.invalid_segment_count(editor.document.data.objects[0].points)==0,"A corrective drag on a legacy wall must persist while the remaining anchors normalize onto its 2-unit lattice.")
	print("MAP_EDITOR_UI_TEST_PASSED")
	quit()
