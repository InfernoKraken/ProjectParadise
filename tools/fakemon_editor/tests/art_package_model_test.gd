extends SceneTree

const Package:=preload("res://art_package_model.gd")

func _init()->void:
	var game_root:=ProjectSettings.globalize_path("res://../..").simplify_path()
	var package:=Package.new(game_root)
	package.load_package("Slumboth")
	assert(package.package_ids().has("Slumboth"),"Existing package IDs must be discovered from canonical filenames.")
	for key in Package.MEMBERS:assert(package.image_for(key)!=null,"Slumboth package must resolve %s."%key)
	assert(package.anchors.Player.has("head") and package.anchors.Player.has("origin"),"Existing v1 Player anchor map must load required anchors.")
	assert(package.anchors.Wild.has("head") and package.anchors.Wild.has("origin"),"Player and Wild anchor documents must load independently.")
	var original_path:=package.path_for("player")
	var original_time:=FileAccess.get_modified_time(original_path)
	assert(package.stage("player",original_path),package.error)
	assert(package.is_dirty() and package.affected_files()==["Slumboth_Player.png"],"Selecting an image must stage exactly one member without writing it.")
	assert(FileAccess.get_modified_time(original_path)==original_time,"Staging must not touch the destination file.")
	assert(package.replacement_warning("Player").contains("review"),"Same-size battle replacements must still require anchor review.")
	package.unstage("player")
	assert(not package.is_dirty(),"Unstaging an unchanged package must restore clean state.")
	print("Fakemon Art Package model: 12 assertions passed")
	quit()
