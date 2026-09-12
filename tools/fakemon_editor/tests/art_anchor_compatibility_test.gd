extends SceneTree

const Package:=preload("res://tools/fakemon_editor/art_package_model.gd")
const ExistingCodec:=preload("res://tools/fakemon_anchor_editor/core/anchor_map.gd")

func _init()->void:
	var package:=Package.new(ProjectSettings.globalize_path("res://"))
	package.load_package("Slumboth")
	for side in ["Player","Wild"]:
		var image:=Image.load_from_file(package.anchor_path(side))
		var existing:Dictionary=ExistingCodec.extract(image).anchors
		var embedded:Dictionary=package._extract(image)
		assert(existing.keys().size()==embedded.keys().size(),"Embedded authoring must recognize the same v1 anchors.")
		for name in existing:
			assert(embedded.has(name) and (existing[name] as Vector2).is_equal_approx(embedded[name]),"Anchor '%s' must remain coordinate-compatible."%name)
	print("Embedded Art anchors are compatible with the existing Anchor Editor codec.")
	quit()
