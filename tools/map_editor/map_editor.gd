extends Control

func _editor_snapshot() -> String:
	return JSON.stringify({"__npc_editor_snapshot":true,"map":document.deterministic_json(),"definitions":npc_data.definitions})

func _add_npc() -> void:
	if document == null or _is_world_index_document(document):return
	if not npc_data.load_error.is_empty() or (document.data.has("npcs") and not document.data.npcs is Array):
		status_label.text="Repair NPC data errors before adding an NPC.";return
	_push_undo()
	var id:int=npc_data.add_default(document.data)
	document.dirty=true;_after_edit()
	for object in editor_objects:
		if String(object.field)=="npcs" and int(object.npc_id)==id:canvas.select_object(String(object.id));break

func _append_npcs(result:Array[Dictionary])->void:
	var placements:Variant=document.data.get("npcs",[])
	if not placements is Array:return
	for i in placements.size():
		var record:Variant=placements[i]
		if not record is Dictionary or not npc_data.valid_id(record.get("id")):continue
		var p:Variant=record.get("position")
		if not p is Array or p.size()!=3 or not p.all(func(v):return v is int or v is float):continue
		var definition:Dictionary=npc_data.definitions.get(str(int(record.id)),{}) if npc_data.definitions.get(str(int(record.id)),{}) is Dictionary else {}
		var type:String=str(definition.get("type",""));var sprite:String=str(definition.get("sprite",""));var facing:String=str(record.get("facing",""))
		var path:="$.npcs[%d]"%i
		var texture:Texture2D=npc_visuals.texture_for(type,sprite,facing)
		result.append({"id":_stable_id(path),"npc_id":int(record.id),"path":path,"field":"npcs","label":"NPC %d · %s"%[int(record.id),sprite],"position":Vector3(float(p[0]),float(p[1]),float(p[2])),"size":Vector3.ONE,"shape":"point","role":"npc","variant":-1,"texture":"","resolved_texture":texture,"display_height":1.25 if type=="human" else 0.9,"footprint":Vector2(0.8,0.8),"color":Color("#67c46a")})

func _add_npc_inspector(object:Dictionary)->void:
	var key:=str(int(object.npc_id))
	var definition:Variant=npc_data.definitions.get(key)
	var label:=Label.new();label.text="NPC ID: "+key;inspector.add_child(label)
	if not definition is Dictionary:
		var missing:=Label.new();missing.text="Missing companion definition. Repair the companion before saving.";missing.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(missing);return
	var type_picker:=OptionButton.new();type_picker.name="NpcType"
	for type in ["human","fakemon"]:type_picker.add_item(type.capitalize());type_picker.set_item_metadata(type_picker.item_count-1,type)
	type_picker.select(0 if definition.get("type")=="human" else 1)
	type_picker.item_selected.connect(func(index):
		var type:=String(type_picker.get_item_metadata(index));var sprites:Array=npc_visuals.sprites(type)
		if sprites.is_empty():return
		_push_undo();definition.type=type;definition.sprite=sprites[0]
		if type=="fakemon":document.set_value(String(object.path)+".facing","down")
		document.dirty=true;_after_edit())
	inspector.add_child(type_picker)
	var sprite_picker:=OptionButton.new();sprite_picker.name="NpcSprite"
	for sprite in npc_visuals.sprites(str(definition.get("type",""))):
		sprite_picker.add_item(String(sprite));sprite_picker.set_item_metadata(sprite_picker.item_count-1,sprite)
		if sprite==definition.get("sprite"):sprite_picker.select(sprite_picker.item_count-1)
	sprite_picker.item_selected.connect(func(index):_push_undo();definition.sprite=String(sprite_picker.get_item_metadata(index));document.dirty=true;_after_edit())
	inspector.add_child(sprite_picker)
	var facing_picker:=OptionButton.new();facing_picker.name="NpcFacing"
	var record:Dictionary=_get_path(String(object.path))
	for facing in npc_data.FACINGS:
		facing_picker.add_item(facing.capitalize());facing_picker.set_item_metadata(facing_picker.item_count-1,facing)
		if facing==record.get("facing"):facing_picker.select(facing_picker.item_count-1)
	facing_picker.item_selected.connect(func(index):_push_undo();document.set_value(String(object.path)+".facing",String(facing_picker.get_item_metadata(index)));_after_edit())
	inspector.add_child(facing_picker)
	_add_npc_movement_inspector(definition)
	var text_label:=Label.new();text_label.text="Interaction text";inspector.add_child(text_label)
	var text:=TextEdit.new();text.name="NpcInteractionText";text.custom_minimum_size.y=120;text.text=str(definition.get("interaction_text",""));inspector.add_child(text)
	var edit_state:={"checkpoint":false}
	text.focus_entered.connect(func():edit_state.checkpoint=false)
	text.text_changed.connect(func():
		if definition.get("interaction_text","")==text.text:return
		if not edit_state.checkpoint:_push_undo();edit_state.checkpoint=true
		definition.interaction_text=text.text;document.dirty=true;_refresh_raw())

func _assign_npc_copy(copy:Dictionary)->void:
	var previous:Dictionary=npc_data.definitions.get(str(int(copy.id)),{}).duplicate(true)
	var id:int=npc_data.next_id(document.data.get("npcs",[]))
	copy.id=id;npc_data.definitions[str(id)]=previous

func _save_npc_pair(path:String,validation:Array)->Error:
	if path.ends_with("_NPC_Data.json"):return ERR_INVALID_PARAMETER
	for issue:Dictionary in validation:
		if String(issue.get("severity",""))=="error":return ERR_INVALID_DATA
	if not npc_data.load_error.is_empty():return ERR_INVALID_DATA
	var companion:String=npc_data.companion_path(path)
	var existed:=FileAccess.file_exists(companion)
	var previous:=FileAccess.get_file_as_string(companion) if existed else ""
	if npc_companion_doc==null:npc_companion_doc=MapDocumentRef.from_text("{}",companion)
	npc_companion_doc.data=npc_data.definitions
	var needs_companion:bool=document.data.has("npcs") or not npc_data.definitions.is_empty() or existed
	if needs_companion:
		var error:=npc_companion_doc.save_atomic(companion,[])
		if error!=OK:return error
	var map_error:=document.save_atomic(path,validation)
	if map_error!=OK and needs_companion:
		if existed:
			var file:=FileAccess.open(companion,FileAccess.WRITE)
			if file!=null:file.store_string(previous);file.close()
			else:push_error("Map save failed and NPC companion rollback failed: "+companion)
		else:DirAccess.remove_absolute(companion)
	return map_error

const MapDocumentRef := preload("res://core/map_document.gd")
const MapSchemaRef := preload("res://core/map_schema.gd")
const MapValidatorRef := preload("res://core/map_validator.gd")
const MapGraphRef := preload("res://core/map_graph.gd")
const AssetCatalogRef := preload("res://core/asset_catalog.gd")
const WallGeometryRef := preload("res://core/wall_geometry.gd")
const CanvasRef := preload("res://ui/editor_canvas.gd")

var npc_movement: Script
var npc_data: RefCounted
var npc_visuals: RefCounted
var npc_companion_doc: MapDocument
var project_root := ""
var map_directory := ""
var document: MapDocument
var catalog: AssetCatalog
var trainer_catalog_doc: MapDocument
var fakemon_names:Array[String]=[]
var canvas: EditorCanvas
var palette: ItemList
var palette_search: LineEdit
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
var import_sprite_dialog: FileDialog
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
var palette_painting := false
var palette_paint_last_key := ""
var activity_tabs: TabContainer
var activity_buttons: Array[Button] = []
var active_wall_id := ""
var attachment_overlay_id := ""
var polygon_asset_path:=""
var polygon_undo_stack:Array[Dictionary]=[]
var polygon_redo_stack:Array[Dictionary]=[]

func _ready() -> void:
	project_root = ProjectSettings.globalize_path("res://").simplify_path().get_base_dir().get_base_dir()
	map_directory = project_root.path_join("data/maps")
	npc_movement = load(project_root.path_join("world/npc_movement.gd"))
	npc_data = load(project_root.path_join("world/npc_map_data.gd")).new()
	npc_visuals = load(project_root.path_join("world/npc_visual_resolver.gd")).new(project_root)
	catalog = AssetCatalogRef.load_catalog(ProjectSettings.globalize_path("res://catalog/map_asset_catalog.json"))
	trainer_catalog_doc=MapDocumentRef.load_file(project_root.path_join("data/trainers.json"))
	var battle_doc:=MapDocumentRef.load_file(project_root.path_join("data/battle_data.json"))
	for species:Variant in battle_doc.data.get("fakemon",[]):if species is Dictionary:fakemon_names.append(String(species.get("name","")))
	_build_ui()
	_load_path(map_directory.path_join("eastern_rainforest_route.json"))

func _build_ui() -> void:
	var root_v := VBoxContainer.new(); root_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root_v)
	var toolbar := HFlowContainer.new(); toolbar.name="DocumentToolbar"; toolbar.custom_minimum_size.y = 42; root_v.add_child(toolbar)
	_add_button(toolbar, "New", _request_new)
	_add_button(toolbar, "Open", _request_open)
	_add_button(toolbar, "Save", _save)
	_add_button(toolbar, "Add NPC", _add_npc)
	_add_button(toolbar, "Save As", _save_as)
	_add_button(toolbar, "Rename", _request_rename)
	toolbar.add_child(VSeparator.new())
	_add_button(toolbar, "Undo", _undo)
	_add_button(toolbar, "Redo", _redo)
	_add_button(toolbar, "Duplicate", _duplicate_selected)
	_add_button(toolbar, "Delete", _delete_selected)
	_add_button(toolbar, "Add Warp", _add_warp)
	var import_button:=_add_button(toolbar,"Import Sprite",_request_import_sprites);import_button.name="ImportSpritesButton";import_button.tooltip_text="Copy image files into assets/overworld and add them to the object palette."
	var test_map_button:=_add_button(toolbar, "Test Map", _test_current_map);test_map_button.name="TestMapButton";test_map_button.tooltip_text="Save and launch the game at this map's entry point."
	toolbar.add_child(VSeparator.new())
	toolbar = HFlowContainer.new(); toolbar.name="EditingToolbar"; toolbar.custom_minimum_size.y=42; root_v.add_child(toolbar)
	var selection_label:=Label.new();selection_label.text="Select";toolbar.add_child(selection_label)
	var selection_group:=ButtonGroup.new()
	var object_mode:=Button.new();object_mode.name="ObjectSelectionMode";object_mode.text="Objects";object_mode.toggle_mode=true;object_mode.button_group=selection_group;object_mode.button_pressed=true;object_mode.tooltip_text="Select NPCs, props, buildings, overlays, and other non-terrain content.";object_mode.pressed.connect(func():canvas.set_selection_mode("objects");status_label.text="Object selection mode active. Terrain cannot be selected.");toolbar.add_child(object_mode)
	var terrain_mode:=Button.new();terrain_mode.name="TerrainSelectionMode";terrain_mode.text="Terrain";terrain_mode.toggle_mode=true;terrain_mode.button_group=selection_group;terrain_mode.tooltip_text="Select terrain cells, floor blocks, water blocks, and tile assets only.";terrain_mode.pressed.connect(func():canvas.set_selection_mode("terrain");status_label.text="Terrain selection mode active. Objects cannot be selected.");toolbar.add_child(terrain_mode)
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
	var placement_preview := CheckBox.new();placement_preview.name="PlacementPreview";placement_preview.text="Placement Preview";placement_preview.tooltip_text="Hide editor bounds, boxes, labels, and grid while showing the authored ground terrain.";placement_preview.toggled.connect(func(enabled):canvas.placement_preview=enabled;canvas.queue_redraw());toolbar.add_child(placement_preview)
	_add_button(toolbar, "Frame Map", func(): canvas.frame_all())
	var debug_geometry:=CheckBox.new();debug_geometry.text="Debug Geometry";debug_geometry.tooltip_text="Show selected-object wall render, collision, origin, and bake diagnostics.";debug_geometry.toggled.connect(func(enabled):canvas.debug_geometry=enabled;canvas.queue_redraw());toolbar.add_child(debug_geometry)
	status_label = Label.new(); status_label.clip_text=true; status_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT; root_v.add_child(status_label)

	var split := HSplitContainer.new(); split.name="EditorWorkspace";split.size_flags_horizontal=Control.SIZE_EXPAND_FILL;split.size_flags_vertical=Control.SIZE_EXPAND_FILL;split.split_offset=320;root_v.add_child(split)
	var sidebar := VBoxContainer.new(); sidebar.name="ActivitySidebar";sidebar.custom_minimum_size.x=320;split.add_child(sidebar)
	var activity_header:=HBoxContainer.new();activity_header.name="ActivityHeader";sidebar.add_child(activity_header)
	activity_tabs=TabContainer.new();activity_tabs.name="ActivityPages";activity_tabs.tabs_visible=false;activity_tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;sidebar.add_child(activity_tabs)
	for activity_name in ["OBJECTS","INSPECTOR","MAP"]:
		var button:=Button.new();button.text=activity_name;button.toggle_mode=true;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.custom_minimum_size.y=44;button.add_theme_font_size_override("font_size",14);var activity_index:=activity_buttons.size();button.pressed.connect(func():_set_activity(activity_index));activity_header.add_child(button);activity_buttons.append(button)
	var objects_page:=VBoxContainer.new();objects_page.name="Objects";activity_tabs.add_child(objects_page)
	var pal_title := Label.new(); pal_title.text="OBJECTS";pal_title.add_theme_font_size_override("font_size",18); objects_page.add_child(pal_title)
	palette_search=LineEdit.new();palette_search.name="ObjectSearch";palette_search.placeholder_text="Search objects…";palette_search.text_changed.connect(func(_text):_populate_palette());objects_page.add_child(palette_search)
	palette = ItemList.new(); palette.size_flags_vertical=Control.SIZE_EXPAND_FILL; palette.item_selected.connect(_palette_selected); palette.gui_input.connect(_palette_gui_input); objects_page.add_child(palette)
	_populate_palette()
	palette_help=Label.new();palette_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;palette_help.custom_minimum_size.y=54;objects_page.add_child(palette_help)
	_add_button(objects_page,"Add at Origin",_add_palette_object)
	var insp_scroll:=ScrollContainer.new();insp_scroll.name="Inspector";insp_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;insp_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;activity_tabs.add_child(insp_scroll);inspector=VBoxContainer.new();inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;insp_scroll.add_child(inspector)
	var map_scroll:=ScrollContainer.new();map_scroll.name="Map";map_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;map_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;activity_tabs.add_child(map_scroll)
	var map_page:=VBoxContainer.new();map_page.size_flags_horizontal=Control.SIZE_EXPAND_FILL;map_scroll.add_child(map_page)
	metadata_box=VBoxContainer.new();metadata_box.name="MapProperties";map_page.add_child(metadata_box)
	var map_details:=TabContainer.new();map_details.name="MapDetails";map_details.custom_minimum_size.y=260;map_details.size_flags_vertical=Control.SIZE_EXPAND_FILL;map_page.add_child(map_details)
	validation_list=ItemList.new();validation_list.name="Validation";validation_list.item_selected.connect(_validation_selected);map_details.add_child(validation_list)
	raw_json=TextEdit.new();raw_json.name="Raw JSON";raw_json.editable=false;raw_json.wrap_mode=TextEdit.LINE_WRAPPING_NONE;map_details.add_child(raw_json)
	graph_text=RichTextLabel.new();graph_text.name="Warp Graph";graph_text.bbcode_enabled=true;graph_text.fit_content=false;map_details.add_child(graph_text)
	canvas = CanvasRef.new(); canvas.project_root=project_root; canvas.custom_minimum_size=Vector2(600,500); canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL; canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL; canvas.object_selected.connect(_on_object_selected);canvas.object_activated.connect(_on_object_activated); canvas.object_moved.connect(_on_canvas_moved);canvas.objects_moved.connect(_on_canvas_objects_moved); canvas.object_resized.connect(_on_canvas_resized);canvas.map_resized.connect(_on_map_resized);canvas.terrain_stroke_started.connect(_terrain_stroke_started);canvas.terrain_cell_changed.connect(_terrain_cell_changed);canvas.terrain_stroke_finished.connect(_terrain_stroke_finished);canvas.wall_anchor_requested.connect(_wall_anchor_requested);canvas.wall_finished.connect(_wall_finished);canvas.wall_anchor_moved.connect(_wall_anchor_moved);canvas.wall_anchors_moved.connect(_wall_anchors_moved);canvas.host_picked.connect(_on_attachment_host_picked);canvas.collision_polygon_changed.connect(_on_collision_polygon_changed); split.add_child(canvas)
	_set_activity(0)

	open_dialog=FileDialog.new();open_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;open_dialog.access=FileDialog.ACCESS_FILESYSTEM;open_dialog.add_filter("*.json","Map JSON");open_dialog.file_selected.connect(_load_path);add_child(open_dialog)
	save_dialog=FileDialog.new();save_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;save_dialog.access=FileDialog.ACCESS_FILESYSTEM;save_dialog.add_filter("*.json","Map JSON");save_dialog.file_selected.connect(_save_to);add_child(save_dialog)
	import_sprite_dialog=FileDialog.new();import_sprite_dialog.title="Import Overworld Sprites";import_sprite_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILES;import_sprite_dialog.access=FileDialog.ACCESS_FILESYSTEM;import_sprite_dialog.add_filter("*.png, *.webp, *.jpg, *.jpeg","Sprite Images");import_sprite_dialog.files_selected.connect(_import_sprite_files);add_child(import_sprite_dialog)
	unsaved_dialog=ConfirmationDialog.new();unsaved_dialog.dialog_text="Discard unsaved map changes?";unsaved_dialog.confirmed.connect(func(): if pending_action.is_valid(): pending_action.call());add_child(unsaved_dialog)
	rename_dialog=ConfirmationDialog.new();rename_dialog.title="Rename Map";rename_dialog.dialog_text="New filename (.json is optional):";rename_dialog.confirmed.connect(_confirm_rename);add_child(rename_dialog);rename_edit=LineEdit.new();rename_edit.custom_minimum_size.x=360;rename_dialog.add_child(rename_edit)
	palette_drag_preview=PanelContainer.new();palette_drag_preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;palette_drag_preview.visible=false;palette_drag_preview.z_index=100;add_child(palette_drag_preview)
	palette_drag_preview_label=Label.new();palette_drag_preview_label.add_theme_font_size_override("font_size",14);palette_drag_preview_label.add_theme_color_override("font_color",Color.WHITE);palette_drag_preview.add_child(palette_drag_preview_label)

func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button:=Button.new();button.text=text;button.pressed.connect(callback);parent.add_child(button);return button

func _populate_palette()->void:
	if palette==null:return
	var search:=palette_search.text.strip_edges().to_lower() if palette_search!=null else ""
	palette.clear();palette_index_by_type.clear()
	for entry in catalog.entries:
		if bool(entry.get("non_serializing",false)) or bool(entry.get("palette_hidden",false)):continue
		var label:="%s  ·  %s" % [entry.get("category",""),entry.get("display_name","")]
		if not search.is_empty() and not label.to_lower().contains(search):continue
		var index:=palette.add_item(label);palette.set_item_metadata(index,entry.get("type_id",""));palette_index_by_type[String(entry.get("type_id",""))]=index

func _set_activity(index:int)->void:
	if activity_tabs==null:return
	activity_tabs.current_tab=clampi(index,0,activity_tabs.get_tab_count()-1)
	for button_index in activity_buttons.size():
		activity_buttons[button_index].set_pressed_no_signal(button_index==activity_tabs.current_tab)

func _request_open() -> void:
	_run_after_discard_check(func(): open_dialog.current_dir=map_directory;open_dialog.popup_centered_ratio(0.75))

func _request_import_sprites()->void:
	import_sprite_dialog.popup_centered_ratio(0.75)

func _import_sprite_files(paths:PackedStringArray)->void:
	var destination_directory:=project_root.path_join("assets/overworld");var imported:=0;var skipped:Array[String]=[]
	for source_path:String in paths:
		var extension:=source_path.get_extension().to_lower()
		if not extension in ["png","webp","jpg","jpeg"]:skipped.append(source_path.get_file()+" (unsupported format)");continue
		var image:=Image.load_from_file(source_path)
		if image==null or image.is_empty():skipped.append(source_path.get_file()+" (invalid image)");continue
		var destination:=destination_directory.path_join(source_path.get_file())
		if FileAccess.file_exists(destination):skipped.append(source_path.get_file()+" (already exists)");continue
		if DirAccess.copy_absolute(source_path,destination)!=OK:skipped.append(source_path.get_file()+" (copy failed)");continue
		imported+=1
	if imported>0:
		catalog=AssetCatalogRef.load_catalog(ProjectSettings.globalize_path("res://catalog/map_asset_catalog.json"));_populate_palette();canvas.texture_cache.clear();canvas.queue_redraw()
		# Generate the gameplay project's normal .import sidecars in the background.
		OS.create_process(OS.get_executable_path(),["--headless","--rendering-driver","opengl3","--path",project_root,"--editor","--quit-after","2"])
	status_label.text="Imported %d sprite%s into assets/overworld%s"%[imported,"" if imported==1 else "s","; skipped: "+", ".join(skipped) if not skipped.is_empty() else "."]

func _request_new() -> void:
	_run_after_discard_check(_new_document)

func _run_after_discard_check(action: Callable) -> void:
	if document != null and (document.dirty or (trainer_catalog_doc!=null and trainer_catalog_doc.dirty)): pending_action=action;unsaved_dialog.popup_centered()
	else: action.call()

func _test_current_map()->void:
	if document==null or document.path.is_empty():status_label.text="Test Map requires a saved map file.";return
	if _is_world_index_document(document):status_label.text="Open an individual map before using Test Map.";return
	if document.dirty or (trainer_catalog_doc!=null and trainer_catalog_doc.dirty):
		_save_to(document.path)
		if document.dirty or (trainer_catalog_doc!=null and trainer_catalog_doc.dirty):return
	var filename:=document.path.get_file()
	var executable:=OS.get_executable_path()
	var process_id:=OS.create_process(executable,["--path",project_root,"--","--test-map="+filename])
	status_label.text="Testing "+filename+" in game." if process_id>0 else "Could not launch the game test process."

func _new_document() -> void:
	var template:={"format_version":2,"map_type":"Rainforest","map_metadata":{"id":"new_map","display_name":"New Map","layout_type":"outdoor","group":"custom","tags":[]},"origin":[0,0,0],"size":[20,20],"base_terrain_type":"forest_floor","terrain_tiles":[],"entry":[0,0.65,8],"return_warp":[0,0.12,9.5],"arrival_points":{"entry":[0,0.65,8]},"outdoor_connections":[],"tall_grass_species":[],"water_species":[],"water_encounter_chance":0.0,"objects":[],"grass_zones":[],"water_blocks":[],"sand_blocks":[],"rocks":[],"floor_blocks":[],"wall_blocks":[],"furnishings":[],"vines":[],"orchids":[]}
	npc_data.definitions={};npc_data.load_error="";npc_companion_doc=MapDocumentRef.from_text("{}");document=MapDocumentRef.from_text(JSON.stringify(template),"new_map.json");document.dirty=true;undo_stack.clear();redo_stack.clear();identity_by_path.clear();next_identity=1;_refresh_all();status_label.text="New universal outdoor map"

func _load_path(path: String) -> void:
	if path.ends_with("_NPC_Data.json"):status_label.text="Open the owning map JSON.";return
	npc_data.load_for_map(path)
	var companion:String=npc_data.companion_path(path)
	npc_companion_doc=MapDocumentRef.load_file(companion) if FileAccess.file_exists(companion) else MapDocumentRef.from_text("{}",companion)
	document=MapDocumentRef.load_file(path);undo_stack.clear();redo_stack.clear();selected_id="";identity_by_path.clear();next_identity=1
	var repaired:=_normalize_document_walls()
	repaired=_normalize_overlay_attachments() or repaired
	if repaired:document.dirty=true
	_refresh_all()
	if repaired:status_label.text="Opened map and repaired redundant sub-minimum wall anchors. Review and save to persist."

func _refresh_all() -> void:
	if document==null:return
	editor_objects=_extract_objects();canvas.base_terrain_texture_path=_base_terrain_texture_path();canvas.set_document_objects(editor_objects,_map_size());canvas.selected_id=selected_id
	issues=MapValidatorRef.validate(document);issues.append_array(npc_data.issues(document.data,npc_visuals))
	for graph_issue in MapGraphRef.scan(map_directory).issues:
		if String(graph_issue.get("message","")).begins_with("World-space bounds overlap") and String(graph_issue.get("path","")).begins_with(document.path.get_file()+"."):issues.append(graph_issue)
	_refresh_palette_compatibility();_refresh_validation();_refresh_canvas_validation();_refresh_raw();_refresh_metadata();_refresh_inspector();_refresh_graph()
	var document_name:=document.path.get_file()
	if _is_world_index_document(document) and document.data.get("index_metadata") is Dictionary:
		document_name=String(document.data.index_metadata.get("display_name","World Index"))+" (map_index.json)"
	status_label.text=("● " if document.dirty or (trainer_catalog_doc!=null and trainer_catalog_doc.dirty) else "")+document_name+"  ·  "+document.kind+"  ·  %d objects"%editor_objects.size()

func _map_size() -> Vector2:
	var value:Variant=document.data.get("map_size",document.data.get("interior_size",document.data.get("size",[20,20])))
	if value is Array and value.size()>=2:return Vector2(float(value[0]),float(value[1]))
	return Vector2(20,20)

func _map_size_field()->String:
	for field in ["map_size","interior_size","size"]:
		if document.data.get(field) is Array and document.data[field].size()>=2:return field
	return ""

func _extract_objects() -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if not document.parse_error.is_empty():return result
	for field in document.data:
		var name:=String(field);var value:Variant=document.data[field]
		if MapSchemaRef.is_marker_field(name) and value is Array and value.size()>=3:_append_point(result,name,"$."+name,value,-1,"marker")
		elif name=="trees" and value is Array:
			for i in value.size():if value[i] is Array and value[i].size()>=4:_append_point(result,name,"$.trees[%d]"%i,value[i],int(value[i][3]),"tree")
		elif name in MapSchemaRef.POINT_ARRAY_FIELDS and value is Array:
			for i in value.size():
				if value[i] is Array and value[i].size()>=3:_append_point(result,name,"$.%s[%d]"%[name,i],value[i],-1,"point")
				elif name=="children" and value[i] is Dictionary and value[i].get("position") is Array and value[i].position.size()>=3:_append_point(result,name,"$.children[%d].position"%i,value[i].position,-1,"point")
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
	_append_npcs(result)
	_append_linked_context(result)
	_resolve_editor_attachments(result)
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
	if type_id=="wall.fence":
		_append_wall(result,path,value);return
	if entry.is_empty() or not p is Array or p.size()<3:return
	var s:Variant=value.get("size",[1.0,1.0,1.0]);if not s is Array or s.size()<3:s=[1.0,1.0,1.0]
	var is_bridge:=type_id=="structure.bridge"
	var shape:="bridge" if is_bridge else ("building" if type_id.begins_with("building.") or type_id.begins_with("background.citybuilding") else ("rectangle" if String(entry.get("scale_mode",""))=="explicit_size" else "point"))
	var fp:Variant=entry.get("footprint",[0.8,0.8]);if not fp is Array:fp=[float(s[0]),float(s[2])]
	if is_bridge:
		var length:=float(value.get("length",3));var width:=float(value.get("width",1.0))
		fp=[length,width] if String(value.get("orientation","vertical"))=="horizontal" else [width,length]
		s=[float(fp[0]),float(value.get("elevation",1.0)),float(fp[1])]
	var object_label:Variant=entry.get("display_name",type_id)
	if type_id=="npc.opponent":object_label=_trainer_definition(value).get("name",object_label)
	var asset_variant:=-1;var object_texture:=String(entry.get("preview_texture",""))
	if (type_id.begins_with("asset.") or type_id.begins_with("overlay.")) and entry.get("variants",[]) is Array and not entry.get("variants",[]).is_empty():
		asset_variant=int(value.get("variant",0));var serialized_asset:=String(value.get("asset_path",""))
		for candidate:Variant in entry.variants:
			if candidate is Dictionary and (int(candidate.get("value",-1))==asset_variant or String(candidate.get("asset_path",""))==serialized_asset):asset_variant=int(candidate.value);object_texture=String(candidate.preview_texture);break
	var display_height:=float(value.get("height",entry.get("display_height",1.0)))
	if (type_id.begins_with("asset.") or type_id.begins_with("overlay.")) and String(value.get("asset_path","")).begins_with("res://assets/overworld/"):
		var scale_metadata:=AssetCatalogRef.load_metadata(project_root.path_join(String(value.asset_path).trim_prefix("res://")))
		if bool(scale_metadata.get("standardize_scale",false)):
			display_height=float(scale_metadata.get("visual_height",display_height))
			var shared_size:Variant=scale_metadata.get("size",[])
			if shared_size is Array and shared_size.size()>=3:s=shared_size
	var instance_id:=String(value.get("instance_id",""));var editor_id:="placed:"+instance_id if not instance_id.is_empty() else _stable_id(path)
	var editor_object:={"id":editor_id,"instance_id":instance_id,"path":path,"field":"objects","label":object_label,"position":Vector3(float(p[0]),float(p[1]),float(p[2])),"size":Vector3(float(s[0]),float(s[1]),float(s[2])),"size_path":path+".size","shape":shape,"variant":-1,"asset_variant":asset_variant,"texture":object_texture,"display_height":display_height,"footprint":Vector2(float(fp[0]),float(fp[1])),"color":Color("#d4b47a") if shape=="building" else Color("#dce6ee"),"universal_type":type_id,"rotation_degrees":float(value.get("rotation_degrees",0.0)),"is_attached":bool(value.get("is_attached",false)),"host_id":String(value.get("host_id","")),"attachment_order":int(value.get("attachment_order",0))}
	if shape=="building":
		var extension:=float(entry.get("front_depth_extension",0.0));editor_object["display_width"]=float(s[0]) if type_id.begins_with("background.") else float(s[0])*(1.08 if type_id=="building.medical_ward" else 1.15)
		editor_object["footprint"]=Vector2(float(s[0]),float(s[2])+extension);editor_object["footprint_offset"]=Vector2(0,extension*0.5)
		var collision:Variant=entry.get("collision",{})
		if collision is Dictionary and String(collision.get("anchor","center"))=="back":editor_object["footprint_offset"]=Vector2(0,-float(s[2])*0.5)
	result.append(editor_object)
	if not String(entry.get("water_kind","")).is_empty():
		editor_object["water_kind"] = entry.water_kind
		editor_object["render_band"] = entry.render_band
	if not editor_object.has("water_kind") and not type_id.begins_with("overlay.") and String(value.get("asset_path","")).begins_with("res://assets/overworld/"):_append_asset_collision_boxes(result,path,editor_object,String(value.asset_path))

func _append_asset_collision_boxes(result:Array[Dictionary],owner_path:String,owner:Dictionary,asset_path:String)->void:
	var absolute_path:=project_root.path_join(asset_path.trim_prefix("res://"));var metadata:=AssetCatalogRef.load_metadata(absolute_path)
	var boxes:Variant=metadata.get("collision_boxes",[]);if not boxes is Array:return
	for index in boxes.size():
		var box:Variant=boxes[index];if not box is Dictionary:continue
		var offset:Variant=box.get("offset",[]);var box_size:Variant=box.get("size",[])
		if not offset is Array or offset.size()<2 or not box_size is Array or box_size.size()<3:continue
		result.append({"id":_stable_id(owner_path+".asset_collision[%d]"%index),"path":owner_path+".asset_collision[%d]"%index,"field":"asset_collision","label":"Collision Box %d"%(index+1),"position":owner.position+Vector3(float(offset[0]),0,float(offset[1])),"size":Vector3(float(box_size[0]),float(box_size[1]),float(box_size[2])),"shape":"rectangle","variant":-1,"texture":"","footprint":Vector2(float(box_size[0]),float(box_size[2])),"color":Color("#ef566f"),"asset_path":asset_path,"owner_position":owner.position,"collision_index":index})

func _append_wall(result:Array[Dictionary],path:String,value:Dictionary)->void:
	var points:Variant=value.get("points",[])
	if not points is Array or points.size()<1:return
	var anchors:Array[Vector2]=[]
	for point:Variant in points:
		if point is Array and point.size()>=2:anchors.append(Vector2(float(point[0]),float(point[1])))
	if anchors.is_empty():return
	var first:=anchors[0]
	result.append({"id":_stable_id(path),"path":path,"field":"objects","label":"Wall / Fence","position":Vector3(first.x,float(value.get("y",0.5)),first.y),"size":Vector3.ONE,"shape":"wall","variant":-1,"texture":"assets/overworld/wall_horizontal_generic.png","footprint":Vector2.ONE,"color":Color("#dce6ee"),"universal_type":"wall.fence","wall_set":String(value.get("wall_set","generic_wall")),"wall_points":anchors,"wall_segments":value.get("baked_segments",[]),"collision":value.get("baked_collision",[])})

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
	selected_id=id;_refresh_inspector()
	if not id.is_empty():_set_activity(1)
	status_label.text="Selection cleared." if id.is_empty() else "Selected %s."%String(_find_object(id).get("label","object"))

func _on_object_activated(id:String)->void:
	var object:=_find_object(id)
	if object.is_empty():return
	var owner:=String(object.get("source_file",document.path.get_file()))
	var destination:=MapGraphRef.metadata_destination(document.data,String(object.path),map_directory) if owner == document.path.get_file() else {}
	if destination.is_empty(): destination=MapGraphRef.destination_for(owner,String(object.path),map_directory)
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
	_ensure_map_has_warp(String(destination.map))
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
	if object.field=="asset_collision":_write_asset_collision(object,new,object.size);return
	_push_undo();_write_object_position(object,new);_after_edit()

func _on_canvas_objects_moved(moves:Array)->void:
	if moves.is_empty():return
	_push_undo()
	for move in moves:
		var object:=_find_object(String(move.get("id","")));if not object.is_empty():_write_object_position(object,move.get("new",Vector3.ZERO))
	_after_edit()

func _on_canvas_resized(id:String,old:Vector3,new:Vector3)->void:
	var object:=_find_object(id);if object.is_empty():return
	if object.field=="asset_collision":_write_asset_collision(object,object.position,new);return
	if object.field=="terrain_tiles":_resize_terrain_cell(object,new)
	else:_push_undo();_write_object_size(object,new);_after_edit()

func _write_asset_collision(object:Dictionary,position:Vector3,box_size:Vector3)->void:
	var absolute_path:=project_root.path_join(String(object.asset_path).trim_prefix("res://"));var metadata:=AssetCatalogRef.load_metadata(absolute_path);var boxes:Variant=metadata.get("collision_boxes",[])
	var index:=int(object.collision_index)
	if not boxes is Array or index<0 or index>=boxes.size() or not boxes[index] is Dictionary:return
	boxes[index]={"offset":[position.x-object.owner_position.x,position.z-object.owner_position.z],"size":[box_size.x,box_size.y,box_size.z]};metadata["collision_boxes"]=boxes
	if AssetCatalogRef.save_metadata(absolute_path,metadata)==OK:_refresh_all()

func _resize_terrain_cell(object:Dictionary,new_size:Vector3)->void:
	if not document.data.get("terrain_tiles") is Array:return
	_push_undo()
	var width:=maxi(1,roundi(new_size.x));var depth:=maxi(1,roundi(new_size.z));var center:=Vector2i(roundi(object.position.x),roundi(object.position.z))
	var min_x:=center.x-int(floor(float(width-1)*0.5));var min_z:=center.y-int(floor(float(depth-1)*0.5));var cells:Dictionary={}
	for x in range(min_x,min_x+width):
		for z in range(min_z,min_z+depth):cells[Vector2i(x,z)]=true
	for entry_index in range(document.data.terrain_tiles.size()-1,-1,-1):
		var entry:Variant=document.data.terrain_tiles[entry_index];if not entry is Dictionary:continue
		var single:Variant=entry.get("position",null)
		if single is Array and single.size()>=2 and cells.has(Vector2i(roundi(float(single[0])),roundi(float(single[1])))):entry.erase("position")
		if entry.get("positions") is Array:
			for position_index in range(entry.positions.size()-1,-1,-1):
				var position:Variant=entry.positions[position_index]
				if position is Array and position.size()>=2 and cells.has(Vector2i(roundi(float(position[0])),roundi(float(position[1])))):entry.positions.remove_at(position_index)
		if not entry.has("position") and (not entry.get("positions") is Array or entry.positions.is_empty()):document.data.terrain_tiles.remove_at(entry_index)
	var positions:Array=[]
	for cell:Vector2i in cells:positions.append([cell.x,cell.y])
	document.data.terrain_tiles.append({"terrain_type":String(object.label),"positions":positions})
	document.dirty=true;_after_edit()

func _on_map_resized(_old:Vector2,new:Vector2)->void:
	var field:=_map_size_field();if field.is_empty():return
	_push_undo();var value:Array=document.data[field].duplicate();value[0]=new.x;value[1]=new.y;document.set_value("$."+field,value);_after_edit()

func _wall_anchor_requested(point:Vector2)->void:
	if document==null:return
	var rejection_message:=""
	# Wall anchors always use the wall grid. A free diagonal mouse gesture is
	# stored as a deterministic three-run orthogonal path, never as a diagonal.
	point=Vector2(snappedf(point.x,grid_spin.value),snappedf(point.y,grid_spin.value))
	if active_wall_id.is_empty():
		_push_undo()
		if not document.data.get("objects") is Array:document.data["objects"]=[]
		document.data.objects.append({"type":"wall.fence","wall_set":"generic_wall","segment_length":WallGeometryRef.MIN_FILLER_SPAN,"collision_thickness":0.22,"collision_offset":0.0,"points":[[point.x,point.y]]})
		active_wall_id=_stable_id("$.objects[%d]"%(document.data.objects.size()-1))
	else:
		var object:=_find_object(active_wall_id);var record:Variant=_get_path(String(object.get("path","")))
		if record is Dictionary:
			var points:Array=record.get("points",[]);var origin:=Vector2(float(points[-1][0]),float(points[-1][1]))
			point=origin+Vector2(snappedf(point.x-origin.x,WallGeometryRef.MIN_FILLER_SPAN),snappedf(point.y-origin.y,WallGeometryRef.MIN_FILLER_SPAN))
			var route:=_orthogonal_wall_route(origin,point,float(grid_spin.value))
			if route.is_empty():
				rejection_message="Wall segment rejected: every horizontal/vertical run must be at least %.1f map units."%WallGeometryRef.MIN_FILLER_SPAN
			else:
				for route_point in route:points.append([route_point.x,route_point.y])
				record["points"]=points;_normalize_wall_record(record);document.dirty=true
	_after_edit()
	if not active_wall_id.is_empty():canvas.select_object(active_wall_id)
	if not rejection_message.is_empty():status_label.text=rejection_message

func _wall_finished()->void:
	var object:=_find_object(active_wall_id)
	if not object.is_empty():
		var record:Variant=_get_path(String(object.path))
		if record is Dictionary and (not record.get("points") is Array or record.points.size()<2):
			document.data.objects.remove_at(document.data.objects.find(record));document.dirty=true;_after_edit()
	active_wall_id="";canvas.wall_tool_active=false
	if selected_palette_entry=="wall.generic":_clear_palette_selection()
	status_label.text="Wall finished. Select it to drag anchors or delete it."

func _wall_anchor_moved(id:String,index:int,point:Vector2)->void:
	var object:=_find_object(id);if object.is_empty():return
	var record:Variant=_get_path(String(object.path));if not record is Dictionary:return
	var points:Array=record.get("points",[]);if index<0 or index>=points.size():return
	point=_snap_wall_anchor(points,index,point)
	var lattice_reference:=Vector2(float(points[1][0]),float(points[1][1])) if index==0 and points.size()>1 else Vector2(float(points[0][0]),float(points[0][1]))
	point=lattice_reference+Vector2(snappedf(point.x-lattice_reference.x,WallGeometryRef.MIN_FILLER_SPAN),snappedf(point.y-lattice_reference.y,WallGeometryRef.MIN_FILLER_SPAN))
	var original_points:=points.duplicate(true);var original_invalid_count:=WallGeometryRef.invalid_segment_count(original_points)
	_push_undo();points[index]=[point.x,point.y];record["points"]=points
	var normalization:=_normalize_wall_record(record)
	var remaining_invalid_count:=WallGeometryRef.invalid_segment_count(record.get("points",[]))
	if not bool(normalization.valid) and remaining_invalid_count>=original_invalid_count:
		record["points"]=original_points;_bake_wall(record);undo_stack.pop_back();_after_edit();status_label.text="Anchor move rejected: it must remove at least one invalid short wall run without creating another.";return
	document.dirty=true;_after_edit()
	if remaining_invalid_count>0:status_label.text="Anchor repaired. %d invalid wall run(s) remain."%remaining_invalid_count

func _wall_anchors_moved(anchor_keys:Array,delta:Vector2)->void:
	if anchor_keys.is_empty() or delta.length_squared()<0.000001:return
	_push_undo();var grouped:Dictionary={}
	for key in anchor_keys:
		var parts:=String(key).split(":");if parts.size()!=2:continue
		if not grouped.has(parts[0]):grouped[parts[0]]=[]
		grouped[parts[0]].append(int(parts[1]))
	for id in grouped:
		var object:=_find_object(String(id));var record:Variant=_get_path(String(object.get("path","")));if not record is Dictionary:continue
		var points:Array=record.get("points",[])
		for index in grouped[id]:
			if index>=0 and index<points.size():points[index]=[float(points[index][0])+delta.x,float(points[index][1])+delta.y]
		record["points"]=points;_normalize_wall_record(record)
	document.dirty=true;_after_edit()

func _snap_wall_point(origin:Vector2,target:Vector2)->Vector2:
	var delta:=target-origin
	return Vector2(target.x,origin.y) if absf(delta.x)>=absf(delta.y) else Vector2(origin.x,target.y)

func _orthogonal_wall_route(origin:Vector2,target:Vector2,grid_step:float)->Array[Vector2]:
	var route:Array[Vector2]=[];var delta:=target-origin
	if delta.length_squared()<0.0001:return route
	if is_zero_approx(delta.x) or is_zero_approx(delta.y):
		if WallGeometryRef.segment_is_valid(origin,target):route.append(target)
		return route
	if grid_step<=0.0:return route
	var horizontal_first:=absf(delta.x)>=absf(delta.y)
	var dominant_distance:=absf(delta.x) if horizontal_first else absf(delta.y)
	var dominant_steps:=roundi(dominant_distance/WallGeometryRef.MIN_FILLER_SPAN)
	if dominant_steps<2 or not is_equal_approx(dominant_distance,float(dominant_steps)*WallGeometryRef.MIN_FILLER_SPAN):return route
	var first_steps:=floori(float(dominant_steps)*0.5)
	if horizontal_first:
		var split_x:=origin.x+signf(delta.x)*float(first_steps)*WallGeometryRef.MIN_FILLER_SPAN
		route.assign([Vector2(split_x,origin.y),Vector2(split_x,target.y),target])
	else:
		var split_y:=origin.y+signf(delta.y)*float(first_steps)*WallGeometryRef.MIN_FILLER_SPAN
		route.assign([Vector2(origin.x,split_y),Vector2(target.x,split_y),target])
	var previous:=origin
	for route_point in route:
		if not WallGeometryRef.segment_is_valid(previous,route_point):route.clear();return route
		previous=route_point
	return route

func _snap_wall_anchor(points:Array,index:int,target:Vector2)->Vector2:
	if points.size()<2:return target
	if index==0:return _snap_wall_point(Vector2(float(points[1][0]),float(points[1][1])),target)
	if index==points.size()-1:return _snap_wall_point(Vector2(float(points[index-1][0]),float(points[index-1][1])),target)
	var previous:=Vector2(float(points[index-1][0]),float(points[index-1][1]))
	var following:=Vector2(float(points[index+1][0]),float(points[index+1][1]))
	var candidates:Array[Vector2]=[Vector2(previous.x,following.y),Vector2(following.x,previous.y)]
	if is_equal_approx(previous.x,following.x):candidates.append(Vector2(previous.x,target.y))
	if is_equal_approx(previous.y,following.y):candidates.append(Vector2(target.x,previous.y))
	var best:=candidates[0]
	for candidate in candidates:
		if candidate.distance_squared_to(target)<best.distance_squared_to(target):best=candidate
	return best

func _bake_wall(record:Dictionary)->void:
	var points:Array=record.get("points",[]);var segments:Array=[];var collision:Array=[]
	for i in range(1,points.size()):
		var a:=Vector2(float(points[i-1][0]),float(points[i-1][1]));var b:=Vector2(float(points[i][0]),float(points[i][1]));var delta:=b-a
		if delta.length_squared()<0.0001:continue
		if not is_zero_approx(delta.x) and not is_zero_approx(delta.y):continue
		var direction:="horizontal" if is_zero_approx(delta.y) else "vertical"
		segments.append({"from":[a.x,a.y],"to":[b.x,b.y],"direction":direction,"length":delta.length()})
		collision.append({"from":[a.x,a.y],"to":[b.x,b.y],"thickness":float(record.get("collision_thickness",0.22)),"offset":float(record.get("collision_offset",0.0))})
	record["baked_segments"]=segments;record["baked_collision"]=collision

func _normalize_wall_record(record:Dictionary)->Dictionary:
	var result:=WallGeometryRef.normalize_points(record.get("points",[]))
	var changed:=bool(result.changed) or not is_equal_approx(float(record.get("segment_length",0.0)),WallGeometryRef.MIN_FILLER_SPAN)
	var old_segments:Variant=record.get("baked_segments",null);var old_collision:Variant=record.get("baked_collision",null)
	record["segment_length"]=WallGeometryRef.MIN_FILLER_SPAN
	if bool(result.changed):record["points"]=result.points
	_bake_wall(record)
	changed=changed or old_segments!=record.baked_segments or old_collision!=record.baked_collision
	return {"changed":changed,"valid":result.valid}

func _normalize_document_walls()->bool:
	if document==null or not document.data.get("objects") is Array:return false
	var changed:=false
	for value:Variant in document.data.objects:
		if value is Dictionary and String(value.get("type",""))=="wall.fence" and value.get("points") is Array and value.points.size()>=2:
			changed=bool(_normalize_wall_record(value).changed) or changed
	return changed

func _new_instance_id()->String:
	var used:Dictionary={}
	for record:Variant in document.data.get("objects",[]):
		if record is Dictionary:used[String(record.get("instance_id",""))]=true
	var candidate:="placed-%d-%d"%[Time.get_unix_time_from_system(),randi()]
	while used.has(candidate):candidate="placed-%d-%d"%[Time.get_unix_time_from_system(),randi()]
	return candidate

func _valid_attachment_host_record(record:Dictionary)->bool:
	var type_id:=String(record.get("type",""))
	return not String(record.get("instance_id","")).is_empty() and not type_id.begins_with("overlay.") and not type_id.begins_with("npc.") and type_id not in ["wall.fence","structure.bridge","block.water","block.sand","block.rock"]

func _normalize_overlay_attachments()->bool:
	var objects:Variant=document.data.get("objects",[])
	if not objects is Array:return false
	var hosts:Dictionary={}
	for record:Variant in objects:
		if record is Dictionary and _valid_attachment_host_record(record):hosts[String(record.instance_id)]=record
	var changed:=false
	for record:Variant in objects:
		if not record is Dictionary or not String(record.get("type","")).begins_with("overlay.") or not bool(record.get("is_attached",false)):continue
		if not hosts.has(String(record.get("host_id",""))):
			record["is_attached"]=false;record.erase("host_id");record.erase("local_position");record.erase("attachment_order");changed=true
	return changed

func _resolve_editor_attachments(result:Array[Dictionary])->void:
	var hosts:Dictionary={}
	for object in result:
		if _is_valid_attachment_host(object):hosts[String(object.instance_id)]=object
	for object in result:
		if not bool(object.get("is_attached",false)):continue
		var host:Dictionary=hosts.get(String(object.get("host_id","")),{})
		if host.is_empty():continue
		var source:Variant=_get_path(String(object.path));var local:Variant=source.get("local_position",[]) if source is Dictionary else []
		if local is Array and local.size()>=2:
			object.position=host.position+Vector3(float(local[0]),0,float(local[1]));object["sort_depth"]=host.position.z+float(host.get("sort_offset_y",0.0));object["host_label"]=host.label

func _is_valid_attachment_host(object:Dictionary)->bool:
	return String(object.get("field",""))=="objects" and not String(object.get("instance_id","")).is_empty() and not String(object.get("universal_type","")).begins_with("overlay.") and not String(object.get("universal_type","")).begins_with("npc.") and String(object.get("shape","")) not in ["wall","bridge"]

func _host_by_instance_id(instance_id:String)->Dictionary:
	for object in editor_objects:
		if String(object.get("instance_id",""))==instance_id and _is_valid_attachment_host(object):return object
	return {}

func _sync_host_attachments(host_id:String,host_position:Vector3)->void:
	if host_id.is_empty():return
	for record:Variant in document.data.get("objects",[]):
		if record is Dictionary and bool(record.get("is_attached",false)) and String(record.get("host_id",""))==host_id:
			var local:Variant=record.get("local_position",[0,0])
			if local is Array and local.size()>=2:record["position"]=[host_position.x+float(local[0]),float(record.get("position",[0,host_position.y,0])[1]),host_position.z+float(local[1])]

func _write_object_position(object:Dictionary,value:Vector3)->void:
	var path:=String(object.path)
	if object.field=="objects":
		document.set_value(path+".position",[value.x,value.y,value.z])
		var record:Variant=_get_path(path)
		if record is Dictionary and bool(record.get("is_attached",false)):
			var host:=_host_by_instance_id(String(record.get("host_id","")))
			if not host.is_empty():record["local_position"]=[value.x-host.position.x,value.z-host.position.z]
		elif record is Dictionary:_sync_host_attachments(String(record.get("instance_id","")),value)
	elif object.field in ["grass_zones","wild_zone"]:
		document.set_value(path+".position",[value.x,value.y,value.z])
	elif object.field=="furnishings":document.set_value(path+".position",[value.x,value.y,value.z])
	elif object.field in ["trainers","npcs"]:document.set_value(path+".position",[value.x,value.y,value.z])
	elif object.field=="terrain_tiles":document.set_value(path,[roundi(value.x),roundi(value.z)])
	elif object.field=="children" and path.ends_with(".position"):document.set_value(path,[value.x,value.y,value.z])
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

func _base_terrain_texture_path() -> String:
	var terrain_type:=String(document.data.get("base_terrain_type","forest_floor"))
	var entry:Dictionary=catalog.by_id.get("terrain."+terrain_type,{})
	return String(entry.get("preview_texture","assets/overworld/tile_grass_generic.png"))

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
	document.dirty=true;editor_objects=_extract_objects();canvas.set_document_objects(editor_objects,_map_size());issues=MapValidatorRef.validate(document);issues.append_array(npc_data.issues(document.data,npc_visuals));_refresh_validation();_refresh_canvas_validation();_refresh_raw()

func _terrain_stroke_finished()->void:
	if terrain_stroke_changed:_refresh_all();status_label.text="Terrain stroke applied. Undo is available."

func _push_undo()->void:
	undo_stack.append(_editor_snapshot());if undo_stack.size()>100:undo_stack.pop_front();redo_stack.clear()

func _undo()->void:
	if canvas!=null and canvas.collision_polygon_active and not polygon_undo_stack.is_empty():_polygon_undo();return
	if undo_stack.is_empty() or document==null:return
	redo_stack.append(_editor_snapshot());_restore_snapshot(undo_stack.pop_back())

func _redo()->void:
	if canvas!=null and canvas.collision_polygon_active and not polygon_redo_stack.is_empty():_polygon_redo();return
	if redo_stack.is_empty() or document==null:return
	undo_stack.append(_editor_snapshot());_restore_snapshot(redo_stack.pop_back())

func _restore_snapshot(text:String)->void:
	var parsed:Variant=JSON.parse_string(text)
	var map_text:=text
	if parsed is Dictionary and parsed.get("__npc_editor_snapshot",false)==true:
		map_text=String(parsed.map)
		npc_data.definitions=parsed.definitions.duplicate(true)
	var path:=document.path;var kind:=document.kind;document=MapDocumentRef.from_text(map_text,path);document.kind=kind;document.dirty=true;_refresh_all()

func _delete_selected()->void:
	var selected:=canvas.selected_object_ids()
	if selected.size()>1:
		_push_undo();var targets:Array[Dictionary]=[]
		for id in selected:
			var candidate:=_find_object(id)
			if not candidate.is_empty() and not bool(candidate.get("locked",false)):targets.append(candidate)
		targets.sort_custom(func(a,b):
			var a_parts:=_array_parent_and_index(String(a.path));var b_parts:=_array_parent_and_index(String(b.path))
			return int(a_parts.get("index",-1))>int(b_parts.get("index",-1)) if String(a_parts.get("path",""))==String(b_parts.get("path","")) else String(a_parts.get("path",""))>String(b_parts.get("path","")))
		var removed:=0
		for candidate in targets:
			_detach_for_deleted_host(candidate)
			var parts:=_array_parent_and_index(String(candidate.path));var array:Variant=_get_path(String(parts.get("path","")))
			if not parts.is_empty() and array is Array and int(parts.index)<array.size():array.remove_at(int(parts.index));removed+=1
		if removed==0:undo_stack.pop_back();return
		selected_id="";document.dirty=true;_after_edit();status_label.text="Deleted %d selected objects. Undo is available."%removed;return
	var object:=_find_object(selected_id)
	if object.is_empty():status_label.text="Select an object before deleting.";return
	if bool(object.get("locked",false)):status_label.text="Linked objects are edited in %s. Double-click to open it."%String(object.source_file);return
	if object.field=="terrain_tiles":_delete_terrain_cell(object);return
	if String(object.field).begins_with("warp_"):
		_delete_authored_warp(object);return
	var parts:=_array_parent_and_index(String(object.path))
	if parts.is_empty():status_label.text="%s is a required singular map field and cannot be deleted; move it or edit its properties instead."%String(object.field);return
	var array:Variant=_get_path(parts.path)
	if not array is Array:status_label.text="Could not locate the selected object array.";return
	_push_undo();_detach_for_deleted_host(object);array.remove_at(parts.index);_shift_array_identities(parts.path,parts.index,-1,true);document.dirty=true;selected_id="";_after_edit();status_label.text="Deleted object. Attached overlays were safely detached. Undo is available."

func _detach_for_deleted_host(object:Dictionary)->void:
	if String(object.get("field",""))=="npcs":npc_data.definitions.erase(str(int(object.npc_id)))
	var host_id:=String(object.get("instance_id",""));if host_id.is_empty():return
	for record:Variant in document.data.get("objects",[]):
		if record is Dictionary and bool(record.get("is_attached",false)) and String(record.get("host_id",""))==host_id:
			record["is_attached"]=false;record.erase("host_id");record.erase("local_position");record.erase("attachment_order")

func _add_warp()->void:
	if document == null: return
	var used_ids := {}; var highest_id := 0
	for field in MapGraphRef.warp_fields(document.data):
		var warp_id := MapGraphRef.warp_id_for(document.data, field); used_ids[warp_id] = true; highest_id = maxi(highest_id, warp_id)
	var new_id := highest_id + 1
	while used_ids.has(new_id): new_id += 1
	var field := "warp_%d" % new_id
	while document.data.has(field): field += "_new"
	_push_undo()
	document.data[field] = [0.0, 0.12, 0.0]
	if not document.data.get("warp_metadata") is Dictionary: document.data["warp_metadata"] = {}
	document.data.warp_metadata[field] = {"id":new_id,"entrance_map":"","entrance_map_warp_id":1}
	document.dirty = true; _after_edit()
	for object in editor_objects:
		if String(object.path) == "$." + field: canvas.select_object(String(object.id)); break
	status_label.text = "Added warp ID %d at the origin. Set its position and entrance map in the Inspector." % new_id

func _delete_authored_warp(object:Dictionary)->void:
	var field := String(object.field)
	_push_undo(); document.data.erase(field)
	if document.data.get("warp_metadata") is Dictionary: document.data.warp_metadata.erase(field)
	if document.data.get("outdoor_connections") is Array:
		for index in range(document.data.outdoor_connections.size() - 1, -1, -1):
			var connection: Variant = document.data.outdoor_connections[index]
			if connection is Dictionary and String(connection.get("warp", "")) == field: document.data.outdoor_connections.remove_at(index)
	document.dirty = true; selected_id = ""; _after_edit(); status_label.text = "Deleted authored warp. Undo is available."

func _delete_terrain_cell(object:Dictionary)->void:
	if not document.data.get("terrain_tiles") is Array:return
	var cell:=Vector2i(roundi(object.position.x),roundi(object.position.z));var removed:=false
	_push_undo()
	for entry_index in range(document.data.terrain_tiles.size()-1,-1,-1):
		var entry:Variant=document.data.terrain_tiles[entry_index];if not entry is Dictionary:continue
		var single:Variant=entry.get("position",null)
		if single is Array and single.size()>=2 and Vector2i(roundi(float(single[0])),roundi(float(single[1])))==cell:entry.erase("position");removed=true
		if entry.get("positions") is Array:
			for position_index in range(entry.positions.size()-1,-1,-1):
				var position:Variant=entry.positions[position_index]
				if position is Array and position.size()>=2 and Vector2i(roundi(float(position[0])),roundi(float(position[1])))==cell:entry.positions.remove_at(position_index);removed=true
		if not entry.has("position") and (not entry.get("positions") is Array or entry.positions.is_empty()):document.data.terrain_tiles.remove_at(entry_index)
	if not removed:undo_stack.pop_back();status_label.text="Could not locate the selected terrain cell.";return
	document.dirty=true;selected_id="";_after_edit();status_label.text="Deleted terrain cell. Undo is available."

func _duplicate_selected()->void:
	var selected:=canvas.selected_object_ids()
	if selected.size()>1:
		_push_undo();var copies_by_parent:Dictionary={};var copied:=0;var host_id_remap:Dictionary={};var selected_sources:Array=[]
		for id in selected:
			var candidate:=_find_object(id);if candidate.is_empty():continue
			var source:Variant=_get_path(String(candidate.path));if source is Dictionary:
				selected_sources.append(source)
				var old_id:=String(source.get("instance_id",""));if not old_id.is_empty() and not String(source.get("type","")).begins_with("overlay."):host_id_remap[old_id]=_new_instance_id()
		for id in selected:
			var candidate:=_find_object(id);if candidate.is_empty() or bool(candidate.get("locked",false)):continue
			var parts:=_array_parent_and_index(String(candidate.path));if parts.is_empty():continue
			var source:Variant=_get_path(String(candidate.path));if source==null:continue
			if not copies_by_parent.has(parts.path):copies_by_parent[parts.path]=[]
			var copy:Variant=source.duplicate(true)
			if copy is Array and copy.size()>=3:copy[0]=float(copy[0])+grid_spin.value;copy[2]=float(copy[2])+grid_spin.value
			elif copy is Dictionary and copy.get("position") is Array:
				copy.position[0]=float(copy.position[0])+grid_spin.value;copy.position[2]=float(copy.position[2])+grid_spin.value
				var old_id:=String(copy.get("instance_id",""));if host_id_remap.has(old_id):copy["instance_id"]=host_id_remap[old_id]
				var old_host:=String(copy.get("host_id",""));if host_id_remap.has(old_host):copy["host_id"]=host_id_remap[old_host]
			if String(candidate.field)=="npcs":_assign_npc_copy(copy)
			copies_by_parent[parts.path].append(copy);copied+=1
		for old_host_id:String in host_id_remap:
			for attached:Variant in document.data.get("objects",[]):
				if attached is Dictionary and attached not in selected_sources and bool(attached.get("is_attached",false)) and String(attached.get("host_id",""))==old_host_id:
					var attached_copy:Dictionary=attached.duplicate(true);attached_copy["host_id"]=host_id_remap[old_host_id];attached_copy.position[0]=float(attached_copy.position[0])+grid_spin.value;attached_copy.position[2]=float(attached_copy.position[2])+grid_spin.value
					if not copies_by_parent.has("$.objects"):copies_by_parent["$.objects"]=[]
					copies_by_parent["$.objects"].append(attached_copy);copied+=1
		for parent in copies_by_parent:
			var array:Variant=_get_path(String(parent));if array is Array:for copy in copies_by_parent[parent]:array.append(copy)
		if copied==0:undo_stack.pop_back();return
		document.dirty=true;_after_edit();status_label.text="Duplicated %d selected objects. Undo is available."%copied;return
	var object:=_find_object(selected_id);if object.is_empty():return
	if bool(object.get("locked",false)):status_label.text="Linked objects cannot be duplicated from this map. Double-click to open %s."%String(object.source_file);return
	var parts:=_array_parent_and_index(String(object.path));if parts.is_empty():return
	var array:Variant=_get_path(parts.path);if not array is Array:return
	if parts.index<0 or parts.index>=array.size() or array[parts.index]==null:return
	_push_undo();var copy:Variant=array[parts.index].duplicate(true);if copy is Array and copy.size()>=3:copy[0]=float(copy[0])+grid_spin.value;copy[2]=float(copy[2])+grid_spin.value
	elif copy is Dictionary and copy.get("position") is Array:
		copy.position[0]=float(copy.position[0])+grid_spin.value;copy.position[2]=float(copy.position[2])+grid_spin.value
		var old_host_id:=String(copy.get("instance_id",""));var new_host_id:=""
		if not old_host_id.is_empty():new_host_id=_new_instance_id();copy["instance_id"]=new_host_id
		if bool(copy.get("is_attached",false)):copy["instance_id"]=_new_instance_id() if copy.has("instance_id") else copy.get("instance_id","")
		if not old_host_id.is_empty() and not String(copy.get("type","")).begins_with("overlay."):
			for attached:Variant in document.data.get("objects",[]):
				if attached is Dictionary and bool(attached.get("is_attached",false)) and String(attached.get("host_id",""))==old_host_id:
					var attached_copy:Dictionary=attached.duplicate(true);attached_copy["host_id"]=new_host_id;attached_copy["position"]=[float(attached_copy.position[0])+grid_spin.value,float(attached_copy.position[1]),float(attached_copy.position[2])+grid_spin.value];document.data.objects.append(attached_copy)
	if String(object.field)=="npcs":_assign_npc_copy(copy)
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
	canvas.wall_tool_active=selected_palette_entry=="wall.generic";active_wall_id=""
	if canvas.wall_tool_active: palette_help.text="Click to place anchors. Diagonal gestures become three horizontal/vertical runs; every run must span at least %.1f map units. Right-click or Esc finishes."%WallGeometryRef.MIN_FILLER_SPAN;status_label.text="Wall tool active.";return
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
	var type_id:=String(entry.get("type_id",""))
	if type_id=="area.grass":return "grass_zones"
	if type_id.begins_with("terrain."):return "terrain_tiles"
	if selected_palette_entry=="wall.generic":return "objects"
	if _universal_type(entry).begins_with("building.") or _universal_type(entry).begins_with("background.") or _universal_type(entry).begins_with("npc."):return "objects"
	for field in entry.get("serialization",{}).get("fields",[]):
		if document.data.has(String(field)) and document.data[String(field)] is Array:return String(field)
	if not _universal_type(entry).is_empty():return "objects"
	return ""

func _universal_type(entry:Dictionary)->String:
	var type_id:=String(entry.get("type_id",""))
	return type_id if type_id.begins_with("asset.") or type_id.begins_with("overlay.") or type_id.begins_with("tile.") or type_id.begins_with("building.") or type_id.begins_with("tree.") or type_id.begins_with("flower.") or type_id.begins_with("background.citybuilding") or type_id=="cave.vine" or type_id in ["structure.bridge","block.water","block.sand","block.rock","npc.opponent","npc.generic","wall.generic"] else ""

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
	if canvas.wall_tool_active:return
	if palette_dragging and event is InputEventMouseMotion:
		palette_drag_preview.global_position = event.global_position + Vector2(16,16)
		var over_canvas := canvas.get_global_rect().has_point(event.global_position)
		palette_drag_preview.modulate = Color.WHITE if over_canvas else Color(1,1,1,0.55)
		canvas.queue_redraw()
	elif palette_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var drop_global: Vector2 = event.global_position
		var over_canvas := canvas.get_global_rect().has_point(drop_global)
		var drop_type:=palette_drag_entry
		_finish_palette_drag()
		if over_canvas:
			var local_screen: Vector2 = drop_global - canvas.global_position
			var world_xz: Vector2 = canvas.screen_to_world(local_screen)
			_add_palette_object_at(world_xz,drop_type)
		get_viewport().set_input_as_handled()
	elif not palette_dragging and not selected_palette_entry.is_empty() and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed and canvas.get_global_rect().has_point(event.global_position):
			palette_painting=true;palette_paint_last_key="";_push_undo()
			_stamp_palette_at_global(event.global_position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and palette_painting:
			palette_painting=false;palette_paint_last_key="";_clear_palette_selection();get_viewport().set_input_as_handled()
	elif not palette_dragging and palette_painting and event is InputEventMouseMotion and (event.button_mask&MOUSE_BUTTON_MASK_LEFT)!=0:
		_stamp_palette_at_global(event.global_position)
		get_viewport().set_input_as_handled()

func _stamp_palette_at_global(global_position:Vector2)->void:
	if not canvas.get_global_rect().has_point(global_position):return
	var world_xz:=canvas.screen_to_world(global_position-canvas.global_position)
	var x:=snappedf(world_xz.x,grid_spin.value) if snap_check.button_pressed else world_xz.x
	var z:=snappedf(world_xz.y,grid_spin.value) if snap_check.button_pressed else world_xz.y
	var stamp_key:="%.4f,%.4f"%[x,z]
	if stamp_key==palette_paint_last_key:return
	palette_paint_last_key=stamp_key
	_add_palette_object_at(Vector2(x,z),selected_palette_entry,false,false)

func _start_palette_drag(type_id: String) -> void:
	if type_id.is_empty(): return
	var entry:Dictionary=catalog.by_id.get(type_id,{})
	if _compatible_array_field(entry).is_empty():status_label.text=_incompatible_palette_reason(entry);return
	palette_dragging=true;palette_drag_entry=type_id
	palette_drag_preview_label.text="  %s\n  Drop onto map  " % String(entry.get("display_name",type_id))
	palette_drag_preview.reset_size();palette_drag_preview.visible=true
	palette_drag_preview.global_position=get_viewport().get_mouse_position()+Vector2(16,16)

func _finish_palette_drag() -> void:
	palette_dragging=false;palette_drag_preview.visible=false;palette_drag_entry="";palette_press_entry="";_clear_palette_selection();canvas.queue_redraw()

func _clear_palette_selection()->void:
	selected_palette_entry=""
	palette.deselect_all()

func _add_palette_object()->void:
	_add_palette_object_at(Vector2.ZERO)

func _add_palette_object_at(world_xz: Vector2,type_id:String="",record_undo:bool=true,select_created:bool=true)->void:
	var placement_type:=selected_palette_entry if type_id.is_empty() else type_id
	if placement_type.is_empty() or document==null:return
	var entry:Dictionary=catalog.by_id.get(placement_type,{});var serialization:Dictionary=entry.get("serialization",{});var fields:Array=serialization.get("fields",[]);var chosen:=""
	var palette_choices:Variant=entry.get("palette_choices",[])
	if palette_choices is Array and not palette_choices.is_empty():
		placement_type=String(palette_choices.pick_random());entry=catalog.by_id.get(placement_type,{});serialization=entry.get("serialization",{});fields=serialization.get("fields",[])
	if placement_type=="area.grass":
		chosen="grass_zones"
		if not document.data.get(chosen) is Array:document.data[chosen]=[]
	elif placement_type.begins_with("terrain."):
		chosen="terrain_tiles"
		if not document.data.get(chosen) is Array:document.data[chosen]=[]
	if not placement_type.begins_with("building.") and not placement_type.begins_with("background.") and not placement_type.begins_with("npc."):
		if chosen.is_empty():
			for f in fields:if document.data.has(String(f)) and document.data[String(f)] is Array:chosen=String(f);break
	if chosen.is_empty() and not _universal_type(entry).is_empty():
		chosen="objects"
		if not document.data.get(chosen) is Array:document.data[chosen]=[]
	if chosen.is_empty():status_label.text="This object type has no compatible array in the current schema.";return
	var x := world_xz.x;var z := world_xz.y
	if snap_check.button_pressed:x=snappedf(x,grid_spin.value);z=snappedf(z,grid_spin.value)
	if record_undo:_push_undo()
	var y:=float(entry.get("default_y",0.0));var kind:=String(serialization.get("kind",""));var shape:=String(serialization.get("shape",""));var value:Variant
	if chosen=="objects":
		var default_size:Variant=entry.get("default_size",[10.0,6.0,4.0] if placement_type.begins_with("background.") else ([5.0,3.0,4.0] if placement_type.begins_with("building.") else ([2.0,0.3,2.0] if String(entry.get("scale_mode",""))=="explicit_size" else [1.0,1.0,1.0])))
		value={"type":placement_type,"position":[x,y,z],"size":default_size}
		if entry.has("asset_path"):
			var asset_variants:Variant=entry.get("variants",[])
			if asset_variants is Array and not asset_variants.is_empty():value["variant"]=int(asset_variants[0].get("value",0));value["asset_path"]=String(asset_variants[0].get("asset_path",entry.get("asset_path","")))
			else:value["asset_path"]=String(entry.get("asset_path",""))
		if placement_type=="structure.bridge":value={"type":placement_type,"position":[x,y,z],"orientation":"vertical","length":5,"width":1.0,"elevation":1.0,"entrance_length":1.0,"traversal_layer":1}
		elif placement_type=="npc.generic":value.merge({"speaker":"NPC","dialogue":["Hello, traveler!"]})
		elif placement_type=="npc.opponent":
			var trainer_id:=_create_trainer_definition()
			value["trainer_id"]=trainer_id
		elif entry.has("display_height"):value["height"]=float(entry.display_height)
		if bool(entry.get("supports_rotation",false)):value["rotation_degrees"]=0.0
	elif kind=="zone":value={"position":[x,y,z],"size":[3,0.25,3],"encounter_chance":0.2}
	elif kind=="furnishing":value={"type":String(serialization.get("prop_type","")),"position":[x,y,z],"height":float(entry.get("display_height",1.0))}
	elif kind=="terrain_tile":value={"terrain_type":String(serialization.get("terrain_type","")),"position":[roundi(x),roundi(z)]}
	elif kind=="block6":value=[x,y,z,2,0.3,2]
	elif shape.contains("variant"):value=[x,y,z,0 if placement_type=="tree.main" else 1]
	else:value=[x,y,z]
	var new_index: int=document.data[chosen].size();document.data[chosen].append(value);document.dirty=true
	var new_path := "$.%s[%d]" % [chosen,new_index]
	_after_edit()
	if select_created:
		for object in editor_objects:
			if String(object.path)==new_path:canvas.select_object(String(object.id));break

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_ESCAPE and canvas.collision_polygon_active:
		_finish_polygon_collision_editor();get_viewport().set_input_as_handled();return
	if event.ctrl_pressed and event.keycode==KEY_Z:
		if event.shift_pressed:_redo()
		else:_undo()
		get_viewport().set_input_as_handled();return
	if event.ctrl_pressed and event.keycode==KEY_Y:
		_redo();get_viewport().set_input_as_handled();return
	if event.keycode == KEY_DELETE and canvas.has_focus() and canvas.collision_polygon_active:
		if canvas.delete_collision_polygon_vertex():get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_DELETE and canvas.has_focus():
		_delete_selected();get_viewport().set_input_as_handled()
	if event.keycode==KEY_ESCAPE and canvas.wall_tool_active:
		_wall_finished();get_viewport().set_input_as_handled()
	elif event.keycode==KEY_ESCAPE and canvas.terrain_brush_mode!="select":
		canvas.terrain_brush_mode="select";canvas.queue_redraw();status_label.text="Selection tool active.";get_viewport().set_input_as_handled()
	elif event.keycode==KEY_ESCAPE and not selected_palette_entry.is_empty():
		selected_palette_entry="";palette.deselect_all();status_label.text="Object palette brush cleared.";get_viewport().set_input_as_handled()

func _refresh_inspector()->void:
	for child in inspector.get_children():
		inspector.remove_child(child);child.queue_free()
	var object:=_find_object(selected_id)
	if object.is_empty():
		var heading:=Label.new();heading.text="INSPECTOR";heading.add_theme_font_size_override("font_size",18);inspector.add_child(heading)
		var empty:=Label.new();empty.text="No object selected.\n\nSelect an object on the map\nto edit its properties.";empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(empty);return
	var inspector_heading:=Label.new();inspector_heading.text="INSPECTOR";inspector_heading.add_theme_font_size_override("font_size",18);inspector.add_child(inspector_heading)
	var title:=Label.new();title.text=String(object.field)+"\n"+String(object.path);title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(title)
	if bool(object.get("linked",false)):
		var linked_note:=Label.new();linked_note.text="Read-only linked object from %s. Double-click it to open the owning map."%String(object.source_file);linked_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(linked_note);return
	var is_warp := String(object.get("role", "")) == "marker" and MapSchemaRef.is_marker_field(String(object.field)) and (String(object.field).contains("warp") or String(object.field) in ["door", "exit_door"])
	var is_warp_visual := _is_universal_warp_visual(object)
	var destination:=MapGraphRef.destination_for(document.path.get_file(),String(object.path),map_directory)
	if is_warp_visual:
		var warp_note := Label.new(); warp_note.text = "This is a placed warp visual. Convert it to a functional warp to give it an ID and destination."; warp_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; inspector.add_child(warp_note)
		var convert := Button.new(); convert.name = "ConvertToFunctionalWarp"; convert.text = "Convert to Functional Warp"; convert.pressed.connect(func(): _convert_warp_visual(object)); inspector.add_child(convert)
	if is_warp: _add_warp_id_editor(object, destination)
	_add_vector_editor("Offset (relative X / Y / Z)" if object.field=="asset_collision" else "Position",object.position-object.owner_position if object.field=="asset_collision" else object.position,func(v):
		if object.field=="asset_collision":_write_asset_collision(object,object.owner_position+v,object.size)
		else:_push_undo();_write_object_position(object,v);_after_edit())
	if String(object.get("universal_type",""))=="structure.bridge":_add_bridge_editor(object)
	elif object.field=="npcs":_add_npc_inspector(object)
	elif String(object.get("universal_type","")).begins_with("npc."):_add_character_editor(object)
	elif object.field=="objects" and object.shape=="point":
		var standardize:CheckBox=null
		if String(object.get("universal_type","")).begins_with("asset."):standardize=_add_asset_scale_standardizer(object)
		var height:=SpinBox.new();height.min_value=0.05;height.max_value=20;height.step=0.05;height.value=float(object.display_height);height.prefix="Visual height ";height.value_changed.connect(func(v):_set_asset_visual_height(object,float(v),standardize!=null and standardize.button_pressed));inspector.add_child(height)
		_add_vector_editor("Dimensions",object.size,func(v):_set_asset_dimensions(object,v,standardize!=null and standardize.button_pressed))
		if String(object.get("universal_type","")).begins_with("overlay.") or object.has("water_kind"):
			var rotation:=SpinBox.new();rotation.name="OverlayRotationDegrees";rotation.min_value=-3600.0;rotation.max_value=3600.0;rotation.step=1.0;rotation.allow_greater=true;rotation.allow_lesser=true;rotation.value=float(object.get("rotation_degrees",0.0));rotation.prefix="Rotation ";rotation.suffix="°";rotation.value_changed.connect(func(value):_set_overlay_rotation(object,float(value)));inspector.add_child(rotation)
			if not object.has("water_kind"): _add_attachment_editor(object)
	if object.shape=="rectangle":_add_vector_editor("Size",object.size,func(v):
		if object.field=="asset_collision":_write_asset_collision(object,object.position,v)
		else:_push_undo();_write_object_size(object,v);_after_edit())
	elif object.shape=="building":_add_vector_editor("Exterior Collision Size",object.size,func(v):_push_undo();document.set_value(String(object.size_path),[v.x,v.y,v.z]);_after_edit())
	if String(object.get("universal_type","")).begins_with("tile."):
		var tile_rotation:=SpinBox.new();tile_rotation.name="TileRotationDegrees";tile_rotation.min_value=-3600.0;tile_rotation.max_value=3600.0;tile_rotation.step=1.0;tile_rotation.allow_greater=true;tile_rotation.allow_lesser=true;tile_rotation.value=float(object.get("rotation_degrees",0.0));tile_rotation.prefix="Rotation ";tile_rotation.suffix="°";tile_rotation.value_changed.connect(func(value):_set_overlay_rotation(object,float(value)));inspector.add_child(tile_rotation)
	var source_record:Variant=_get_path(String(object.path))
	if int(object.get("asset_variant",-1))>=0:_add_asset_variant_editor(object,source_record)
	if not object.has("water_kind") and source_record is Dictionary and String(source_record.get("asset_path","")).begins_with("res://assets/overworld/"):_add_asset_collision_editor(project_root.path_join(String(source_record.asset_path).trim_prefix("res://")))
	if int(object.variant)>=0:
		var variant:=SpinBox.new();variant.min_value=0;variant.max_value=1;variant.value=object.variant;variant.value_changed.connect(func(v):_push_undo();document.set_value(String(object.path)+"[3]",int(v));_after_edit());inspector.add_child(variant)
	var navigation_text:="\nDouble-click: "+String(destination.get("label","open destination")) if not destination.is_empty() else ""
	var space:=Label.new();space.text="Coordinate space: "+MapSchemaRef.coordinate_space(document.kind,String(object.field))+navigation_text+"\nFacing after arrival: unsupported\nTransition options: unsupported / fixed by runtime";space.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(space)
	if is_warp: _add_warp_destination_editor(object, destination)

func _add_asset_scale_standardizer(object:Dictionary)->CheckBox:
	var checkbox:=CheckBox.new();checkbox.name="StandardizeAssetScale";checkbox.text="Standardize scale for all instances"
	checkbox.tooltip_text="Use this visual height and these dimensions for every instance of this asset family, including numbered variants and future placements."
	var paths:=_asset_family_paths(String(object.get("universal_type","")))
	if not paths.is_empty():checkbox.button_pressed=bool(AssetCatalogRef.load_metadata(paths[0]).get("standardize_scale",false))
	checkbox.toggled.connect(func(enabled):
		if enabled:_standardize_asset_scale(object,float(object.display_height),object.size)
		else:
			for asset_path:String in paths:
				var metadata:=AssetCatalogRef.load_metadata(asset_path);metadata["standardize_scale"]=false;AssetCatalogRef.save_metadata(asset_path,metadata)
		status_label.text="Shared asset scale enabled." if enabled else "Shared asset scale disabled; existing instance sizes were preserved.")
	inspector.add_child(checkbox);return checkbox

func _asset_family_paths(type_id:String)->Array[String]:
	var result:Array[String]=[];var entry:Dictionary=catalog.by_id.get(type_id,{})
	for variant:Variant in entry.get("variants",[]):
		if variant is Dictionary:
			var variant_path:=String(variant.get("asset_path",""))
			if variant_path.begins_with("res://"):result.append(project_root.path_join(variant_path.trim_prefix("res://")))
	var entry_path:=String(entry.get("asset_path",""))
	if result.is_empty() and entry_path.begins_with("res://"):result.append(project_root.path_join(entry_path.trim_prefix("res://")))
	return result

func _standardize_asset_scale(object:Dictionary,height:float,size:Vector3)->void:
	var type_id:=String(object.get("universal_type",""));_push_undo()
	for record:Variant in document.data.get("objects",[]):
		if record is Dictionary and String(record.get("type",""))==type_id:record["height"]=height;record["size"]=[size.x,size.y,size.z]
	for asset_path:String in _asset_family_paths(type_id):
		var metadata:=AssetCatalogRef.load_metadata(asset_path);metadata["standardize_scale"]=true;metadata["visual_height"]=height;metadata["size"]=[size.x,size.y,size.z];AssetCatalogRef.save_metadata(asset_path,metadata)
	var entry:Dictionary=catalog.by_id.get(type_id,{})
	if not entry.is_empty():entry["display_height"]=height;entry["default_size"]=[size.x,size.y,size.z]
	document.dirty=true;_after_edit()

func _set_asset_visual_height(object:Dictionary,height:float,standardize:bool)->void:
	if standardize:_standardize_asset_scale(object,height,object.size);return
	_push_undo();var record:Variant=_get_path(String(object.path));if record is Dictionary:record["height"]=height;document.dirty=true;_after_edit()

func _set_asset_dimensions(object:Dictionary,size:Vector3,standardize:bool)->void:
	if standardize:_standardize_asset_scale(object,float(object.display_height),size);return
	_push_undo();_write_object_size(object,size);_after_edit()

func _set_overlay_rotation(object:Dictionary,rotation_degrees:float)->void:
	_push_undo();document.set_value(String(object.path)+".rotation_degrees",rotation_degrees);_after_edit()

func _add_attachment_editor(object:Dictionary)->void:
	var attached:=CheckBox.new();attached.name="IsAttachedOverlay";attached.text="Is Attached Overlay";attached.button_pressed=bool(object.get("is_attached",false));inspector.add_child(attached)
	var state:=Label.new();state.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;state.text="Host: %s\nHost-local position controls sorting as one decorated object."%String(object.get("host_label","Choose a host" if not attached.button_pressed else "Missing host"));inspector.add_child(state)
	var picker:=Button.new();picker.name="HostEyedropper";picker.text="Choose Host (Eyedropper)";picker.disabled=not attached.button_pressed;picker.pressed.connect(func():attachment_overlay_id=String(object.id);canvas.host_picker_active=true;status_label.text="Host eyedropper active. Click a tree, building, or placed object sprite.");inspector.add_child(picker)
	var order:=SpinBox.new();order.name="AttachmentOrder";order.min_value=0;order.max_value=100000;order.step=1;order.value=int(object.get("attachment_order",0));order.prefix="Attachment order ";order.editable=attached.button_pressed;order.value_changed.connect(func(value):_push_undo();document.set_value(String(object.path)+".attachment_order",int(value));_after_edit());inspector.add_child(order)
	attached.toggled.connect(func(enabled):
		if enabled:
			attachment_overlay_id=String(object.id);canvas.host_picker_active=true;status_label.text="Attachment enabled. Click a valid host sprite."
		else:_detach_overlay(object))

func _detach_overlay(object:Dictionary)->void:
	var record:Variant=_get_path(String(object.path));if not record is Dictionary:return
	_push_undo();record["position"]=[object.position.x,object.position.y,object.position.z];record["is_attached"]=false;record.erase("host_id");record.erase("local_position");record.erase("attachment_order");document.dirty=true;_after_edit();status_label.text="Overlay detached without moving it."

func _ensure_host_identity(host:Dictionary)->String:
	if _is_valid_attachment_host(host):return String(host.instance_id)
	if String(host.get("field",""))=="trees":
		var parts:=_array_parent_and_index(String(host.path));var trees:Variant=_get_path(String(parts.get("path","")))
		if trees is Array and int(parts.get("index",-1))>=0:
			var id:=_new_instance_id();var type_id:="tree.main" if int(host.get("variant",0))==0 else "tree.palm"
			var record:={"type":type_id,"position":[host.position.x,host.position.y,host.position.z],"height":float(host.get("display_height",4.2)),"instance_id":id}
			trees.remove_at(int(parts.index));if not document.data.get("objects") is Array:document.data["objects"]=[];document.data.objects.append(record);return id
	if String(host.get("field",""))=="objects" and not String(host.get("universal_type","")).begins_with("overlay.") and not String(host.get("universal_type","")).begins_with("npc."):
		var record:Variant=_get_path(String(host.path));if record is Dictionary:
			var id:=_new_instance_id();record["instance_id"]=id;return id
	return ""

func _on_attachment_host_picked(host_editor_id:String)->void:
	var overlay:=_find_object(attachment_overlay_id);var host:=_find_object(host_editor_id);attachment_overlay_id=""
	if overlay.is_empty() or host.is_empty():status_label.text="No host selected; the overlay was not attached.";_refresh_inspector();return
	if String(host.get("universal_type","")).begins_with("overlay.") or String(host.get("role","")) in ["terrain","marker","npc"] or String(host.get("field","")) in ["terrain_tiles","asset_collision"]:
		status_label.text="That target cannot host an overlay.";_refresh_inspector();return
	_push_undo();var host_id:=_ensure_host_identity(host)
	if host_id.is_empty():undo_stack.pop_back();status_label.text="That target has no attachable object sprite.";_refresh_inspector();return
	var record:Variant=_get_path(String(overlay.path));if not record is Dictionary:undo_stack.pop_back();return
	var next_order:=0
	for candidate:Variant in document.data.get("objects",[]):if candidate is Dictionary and candidate!=record and bool(candidate.get("is_attached",false)) and String(candidate.get("host_id",""))==host_id:next_order=maxi(next_order,int(candidate.get("attachment_order",-1))+1)
	var host_position:Vector3=host.position;record["is_attached"]=true;record["host_id"]=host_id;record["local_position"]=[overlay.position.x-host_position.x,overlay.position.z-host_position.z]
	record["attachment_order"]=next_order;record["position"]=[overlay.position.x,overlay.position.y,overlay.position.z];document.dirty=true;_after_edit();status_label.text="Overlay attached without changing its apparent position."

func _add_asset_variant_editor(object:Dictionary,source_record:Variant)->void:
	if not source_record is Dictionary:return
	var entry:Dictionary=catalog.by_id.get(String(object.get("universal_type","")),{});var variants:Variant=entry.get("variants",[])
	if not variants is Array or variants.is_empty():return
	var label:=Label.new();label.text="Asset Variant";inspector.add_child(label)
	var selector:=OptionButton.new();selector.name="AssetVariant"
	for candidate:Variant in variants:
		if not candidate is Dictionary:continue
		selector.add_item(String(candidate.get("name","Variant")));selector.set_item_metadata(selector.item_count-1,int(candidate.get("value",0)))
		if int(candidate.get("value",0))==int(object.asset_variant):selector.select(selector.item_count-1)
	selector.item_selected.connect(func(index):
		var chosen_value:=int(selector.get_item_metadata(index));var chosen:Dictionary={}
		for candidate:Variant in variants:if candidate is Dictionary and int(candidate.get("value",-1))==chosen_value:chosen=candidate;break
		if chosen.is_empty():return
		_push_undo();source_record["variant"]=chosen_value;source_record["asset_path"]=String(chosen.asset_path);document.dirty=true;_after_edit())
	inspector.add_child(selector)

func _add_warp_id_editor(object: Dictionary, destination: Dictionary) -> void:
	var field := String(object.field)
	var record := _warp_metadata_record(field, destination)
	var id_label := Label.new(); id_label.text = "ID"; inspector.add_child(id_label)
	var id_spin := SpinBox.new(); id_spin.name = "WarpId"; id_spin.min_value = 1; id_spin.max_value = 999999; id_spin.step = 1; id_spin.value = int(record.id)
	id_spin.value_changed.connect(func(value): _set_warp_metadata(field, "id", int(value))); inspector.add_child(id_spin)

func _add_warp_destination_editor(object: Dictionary, destination: Dictionary) -> void:
	var field := String(object.field)
	var record := _warp_metadata_record(field, destination)
	var facing_label := Label.new(); facing_label.text = "Warp Visual Facing"; inspector.add_child(facing_label)
	var facing_select := OptionButton.new(); facing_select.name = "WarpFacing"
	for facing in ["generic", "north", "east", "west"]:
		facing_select.add_item(facing.capitalize()); facing_select.set_item_metadata(facing_select.item_count - 1, facing)
		if facing == String(record.facing): facing_select.select(facing_select.item_count - 1)
	facing_select.item_selected.connect(func(index): _set_warp_metadata(field, "facing", String(facing_select.get_item_metadata(index)))); inspector.add_child(facing_select)
	var map_label := Label.new(); map_label.text = "Entrance Map"; inspector.add_child(map_label)
	var map_select := OptionButton.new(); map_select.name = "WarpEntranceMap"; map_select.fit_to_longest_item = false; map_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var maps := _available_map_files(); map_select.add_item("None"); map_select.set_item_metadata(0, "")
	var selected := 0
	for filename in maps:
		map_select.add_item(filename.trim_suffix(".json")); map_select.set_item_metadata(map_select.item_count - 1, filename)
		if filename == String(record.entrance_map): selected = map_select.item_count - 1
	if selected == 0 and not String(record.entrance_map).is_empty():
		map_select.add_item("Invalid destination: " + String(record.entrance_map));map_select.set_item_metadata(map_select.item_count - 1, String(record.entrance_map));map_select.set_item_disabled(map_select.item_count - 1, true);selected=map_select.item_count - 1
	map_select.select(selected)
	map_select.item_selected.connect(func(index): _set_warp_entrance_map(field, String(map_select.get_item_metadata(index)))); inspector.add_child(map_select)
	var target_label := Label.new(); target_label.text = "Entrance Map Warp ID"; inspector.add_child(target_label)
	var target_spin := SpinBox.new(); target_spin.name = "WarpEntranceMapWarpId"; target_spin.min_value = 1; target_spin.max_value = 999999; target_spin.step = 1; target_spin.value = int(record.entrance_map_warp_id)
	target_spin.value_changed.connect(func(value): _set_warp_target_id(field, int(value))); inspector.add_child(target_spin)

func _warp_metadata_record(field: String, destination: Dictionary = {}) -> Dictionary:
	var metadata: Variant = document.data.get("warp_metadata", {})
	var existing: Dictionary = metadata.get(field, {}) if metadata is Dictionary and metadata.get(field) is Dictionary else {}
	return {"id":maxi(1, int(existing.get("id", MapGraphRef.warp_id_for(document.data, field)))), "entrance_map":String(existing.get("entrance_map", destination.get("map", ""))), "entrance_map_warp_id":maxi(1, int(existing.get("entrance_map_warp_id", 1))), "facing":String(existing.get("facing", "generic"))}

func _is_universal_warp_visual(object: Dictionary) -> bool:
	return String(object.get("field", "")) == "objects" and String(object.get("universal_type", "")).begins_with("asset.warp_")

func _convert_warp_visual(object: Dictionary) -> void:
	var source: Variant = _get_path(String(object.path))
	if not source is Dictionary or not source.get("position") is Array or source.position.size() < 3: return
	var used_ids := {}; var highest_id := 0
	for existing_field in MapGraphRef.warp_fields(document.data):
		var existing_id := MapGraphRef.warp_id_for(document.data, existing_field); used_ids[existing_id] = true; highest_id = maxi(highest_id, existing_id)
	var new_id := highest_id + 1
	while used_ids.has(new_id): new_id += 1
	var field := "warp_%d" % new_id
	while document.data.has(field): field += "_new"
	var type_id := String(source.get("type", ""))
	var facing := "generic"
	for candidate in ["north", "east", "west"]:
		if type_id.ends_with("facing_" + candidate): facing = candidate; break
	var parts := _array_parent_and_index(String(object.path))
	var objects: Variant = _get_path(String(parts.get("path", "")))
	if parts.is_empty() or not objects is Array: return
	_push_undo()
	document.data[field] = source.position.duplicate()
	if not document.data.get("warp_metadata") is Dictionary: document.data["warp_metadata"] = {}
	document.data.warp_metadata[field] = {"id":new_id, "entrance_map":"", "entrance_map_warp_id":1, "facing":facing}
	objects.remove_at(int(parts.index)); _shift_array_identities(String(parts.path), int(parts.index), -1, true)
	document.dirty = true; _after_edit()
	for candidate in editor_objects:
		if String(candidate.path) == "$." + field: canvas.select_object(String(candidate.id)); break
	status_label.text = "Converted warp visual to warp ID %d. Choose its destination in the Inspector." % new_id

func _set_warp_metadata(field: String, property: String, value: Variant) -> void:
	_push_undo()
	if not document.data.get("warp_metadata") is Dictionary: document.data["warp_metadata"] = {}
	var record := _warp_metadata_record(field, MapGraphRef.destination_for(document.path.get_file(), "$." + field, map_directory)); record[property] = value
	document.data.warp_metadata[field] = record; document.dirty = true; _after_edit()

func _set_warp_entrance_map(field: String, filename: String) -> void:
	if not filename.is_empty(): _ensure_map_has_warp(filename)
	_set_warp_metadata(field, "entrance_map", filename)
	_sync_legacy_connection(field, filename, int(_warp_metadata_record(field).entrance_map_warp_id))

func _set_warp_target_id(field: String, warp_id: int) -> void:
	_set_warp_metadata(field, "entrance_map_warp_id", warp_id)
	var record := _warp_metadata_record(field); _sync_legacy_connection(field, String(record.entrance_map), warp_id)

func _sync_legacy_connection(field: String, target_map: String, target_id: int) -> void:
	for value: Variant in document.data.get("outdoor_connections", []):
		if value is Dictionary and String(value.get("warp", "")) == field:
			value["destination_map"] = target_map
			var target_field := MapGraphRef.warp_field_for_id(target_map, target_id, map_directory) if not target_map.is_empty() else ""
			if not target_field.is_empty(): value["arrival"] = target_field
			document.dirty = true; _after_edit(); return

func _available_map_files() -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(map_directory)
	if directory == null: return result
	for filename in directory.get_files():
		if not filename.to_lower().ends_with(".json") or filename == "map_index.json":continue
		if filename.ends_with("_NPC_Data.json"):continue
		var candidate:=MapDocumentRef.load_file(map_directory.path_join(filename))
		if not candidate.parse_error.is_empty() or _is_world_index_document(candidate):continue
		result.append(filename)
	result.sort(); return result

func _ensure_map_has_warp(filename: String) -> void:
	if filename.is_empty(): return
	if document != null and document.path.get_file() == filename:
		if not MapGraphRef.warp_fields(document.data).is_empty(): return
		document.data["return_warp"] = [0.0, 0.12, 0.0]; document.data["warp_metadata"] = {"return_warp":{"id":1,"entrance_map":"","entrance_map_warp_id":1}}; document.dirty = true; return
	var target := MapDocumentRef.load_file(map_directory.path_join(filename))
	if not target.parse_error.is_empty() or _is_world_index_document(target) or not MapGraphRef.warp_fields(target.data).is_empty(): return
	target.data["return_warp"] = [0.0, 0.12, 0.0]
	target.data["warp_metadata"] = {"return_warp":{"id":1,"entrance_map":"","entrance_map_warp_id":1}}
	target.dirty = true
	var save_error := target.save_atomic(target.path, [])
	if save_error != OK: status_label.text = "Could not create warp ID 1 in %s." % filename

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

func _add_asset_collision_editor(asset_path:String)->void:
	var heading:=Label.new();heading.text="SHARED ASSET COLLISION";heading.add_theme_font_size_override("font_size",16);inspector.add_child(heading)
	var note:=Label.new();note.text="Collision is saved beside the sprite and affects every instance. Instance movement, resize, and rotation transform the canonical shape automatically.";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(note)
	var metadata:=AssetCatalogRef.load_metadata(asset_path);var boxes:Variant=metadata.get("collision_boxes",[])
	if not boxes is Array:boxes=[];metadata["collision_boxes"]=boxes
	for index in boxes.size():
		var box:Variant=boxes[index];if not box is Dictionary:continue
		var row:=HBoxContainer.new();inspector.add_child(row)
		var offset:=LineEdit.new();offset.text="%s, %s"%[box.get("offset",[0,0])[0],box.get("offset",[0,0])[1]];offset.tooltip_text="Offset X, Z";row.add_child(offset)
		var dimensions:=LineEdit.new();dimensions.text="%s, %s, %s"%[box.get("size",[1,1,1])[0],box.get("size",[1,1,1])[1],box.get("size",[1,1,1])[2]];dimensions.tooltip_text="Size X, Y, Z";row.add_child(dimensions)
		var edit:=Button.new();edit.name="EditCollisionBox%d"%index;edit.text="Edit";edit.tooltip_text="Edit this collision box numerically without selecting it on the canvas.";edit.pressed.connect(_open_collision_box_editor.bind(asset_path,metadata,boxes,index));row.add_child(edit)
		var remove:=Button.new();remove.text="Remove";remove.pressed.connect(func():boxes.remove_at(index);AssetCatalogRef.save_metadata(asset_path,metadata);_refresh_all());row.add_child(remove)
		offset.text_submitted.connect(func(text):var v:=_collision_numbers(text,2);if v.size()==2:box["offset"]=v;AssetCatalogRef.save_metadata(asset_path,metadata))
		dimensions.text_submitted.connect(func(text):var v:=_collision_numbers(text,3);if v.size()==3:box["size"]=v;AssetCatalogRef.save_metadata(asset_path,metadata))
	var add:=Button.new();add.text="Add Collision";add.pressed.connect(func():boxes.append({"offset":[0.0,0.0],"size":[1.0,1.0,1.0]});AssetCatalogRef.save_metadata(asset_path,metadata);_refresh_all());inspector.add_child(add)
	var collision:Variant=metadata.get("collision",{})
	var polygon_errors:=AssetCatalogRef.validate_polygon_collision(collision)
	var polygon_state:=Label.new();polygon_state.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	polygon_state.text="Polygon: none" if not collision is Dictionary or String(collision.get("type",""))!="polygon" else ("Polygon: valid (%d vertices)"%collision.get("points",[]).size() if polygon_errors.is_empty() else "Polygon needs attention: "+" ".join(polygon_errors))
	polygon_state.add_theme_color_override("font_color",Color("#8ee59b") if polygon_errors.is_empty() and collision is Dictionary and String(collision.get("type",""))=="polygon" else Color("#ffb46b"));inspector.add_child(polygon_state)
	var editing_this_polygon:=canvas.collision_polygon_active and polygon_asset_path==asset_path
	var edit_polygon:=Button.new();edit_polygon.name="EditPolygonCollider";edit_polygon.text="Finish Editing Polygon Collider" if editing_this_polygon else "Edit Polygon Collider";edit_polygon.pressed.connect(_toggle_polygon_collision_editor.bind(asset_path));inspector.add_child(edit_polygon)
	var clear_polygon:=Button.new();clear_polygon.name="ClearPolygonCollider";clear_polygon.text="Clear / Reset Polygon";clear_polygon.pressed.connect(func():
		if canvas.collision_polygon_active and polygon_asset_path==asset_path:canvas.clear_collision_polygon()
		else:
			var current:=AssetCatalogRef.load_metadata(asset_path);var before:Variant=current.get("collision",{});polygon_undo_stack.append({"asset_path":asset_path,"collision":before.duplicate(true) if before is Dictionary else {}});polygon_redo_stack.clear();current["collision"]={"type":"polygon","points":[],"closed":false};AssetCatalogRef.save_metadata(asset_path,current);_refresh_all());inspector.add_child(clear_polygon)

func _begin_polygon_collision_editor(asset_path:String)->void:
	polygon_asset_path=asset_path;polygon_undo_stack.clear();polygon_redo_stack.clear()
	var collision:Variant=AssetCatalogRef.load_metadata(asset_path).get("collision",{})
	var points:Array=collision.get("points",[]) if collision is Dictionary and String(collision.get("type",""))=="polygon" else []
	var closed:=bool(collision.get("closed",false)) if collision is Dictionary else false
	canvas.begin_collision_polygon_editor(points,closed);status_label.text="Polygon collider mode: click to add, click the first vertex to close, drag vertices, click edges to insert, Delete removes the selected vertex."
	_refresh_inspector()

func _toggle_polygon_collision_editor(asset_path:String)->void:
	if canvas.collision_polygon_active and polygon_asset_path==asset_path:
		_finish_polygon_collision_editor()
	else:_begin_polygon_collision_editor(asset_path)

func _finish_polygon_collision_editor()->void:
	canvas.end_collision_polygon_editor();polygon_asset_path="";status_label.text="Polygon collider saved. Selection mode restored.";_refresh_inspector()

func _on_collision_polygon_changed(points:Array,closed:bool,action:String)->void:
	if polygon_asset_path.is_empty():return
	var metadata:=AssetCatalogRef.load_metadata(polygon_asset_path);var before:Variant=metadata.get("collision",{})
	polygon_undo_stack.append({"asset_path":polygon_asset_path,"collision":before.duplicate(true) if before is Dictionary else {}});polygon_redo_stack.clear()
	metadata["collision"]={"type":"polygon","points":points,"closed":closed}
	if AssetCatalogRef.save_metadata(polygon_asset_path,metadata)!=OK:status_label.text="Could not save polygon collision metadata.";return
	var errors:=AssetCatalogRef.validate_polygon_collision(metadata.collision)
	status_label.text=action+". Polygon collider saved for every instance." if errors.is_empty() else action+". "+" ".join(errors)

func _apply_polygon_history(entry:Dictionary,target_stack:Array[Dictionary])->void:
	var asset_path:=String(entry.get("asset_path",""));if asset_path.is_empty():return
	var metadata:=AssetCatalogRef.load_metadata(asset_path);var current:Variant=metadata.get("collision",{})
	target_stack.append({"asset_path":asset_path,"collision":current.duplicate(true) if current is Dictionary else {}});metadata["collision"]=entry.get("collision",{}).duplicate(true);AssetCatalogRef.save_metadata(asset_path,metadata)
	var collision:Variant=metadata.collision;canvas.begin_collision_polygon_editor(collision.get("points",[]) if collision is Dictionary else [],bool(collision.get("closed",false)) if collision is Dictionary else false);status_label.text="Polygon collision history restored."

func _polygon_undo()->void:
	if polygon_undo_stack.is_empty():return
	_apply_polygon_history(polygon_undo_stack.pop_back(),polygon_redo_stack)

func _polygon_redo()->void:
	if polygon_redo_stack.is_empty():return
	_apply_polygon_history(polygon_redo_stack.pop_back(),polygon_undo_stack)

func _open_collision_box_editor(asset_path:String,metadata:Dictionary,boxes:Array,index:int)->void:
	if index<0 or index>=boxes.size() or not boxes[index] is Dictionary:return
	var box:Dictionary=boxes[index];var offset:Variant=box.get("offset",[0.0,0.0]);var size:Variant=box.get("size",[1.0,1.0,1.0])
	var dialog:=ConfirmationDialog.new();dialog.name="CollisionBoxDataEditor";dialog.title="Edit Collision Box %d"%(index+1);dialog.dialog_text="Direct shared collision data";dialog.ok_button_text="Save"
	var fields:=VBoxContainer.new();fields.custom_minimum_size.x=420;dialog.add_child(fields)
	var offset_label:=Label.new();offset_label.text="Offset (X / Z)";fields.add_child(offset_label)
	var offset_row:=HBoxContainer.new();fields.add_child(offset_row);var offset_spins:Array[SpinBox]=[]
	for axis in 2:
		var spin:=SpinBox.new();spin.name="CollisionOffset%s"%("X" if axis==0 else "Z");spin.min_value=-10000;spin.max_value=10000;spin.step=0.01;spin.value=float(offset[axis]) if offset is Array and offset.size()>axis else 0.0;spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL;offset_row.add_child(spin);offset_spins.append(spin)
	var size_label:=Label.new();size_label.text="Size (X / Y / Z)";fields.add_child(size_label)
	var size_row:=HBoxContainer.new();fields.add_child(size_row);var size_spins:Array[SpinBox]=[]
	for axis in 3:
		var spin:=SpinBox.new();spin.name="CollisionSize"+["X","Y","Z"][axis];spin.min_value=0.01;spin.max_value=10000;spin.step=0.01;spin.value=float(size[axis]) if size is Array and size.size()>axis else 1.0;spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL;size_row.add_child(spin);size_spins.append(spin)
	dialog.confirmed.connect(func():
		box["offset"]=[offset_spins[0].value,offset_spins[1].value];box["size"]=[size_spins[0].value,size_spins[1].value,size_spins[2].value];metadata["collision_boxes"]=boxes
		if AssetCatalogRef.save_metadata(asset_path,metadata)==OK:status_label.text="Collision box %d updated for every instance."%(index+1);_refresh_all()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);add_child(dialog);dialog.popup_centered()

func _collision_numbers(text:String,count:int)->Array:
	var result:Array=[]
	for part in text.split(","):
		if not part.strip_edges().is_valid_float():return []
		result.append(float(part.strip_edges()))
	return result if result.size()==count else []

func _add_vector_editor(label_text:String,value:Vector3,callback:Callable)->void:
	var label:=Label.new();label.text=label_text+" (X / Y / Z)";inspector.add_child(label);var row:=HBoxContainer.new();inspector.add_child(row)
	var spins:Array[SpinBox]=[]
	for axis in 3:
		var spin:=SpinBox.new();spin.min_value=-10000;spin.max_value=10000;spin.step=0.01;spin.value=value[axis];spin.custom_minimum_size.x=100;row.add_child(spin);spins.append(spin)
	for spin in spins:spin.value_changed.connect(func(_v):if not updating_inspector:callback.call(Vector3(spins[0].value,spins[1].value,spins[2].value)))

func _refresh_metadata()->void:
	for child in metadata_box.get_children():child.queue_free()
	var heading:=Label.new();heading.text="MAP";heading.add_theme_font_size_override("font_size",18);metadata_box.add_child(heading)
	var name_label:=Label.new();name_label.text="Name";metadata_box.add_child(name_label)
	var name_edit:=LineEdit.new();name_edit.name="MapDisplayName";name_edit.text=String(document.data.get("map_metadata",{}).get("display_name",document.path.get_basename().get_file().replace("_"," ").capitalize()));name_edit.text_submitted.connect(func(text):_set_map_metadata("display_name",text));metadata_box.add_child(name_edit)
	if document.data.get("origin") is Array:_add_metadata_vector("Origin", "origin", document.data.origin)
	var size_field:=_map_size_field()
	if not size_field.is_empty():_add_metadata_vector("Dimensions",size_field,document.data[size_field])
	if document.data.has("base_terrain_type"):
		var base_label:=Label.new();base_label.text="Base Terrain";metadata_box.add_child(base_label)
		var base:=OptionButton.new();base.name="BaseTerrainType"
		for terrain_type in ["forest_floor","sand","water","mud","stone","rock"]:base.add_item(terrain_type.replace("_"," ").capitalize());base.set_item_metadata(base.item_count-1,terrain_type)
		var current:=String(document.data.get("base_terrain_type",""));for index in base.item_count:if String(base.get_item_metadata(index))==current:base.select(index)
		base.item_selected.connect(func(index):_push_undo();document.set_value("$.base_terrain_type",String(base.get_item_metadata(index)));_after_edit());metadata_box.add_child(base)
	if document.data.get("map_metadata") is Dictionary:
		for field in ["id","layout_type","group"]:
			var meta_edit:=LineEdit.new();meta_edit.placeholder_text="Map "+field;meta_edit.text=String(document.data.map_metadata.get(field,""));meta_edit.text_submitted.connect(func(text):_push_undo();document.data.map_metadata[field]=text;document.kind=MapSchemaRef.kind_for_data(document.data,document.kind);document.dirty=true;_after_edit());metadata_box.add_child(meta_edit)
	var encounters:=Label.new();encounters.text="ENCOUNTERS";encounters.add_theme_font_size_override("font_size",16);metadata_box.add_child(HSeparator.new());metadata_box.add_child(encounters)
	if document.data.get("tall_grass_species") is Array:
		_add_encounter_species_editor("Forest Floor", "tall_grass_species")
	if document.data.get("water_species") is Array:
		_add_encounter_species_editor("Water", "water_species")
	if document.data.has("water_encounter_chance"):
		var chance_label:=Label.new();chance_label.text="Encounter Chance";metadata_box.add_child(chance_label)
		var chance:=SpinBox.new();chance.name="WaterEncounterChance";chance.min_value=0;chance.max_value=1;chance.step=0.01;chance.value=float(document.data.water_encounter_chance);chance.value_changed.connect(func(value):_push_undo();document.set_value("$.water_encounter_chance",value);_after_edit());metadata_box.add_child(chance)

func _add_metadata_vector(label_text:String,field:String,value:Array)->void:
	var label:=Label.new();label.text=label_text;metadata_box.add_child(label)
	var row:=HBoxContainer.new();metadata_box.add_child(row)
	for axis in value.size():
		var edit:=SpinBox.new();edit.name="Map%s%d"%[field.to_pascal_case(),axis];edit.min_value=-10000;edit.max_value=10000;edit.step=0.01;edit.value=float(value[axis]);edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var axis_names:=["X","Y","Z"];edit.prefix=(axis_names[axis] if axis<axis_names.size() else str(axis))+" ";edit.value_changed.connect(func(number):_set_numeric_component(field,axis,number));row.add_child(edit)

func _set_numeric_component(field:String,index:int,value:float)->void:
	var values:Variant=document.data.get(field)
	if not values is Array or index<0 or index>=values.size():return
	_push_undo();var updated:Array=values.duplicate();updated[index]=value;document.set_value("$."+field,updated);_after_edit()

func _set_map_metadata(field:String,value:String)->void:
	_push_undo();if not document.data.get("map_metadata") is Dictionary:document.data["map_metadata"]={}
	document.data.map_metadata[field]=value;document.kind=MapSchemaRef.kind_for_data(document.data,document.kind);document.dirty=true;_after_edit()

func _add_encounter_species_editor(label_text:String,field:String)->void:
	var label:=Label.new();label.text=label_text;metadata_box.add_child(label)
	var edit:=LineEdit.new();edit.placeholder_text="Fakemon, Fakemon@level";var labels:Array[String]=[]
	for value:Variant in document.data.get(field,[]):labels.append("%s@%d"%[value.get("fakemon","Unknown"),int(value.get("level",5))] if value is Dictionary else String(value))
	edit.text=", ".join(labels);edit.text_submitted.connect(func(text):_set_encounter_species(field,text));metadata_box.add_child(edit)
	var search:=LineEdit.new();search.name="EncounterSearch_"+field;search.placeholder_text="Search Fakemon to add…";metadata_box.add_child(search)
	var matches:=ItemList.new();matches.name="EncounterMatches_"+field;matches.custom_minimum_size.y=96;matches.visible=false;metadata_box.add_child(matches)
	search.text_changed.connect(func(query):
		matches.clear();var needle:String=query.strip_edges().to_lower()
		if needle.is_empty():matches.visible=false;return
		for species_name in fakemon_names:
			if species_name.to_lower().contains(needle):matches.add_item(species_name)
		matches.visible=matches.item_count>0)
	matches.item_activated.connect(func(index):
		var species_name:=matches.get_item_text(index)
		edit.text=(edit.text+", " if not edit.text.strip_edges().is_empty() else "")+species_name
		_set_encounter_species(field,edit.text);search.clear();matches.visible=false)

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

func _save_as()->void:
	if _is_world_index_document(document):status_label.text="The world manifest always saves as map_index.json. Use Rename to change only its display name.";return
	save_dialog.current_dir=map_directory;save_dialog.current_file=document.path.get_file();save_dialog.popup_centered_ratio(0.75)

func _is_world_index_document(doc:MapDocument)->bool:
	if doc==null or not doc.data is Dictionary:return false
	return doc.data.has("root") and doc.data.get("sections") is Dictionary and doc.data.get("nested_sections") is Dictionary

func _request_rename()->void:
	if document==null or document.path.is_empty():return
	if document.dirty:status_label.text="Save the map before renaming it.";return
	if _is_world_index_document(document):
		rename_dialog.title="Rename World Index";rename_dialog.dialog_text="Display name (the runtime filename remains map_index.json):"
		var metadata:Variant=document.data.get("index_metadata",{});rename_edit.text=String(metadata.get("display_name","Project Paradise World")) if metadata is Dictionary else "Project Paradise World"
	else:
		rename_dialog.title="Rename Map";rename_dialog.dialog_text="New filename (.json is optional):";rename_edit.text=document.path.get_file()
	rename_dialog.popup_centered()

func _confirm_rename()->void:
	var requested:=rename_edit.text.strip_edges()
	if requested.is_empty():return
	if _is_world_index_document(document):
		_push_undo()
		if not document.data.get("index_metadata") is Dictionary:document.data["index_metadata"]={"id":"project_paradise_world"}
		document.data.index_metadata["display_name"]=requested;document.dirty=true;_refresh_all();status_label.text="World index display name changed to "+requested+". Save to persist it.";return
	while requested.to_lower().ends_with(".json.json"):requested=requested.left(requested.length()-5)
	if not requested.to_lower().ends_with(".json"):requested+=".json"
	if requested.contains("/") or requested.contains("\\"):status_label.text="Enter a filename, not a path.";return
	_rename_current_map(requested)

func _rename_current_map(new_filename:String)->bool:
	if _is_world_index_document(document):status_label.text="The world manifest filename is fixed as map_index.json; rename its display name instead.";return false
	var old_path:=document.path;var old_filename:=old_path.get_file();var new_path:=map_directory.path_join(new_filename)
	if old_filename==new_filename:return true
	if FileAccess.file_exists(new_path):status_label.text="Rename blocked: %s already exists."%new_filename;return false
	var old_backup:=old_path+".bak";var copy_error:=document._copy_file(old_path,old_backup)
	if copy_error!=OK:status_label.text="Rename blocked: could not create backup.";return false
	var metadata:Variant=document.data.get("map_metadata",{})
	if metadata is Dictionary:metadata["id"]=new_filename.get_basename()
	var save_error:=_save_npc_pair(new_path,npc_data.issues(document.data,npc_visuals))
	if save_error!=OK:status_label.text="Rename blocked while writing the new map.";return false
	for filename in DirAccess.get_files_at(map_directory):
		if not filename.to_lower().ends_with(".json") or filename.ends_with("_NPC_Data.json") or filename in [old_filename,new_filename]:continue
		var ref_doc:=MapDocumentRef.load_file(map_directory.path_join(filename));if not ref_doc.parse_error.is_empty():continue
		if _replace_filename_references(ref_doc.data,old_filename,new_filename):
			ref_doc.dirty=true;var ref_error:=ref_doc.save_atomic(ref_doc.path,[])
			if ref_error!=OK:status_label.text="Renamed map, but failed to update %s."%filename;return false
	DirAccess.remove_absolute(old_path)
	var old_companion:String=npc_data.companion_path(old_path)
	if FileAccess.file_exists(old_companion):DirAccess.remove_absolute(old_companion)
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
	if _is_world_index_document(document) and path.get_file().to_lower()!="map_index.json":status_label.text="Save blocked: the world manifest must remain map_index.json.";return
	if _normalize_document_walls():document.dirty=true;_refresh_all()
	issues=MapValidatorRef.validate(document);issues.append_array(npc_data.issues(document.data,npc_visuals));var error:=_save_npc_pair(path,issues)
	if error==OK:
		if trainer_catalog_doc!=null and trainer_catalog_doc.dirty:
			var trainer_error:=trainer_catalog_doc.save_atomic(trainer_catalog_doc.path,[])
			if trainer_error!=OK:status_label.text="Map saved, but trainer catalog save failed.";return
		_register_current_map();status_label.text="Saved map and trainer catalog atomically; backup: "+path.get_file()+".bak";_refresh_all()
	else:status_label.text="Save blocked: fix validation errors before replacing output."

func _register_current_map()->void:
	if _is_world_index_document(document) or not document.data.get("map_metadata") is Dictionary:return
	var index_path:=map_directory.path_join("map_index.json");var index_doc:=MapDocumentRef.load_file(index_path)
	if not index_doc.parse_error.is_empty():return
	if not index_doc.data.get("maps") is Dictionary:index_doc.data["maps"]={}
	var map_id:=String(document.data.map_metadata.get("id",document.path.get_basename().get_file()));index_doc.data.maps[map_id]=document.path.get_file()
	if not index_doc.data.get("map_groups") is Dictionary:index_doc.data["map_groups"]={}
	var group:=String(document.data.map_metadata.get("group","custom"));if not index_doc.data.map_groups.get(group) is Array:index_doc.data.map_groups[group]=[]
	if not index_doc.data.map_groups[group].has(map_id):index_doc.data.map_groups[group].append(map_id)
	index_doc.dirty=true;index_doc.save_atomic(index_path,[])


func _add_npc_movement_inspector(definition: Dictionary) -> void:
	var modes := OptionButton.new();modes.name = "NpcMovementMode"
	for mode: String in npc_movement.MODE_OFFSETS:
		modes.add_item(mode.capitalize());modes.set_item_metadata(modes.item_count-1,mode)
		if mode == definition.get("movement_mode","ground"): modes.select(modes.item_count-1)
	modes.item_selected.connect(func(index):
		_push_undo();definition["movement_mode"] = modes.get_item_metadata(index);document.dirty = true;_after_edit())
	inspector.add_child(modes)
	var offset := SpinBox.new();offset.name = "NpcHeightOffset";offset.min_value = -100;offset.max_value = 100;offset.step = 0.1;offset.prefix = "Height offset "
	if npc_movement.traversal_error(definition).is_empty(): offset.value = float(definition.get("height_offset",0.0))
	offset.value_changed.connect(func(value):
		_push_undo();definition["height_offset"] = value;document.dirty = true;_after_edit())
	inspector.add_child(offset)
	var config:Dictionary = npc_movement.settings({})
	if not definition.has("movement") or npc_movement.validation_error(definition.movement).is_empty():
		config = npc_movement.settings(definition)
	var label := Label.new(); label.text = "Movement"; inspector.add_child(label)
	var picker := OptionButton.new(); picker.name = "NpcMovement"
	for preset: String in npc_movement.PRESETS:
		picker.add_item(String(npc_movement.PRESETS[preset]))
		picker.set_item_metadata(picker.item_count-1,preset)
		if preset == config.preset: picker.select(picker.item_count-1)
	picker.item_selected.connect(func(index):
		_push_undo();config.preset = String(picker.get_item_metadata(index))
		definition["movement"] = config.duplicate(true);document.dirty = true;_after_edit())
	inspector.add_child(picker)
	for axis in 2:
		var spin := SpinBox.new();spin.name = "NpcRangeX" if axis == 0 else "NpcRangeY"
		spin.min_value = 0;spin.max_value = 10000;spin.step = 0.25;spin.value = float(config.range[axis])
		spin.prefix = "Max X range ± " if axis == 0 else "Max Y range ± "
		spin.value_changed.connect(func(value):
			_push_undo();config.range[axis] = value
			definition["movement"] = config.duplicate(true);document.dirty = true;_after_edit())
		inspector.add_child(spin)
	var note := Label.new();note.text = "Range is measured from the placed starting point. Map Y is world Z. Movement runs in Test Map; obstacles stop movement."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;inspector.add_child(note)
