class_name BattleSpriteGeometry
extends RefCounted

const MAX_BATTLE_ART_DIMENSION := 200.0


static func processed_size(source_size: Vector2, max_dimension: float = MAX_BATTLE_ART_DIMENSION) -> Vector2:
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return Vector2.ZERO
	var scale_factor := minf(1.0, max_dimension / maxf(source_size.x, source_size.y))
	return source_size * scale_factor


static func process_image(source: Image, max_dimension: float = MAX_BATTLE_ART_DIMENSION, nearest := false) -> Image:
	var result := source.duplicate()
	var size := processed_size(Vector2(source.get_width(), source.get_height()), max_dimension)
	var width := maxi(1, roundi(size.x))
	var height := maxi(1, roundi(size.y))
	if width != source.get_width() or height != source.get_height():
		result.resize(width, height, Image.INTERPOLATE_NEAREST if nearest else Image.INTERPOLATE_BILINEAR)
	return result
