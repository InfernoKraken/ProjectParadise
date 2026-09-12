class_name MoveEffectImportPanel
extends VBoxContainer

var model := MoveAnimationEditorModel.new()
var asset_list: ItemList
var summary_label: Label
var status_label: Label
var entries: Array[Dictionary] = []

func _ready() -> void:
	var toolbar:=HBoxContainer.new();add_child(toolbar)
	_add_button(toolbar,"Refresh",refresh)
	_add_button(toolbar,"Import Selected",_import_selected)
	_add_button(toolbar,"Import Missing",_import_missing)
	summary_label=Label.new();summary_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(summary_label)
	asset_list=ItemList.new();asset_list.size_flags_vertical=Control.SIZE_EXPAND_FILL;asset_list.fixed_icon_size=Vector2i(56,56);asset_list.icon_mode=ItemList.ICON_MODE_LEFT;add_child(asset_list)
	status_label=Label.new();status_label.custom_minimum_size.y=28;status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(status_label)
	refresh()

func refresh() -> void:
	var selected_path := ""
	var selected:=asset_list.get_selected_items() if asset_list!=null else PackedInt32Array()
	if not selected.is_empty() and selected[0]<entries.size():selected_path=String(entries[selected[0]]["path"])
	entries=model.effect_import_entries();asset_list.clear();var imported:=0;var warnings:=0;var restored:=-1
	for index in entries.size():
		var entry:=entries[index];if bool(entry["imported"]):imported+=1;if not String(entry["warning"]).is_empty():warnings+=1
		var warning_text:="" if String(entry["warning"]).is_empty() else "\nWarning: %s"%entry["warning"]
		asset_list.add_item("%s\n%s\n%s%s"%[entry["filename"],entry["path"],entry["status"],warning_text],_preview(String(entry["path"])))
		asset_list.set_item_metadata(index,entry["path"]);if entry["path"]==selected_path:restored=index
	if restored>=0:asset_list.select(restored);asset_list.ensure_current_is_visible()
	summary_label.text="%d move/weather PNGs • %d Imported • %d Missing/Error • %d Warnings"%[entries.size(),imported,entries.size()-imported,warnings]

func _import_selected() -> void:
	var selected:=asset_list.get_selected_items();if selected.is_empty():_status("Select a PNG first.",true);return
	var entry:=entries[selected[0]];if bool(entry["imported"]):_status("%s is already imported and usable."%entry["filename"]);return
	_run_import("Importing %s with Godot…"%entry["filename"])

func _import_missing() -> void:
	var missing:=entries.filter(func(entry):return not bool(entry["imported"]));if missing.is_empty():_status("All move-effect and weather PNGs are imported and usable.");return
	_run_import("Importing %d missing or broken PNGs with Godot…"%missing.size())

func _run_import(progress_text:String)->void:
	_status(progress_text);var result:=model.trigger_godot_import();refresh()
	var remaining:=entries.filter(func(entry):return not bool(entry["imported"])).size()
	if int(result["error"])!=OK:_status("Godot importer failed (exit %d). %d PNGs remain unavailable."%[result["exit_code"],remaining],true)
	elif remaining>0:_status("Godot import completed; %d PNGs still have import errors. Refresh for details."%remaining,true)
	else:_status("Godot import completed. All move-effect and weather PNGs are usable.")

func _preview(path:String)->Texture2D:
	if ResourceLoader.exists(path,"Texture2D"):return ResourceLoader.load(path,"Texture2D") as Texture2D
	var image:=Image.load_from_file(ProjectSettings.globalize_path(path));return ImageTexture.create_from_image(image) if image!=null and not image.is_empty() else null

func _status(text:String,error:=false)->void:status_label.text=text;status_label.modulate=Color("#ff7777") if error else Color("#7ce38b")
func _add_button(parent:Node,text:String,callback:Callable)->void:var button:=Button.new();button.text=text;button.pressed.connect(callback);parent.add_child(button)
