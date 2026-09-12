class_name AnchorValidator
extends RefCounted

const Encoding := preload("res://tools/fakemon_anchor_editor/core/anchor_encoding.gd")
const AnchorMapCodec := preload("res://tools/fakemon_anchor_editor/core/anchor_map.gd")


static func validate(source: Image, anchor_map: Image, max_dimension := 200.0) -> Array[String]:
	var errors := AnchorMapCodec.validate_signature(anchor_map)
	if source.get_size() != anchor_map.get_size():
		errors.append("Anchor map dimensions %s differ from source sprite dimensions %s." % [anchor_map.get_size(), source.get_size()])
	var source_result := AnchorMapCodec.extract(anchor_map)
	for required: StringName in Encoding.REQUIRED:
		if not source_result.anchors.has(String(required)):
			errors.append("Required anchor '%s' is missing." % required)
	for duplicate: String in source_result.duplicates:
		errors.append("Anchor '%s' has multiple marker regions." % duplicate)
	if not source_result.unknown_pixels.is_empty():
		errors.append("Anchor map contains %d pixels with unknown marker colors." % source_result.unknown_pixels.size())
	var processed := AnchorMapCodec.process_and_extract(anchor_map, max_dimension)
	for anchor_name: String in source_result.anchors:
		if not processed.anchors.has(anchor_name):
			errors.append("Anchor '%s' is not detectable after processing." % anchor_name)
			continue
		var point: Vector2 = processed.anchors[anchor_name]
		if point.x < 0 or point.y < 0 or point.x >= processed.image.get_width() or point.y >= processed.image.get_height():
			errors.append("Processed anchor '%s' is outside the sprite bounds." % anchor_name)
	return errors
