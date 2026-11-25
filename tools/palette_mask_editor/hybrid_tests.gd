extends SceneTree
const Hybrid := preload("res://hybrid_generator.gd")
const Background := preload("res://background_segmenter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func prediction(c: Color, uncertain := 0) -> Dictionary:
	var image := Image.create(1,1,false,Image.FORMAT_RGB8); image.fill(c)
	return {"mask":image,"uncertain":PackedByteArray([uncertain])}
func _initialize() -> void:
	var target := Image.create(1,1,false,Image.FORMAT_RGBA8); target.fill(Color.YELLOW)
	var bg := {"states":PackedByteArray([0])}
	var result := Hybrid.combine(target,prediction(Color.GREEN),prediction(Color.RED),bg)
	check(result.uncertain[0] == 1 and result.conflicts[0] == 1 and result.mask.get_pixel(0,0) == Color.RED,"Conflicting skin/hair decisions uncertain; hair tentative uses spatial")
	result = Hybrid.combine(target,prediction(Color.BLACK,1),prediction(Color.RED),bg)
	check(result.uncertain[0] == 0 and result.mask.get_pixel(0,0) == Color.RED,"Confident spatial hair wins against uncertain RGB")
	result = Hybrid.combine(target,prediction(Color.GREEN),prediction(Color.BLACK,1),bg)
	check(result.uncertain[0] == 0 and result.mask.get_pixel(0,0) == Color.GREEN,"Fallback can use confident RGB skin")
	result = Hybrid.combine(target,prediction(Color.GREEN),prediction(Color.BLACK,1),bg,true)
	check(result.uncertain[0] == 1,"Agreement variant abstains without two confident votes")
	bg.states[0] = 1
	result = Hybrid.combine(target,prediction(Color.GREEN),prediction(Color.WHITE),bg)
	check(result.uncertain[0] == 1 and result.conflicts[0] == 1,"Exterior versus foreground conflict is reviewable")
	bg.states[0] = 2
	result = Hybrid.combine(target,prediction(Color.WHITE),prediction(Color.WHITE),bg)
	check(result.uncertain[0] == 0 and result.mask.get_pixel(0,0) == Color.WHITE,"Enclosed candidate needs agreeing white semantic votes")
	result = Hybrid.combine(target,prediction(Color.WHITE),prediction(Color.WHITE,1),bg)
	check(result.uncertain[0] == 1,"Enclosed hole not confidently guessed from one method")
	target.set_pixel(0,0,Color.TRANSPARENT)
	result = Hybrid.combine(target,prediction(Color.RED),prediction(Color.GREEN),bg)
	check(result.uncertain[0] == 0 and result.mask.get_pixel(0,0) == Color.WHITE,"Alpha overrides semantic disagreement")
	# A busy opaque border must not invent a dominant background.
	var busy := Image.create(3,3,false,Image.FORMAT_RGBA8)
	for y in 3:
		for x in 3: busy.set_pixel(x,y,Color8(x*70,y*70,100))
	check(Background.segment(busy).mode == "opaque_no_dominant_border","Refuse ambiguous border")
	var model := preload("res://mask_model.gd").new()
	model.source = Image.create(4,2,false,Image.FORMAT_RGBA8); model.source.fill(Color.YELLOW)
	model.reference = Image.create(4,2,false,Image.FORMAT_RGB8); model.reference.fill(Color.RED)
	model.mask = Image.create(4,2,false,Image.FORMAT_RGB8); model.mask.fill(Color.BLACK)
	model.uncertain.resize(8); model.uncertain.fill(1); model.confirmed.resize(8); model.confirmed.fill(0)
	model.paint(Vector2i(2,0),1)
	var before := model.snapshot()
	check(model.generate_hybrid(Rect2i(0,0,2,2),Rect2i(2,0,2,2),[],true).is_empty(),"Strict policy model API")
	check(model.mask.get_pixel(2,0) == Color.GREEN and model.confirmed[2] == 1,"Strict hybrid preserves manual confirmation")
	check(model.mask.get_pixel(0,0) == Color.BLACK,"Hybrid only modifies target frame")
	var first := model.snapshot()
	model.undo(); check(model.mask.get_data() == before.mask.get_data() and model.confirmed == before.confirmed,"Hybrid undo restores manual state")
	model.redo(); check(model.mask.get_data() == first.mask.get_data(),"Hybrid redo")
	check(model.generate_hybrid(Rect2i(0,0,2,2),Rect2i(2,0,2,2)).is_empty(),"Fallback policy model API")
	print("CHECK FAILURES: ",failures)
	quit(1 if failures else 0)

