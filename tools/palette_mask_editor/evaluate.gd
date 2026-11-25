extends SceneTree
const Model := preload("res://mask_model.gd")
var failures := 0
func check(condition: bool, text: String) -> void:
	if not condition: push_error(text); failures += 1
func _initialize() -> void:
	var m := Model.new()
	var repo := ProjectSettings.globalize_path("res://").path_join("../..").simplify_path()
	check(m.load_source(repo.path_join("assets/trainers/PlayerSprite.png")).is_empty(),"Source load")
	check(m.load_reference(repo.path_join("assets/trainers/PlayerSprite_Mask_Aligned.png")).is_empty(),"Reference load")
	if m.reference == null: quit(1); return
	# Explicit disjoint idle rectangles; no walking-frame labels enter training.
	var training := [Rect2i(582,72,161,307),Rect2i(987,81,154,294),Rect2i(33,82,160,332),Rect2i(777,86,189,294)]
	for r in training: m.sample_reference(r)
	m.generate()
	var frames := {
		"male_walk_down_0":Rect2i(693,458,148,270),"male_walk_down_1":Rect2i(861,459,141,272),
		"male_walk_up_0":Rect2i(1042,462,149,262),"male_walk_up_1":Rect2i(1202,462,141,263),
		"male_walk_side_0":Rect2i(700,824,147,264),"male_walk_side_1":Rect2i(858,823,147,264),
		"female_walk_down_0":Rect2i(329,466,170,265),"female_walk_down_1":Rect2i(495,465,184,266),
		"female_walk_up_0":Rect2i(1018,820,160,276),"female_walk_up_1":Rect2i(1205,820,150,273),
		"female_walk_left_0":Rect2i(17,824,164,264),"female_walk_left_1":Rect2i(181,824,164,264),
		"female_walk_right_0":Rect2i(351,824,164,264),"female_walk_right_1":Rect2i(517,824,164,264)}
	var totals := []
	for i in 4: totals.append({"class":Model.NAMES[i],"pixels":0,"correct":0,"suggestion_correct":0,"uncertain":0,"confident_wrong":0})
	var locations := {}
	var per_frame := {}
	for name in frames:
		var r: Rect2i = frames[name]
		for train in training: check(not r.intersects(train),"Train/test overlap")
		var runs := []
		var count := 0
		for y in range(r.position.y,r.end.y):
			var start := -1
			for x in range(r.position.x,r.end.x):
				var p := Vector2i(x,y)
				var truth := m.label(m.reference.get_pixelv(p))
				var predicted := m.label(m.mask.get_pixelv(p))
				var pending: bool = m.uncertain[m.index(p)] != 0
				totals[truth].pixels += 1
				if truth == predicted: totals[truth].suggestion_correct += 1
				if pending: totals[truth].uncertain += 1; count += 1
				elif truth == predicted: totals[truth].correct += 1
				else: totals[truth].confident_wrong += 1
				if pending and start < 0: start = x
				if start >= 0 and (not pending or x == r.end.x-1):
					runs.append([y,start,x if pending else x-1]); start = -1
		locations[name] = runs
		per_frame[name] = {"rect":[r.position.x,r.position.y,r.size.x,r.size.y],"uncertain":count}
	for row in totals:
		row["suggested_label_accuracy_percent"] = 100.0*row.suggestion_correct/maxi(1,row.pixels)
		row["accuracy_percent_uncertain_counts_as_incorrect"] = 100.0*row.correct/maxi(1,row.pixels)
		row["accuracy_on_confident_percent"] = 100.0*row.correct/maxi(1,row.pixels-row.uncertain)
	var report := {"source_dimensions":[m.source.get_width(),m.source.get_height()],"tolerance":m.tolerance,"training_rectangles":[[582,72,161,307],[987,81,154,294],[33,82,160,332],[777,86,189,294]],"sampled_colors":m.samples.size(),"classes":totals,"frames":per_frame,"uncertain_locations_y_xstart_xend_inclusive":locations}
	var output := FileAccess.open("res://evaluation.json",FileAccess.WRITE); output.store_string(JSON.stringify(report,"\t")); output.close()
	print(JSON.stringify(totals))
	# Synthetic checks exercise collisions, alpha/background, region topology and history.
	var s := Model.new()
	s.source = Image.create(3,2,false,Image.FORMAT_RGBA8); s.source.fill(Color8(80,40,20))
	s.source.set_pixel(1,0,Color(0,0,0,0))
	s.mask = Image.create(3,2,false,Image.FORMAT_RGB8); s.mask.fill(Color.BLACK)
	s.uncertain.resize(6); s.uncertain.fill(1)
	s.sample_pixel(Vector2i.ZERO,0); s.sample_pixel(Vector2i(2,0),1); s.generate()
	check(s.uncertain[0] == 1,"Shared hair/skin must be uncertain")
	check(s.mask.get_pixel(1,0) == Color.WHITE,"Transparent source must become white")
	check(not s.validate().is_empty(),"Unresolved export rejected")
	s.checkpoint(); s.paint(Vector2i.ZERO,1); s.undo()
	check(s.uncertain[0] == 1,"Undo restores uncertainty")
	s.redo(); check(s.uncertain[0] == 0 and s.mask.get_pixel(0,0) == Color.GREEN,"Redo restores correction")
	s.checkpoint(); s.region(Vector2i.ZERO,0)
	check(s.mask.get_pixel(2,0) == Color.RED,"Connected region reaches around transparent barrier")
	check(s.mask.get_pixel(1,0) == Color.WHITE,"Region respects alpha")
	check(s.validate().is_empty(),"Resolved synthetic mask validates")
	check(not s.export_png(m.source_path).is_empty(),"Existing asset cannot be overwritten")
	var export_path := "res://.godot/palette_mask_test.png"
	if FileAccess.file_exists(export_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(export_path))
	check(s.export_png(export_path).is_empty(),"Export succeeds after review")
	var roundtrip := Image.load_from_file(export_path)
	check(roundtrip != null and roundtrip.get_size() == s.source.get_size(),"PNG dimensions preserved")
	if roundtrip != null:
		for y in roundtrip.get_height():
			for x in roundtrip.get_width(): check(s.label(roundtrip.get_pixel(x,y)) >= 0,"PNG contains exact allowed RGB only")
	check(not s.export_png(export_path).is_empty(),"Existing output protected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(export_path))
	print("CHECK FAILURES: ",failures)
	quit(1 if failures else 0)





