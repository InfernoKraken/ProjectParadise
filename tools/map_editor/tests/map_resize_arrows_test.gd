extends SceneTree

const Pruner:=preload("res://core/map_bounds_pruner.gd")
const Document:=preload("res://core/map_document.gd")

func _initialize()->void:
	create_timer(30.0).timeout.connect(func():push_error("MAP_RESIZE_ARROWS_TIMEOUT");quit(2))
	var fixture:={"size":[20,20],"map_metadata":{"layout_type":"outdoor"},"entry":[9,0,0],"warp_2":[9,0,0],"warp_metadata":{"warp_2":{"id":2}},"arrival_points":{"warp_2":[9,0,0]},"objects":[{"type":"asset.flower_tall_banana_plant","instance_id":"outside","position":[9,0,0]},{"type":"asset.flower_tall_banana_plant","position":[0,0,0]},{"type":"overlay.heliconia_hanging","position":[0,0,0],"is_attached":true,"host_id":"outside"}],"terrain_tiles":[{"terrain_type":"sand","positions":[[0,0],[9,0],[-9,0]]},{"terrain_type":"water","position":[10,10]}],"trees":[[9,0,0,1],[0,0,0,0]],"npcs":[{"id":1,"position":[9,0,0],"facing":"down"}],"floor_blocks":[[9,0,0,1,1,1]],"grass_zones":[{"position":[9,0,0],"size":[1,1,1]}]}
	var cropped:Dictionary=fixture.duplicate(true)
	Pruner.prune(cropped,Vector2(10,20))
	assert(cropped.objects.size()==1 and cropped.trees.size()==1 and cropped.npcs.is_empty())
	assert(cropped.floor_blocks.is_empty() and cropped.grass_zones.is_empty())
	assert(cropped.terrain_tiles.size()==1 and cropped.terrain_tiles[0].positions==[[0,0]])
	assert(not cropped.has("warp_2") and not cropped.warp_metadata.has("warp_2") and not cropped.arrival_points.has("warp_2"))
	assert(is_equal_approx(float(cropped.entry[0]),5.0) and is_zero_approx(float(cropped.entry[2])))
	var walls:={"objects":[{"type":"wall.fence","points":[[-9,0],[9,0]]},{"type":"wall.fence","points":[[8,8],[9,9]]}]}
	Pruner.prune(walls,Vector2(10,10));assert(walls.objects.size()==1,"Retain walls crossing the bounds; remove fully outside walls.")
	var editor=load("res://map_editor.tscn").instantiate();root.add_child(editor);await process_frame
	editor.document=Document.from_text(JSON.stringify(fixture),"resize_fixture.json");editor._refresh_all()
	editor._set_activity(0);assert(not editor.canvas.map_resize_enabled)
	editor._set_activity(2);assert(editor.canvas.map_resize_enabled)
	await process_frame
	editor.canvas.frame_all()
	var cases:Array[Dictionary]=[]
	for edge in ["east","west","north","south"]:
		for change in [-5,5]:cases.append({"edge":edge,"change":change})
	for scenario:Dictionary in cases:
		var edge:String=scenario.edge;var change:float=scenario.change
		var before:String=editor.document.deterministic_json()
		var old_bounds:=Rect2(editor._map_center()-editor._map_size()*0.5,editor._map_size())
		var object_screen:Vector2=editor.canvas.world_to_screen(Vector2.ZERO)
		var start:Vector2=editor.canvas._map_resize_handles()[edge].get_center()
		var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=start;editor.canvas._gui_input(press)
		assert(editor.canvas.map_resizing and editor.canvas.map_resize_edge==edge)
		var direction:Vector2={"east":Vector2.RIGHT,"west":Vector2.LEFT,"north":Vector2.UP,"south":Vector2.DOWN}[edge]*signf(change)
		var motion:=InputEventMouseMotion.new();motion.position=start+direction*5*editor.canvas.pixels_per_unit*editor.canvas.zoom*editor.canvas._ground_projection();motion.button_mask=MOUSE_BUTTON_MASK_LEFT;editor.canvas._gui_input(motion)
		press.pressed=false;press.position=motion.position;editor.canvas._gui_input(press)
		var dimensions:Vector2=editor._map_size()
		var new_bounds:=Rect2(editor._map_center()-dimensions*0.5,dimensions)
		assert(editor._map_center().is_equal_approx(direction*2.5))
		if edge=="east":assert(new_bounds.position==old_bounds.position and new_bounds.end.y==old_bounds.end.y)
		if edge=="west":assert(new_bounds.end==old_bounds.end and new_bounds.position.y==old_bounds.position.y)
		if edge=="north":assert(new_bounds.end==old_bounds.end and new_bounds.position.x==old_bounds.position.x)
		if edge=="south":assert(new_bounds.position==old_bounds.position and new_bounds.end.x==old_bounds.end.x)
		assert(editor.canvas.world_to_screen(Vector2.ZERO)==object_screen,"Resizing must not move retained elements on the canvas.")
		assert(dimensions==Vector2(20+change,20) if edge in ["east","west"] else dimensions==Vector2(20,20+change))
		if edge=="east" and change<0:assert(editor.document.data.objects.size()==1)
		if change>0:assert(editor.document.data.objects.size()==3,"Expansion must preserve all placements.")
		var saved=Document.from_text(editor.document.deterministic_json(),"reload.json");assert(saved.data.size==editor.document.data.size)
		assert(saved.data.bounds_center==editor.document.data.bounds_center)
		editor._undo();assert(editor.document.deterministic_json()==before,"One undo restores dimensions and every removed placement.")
		editor._redo();assert(editor._map_size()==dimensions and editor._map_center().is_equal_approx(direction*2.5));editor._undo()
	# Cancelling a drag or leaving Map must preserve the document and preview.
	var start:Vector2=editor.canvas._map_resize_handles().east.get_center()
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=start;editor.canvas._gui_input(press)
	var motion:=InputEventMouseMotion.new();motion.position=start+Vector2(40,0);editor.canvas._gui_input(motion)
	editor._set_activity(1);assert(not editor.canvas.map_resize_enabled and editor.canvas.map_size==editor._map_size())
	editor._set_activity(2)
	editor._set_numeric_component("size",0,10);assert(editor.document.data.objects.size()==1);editor._undo()
	var before_expand:String=editor.document.deterministic_json()
	editor._on_map_resized(Vector2(20,20),Vector2(30,20))
	assert(editor.document.data.objects.size()==3 and editor.document.data.terrain_tiles.size()==2,"Expansion must preserve every placement.")
	editor._undo();assert(editor.document.deterministic_json()==before_expand)
	# An arrow must capture the drag even if a terrain brush was left active.
	editor.canvas.terrain_brush_mode="paint"
	press.pressed=true;press.position=editor.canvas._map_resize_handles().east.get_center();editor.canvas._gui_input(press)
	motion.position=press.position+Vector2(40,0);editor.canvas._gui_input(motion)
	var cancel:=InputEventKey.new();cancel.keycode=KEY_ESCAPE;cancel.pressed=true;editor.canvas._gui_input(cancel)
	assert(not editor.canvas.map_resizing and editor.canvas.map_size==editor._map_size() and editor.document.deterministic_json()==before_expand)
	editor.canvas.terrain_brush_mode="select"
	if "--capture" in OS.get_cmdline_user_args():
		editor._load_path(editor.map_directory.path_join("jalovea_city.json"));editor._set_activity(2);editor.canvas.frame_all()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/generated/map_resize_arrows.png")
	print("MAP_RESIZE_ARROWS_PASSED");quit()
