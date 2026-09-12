extends SceneTree

const Encoding := preload("res://tools/fakemon_anchor_editor/core/anchor_encoding.gd")
const AnchorMapCodec := preload("res://tools/fakemon_anchor_editor/core/anchor_map.gd")
const Validator := preload("res://tools/fakemon_anchor_editor/core/anchor_validator.gd")
const Geometry := preload("res://battle/battle_sprite_geometry.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_save_load_ids()
	_test_required_and_optional_validation()
	_test_customs_and_independence()
	_test_duplicates()
	_test_centroid()
	_test_resize_and_geometry()
	_test_processing_size_regeneration()
	_test_malformed_and_dimensions()
	if failures.is_empty():
		print("Fakemon Anchor Editor: 12 tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _source(size := Vector2i(32, 24)) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return image


func _valid_map(size := Vector2i(32, 24)) -> Image:
	return AnchorMapCodec.create_image(size, {"head": Vector2i(8, 7), "origin": Vector2i(16, 17)})


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _test_save_load_ids() -> void:
	var result := AnchorMapCodec.extract(AnchorMapCodec.create_image(Vector2i(40, 30), {"head": Vector2i(8, 8), "origin": Vector2i(20, 20), "mouth": Vector2i(12, 12)}))
	_check(result.anchors.has("head") and result.anchors.has("origin") and result.anchors.has("mouth"), "Saving/loading known anchor IDs failed.")


func _test_required_and_optional_validation() -> void:
	var missing := AnchorMapCodec.create_image(Vector2i(32, 24), {"origin": Vector2i(16, 17)})
	_check(_has_error(Validator.validate(_source(), missing), "head"), "Missing required head was not rejected.")
	_check(Validator.validate(_source(), _valid_map()).is_empty(), "Absent optional anchors should be valid.")


func _test_customs_and_independence() -> void:
	var player := AnchorMapCodec.create_image(Vector2i(40, 30), {"head": Vector2i(8, 8), "origin": Vector2i(20, 20), "custom_1": Vector2i(28, 8), "custom_9000": Vector2i(30, 20)})
	var wild := AnchorMapCodec.create_image(Vector2i(40, 30), {"head": Vector2i(10, 10), "origin": Vector2i(25, 20)})
	var player_result := AnchorMapCodec.extract(player)
	var wild_result := AnchorMapCodec.extract(wild)
	_check(player_result.anchors.has("custom_1") and player_result.anchors.has("custom_9000"), "Multiple custom anchors did not round-trip.")
	_check(not wild_result.anchors.has("custom_1") and player_result.anchors.origin != wild_result.anchors.origin, "Player and Wild maps are not independent.")


func _test_duplicates() -> void:
	var image := _valid_map(Vector2i(50, 30))
	AnchorMapCodec.paint_marker(image, "head", Vector2i(40, 20))
	_check((AnchorMapCodec.extract(image).duplicates as Array).has("head"), "Duplicate semantic marker was not detected.")


func _test_centroid() -> void:
	var result := AnchorMapCodec.extract(_valid_map())
	_check((result.anchors.head as Vector2).is_equal_approx(Vector2(8, 7)), "Marker centroid extraction was incorrect.")


func _test_resize_and_geometry() -> void:
	var map := AnchorMapCodec.create_image(Vector2i(100, 50), {"head": Vector2i(20, 10), "origin": Vector2i(80, 40)})
	var result := AnchorMapCodec.process_and_extract(map, 50.0)
	_check(result.anchors.has("head") and result.image.get_size() == Vector2i(50, 25), "Nearest-neighbor resize did not preserve markers.")
	_check((result.anchors.head as Vector2).distance_to(Vector2(10, 5)) <= 1.0, "Resize produced an unexpected transformed position.")
	# The current real pipeline has no crop. This synthetic crop verifies that cropping
	# before the shared resize gives the expected translated point if crop is later added.
	var cropped := map.get_region(Rect2i(10, 5, 80, 40))
	var cropped_result := AnchorMapCodec.process_and_extract(cropped, 40.0)
	_check((cropped_result.anchors.head as Vector2).distance_to(Vector2(5, 2.5)) <= 1.0, "Crop + resize transformed position was unexpected.")


func _test_processing_size_regeneration() -> void:
	var map := AnchorMapCodec.create_image(Vector2i(100, 50), {"head": Vector2i(20, 10), "origin": Vector2i(80, 40)})
	var large: Vector2 = AnchorMapCodec.process_and_extract(map, 80.0).anchors.origin
	var small: Vector2 = AnchorMapCodec.process_and_extract(map, 40.0).anchors.origin
	_check(small.distance_to(large * 0.5) <= 1.0, "Regeneration after processing-size change did not move coordinates.")
	_check(Geometry.processed_size(Vector2(400, 200), 200.0) == Vector2(200, 100), "Shared battle geometry scale is incorrect.")


func _test_malformed_and_dimensions() -> void:
	var malformed := _valid_map()
	malformed.set_pixel(30, 20, Color8(100, 101, 102))
	_check(_has_error(Validator.validate(_source(), malformed), "unknown"), "Unknown marker encoding did not fail clearly.")
	_check(_has_error(Validator.validate(_source(Vector2i(31, 24)), _valid_map()), "dimensions"), "Dimension mismatch did not fail clearly.")


func _has_error(errors: Array[String], fragment: String) -> bool:
	for error in errors:
		if fragment.to_lower() in error.to_lower():
			return true
	return false
