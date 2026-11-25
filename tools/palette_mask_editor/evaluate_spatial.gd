extends SceneTree
const Model := preload("res://mask_model.gd")
const Spatial := preload("res://spatial_generator.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures += 1; push_error(text)
func metrics() -> Array:
	var rows := []
	for name in Model.NAMES: rows.append({"class":name,"truth":0,"tp":0,"fp":0,"uncertain":0,"wrong_confident":0,"suggested_wrong":0})
	return rows
func measure(rows: Array, predicted: Image, pending: PackedByteArray, truth: Image) -> void:
	var model := Model.new()
	for y in truth.get_height():
		for x in truth.get_width():
			var actual := model.label(truth.get_pixel(x,y))
			var label := model.label(predicted.get_pixel(x,y))
			check(label >= 0,"Exact RGB output")
			rows[actual].truth += 1
			if actual != label: rows[actual].suggested_wrong += 1
			if pending[y*truth.get_width()+x]: rows[actual].uncertain += 1
			elif label == actual: rows[actual].tp += 1
			else: rows[label].fp += 1; rows[actual].wrong_confident += 1
func finish(rows: Array) -> Dictionary:
	var foreground := 0
	var review := 0
	var uncertain := 0
	for row in rows:
		row["precision_percent"] = 100.0*row.tp/maxi(1,row.tp+row.fp)
		row["recall_percent"] = 100.0*row.tp/maxi(1,row.truth)
		row["uncertain_percent"] = 100.0*row.uncertain/maxi(1,row.truth)
		row["review_or_correct_pixels"] = row.uncertain+row.wrong_confident
		if row.class != "Background":
			foreground += row.truth; review += row.review_or_correct_pixels; uncertain += row.uncertain
	return {"classes":rows,"foreground_pixels":foreground,"foreground_review_or_correct":review,"foreground_review_or_correct_percent":100.0*review/foreground,"foreground_uncertain_percent":100.0*uncertain/foreground}
func _initialize() -> void:
	var m := Model.new()
	var repo := ProjectSettings.globalize_path("res://../..")
	check(m.load_source(repo.path_join("assets/trainers/PlayerSprite.png")).is_empty(),"Source loads")
	check(m.load_reference(repo.path_join("assets/trainers/PlayerSprite_Mask_Aligned.png")).is_empty(),"Reference loads")
	var truth: Image = m.reference.duplicate()
	check(m.copy_aligned_reference().is_empty(),"Aligned copy")
	var differences := 0
	for y in truth.get_height():
		for x in truth.get_width():
			if m.mask.get_pixel(x,y) != truth.get_pixel(x,y): differences += 1
	check(differences == 0,"Aligned copy zero RGB differences")
	check(m.validate().is_empty(),"Aligned copy validates")
	m.undo(); check(m.uncertain[0] == 1,"Copy undo")
	m.redo(); check(m.uncertain[0] == 0,"Copy redo")
	var sources := {"male_down":Rect2i(582,72,161,307),"male_up":Rect2i(987,81,154,294),"male_side":Rect2i(377,77,148,317),"female_down":Rect2i(777,86,189,294),"female_up":Rect2i(1189,93,159,283),"female_left":Rect2i(33,82,160,332),"female_right":Rect2i(200,83,176,327)}
	var targets := {"male_down":[Rect2i(693,458,148,270),Rect2i(861,459,141,272)],"male_up":[Rect2i(1042,462,149,262),Rect2i(1202,462,141,263)],"male_side":[Rect2i(700,824,147,264),Rect2i(858,823,147,264)],"female_down":[Rect2i(329,466,170,265),Rect2i(495,465,184,266)],"female_up":[Rect2i(1018,820,160,276),Rect2i(1205,820,150,273)],"female_left":[Rect2i(17,824,164,264),Rect2i(181,824,164,264)],"female_right":[Rect2i(351,824,164,264),Rect2i(517,824,164,264)]}
	var baseline_rows := metrics()
	var spatial_rows := metrics()
	var frames := []
	for key in sources:
		var train: Rect2i = sources[key]
		for target in targets[key]:
			for other_train in sources.values(): check(not target.intersects(other_train),"Entire target withheld from all training frames")
			var art := m.source.get_region(train)
			var labels := truth.get_region(train)
			var unlabeled := m.source.get_region(target)
			# Neither predictor receives the target mask. Truth used only below for scoring.
			var prediction := Spatial.predict(art,labels,unlabeled,m.tolerance)
			var target_truth := truth.get_region(target)
			measure(spatial_rows,prediction.mask,prediction.uncertain,target_truth)
			var frame_rows := metrics(); measure(frame_rows,prediction.mask,prediction.uncertain,target_truth)
			m.samples.clear(); m.reference = truth; m.sample_reference(train)
			var baseline := Image.create(target.size.x,target.size.y,false,Image.FORMAT_RGB8)
			var baseline_pending := PackedByteArray(); baseline_pending.resize(target.size.x*target.size.y)
			var cache := {}
			for y in target.size.y:
				for x in target.size.x:
					var rgb := m.rgb(unlabeled.get_pixel(x,y))
					if not cache.has(rgb): cache[rgb] = m.classify(rgb)
					baseline.set_pixel(x,y,Model.COLORS[cache[rgb][0]])
					baseline_pending[y*target.size.x+x] = cache[rgb][1]
			measure(baseline_rows,baseline,baseline_pending,target_truth)
			frames.append({"training_rect":[train.position.x,train.position.y,train.size.x,train.size.y],"target_rect":[target.position.x,target.position.y,target.size.x,target.size.y],"direction":key,"spatial":finish(frame_rows)})
			print("SCORED ",key," ",target)
	# Exercise model path with all labels outside selected training crop erased.
	var train: Rect2i = sources.male_down
	var target: Rect2i = targets.male_down[0]
	m.reference = Image.create(truth.get_width(),truth.get_height(),false,Image.FORMAT_RGB8); m.reference.fill(Color.WHITE)
	m.reference.blit_rect(truth,train,train.position)
	m.confirmed.fill(0)
	var pinned := target.position+Vector2i(10,10)
	m.paint(pinned,1)
	var before := m.snapshot()
	check(m.generate_spatial(train,target).is_empty(),"Spatial model call")
	check(m.mask.get_pixelv(pinned) == Color.GREEN and m.confirmed[m.index(pinned)] == 1,"Manual correction preserved")
	var first := m.snapshot()
	m.reference.fill(Color.BLACK); m.reference.blit_rect(truth,train,train.position)
	check(m.generate_spatial(train,target).is_empty(),"Poisoned target labels call")
	check(m.mask.get_data() == first.mask.get_data() and m.uncertain == first.uncertain,"Outside-reference labels cannot affect spatial prediction")
	m.undo(); m.undo()
	check(m.mask.get_data() == before.mask.get_data() and m.confirmed == before.confirmed,"Spatial undo restores labels and confirmation")
	m.redo(); check(m.mask.get_data() == first.mask.get_data(),"Spatial redo")
	check(not m.generate_spatial(train,train).is_empty(),"Overlapping frame rejection")
	check(not m.generate_spatial(train,target,[[Vector2i(-1,0),Vector2i.ZERO]]).is_empty(),"Invalid landmark rejection")
	var identity := Spatial.predict(m.source.get_region(train),truth.get_region(train),m.source.get_region(train),m.tolerance,[[Vector2i(40,40),Vector2i(40,40)]])
	check(identity.mask.get_size() == train.size,"Landmark path executes")
	var report := {"aligned_copy_rgb_differences":differences,"baseline":finish(baseline_rows),"spatial":finish(spatial_rows),"frames":frames,"landmarks_in_benchmark":[],"checks_failed":failures}
	var output := FileAccess.open("res://spatial_evaluation.json",FileAccess.WRITE); output.store_string(JSON.stringify(report,"\t")); output.close()
	print("FINAL ",JSON.stringify(report).left(3000)); print("CHECK FAILURES: ",failures)
	quit(1 if failures else 0)

