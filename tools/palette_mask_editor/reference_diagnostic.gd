extends SceneTree
const Model := preload("res://mask_model.gd")
func _initialize() -> void:
	var report := {}
	var repo := ProjectSettings.globalize_path("res://../..")
	for mode in ["default_rectangle","full_reference"]:
		var m := Model.new()
		var error := m.load_source(repo.path_join("assets/trainers/PlayerSprite.png"))
		if not error.is_empty(): push_error(error); quit(1); return
		error = m.load_reference(repo.path_join("assets/trainers/PlayerSprite_Mask_Aligned.png"))
		if not error.is_empty(): push_error(error); quit(1); return
		var before_samples := m.samples.size()
		var region := Rect2i(0,0,200,400) if mode == "default_rectangle" else Rect2i(Vector2i.ZERO,m.source.get_size())
		m.sample_reference(region)
		var sampled := [0,0,0,0]
		var collision_colors := 0
		var theoretical_errors := 0
		for key in m.samples:
			var classes := 0
			var total := 0
			var largest := 0
			for i in 4:
				sampled[i] += m.samples[key][i]
				total += m.samples[key][i]
				largest = maxi(largest,m.samples[key][i])
				if m.samples[key][i] > 0: classes += 1
			if classes > 1: collision_colors += 1
			theoretical_errors += total-largest
		m.generate()
		var foreground := 0
		var uncertain_foreground := 0
		var uncertain_total := 0
		var uncertain_background := 0
		var mismatches := 0
		var nontransparent := 0
		var no_match := 0
		var classification_cache := {}
		var example := []
		for y in m.source.get_height():
			for x in m.source.get_width():
				var p := Vector2i(x,y)
				var truth := m.label(m.reference.get_pixelv(p))
				var pending: int = m.uncertain[m.index(p)]
				if m.source.get_pixelv(p).a > 0: nontransparent += 1
				if truth != 3:
					foreground += 1
					uncertain_foreground += pending
				else: uncertain_background += pending
				uncertain_total += pending
				if m.label(m.mask.get_pixelv(p)) != truth:
					mismatches += 1
					if example.size() < 5: example.append({"x":x,"y":y,"truth":Model.NAMES[truth],"suggested":Model.NAMES[m.label(m.mask.get_pixelv(p))]})
				var key := m.rgb(m.source.get_pixelv(p))
				if not classification_cache.has(key):
					var nearest := INF
					for sample in m.samples: nearest = minf(nearest,m.color(key).distance_to(m.color(sample)))
					classification_cache[key] = nearest > m.tolerance
				if pending and classification_cache[key]: no_match += 1
		report[mode] = {"sample_count_before_explicit_sampling":before_samples,"rectangle":[region.position.x,region.position.y,region.size.x,region.size.y],"sampled_by_class_hair_skin_other_background":sampled,"sampled_total":sampled[0]+sampled[1]+sampled[2]+sampled[3],"unique_sampled_rgb":m.samples.size(),"rgb_shared_between_classes":collision_colors,"minimum_errors_for_one_label_per_exact_rgb_on_sampled_pixels":theoretical_errors,"foreground_reference_nonwhite":foreground,"source_nontransparent":nontransparent,"uncertain_foreground":uncertain_foreground,"uncertain_foreground_percent":100.0*uncertain_foreground/foreground,"uncertain_background":uncertain_background,"uncertain_total":uncertain_total,"uncertain_outside_tolerance":no_match,"uncertain_mixed_votes":uncertain_total-no_match,"reference_mismatches":mismatches,"mismatch_examples":example,"validation":m.validate()}
	var file := FileAccess.open("res://reference_diagnostic.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print(JSON.stringify(report))
	quit()
