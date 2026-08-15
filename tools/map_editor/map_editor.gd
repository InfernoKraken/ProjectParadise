extends Control

const MapDocumentRef := preload("res://core/map_document.gd")
const MapSchemaRef := preload("res://core/map_schema.gd")
const MapValidatorRef := preload("res://core/map_validator.gd")
const MapGraphRef := preload("res://core/map_graph.gd")
const AssetCatalogRef := preload("res://core/asset_catalog.gd")
const CanvasRef := preload("res://ui/editor_canvas.gd")

var project_root := ""
var map_directory := ""
var document: MapDocument
var catalog: AssetCatalog
var canvas: EditorCanvas
var palette: ItemList
var palette_help: Label
var inspector: VBoxContainer
var validation_list: ItemList
var raw_json: TextEdit
var graph_text: RichTextLabel
var status_label: Label
var grid_spin: SpinBox
var snap_check: CheckBox
var metadata_box: VBoxContainer
var issues: Array[Dictionary] = []
var editor_objects: Array[Dictionary] = []
var selected_id := ""
var selected_palette_entry := ""
var undo_stack: Array[String] = []
var redo_stack: Array[String] = []
var open_dialog: FileDialog
var save_dialog: FileDialog
var unsaved_dialog: ConfirmationDialog
var pending_action: Callable
var pending_navigation_target: Dictionary = {}
var updating_inspector := false
var identity_by_path: Dictionary = {}
var next_identity := 1
var palette_dragging := false
var palette_drag_entry := ""
var palette_press_entry := ""
var palette_drag_preview: PanelContainer
var palette_drag_preview_label: Label
var palette_index_by_type: Dictionary = {}

func _ready() -> void:
	project_root = ProjectSettings.globalize_path("res://").simplify_path().get_base_dir().get_base_dir()
	map_directory = project_root.path_join("data/maps")
	catalog = AssetCatalogRef.load_catalog(ProjectSettings.globalize_path("res://catalog/map_asset_catalog.json"))
	_build_ui()
	_load_path(map_directory.path_join("eastern_rainforest_route.json"))

func _build_ui() -> void:
	var root_v := VBoxContainer.new(); root_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root_v)
	var toolbar := HBoxContainer.new(); toolbar.custom_minimum_size.y = 42; root_v.add_child(toolbar)
	_add_button(toolbar, "New", _request_new)
	_add_button(toolbar, "Open", _request_open)
	_add_button(toolbar, "Save", _save)
	_add_button(toolbar, "Save As", _save_as)
	toolbar.add_child(VSeparator.new())
	_add_button(toolbar, "Undo", _undo)
	_add_button(toolbar, "Redo", _redo)
	_add_button(toolbar, "Duplicate", _duplicate_selected)
	_add_button(toolbar, "Delete", _delete_selected)
	toolbar.add_child(VSeparator.new())
	var grid_label := Label.new(); grid_label.text = "Grid"; toolbar.add_child(grid_label)
	grid_spin = SpinBox.new(); grid_spin.min_value=0.05; grid_spin.max_value=8; grid_spin.step=0.05; grid_spin.value=1; grid_spin.custom_minimum_size.x=85; grid_spin.value_changed.connect(func(v): canvas.grid_size=v; canvas.queue_redraw()); toolbar.add_child(grid_spin)
	snap_check = CheckBox.new(); snap_check.text="Snap"; snap_check.button_pressed=true; snap_check.toggled.connect(func(v): canvas.snapping=v); toolbar.add_child(snap_check)
	_add_button(toolbar, "Frame Map", func(): canvas.frame_all())
	status_label = Label.new(); status_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; toolbar.add_child(status_label)

	var split := HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; root_v.add_child(split)
	var left := VBoxContainer.new(); left.custom_minimum_size.x=250; split.add_child(left)
	var pal_title := Label.new(); pal_title.text="OBJECT PALETTE"; left.add_child(pal_title)
	palette = ItemList.new(); palette.size_flags_vertical=Control.SIZE_EXPAND_FILL; palette.item_selected.connect(_palette_selected); palette.gui_input.connect(_palette_gui_input); left.add_child(palette)
	for entry in catalog.entries:
		if not bool(entry.get("non_serializing",false)):
			var index: int=palette.add_item("%s  ·  %s" % [entry.get("category",""),entry.get("display_name","")]); palette.set_item_metadata(index,entry.get("type_id",""));palette_index_by_type[String(entry.get("type_id",""))]=index
	palette_help=Label.new();palette_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;palette_help.custom_minimum_size.y=54;left.add_child(palette_help)
	_add_button(left,"Add at Origin",_add_palette_object)
	metadata_box=VBoxContainer.new(); left.add_child(HSeparator.new()); var mt:=Label.new();mt.text="MAP METADATA";left.add_child(mt);left.add_child(metadata_box)

	canvas = CanvasRef.new(); canvas.project_root=project_root; canvas.custom_minimum_size=Vector2(600,500); canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL; canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL; canvas.object_selected.connect(_on_object_selected);canvas.object_activated.connect(_on_object_activated); canvas.object_moved.connect(_on_canvas_moved); canvas.object_resized.connect(_on_canvas_resized); split.add_child(canvas)

	var tabs:=TabContainer.new(); tabs.custom_minimum_size.x=360; split.add_child(tabs)
	var insp_scroll:=ScrollContainer.new();insp_scroll.name="Inspector";tabs.add_child(insp_scroll);inspector=VBoxContainer.new();inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;insp_scroll.add_child(inspector)
	validation_list=ItemList.new();validation_list.name="Validation";validation_list.item_selected.connect(_validation_selected);tabs.add_child(validation_list)
	raw_json=TextEdit.new();raw_json.name="Raw JSON";raw_json.editable=false;raw_json.wrap_mode=TextEdit.LINE_WRAPPING_NONE;tabs.add_child(raw_json)
	graph_text=RichTextLabel.new();graph_text.name="Warp Graph";graph_text.bbcode_enabled=true;graph_text.fit_content=false;tabs.add_child(graph_text)

	open_dialog=FileDialog.new();open_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;open_dialog.access=FileDialog.ACCESS_FILESYSTEM;open_dialog.add_filter("*.json","Map JSON");open_dialog.file_selected.connect(_load_path);add_child(open_dialog)
	save_dialog=FileDialog.new();save_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;save_dialog.access=FileDialog.ACCESS_FILESYSTEM;save_dialog.add_filter("*.json","Map JSON");save_dialog.file_selected.connect(_save_to);add_child(save_dialog)
	unsaved_dialog=ConfirmationDialog.new();unsaved_dialog.dialog_text="Discard unsaved map changes?";unsaved_dialog.confirmed.connect(func(): if pending_action.is_valid(): pending_action.call());add_child(unsaved_dialog)
	palette_drag_preview=PanelContainer.new();palette_drag_preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;palette_drag_preview.visible=false;palette_drag_preview.z_index=100;add_child(palette_drag_preview)
	palette_drag_preview_label=Label.new();palette_drag_preview_label.add_theme_font_size_override("font_size",14);palette_drag_preview_label.add_theme_color_override("font_color",Color.WHITE);palette_drag_preview.add_child(palette_drag_preview_label)

func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button:=Button.new();button.text=text;button.pressed.connect(callback);parent.add_child(button);return button

func _request_open() -> void:
	_run_after_discard_check(func(): open_dialog.current_dir=map_directory;open_dialog.popup_centered_ratio(0.75))

func _request_new() -> void:
	_run_after_discard_check(_new_document)

func _run_after_discard_check(action: Callable) -> void:
	if document != null and document.dirty: pending_action=action;unsaved_dialog.popup_centered()
	else: action.call()

func _new_document() -> void:
	var text := '{"origin":[0,0,0],"size":[20,20],"entry":[0,0.65,8],"return_warp":[0,0.12,9.5],"tall_grass_species":[],"grass_zones":[],"water_blocks":[],"sand_blocks":[],"tall_flowers":[],"trees":[]}'
	document=MapDocumentRef.from_text(text,"new_route.json");document.kind="west_route";document.dirty=true;undo_stack.clear();redo_stack.clear();identity_by_path.clear();next_identity=1;_refresh_all();status_label.text="New unsaved route"

func _load_path(path: String) -> void:
	document=MapDocumentRef.load_file(path);undo_stack.clear();redo_stack.clear();selected_id="";identity_by_path.clear();next_identity=1;_refresh_all()

func _refresh_all() -> void:
	if document==null:return
	editor_objects=_extract_objects();canvas.set_document_objects(editor_objects,_map_size());canvas.selected_id=selected_id
	issues=MapValidatorRef.validate(document);_refresh_palette_compatibility();_refresh_validation();_refresh_raw();_refresh_metadata();_refresh_inspector();_refresh_graph()
	status_label.text=("● " if document.dirty else "")+document.path.get_file()+"  ·  "+document.kind+"  ·  %d objects"%editor_objects.size()

func _map_size() -> Vector2:
	var value:Variant=document.data.get("map_size",document.data.get("size",document.data.get("interior_size",[20,20])))
	if value is Array and value.size()>=2:return Vector2(float(value[0]),float(value[1]))
	return Vector2(20,20)

func _extract_objects() -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if not document.parse_error.is_empty():return result
	for field in document.data:
		var name:=String(field);var value:Variant=document.data[field]
		if MapSchemaRef.is_marker_field(name) and value is Array and value.size()>=3:_append_point(result,name,"$."+name,value,-1,"marker")
		elif name=="trees" and value is Array:
			for i in value.size():if value[i] is Array and value[i].size()>=4:_append_point(result,name,"$.trees[%d]"%i,value[i],int(value[i][3]),"tree")
		elif name in MapSchemaRef.POINT_ARRAY_FIELDS and value is Array:
			for i in value.size():if value[i] is Array and value[i].size()>=3:_append_point(result,name,"$.%s[%d]"%[name,i],value[i],-1,"point")
		elif name in ["water_blocks","sand_blocks","rocks","floor_blocks","wall_blocks"] and value is Array:
			for i in value.size():if value[i] is Array and value[i].size()>=6:_append_rectangle(result,name,"$.%s[%d]"%[name,i],value[i])
		elif name=="grass_zones" and value is Array:
			for i in value.size():if value[i] is Dictionary and value[i].get("position") is Array and value[i].get("size") is Array:_append_zone(result,name,"$.grass_zones[%d]"%i,value[i])
		elif name=="furnishings" and value is Array:
			for i in value.size():if value[i] is Dictionary:_append_furnishing(result,"$.furnishings[%d]"%i,value[i])
		elif name=="objects" and value is Array:
			for i in value.size():if value[i] is Dictionary:_append_universal_object(result,"$.objects[%d]"%i,value[i])
		elif name=="trainers" and value is Array:
			for i in value.size():if value[i] is Dictionary and value[i].get("position") is Array:_append_point(result,"trainers","$.trainers[%d].position"%i,value[i].position,-1,"npc")
		elif name=="wild_zone" and value is Dictionary and value.get("position") is Array and value.get("size") is Array:_append_zone(result,name,"$.wild_zone",value)
	if document.data.get("opponent") is Dictionary and document.data.opponent.get("position") is Array:_append_point(result,"opponent.position","$.opponent.position",document.data.opponent.position,-1,"npc")
	if document.data.get("building") is Dictionary and document.data.building.get("position") is Array:
		_append_building(result,"$.building.position",document.data.building.position,document.data.building.get("size",[5,3,4]),"building.medical_ward","$.building.size")
		if document.data.building.get("door") is Array:_append_point(result,"door","$.building.door",document.data.building.door,-1,"marker")
	if document.data.has("position") and document.data.position is Array and document.data.has("size") and document.data.size is Array and document.data.size.size()>=3:
		var building_type:="building.medical_ward" if document.kind=="city_ward" else "building.house"
		_append_building(result,"$.position",document.data.position,document.data.size,building_type,"$.size")
	_append_linked_context(result)
	return result

func _append_linked_context(result:Array[Dictionary])->void:
	var filename:=document.path.get_file()
	if filename=="rainforest_clearing.json":
		_append_linked_exterior(result,"rainforest_house.json","Rainforest House")
		var ward:=MapDocumentRef.load_file(map_directory.path_join("rainforest_medical_ward.json"))
		_append_linked_point(result,"rainforest_medical_ward.json","$.exterior_return",ward.data.get("exterior_return",[]),"Medical Ward Arrival","exterior_return")
	elif filename=="mossvale_city.json":
		_append_linked_exterior(result,"mossvale_medical_ward.json","Medical Ward")
		_append_linked_exterior(result,"mossvale_orchid_house.json","Orchid House")
		_append_linked_exterior(result,"mossvale_family_house.json","Family House")

func _append_linked_point(result:Array[Dictionary],source_file:String,path:String,value:Variant,label:String,field:String)->void:
	if not value is Array or value.size()<3:return
	var entry:Dictionary=_entry_for(field,-1);var fp:Variant=entry.get("footprint",[0.8,0.8])
	result.append({"id":_stable_id("linked|"+source_file+"|"+path),"path":path,"field":field,"label":label,"position":Vector3(float(value[0]),float(value[1]),float(value[2])),"size":Vector3.ONE,"shape":"point","variant":-1,"role":"marker","texture":entry.get("preview_texture",""),"display_height":entry.get("display_height",1.0),"footprint":Vector2(float(fp[0]),float(fp[1])),"color":Color(entry.get("editor_color","#55e6d4")),"linked":true,"locked":true,"source_file":source_file})

func _append_linked_exterior(result:Array[Dictionary],source_file:String,label:String)->void:
	var linked:=MapDocumentRef.load_file(map_directory.path_join(source_file))
	if not linked.parse_error.is_empty():return
	var position:Variant=linked.data.get("position",[]);var building_size:Variant=linked.data.get("size",[])
	if position is Array and position.size()>=3 and building_size is Array and building_size.size()>=3:
		var type_id:="building.medical_ward" if source_file.contains("medical_ward") else "building.house";var entry:Dictionary=catalog.by_id.get(type_id,{})
		result.append({"id":_stable_id("linked|"+source_file+"|$.position"),"path":"$.position","field":"building","label":label+" (linked)","position":Vector3(float(position[0]),float(position[1]),float(position[2])),"size":Vector3(float(building_size[0]),float(building_size[1]),float(building_size[2])),"shape":"building","variant":-1,"texture":entry.get("preview_texture",""),"display_width":float(building_size[0])*(1.08 if type_id=="building.medical_ward" else 1.15),"footprint":Vector2(float(building_size[0]),float(building_size[2])),"color":Color("#d4b47a"),"linked":true,"locked":true,"source_file":source_file})
	_append_linked_point(result,source_file,"$.door",linked.data.get("door",[]),label+" Door", "door")
	_append_linked_point(result,source_file,"$.exterior_return",linked.data.get("exterior_return",[]),label+" Arrival", "exterior_return")

func _append_point(result:Array[Dictionary],field:String,path:String,array:Array,variant:int,role:String)->void:
	var entry: Dictionary=_entry_for(field,variant);var fp: Variant=entry.get("footprint",[0.8,0.8]);if not fp is Array:fp=[1.0,1.0]
	result.append({"id":_stable_id(path),"path":path,"field":field,"label":field,"position":Vector3(float(array[0]),float(array[1]),float(array[2])),"size":Vector3.ONE,"shape":"point","variant":variant,"role":role,"texture":entry.get("preview_texture",""),"display_height":entry.get("display_height",1.0),"footprint":Vector2(float(fp[0]),float(fp[1])),"color":Color(entry.get("editor_color","#dce6ee"))})

func _append_rectangle(result:Array[Dictionary],field:String,path:String,array:Array)->void:
	var entry: Dictionary=catalog.for_field(field);var color := "#3d9fd6" if field=="water_blocks" else ("#d9bd72" if field=="sand_blocks" else ("#d6c49a" if field=="floor_blocks" else ("#b5a58c" if field=="wall_blocks" else "#8a8378")));result.append({"id":_stable_id(path),"path":path,"field":field,"label":field,"position":Vector3(float(array[0]),float(array[1]),float(array[2])),"size":Vector3(float(array[3]),float(array[4]),float(array[5])),"shape":"rectangle","variant":-1,"texture":entry.get("preview_texture",""),"footprint":Vector2(float(array[3]),float(array[5])),"color":Color(color)})

func _append_zone(result:Array[Dictionary],field:String,path:String,zone:Dictionary)->void:
	var p:Array=zone.position;var s:Array=zone.size;result.append({"id":_stable_id(path),"path":path,"field":field,"label":field,"position":Vector3(float(p[0]),float(p[1]),float(p[2])),"size":Vector3(float(s[0]),float(s[1]),float(s[2])),"shape":"rectangle","variant":-1,"texture":"assets/overworld/tile_tallgrass_generic.png","footprint":Vector2(float(s[0]),float(s[2])),"color":Color("#69b34c")})

func _append_furnishing(result:Array[Dictionary],path:String,value:Dictionary)->void:
	var p:Variant=value.get("position",[]);if not p is Array or p.size()<3:return
	var prop_type:=String(value.get("type",""));var entry:Dictionary=catalog.by_id.get("prop."+prop_type,{})
	var fp:Variant=value.get("footprint",entry.get("footprint",[0.8,0.8]));if not fp is Array or fp.size()<2:fp=[0.8,0.8]
	var height:=float(value.get("height",entry.get("display_height",1.0)))
	result.append({"id":_stable_id(path),"path":path,"field":"furnishings","label":entry.get("display_name",prop_type),"position":Vector3(float(p[0]),float(p[1]),float(p[2])),"size":Vector3.ONE,"shape":"point","variant":-1,"texture":entry.get("preview_texture",""),"display_height":height,"footprint":Vector2(float(fp[0]),float(fp[1])),"color":Color("#e0b878")})

func _append_universal_object(result:Array[Dictionary],path:String,value:Dictionary)->void:
	var type_id:=String(value.get("type",""));var entry:Dictionary=catalog.by_id.get(type_id,{});var p:Variant=value.get("position",[])
	if entry.is_empty() or not p is Array or p.size()<3:return
	var s:Variant=value.get("size",[1.0,1.0,1.0]);if not s is Array or s.size()<3:s=[1.0,1.0,1.0]
	var shape:="building" if type_id.begins_with("building.") else ("rectangle" if String(entry.get("scale_mode",""))=="explicit_size" else "point")
	var fp:Variant=entry.get("footprint",[0.8,0.8]);if not fp is Array:fp=[float(s[0]),float(s[2])]
	result.append({"id":_stable_id(path),"path":path,"field":"objects","label":entry.get("display_name",type_id),"position":Vector3(float(p[0]),float(p[1]),float(p[2])),"size":Vector3(float(s[0]),float(s[1]),float(s[2])),"shape":shape,"variant":-1,"texture":entry.get("preview_texture",""),"display_height":entry.get("display_height",1.0),"display_width":float(s[0])*(1.08 if type_id=="building.medical_ward" else 1.15),"footprint":Vector2(float(fp[0]),float(fp[1])),"color":Color("#d4b47a") if shape=="building" else Color("#dce6ee"),"universal_type":type_id})

func _append_building(result:Array[Dictionary],path:String,position:Array,building_size:Array,type_id:String,size_path:String)->void:
	var entry:Dictionary=catalog.by_id.get(type_id,{})
	var width_multiplier:=1.08 if type_id=="building.medical_ward" else 1.15
	result.append({"id":_stable_id(path),"path":path,"field":"building","label":entry.get("display_name","Building"),"position":Vector3(float(position[0]),float(position[1]),float(position[2])),"size":Vector3(float(building_size[0]),float(building_size[1]),float(building_size[2])),"size_path":size_path,"shape":"building","variant":-1,"texture":entry.get("preview_texture",""),"display_width":float(building_size[0])*width_multiplier,"footprint":Vector2(float(building_size[0]),float(building_size[2])),"color":Color("#d4b47a")})

func _stable_id(path: String) -> String:
	if not identity_by_path.has(path):
		identity_by_path[path] = "object-%06d" % next_identity
		next_identity += 1
	return String(identity_by_path[path])

func _entry_for(field:String,variant:int)->Dictionary:
	if field=="trees":return catalog.by_id.get("tree.main" if variant==0 else "tree.palm",{})
	if field=="trainers":return catalog.by_id.get("npc.opponent",{})
	if field in ["player_spawn"]:return catalog.by_id.get("marker.player_spawn",{})
	if MapSchemaRef.is_marker_field(field):return catalog.by_id.get("marker.entry" if field.contains("return") or field=="entry" else "marker.warp",{})
	return catalog.for_field(field)

func _on_object_selected(id:String)->void:selected_id=id;_refresh_inspector()

func _on_object_activated(id:String)->void:
	var object:=_find_object(id)
	if object.is_empty():return
	var owner:=String(object.get("source_file",document.path.get_file()))
	var destination:=MapGraphRef.destination_for(owner,String(object.path),map_directory)
	if destination.is_empty() and bool(object.get("linked",false)):
		destination={"map":owner,"target_path":String(object.path),"label":"Open linked "+String(object.label)}
	if destination.is_empty():status_label.text="This object has no runtime warp destination.";return
	_navigate_to_destination(destination)

func _navigate_to_destination(destination:Dictionary)->void:
	var action:=func():_open_warp_destination(destination)
	if document.dirty:
		pending_navigation_target=destination;pending_action=action;unsaved_dialog.dialog_text="Discard unsaved changes and follow this warp?";unsaved_dialog.popup_centered()
	else:action.call()

func _open_warp_destination(destination:Dictionary)->void:
	_load_path(map_directory.path_join(String(destination.map)))
	var target_path:=String(destination.get("target_path",""))
	var legacy_target_path:=String(destination.get("legacy_target_path",""))
	var target_source:=String(destination.get("target_source",""))
	if not target_path.is_empty():
		for object in editor_objects:
			if String(object.path) in [target_path,legacy_target_path] and (target_source.is_empty() or String(object.get("source_file",document.path.get_file()))==target_source):canvas.select_object(String(object.id));status_label.text="Warp destination: %s"%String(destination.get("label",destination.map));return
	status_label.text="Opened %s. Arrival coordinates are stored by compatibility field %s."%[destination.map,String(destination.get("arrival_owner",""))]

func _find_object(id:String)->Dictionary:
	for object in editor_objects:if String(object.id)==id:return object
	return {}

func _on_canvas_moved(id:String,old:Vector3,new:Vector3)->void:
	var object:=_find_object(id);if object.is_empty():return
	_push_undo();_write_object_position(object,new);_after_edit()

func _on_canvas_resized(id:String,old:Vector3,new:Vector3)->void:
	var object:=_find_object(id);if object.is_empty():return
	_push_undo();_write_object_size(object,new);_after_edit()

func _write_object_position(object:Dictionary,value:Vector3)->void:
	var path:=String(object.path)
	if object.field=="objects":document.set_value(path+".position",[value.x,value.y,value.z])
	elif object.field in ["grass_zones","wild_zone"]:
		document.set_value(path+".position",[value.x,value.y,value.z])
	elif object.field=="furnishings":document.set_value(path+".position",[value.x,value.y,value.z])
	elif object.field in ["water_blocks","sand_blocks","rocks","floor_blocks","wall_blocks"] or int(object.get("variant",-1))>=0:
		# Block6 and Tree4 arrays carry serialized values after X/Y/Z. Moving
		# them must update the first three elements without discarding size or
		# variant data.
		for axis in 3:document.set_value(path+"[%d]"%axis,value[axis])
	else:
		document.set_value(path,[value.x,value.y,value.z])
		var field:=path.trim_prefix("$.")
		if document.data.get("arrival_points") is Dictionary and document.data.arrival_points.has(field):document.set_value("$.arrival_points."+field,[value.x,value.y,value.z])

func _write_object_size(object:Dictionary,value:Vector3)->void:
	var path:=String(object.path)
	if object.field=="objects":document.set_value(path+".size",[value.x,value.y,value.z])
	elif object.field in ["grass_zones","wild_zone"]:document.set_value(path+".size",[value.x,value.y,value.z])
	else:
		for axis in 3:document.set_value(path+"[%d]"%(axis+3),value[axis])

func _push_undo()->void:
	undo_stack.append(document.deterministic_json());if undo_stack.size()>100:undo_stack.pop_front();redo_stack.clear()

func _undo()->void:
	if undo_stack.is_empty() or document==null:return
	redo_stack.append(document.deterministic_json());_restore_snapshot(undo_stack.pop_back())

func _redo()->void:
	if redo_stack.is_empty() or document==null:return
	undo_stack.append(document.deterministic_json());_restore_snapshot(redo_stack.pop_back())

func _restore_snapshot(text:String)->void:
	var path:=document.path;var kind:=document.kind;document=MapDocumentRef.from_text(text,path);document.kind=kind;document.dirty=true;_refresh_all()

func _delete_selected()->void:
	var object:=_find_object(selected_id)
	if object.is_empty():status_label.text="Select an object before deleting.";return
	if bool(object.get("locked",false)):status_label.text="Linked objects are edited in %s. Double-click to open it."%String(object.source_file);return
	var parts:=_array_parent_and_index(String(object.path))
	if parts.is_empty():status_label.text="%s is a required singular map field and cannot be deleted; move it or edit its properties instead."%String(object.field);return
	var array:Variant=_get_path(parts.path)
	if not array is Array:status_label.text="Could not locate the selected object array.";return
	_push_undo();array.remove_at(parts.index);_shift_array_identities(parts.path,parts.index,-1,true);document.dirty=true;selected_id="";_after_edit();status_label.text="Deleted object. Undo is available."

func _duplicate_selected()->void:
	var object:=_find_object(selected_id);if object.is_empty():return
	if bool(object.get("locked",false)):status_label.text="Linked objects cannot be duplicated from this map. Double-click to open %s."%String(object.source_file);return
	var parts:=_array_parent_and_index(String(object.path));if parts.is_empty():return
	var array:Variant=_get_path(parts.path);if not array is Array:return
	_push_undo();var copy:Variant=array[parts.index].duplicate(true);if copy is Array and copy.size()>=3:copy[0]=float(copy[0])+grid_spin.value;copy[2]=float(copy[2])+grid_spin.value
	elif copy is Dictionary and copy.get("position") is Array:copy.position[0]=float(copy.position[0])+grid_spin.value;copy.position[2]=float(copy.position[2])+grid_spin.value
	_shift_array_identities(parts.path,parts.index+1,1,false);array.insert(parts.index+1,copy);document.dirty=true;_after_edit()

func _shift_array_identities(parent_path: String, start_index: int, delta: int, remove_start: bool) -> void:
	var changes: Array[Dictionary] = []
	for path in identity_by_path.keys():
		var prefix := parent_path + "["
		if not String(path).begins_with(prefix): continue
		var close := String(path).find("]", prefix.length())
		if close < 0: continue
		var index := int(String(path).substr(prefix.length(), close - prefix.length()))
		if remove_start and index == start_index: identity_by_path.erase(path)
		elif index >= start_index: changes.append({"old":path,"new":prefix+str(index+delta)+String(path).substr(close),"id":identity_by_path[path]})
	changes.sort_custom(func(a,b): return String(a.old)>String(b.old) if delta>0 else String(a.old)<String(b.old))
	for change in changes: identity_by_path.erase(change.old);identity_by_path[change.new]=change.id

func _array_parent_and_index(path:String)->Dictionary:
	var close:=path.rfind("]");var open:=path.rfind("[");if close!=path.length()-1 or open<0:return {}
	return {"path":path.substr(0,open),"index":int(path.substr(open+1,close-open-1))}

func _get_path(path:String)->Variant:
	var target: Variant=document.data
	for part in document._path_parts(path):
		if part is int:
			if not target is Array or part < 0 or part >= target.size():return null
			target=target[part]
		else:
			if not target is Dictionary or not target.has(part):return null
			target=target[part]
	return target

func _palette_selected(index:int)->void:
	selected_palette_entry=String(palette.get_item_metadata(index));var entry:Dictionary=catalog.by_id.get(selected_palette_entry,{})
	palette_help.text=("Available: saves to '%s'."%_compatible_array_field(entry)) if not _compatible_array_field(entry).is_empty() else _incompatible_palette_reason(entry)

func _refresh_palette_compatibility()->void:
	if document==null:return
	palette_help.text="Universal buildings, vegetation, and terrain use the shared 'objects' collection when this map has no legacy field. Only map-specific gameplay markers remain restricted."
	for type_id in palette_index_by_type:
		var index:int=int(palette_index_by_type[type_id]);var entry:Dictionary=catalog.by_id.get(type_id,{})
		var compatible:=_compatible_array_field(entry)
		var available:=not compatible.is_empty()
		palette.set_item_disabled(index,not available)
		palette.set_item_tooltip(index,"Drop onto this map; serializes to '%s'."%compatible if available else _incompatible_palette_reason(entry))
		palette.set_item_custom_fg_color(index,Color("#dce6ee") if available else Color("#68737d"))

func _compatible_array_field(entry:Dictionary)->String:
	if _universal_type(entry).begins_with("building.") or _universal_type(entry).begins_with("npc."):return "objects"
	for field in entry.get("serialization",{}).get("fields",[]):
		if document.data.has(String(field)) and document.data[String(field)] is Array:return String(field)
	if not _universal_type(entry).is_empty():return "objects"
	return ""

func _universal_type(entry:Dictionary)->String:
	var type_id:=String(entry.get("type_id",""))
	return type_id if type_id.begins_with("tree.") or type_id.begins_with("flower.") or type_id=="cave.vine" or type_id in ["block.water","block.sand","block.rock","building.house","building.medical_ward","npc.opponent","npc.generic"] else ""

func _incompatible_palette_reason(entry:Dictionary)->String:
	var fields:Array=entry.get("serialization",{}).get("fields",[])
	if fields.is_empty():return "This runtime-derived object is not serialized by map JSON."
	return "Unavailable for %s. This map-specific object requires: %s."%[document.kind,", ".join(fields)]

func _palette_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var index:=palette.get_item_at_position(event.position,true)
			palette_press_entry=String(palette.get_item_metadata(index)) if index>=0 else ""
		elif not palette_dragging:palette_press_entry=""
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and not palette_dragging and not palette_press_entry.is_empty():
		_start_palette_drag(palette_press_entry)

func _input(event: InputEvent) -> void:
	if not palette_dragging: return
	if event is InputEventMouseMotion:
		palette_drag_preview.global_position = event.global_position + Vector2(16,16)
		var over_canvas := canvas.get_global_rect().has_point(event.global_position)
		palette_drag_preview.modulate = Color.WHITE if over_canvas else Color(1,1,1,0.55)
		canvas.queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var drop_global: Vector2 = event.global_position
		var over_canvas := canvas.get_global_rect().has_point(drop_global)
		var drop_type:=palette_drag_entry
		_finish_palette_drag()
		if over_canvas:
			var local_screen: Vector2 = drop_global - canvas.global_position
			var world_xz: Vector2 = canvas.screen_to_world(local_screen)
			_add_palette_object_at(world_xz,drop_type)
		get_viewport().set_input_as_handled()

func _start_palette_drag(type_id: String) -> void:
	if type_id.is_empty(): return
	var entry:Dictionary=catalog.by_id.get(type_id,{})
	if _compatible_array_field(entry).is_empty():status_label.text=_incompatible_palette_reason(entry);return
	palette_dragging=true;palette_drag_entry=type_id
	palette_drag_preview_label.text="  %s\n  Drop onto map  " % String(entry.get("display_name",type_id))
	palette_drag_preview.reset_size();palette_drag_preview.visible=true
	palette_drag_preview.global_position=get_viewport().get_mouse_position()+Vector2(16,16)

func _finish_palette_drag() -> void:
	palette_dragging=false;palette_drag_preview.visible=false;palette_drag_entry="";palette_press_entry="";canvas.queue_redraw()

func _add_palette_object()->void:
	_add_palette_object_at(Vector2.ZERO)

func _add_palette_object_at(world_xz: Vector2,type_id:String="")->void:
	var placement_type:=selected_palette_entry if type_id.is_empty() else type_id
	if placement_type.is_empty() or document==null:return
	var entry:Dictionary=catalog.by_id.get(placement_type,{});var serialization:Dictionary=entry.get("serialization",{});var fields:Array=serialization.get("fields",[]);var chosen:=""
	if not placement_type.begins_with("building.") and not placement_type.begins_with("npc."):
		for f in fields:if document.data.has(String(f)) and document.data[String(f)] is Array:chosen=String(f);break
	if chosen.is_empty() and not _universal_type(entry).is_empty():
		chosen="objects"
		if not document.data.get(chosen) is Array:document.data[chosen]=[]
	if chosen.is_empty():status_label.text="This object type has no compatible array in the current schema.";return
	var x := world_xz.x;var z := world_xz.y
	if snap_check.button_pressed:x=snappedf(x,grid_spin.value);z=snappedf(z,grid_spin.value)
	_push_undo();var y:=float(entry.get("default_y",0.0));var kind:=String(serialization.get("kind",""));var shape:=String(serialization.get("shape",""));var value:Variant
	if chosen=="objects":
		var default_size:=[5.0,3.0,4.0] if placement_type.begins_with("building.") else ([2.0,0.3,2.0] if String(entry.get("scale_mode",""))=="explicit_size" else [1.0,1.0,1.0])
		value={"type":placement_type,"position":[x,y,z],"size":default_size}
		if placement_type=="npc.generic":value.merge({"speaker":"NPC","dialogue":["Hello, traveler!"]})
		elif placement_type=="npc.opponent":value.merge({"name":"TRAINER","dialogue":["Let's battle!"],"team":[{"fakemon":0,"level":5}]})
	elif kind=="zone":value={"position":[x,y,z],"size":[3,0.25,3],"encounter_chance":0.2}
	elif kind=="furnishing":value={"type":String(serialization.get("prop_type","")),"position":[x,y,z],"height":float(entry.get("display_height",1.0))}
	elif kind=="block6":value=[x,y,z,2,0.3,2]
	elif shape.contains("variant"):value=[x,y,z,0 if placement_type=="tree.main" else 1]
	else:value=[x,y,z]
	var new_index: int=document.data[chosen].size();document.data[chosen].append(value);document.dirty=true
	var new_path := "$.%s[%d]" % [chosen,new_index]
	_after_edit()
	for object in editor_objects:
		if String(object.path)==new_path:canvas.select_object(String(object.id));break

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.ctrl_pressed and event.keycode==KEY_Z:
		if event.shift_pressed:_redo()
		else:_undo()
		get_viewport().set_input_as_handled();return
	if event.ctrl_pressed and event.keycode==KEY_Y:
		_redo();get_viewport().set_input_as_handled();return
	if event.keycode == KEY_DELETE and canvas.has_focus():
		_delete_selected();get_viewport().set_input_as_handled()

func _refresh_inspector()->void:
	for child in inspector.get_children():child.queue_free()
	var object:=_find_object(selected_id)
	if object.is_empty():var l:=Label.new();l.text="Select an object to edit its properties.";inspector.add_child(l);return
	var title:=Label.new();title.text=String(object.field)+"\n"+String(object.path);title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(title)
	if bool(object.get("linked",false)):
		var linked_note:=Label.new();linked_note.text="Read-only linked object from %s. Double-click it to open the owning map."%String(object.source_file);linked_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(linked_note);return
	_add_vector_editor("Position",object.position,func(v):_push_undo();_write_object_position(object,v);_after_edit())
	if String(object.get("universal_type","")).begins_with("npc."):_add_character_editor(object)
	if object.shape=="rectangle":_add_vector_editor("Size",object.size,func(v):_push_undo();_write_object_size(object,v);_after_edit())
	elif object.shape=="building":_add_vector_editor("Exterior Collision Size",object.size,func(v):_push_undo();document.set_value(String(object.size_path),[v.x,v.y,v.z]);_after_edit())
	if int(object.variant)>=0:
		var variant:=SpinBox.new();variant.min_value=0;variant.max_value=1;variant.value=object.variant;variant.value_changed.connect(func(v):_push_undo();document.set_value(String(object.path)+"[3]",int(v));_after_edit());inspector.add_child(variant)
	var destination:=MapGraphRef.destination_for(document.path.get_file(),String(object.path),map_directory);var navigation_text:="\nDouble-click: "+String(destination.get("label","open destination")) if not destination.is_empty() else ""
	var space:=Label.new();space.text="Coordinate space: "+MapSchemaRef.coordinate_space(document.kind,String(object.field))+navigation_text+"\nFacing after arrival: unsupported\nTransition options: unsupported / fixed by runtime";space.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(space)
	if destination.get("connection") is Dictionary:
		var connection:Dictionary=destination.connection
		for property in ["destination_map","arrival","reverse","facing"]:
			var edit:=LineEdit.new();edit.placeholder_text=property;edit.text=String(connection.get(property,""));edit.text_submitted.connect(func(text):_push_undo();connection[property]=text;document.dirty=true;_after_edit());inspector.add_child(edit)

func _add_character_editor(object:Dictionary)->void:
	var record:Variant=_get_path(String(object.path));if not record is Dictionary:return
	var name_field:="name" if String(record.get("type",""))=="npc.opponent" else "speaker"
	var name_edit:=LineEdit.new();name_edit.placeholder_text="Trainer name" if name_field=="name" else "Speaker name";name_edit.text=String(record.get(name_field,""));name_edit.text_submitted.connect(func(text):_push_undo();record[name_field]=text;document.dirty=true;_after_edit());inspector.add_child(name_edit)
	var dialogue_edit:=LineEdit.new();dialogue_edit.placeholder_text="Dialogue pages separated by |";dialogue_edit.text=" | ".join(record.get("dialogue",[]));dialogue_edit.text_submitted.connect(func(text):_push_undo();record["dialogue"]=_split_nonempty(text,"|");document.dirty=true;_after_edit());inspector.add_child(dialogue_edit)
	if String(record.get("type",""))=="npc.opponent":
		var team_edit:=LineEdit.new();team_edit.placeholder_text="Team: Fakemon:level, Fakemon:level";var rows:Array=[]
		for member:Variant in record.get("team",[]):if member is Dictionary:rows.append("%s:%d"%[str(member.get("fakemon",0)),int(member.get("level",5))])
		team_edit.text=", ".join(rows);team_edit.text_submitted.connect(func(text):_push_undo();record["team"]=_parse_team(text);document.dirty=true;_after_edit());inspector.add_child(team_edit)

func _split_nonempty(text:String,separator:String)->Array:
	var values:Array=[]
	for part in text.split(separator):if not part.strip_edges().is_empty():values.append(part.strip_edges())
	return values

func _parse_team(text:String)->Array:
	var team:Array=[]
	for raw in text.split(","):
		var parts:=raw.strip_edges().rsplit(":",true,1);if parts.is_empty() or parts[0].strip_edges().is_empty():continue
		var fakemon:Variant=int(parts[0]) if parts[0].strip_edges().is_valid_int() else parts[0].strip_edges()
		team.append({"fakemon":fakemon,"level":clampi(int(parts[1]) if parts.size()>1 and parts[1].strip_edges().is_valid_int() else 5,1,100)})
	return team

func _add_vector_editor(label_text:String,value:Vector3,callback:Callable)->void:
	var label:=Label.new();label.text=label_text+" (X / Y / Z)";inspector.add_child(label);var row:=HBoxContainer.new();inspector.add_child(row)
	var spins:Array[SpinBox]=[]
	for axis in 3:
		var spin:=SpinBox.new();spin.min_value=-10000;spin.max_value=10000;spin.step=0.01;spin.value=value[axis];spin.custom_minimum_size.x=100;row.add_child(spin);spins.append(spin)
	for spin in spins:spin.value_changed.connect(func(_v):if not updating_inspector:callback.call(Vector3(spins[0].value,spins[1].value,spins[2].value)))

func _refresh_metadata()->void:
	for child in metadata_box.get_children():child.queue_free()
	for field in ["origin","map_size","size","interior_size"]:
		if document.data.get(field) is Array:
			var edit:=LineEdit.new();edit.placeholder_text=field;edit.text=",".join(document.data[field].map(func(v):return str(v)));edit.text_submitted.connect(func(text):_set_numeric_array(field,text));metadata_box.add_child(edit)
	if document.data.get("tall_grass_species") is Array:
		var species:=LineEdit.new();species.placeholder_text="Encounter species (comma-separated)";species.text=", ".join(document.data.tall_grass_species);species.text_submitted.connect(_set_species);metadata_box.add_child(species)

func _set_numeric_array(field:String,text:String)->void:
	var values:=text.split(",");var parsed:Array=[];for v in values:parsed.append(float(v.strip_edges()))
	_push_undo();document.set_value("$."+field,parsed);_after_edit()

func _set_species(text:String)->void:
	var values:Array=[];for v in text.split(","):if not v.strip_edges().is_empty():values.append(v.strip_edges())
	_push_undo();document.set_value("$.tall_grass_species",values);_after_edit()

func _after_edit()->void:_refresh_all()

func _refresh_validation()->void:
	validation_list.clear();for issue in issues:var icon:="ERROR" if issue.severity=="error" else "WARN";var index:=validation_list.add_item("[%s] %s — %s"%[icon,issue.path,issue.message]);validation_list.set_item_metadata(index,issue.path)
	if issues.is_empty():validation_list.add_item("No validation issues.")

func _validation_selected(index:int)->void:
	var path:=String(validation_list.get_item_metadata(index));for object in editor_objects:if String(object.path)==path or path.begins_with(String(object.path)):canvas.select_object(String(object.id));return

func _refresh_raw()->void:raw_json.text=document.source_text if not document.parse_error.is_empty() else document.deterministic_json()

func _refresh_graph()->void:
	var graph:=MapGraphRef.scan(map_directory);var text:="[b]Current runtime-compatible connection graph[/b]\n\n"
	for c in graph.connections:text+="%s.%s → %s.%s\n  return: %s.%s → %s.%s\n  facing: fixed by runtime; transition: unsupported\n\n"%[c.from,c.from_warp,c.to,c.to_entry,c.to,c.return_warp,c.from,c.return_entry]
	for issue in graph.issues:text+="[color=orange]%s: %s[/color]\n"%[issue.path,issue.message]
	graph_text.text=text

func _save()->void:
	if document.path.is_empty() or document.path.get_file().begins_with("new_"):_save_as();return
	_save_to(document.path)

func _save_as()->void:save_dialog.current_dir=map_directory;save_dialog.current_file=document.path.get_file();save_dialog.popup_centered_ratio(0.75)

func _save_to(path:String)->void:
	issues=MapValidatorRef.validate(document);var error:=document.save_atomic(path,issues)
	if error==OK:status_label.text="Saved atomically; backup: "+path.get_file()+".bak";_refresh_all()
	else:status_label.text="Save blocked: fix validation errors before replacing output."
