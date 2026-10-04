extends SceneTree

const Document := preload("res://core/map_document.gd")

func _initialize() -> void:
	create_timer(30).timeout.connect(func():push_error("NPC_EDITOR_TIMEOUT");quit(2))
	var editor := (load("res://map_editor.tscn") as PackedScene).instantiate()
	root.add_child(editor)
	await process_frame
	editor._new_document()
	assert(editor.npc_visuals.sprites("human")==["Young Man","Young Woman","Young Boy","Young Girl"])
	assert(editor.npc_visuals.sprites("fakemon").has("Sylvafin"))
	assert(editor.npc_visuals.sprites("fakemon").has("Celestraal"),"The existing evolved-species registry must also provide NPC sprites.")
	editor._add_npc()
	assert(editor.document.data.npcs[0]=={"id":1,"position":[0.0,0.0,0.0],"facing":"down"})
	assert(editor.npc_data.definitions["1"]=={"type":"human","sprite":"Young Man","interaction_text":""})
	assert(editor.canvas.get_node_or_null("NpcType")==null) # Inspector, not a new canvas placement subsystem.
	var first:Dictionary=editor._find_object(editor.selected_id)
	assert(first.resolved_texture != null)
	var facing:=editor.inspector.get_node("NpcFacing") as OptionButton
	facing.select(3);facing.item_selected.emit(3)
	assert(editor.document.data.npcs[0].facing=="right")
	var text:=editor.inspector.get_node("NpcInteractionText") as TextEdit
	text.text="Hello from checkpoint one!";text.text_changed.emit()
	assert(editor.npc_data.definitions["1"].interaction_text==text.text)
	var before:Dictionary=editor.npc_data.definitions.duplicate(true)
	var start:Vector2=editor.canvas.world_to_screen(Vector2.ZERO)
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=start
	editor.canvas._gui_input(press)
	var motion:=InputEventMouseMotion.new();motion.button_mask=MOUSE_BUTTON_MASK_LEFT;motion.position=start+Vector2(2,-3)*editor.canvas.pixels_per_unit*editor.canvas.zoom
	editor.canvas._gui_input(motion)
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=motion.position
	editor.canvas._gui_input(release)
	assert(editor.document.data.npcs[0].position==[2.0,0.0,-3.0])
	assert(editor.npc_data.definitions==before,"Drag must update placement only.")
	editor._undo();assert(editor.document.data.npcs[0].position==[0.0,0.0,0.0])
	editor._redo();assert(editor.document.data.npcs[0].position==[2.0,0.0,-3.0])
	editor._add_npc()
	var types:=editor.inspector.get_node("NpcType") as OptionButton
	types.select(1);types.item_selected.emit(1)
	assert(editor.document.data.npcs[1].facing=="down")
	var sprites:=editor.inspector.get_node("NpcSprite") as OptionButton
	for i in sprites.item_count:
		if sprites.get_item_metadata(i)=="Sylvafin":sprites.select(i);sprites.item_selected.emit(i);break
	assert(editor.npc_data.definitions["2"].sprite=="Sylvafin")
	editor.document.set_value("$.npcs[1].position",[-4.0,0.25,5.0])
	editor.document.set_value("$.npcs[1].facing","up")
	editor.npc_data.definitions["2"].interaction_text="Sylvafin says hello."
	editor._add_npc()
	assert(editor.document.data.npcs[2].id==3)
	editor.document.set_value("$.npcs[2].position",[6.0,0.0,2.0])
	editor.npc_data.definitions["3"].interaction_text="A separate Young Man."
	var map_before:Dictionary=editor.document.data.duplicate(true)
	var definitions_before:Dictionary=editor.npc_data.definitions.duplicate(true)
	var path:=ProjectSettings.globalize_path("res://tests/generated/npc_checkpoint.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert(editor._save_npc_pair(path,editor.npc_data.issues(editor.document.data,editor.npc_visuals))==OK)
	editor._load_path(path)
	assert(editor.document.semantic_equivalent(Document.from_text(JSON.stringify(map_before))) and editor.npc_data.definitions==definitions_before)
	for placement:Dictionary in editor.document.data.npcs:
		assert(placement.keys().size()==3 and placement.has("id") and placement.has("position") and placement.has("facing"))
	for definition:Dictionary in editor.npc_data.definitions.values():
		assert(definition.keys().size()==3 and definition.has("type") and definition.has("sprite") and definition.has("interaction_text"))
	assert(editor.npc_data.definitions["1"].sprite==editor.npc_data.definitions["3"].sprite)
	for object:Dictionary in editor.editor_objects:
		if object.get("npc_id")==2:editor.canvas.select_object(String(object.id));break
	editor._delete_selected()
	assert(editor.document.data.npcs.map(func(n):return int(n.id))==[1,3])
	assert(not editor.npc_data.definitions.has("2"))
	editor._undo();assert(editor.npc_data.definitions.has("2") and editor.document.data.npcs.size()==3)
	editor._redo();assert(not editor.npc_data.definitions.has("2"))
	var stable_path:=path.get_base_dir().path_join("npc_stability.json")
	assert(editor._save_npc_pair(stable_path,[])==OK)
	editor._load_path(stable_path)
	assert(editor.document.data.npcs.map(func(n):return int(n.id))==[1,3])
	editor._add_npc();assert(editor.document.data.npcs[-1].id==4)
	editor._duplicate_selected();assert(editor.document.data.npcs[-1].id==5)
	# Movement settings belong to definitions and share the existing history/save path.
	var movement:=editor.inspector.get_node("NpcMovement") as OptionButton
	for i in movement.item_count:
		if movement.get_item_metadata(i)=="clockwise":movement.select(i);movement.item_selected.emit(i);break
	var range_x:=editor.inspector.get_node("NpcRangeX") as SpinBox;range_x.value=3.5
	var range_y:=editor.inspector.get_node("NpcRangeY") as SpinBox;range_y.value=1.25
	assert(editor.npc_data.definitions["4"].movement=={"preset":"clockwise","range":[3.5,1.25]})
	editor._undo();assert(editor.npc_data.definitions["4"].movement.range[1]==2.0)
	editor._redo();assert(editor.npc_data.definitions["4"].movement.range[1]==1.25)
	var mode_picker:=editor.inspector.get_node("NpcMovementMode") as OptionButton
	for i in mode_picker.item_count:
		if mode_picker.get_item_metadata(i)=="flying":mode_picker.select(i);mode_picker.item_selected.emit(i);break
	var height_offset:=editor.inspector.get_node("NpcHeightOffset") as SpinBox;height_offset.value=0.7
	assert(editor.npc_data.definitions["4"].movement_mode=="flying" and is_equal_approx(editor.npc_data.definitions["4"].height_offset,0.7))
	editor._undo();assert(not editor.npc_data.definitions["4"].has("height_offset"))
	editor._redo();assert(is_equal_approx(editor.npc_data.definitions["4"].height_offset,0.7))
	var movement_path:=path.get_base_dir().path_join("npc_movement.json")
	assert(editor._save_npc_pair(movement_path,[])==OK)
	editor._load_path(movement_path)
	assert(editor.npc_data.definitions["4"].movement=={"preset":"clockwise","range":[3.5,1.25]})
	assert(editor.npc_data.definitions["4"].movement_mode=="flying" and is_equal_approx(editor.npc_data.definitions["4"].height_offset,0.7))
	assert(editor.document.data.npcs.all(func(n):return n.size()==3))
	# Invalid companion and placements block save without replacing either file.
	editor.npc_data.definitions["1"].sprite="unregistered"
	assert(editor._save_npc_pair(stable_path,editor.npc_data.issues(editor.document.data,editor.npc_visuals))==ERR_INVALID_DATA)
	assert(Document.load_file(stable_path).data.npcs.size()==2)
	editor.queue_free()
	await process_frame
	print("NPC_EDITOR_TESTS_PASSED: defaults, selectors, text, drag, undo/redo, paired roundtrip, ID stability, shared sprite, deletion, duplication, save protection")
	quit()
