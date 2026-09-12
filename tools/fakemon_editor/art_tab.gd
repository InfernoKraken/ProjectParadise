class_name FakemonArtTab
extends VBoxContainer

signal changed
signal message(text:String, bad:bool)

const Package:=preload("res://art_package_model.gd")
const Canvas:=preload("res://art_anchor_canvas.gd")
const KEYS:=["player","wild","down","up","right","left"]
var package:FakemonArtPackage
var id_edit:LineEdit
var package_search:LineEdit
var package_box:OptionButton
var health:RichTextLabel
var cards:Dictionary={}
var picker:FileDialog
var picking_key:=""
var side_box:OptionButton
var anchor_list:ItemList
var canvas:ArtAnchorCanvas
var anchor_status:Label
var confirm:ConfirmationDialog

func setup(game_root:String)->void:
	package=Package.new(game_root)
	_build()

func load_art(art_id:String,proposed_name:String)->void:
	var id:=art_id if not art_id.is_empty() else proposed_name
	package.load_package(id);id_edit.text=id;package_search.text="";_fill_packages("");_refresh()

func has_unsaved()->bool:return package!=null and package.is_dirty()

func _build()->void:
	var management:=VBoxContainer.new();add_child(management)
	var heading:=Label.new();heading.text="Art Package Management";heading.add_theme_font_size_override("font_size",20);management.add_child(heading)
	id_edit=LineEdit.new();id_edit.text_changed.connect(_id_changed);_row(management,"Art ID",id_edit)
	package_search=LineEdit.new();package_search.placeholder_text="Search existing packages…";package_search.text_changed.connect(_fill_packages);_row(management,"Assign Existing",package_search)
	package_box=OptionButton.new();package_box.item_selected.connect(_assign_existing);management.add_child(package_box)
	health=RichTextLabel.new();health.bbcode_enabled=true;health.fit_content=true;management.add_child(health)
	var assembly:=Label.new();assembly.text="Art Package Assembly — click a frame to stage a PNG";assembly.add_theme_font_size_override("font_size",20);add_child(assembly)
	var grid:=GridContainer.new();grid.columns=3;add_child(grid)
	for key in KEYS:_make_card(grid,key)
	var anchor_heading:=Label.new();anchor_heading.text="Integrated Battle Anchors";anchor_heading.add_theme_font_size_override("font_size",20);add_child(anchor_heading)
	var anchor_body:=HBoxContainer.new();add_child(anchor_body)
	var tools:=VBoxContainer.new();tools.custom_minimum_size.x=230;anchor_body.add_child(tools)
	side_box=OptionButton.new();side_box.add_item("Player");side_box.add_item("Wild");side_box.item_selected.connect(func(_i):_load_anchor_side());tools.add_child(side_box)
	anchor_list=ItemList.new();anchor_list.custom_minimum_size.y=240;anchor_list.item_selected.connect(_anchor_selected);tools.add_child(anchor_list)
	_button(tools,"+ Custom Anchor",_add_custom);_button(tools,"Clear Selected",_clear_anchor)
	anchor_status=Label.new();anchor_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;tools.add_child(anchor_status)
	canvas=Canvas.new();canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL;canvas.anchor_changed.connect(_anchor_changed);anchor_body.add_child(canvas)
	var write:=Button.new();write.text="Write Art Package";write.custom_minimum_size.y=48;write.pressed.connect(_request_write);add_child(write)
	var discard:=Button.new();discard.text="Discard Staged Art / Anchor Changes";discard.pressed.connect(_discard);add_child(discard)
	picker=FileDialog.new();picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.access=FileDialog.ACCESS_FILESYSTEM;picker.filters=PackedStringArray(["*.png ; PNG images"]);picker.file_selected.connect(_file_selected);add_child(picker)
	confirm=ConfirmationDialog.new();confirm.confirmed.connect(_write_confirmed);add_child(confirm)

func _make_card(parent:Control,key:String)->void:
	var card:=VBoxContainer.new();card.custom_minimum_size=Vector2(260,230);parent.add_child(card)
	var title:=Button.new();title.text=Package.MEMBERS[key].label;title.pressed.connect(_pick.bind(key));card.add_child(title)
	var file:=Label.new();file.name="File";card.add_child(file)
	var preview:=TextureRect.new();preview.name="Preview";preview.custom_minimum_size=Vector2(240,160);preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;card.add_child(preview)
	var state:=Label.new();state.name="State";card.add_child(state);cards[key]=card

func _refresh()->void:
	health.text="[b]Art Package: %s[/b]\n"%package.art_id
	for line in package.health():
		var parts:=line.split("|");var icon:="✓" if parts[0]=="OK" else "●" if parts[0]=="STAGED" else "⚠" if parts[0]=="INVALID" else "✗"
		var color:="#78dba9" if parts[0]=="OK" else "#ffbd69" if parts[0]!="MISSING" else "#ff7777";health.text+="[color=%s]%s %s[/color]\n"%[color,icon,parts[1]]
	for key in KEYS:
		var image:=package.image_for(key);var card:VBoxContainer=cards[key];card.get_node("File").text=package.path_for(key).get_file()+("  • staged" if package.staged.has(key) else "")
		card.get_node("Preview").texture=ImageTexture.create_from_image(image) if image!=null else null
		card.get_node("State").text=("%d × %d"%[image.get_width(),image.get_height()] if image!=null else "MISSING — runtime uses color placeholder")
	_load_anchor_side();changed.emit()

func _fill_packages(query:String)->void:
	if package_box==null:return
	package_box.clear();var needle:=query.to_lower()
	for id in package.package_ids():if needle.is_empty() or id.to_lower().contains(needle):package_box.add_item(id)
func _assign_existing(index:int)->void:
	var id:=package_box.get_item_text(index);package.load_package(id);id_edit.text=id;message.emit("Assigned existing package '%s' in the Fakemon draft. No files were changed."%id,false);_refresh()
func _id_changed(text:String)->void:
	if package==null:return
	package.art_id=text.strip_edges();_refresh()
func _pick(key:String)->void:picking_key=key;picker.title="Stage %s"%Package.MEMBERS[key].label;picker.popup_centered_ratio(0.7)
func _file_selected(path:String)->void:
	if package.stage(picking_key,path):message.emit("Staged %s. Nothing has been written yet."%Package.MEMBERS[picking_key].label,false);_refresh()
	else:message.emit(package.error,true)

func _load_anchor_side()->void:
	if package==null:return
	var side:=side_box.get_item_text(side_box.selected);var image:=package.image_for(side.to_lower());canvas.set_document(image,package.anchors[side]);_refresh_anchor_list()
	var warning:=package.replacement_warning(side);anchor_status.text=warning if not warning.is_empty() else "%s anchors are independent and use the displayed %s image."%[side,side]
func _refresh_anchor_list(selected:="")->void:
	anchor_list.clear();var side:=side_box.get_item_text(side_box.selected);var names:Array=Package.REQUIRED+Package.OPTIONAL
	for name in package.anchors[side]:if String(name).begins_with("custom_"):names.append(name)
	for name in names:
		anchor_list.add_item("%s %s%s"%["✓" if package.anchors[side].has(name) else "○",name," (required)" if Package.REQUIRED.has(name) else ""]);anchor_list.set_item_metadata(anchor_list.item_count-1,name)
		if name==selected:anchor_list.select(anchor_list.item_count-1)
	if anchor_list.get_selected_items().is_empty() and anchor_list.item_count>0:anchor_list.select(0)
	_anchor_selected(anchor_list.get_selected_items()[0])
func _anchor_selected(index:int)->void:canvas.selected=anchor_list.get_item_metadata(index);canvas.queue_redraw()
func _anchor_changed(name:String,point:Vector2i)->void:
	var side:=side_box.get_item_text(side_box.selected);package.set_anchor(side,name,point);canvas.anchors=package.anchors[side].duplicate(true);_refresh_anchor_list(name);anchor_status.text="%s placed at %s (staged)"%[name,point];changed.emit()
func _add_custom()->void:
	var side:=side_box.get_item_text(side_box.selected);var id:=1
	while package.anchors[side].has("custom_%d"%id):id+=1
	package.set_anchor(side,"custom_%d"%id,Vector2i.ZERO);_refresh_anchor_list("custom_%d"%id);changed.emit()
func _clear_anchor()->void:
	var side:=side_box.get_item_text(side_box.selected);var name:=String(anchor_list.get_item_metadata(anchor_list.get_selected_items()[0]))
	if Package.REQUIRED.has(name):message.emit("Required anchor '%s' cannot be cleared."%name,true);return
	package.clear_anchor(side,name);_load_anchor_side();changed.emit()

func _request_write()->void:
	if package.art_id.is_empty():message.emit("Art ID is required before writing a package.",true);return
	var affected:=package.affected_files();if affected.is_empty():message.emit("There are no staged art or anchor changes to write.",false);return
	var replaced:Array[String]=[];var created:Array[String]=[]
	for file in affected:
		var existing:=false
		for key in KEYS:if package.path_for(key).get_file()==file:existing=FileAccess.file_exists(package.path_for(key))
		for side in ["Player","Wild"]:if package.anchor_path(side).get_file()==file:existing=FileAccess.file_exists(package.anchor_path(side))
		(replaced if existing else created).append(file)
	var text:="Art package \"%s\" will write:\n"%package.art_id
	if not replaced.is_empty():text+="\nFiles replaced:\n• "+"\n• ".join(replaced)
	if not created.is_empty():text+="\n\nFiles created:\n• "+"\n• ".join(created)
	for side in ["Player","Wild"]:
		var warning:=package.replacement_warning(side);if not warning.is_empty():text+="\n\n"+warning
	text+="\n\nUnstaged package members remain unchanged. Continue?";confirm.dialog_text=text;confirm.popup_centered(Vector2i(650,500))
func _write_confirmed()->void:
	if package.write():message.emit("Art package '%s' written. Save Fakemon as well if its Art ID changed. Godot will generate normal .import metadata when the gameplay project scans the PNGs."%package.art_id,false);_refresh()
	else:message.emit(package.error,true)
func _discard()->void:
	package.load_package(package.original_art_id);id_edit.text=package.art_id;message.emit("Discarded staged Art Package and anchor changes. No files were modified.",false);_refresh()
func _row(parent:Control,label_text:String,control:Control)->void:
	var row:=HBoxContainer.new();parent.add_child(row);var label:=Label.new();label.text=label_text;label.custom_minimum_size.x=150;row.add_child(label);control.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(control)
func _button(parent:Control,text:String,callback:Callable)->void:var button:=Button.new();button.text=text;button.pressed.connect(callback);parent.add_child(button)
