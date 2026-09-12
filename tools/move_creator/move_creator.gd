extends Control

const ANIMATION_SCENE := preload("res://tools/move_creator/move_animation_editor.tscn")
const IMPORT_PANEL_SCRIPT := preload("res://tools/move_creator/move_effect_import_panel.gd")
const WEATHER_EDITOR_SCRIPT := preload("res://tools/move_creator/weather_editor.gd")
var model := MoveCreatorModel.new()
var move_select: OptionButton; var id_label: Label; var dirty_label: Label; var description_warning_label: Label; var status_label: Label; var tabs: TabContainer
var move_form: VBoxContainer; var stat_rows: VBoxContainer; var unknown_text: TextEdit; var animation_choice: OptionButton
var animation_editor: Control; var new_dialog: ConfirmationDialog; var new_id: LineEdit; var new_name: LineEdit; var new_type: OptionButton; var new_class: OptionButton
var delete_move_dialog: ConfirmationDialog; var delete_animation_dialog: ConfirmationDialog; var _orphan_animation_id := ""
var _pending_action: Callable
var _animation_assignment_target := "initial"

func _ready()->void:
	# Authoring tools need physical window dimensions; game canvas stretching makes fullscreen controls enormous.
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	var error:=model.load_database()
	if error!=OK:push_error("Move Creator could not load battle data: %s"%error_string(error));return
	_build_ui();_refresh_moves();if move_select.item_count>0:_load_selected(true)

func _build_ui()->void:
	var outer:=VBoxContainer.new();outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(outer)
	var title:=Label.new();title.text="Move Creator v0.1";title.add_theme_font_size_override("font_size",26);outer.add_child(title)
	var toolbar:=HBoxContainer.new();outer.add_child(toolbar);toolbar.add_child(_label("Move:"));move_select=OptionButton.new();move_select.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(move_select);_button(toolbar,"Load",func():_request_action(func():_load_selected(true)));_button(toolbar,"New Move",func():_request_action(_show_new_dialog));_button(toolbar,"Save Move",_save_move);_button(toolbar,"Delete Move",func():_request_action(_request_delete_move));_button(toolbar,"Refresh",_refresh_moves)
	var identity:=HBoxContainer.new();outer.add_child(identity);id_label=_label("Move ID: —");id_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;identity.add_child(id_label);dirty_label=_label("");identity.add_child(dirty_label)
	description_warning_label=_label("");description_warning_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;outer.add_child(description_warning_label)
	tabs=TabContainer.new();tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;outer.add_child(tabs)
	var data_scroll:=ScrollContainer.new();data_scroll.name="Move Data";tabs.add_child(data_scroll);move_form=VBoxContainer.new();move_form.size_flags_horizontal=Control.SIZE_EXPAND_FILL;data_scroll.add_child(move_form)
	var animation_panel:=VBoxContainer.new();animation_panel.name="Animation";animation_panel.clip_contents=true;tabs.add_child(animation_panel);var animation_header:=HBoxContainer.new();animation_panel.add_child(animation_header);var context:=Label.new();context.name="MoveContext";context.size_flags_horizontal=Control.SIZE_EXPAND_FILL;animation_header.add_child(context);_button(animation_header,"Assign to Move",_assign_current_animation)
	animation_editor=ANIMATION_SCENE.instantiate();animation_editor.embedded_mode=true;animation_editor.size_flags_horizontal=Control.SIZE_EXPAND_FILL;animation_editor.size_flags_vertical=Control.SIZE_EXPAND_FILL;animation_panel.add_child(animation_editor)
	var weather_panel:=VBoxContainer.new();weather_panel.name="Weather";weather_panel.set_script(WEATHER_EDITOR_SCRIPT);tabs.add_child(weather_panel)
	var import_panel:=VBoxContainer.new();import_panel.name="Import";import_panel.set_script(IMPORT_PANEL_SCRIPT);tabs.add_child(import_panel)
	status_label=Label.new();status_label.custom_minimum_size.y=24;status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;outer.add_child(status_label);_build_new_dialog();_build_delete_dialogs()

func _build_new_dialog()->void:
	new_dialog=ConfirmationDialog.new();new_dialog.title="New Move";add_child(new_dialog);var form:=VBoxContainer.new();new_dialog.add_child(form);form.add_child(_label("Move ID (lowercase_snake_case)"));new_id=LineEdit.new();form.add_child(new_id);form.add_child(_label("Name"));new_name=LineEdit.new();form.add_child(new_name);form.add_child(_label("Type"));new_type=_option(model.types(),model.types()[0]);form.add_child(new_type);form.add_child(_label("Damage Class"));new_class=_option(MoveCreatorModel.DAMAGE_CLASSES,"Physical");form.add_child(new_class);new_dialog.confirmed.connect(_create_move)

func _build_delete_dialogs()->void:
	delete_move_dialog=ConfirmationDialog.new();delete_move_dialog.title="Delete Move";delete_move_dialog.ok_button_text="Delete Move";add_child(delete_move_dialog);delete_move_dialog.confirmed.connect(_confirm_delete_move)
	delete_animation_dialog=ConfirmationDialog.new();delete_animation_dialog.title="Unreferenced Animation";delete_animation_dialog.ok_button_text="Delete Animation";add_child(delete_animation_dialog);delete_animation_dialog.confirmed.connect(_confirm_delete_animation);delete_animation_dialog.canceled.connect(func():_orphan_animation_id="")

func _refresh_moves(select_id:="")->void:
	move_select.clear()
	var missing_descriptions:=model.missing_description_move_ids()
	for move_id in model.move_ids():move_select.add_item(("⚠ " if missing_descriptions.has(move_id) else "")+model.display_label(move_id));move_select.set_item_metadata(move_select.item_count-1,move_id);if move_id==select_id:move_select.select(move_select.item_count-1)
	_update_description_warning()

func _update_description_warning()->void:
	var missing:=model.missing_description_move_ids()
	if missing.is_empty():description_warning_label.text="All moves have descriptions.";description_warning_label.modulate=Color("#7ce38b");return
	var names:=PackedStringArray()
	for move_id in missing:names.append(model.display_label(move_id))
	var preview_names:=names.slice(0,mini(8,names.size()))
	var remainder:="" if names.size()<=8 else " (+%d more)"%(names.size()-8)
	description_warning_label.text="⚠ %d move%s missing a description: %s%s"%[missing.size()," is" if missing.size()==1 else "s are",", ".join(preview_names),remainder]
	description_warning_label.modulate=Color("#ffd166")

func _load_selected(_force:=false)->void:
	if move_select.item_count==0:return
	var move_id:=String(move_select.get_item_metadata(move_select.selected));if model.select_move(move_id):_build_move_form();_status("Loaded %s."%model.display_label(move_id),false)

func _build_move_form()->void:
	for child in move_form.get_children():child.queue_free()
	id_label.text="Move ID: %s"%model.selected_id;_update_dirty();var move:=model.selected_move
	_text_field("Name",move.get("name",""),func(v):model.set_field("name",v);_changed())
	_multiline_field("Description",move.get("description",""),func(v):model.set_field("description",v);_changed())
	_number_field("Power",move.get("power",0),0,9999,1,func(v):model.set_field("power",int(v));_changed())
	_choice_field("Type",model.types(),model.types(),move.get("type",""),func(v):model.set_field("type",v);_changed())
	_choice_field("Damage Class",MoveCreatorModel.DAMAGE_CLASSES,MoveCreatorModel.DAMAGE_CLASSES,move.get("damage_class",""),func(v):model.set_field("damage_class",v);_changed())
	var animation_ids:=_animation_ids();var animation_labels:=PackedStringArray(["None / Use Fallback"]);var animation_values:=PackedStringArray([""]);animation_labels.append_array(animation_ids);animation_values.append_array(animation_ids);animation_choice=_choice_field("Initial Move Animation",animation_labels,animation_values,move.get("animation_id",""),func(v):model.set_field("animation_id",v);_changed())
	var animation_actions:=HBoxContainer.new();move_form.add_child(animation_actions);_button(animation_actions,"Edit Animation",_edit_animation);_button(animation_actions,"New Animation",_new_animation)
	var fallback_labels:=PackedStringArray(["None"]);fallback_labels.append_array(MoveCreatorModel.FALLBACK_ANIMATIONS);var fallback_values:=PackedStringArray([""]);fallback_values.append_array(MoveCreatorModel.FALLBACK_ANIMATIONS);_choice_field("Fallback Animation",fallback_labels,fallback_values,move.get("fallback_animation",move.get("animation_kind","")),func(v):model.set_field("fallback_animation",v);_changed())
	var conditions:=PackedStringArray(["None"]);conditions.append_array(model.conditions());var condition_values:=PackedStringArray([""]);condition_values.append_array(model.conditions());_choice_field("Condition",conditions,condition_values,move.get("condition",""),func(v):model.set_field("condition",v);if String(v).is_empty():model.set_field("condition_chance",null);_changed();_build_move_form())
	if not String(move.get("condition","")).is_empty():_number_field("Condition Chance",move.get("condition_chance",1.0),0,1,0.01,func(v):model.set_field("condition_chance",v);_changed())
	_number_field("Priority",move.get("priority",0),-10,10,1,func(v):model.set_field("priority",int(v));_changed())
	_build_multi_hit_section()
	_build_scheduled_effect_section(animation_ids)
	var stat_title:=Label.new();stat_title.text="Stat Changes";stat_title.add_theme_font_size_override("font_size",18);move_form.add_child(stat_title);stat_rows=VBoxContainer.new();move_form.add_child(stat_rows);_build_stat_rows();_button(move_form,"Add Stat Change",func():model.add_stat_change();_build_move_form())
	var unknown:=model.unknown_fields();var unknown_title:=Label.new();unknown_title.text="Additional Engine Fields (JSON key-value module)";unknown_title.add_theme_font_size_override("font_size",18);move_form.add_child(unknown_title);unknown_text=TextEdit.new();unknown_text.custom_minimum_size.y=160;unknown_text.text=JSON.stringify(unknown,"  ");move_form.add_child(unknown_text)
	_button(move_form,"Apply Additional JSON Fields",_apply_additional_fields)
	_button(move_form,"Edit Full Raw Move JSON",_show_raw_move)
	var context:=tabs.get_node_or_null("Animation/MoveContext") as Label;if context!=null:context.text="Editing move: %s    Animation: %s"%[move.get("name",model.selected_id),move.get("animation_id","None / fallback")]

func _build_multi_hit_section()->void:
	_section("Multi-Hit");_check_field("Enabled",model.multi_hit_enabled(),func(enabled):model.set_multi_hit_enabled(enabled);_build_move_form();_changed())
	if not model.multi_hit_enabled():return
	_number_field("Minimum Hits",model.selected_move.get("min_hits",2),1,99,1,func(v):model.set_field("min_hits",int(v));_changed())
	_number_field("Maximum Hits",model.selected_move.get("max_hits",2),1,99,1,func(v):model.set_field("max_hits",int(v));_changed())
	move_form.add_child(_label("Each hit resolves separately. The Initial Move Animation is reused by the battle sequencer."))

func _build_scheduled_effect_section(animation_ids:PackedStringArray)->void:
	_section("Scheduled Effect");_check_field("Creates Scheduled Effect",model.scheduled_effect_enabled(),func(enabled):model.set_scheduled_effect_enabled(enabled);_build_move_form();_changed())
	if not model.scheduled_effect_enabled():return
	var recipe:Dictionary=model.selected_move["scheduled_effect"]
	_text_field("Effect ID",recipe.get("effect_id",""),func(v):model.set_scheduled_effect_field("effect_id",v);_changed());var known_ids:=model.effect_ids();move_form.add_child(_label("Known IDs: %s. The engine has no closed effect-ID registry."%(", ".join(known_ids) if not known_ids.is_empty() else "none")))
	_choice_field("Owner",PackedStringArray(["User Battler","Target Battler","Battle"]),model.effect_owners(),recipe.get("owner","target_battler"),func(v):model.set_scheduled_effect_field("owner",v);_changed())
	_choice_field("Trigger",PackedStringArray(["Start of Turn","End of Turn"]),model.effect_triggers(),recipe.get("trigger","end_of_turn"),func(v):model.set_scheduled_effect_field("trigger",v);_changed())
	_number_field("Delay Turns",recipe.get("delay_turns",0),0,99,1,func(v):model.set_scheduled_effect_field("delay_turns",int(v));_changed());_number_field("Repeat Count",recipe.get("repeat_count",1),1,99,1,func(v):model.set_scheduled_effect_field("repeat_count",int(v));_changed())
	_text_field("Effect Group",recipe.get("effect_group",""),func(v):model.set_scheduled_effect_field("effect_group",v);_changed());var known_groups:=model.effect_groups();move_form.add_child(_label("Known groups: %s"%(", ".join(known_groups) if not known_groups.is_empty() else "none")))
	_choice_field("Stacking",PackedStringArray(["Replace Existing In Group"]),PackedStringArray(["replace_group"]),recipe.get("stacking","replace_group"),func(v):model.set_scheduled_effect_field("stacking",v);_changed())
	var payload:Dictionary=recipe.get("payload",{});_choice_field("Payload",PackedStringArray(["Heal","Damage","Condition","Stat Change"]),model.effect_payload_kinds(),payload.get("kind","heal"),func(v):model.set_scheduled_payload_kind(v);_build_move_form();_changed())
	match String(payload.get("kind","")):
		"heal", "damage":_number_field("Payload Amount",payload.get("amount",0.1),0,9999,0.01,func(v):model.set_scheduled_payload_field("amount",v);_changed())
		"condition":_choice_field("Payload Condition",model.conditions(),model.conditions(),payload.get("condition",""),func(v):model.set_scheduled_payload_field("condition",v);_changed());_number_field("Payload Chance",payload.get("chance",1.0),0,1,0.01,func(v):model.set_scheduled_payload_field("chance",v);_changed())
		"stat_change":_choice_field("Payload Stat",MoveCreatorModel.STATS,MoveCreatorModel.STATS,payload.get("stat","attack"),func(v):model.set_scheduled_payload_field("stat",v);_changed());_number_field("Payload Amount",payload.get("amount",0.1),-10,10,0.05,func(v):model.set_scheduled_payload_field("amount",v);_changed())
	var effect_labels:=PackedStringArray(["None"]);var effect_values:=PackedStringArray([""]);effect_labels.append_array(animation_ids);effect_values.append_array(animation_ids);_choice_field("Activation Animation",effect_labels,effect_values,recipe.get("animation_id",""),func(v):model.set_scheduled_effect_field("animation_id",v);_changed())
	var actions:=HBoxContainer.new();move_form.add_child(actions);_button(actions,"Edit Activation Animation",_edit_effect_animation);_button(actions,"New Activation Animation",_new_effect_animation)

func _build_stat_rows()->void:
	for child in stat_rows.get_children():child.queue_free()
	var changes:Array=model.selected_move.get("stat_changes",[])
	for index in changes.size():
		var row:=HBoxContainer.new();stat_rows.add_child(row);var change:Dictionary=changes[index];var stat:=_option(MoveCreatorModel.STATS,String(change.get("stat","attack")));row.add_child(stat);var amount:=SpinBox.new();amount.min_value=-10;amount.max_value=10;amount.step=0.05;amount.value=float(change.get("amount",0.1));row.add_child(amount);stat.item_selected.connect(func(_i,idx=index,s=stat,a=amount):model.set_stat_change(idx,s.get_item_text(s.selected),a.value);_changed());amount.value_changed.connect(func(_v,idx=index,s=stat,a=amount):model.set_stat_change(idx,s.get_item_text(s.selected),a.value);_changed());_button(row,"Remove",func(idx=index):model.remove_stat_change(idx);_build_move_form())

func _save_move()->void:
	var errors:=model.validation_errors(_animation_ids());if not errors.is_empty():_status("Move errors:\n"+"\n".join(errors),true);return
	var error:=model.save(_animation_ids());if error!=OK:_status("Save failed: %s"%error_string(error),true);return
	_refresh_moves(model.selected_id);_update_dirty();_status("Saved move '%s' without rewriting animation data."%model.selected_id,false)

func _show_new_dialog()->void:new_id.text="";new_name.text="";new_dialog.popup_centered()
func _create_move()->void:
	var errors:=model.create_move(new_id.text,new_name.text,new_type.get_item_text(new_type.selected),new_class.get_item_text(new_class.selected));if not errors.is_empty():_status("New move errors:\n"+"\n".join(errors),true);return
	_build_move_form();_status("New move is unsaved. Complete its fields, then Save Move.",false)

func _request_delete_move()->void:
	if model.selected_id.is_empty():_status("Select a saved move to delete.",true);return
	delete_move_dialog.dialog_text="Delete move '%s' (%s)?\n\nThis removes the move entry. Shared animations and all PNG assets are preserved."%[model.selected_move.get("name",model.selected_id),model.selected_id];delete_move_dialog.popup_centered()

func _confirm_delete_move()->void:
	var deleted_id:=model.selected_id;var animation_id:=String(model.selected_move.get("animation_id",""));var remaining_references:=model.animation_reference_count(animation_id,deleted_id)
	var error:=model.delete_selected_move();if error!=OK:_status("Delete failed: %s"%error_string(error),true);return
	_refresh_moves();if move_select.item_count>0:_load_selected(true)
	if MoveAnimationDefinition.is_valid_animation_id(animation_id) and remaining_references==0 and FileAccess.file_exists("%s/%s.json"%[MoveCreatorModel.ANIMATION_DIR,animation_id]):
		_orphan_animation_id=animation_id;delete_animation_dialog.dialog_text="Also delete unreferenced animation %s?\n\nMove-effect PNG assets will not be deleted."%animation_id;delete_animation_dialog.popup_centered();_status("Deleted move '%s'. Animation '%s' is now unreferenced."%[deleted_id,animation_id],false)
	elif not animation_id.is_empty() and remaining_references>0:_status("Deleted move '%s'. Preserved shared animation '%s' (%d remaining reference%s)."%[deleted_id,animation_id,remaining_references,"" if remaining_references==1 else "s"],false)
	else:_status("Deleted move '%s'."%deleted_id,false)

func _confirm_delete_animation()->void:
	var animation_id:=_orphan_animation_id;_orphan_animation_id=""
	if animation_id.is_empty() or model.animation_reference_count(animation_id)>0:_status("Animation deletion cancelled because it is referenced by a move.",true);return
	var path:="%s/%s.json"%[MoveCreatorModel.ANIMATION_DIR,animation_id]
	if not MoveAnimationDefinition.is_valid_animation_id(animation_id) or not FileAccess.file_exists(path):_status("Animation '%s' is already absent."%animation_id,true);return
	var error:=DirAccess.remove_absolute(ProjectSettings.globalize_path(path));if error!=OK:_status("Animation delete failed: %s"%error_string(error),true);return
	if String(animation_editor.model.document.data.get("id",""))==animation_id:animation_editor._new_document()
	animation_editor._refresh_animations();_build_move_form();_status("Deleted unreferenced animation '%s'. Move-effect PNG assets were preserved."%animation_id,false)

func _edit_animation()->void:
	_animation_assignment_target="initial"
	var animation_id:=String(model.selected_move.get("animation_id",""));if animation_id.is_empty():_status("This move has no custom animation. Use New Animation or select one.",true);return
	tabs.current_tab=1;_load_animation_in_editor(animation_id)
func _new_animation()->void:
	_animation_assignment_target="initial"
	tabs.current_tab=1;animation_editor._new_document();animation_editor.id_edit.text=model.selected_id;_status("New unsaved animation suggested from move ID. Save it in the Animation tab, then use Assign Current Animation to Move.",false)

func _edit_effect_animation()->void:
	var recipe:Dictionary=model.selected_move.get("scheduled_effect",{});var animation_id:=String(recipe.get("animation_id",""));if animation_id.is_empty():_status("This Scheduled Effect has no activation animation. Use New Activation Animation or select one.",true);return
	_animation_assignment_target="scheduled_effect";tabs.current_tab=1;_load_animation_in_editor(animation_id)

func _new_effect_animation()->void:
	var recipe:Dictionary=model.selected_move.get("scheduled_effect",{});_animation_assignment_target="scheduled_effect";tabs.current_tab=1;animation_editor._new_document();animation_editor.id_edit.text="%s_activation"%String(recipe.get("effect_id",model.selected_id));_status("Save the new activation animation, then use Assign to Move. The initial move animation will remain unchanged.",false)
func _load_animation_in_editor(animation_id:String)->void:
	animation_editor._refresh_animations(animation_id)
	for index in animation_editor.animation_select.item_count:
		if animation_editor.animation_select.get_item_text(index)==animation_id:animation_editor.animation_select.select(index);animation_editor._load_document();return
	_status("Animation '%s' is missing."%animation_id,true)
func _assign_current_animation()->void:
	var animation_id:=String(animation_editor.model.document.data.get("id",""));if not _animation_ids().has(animation_id):_status("Save animation '%s' before assigning it."%animation_id,true);return
	if _animation_assignment_target=="scheduled_effect":model.set_scheduled_effect_field("animation_id",animation_id)
	else:model.set_field("animation_id",animation_id)
	_build_move_form();tabs.current_tab=0;_status("Assigned %s animation '%s'. Save Move to persist the link."%["activation" if _animation_assignment_target=="scheduled_effect" else "initial move",animation_id],false)

func _animation_ids()->PackedStringArray:return MoveAnimationEditorModel.new().discover_animations()["ids"]
func _changed()->void:_update_dirty();_validate_live()
func _update_dirty()->void:dirty_label.text="● Unsaved Move Data" if model.dirty else "Saved";dirty_label.modulate=Color("#ffd166") if model.dirty else Color("#7ce38b")
func _validate_live()->void:var errors:=model.validation_errors(_animation_ids());_status("Move data valid." if errors.is_empty() else "Move errors: "+"; ".join(errors),not errors.is_empty())
func _request_action(action:Callable)->void:
	if model.dirty:_status("Unsaved move changes. Save Move before loading or creating another move.",true);return
	action.call()
func _show_raw_move()->void:
	var dialog:=ConfirmationDialog.new();dialog.title="Edit Full Raw Move JSON";dialog.ok_button_text="Apply JSON";add_child(dialog)
	var text:=TextEdit.new();text.custom_minimum_size=Vector2(600,420);text.text=JSON.stringify(model.selected_move,"  ");dialog.add_child(text);dialog.popup_centered()
	dialog.canceled.connect(dialog.queue_free);dialog.confirmed.connect(func():_apply_full_raw_json(dialog,text))
func _apply_full_raw_json(dialog:ConfirmationDialog,text:TextEdit)->void:
	var message:=model.apply_raw_move_json(text.text)
	if message.is_empty():
		_build_move_form();_status("Applied raw move JSON. Save Move to persist it.",false)
	else:_status(message,true)
	dialog.queue_free()
func _apply_additional_fields()->void:
	var message:=model.apply_additional_fields_json(unknown_text.text)
	if not message.is_empty():_status(message,true);return
	_build_move_form();_status("Applied additional JSON fields. Save Move to persist them.",false)
func _status(text:String,error:bool)->void:status_label.text=text;status_label.modulate=Color("#ff7777") if error else Color("#7ce38b")
func _section(text:String)->void:var title:=Label.new();title.text=text;title.add_theme_font_size_override("font_size",18);move_form.add_child(title)
func _check_field(label_text:String,value:bool,callback:Callable)->CheckBox:var row:=_row(label_text);var check:=CheckBox.new();check.button_pressed=value;check.toggled.connect(callback);row.add_child(check);return check
func _text_field(label_text:String,value:Variant,callback:Callable)->LineEdit:var row:=_row(label_text);var edit:=LineEdit.new();edit.text=String(value);edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;edit.text_changed.connect(callback);row.add_child(edit);return edit
func _multiline_field(label_text:String,value:Variant,callback:Callable)->TextEdit:var row:=_row(label_text);var edit:=TextEdit.new();edit.text=String(value);edit.custom_minimum_size.y=90;edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;edit.text_changed.connect(func():callback.call(edit.text));row.add_child(edit);return edit
func _number_field(label_text:String,value:Variant,min_value:float,max_value:float,step:float,callback:Callable)->SpinBox:var row:=_row(label_text);var spin:=SpinBox.new();spin.min_value=min_value;spin.max_value=max_value;spin.step=step;spin.value=float(value);spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL;spin.value_changed.connect(callback);row.add_child(spin);return spin
func _choice_field(label_text:String,labels:PackedStringArray,values:PackedStringArray,current:Variant,callback:Callable)->OptionButton:
	var row:=_row(label_text);var option:=OptionButton.new();option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for index in values.size():
		option.add_item(labels[index]);option.set_item_metadata(index,values[index])
		if String(values[index])==String(current):option.select(index)
	option.item_selected.connect(func(index):callback.call(option.get_item_metadata(index)));row.add_child(option);return option
func _row(label_text:String)->HBoxContainer:var row:=HBoxContainer.new();move_form.add_child(row);var label:=_label(label_text);label.custom_minimum_size.x=180;row.add_child(label);return row
func _option(items:PackedStringArray,current:String)->OptionButton:
	var option:=OptionButton.new()
	for item in items:
		option.add_item(item)
		if item==current:option.select(option.item_count-1)
	return option
func _label(text:String)->Label:var label:=Label.new();label.text=text;return label
func _button(parent:Node,text:String,callback:Callable)->Button:var button:=Button.new();button.text=text;button.pressed.connect(callback);parent.add_child(button);return button
