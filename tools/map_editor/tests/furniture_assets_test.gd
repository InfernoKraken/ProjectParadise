extends SceneTree

func _initialize()->void:
	var project_root:=ProjectSettings.globalize_path("res://").simplify_path().get_base_dir().get_base_dir()
	var catalog=preload("res://core/asset_catalog.gd").load_catalog(ProjectSettings.globalize_path("res://catalog/map_asset_catalog.json"))
	var passed:=true
	for asset in ["indoor_lab_desk_small","indoor_lab_desk_down","indoor_lab_desk_up","indoor_lab_table_specimen","indoor_couch_double","indoor_couch_r_facing","indoor_couch_l_facing","indoor_aquarium_long"]:
		if not catalog.by_id.has("asset."+asset):passed=false;push_error("Missing imported furniture: "+asset);continue
		var metadata:Dictionary=catalog.load_metadata(project_root.path_join("assets/overworld/"+asset+".png"))
		if metadata.get("collision_boxes",[]).is_empty():passed=false;push_error("Missing editable collision for "+asset)
	if not bool(catalog.by_id["asset.indoor_display"].get("wall_overlay",false)):passed=false;push_error("Display family must use wall overlay depth.")
	print("FURNITURE_ASSETS_PASSED" if passed else "FURNITURE_ASSETS_FAILED")
	quit(0 if passed else 1)
