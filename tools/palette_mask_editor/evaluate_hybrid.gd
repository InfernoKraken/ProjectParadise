extends SceneTree
const Model := preload("res://mask_model.gd")
const Hybrid := preload("res://hybrid_generator.gd")
const Background := preload("res://background_segmenter.gd")
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
	var sources := {"male_down":Rect2i(582,72,161,307),"male_up":Rect2i(987,81,154,294),"male_side":Rect2i(377,77,148,317),"female_down":Rect2i(777,86,189,294),"female_up":Rect2i(1189,93,159,283),"female_left":Rect2i(33,82,160,332),"female_right":Rect2i(200,83,176,327)}
	var targets := {"male_down":[Rect2i(693,458,148,270),Rect2i(861,459,141,272)],"male_up":[Rect2i(1042,462,149,262),Rect2i(1202,462,141,263)],"male_side":[Rect2i(700,824,147,264),Rect2i(858,823,147,264)],"female_down":[Rect2i(329,466,170,265),Rect2i(495,465,184,266)],"female_up":[Rect2i(1018,820,160,276),Rect2i(1205,820,150,273)],"female_left":[Rect2i(17,824,164,264),Rect2i(181,824,164,264)],"female_right":[Rect2i(351,824,164,264),Rect2i(517,824,164,264)]}
	var rows := {}
	for name in ["rgb","spatial","segmented_spatial","hybrid_fallback","hybrid_agreement"]: rows[name] = metrics()
	var frame_reports := []
	for key in sources:
		var train: Rect2i = sources[key]
		for target in targets[key]:
			for other_train in sources.values(): check(not target.intersects(other_train),"Whole target frame withheld")
			var art := m.source.get_region(train)
			var labels := truth.get_region(train)
			var unlabeled := m.source.get_region(target)
			var rgb := Hybrid.rgb_prediction(art,labels,unlabeled,m.tolerance)
			var spatial := Spatial.predict(art,labels,unlabeled,m.tolerance)
			var background := Background.segment(unlabeled)
			var predictions := {"rgb":rgb,"spatial":spatial,"segmented_spatial":Hybrid.combine(unlabeled,spatial,spatial,background),"hybrid_fallback":Hybrid.combine(unlabeled,rgb,spatial,background),"hybrid_agreement":Hybrid.combine(unlabeled,rgb,spatial,background,true)}
			var target_truth := truth.get_region(target)
			var frame := {"direction":key,"training_rect":[train.position.x,train.position.y,train.size.x,train.size.y],"target_rect":[target.position.x,target.position.y,target.size.x,target.size.y],"background_mode":background.mode,"methods":{}}
			for name in predictions:
				var prediction: Dictionary = predictions[name]
				measure(rows[name],prediction.mask,prediction.uncertain,target_truth)
				var local := metrics(); measure(local,prediction.mask,prediction.uncertain,target_truth)
				var summary := finish(local)
				if prediction.has("conflicts"):
					var conflicts := 0
					for flag in prediction.conflicts: conflicts += flag
					summary["conflicts"] = conflicts
				frame.methods[name] = summary
			frame_reports.append(frame)
			print("SCORED HYBRID ",key," ",target)
	var methods := {}
	for name in rows:
		var summary := finish(rows[name])
		var uncertain := 0; var wrong := 0; var pixels := 0
		for row in summary.classes: uncertain += row.uncertain; wrong += row.wrong_confident; pixels += row.truth
		summary["all_pixels"] = pixels; summary["all_uncertain"] = uncertain; summary["all_wrong_confident"] = wrong; summary["all_review_or_correct"] = uncertain+wrong
		methods[name] = summary
	# Model-path isolation and editing tests use erased/poisoned nontraining labels.
	var train: Rect2i = sources.male_down
	var target: Rect2i = targets.male_down[0]
	m.reference = Image.create(truth.get_width(),truth.get_height(),false,Image.FORMAT_RGB8); m.reference.fill(Color.WHITE)
	m.reference.blit_rect(truth,train,train.position)
	var pin := target.position+Vector2i(10,10)
	m.paint(pin,1)
	var before := m.snapshot()
	check(m.generate_hybrid(train,target).is_empty(),"Hybrid model call")
	check(m.mask.get_pixelv(pin) == Color.GREEN and m.confirmed[m.index(pin)] == 1,"Manual confirmation preserved")
	var first := m.snapshot()
	m.reference.fill(Color.BLACK); m.reference.blit_rect(truth,train,train.position)
	check(m.generate_hybrid(train,target).is_empty(),"Poisoned reference call")
	check(first.mask.get_data() == m.mask.get_data() and first.uncertain == m.uncertain,"Target labels cannot enter hybrid")
	m.undo(); m.undo()
	check(m.mask.get_data() == before.mask.get_data() and m.confirmed == before.confirmed,"Undo confirmation and labels")
	m.redo(); check(m.mask.get_data() == first.mask.get_data(),"Redo hybrid")
	check(not m.generate_hybrid(train,train).is_empty(),"Overlap rejected")
	check(not m.generate_hybrid(train,target,[[Vector2i(-1,0),Vector2i.ZERO]]).is_empty(),"Invalid landmark rejected")
	var report := {"methods":methods,"frames":frame_reports,"checks_failed":failures,"landmarks_in_benchmark":[]}
	var output := FileAccess.open("res://hybrid_evaluation.json",FileAccess.WRITE); output.store_string(JSON.stringify(report,"\t")); output.close()
	print("CHECK FAILURES: ",failures)
	quit(1 if failures else 0)
