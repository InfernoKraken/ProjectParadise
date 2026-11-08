extends SceneTree

var failed:=false
func check(condition:bool,message:String)->void:
	if not condition:failed=true;push_error(message)

func _initialize()->void:
	create_timer(15).timeout.connect(func():push_error("INDOOR_VISUAL_TEST_TIMEOUT");quit(2))
	var editor:Control=load("res://map_editor.gd").new()
	root.add_child(editor)
	await process_frame
	editor._load_path(editor.map_directory.path_join("tropical_research_institute_indoor.json"))
	var table:Dictionary=editor.catalog.by_id["asset.indoor_lab_table_specimen"]
	check(float(table.get("sort_offset_y",0))<0,"The specimen table must sort behind a tank at the same anchor.")
	editor.document.data.warp_metadata.return_warp.show_sprite=false
	editor._refresh_all()
	var warp:Array=editor.editor_objects.filter(func(object):return object.field=="return_warp")
	check(not warp.is_empty() and not warp[0].get("preview_visible",true),"Hidden warps must be hidden in placement preview.")
	var billboards:Array=editor.editor_objects.filter(func(object):return String(object.get("universal_type",""))=="asset.indoor_billboard_tropical_research")
	check(not billboards.is_empty(),"The lab must contain the research billboard fixture.")
	if not billboards.is_empty():
		editor.selected_id=String(billboards[0].id);editor._refresh_inspector()
		check(editor.inspector.find_child("IndoorDisplayTextbox",true,false)!=null,"The research billboard must expose the existing textbox editor.")
	editor.canvas.placement_preview=true
	editor.canvas.objects.clear()
	editor.canvas.objects.append({"field":"wall_blocks","position":Vector3.ZERO,"size":Vector3(4,0.3,2)})
	var sign:={"field":"objects","position":Vector3.ZERO,"wall_overlay":true}
	check(is_equal_approx(editor.canvas._draw_depth(sign),1.001),"Signs must sort just above their supporting wall.")
	check(editor.canvas._draw_depth(sign)<editor.canvas._draw_depth({"position":Vector3(0,0,1.2)}),"A player or NPC in front must cover the wall sign.")
	editor.canvas.objects.clear()
	print("INDOOR_VISUAL_BEHAVIOR_PASSED" if not failed else "INDOOR_VISUAL_BEHAVIOR_FAILED")
	quit(1 if failed else 0)
