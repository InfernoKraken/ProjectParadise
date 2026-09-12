extends SceneTree

func _initialize()->void:
	create_timer(8.0).timeout.connect(func():push_error("BRIDGE_EDITOR_UI_TEST_TIMEOUT");quit(2))
	var editor:Control=(load("res://map_editor.tscn") as PackedScene).instantiate();root.add_child(editor);await process_frame
	var bridge:Dictionary={}
	for object in editor.editor_objects:
		if object.get("universal_type","")=="structure.bridge":bridge=object;break
	assert(not bridge.is_empty() and bridge.shape=="bridge" and bridge.footprint==Vector2(1,5),"The authored vertical bridge must render its width-by-length footprint.")
	editor.selected_id=String(bridge.id);editor._refresh_inspector();await process_frame
	for control_name in ["BridgeOrientation","BridgeLength","BridgeWidth","BridgeElevation","BridgeEntranceLength","BridgeTraversalLayer"]:
		assert(editor.inspector.find_child(control_name,true,false)!=null,"Bridge inspector must expose "+control_name.trim_prefix("Bridge")+".")
	var record:Dictionary=editor._get_path(String(bridge.path));record["future_ui_field"]=17
	editor._set_bridge_field(bridge,"orientation","horizontal");editor._set_bridge_field(bridge,"length",7);editor._set_bridge_field(bridge,"width",2.0)
	var updated:Dictionary=editor._find_object(String(bridge.id))
	assert(updated.footprint==Vector2(7,2) and record.future_ui_field==17,"Bridge edits must update its oriented footprint and retain unknown fields.")
	assert(editor.MapValidatorRef.validate(editor.document).filter(func(issue):return issue.severity=="error").is_empty(),"The edited eastern route must remain valid.")
	print("BRIDGE_EDITOR_UI_TEST_PASSED");quit(0)
