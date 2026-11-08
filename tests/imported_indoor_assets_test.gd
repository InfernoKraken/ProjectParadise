extends SceneTree

func _initialize()->void:
	var main=load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false);main.set_physics_process(false)
	var objects:Array=[]
	for asset_name in ["indoor_display_fossil","indoor_billboard_tropical_research","indoor_lab_desk_small","indoor_lab_desk_down","indoor_lab_desk_up","indoor_lab_table_specimen","indoor_couch_double","indoor_couch_r_facing","indoor_couch_l_facing","indoor_aquarium_long"]:
		objects.append({"type":"asset."+asset_name,"asset_path":"res://assets/overworld/"+asset_name+".png","position":[0,0,0],"size":[1,1,1],"height":1})
	main._build_universal_objects({"objects":objects},Vector3(2000,0,2000),"ImportedBillboards",true)
	var passed:=true
	for index in objects.size():
		var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(String(objects[index].asset_path).trim_suffix(".png")+".json"))
		var polygon:bool=String(metadata.get("collision",{}).get("type",""))=="polygon"
		if not polygon and metadata.get("collision_boxes",[]).is_empty():continue
		var collision_name:="ImportedBillboardsUniversalObject%d"%index+("AssetPolygonCollision" if polygon else "AssetCollision0")
		if not main.world.get_node_or_null(collision_name) is StaticBody3D:
			passed=false;push_error("Imported billboard must build its editable collision box.")
	main._build_universal_objects({"objects":[{"type":"asset.indoor_billboard_tropical_research","asset_path":"res://assets/overworld/indoor_billboard_tropical_research.png","position":[0,0,0],"size":[1,1,1],"interaction_text":"Research notes"}]},Vector3.ZERO,"TextBillboard",true)
	if main.object_sort_entries[-1].get("interaction_text","")!="Research notes":passed=false;push_error("Research billboard must preserve its textbox text.")
	for variant in ["00","01","02"]:
		main._build_universal_objects({"objects":[{"type":"asset.indoor_display","asset_path":"res://assets/overworld/indoor_display_"+variant+".png","position":[0,0,0],"size":[1,1,1],"interaction_text":"Exhibit notes"}]},Vector3.ZERO,"DisplayOverlay"+variant,true)
		var entry:Dictionary=main.object_sort_entries[-1]
		if not bool(entry.get("wall_overlay",false)) or int(entry.get("render_band",0))!=0 or entry.get("interaction_text","")!="Exhibit notes":passed=false;push_error("Wall display must use depth sorting and preserve textbox interaction.")
	print("IMPORTED_INDOOR_ASSETS_PASSED" if passed else "IMPORTED_INDOOR_ASSETS_FAILED")
	quit(0 if passed else 1)
