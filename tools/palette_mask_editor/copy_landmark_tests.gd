extends SceneTree
const Model := preload("res://mask_model.gd")
const Spatial := preload("res://spatial_generator.gd")
func _initialize() -> void:
	var repo := ProjectSettings.globalize_path("res://../..")
	var pairs := [["PlayerSprite.png","PlayerSprite_Mask_Aligned.png"],["Walking_Anim_Diagonal.png","Walking_Anim_Diagonal_RGB_Mask.png"],["Player_Swimming Sprites.png","Player_Swimming Sprites_Mask.png"],["Diving In Sprite.png","Diving In Sprite Mask.png"]]
	var failures := 0
	for pair in pairs:
		var m := Model.new()
		var error := m.load_source(repo.path_join("assets/trainers/"+pair[0]))
		if error.is_empty(): error = m.load_reference(repo.path_join("assets/trainers/"+pair[1]))
		if not error.is_empty(): push_error(error); failures += 1; continue
		m.copy_aligned_reference()
		var expected: Image = m.reference.duplicate(); expected.convert(Image.FORMAT_RGB8)
		if expected.get_data() != m.mask.get_data(): failures += 1; push_error("Copy differs: "+pair[0])
		var path := "res://.godot/copy_test.png"
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		# RGB copy remains exact even when source alpha/reference coverage disagree;
		# export validation independently enforces the source alpha contract.
		m.mask.save_png(path)
		var loaded := Image.load_from_file(path); loaded.convert(Image.FORMAT_RGB8)
		if loaded.get_size() != expected.get_size() or loaded.get_data() != expected.get_data(): failures += 1
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		print("EXACT RGB COPY + PNG ROUNDTRIP: ",pair[0],"; validation: ",m.validate())
	# A synthetic shift puts the target well beyond the 6px search radius.
	var art := Image.create(30,1,false,Image.FORMAT_RGBA8); art.fill(Color.BLUE)
	var labels := Image.create(30,1,false,Image.FORMAT_RGB8); labels.fill(Color.BLACK)
	art.set_pixel(2,0,Color.YELLOW); labels.set_pixel(2,0,Color.RED)
	var target := Image.create(30,1,false,Image.FORMAT_RGBA8); target.fill(Color.BLUE); target.set_pixel(25,0,Color.YELLOW)
	var no_landmarks := Spatial.predict(art,labels,target,0)
	var landmarks := Spatial.predict(art,labels,target,0,[[Vector2i(2,0),Vector2i(25,0)]])
	if no_landmarks.uncertain[25] != 1 or landmarks.uncertain[25] != 0 or landmarks.mask.get_pixel(25,0) != Color.RED:
		failures += 1; push_error("Landmark must shift spatial search to labeled source point")
	print("CHECK FAILURES: ",failures)
	quit(1 if failures else 0)
