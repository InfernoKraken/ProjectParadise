extends SceneTree

const AnchorMapCodec := preload("res://tools/fakemon_anchor_editor/core/anchor_map.gd")
const Validator := preload("res://tools/fakemon_anchor_editor/core/anchor_validator.gd")

const CASES := {
	"Lochirp_Player": {"head": Vector2i(81, 21), "origin": Vector2i(65, 71), "mouth": Vector2i(103, 30)},
	"Lochirp_Wild": {"head": Vector2i(45, 21), "origin": Vector2i(62, 71), "mouth": Vector2i(24, 30)},
	"Flambian_Player": {"head": Vector2i(140, 58), "origin": Vector2i(137, 147), "mouth": Vector2i(160, 71)},
	"Flambian_Wild": {"head": Vector2i(115, 58), "origin": Vector2i(119, 147), "mouth": Vector2i(91, 71)},
}


func _init() -> void:
	var generated := {"format_version": 1, "sprites": {}}
	for sprite_key: String in CASES:
		var source_path := "res://assets/fakemon/battle/%s.png" % sprite_key
		var source := Image.load_from_file(ProjectSettings.globalize_path(source_path))
		var anchor_image := AnchorMapCodec.create_image(source.get_size(), CASES[sprite_key])
		var errors := Validator.validate(source, anchor_image)
		if not errors.is_empty():
			push_error("%s: %s" % [sprite_key, errors])
			quit(1)
			return
		anchor_image.save_png(ProjectSettings.globalize_path(source_path.trim_suffix(".png") + ".anchors.png"))
		var processed := AnchorMapCodec.process_and_extract(anchor_image)
		var points := {}
		for anchor_name: String in processed.anchors:
			var point: Vector2 = processed.anchors[anchor_name]
			points[anchor_name] = [snappedf(point.x, 0.001), snappedf(point.y, 0.001)]
		generated.sprites[sprite_key] = {"processed_size": [processed.image.get_width(), processed.image.get_height()], "anchors": points}
		var changed := AnchorMapCodec.process_and_extract(anchor_image, 100.0)
		assert(changed.image.get_size() != processed.image.get_size())
		assert((changed.anchors.origin as Vector2).distance_to(processed.anchors.origin as Vector2) > 1.0)
		print("%s: source=%s processed=%s origin=%s regenerated@100=%s" % [sprite_key, source.get_size(), processed.image.get_size(), processed.anchors.origin, changed.anchors.origin])
	var file := FileAccess.open("res://data/generated_battle_anchors.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(generated, "  ") + "\n")
	print("Manual acceptance anchor maps and runtime coordinates generated.")
	quit(0)
