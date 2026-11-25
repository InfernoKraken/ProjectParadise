extends RefCounted

const COLORS := [Color.RED, Color.GREEN, Color.BLACK, Color.WHITE]
const NAMES := ["Hair", "Skin", "Other", "Background"]
var source: Image
var mask: Image
var reference: Image
var source_path := ""
var reference_path := ""
var uncertain := PackedByteArray()
var confirmed := PackedByteArray()
var samples: Dictionary = {}
var undo_stack: Array = []
var redo_stack: Array = []
var tolerance := 18.0

func load_source(path: String) -> String:
	var image := Image.load_from_file(path)
	if image == null: return "Cannot read source PNG."
	image.convert(Image.FORMAT_RGBA8)
	source = image
	source_path = path.simplify_path()
	reference = null
	reference_path = ""
	samples.clear()
	mask = Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGB8)
	mask.fill(Color.BLACK)
	uncertain.resize(source.get_width() * source.get_height())
	confirmed.resize(uncertain.size()); confirmed.fill(0)
	for y in source.get_height():
		for x in source.get_width():
			var bg := source.get_pixel(x,y).a == 0
			mask.set_pixel(x,y,Color.WHITE if bg else Color.BLACK)
			uncertain[index(Vector2i(x,y))] = 0 if bg else 1
	undo_stack.clear(); redo_stack.clear()
	return ""

func load_reference(path: String) -> String:
	if source == null: return "Load source first."
	var image := Image.load_from_file(path)
	if image == null: return "Cannot read reference."
	if image.get_size() != source.get_size(): return "Reference dimensions must match source."
	for y in image.get_height():
		for x in image.get_width():
			if label(image.get_pixel(x,y)) < 0: return "Reference has noncanonical colors at (%d,%d)." % [x,y]
	reference = image
	reference_path = path.simplify_path()
	return ""

func label(c: Color) -> int:
	for i in 4:
		if c.r == COLORS[i].r and c.g == COLORS[i].g and c.b == COLORS[i].b: return i
	return -1

func index(p: Vector2i) -> int: return p.y * source.get_width() + p.x
func inside(p: Vector2i) -> bool: return source != null and Rect2i(Vector2i.ZERO,source.get_size()).has_point(p)
func rgb(c: Color) -> int: return (c.r8 << 16) | (c.g8 << 8) | c.b8
func color(key: int) -> Vector3: return Vector3((key >> 16) & 255,(key >> 8) & 255,key & 255)

func sample_pixel(p: Vector2i, category: int) -> void:
	var key := rgb(source.get_pixelv(p))
	if not samples.has(key): samples[key] = [0,0,0,0]
	samples[key][category] += 1

func sample_reference(region: Rect2i) -> void:
	if reference == null: return
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var p := Vector2i(x,y)
			if inside(p): sample_pixel(p,label(reference.get_pixelv(p)))

func snapshot() -> Dictionary: return {"mask":mask.duplicate(),"uncertain":uncertain.duplicate(),"confirmed":confirmed.duplicate()}
func checkpoint() -> void:
	undo_stack.append(snapshot()); redo_stack.clear()
	if undo_stack.size() > 30: undo_stack.pop_front()
func restore(s: Dictionary) -> void:
	mask = s.mask.duplicate(); uncertain = s.uncertain.duplicate(); confirmed = s.confirmed.duplicate()
func undo() -> void:
	if undo_stack.is_empty(): return
	redo_stack.append(snapshot()); restore(undo_stack.pop_back())
func redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(snapshot()); restore(redo_stack.pop_back())

func generate() -> void:
	if source == null: return
	checkpoint()
	var cache := {}
	for y in source.get_height():
		for x in source.get_width():
			var p := Vector2i(x,y)
			if confirmed.size() > index(p) and confirmed[index(p)]: continue
			if source.get_pixelv(p).a == 0:
				mask.set_pixelv(p,Color.WHITE); uncertain[index(p)] = 0; continue
			var key := rgb(source.get_pixelv(p))
			if not cache.has(key): cache[key] = classify(key)
			var result: Array = cache[key]
			mask.set_pixelv(p,COLORS[result[0]])
			uncertain[index(p)] = result[1]

func classify(key: int) -> Array:
	var nearest := INF
	for sample in samples:
		nearest = minf(nearest,color(key).distance_to(color(sample)))
	if nearest > tolerance: return [2,1]
	var votes := [0.0,0.0,0.0,0.0]
	for sample in samples:
		var distance := color(key).distance_to(color(sample))
		if distance <= nearest + 3.0 and distance <= tolerance:
			for i in 4: votes[i] += samples[sample][i] / (1.0+distance)
	var best := 2
	var total := 0.0
	for i in 4:
		total += votes[i]
		if votes[i] > votes[best]: best = i
	# Minority labels remain visible as uncertainty unless evidence is >= 90%.
	return [best,0 if total > 0 and votes[best]/total >= 0.9 else 1]
func paint(p: Vector2i, category: int) -> void:
	if not inside(p): return
	if source.get_pixelv(p).a == 0: category = 3
	mask.set_pixelv(p,COLORS[category]); uncertain[index(p)] = 0
	if confirmed.size() == uncertain.size(): confirmed[index(p)] = 1

func region(seed: Vector2i, category: int) -> void:
	if not inside(seed): return
	var target := color(rgb(source.get_pixelv(seed)))
	var visited := PackedByteArray(); visited.resize(uncertain.size())
	var todo: Array[Vector2i] = [seed]
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		if not inside(p) or visited[index(p)]: continue
		visited[index(p)] = 1
		if color(rgb(source.get_pixelv(p))).distance_to(target) > tolerance: continue
		if (source.get_pixelv(p).a == 0) != (source.get_pixelv(seed).a == 0): continue
		paint(p,category)
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]: todo.append(p+delta)

func validate() -> String:
	if source == null or mask == null: return "Load source first."
	if source.get_size() != mask.get_size(): return "Mask dimensions differ from source."
	var pending := 0
	for y in source.get_height():
		for x in source.get_width():
			var p := Vector2i(x,y)
			if label(mask.get_pixelv(p)) < 0: return "Invalid mask RGB at %s." % p
			if source.get_pixelv(p).a == 0 and label(mask.get_pixelv(p)) != 3: return "Transparent background must be white at %s." % p
			pending += uncertain[index(p)]
	return "%d uncertain pixels remain; review highlighted pixels before export." % pending if pending else ""

func export_png(path: String) -> String:
	var error := validate()
	if not error.is_empty(): return error
	var resolved := ProjectSettings.globalize_path(path).simplify_path()
	if resolved.to_lower() in [ProjectSettings.globalize_path(source_path).simplify_path().to_lower(),ProjectSettings.globalize_path(reference_path).simplify_path().to_lower()]: return "Source and reference are protected; choose a new output path."
	if FileAccess.file_exists(path): return "Output already exists; choose a new filename to preserve images."
	return "" if mask.save_png(path) == OK else "PNG export failed."



# Explicit authoritative operation. It intentionally replaces all in-memory labels.
func copy_aligned_reference() -> String:
	if reference == null: return "Load an aligned reference first."
	checkpoint()
	mask = reference.duplicate(); mask.convert(Image.FORMAT_RGB8)
	uncertain.fill(0)
	confirmed.resize(uncertain.size()); confirmed.fill(1)
	return ""

func generate_spatial(labeled_frame: Rect2i, target_frame: Rect2i, landmarks: Array = []) -> String:
	if reference == null or source == null: return "Load source and aligned reference first."
	var bounds := Rect2i(Vector2i.ZERO,source.get_size())
	if not labeled_frame.has_area() or not target_frame.has_area() or not bounds.encloses(labeled_frame) or not bounds.encloses(target_frame): return "Frame rectangles must be nonempty and inside the source."
	if labeled_frame.intersects(target_frame): return "Training and target frames must not overlap."
	for pair in landmarks:
		if not Rect2i(Vector2i.ZERO,labeled_frame.size).has_point(Vector2i(pair[0])) or not Rect2i(Vector2i.ZERO,target_frame.size).has_point(Vector2i(pair[1])): return "Landmarks must be frame-local coordinates inside their frames."
	# Extract only the selected reference crop; target labels cannot enter predictor.
	var prediction: Dictionary = preload("res://spatial_generator.gd").predict(source.get_region(labeled_frame),reference.get_region(labeled_frame),source.get_region(target_frame),tolerance,landmarks)
	checkpoint()
	for y in target_frame.size.y:
		for x in target_frame.size.x:
			var p := target_frame.position+Vector2i(x,y)
			if confirmed[index(p)]: continue
			mask.set_pixelv(p,prediction.mask.get_pixel(x,y))
			uncertain[index(p)] = prediction.uncertain[y*target_frame.size.x+x]
	return ""

# Separate experimental operation; existing RGB and spatial modes are unchanged.
func generate_hybrid(labeled_frame: Rect2i, target_frame: Rect2i, landmarks: Array = [], require_agreement := false) -> String:
	if reference == null or source == null: return "Load source and aligned reference first."
	var bounds := Rect2i(Vector2i.ZERO,source.get_size())
	if not labeled_frame.has_area() or not target_frame.has_area() or not bounds.encloses(labeled_frame) or not bounds.encloses(target_frame): return "Frame rectangles must be nonempty and inside the source."
	if labeled_frame.intersects(target_frame): return "Training and target frames must not overlap."
	for pair in landmarks:
		if not Rect2i(Vector2i.ZERO,labeled_frame.size).has_point(Vector2i(pair[0])) or not Rect2i(Vector2i.ZERO,target_frame.size).has_point(Vector2i(pair[1])): return "Landmarks must be frame-local coordinates inside their frames."
	# Runtime load avoids a preload cycle: hybrid delegates RGB math to this model.
	var prediction: Dictionary = load("res://hybrid_generator.gd").predict(source.get_region(labeled_frame),reference.get_region(labeled_frame),source.get_region(target_frame),tolerance,landmarks,require_agreement)
	checkpoint()
	for y in target_frame.size.y:
		for x in target_frame.size.x:
			var p := target_frame.position+Vector2i(x,y)
			if confirmed[index(p)]: continue
			mask.set_pixelv(p,prediction.mask.get_pixel(x,y))
			uncertain[index(p)] = prediction.uncertain[y*target_frame.size.x+x]
	return ""

