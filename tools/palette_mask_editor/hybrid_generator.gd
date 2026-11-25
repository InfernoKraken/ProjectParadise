extends RefCounted
const Model := preload("res://mask_model.gd")
const Spatial := preload("res://spatial_generator.gd")
const Background := preload("res://background_segmenter.gd")

static func rgb_prediction(art: Image, labels: Image, target: Image, tolerance: float) -> Dictionary:
	var model := Model.new(); model.source = art; model.reference = labels; model.tolerance = tolerance
	model.sample_reference(Rect2i(Vector2i.ZERO,art.get_size()))
	var result := Image.create(target.get_width(),target.get_height(),false,Image.FORMAT_RGB8)
	var pending := PackedByteArray(); pending.resize(target.get_width()*target.get_height())
	var cache := {}
	for y in target.get_height():
		for x in target.get_width():
			var pixel := target.get_pixel(x,y)
			var key := model.rgb(pixel)
			if not cache.has(key): cache[key] = model.classify(key)
			result.set_pixel(x,y,Color.WHITE if pixel.a == 0 else Model.COLORS[cache[key][0]])
			pending[y*target.get_width()+x] = 0 if pixel.a == 0 else cache[key][1]
	return {"mask":result,"uncertain":pending}

# Fuse precomputed predictions for controlled ablations without rerunning spatial.
static func combine(target: Image, rgb: Dictionary, spatial: Dictionary, background: Dictionary, require_agreement := false) -> Dictionary:
	var model := Model.new()
	var result := Image.create(target.get_width(),target.get_height(),false,Image.FORMAT_RGB8)
	var pending := PackedByteArray(); pending.resize(target.get_width()*target.get_height())
	var conflicts := PackedByteArray(); conflicts.resize(pending.size())
	for y in target.get_height():
		for x in target.get_width():
			var i := y*target.get_width()+x
			var r := model.label(rgb.mask.get_pixel(x,y))
			var s := model.label(spatial.mask.get_pixel(x,y))
			var rc: bool = rgb.uncertain[i] == 0
			var sc: bool = spatial.uncertain[i] == 0
			var selected := s if s == 0 else r # Spatial hair preference for tentative display.
			var uncertain := true
			var conflict := rc and sc and r != s
			if not conflict:
				if sc and s == 0: selected = s; uncertain = false
				elif rc and sc: selected = r; uncertain = false
				elif not require_agreement and (rc or sc):
					selected = r if rc else s; uncertain = false
			# Source alpha is authoritative. Opaque exterior is evidence, not proof:
			# any confident foreground contradiction is retained as reviewable.
			if target.get_pixel(x,y).a == 0:
				selected = 3; uncertain = false; conflict = false
			elif background.states[i] == 1:
				var foreground_conflict := (rc and r != 3) or (sc and s != 3)
				selected = 3; uncertain = foreground_conflict; conflict = conflict or foreground_conflict
			elif background.states[i] == 2:
				# Exterior flood cannot establish enclosed holes. Require both semantic
				# predictors to agree on white; a foreground decision stays reviewable.
				if rc and sc and r == 3 and s == 3: selected = 3; uncertain = false
				else: uncertain = true
			if conflict: uncertain = true
			result.set_pixel(x,y,Model.COLORS[selected]); pending[i] = 1 if uncertain else 0; conflicts[i] = 1 if conflict else 0
	return {"mask":result,"uncertain":pending,"conflicts":conflicts}

static func predict(art: Image, labels: Image, target: Image, tolerance: float, landmarks: Array = [], require_agreement := false) -> Dictionary:
	var rgb := rgb_prediction(art,labels,target,tolerance)
	var spatial := Spatial.predict(art,labels,target,tolerance,landmarks)
	return combine(target,rgb,spatial,Background.segment(target),require_agreement)

