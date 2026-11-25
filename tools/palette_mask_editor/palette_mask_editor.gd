extends Control
const Model := preload("res://mask_model.gd")
const Canvas := preload("res://mask_canvas.gd")
var model := Model.new()
var canvas: Control
var status: Label
var tool: OptionButton
var category: OptionButton
var brush: SpinBox
var show_review: CheckButton
var region_fields: Array[SpinBox] = []
var target_fields: Array[SpinBox] = []
var hybrid_agreement: CheckButton
var landmarks_input: LineEdit
var copy_dialog: ConfirmationDialog
var dialog: FileDialog
var quit_dialog: ConfirmationDialog

func _ready() -> void:
	var bg := ColorRect.new(); bg.color = Color("10151f"); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var root := VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT,Control.PRESET_MODE_MINSIZE,14); add_child(root)
	var title := Label.new(); title.text = "PALETTE MASK EDITOR"; title.add_theme_font_size_override("font_size",24); root.add_child(title)
	var files := HBoxContainer.new(); root.add_child(files)
	button(files,"Load source",func(): choose(0))
	button(files,"Load aligned reference",func(): choose(1))
	button(files,"Aligned Reference Copy",func(): copy_dialog.popup_centered())
	button(files,"Export PNG",func(): choose(2))
	button(files,"Undo",func(): model.undo(); refresh())
	button(files,"Redo",func(): model.redo(); refresh())
	var row := HBoxContainer.new(); root.add_child(row)
	tool = OptionButton.new()
	for text in ["Brush","Connected region fill","Erase decision","Label source sample"]: tool.add_item(text)
	row.add_child(tool)
	category = OptionButton.new()
	for text in Model.NAMES: category.add_item(text)
	row.add_child(category)
	label(row,"Brush radius"); brush = spin(row,1,20,1)
	label(row,"RGB tolerance"); var tolerance := spin(row,0,442,18)
	tolerance.value_changed.connect(func(v): model.tolerance = v)
	show_review = CheckButton.new(); show_review.text = "Review overlay"; show_review.button_pressed = true; row.add_child(show_review)
	show_review.toggled.connect(func(_v): canvas.queue_redraw())
	var sampling := HBoxContainer.new(); root.add_child(sampling)
	label(sampling,"Reference sample rectangle (x, y, width, height)")
	for v in [0,0,200,400]: region_fields.append(spin(sampling,0,16384,v))
	button(sampling,"Add reference labels",func():
		if model.reference == null: message("Load an aligned reference first."); return
		model.sample_reference(Rect2i(int(region_fields[0].value),int(region_fields[1].value),int(region_fields[2].value),int(region_fields[3].value)))
		message("Sampled rectangle only. %d source colors labeled." % model.samples.size()))
	button(sampling,"Clear samples",func(): model.samples.clear(); message("Samples cleared."))
	button(sampling,"RGB baseline",func(): model.generate(); refresh())
	var spatial_row := HBoxContainer.new(); root.add_child(spatial_row)
	label(spatial_row,"Spatial target (x,y,w,h); source = reference rectangle above")
	for v in [200,400,200,400]: target_fields.append(spin(spatial_row,0,16384,v))
	button(spatial_row,"Generate spatial target",_spatial.bind(false))
	button(spatial_row,"Hybrid experiment",_spatial.bind(true))
	var landmark_row := HBoxContainer.new(); root.add_child(landmark_row)
	label(landmark_row,"Optional landmarks: sourceX,sourceY,targetX,targetY; ... (frame-local pixels)")
	landmarks_input = LineEdit.new(); landmarks_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; landmark_row.add_child(landmarks_input)
	hybrid_agreement = CheckButton.new(); hybrid_agreement.text = "Strict hybrid agreement"; landmark_row.add_child(hybrid_agreement)
	copy_dialog = ConfirmationDialog.new(); copy_dialog.dialog_text = "Use reference as authoritative pixel-aligned labels? This replaces all current labels and corrections. Only use with the identical aligned artwork. Undo is available."; add_child(copy_dialog)
	copy_dialog.confirmed.connect(func():
		var error := model.copy_aligned_reference(); refresh()
		message(error if not error.is_empty() else "Copied aligned reference exactly. All pixels confirmed; undo available."))
	canvas = Canvas.new(); canvas.editor = self; canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL; canvas.mouse_filter = Control.MOUSE_FILTER_STOP; root.add_child(canvas)
	label(root,"Wheel: synchronized zoom · Middle drag: pan · Left drag: paint · Ctrl+Z / Ctrl+Y · Erase restores uncertainty · White labels opaque backgrounds explicitly")
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.custom_minimum_size.y = 50; root.add_child(status)
	message("Load source, label representative colors or sample reference rectangles, then generate. Ambiguous colors require review.")
	dialog = FileDialog.new(); dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.filters = PackedStringArray(["*.png ; PNG images"]); add_child(dialog)
	quit_dialog = ConfirmationDialog.new(); quit_dialog.dialog_text = "Close editor? In-memory work will be discarded."; quit_dialog.confirmed.connect(func(): get_tree().quit()); add_child(quit_dialog)

func button(parent: Node, text: String, action: Callable) -> void:
	var b := Button.new(); b.text = text; b.pressed.connect(action); parent.add_child(b)
func label(parent: Node, text: String) -> void:
	var l := Label.new(); l.text = text; parent.add_child(l)
func spin(parent: Node, minimum: float, maximum: float, value: float) -> SpinBox:
	var s := SpinBox.new(); s.min_value = minimum; s.max_value = maximum; s.value = value; s.custom_minimum_size.x = 85; parent.add_child(s); return s
func message(text: String) -> void: status.text = text
func refresh() -> void: canvas.refresh(); update_status()
func update_status() -> void:
	if model.source == null: return
	var error := model.validate()
	message("%s · %s · %d sampled colors" % [model.source.get_size(),"Ready to export" if error.is_empty() else error,model.samples.size()])
func choose(mode: int) -> void:
	if mode == 2:
		var error := model.validate()
		if not error.is_empty(): message(error); return
	for connection in dialog.file_selected.get_connections(): dialog.file_selected.disconnect(connection.callable)
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if mode == 2 else FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = ["Load source PNG (preserved)","Load reference PNG (preserved)","Export to NEW mask PNG"][mode]
	dialog.file_selected.connect(func(path):
		var error: String
		if mode == 0: error = model.load_source(path)
		elif mode == 1: error = model.load_reference(path)
		else: error = model.export_png(path)
		refresh()
		if not error.is_empty(): message(error)
		elif mode == 2: message("Exported exact RGB mask: " + path)
		elif mode == 1: message("Reference loaded. Choose aligned copy, RGB sampling, or a labeled source frame for spatial transfer."))
	dialog.popup_centered_ratio(0.75)
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_Z: model.undo(); refresh()
		elif event.keycode == KEY_Y: model.redo(); refresh()
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if model.source != null: quit_dialog.popup_centered()
		else: get_tree().quit()

func _spatial(hybrid := false) -> void:
	var landmarks := []
	if not landmarks_input.text.strip_edges().is_empty():
		for entry in landmarks_input.text.split(";",false):
			var parts := entry.split(",")
			if parts.size() != 4: message("Each landmark needs four frame-local numbers."); return
			for part in parts:
				if not part.strip_edges().is_valid_int(): message("Landmark coordinates must be integers."); return
			landmarks.append([Vector2i(int(parts[0]),int(parts[1])),Vector2i(int(parts[2]),int(parts[3]))])
	var labeled := Rect2i(int(region_fields[0].value),int(region_fields[1].value),int(region_fields[2].value),int(region_fields[3].value))
	var target := Rect2i(int(target_fields[0].value),int(target_fields[1].value),int(target_fields[2].value),int(target_fields[3].value))
	var error: String = model.generate_hybrid(labeled,target,landmarks,hybrid_agreement.button_pressed) if hybrid else model.generate_spatial(labeled,target,landmarks)
	refresh()
	if not error.is_empty(): message(error)



