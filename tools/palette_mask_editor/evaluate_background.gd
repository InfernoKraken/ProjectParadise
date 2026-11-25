extends SceneTree
const Background := preload("res://background_segmenter.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures += 1; push_error(text)
func score(image: Image, truth: Image) -> Dictionary:
	var prediction := Background.segment(image)
	var w := image.get_width(); var h := image.get_height()
	var exterior := PackedByteArray(); exterior.resize(w*h)
	var todo: Array[int] = []
	var background := PackedByteArray(); background.resize(w*h)
	var total := 0
	for y in h:
		for x in w:
			var c := truth.get_pixel(x,y)
			var i := y*w+x
			if c.r == 1 and c.g == 1 and c.b == 1:
				background[i] = 1; total += 1
				if x == 0 or y == 0 or x == w-1 or y == h-1: exterior[i] = 1; todo.append(i)
	while not todo.is_empty():
		var i: int = todo.pop_back()
		var p := Vector2i(i%w,i/w)
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var q: Vector2i = p+delta
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h: continue
			var j := q.y*w+q.x
			if background[j] and not exterior[j]: exterior[j] = 1; todo.append(j)
	var tp := 0; var fp := 0; var enclosed := 0; var enclosed_tp := 0; var enclosed_candidate := 0; var outside := 0; var outside_tp := 0
	var fp_classes := {"Hair":0,"Skin":0,"Other":0}
	for y in h:
		for x in w:
			var i := y*w+x
			if prediction.states[i] == 1:
				if background[i]: tp += 1
				else:
					fp += 1
					var c := truth.get_pixel(x,y)
					fp_classes["Hair" if c.r == 1 else ("Skin" if c.g == 1 else "Other")] += 1
			if background[i]:
				if exterior[i]:
					outside += 1
					if prediction.states[i] == 1: outside_tp += 1
				else:
					enclosed += 1
					if prediction.states[i] == 1: enclosed_tp += 1
					if prediction.states[i] == 2: enclosed_candidate += 1
	return {"mode":prediction.mode,"border_fraction":prediction.border_fraction,"truth_background":total,"tp":tp,"fp":fp,"fn":total-tp,"precision_percent":100.0*tp/maxi(1,tp+fp),"recall_percent":100.0*tp/maxi(1,total),"exterior_truth":outside,"exterior_tp":outside_tp,"enclosed_truth":enclosed,"enclosed_tp":enclosed_tp,"enclosed_candidates":enclosed_candidate,"false_background_by_true_class":fp_classes}
func _initialize() -> void:
	var repo := ProjectSettings.globalize_path("res://../..")
	var pairs := [["PlayerSprite.png","PlayerSprite_Mask_Aligned.png"],["Walking_Anim_Diagonal.png","Walking_Anim_Diagonal_RGB_Mask.png"],["Player_Swimming Sprites.png","Player_Swimming Sprites_Mask.png"],["Diving In Sprite.png","Diving In Sprite Mask.png"]]
	var reports := {}
	for pair in pairs:
		var image := Image.load_from_file(repo.path_join("assets/trainers/"+pair[0]))
		var truth := Image.load_from_file(repo.path_join("assets/trainers/"+pair[1]))
		check(image != null and truth != null and image.get_size() == truth.get_size(),"Aligned inputs")
		reports[pair[0]] = score(image,truth)
		print("SCORED BACKGROUND ",pair[0])
	# Opaque enclosed hole: candidate only, never pretend exterior flood reaches it.
	var ring := Image.create(9,9,false,Image.FORMAT_RGBA8); ring.fill(Color.WHITE)
	for y in range(2,7):
		for x in range(2,7): ring.set_pixel(x,y,Color.RED)
	ring.set_pixel(4,4,Color.WHITE)
	var segmented := Background.segment(ring)
	check(segmented.states[0] == 1 and segmented.states[40] == 2 and segmented.states[20] == 0,"Opaque hole remains enclosed candidate")
	ring.set_pixel(4,4,Color.TRANSPARENT)
	segmented = Background.segment(ring)
	check(segmented.mode == "alpha" and segmented.states[40] == 1 and segmented.states[20] == 0,"Alpha detects enclosed transparent hole")
	var output := FileAccess.open("res://background_evaluation.json",FileAccess.WRITE); output.store_string(JSON.stringify({"assets":reports,"checks_failed":failures},"\t")); output.close()
	print("CHECK FAILURES: ",failures)
	quit(1 if failures else 0)
