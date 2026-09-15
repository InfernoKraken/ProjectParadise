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
var trainer_catalog_doc: MapDocument
var fakemon_names:Array[String]=[]
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
var rename_dialog: ConfirmationDialog
var rename_edit: LineEdit
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
var terrain_type_option: OptionButton
var terrain_stroke_changed := false

func _ready() -> void:
	project_root = ProjectSettings.globalize_path("res://").simplify_path().get_base_dir().get_base_dir()
	map_directory = project_root.path_join("data/maps")
	catalog = AssetCatalogRef.load_catalog(ProjectSettings.globalize_path("res://catalog/map_asset_catalog.json"))
	trainer_catalog_doc=MapDocumentRef.load_file(project_root.path_join("data/trainers.json"))
	var battle_doc:=MapDocumentRef.load_file(project_root.path_join("data/battle_data.json"))
	for species:Variant in battle_doc.data.get("fakemon",[]):if species is Dictionary:fakemon_names.append(String(species.get("name","")))
	_build_ui()
	_load_path(map_directory.path_join("eastern_rainforest_route.json"))

func _build_ui() -> void:
	var root_v := VBoxContainer.new(); root_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root_v)
	var toolbar := HBoxContainer.new(); toolbar.custom_minimum_size.y = 42; root_v.add_child(toolbar)
	_add_button(toolbar, "New", _request_new)
	_add_button(toolbar, "Open", _request_open)
	_add_button(toolbar, "Save", _save)
	_add_button(toolbar, "Save As", _save_as)
	_add_button(toolbar, "Rename", _request_rename)
	toolbar.add_child(VSeparator.new())
	_add_button(toolbar, "Undo", _undo)
	_add_button(toolbar, "Redo", _redo)
	_add_button(toolbar, "Duplicate", _duplicate_selected)
	_add_button(toolbar, "Delete", _delete_selected)
	toolbar.add_child(VSeparator.new())
	var terrain_label:=Label.new();terrain_label.text="Terrain";toolbar.add_child(terrain_label)
	terrain_type_option=OptionButton.new();terrain_type_option.name="TerrainTypePalette"
	for terrain_type in ["forest_floor","sand","water","mud","stone","rock"]:terrain_type_option.add_item(terrain_type.replace("_"," ").capitalize());terrain_type_option.set_item_metadata(terrain_type_option.item_count-1,terrain_type)
	toolbar.add_child(terrain_type_option)
	_add_button(toolbar,"Paint",func():canvas.terrain_brush_mode="paint";status_label.text="Terrain paint brush active. Drag across the canvas; Esc returns to selection.")
	_add_button(toolbar,"Erase",func():canvas.terrain_brush_mode="erase";status_label.text="Terrain erase brush active. Drag across the canvas; Esc returns to selection.")
	_add_button(toolbar,"Select",func():canvas.terrain_brush_mode="select";status_label.text="Selection tool active.")
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

	canvas = CanvasRef.new(); canvas.project_root=project_root; canvas.custom_minimum_size=Vector2(600,500); canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL; canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL; canvas.object_selected.connect(_on_object_selected);canvas.object_activated.connect(_on_object_activated); canvas.object_moved.connect(_on_canvas_moved); canvas.object_resized.connect(_on_canvas_resized);canvas.terrain_stroke_started.connect(_terrain_stroke_started);canvas.terrain_cell_changed.connect(_terrain_cell_changed);canvas.terrain_stroke_finished.connect(_terrain_stroke_finished); split.add_child(canvas)

	var tabs:=TabContainer.new(); tabs.custom_minimum_size.x=360; split.add_child(tabs)
	var insp_scroll:=ScrollContainer.new();insp_scroll.name="Inspector";tabs.add_child(insp_scroll);inspector=VBoxContainer.new();inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;insp_scroll.add_child(inspector)
	validation_list=ItemList.new();validation_list.name="Validation";validation_list.item_selected.connect(_validation_selected);tabs.add_child(validation_list)
	raw_json=TextEdit.new();raw_json.name="Raw JSON";raw_json.editable=false;raw_json.wrap_mode=TextEdit.LINE_WRAPPING_NONE;tabs.add_child(raw_json)
	graph_text=RichTextLabel.new();graph_text.name="Warp Graph";graph_text.bbcode_enabled=true;graph_text.fit_content=false;tabs.add_child(graph_text)

	open_dialog=FileDialog.new();open_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;open_dialog.access=FileDialog.ACCESS_FILESYSTEM;open_dialog.add_filter("*.json","Map JSON");open_dialog.file_selected.connect(_load_path);add_child(open_dialog)
	save_dialog=FileDialog.new();save_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;save_dialog.access=FileDialog.ACCESS_FILESYSTEM;save_dialog.add_filter("*.json","Map JSON");save_dialog.file_selected.connect(_save_to);add_child(save_dialog)
	unsaved_dialog=ConfirmationDialog.new();unsaved_dialog.dialog_text="Discard unsaved map changes?";unsaved_dialog.confirmed.connect(func(): if pending_action.is_valid(): pending_action.call());add_child(unsaved_dialog)
	rename_dialog=ConfirmationDialog.new();rename_dialog.title="Rename Map";rename_dialog.dialog_text="New filename (.json is optional):";rename_dialog.confirmed.connect(_confirm_rename);add_child(rename_dialog);rename_edit=LineEdit.new();rename_edit.custom_minimum_size.x=360;rename_dialog.add_child(rename_edit)
	palette_drag_preview=PanelContainer.new();palette_drag_preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;palette_drag_preview.visible=false;palette_drag_preview.z_index=100;add_child(palette_drag_preview)
	palette_drag_preview_label=Label.new();palette_drag_preview_label.add_theme_font_size_override("font_size",14);palette_drag_preview_label.add_theme_color_override("font_color",Color.WHITE);palette_drag_preview.add_child(palette_drag_preview_label)

func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button:=Button.new();button.text=text;button.pressed.connect(callback);parent.add_child(button);return button

func _request_open() -> void:
	_run_after_discard_check(func(): open_dialog.current_dir=map_directory;open_dialog.popup_centered_ratio(0.75))

func _request_new() -> void:
	_run_after_discard_check(_new_document)

func _run_after_discard_check(action: Callable) -> void:
	if document != null and (document.dirty or (trainer_catalog_doc!=null and trainer_catalog_doc.dirty)): pending_action=action;unsaved_dialog.popup_centered()
	else: action.call()

func _new_document() -> void:
	var template:={"format_version":2,"map_type":"Rainforest","map_metadata":{"id":"new_map","display_name":"New Map","layout_type":"outdoor","group":"custom","tags":[]},"origin":[0,0,0],"size":[20,20],"base_terrain_type":"forest_floor","terrain_tiles":[],"entry":[0,0.65,8],"return_warp":[0,0.12,9.5],"arrival_points":{"entry":[0,0.65,8]},"outdoor_connections":[],"tall_grass_species":[],"water_species":[],"water_encounter_chance":0.0,"objects":[],"grass_zones":[],"water_blocks":[],"sand_blocks":[],"rocks":[],"floor_blocks":[],"wall_blocks":[],"furnishings":[],"vines":[],"orchids":[]}
	document=MapDocumentRef.from_text(JSON.stringify(template),"new_map.json");document.dirty=true;undo_stack.clear();redo_stack.clear();identity_by_path.clear();next_identity=1;_refresh_all();status_label.text="New universal outdoor map"

func _load_path(path: String) -> void:
	document=MapDocumentRef.load_file(path);undo_stack.clear();redo_stack.clear();selected_id="";identity_by_path.clear();next_identity=1;_refresh_all()

func _refresh_all() -> void:
	if document==null:return
	editor_objects=_extract_objects();canvas.set_document_objects(editor_objects,_map_size());canvas.selected_id=selected_id
	issues=MapValidatorRef.validate(document);_refresh_palette_compatibility();_refresh_validation();_refresh_canvas_validation();_refresh_raw();_refresh_metadata();_refresh_inspector();_refresh_graph()
	var document_name:=document.path.get_file()
	if document_name.to_lower()=="map_index.json" and document.data.get("index_metadata") is Dictionary:
		document_name=String(document.data.index_metadata.get("display_name","World Index"))+" (map_index.json)"
	status_label.text=("● " if document.dirty or (trainer_catalog_doc!=null and trainer_catalog_doc.dirty) else "")+document_name+"  ·  "+document.kind+"  ·  %d objects"%editor_objects.size()

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
		elif name=="terrain_tiles" and value is Array:
			for i in value.size():if value[i] is Dictionary:_append_terrain_entry(result,"$.terrain_tiles[%d]"%i,value[i])
		elif name=="trainers" and value is Array:
			for i in value.size():if value[i] is Dictionary and value[i].get("position") is Array:_append_trainer(result,"$.trainers[%d]"%i,value[i])
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

func _append_trainer(result:Array[Dictionary],path:String,record:Dictionary)->void:
	var p:Array=record.position;var entry:Dictionary=catalog.by_id.get("npc.opponent",{});var fp:Variant=entry.get("footprint",[1,1])
	result.append({"id":_stable_id(path),"path":path,"field":"trainers","label":String(_trainer_definition(record).get("name",record.get("name","Trainer"))),"position":Vector3(float(p[0]),float(p[1]),float(p[2])),"size":Vector3.ONE,"shape":"point","variant":-1,"role":"npc","texture":entry.get("preview_texture",""),"display_height":entry.get("display_height",1.25),"footprint":Vector2(float(fp[0]),float(fp[1])),"color":Color(entry.get("editor_color","#df6d5f")),"universal_type":"npc.opponent"})

func _append_rectangle(result:Array[Dictionary],field:String,path:String,array:Array)->void:
	var entry: Dictionary=catalog.for_field(field);var color := "#3d9fd6" if field=="water_blocks" else ("#d9bd72" if field=="sand_blocks" else ("#d6c49a" if field=="floor_blocks" else ("#b5a58c" if field=="wall_blocks" else "#8a8378")));result.append({"id":_stable_id(path),"path":path,"field":field,"label":field,"position":Vector3(float(array[0]),float(array[1]),float(array[2])),"size":Vector3(float(array[3]),float(array[4]),float(array[5])),"shape":"rectangle","variant":-1,"texture":entry.get("preview_texture",""),"footprint":Vector2(float(array[3]),float(array[5])),"color":Color(color)})

func _append_terrain_entry(result:Array[Dictionary],path:String,value:Dictionary)->void:
	var terrain_type:=String(value.get("terrain_type",""));var entry:Dictionary=catalog.by_id.get("terrain."+terrain_type,{})
	var positions:Variant=value.get("positions",[])
	if positions is Array:
		for position_index in positions.size():
			var position:Variant=positions[position_index]
			if position is Array and position.size()>=2:_append_terrain_cell(result,"%s.positions[%d]"%[path,position_index],position,terrain_type,entry)
	var position:Variant=value.get("position",[])
	if position is Array and position.size()>=2:_append_terrain_cell(result,path+".position",position,terrain_type,entry)

func _append_terrain_cell(result:Array[Dictionary],path:String,position:Array,terrain_type:String,entry:Dictionary)->void:
	var colors:={"water":"3d9fd6","sand":"d9bd72","mud":"8a603f","forest_floor":"62945c","stone":"a6a79f","rock":"77736d"}
	result.append({"id":_stable_id(path),"path":path,"field":"terrain_tiles","label":terrain_type,"position":Vector3(float(position[0]),0,float(position[1])),"size":Vector3.ONE,"shape":"terrain","role":"terrain","variant":-1,"texture":entry.get("preview_texture",""),"display_height":1.0,"footprint":Vector2.ONE,"color":Color(String(colors.get(terrain_type,"ff3344")))})

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
	var is_bridge:=type_id=="structure.bridge"
	var shape:="bridge" if is_bridge else ("building" if type_id.begins_with("building.") else ("rectangle" if String(entry.get("scale_mode",""))=="explicit_size" else "point"))
	var fp:Variant=entry.get("footprint",[0.8,0.8]);if not fp is Array:fp=[float(s[0]),float(s[2])]
	if is_bridge:
		var length:=float(value.get("length",3));var width:=float(value.get("width",1.0))
		fp=[length,width] if String(value.get("orientation","vertical"))=="horizontal" else [width,length]
		s=[float(fp[0]),float(value.get("elevation",1.0)),float(fp[1])]
	var object_label:Variant=entry.get("display_name",type_id)
	if type_id=="npc.opponent":object_label=_trainer_definition(value).get("name",object_label)
	var editor_object:={"id":_stable_id(path),"path":path,"field":"objects","label":object_label,"position":Vector3(float(p[0]),float(p[1]),float(p[2])),"size":Vector3(float(s[0]),float(s[1]),float(s[2])),"shape":shape,"variant":-1,"texture":entry.get("preview_texture",""),"display_height":value.get("height",entry.get("display_height",1.0)),"footprint":Vector2(float(fp[0]),float(fp[1])),"color":Color("#d4b47a") if shape=="building" else Color("#dce6ee"),"universal_type":type_id}
	if shape=="building":
		var extension:=float(entry.get("front_depth_extension",0.0));editor_object["display_width"]=float(s[0])*(1.08 if type_id=="building.medical_ward" else 1.15)
		editor_object["footprint"]=Vector2(float(s[0]),float(s[2])+extension);editor_object["footprint_offset"]=Vector2(0,extension*0.5)
	result.append(editor_object)

func _append_building(result:Array[Dictionary],path:String,position:Array,building_size:Array,type_id:String,size_path:String)->void:
	var entry:Dictionary=catalog.by_id.get(type_id,{})
	var width_multiplier:=1.08 if type_id=="building.medical_ward" else 1.15;var extension:=float(entry.get("front_depth_extension",0.0))
	result.append({"id":_stable_id(path),"path":path,"field":"building","label":entry.get("display_name","Building"),"position":Vector3(float(position[0]),float(position[1]),float(position[2])),"size":Vector3(float(building_size[0]),float(building_size[1]),float(building_size[2])),"size_path":size_path,"shape":"building","variant":-1,"texture":entry.get("preview_texture",""),"display_width":float(building_size[0])*width_multiplier,"footprint":Vector2(float(building_size[0]),float(building_size[2])+extension),"footprint_offset":Vector2(0,extension*0.5),"color":Color("#d4b47a")})

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

func _on_object_selected(id:String)->void:
	selected_id=id;_refresh_inspector();status_label.text="Selection cleared." if id.is_empty() else "Selected %s."%String(_find_object(id).get("label","object"))

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
	elif object.field=="trainers":document.set_value(path+".position",[value.x,value.y,value.z])
	elif object.field=="terrain_tiles":document.set_value(path,[roundi(value.x),roundi(value.z)])
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

func _terrain_stroke_started()->void:
	terrain_stroke_changed=false

func _terrain_cell_changed(cell:Vector2i,erase:bool)->void:
	if document==null or not document.data.get("terrain_tiles") is Array:return
	var terrain_type:=String(terrain_type_option.get_item_metadata(terrain_type_option.selected))
	var owners:Array[Dictionary]=[]
	for entry_index in document.data.terrain_tiles.size():
		var entry:Variant=document.data.terrain_tiles[entry_index]
		if not entry is Dictionary:continue
		if entry.get("positions") is Array:
			for position_index in range(entry.positions.size()-1,-1,-1):
				var position:Variant=entry.positions[position_index]
				if position is Array and position.size()==2 and Vector2i(roundi(float(position[0])),roundi(float(position[1])))==cell:owners.append({"entry":entry,"index":position_index,"single":false})
		var position:Variant=entry.get("position",null)
		if position is Array and position.size()==2 and Vector2i(roundi(float(position[0])),roundi(float(position[1])))==cell:owners.append({"entry":entry,"single":true})
	if erase and owners.is_empty():return
	if not erase and owners.size()==1 and String(owners[0].entry.get("terrain_type",""))==terrain_type:return
	if not terrain_stroke_changed:_push_undo();terrain_stroke_changed=true
	for owner in owners:
		if owner.single:owner.entry.erase("position")
		else:owner.entry.positions.remove_at(owner.index)
	if not erase:
		var target:Dictionary={}
		for entry in document.data.terrain_tiles:
			if entry is Dictionary and String(entry.get("terrain_type",""))==terrain_type and entry.get("positions") is Array:target=entry;break
		if target.is_empty():target={"terrain_type":terrain_type,"positions":[]};document.data.terrain_tiles.append(target)
		target.positions.append([cell.x,cell.y])
	document.dirty=true;editor_objects=_extract_objects();canvas.set_document_objects(editor_objects,_map_size());issues=MapValidatorRef.validate(document);_refresh_validation();_refresh_canvas_validation();_refresh_raw()

func _terrain_stroke_finished()->void:
	if terrain_stroke_changed:_refresh_all();status_label.text="Terrain stroke applied. Undo is available."

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
	return type_id if type_id.begins_with("tree.") or type_id.begins_with("flower.") or type_id=="cave.vine" or type_id in ["structure.bridge","block.water","block.sand","block.rock","building.house","building.medical_ward","npc.opponent","npc.generic"] else ""

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
		if placement_type=="structure.bridge":value={"type":placement_type,"position":[x,y,z],"orientation":"vertical","length":5,"width":1.0,"elevation":1.0,"entrance_length":1.0,"traversal_layer":1}
		elif placement_type=="npc.generic":value.merge({"speaker":"NPC","dialogue":["Hello, traveler!"]})
		elif placement_type=="npc.opponent":
			var trainer_id:=_create_trainer_definition()
			value["trainer_id"]=trainer_id
		elif entry.has("display_height"):value["height"]=float(entry.display_height)
	elif kind=="zone":value={"position":[x,y,z],"size":[3,0.25,3],"encounter_chance":0.2}
	elif kind=="furnishing":value={"type":String(serialization.get("prop_type","")),"position":[x,y,z],"height":float(entry.get("display_height",1.0))}
	elif kind=="terrain_tile":value={"terrain_type":String(serialization.get("terrain_type","")),"position":[roundi(x),roundi(z)]}
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
	if event.keycode==KEY_ESCAPE and canvas.terrain_brush_mode!="select":
		canvas.terrain_brush_mode="select";canvas.queue_redraw();status_label.text="Selection tool active.";get_viewport().set_input_as_handled()

func _refresh_inspector()->void:
	for child in inspector.get_children():child.queue_free()
	var object:=_find_object(selected_id)
	if object.is_empty():var l:=Label.new();l.text="Select an object to edit its properties.";inspector.add_child(l);return
	var title:=Label.new();title.text=String(object.field)+"\n"+String(object.path);title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(title)
	if bool(object.get("linked",false)):
		var linked_note:=Label.new();linked_note.text="Read-only linked object from %s. Double-click it to open the owning map."%String(object.source_file);linked_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(linked_note);return
	_add_vector_editor("Position",object.position,func(v):_push_undo();_write_object_position(object,v);_after_edit())
	if String(object.get("universal_type",""))=="structure.bridge":_add_bridge_editor(object)
	elif String(object.get("universal_type","")).begins_with("npc."):_add_character_editor(object)
	elif object.field=="objects" and object.shape=="point":
		var height:=SpinBox.new();height.min_value=0.05;height.max_value=20;height.step=0.05;height.value=float(object.display_height);height.prefix="Visual height ";height.value_changed.connect(func(v):_push_undo();var record:Dictionary=_get_path(String(object.path));record["height"]=v;document.dirty=true;_after_edit());inspector.add_child(height)
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

func _add_bridge_editor(object:Dictionary)->void:
	var record:Variant=_get_path(String(object.path));if not record is Dictionary:return
	var orientation:=OptionButton.new();orientation.name="BridgeOrientation";orientation.add_item("Horizontal");orientation.set_item_metadata(0,"horizontal");orientation.add_item("Vertical");orientation.set_item_metadata(1,"vertical");orientation.select(0 if String(record.get("orientation",""))=="horizontal" else 1)
	orientation.item_selected.connect(func(index):_set_bridge_field(object,"orientation",String(orientation.get_item_metadata(index))));inspector.add_child(orientation)
	_add_bridge_number(object,"length",3,1000,1,true)
	_add_bridge_number(object,"width",1.0,1000,0.5,false)
	_add_bridge_number(object,"elevation",0.5,1000,0.25,false)
	_add_bridge_number(object,"entrance_length",0.5,1000,0.25,false)
	_add_bridge_number(object,"traversal_layer",1,1024,1,true)

func _add_bridge_number(object:Dictionary,field:String,min_value:float,max_value:float,step:float,integer_value:bool)->void:
	var record:Dictionary=_get_path(String(object.path));var spin:=SpinBox.new();spin.name="Bridge"+field.to_pascal_case();spin.min_value=min_value;spin.max_value=max_value;spin.step=step;spin.value=float(record.get(field,min_value));spin.prefix=field.replace("_"," ").capitalize()+" ";spin.value_changed.connect(func(value):_set_bridge_field(object,field,int(value) if integer_value else value));inspector.add_child(spin)

func _set_bridge_field(object:Dictionary,field:String,value:Variant)->void:
	_push_undo();var record:Variant=_get_path(String(object.path));if not record is Dictionary:return
	record[field]=value;document.dirty=true;_after_edit()

func _add_character_editor(object:Dictionary)->void:
	var record:Variant=_get_path(String(object.path));if not record is Dictionary:return
	var is_trainer:=String(object.get("universal_type",""))=="npc.opponent"
	var editable:Dictionary=_trainer_definition(record) if is_trainer else record
	var catalog_backed:bool=is_trainer and _trainer_is_catalog_backed(record)
	if is_trainer and record.has("trainer_id"):
		var id_label:=Label.new();id_label.text="Trainer ID: "+String(record.trainer_id)+" (definition: data/trainers.json)";id_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(id_label)
	var name_field:="name" if is_trainer else "speaker"
	var name_edit:=LineEdit.new();name_edit.placeholder_text="Trainer name" if name_field=="name" else "Speaker name";name_edit.text=String(editable.get(name_field,""));name_edit.focus_exited.connect(func():editable[name_field]=name_edit.text;_mark_character_dirty(catalog_backed));inspector.add_child(name_edit)
	var dialogue_edit:=LineEdit.new();dialogue_edit.placeholder_text="Dialogue pages separated by |";dialogue_edit.text=" | ".join(editable.get("dialogue",[]));dialogue_edit.focus_exited.connect(func():editable["dialogue"]=_split_nonempty(dialogue_edit.text,"|");_mark_character_dirty(catalog_backed));inspector.add_child(dialogue_edit)
	var sprite_edit:=LineEdit.new();sprite_edit.name="NpcSprite";sprite_edit.placeholder_text="Sprite ID (man, woman, boy, girl)";sprite_edit.text=String(editable.get("sprite",""));sprite_edit.focus_exited.connect(func():editable["sprite"]=sprite_edit.text.strip_edges();_mark_character_dirty(catalog_backed));inspector.add_child(sprite_edit)
	var color_edit:=LineEdit.new();color_edit.name="NpcColor";color_edit.placeholder_text="Fallback color (hex)";color_edit.text=String(editable.get("color",""));color_edit.focus_exited.connect(func():editable["color"]=color_edit.text.strip_edges().trim_prefix("#");_mark_character_dirty(catalog_backed));inspector.add_child(color_edit)
	if is_trainer:
		_add_team_rows(editable,catalog_backed)

func _trainer_definition(record:Dictionary)->Dictionary:
	var trainer_id:=String(record.get("trainer_id",""))
	if trainer_catalog_doc!=null and trainer_catalog_doc.data.get("trainers") is Dictionary and trainer_catalog_doc.data.trainers.get(trainer_id) is Dictionary:return trainer_catalog_doc.data.trainers[trainer_id]
	return record

func _trainer_is_catalog_backed(record:Dictionary)->bool:
	var trainer_id:=String(record.get("trainer_id",""))
	return trainer_catalog_doc!=null and trainer_catalog_doc.data.get("trainers") is Dictionary and trainer_catalog_doc.data.trainers.get(trainer_id) is Dictionary

func _mark_character_dirty(catalog_backed:bool)->void:
	if catalog_backed and trainer_catalog_doc!=null:trainer_catalog_doc.dirty=true
	else:document.dirty=true
	_refresh_raw()

func _add_team_rows(definition:Dictionary,catalog_backed:bool)->void:
	var team:Variant=definition.get("team",definition.get("party",[]))
	if not team is Array:team=[];definition["team"]=team
	var heading:=Label.new();heading.text="Fakemon Team (%d / 7)"%team.size();inspector.add_child(heading)
	for member_index in team.size():
		var original:Variant=team[member_index]
		if not original is Dictionary:
			original={"fakemon":original,"level":5};team[member_index]=original
		var member:Dictionary=original;var row:=HBoxContainer.new();inspector.add_child(row)
		var species:=OptionButton.new();species.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		for species_name in fakemon_names:species.add_item(species_name)
		var reference:Variant=member.get("fakemon",0);var selected:int=int(reference) if reference is int or reference is float else fakemon_names.find(String(reference));species.select(clampi(selected,0,maxi(0,fakemon_names.size()-1)));species.item_selected.connect(func(index):member["fakemon"]=fakemon_names[index];_mark_character_dirty(catalog_backed));row.add_child(species)
		var level:=SpinBox.new();level.min_value=1;level.max_value=100;level.value=int(member.get("level",5));level.prefix="Lv. ";level.value_changed.connect(func(v):member["level"]=int(v);_mark_character_dirty(catalog_backed));row.add_child(level)
		var remove:=Button.new();remove.text="Remove";remove.pressed.connect(func():team.remove_at(member_index);_mark_character_dirty(catalog_backed);_refresh_inspector());row.add_child(remove)
	var add:=Button.new();add.text="Add Fakemon";add.disabled=team.size()>=7;add.pressed.connect(func():team.append({"fakemon":fakemon_names[0] if not fakemon_names.is_empty() else 0,"level":5});_mark_character_dirty(catalog_backed);_refresh_inspector());inspector.add_child(add)

func _create_trainer_definition()->String:
	if trainer_catalog_doc==null:return ""
	if not trainer_catalog_doc.data.get("trainers") is Dictionary:trainer_catalog_doc.data["trainers"]={}
	var number:=1;var trainer_id:="trainer_%03d"%number
	while trainer_catalog_doc.data.trainers.has(trainer_id):number+=1;trainer_id="trainer_%03d"%number
	trainer_catalog_doc.data.trainers[trainer_id]={"name":"NEW TRAINER","team":[{"fakemon":fakemon_names[0] if not fakemon_names.is_empty() else 0,"level":5}],"dialogue":["Let's battle!"],"color":"df6d5f"}
	trainer_catalog_doc.dirty=true
	return trainer_id

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
	if document.data.has("base_terrain_type"):
		var base_label:=Label.new();base_label.text="Base terrain type";metadata_box.add_child(base_label)
		var base:=OptionButton.new();base.name="BaseTerrainType"
		for terrain_type in ["forest_floor","sand","water","mud","stone","rock"]:base.add_item(terrain_type.replace("_"," ").capitalize());base.set_item_metadata(base.item_count-1,terrain_type)
		var current:=String(document.data.get("base_terrain_type",""));for index in base.item_count:if String(base.get_item_metadata(index))==current:base.select(index)
		base.item_selected.connect(func(index):_push_undo();document.set_value("$.base_terrain_type",String(base.get_item_metadata(index)));_after_edit());metadata_box.add_child(base)
	if document.data.get("map_metadata") is Dictionary:
		for field in ["id","display_name","layout_type","group"]:
			var meta_edit:=LineEdit.new();meta_edit.placeholder_text="Map "+field;meta_edit.text=String(document.data.map_metadata.get(field,""));meta_edit.text_submitted.connect(func(text):_push_undo();document.data.map_metadata[field]=text;document.kind=MapSchemaRef.kind_for_data(document.data,document.kind);document.dirty=true;_after_edit());metadata_box.add_child(meta_edit)
	if document.data.get("tall_grass_species") is Array:
		_add_encounter_species_editor("Grass encounters", "tall_grass_species")
	if document.data.get("water_species") is Array:
		_add_encounter_species_editor("Water encounters", "water_species")
	if document.data.has("water_encounter_chance"):
		var chance:=SpinBox.new();chance.name="WaterEncounterChance";chance.min_value=0;chance.max_value=1;chance.step=0.01;chance.value=float(document.data.water_encounter_chance);chance.prefix="Water encounter chance ";chance.value_changed.connect(func(value):_push_undo();document.set_value("$.water_encounter_chance",value);_after_edit());metadata_box.add_child(chance)

func _add_encounter_species_editor(label_text:String,field:String)->void:
	var edit:=LineEdit.new();edit.placeholder_text=label_text+": Fakemon@level, Fakemon@level";var labels:Array[String]=[]
	for value:Variant in document.data.get(field,[]):labels.append("%s@%d"%[value.get("fakemon","Unknown"),int(value.get("level",5))] if value is Dictionary else String(value))
	edit.text=", ".join(labels);edit.text_submitted.connect(func(text):_set_encounter_species(field,text));metadata_box.add_child(edit)

func _set_numeric_array(field:String,text:String)->void:
	var values:=text.split(",");var parsed:Array=[];for v in values:parsed.append(float(v.strip_edges()))
	_push_undo();document.set_value("$."+field,parsed);_after_edit()

func _set_encounter_species(field:String,text:String)->void:
	var values:Array=[];for v in text.split(","):if not v.strip_edges().is_empty():var parts:=v.strip_edges().split("@",false,1);values.append({"fakemon":parts[0].strip_edges(),"level":clampi(int(parts[1]),1,100)} if parts.size()>1 and parts[1].is_valid_int() else parts[0].strip_edges())
	_push_undo();document.set_value("$."+field,values);_after_edit()

func _after_edit()->void:_refresh_all()

func _refresh_validation()->void:
	validation_list.clear();for issue in issues:var icon:="ERROR" if issue.severity=="error" else "WARN";var index:=validation_list.add_item("[%s] %s — %s"%[icon,issue.path,issue.message]);validation_list.set_item_metadata(index,issue.path)
	if issues.is_empty():validation_list.add_item("No validation issues.")

func _refresh_canvas_validation()->void:
	canvas.validation_error_ids.clear();canvas.terrain_error_cells.clear()
	for issue in issues:
		if String(issue.get("severity",""))!="error":continue
		var issue_path:=String(issue.get("path",""))
		var terrain_entry_path:=issue_path.substr(0,issue_path.find("]")+1) if issue_path.begins_with("$.terrain_tiles[") else ""
		for object in editor_objects:
			var object_path:=String(object.path)
			if issue_path.begins_with(object_path) or object_path.begins_with(issue_path) or (not terrain_entry_path.is_empty() and object_path.begins_with(terrain_entry_path)):canvas.validation_error_ids[String(object.id)]=true;canvas.terrain_error_cells[Vector2i(roundi(float(object.position.x)),roundi(float(object.position.z)))]=true
		var value:Variant=_get_path(issue_path)
		if value is Array and value.size()==2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):canvas.terrain_error_cells[Vector2i(roundi(float(value[0])),roundi(float(value[1])))]=true
	canvas.queue_redraw()

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

func _request_rename()->void:
	if document==null or document.path.is_empty():return
	if document.dirty:status_label.text="Save the map before renaming it.";return
	if document.path.get_file().to_lower()=="map_index.json":
		rename_dialog.title="Rename World Index";rename_dialog.dialog_text="Display name (the runtime filename remains map_index.json):"
		var metadata:Variant=document.data.get("index_metadata",{});rename_edit.text=String(metadata.get("display_name","Project Paradise World")) if metadata is Dictionary else "Project Paradise World"
	else:
		rename_dialog.title="Rename Map";rename_dialog.dialog_text="New filename (.json is optional):";rename_edit.text=document.path.get_file()
	rename_dialog.popup_centered()

func _confirm_rename()->void:
	var requested:=rename_edit.text.strip_edges()
	if requested.is_empty():return
	if document.path.get_file().to_lower()=="map_index.json":
		_push_undo()
		if not document.data.get("index_metadata") is Dictionary:document.data["index_metadata"]={"id":"project_paradise_world"}
		document.data.index_metadata["display_name"]=requested;document.dirty=true;_refresh_all();status_label.text="World index display name changed to "+requested+". Save to persist it.";return
	if not requested.to_lower().ends_with(".json"):requested+=".json"
	if requested.contains("/") or requested.contains("\\"):status_label.text="Enter a filename, not a path.";return
	_rename_current_map(requested)

func _rename_current_map(new_filename:String)->bool:
	var old_path:=document.path;var old_filename:=old_path.get_file();var new_path:=map_directory.path_join(new_filename)
	if old_filename==new_filename:return true
	if FileAccess.file_exists(new_path):status_label.text="Rename blocked: %s already exists."%new_filename;return false
	var old_backup:=old_path+".bak";var copy_error:=document._copy_file(old_path,old_backup)
	if copy_error!=OK:status_label.text="Rename blocked: could not create backup.";return false
	var metadata:Variant=document.data.get("map_metadata",{})
	if metadata is Dictionary:metadata["id"]=new_filename.get_basename()
	var save_error:=document.save_atomic(new_path,[])
	if save_error!=OK:status_label.text="Rename blocked while writing the new map.";return false
	for filename in DirAccess.get_files_at(map_directory):
		if not filename.to_lower().ends_with(".json") or filename in [old_filename,new_filename]:continue
		var ref_doc:=MapDocumentRef.load_file(map_directory.path_join(filename));if not ref_doc.parse_error.is_empty():continue
		if _replace_filename_references(ref_doc.data,old_filename,new_filename):
			ref_doc.dirty=true;var ref_error:=ref_doc.save_atomic(ref_doc.path,[])
			if ref_error!=OK:status_label.text="Renamed map, but failed to update %s."%filename;return false
	DirAccess.remove_absolute(old_path)
	document.path=new_path;document.kind=MapSchemaRef.kind_for_data(document.data,MapSchemaRef.kind_for_file(new_path));_refresh_all();status_label.text="Renamed %s → %s and updated references. Backup: %s"%[old_filename,new_filename,old_backup.get_file()];return true

func _replace_filename_references(value:Variant,old_filename:String,new_filename:String)->bool:
	var changed:=false
	if value is Dictionary:
		var rename_keys:Array=[]
		for key in value.keys():
			if value[key] is String and String(value[key])==old_filename:value[key]=new_filename;changed=true
			elif value[key] is Dictionary or value[key] is Array:changed=_replace_filename_references(value[key],old_filename,new_filename) or changed
			if String(key)==old_filename.get_basename():rename_keys.append(key)
		for key in rename_keys:value[new_filename.get_basename()]=value[key];value.erase(key);changed=true
	elif value is Array:
		for i in value.size():
			if value[i] is String and String(value[i])==old_filename:value[i]=new_filename;changed=true
			elif value[i] is Dictionary or value[i] is Array:changed=_replace_filename_references(value[i],old_filename,new_filename) or changed
	return changed

func _save_to(path:String)->void:
	issues=MapValidatorRef.validate(document);var error:=document.save_atomic(path,issues)
	if error==OK:
		if trainer_catalog_doc!=null and trainer_catalog_doc.dirty:
			var trainer_error:=trainer_catalog_doc.save_atomic(trainer_catalog_doc.path,[])
			if trainer_error!=OK:status_label.text="Map saved, but trainer catalog save failed.";return
		_register_current_map();status_label.text="Saved map and trainer catalog atomically; backup: "+path.get_file()+".bak";_refresh_all()
	else:status_label.text="Save blocked: fix validation errors before replacing output."

func _register_current_map()->void:
	if document.path.get_file().to_lower()=="map_index.json" or not document.data.get("map_metadata") is Dictionary:return
	var index_path:=map_directory.path_join("map_index.json");var index_doc:=MapDocumentRef.load_file(index_path)
	if not index_doc.parse_error.is_empty():return
	if not index_doc.data.get("maps") is Dictionary:index_doc.data["maps"]={}
	var map_id:=String(document.data.map_metadata.get("id",document.path.get_basename().get_file()));index_doc.data.maps[map_id]=document.path.get_file()
	if not index_doc.data.get("map_groups") is Dictionary:index_doc.data["map_groups"]={}
	var group:=String(document.data.map_metadata.get("group","custom"));if not index_doc.data.map_groups.get(group) is Array:index_doc.data.map_groups[group]=[]
	if not index_doc.data.map_groups[group].has(map_id):index_doc.data.map_groups[group].append(map_id)
	index_doc.dirty=true;index_doc.save_atomic(index_path,[])
