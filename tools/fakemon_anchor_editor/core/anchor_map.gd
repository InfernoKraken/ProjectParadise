class_name AnchorMap
extends RefCounted

const Encoding := preload("res://tools/fakemon_anchor_editor/core/anchor_encoding.gd")
const Geometry := preload("res://battle/battle_sprite_geometry.gd")
const MARKER_RADIUS := 2


static func create_image(size: Vector2i, anchors: Dictionary) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for index in mini(Encoding.SIGNATURE.size(), size.x):
		image.set_pixel(index, 0, Encoding.SIGNATURE[index])
	for anchor_name: String in anchors:
		paint_marker(image, anchor_name, anchors[anchor_name])
	return image


static func paint_marker(image: Image, anchor_name: String, center: Vector2i) -> void:
	var color := Encoding.color_for(anchor_name)
	for y in range(center.y - MARKER_RADIUS, center.y + MARKER_RADIUS + 1):
		for x in range(center.x - MARKER_RADIUS, center.x + MARKER_RADIUS + 1):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)


static func validate_signature(image: Image) -> Array[String]:
	var errors: Array[String] = []
	if image.get_width() < Encoding.SIGNATURE.size():
		return ["Anchor map is too narrow to contain its v1 encoding signature."]
	for index in Encoding.SIGNATURE.size():
		if image.get_pixel(index, 0).to_rgba32() != (Encoding.SIGNATURE[index] as Color).to_rgba32():
			errors.append("Unrecognized or missing anchor encoding signature (expected v1).")
			break
	return errors


static func extract(image: Image) -> Dictionary:
	var pixels_by_name := {}
	var unknown: Array[Vector2i] = []
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a8 == 0 or Encoding.is_signature_color(color):
				continue
			var anchor_name := Encoding.name_for(color)
			if anchor_name.is_empty():
				unknown.append(Vector2i(x, y))
			else:
				pixels_by_name.get_or_add(anchor_name, []).append(Vector2i(x, y))
	var anchors := {}
	var duplicates: Array[String] = []
	for anchor_name: String in pixels_by_name:
		var regions := _connected_regions(pixels_by_name[anchor_name])
		if regions.size() > 1:
			duplicates.append(anchor_name)
		var sum := Vector2.ZERO
		var count := 0
		for region: Array in regions:
			for pixel: Vector2i in region:
				sum += Vector2(pixel)
				count += 1
		if count > 0:
			anchors[anchor_name] = sum / count
	return {"anchors": anchors, "duplicates": duplicates, "unknown_pixels": unknown}


static func process_and_extract(image: Image, max_dimension := Geometry.MAX_BATTLE_ART_DIMENSION) -> Dictionary:
	var processed := Geometry.process_image(image, max_dimension, true)
	var result := extract(processed)
	result["image"] = processed
	return result


static func _connected_regions(pixels: Array) -> Array:
	var remaining := {}
	for pixel: Vector2i in pixels:
		remaining[pixel] = true
	var regions := []
	while not remaining.is_empty():
		var seed: Vector2i = remaining.keys()[0]
		remaining.erase(seed)
		var region: Array[Vector2i] = [seed]
		var queue: Array[Vector2i] = [seed]
		while not queue.is_empty():
			var current: Vector2i = queue.pop_back()
			for neighbor in [current + Vector2i.LEFT, current + Vector2i.RIGHT, current + Vector2i.UP, current + Vector2i.DOWN]:
				if remaining.erase(neighbor):
					region.append(neighbor)
					queue.append(neighbor)
		regions.append(region)
	return regions
