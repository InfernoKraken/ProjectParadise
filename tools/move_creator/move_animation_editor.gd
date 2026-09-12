extends Control

@export var embedded_mode := false

const ANIMATION_DIR := "res://data/move_animations"
const BASE_ANCHORS := ["origin", "head", "mouth", "neck", "left_wing", "right_wing", "tail"]
var model := MoveAnimationEditorModel.new()
var repository := GeneratedAnchorRepository.new()
var id_edit: LineEdit; var animation_select: OptionButton; var event_list: ItemList; var properties: VBoxContainer; var validation_label: Label; var add_menu: MenuButton
var preview: Control; var user_select: OptionButton; var target_select: OptionButton; var user_side: OptionButton; var target_side: OptionButton; var loop_check: CheckBox
var player: MoveAnimationPlayer; var effect_layer: Node2D; var overlay: ColorRect; var user_sprite: TextureRect; var target_sprite: TextureRect
var raw_dialog: AcceptDialog; var raw_text: TextEdit; var help_dialog: AcceptDialog; var import_dialog: FileDialog; var _updating := false; var _discovery_warnings := PackedStringArray()
var main_split: HSplitContainer; var left_split: VSplitContainer; var right_split: VSplitContainer; var property_scroll: ScrollContainer
var species_effect_data := {}

func _ready() -> void:
	if not embedded_mode: get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_load_species_effect_data()
	_build_ui(); _new_document()

func _build_ui() -> void:
	var outer:=VBoxContainer.new();outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);outer.clip_contents=true;add_child(outer)
	var header:=HBoxContainer.new();outer.add_child(header);var title:=Label.new();title.text="" if embedded_mode else "Move Animation Creator v0.2";title.add_theme_font_size_override("font_size",24);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title);_add_button(header,"Reference ?",_show_reference);_add_button(header,"Raw Definition",_show_raw)
	main_split=HSplitContainer.new();main_split.size_flags_vertical=Control.SIZE_EXPAND_FILL;main_split.split_offset=400 if embedded_mode else 465;outer.add_child(main_split)
	left_split=VSplitContainer.new();left_split.custom_minimum_size=Vector2(360,320);left_split.split_offset=250;main_split.add_child(left_split)
	var events_panel:=VBoxContainer.new();left_split.add_child(events_panel)
	var selector_row:=HBoxContainer.new();events_panel.add_child(selector_row);selector_row.add_child(_label("Animation:"));animation_select=OptionButton.new();animation_select.size_flags_horizontal=Control.SIZE_EXPAND_FILL;selector_row.add_child(animation_select);_add_button(selector_row,"Refresh",_refresh_animations);_add_button(selector_row,"Load",_load_document)
	var animation_row:=HBoxContainer.new();events_panel.add_child(animation_row);id_edit=LineEdit.new();id_edit.placeholder_text="New animation ID (lowercase_snake_case)";id_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;id_edit.text_changed.connect(_id_changed);animation_row.add_child(id_edit);_add_button(animation_row,"New",_new_document);_add_button(animation_row,"Save",_save_document)
	var actions:=HBoxContainer.new();events_panel.add_child(actions);add_menu=MenuButton.new();add_menu.text="Add Event";actions.add_child(add_menu)
	for index in MoveAnimationEditorModel.TYPES.size():add_menu.get_popup().add_item(MoveAnimationEditorModel.TYPE_LABELS[MoveAnimationEditorModel.TYPES[index]],index)
	add_menu.get_popup().id_pressed.connect(_add_event);_add_button(actions,"Delete Selected",_delete_selected)
	var clipboard_actions:=HBoxContainer.new();events_panel.add_child(clipboard_actions);_add_button(clipboard_actions,"Copy Event",_copy_event);_add_button(clipboard_actions,"Paste Event",_paste_event)
	event_list=ItemList.new();event_list.custom_minimum_size.y=110;event_list.size_flags_vertical=Control.SIZE_EXPAND_FILL;event_list.item_selected.connect(_select_event);events_panel.add_child(event_list)
	var properties_panel:=VBoxContainer.new();properties_panel.custom_minimum_size.y=180;left_split.add_child(properties_panel);var property_title:=Label.new();property_title.text="Event Properties";property_title.add_theme_font_size_override("font_size",18);properties_panel.add_child(property_title)
	property_scroll=ScrollContainer.new();property_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;properties_panel.add_child(property_scroll);properties=VBoxContainer.new();properties.custom_minimum_size.x=330;properties.size_flags_horizontal=Control.SIZE_EXPAND_FILL;property_scroll.add_child(properties)
	right_split=VSplitContainer.new();right_split.custom_minimum_size=Vector2(420,320);right_split.split_offset=440;main_split.add_child(right_split);var preview_panel:=VBoxContainer.new();right_split.add_child(preview_panel);var preview_title:=Label.new();preview_title.text="Preview Controls";preview_title.add_theme_font_size_override("font_size",18);preview_panel.add_child(preview_title)
	var selectors:=GridContainer.new();selectors.columns=4;preview_panel.add_child(selectors);for text in ["User Fakemon","User Side","Target Fakemon","Target Side"]:selectors.add_child(_label(text))
	var species:=_battle_species();user_select=_option(species,species[0] if not species.is_empty() else "Lochirp");target_select=_option(species,"Flambian");user_side=_option(["Player","Wild"],"Player");target_side=_option(["Player","Wild"],"Wild")
	for control in [user_select,user_side,target_select,target_side]:control.custom_minimum_size.x=105;selectors.add_child(control);control.item_selected.connect(func(_index):_rebuild_preview();_build_properties())
	preview=Control.new();preview.custom_minimum_size=Vector2(400,220);preview.size_flags_vertical=Control.SIZE_EXPAND_FILL;preview.clip_contents=true;preview_panel.add_child(preview)
	var background:=ColorRect.new();background.color=Color("#8fc985");background.z_index=0;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);preview.add_child(background);overlay=ColorRect.new();overlay.z_index=5;overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.visible=false;preview.add_child(overlay);effect_layer=Node2D.new();effect_layer.z_index=20;preview.add_child(effect_layer);user_sprite=TextureRect.new();target_sprite=TextureRect.new();user_sprite.z_index=10;target_sprite.z_index=10;preview.add_child(user_sprite);preview.add_child(target_sprite)
	var secondary_panel:=VBoxContainer.new();secondary_panel.custom_minimum_size.y=105;right_split.add_child(secondary_panel);var footer:=HBoxContainer.new();secondary_panel.add_child(footer);_add_button(footer,"Play",_play);_add_button(footer,"Stop",func():player.cancel());loop_check=CheckBox.new();loop_check.text="Loop";footer.add_child(loop_check);validation_label=Label.new();validation_label.size_flags_vertical=Control.SIZE_EXPAND_FILL;validation_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;secondary_panel.add_child(validation_label)
	player=MoveAnimationPlayer.new();player.animation_finished.connect(func():
		if loop_check.button_pressed:_play()
	);add_child(player);_build_dialogs();_refresh_animations()

func _build_dialogs()->void:
	raw_dialog=AcceptDialog.new();raw_dialog.title="Raw Definition (read-only)";raw_dialog.size=Vector2i(700,520);add_child(raw_dialog);raw_text=TextEdit.new();raw_text.editable=false;raw_text.custom_minimum_size=Vector2(660,440);raw_dialog.add_child(raw_text)
	import_dialog=FileDialog.new();import_dialog.title="Import Move-Effect PNG";import_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;import_dialog.access=FileDialog.ACCESS_FILESYSTEM;import_dialog.filters=PackedStringArray(["*.png ; PNG Images"]);import_dialog.use_native_dialog=true;import_dialog.file_selected.connect(_import_png);add_child(import_dialog)
	help_dialog=AcceptDialog.new();help_dialog.title="Move Animation Reference";help_dialog.size=Vector2i(620,540);add_child(help_dialog);var help:=RichTextLabel.new();help.bbcode_enabled=true;help.custom_minimum_size=Vector2(580,460);help.text="[b]Animation IDs[/b]\nThe lowercase snake_case ID is the value a move can later reference through animation_id. Loaded IDs are read-only; use New to create a copy under another ID.\n\n[b]Anchors[/b]\nExisting requested anchors are used directly. A missing requested anchor uses Origin; a missing Origin uses the processed sprite center with a warning. Offsets remain relative to the requested semantic anchor.\n\n[b]Beam[/b]\nStretches one PNG from the From anchor to the To anchor. Width is perpendicular thickness in battle-space pixels and never changes endpoint distance. Angle, length, and direction are automatic. Duration -1 persists until Destroy Sprite; zero follows the existing immediate-duration convention. Player-side textures mirror without changing endpoint geometry.\n\n[b]Scale Battler[/b]\nTemporarily stretches or shrinks User or Target by a percentage. Each loop moves out during its first half and restores the exact original scale during its second half.\n\n[b]Vertical Sprite[/b]\nFall To Anchor starts Distance pixels above an anchor and descends to it. Rise From Anchor starts at the anchor and travels upward. Both remove the effect after Duration.\n\n[b]Sprite Tint[/b]\nWhite (#FFFFFF) preserves the PNG. Other colors use standard modulation on Spawn, Impact, Beam, and Vertical Sprite.\n\n[b]Move Battler directions[/b]\nToward Target, Away From Target, Vertical. Vertical preserves X: negative distance moves upward and positive distance moves downward. Legacy Baseline data is treated as Vertical.\n\n[b]Impact Sprite[/b]\nDisplays an image or sprite-sheet over User or Target and automatically removes it after Duration. Its Instance ID lets Fade Sprite or Destroy Sprite target it; fading to zero removes it when the fade completes.\n\n[b]Effect Instance ID[/b]\nNames a spawned sprite, Impact Sprite, Beam, or Vertical Sprite so later Move, Fade, and Destroy events can reference it while active.\n\n[b]Layout[/b]\nThe authoring tools use actual window dimensions in maximized and fullscreen modes. Drag either divider to balance events, properties, preview, and playback controls.\n\n[b]Markers[/b]\nCommon names: impact, release, cast, end. Markers emit runtime synchronization signals.";help_dialog.add_child(help)

func _new_document()->void:model=MoveAnimationEditorModel.new();id_edit.editable=true;_sync_all();id_edit.select_all();id_edit.grab_focus()
func _load_document()->void:
	if animation_select.item_count==0:_status("Error: No valid animations are available to load.",true);return
	var animation_id:=animation_select.get_item_text(animation_select.selected);var path:=String(animation_select.get_item_metadata(animation_select.selected));var loaded:=MoveAnimationDefinition.load_file(path);if loaded==null:_status("Error: Could not load animation '%s'."%animation_id,true);return
	model.load_document(loaded);id_edit.editable=false;_sync_all()
func _save_document()->void:
	var errors:=model.document.validation_errors();if not errors.is_empty():_refresh_validation();return
	var error:=model.document.save_file("%s/%s.json"%[ANIMATION_DIR,model.document.data["id"]]);if error==OK:_refresh_animations(String(model.document.data["id"]));id_edit.editable=false
	_status("Saved %s.json"%model.document.data["id"] if error==OK else "Error: Save failed: %s"%error_string(error),error!=OK)

func _refresh_animations(select_id: String = "")->void:
	var discovery:=model.discover_animations(ANIMATION_DIR);_discovery_warnings=discovery["warnings"];animation_select.clear()
	for animation_id in discovery["ids"]:animation_select.add_item(animation_id);animation_select.set_item_metadata(animation_select.item_count-1,discovery["paths"][animation_id]);if animation_id==select_id:animation_select.select(animation_select.item_count-1)
	_refresh_validation()
func _add_event(id:int)->void:
	var event:=model.add_event(MoveAnimationEditorModel.TYPES[id]);if String(event.get("type","")) in ["move_sprite","fade_sprite","destroy_sprite"]:
		var ids:=model.spawn_instance_ids();event["instance_id"]=ids[0] if not ids.is_empty() else ""
	_sync_events();_build_properties();_refresh_validation()
func _delete_selected()->void:
	if model.delete_selected():_sync_events();_build_properties();_refresh_validation()
func _copy_event()->void:
	var serialized:=model.copy_selected_event_json()
	if serialized.is_empty():_status("Select an event to copy.",true);return
	DisplayServer.clipboard_set(serialized);_status("Copied selected event.")
func _paste_event()->void:
	if not model.paste_event_json(DisplayServer.clipboard_get()):_status("Clipboard does not contain a valid move-animation event.",true);return
	_sync_events();_build_properties();_refresh_validation();_status("Pasted event. Review its time and instance IDs before saving.")
func _select_event(index:int)->void:model.selected_event=model.document.data["events"][index];_build_properties()
func _id_changed(value:String)->void:
	if _updating:return
	model.document.data["id"]=value;_refresh_validation()
func _sync_all()->void:_updating=true;id_edit.text=String(model.document.data["id"]);_updating=false;_sync_events();_build_properties();_rebuild_preview();_refresh_validation()
func _sync_events()->void:
	_updating=true;event_list.clear();var selected_index:=-1
	for index in model.document.data["events"].size():
		var event:Dictionary=model.document.data["events"][index];event_list.add_item(model.event_summary(event));if event==model.selected_event:selected_index=index
	if selected_index>=0:event_list.select(selected_index);event_list.ensure_current_is_visible()
	_updating=false

func _build_properties()->void:
	for child in properties.get_children():child.queue_free()
	var event:=model.selected_event;if event.is_empty():properties.add_child(_label("Select or add an event to edit its properties."));return
	_add_number("Time (seconds)",event.get("time",0),0,999,0.01,func(v):model.set_event_time(event,v);_sync_events();_refresh_validation())
	match String(event.get("type","")):
		"spawn_sprite":_spawn_form(event)
		"impact_sprite":_impact_form(event)
		"beam":_beam_form(event)
		"vertical_sprite":_vertical_sprite_form(event)
		"move_sprite":_add_instance(event);_position_form(event,"to","Destination");_add_number("Duration",event.get("duration",0.3),0,99,0.01,func(v):_set_event(event,"duration",v));_add_choice("Easing",["Linear","Ease In","Ease Out","Ease In Out"],["linear","ease_in","ease_out","ease_in_out"],event.get("easing","linear"),func(v):_set_event(event,"easing",v))
		"fade_sprite":_add_instance(event);_add_number("Target Opacity",event.get("opacity",0),0,1,0.01,func(v):_set_event(event,"opacity",v));_add_number("Duration",event.get("duration",0.25),0,99,0.01,func(v):_set_event(event,"duration",v))
		"destroy_sprite":_add_instance(event)
		"shake_battler":_add_battler(event);_add_number("Duration",event.get("duration",0.2),0,99,0.01,func(v):_set_event(event,"duration",v));_add_number("Magnitude",event.get("magnitude",8),0,999,0.5,func(v):_set_event(event,"magnitude",v))
		"move_battler":_add_battler(event);_add_choice("Direction",["Toward Target","Away From Target","Vertical"],["toward_target","away_from_target","vertical"],"vertical" if event.get("direction","")=="baseline" else event.get("direction","toward_target"),func(v):_set_event(event,"direction",v));_add_number("Distance",event.get("distance",60),-999,999,1,func(v):_set_event(event,"distance",v));_add_number("Duration",event.get("duration",0.2),0,99,0.01,func(v):_set_event(event,"duration",v))
		"scale_battler":_scale_battler_form(event)
		"background_tint":_add_color(event);_add_number("Opacity",event.get("opacity",0.4),0,1,0.01,func(v):_set_event(event,"opacity",v));_add_number("Fade Duration",event.get("duration",0.15),0,99,0.01,func(v):_set_event(event,"duration",v))
		"restore_background":_add_number("Duration",event.get("duration",0.2),0,99,0.01,func(v):_set_event(event,"duration",v))
		"marker":_add_text("Marker Name",event.get("name","impact"),func(v):_set_event(event,"name",v))

func _spawn_form(event:Dictionary)->void:
	_add_text("Instance ID",event.get("instance_id","effect"),func(v):_set_event(event,"instance_id",v,true));var assets:=model.effect_assets();var labels:=PackedStringArray();for path in assets:labels.append(path.get_file())
	_add_choice("Asset",labels,assets,event.get("asset",""),func(v):_set_event(event,"asset",v);_build_properties());properties.add_child(_label(MoveEffectAssetRules.authoring_note(String(event.get("asset","")))));_add_asset_controls();_position_form(event,"position","Attachment");_add_number("Scale",event.get("scale",1),0.01,20,0.01,func(v):_set_event(event,"scale",v));_add_number("Rotation (degrees)",event.get("rotation",0),-3600,3600,1,func(v):_set_event(event,"rotation",v));_add_number("Opacity",event.get("opacity",1),0,1,0.01,func(v):_set_event(event,"opacity",v));_add_tint(event);_add_bool("Is Behind",bool(event.get("is_behind",false)),func(v):_set_event(event,"is_behind",v))
	var is_sheet:=event.get("sprite_sheet") is Dictionary;_add_choice("Sprite Mode",["Single Image","Sprite Sheet"],["single","sheet"],"sheet" if is_sheet else "single",func(v):event["sprite_sheet"]={"columns":1,"rows":1,"frame_count":1,"fps":10.0,"loop":false} if v=="sheet" else null;_build_properties();_changed())
	if event.get("sprite_sheet") is Dictionary:
		var sheet:Dictionary=event["sprite_sheet"];_add_number("Columns",sheet.get("columns",1),1,128,1,func(v):sheet["columns"]=int(v);_changed());_add_number("Rows",sheet.get("rows",1),1,128,1,func(v):sheet["rows"]=int(v);_changed());_add_number("Frame Count",sheet.get("frame_count",1),1,16384,1,func(v):sheet["frame_count"]=int(v);_changed());_add_number("FPS",sheet.get("fps",10),0.01,240,0.1,func(v):sheet["fps"]=v;_changed());_add_bool("Loop",sheet.get("loop",false),func(v):sheet["loop"]=v;_changed())

func _impact_form(event:Dictionary)->void:
	_add_section("Lifetime");_add_text("Instance ID",event.get("instance_id","impact"),func(v):_set_event(event,"instance_id",v,true));_add_number("Duration",event.get("duration",0.3),0,99,0.01,func(v):_set_event(event,"duration",v));properties.add_child(_label("Fade Sprite and Destroy Sprite can target this ID. A fade to 0 removes it safely."))
	_add_section("Placement");_position_form(event,"position","Target");var assets:=model.effect_assets();var labels:=PackedStringArray();for path in assets:labels.append(path.get_file())
	_add_choice("Asset",labels,assets,event.get("asset",""),func(v):_set_event(event,"asset",v);_build_properties());properties.add_child(_label(MoveEffectAssetRules.authoring_note(String(event.get("asset","")))));_add_asset_controls();_add_number("Scale",event.get("scale",1),0.01,20,0.01,func(v):_set_event(event,"scale",v));_add_number("Rotation (degrees)",event.get("rotation",0),-3600,3600,1,func(v):_set_event(event,"rotation",v));_add_number("Opacity",event.get("opacity",1),0,1,0.01,func(v):_set_event(event,"opacity",v));_add_tint(event);_add_bool("Is Behind",bool(event.get("is_behind",false)),func(v):_set_event(event,"is_behind",v))
	var is_sheet:=event.get("sprite_sheet") is Dictionary;_add_choice("Sprite Mode",["Single Image","Sprite Sheet"],["single","sheet"],"sheet" if is_sheet else "single",func(v):event["sprite_sheet"]={"columns":1,"rows":1,"frame_count":1,"fps":10.0,"loop":false} if v=="sheet" else null;_build_properties();_changed())
	if event.get("sprite_sheet") is Dictionary:
		var sheet:Dictionary=event["sprite_sheet"];_add_number("Columns",sheet.get("columns",1),1,128,1,func(v):sheet["columns"]=int(v);_changed());_add_number("Rows",sheet.get("rows",1),1,128,1,func(v):sheet["rows"]=int(v);_changed());_add_number("Frame Count",sheet.get("frame_count",1),1,16384,1,func(v):sheet["frame_count"]=int(v);_changed());_add_number("FPS",sheet.get("fps",10),0.01,240,0.1,func(v):sheet["fps"]=v;_changed());_add_bool("Loop",sheet.get("loop",false),func(v):sheet["loop"]=v;_changed())

func _beam_form(event: Dictionary) -> void:
	_add_section("Identity"); _add_text("Instance ID",event.get("instance_id","beam"),func(v):_set_event(event,"instance_id",v,true))
	_add_section("Start"); _position_form(event,"from","From")
	_add_section("End"); _position_form(event,"to","To")
	_add_section("Appearance"); var assets:=model.effect_assets();var labels:=PackedStringArray();for path in assets:labels.append(path.get_file())
	_add_choice("Texture",labels,assets,event.get("asset",""),func(v):_set_event(event,"asset",v));_add_asset_controls();_add_number("Width (pixels)",event.get("width",20),0.01,999,1,func(v):_set_event(event,"width",v));_add_number("Opacity",event.get("opacity",1),0,1,0.01,func(v):_set_event(event,"opacity",v));_add_tint(event)
	_add_section("Lifetime"); _add_number("Duration",event.get("duration",0.5),-1,99,0.01,func(v):_set_event(event,"duration",v));properties.add_child(_label("-1 persists until Destroy Sprite; 0 removes immediately."))
	_add_section("Layering"); _add_choice("Layer",["Behind Battlers","Between Battlers","Above Battlers","Below User / Above Target"],["behind_battlers","between_battlers","above_battlers","below_user_above_target"],event.get("layer","above_battlers"),func(v):_set_event(event,"layer",v))

func _vertical_sprite_form(event: Dictionary) -> void:
	_add_section("Instance / Asset");_add_text("Instance ID",event.get("instance_id","vertical_effect"),func(v):_set_event(event,"instance_id",v,true));var assets:=model.effect_assets();var labels:=PackedStringArray();for path in assets:labels.append(path.get_file())
	_add_choice("Asset",labels,assets,event.get("asset",""),func(v):_set_event(event,"asset",v));_add_asset_controls()
	_add_section("Placement");_position_form(event,"position","Anchor");_add_choice("Mode",["Fall To Anchor","Rise From Anchor"],["fall_to_anchor","rise_from_anchor"],event.get("mode","fall_to_anchor"),func(v):_set_event(event,"mode",v));_add_number("Distance (pixels)",event.get("distance",120),0.01,9999,1,func(v):_set_event(event,"distance",v));_add_number("Duration",event.get("duration",0.6),0,99,0.01,func(v):_set_event(event,"duration",v))
	_add_section("Appearance");_add_number("Scale",event.get("scale",1),0.01,20,0.01,func(v):_set_event(event,"scale",v));_add_number("Rotation (degrees)",event.get("rotation",0),-3600,3600,1,func(v):_set_event(event,"rotation",v));_add_number("Opacity",event.get("opacity",1),0,1,0.01,func(v):_set_event(event,"opacity",v));_add_tint(event);_add_bool("Is Behind",bool(event.get("is_behind",false)),func(v):_set_event(event,"is_behind",v))

func _scale_battler_form(event: Dictionary) -> void:
	_add_choice("Owner",["User","Target"],["user","target"],event.get("battler","user"),func(v):_set_event(event,"battler",v));_add_choice("Mode",["Stretch","Shrink"],["stretch","shrink"],event.get("mode","stretch"),func(v):_set_event(event,"mode",v));_add_number("Scale Change (%)",event.get("scale_delta_percent",50),0.01,1000,1,func(v):_set_event(event,"scale_delta_percent",v));_add_number("Loops",event.get("loops",1),1,100,1,func(v):_set_event(event,"loops",int(v)));_add_number("Loop Duration",event.get("loop_duration",0.4),0.01,99,0.01,func(v):_set_event(event,"loop_duration",v));properties.add_child(_label("Each loop reaches the temporary scale halfway through, then restores it."))

func _add_section(text: String) -> void:
	var heading:=Label.new();heading.text=text;heading.add_theme_font_size_override("font_size",16);properties.add_child(heading)

func _add_asset_controls() -> void:
	var row:=HBoxContainer.new();properties.add_child(row);_add_button(row,"Refresh Assets",_build_properties);_add_button(row,"Import PNG…",func():import_dialog.popup_centered_ratio(0.8))

func _import_png(source_path: String) -> void:
	var result:=model.import_effect_asset(source_path)
	if int(result.get("error",FAILED))!=OK:_status("Import error: %s"%result.get("message","Unknown error"),true);return
	var import_result:=model.trigger_godot_import();_build_properties()
	if int(import_result.get("error",FAILED))!=OK:_status("%s, but Godot could not generate import metadata."%result["message"],true);return
	_status("%s and generated Godot import metadata."%result["message"])

func _position_form(event:Dictionary,key:String,prefix:String)->void:
	var position:Dictionary=event.get(key,{"battler":"user","anchor":"origin","offset":[0,0]});event[key]=position;_add_choice("%s Battler"%prefix,["User","Target"],["user","target"],position.get("battler","user"),func(v):position["battler"]=v;_build_properties();_changed())
	var values:=_anchor_values(String(position.get("battler","user")));var labels:=PackedStringArray();var present:=_present_anchors(String(position.get("battler","user")));for anchor in values:labels.append(_friendly_anchor(anchor) if present.has(anchor) else "%s (fallback → Origin)"%_friendly_anchor(anchor))
	_add_choice("%s Anchor"%prefix,labels,values,position.get("anchor","origin"),func(v):position["anchor"]=v;_changed());var offset:Array=position.get("offset",[0,0]);if offset.size()!=2:offset=[0,0]
	position["offset"]=offset;_add_number("Offset X",offset[0],-9999,9999,1,func(v):offset[0]=v;_changed());_add_number("Offset Y",offset[1],-9999,9999,1,func(v):offset[1]=v;_changed())

func _add_instance(event:Dictionary)->void:
	var ids:=model.spawn_instance_ids();var current:=String(event.get("instance_id",""));if not current.is_empty() and not ids.has(current):ids.append(current)
	if ids.is_empty():properties.add_child(_label("Effect Instance: No spawned effects available"));return
	_add_choice("Effect Instance",ids,ids,current,func(v):_set_event(event,"instance_id",v))
func _add_battler(event:Dictionary)->void:_add_choice("Battler",["User","Target"],["user","target"],event.get("battler","target"),func(v):_set_event(event,"battler",v))
func _add_color(event:Dictionary)->void:var row:=_field_row("Color");var picker:=ColorPickerButton.new();picker.color=Color(String(event.get("color","#663399")));picker.color_changed.connect(func(v):_set_event(event,"color",v.to_html(false)));row.add_child(picker)
func _add_tint(event:Dictionary)->void:var row:=_field_row("Tint");var picker:=ColorPickerButton.new();picker.color=Color(String(event.get("tint","#FFFFFF")));picker.color_changed.connect(func(v):_set_event(event,"tint","#"+v.to_html(false)));row.add_child(picker)
func _add_text(label_text:String,value:Variant,callback:Callable)->void:var row:=_field_row(label_text);var edit:=LineEdit.new();edit.text=String(value);edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;edit.text_changed.connect(callback);row.add_child(edit)
func _add_number(label_text:String,value:Variant,min_value:float,max_value:float,step:float,callback:Callable)->void:var row:=_field_row(label_text);var spin:=SpinBox.new();spin.min_value=min_value;spin.max_value=max_value;spin.step=step;spin.value=float(value);spin.allow_greater=true;spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL;spin.value_changed.connect(callback);row.add_child(spin)
func _add_bool(label_text:String,value:bool,callback:Callable)->void:var row:=_field_row(label_text);var check:=CheckBox.new();check.button_pressed=value;check.toggled.connect(callback);row.add_child(check)
func _add_choice(label_text:String,labels:PackedStringArray,values:PackedStringArray,current:Variant,callback:Callable)->void:
	var row:=_field_row(label_text);var option:=OptionButton.new();option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for index in values.size():option.add_item(labels[index]);option.set_item_metadata(index,values[index]);if String(values[index])==String(current):option.select(index)
	option.item_selected.connect(func(index):callback.call(option.get_item_metadata(index)));row.add_child(option)
func _field_row(label_text:String)->HBoxContainer:var row:=HBoxContainer.new();var label:=Label.new();label.text=label_text;label.custom_minimum_size.x=150;row.add_child(label);properties.add_child(row);return row
func _set_event(event:Dictionary,key:String,value:Variant,resync:=false)->void:event[key]=value;_changed();if resync:_sync_events()
func _changed()->void:model.sort_events();_sync_events();_refresh_validation()
func _anchor_values(battler:String)->PackedStringArray:
	var result:=PackedStringArray(BASE_ANCHORS);for anchor in _present_anchors(battler):
		if not result.has(anchor):result.append(anchor)
	return result
func _present_anchors(battler:String)->PackedStringArray:var art:=user_select.get_item_text(user_select.selected) if battler=="user" else target_select.get_item_text(target_select.selected);var side:=user_side.get_item_text(user_side.selected) if battler=="user" else target_side.get_item_text(target_side.selected);return repository.get_anchor_names(art,side)
func _friendly_anchor(value:String)->String:return value.replace("_"," ").capitalize()
func _refresh_validation()->void:
	var text:=model.validation_text()
	if text.begins_with("Valid") and not _discovery_warnings.is_empty():text += "\nWarning: " + "\n".join(_discovery_warnings)
	validation_label.text=text;validation_label.modulate=Color("#7ce38b") if text.begins_with("Valid") else Color("#ff7777")
func _status(text:String,is_error:=false)->void:validation_label.text=text;validation_label.modulate=Color("#ff7777") if is_error else Color("#7ce38b")
func _rebuild_preview()->void:
	if user_sprite==null:return
	_setup_sprite(user_sprite,user_select.get_item_text(user_select.selected),user_side.get_item_text(user_side.selected),Vector2(70,165));_setup_sprite(target_sprite,target_select.get_item_text(target_select.selected),target_side.get_item_text(target_side.selected),Vector2(325,40))
func _setup_sprite(sprite:TextureRect,art_id:String,side:String,position:Vector2)->void:var texture:=load("res://assets/fakemon/battle/%s_%s.png"%[art_id,side]) as Texture2D;sprite.texture=texture;sprite.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;sprite.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;sprite.size=BattleSpriteGeometry.processed_size(texture.get_size()) if texture!=null else Vector2(125,125);sprite.position=position
func _play()->void:
	if not model.document.validation_errors().is_empty():_refresh_validation();return
	var context:=MoveAnimationContext.new();context.user=user_sprite;context.target=target_sprite;context.user_art_id=user_select.get_item_text(user_select.selected);context.target_art_id=target_select.get_item_text(target_select.selected);context.user_effect_data=species_effect_data.get(context.user_art_id,{}).duplicate(true);context.target_effect_data=species_effect_data.get(context.target_art_id,{}).duplicate(true);context.user_side=user_side.get_item_text(user_side.selected);context.target_side=target_side.get_item_text(target_side.selected);context.anchor_repository=repository;context.effect_layer=effect_layer;context.background_overlay=overlay;player.play(model.document,context)
	var warnings:=_preview_anchor_warnings()
	if not warnings.is_empty():_status("Preview warning:\n"+"\n".join(warnings),false)

func _preview_anchor_warnings()->PackedStringArray:
	return model.preview_anchor_warnings(repository,{"user":{"art_id":user_select.get_item_text(user_select.selected),"side":user_side.get_item_text(user_side.selected)},"target":{"art_id":target_select.get_item_text(target_select.selected),"side":target_side.get_item_text(target_side.selected)}})
func _show_raw()->void:raw_text.text=JSON.stringify(model.document.data,"  ");raw_dialog.popup_centered()
func _show_reference()->void:help_dialog.popup_centered()
func _battle_species()->PackedStringArray:
	var result:=PackedStringArray();var directory:=DirAccess.open("res://assets/fakemon/battle");if directory==null:return result
	directory.list_dir_begin();var filename:=directory.get_next();while not filename.is_empty():
		if filename.ends_with("_Player.png") and not filename.ends_with(".anchors.png"):result.append(filename.trim_suffix("_Player.png"))
		filename=directory.get_next()
	directory.list_dir_end();result.sort();return result
func _load_species_effect_data()->void:
	species_effect_data.clear()
	var sources:Array=[]
	var battle_value:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/battle_data.json"));if battle_value is Dictionary:sources.append_array(battle_value.get("fakemon",[]))
	var evolved_value:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/evolved_fakemon.json"));if evolved_value is Array:sources.append_array(evolved_value)
	for species:Dictionary in sources:species_effect_data[String(species.get("art_id",""))]=species.duplicate(true)
func _option(items:PackedStringArray,selected_value:String)->OptionButton:
	var result:=OptionButton.new()
	for item in items:
		result.add_item(item)
		if item==selected_value:result.select(result.item_count-1)
	return result
func _label(text:String)->Label:var result:=Label.new();result.text=text;return result
func _add_button(parent:Node,text:String,callback:Callable)->Button:var result:=Button.new();result.text=text;result.pressed.connect(callback);parent.add_child(result);return result
