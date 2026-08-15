extends SceneTree

func _initialize() -> void:
	# Ensure assertion failures cannot leave a headless SceneTree running forever.
	create_timer(8.0).timeout.connect(func(): push_error("MAP_EDITOR_UI_TEST_TIMEOUT"); quit(2))
	var scene := load("res://map_editor.tscn") as PackedScene
	var editor := scene.instantiate()
	root.add_child(editor)
	await process_frame
	var north_screen: Vector2 = editor.canvas.world_to_screen(Vector2(0,-5))
	var south_screen: Vector2 = editor.canvas.world_to_screen(Vector2(0,5))
	assert(north_screen.y < south_screen.y, "The editor canvas must display negative Z north/up, matching gameplay.")
	var before: int = editor.document.data.trees.size()
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
	editor.selected_palette_entry="building.house";editor._add_palette_object_at(Vector2(3,4))
	assert(editor.document.data.objects[-1].type=="building.house" and editor.document.data.objects[-1].size==[5.0,3.0,4.0], "House exteriors must be placeable on any outdoor map as universal objects.")
	editor.selected_palette_entry="building.medical_ward";editor._add_palette_object_at(Vector2(-3,4))
	assert(editor.document.data.objects[-1].type=="building.medical_ward", "Medical ward exteriors must be placeable on any outdoor map.")
	editor.selected_palette_entry="npc.generic";editor._add_palette_object_at(Vector2(0,1))
	assert(editor.document.data.objects[-1].type=="npc.generic" and editor.document.data.objects[-1].dialogue.size()==1,"Dialogue-only NPCs must be placeable on every map.")
	editor.selected_palette_entry="npc.opponent";editor._add_palette_object_at(Vector2(0,-1))
	assert(editor.document.data.objects[-1].type=="npc.opponent" and editor.document.data.objects[-1].team[0]=={"fakemon":0,"level":5},"Trainer drops must include editable dialogue and a default Fakemon/level team.")
	var parsed_team:Array=editor._parse_team("Scorchick:8, 1:12")
	assert(parsed_team==[{"fakemon":"Scorchick","level":8},{"fakemon":1,"level":12}],"Trainer team text must accept Fakemon names or indices with levels.")
	var cave: MapDocument = editor.MapDocumentRef.load_file(editor.map_directory.path_join("vinestone_cave.json"))
	editor.document=cave
	assert(editor._compatible_array_field(vine_entry)=="vines", "Cave vines must be placeable when editing Vinestone Cave.")
	# Restore the route and verify the two rectangle schemas are emitted exactly.
	editor.document=editor.MapDocumentRef.load_file(editor.map_directory.path_join("eastern_rainforest_route.json"))
	editor._refresh_all()
	var water_before:int=editor.document.data.water_blocks.size()
	assert(editor.document.data.sand_blocks.size()>0,"Existing route water must have explicit sand-border blocks.")
	var sand_entry:Dictionary=editor.catalog.by_id["block.sand"]
	assert(editor._compatible_array_field(sand_entry)=="sand_blocks","Sand shore blocks must be placeable on outdoor maps.")
	editor.selected_palette_entry="block.water"
	editor._add_palette_object_at(Vector2(2,-3))
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
	var building_object:Dictionary={};var floor_object:Dictionary={};var wall_count:=0;var furnishing_count:=0
	for object in editor.editor_objects:
		if object.shape=="building":building_object=object
		elif object.field=="floor_blocks":floor_object=object
		elif object.field=="wall_blocks":wall_count+=1
		elif object.field=="furnishings":furnishing_count+=1
	assert(not building_object.is_empty() and is_equal_approx(float(building_object.display_width),4.6),"House exteriors must use the runtime's size-derived preview width.")
	assert(building_object.footprint==Vector2(4,3),"House exterior selection must show its serialized X/Z collision footprint.")
	assert(not floor_object.is_empty() and wall_count==3,"Serialized interior floor and wall blocks must appear as editable building tiles.")
	assert(furnishing_count==editor.document.data.furnishings.size() and furnishing_count>=4,"Every serialized rainforest-house furnishing must appear in the editor.")
	assert(editor.canvas._draw_rank(floor_object)==0,"Floor blocks must remain below walls, props, markers, and cave objects.")
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
	editor._load_path(editor.map_directory.path_join("mossvale_city.json"))
	var linked_city_buildings:=0
	for object in editor.editor_objects:
		if object.shape=="building" and bool(object.get("linked",false)):linked_city_buildings+=1
	assert(linked_city_buildings==3,"Mossvale City must show all three linked building exteriors.")
	assert(editor.palette_help.text.contains("shared 'objects' collection"),"The palette must explain how universal entries are serialized.")
	print("MAP_EDITOR_UI_TEST_PASSED")
	quit()
