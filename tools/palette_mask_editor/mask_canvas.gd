extends Control
var editor: Control
var source_texture: ImageTexture
var mask_texture: ImageTexture
var overlay_texture: ImageTexture
var zoom := 1.0
var pan := Vector2(16,40)
var drawing := false
var panning := false
var last := Vector2i(-1,-1)

func refresh() -> void:
	if editor.model.source == null: return
	source_texture = ImageTexture.create_from_image(editor.model.source)
	mask_texture = ImageTexture.create_from_image(editor.model.mask)
	var overlay := Image.create(editor.model.source.get_width(),editor.model.source.get_height(),false,Image.FORMAT_RGBA8)
	for y in overlay.get_height():
		for x in overlay.get_width():
			if editor.model.uncertain[editor.model.index(Vector2i(x,y))]: overlay.set_pixel(x,y,Color(1,0,1,0.8))
	overlay_texture = ImageTexture.create_from_image(overlay)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("192230"))
	draw_line(Vector2(size.x/2,0),Vector2(size.x/2,size.y),Color.GRAY)
	if source_texture == null: return
	for side in 2:
		var origin := Vector2(side * size.x/2,0)
		draw_set_transform(origin)
		draw_string(ThemeDB.fallback_font,Vector2(12,22),"SOURCE" if side == 0 else "MASK · magenta = review",HORIZONTAL_ALIGNMENT_LEFT,-1,16)
		# Clip each view independently, so oversized sheets cannot cross the divider.
		var texture: Texture2D = source_texture if side == 0 else mask_texture
		var view := Rect2(Vector2.ZERO,Vector2(size.x/2,size.y))
		var dest := Rect2(pan,Vector2(texture.get_size())*zoom)
		var clipped := dest.intersection(view)
		if clipped.has_area():
			var src := Rect2((clipped.position-pan)/zoom,clipped.size/zoom)
			draw_texture_rect_region(texture,clipped,src)
			if editor.show_review.button_pressed: draw_texture_rect_region(overlay_texture,clipped,src)
	draw_set_transform(Vector2.ZERO)

func pixel(pos: Vector2) -> Vector2i:
	return Vector2i(((Vector2(fmod(pos.x,size.x/2),pos.y)-pan)/zoom).floor())

func _gui_input(event: InputEvent) -> void:
	if editor.model.source == null: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE: panning = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var local := Vector2(fmod(event.position.x,size.x/2),event.position.y)
			var before := (local-pan)/zoom
			zoom = clampf(zoom * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8),0.1,40)
			pan = local-before*zoom; queue_redraw()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var p := pixel(event.position)
				if not editor.model.inside(p): return
				if editor.tool.selected == 3:
					editor.model.sample_pixel(p,editor.category.selected); editor.message("Added labeled source sample at %s." % p); return
				editor.model.checkpoint()
				if editor.tool.selected == 1:
					editor.model.region(p,editor.category.selected); refresh(); editor.update_status(); return
				drawing = true; last = p; stroke(p)
			else:
				drawing = false
				editor.update_status()
	if event is InputEventMouseMotion:
		if panning: pan += event.relative; queue_redraw()
		elif drawing: stroke(pixel(event.position))

func stroke(p: Vector2i) -> void:
	var distance := maxi(absi(p.x-last.x),absi(p.y-last.y))
	for i in range(distance+1):
		var point := Vector2i(Vector2(last).lerp(Vector2(p),float(i)/maxi(1,distance)).round())
		var radius: int = int(editor.brush.value)-1
		for y in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				var q := point+Vector2i(x,y)
				if editor.model.inside(q):
					# Erase removes a decision and makes the pixel reviewable again.
					if editor.tool.selected == 2:
						editor.model.paint(q,2)
						editor.model.confirmed[editor.model.index(q)] = 0
						editor.model.uncertain[editor.model.index(q)] = 0 if editor.model.source.get_pixelv(q).a == 0 else 1
					else: editor.model.paint(q,editor.category.selected)
	last = p; refresh()


