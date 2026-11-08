extends SceneTree

var failed:=false

func check(condition:bool,message:String)->void:
	if not condition:failed=true;push_error(message)

func _initialize()->void:
	var editor:Control=load("res://map_editor.gd").new()
	root.add_child(editor)
	await process_frame
	editor._load_path(editor.map_directory.path_join("tropical_research_institute_indoor.json"))
	var displays:Array=editor.editor_objects.filter(func(object):return String(object.get("universal_type",""))=="asset.indoor_display")
	check(not displays.is_empty(),"The lab fixture must contain a display tile.")
	if not displays.is_empty():
		editor.selected_id=String(displays[0].id)
		editor._refresh_inspector()
		var textbox:TextEdit=editor.inspector.find_child("IndoorDisplayTextbox",true,false)
		check(textbox!=null,"Display tiles must expose a multiline textbox editor.")
		if textbox!=null:
			textbox.text="Research notes\nSecond line."
			textbox.focus_exited.emit()
			check(editor._get_path(displays[0].path).interaction_text==textbox.text,"Textbox edits must serialize on the display instance.")
	var option:OptionButton=editor.terrain_type_option
	check(editor.catalog.by_id["asset.indoor_display"].variants.any(func(value):return int(value.value)==2 and String(value.asset_path).ends_with("indoor_display_02.png")),"Display variant 02 must be available in the existing display family.")
	for type_id in ["asset.indoor_display_fossil","asset.indoor_billboard_tropical_research"]:
		check(editor.catalog.by_id.has(type_id),"The new billboard must be available: "+type_id)
		if editor.catalog.by_id.has(type_id):
			var entry:Dictionary=editor.catalog.by_id[type_id]
			var metadata:Dictionary=editor.AssetCatalogRef.load_metadata(editor.project_root.path_join(String(entry.asset_path).trim_prefix("res://")))
			check(metadata.collision_boxes.size()==1 and entry.scale_mode=="target_height","New billboards must use the shared editable collision system.")
	check(editor.catalog.by_id.has("terrain.indoor_floor_tile_00"),"The new floor must be registered as canonical terrain.")
	var new_resolver:Script=load(editor.project_root.path_join("world/terrain_transition_resolver.gd"))
	check(new_resolver.terrain_grid({"size":[4,4],"base_terrain_type":"indoor_floor_tile_00"}).get(Vector2i.ZERO)=="indoor_floor_tile_00","The new floor must work as runtime base terrain.")
	editor.canvas.placement_preview=true
	var projected_x:Vector2=editor.canvas.world_to_screen(Vector2.RIGHT)-editor.canvas.world_to_screen(Vector2.ZERO)
	var projected_z:Vector2=editor.canvas.world_to_screen(Vector2.DOWN)-editor.canvas.world_to_screen(Vector2.ZERO)
	check(is_equal_approx(projected_z.length()/projected_x.length(),sqrt(0.5)),"Placement preview must match the runtime camera's ground compression.")
	check(editor.canvas.screen_to_world(editor.canvas.world_to_screen(Vector2(3,4))).is_equal_approx(Vector2(3,4)),"Preview coordinates must retain an exact inverse projection.")
	var preview_wall:={"field":"wall_blocks","shape":"rectangle","position":Vector3.ZERO,"size":Vector3(4,0.3,2)}
	var preview_prop:={"field":"objects","shape":"point","position":Vector3(0,0,0.5)}
	check(editor.canvas._draws_before(preview_prop,preview_wall),"A prop behind the wall's front edge must be occluded in placement preview.")
	preview_prop.position.z=1.5
	check(editor.canvas._draws_before(preview_wall,preview_prop),"A prop in front of the wall must remain visible in placement preview.")
	editor.canvas.placement_preview=false
	var walls:Array=editor.editor_objects.filter(func(object):return object.field=="wall_blocks")
	check(not walls.is_empty(),"The indoor map must expose wall blocks.")
	if not walls.is_empty():
		editor._set_wall_collision(walls[0],"offset",[0,0,0.5])
		editor._set_wall_collision(walls[0],"size",[1,0.3,3])
		var block:Array=editor._get_path(walls[0].path)
		check(block.size()==7 and block[6].offset==[0,0,0.5] and block[6].size==[1,0.3,3],"Independent wall collider controls must serialize in the wall record.")
		check(editor.editor_objects.any(func(object):return object.field=="wall_blocks" and object.has("wall_collision")),"Custom colliders must retain selectable wall artwork and an outline.")
		var wall_errors:Array=editor.MapValidatorRef.validate(editor.document).filter(func(issue):return issue.severity=="error" and String(issue.path).contains("wall_blocks"))
		check(wall_errors.is_empty(),"Wall collider overrides must pass the map schema validator.")
	check(editor._entry_for("return_warp",-1).preview_texture=="assets/overworld/warp_building_generic.png","Indoor warp previews must use the runtime rug texture.")
	var found:=-1
	for index in option.item_count:
		if String(option.get_item_metadata(index))=="indoor_floor_tile":found=index
	check(found>=0,"The terrain brush must offer Indoor Floor Tile.")
	if found>=0:
		check(option.get_item_text(found)=="Indoor Floor Tile","The terrain must use its catalog display name.")
		option.select(found)
		check(editor.document.data.base_terrain_type=="indoor_floor_tile","The lab must use the indoor floor as its base terrain.")
		check(editor._base_terrain_texture_path()=="assets/overworld/tile_interior_floor_tiles.png","The base preview must use the existing indoor texture.")
		check(editor._compatible_array_field(editor.catalog.by_id["block.interior_wall"])=="wall_blocks","Interior walls must be placeable on the lab map.")
		editor._terrain_stroke_started()
		editor._terrain_cell_changed(Vector2i.ZERO,false)
		editor._terrain_stroke_finished()
		var errors:Array=editor.MapValidatorRef.validate(editor.document).filter(func(issue):return issue.severity=="error" and String(issue.path).contains("terrain"))
		check(errors.is_empty(),"Painted indoor terrain must pass canonical terrain validation.")
		var resolver:Script=load(editor.project_root.path_join("world/terrain_transition_resolver.gd"))
		check(String(resolver.terrain_grid(editor.document.data).get(Vector2i.ZERO,""))=="indoor_floor_tile","Runtime terrain preparation must preserve the painted indoor floor.")
	print("INDOOR_TERRAIN_TEST_PASSED" if not failed else "INDOOR_TERRAIN_TEST_FAILED")
	quit(1 if failed else 0)
