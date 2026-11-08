class_name SwimSpriteFrames
extends RefCounted

# Explicit crops from the authored, labelled swimming and diving sheets. Keeping
# these here makes the runtime independent of image-content scanning.
# Updated swimming sheet: four columns, with separate padded direction rows.
const SWIM_REGIONS := {
	"Male": {
		"down": [Rect2i(180, 0, 350, 126), Rect2i(560, 0, 350, 126), Rect2i(945, 0, 350, 126), Rect2i(1325, 0, 350, 126)],
		"up": [Rect2i(180, 128, 350, 116), Rect2i(560, 128, 350, 116), Rect2i(945, 128, 350, 116), Rect2i(1325, 128, 350, 116)],
		"left": [Rect2i(180, 250, 350, 126), Rect2i(560, 250, 350, 126), Rect2i(945, 250, 350, 126), Rect2i(1325, 250, 350, 126)],
		"right": [Rect2i(180, 376, 350, 120), Rect2i(560, 376, 350, 120), Rect2i(945, 376, 350, 120), Rect2i(1325, 376, 350, 120)],
	},
	"Female": {
		"down": [Rect2i(180, 684, 350, 132), Rect2i(560, 684, 350, 132), Rect2i(945, 684, 350, 132), Rect2i(1325, 684, 350, 132)],
		"up": [Rect2i(180, 816, 350, 116), Rect2i(560, 816, 350, 116), Rect2i(945, 816, 350, 116), Rect2i(1325, 816, 350, 116)],
		"left": [Rect2i(180, 944, 350, 122), Rect2i(560, 944, 350, 122), Rect2i(945, 944, 350, 122), Rect2i(1325, 944, 350, 122)],
		"right": [Rect2i(180, 1074, 350, 126), Rect2i(560, 1074, 350, 126), Rect2i(945, 1074, 350, 126), Rect2i(1325, 1074, 350, 126)],
	},
}

const DIVE_REGIONS := {
	"Male": {
		"down": [Rect2i(84, 80, 105, 231), Rect2i(503, 80, 190, 231), Rect2i(1243, 80, 105, 231), Rect2i(1610, 80, 138, 231), Rect2i(2042, 80, 158, 231)],
		"up": [Rect2i(209, 80, 104, 231), Rect2i(725, 80, 192, 231), Rect2i(1348, 80, 120, 231), Rect2i(1761, 80, 133, 231), Rect2i(2202, 80, 146, 231)],
		"right": [Rect2i(337, 80, 98, 231), Rect2i(972, 80, 197, 231), Rect2i(1468, 80, 121, 231), Rect2i(1910, 80, 113, 231), Rect2i(2349, 80, 151, 231)],
	},
	"Female": {
		"down": [Rect2i(83, 400, 124, 231), Rect2i(496, 400, 199, 231), Rect2i(1243, 400, 105, 231), Rect2i(1602, 400, 149, 231), Rect2i(2037, 400, 163, 231)],
		"up": [Rect2i(213, 400, 113, 231), Rect2i(730, 400, 197, 231), Rect2i(1348, 400, 120, 231), Rect2i(1765, 400, 125, 231), Rect2i(2202, 400, 146, 231)],
		"right": [Rect2i(329, 400, 108, 231), Rect2i(994, 400, 198, 231), Rect2i(1468, 400, 123, 231), Rect2i(1899, 400, 118, 231), Rect2i(2349, 400, 151, 231)],
	},
}

static func frames(gender: String, direction: String, atlas: Texture2D) -> Array[AtlasTexture]:
	var resolved_gender := gender if SWIM_REGIONS.has(gender) else "Male"
	var regions: Array = SWIM_REGIONS[resolved_gender].get(direction, SWIM_REGIONS[resolved_gender]["down"])
	var result: Array[AtlasTexture] = []
	for region: Rect2i in regions:
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = region
		frame.filter_clip = true
		result.append(frame)
	return result


static func dive_actor_frame(gender: String, direction: String, stage: int, atlas: Texture2D) -> AtlasTexture:
	# Actor stages are neutral, throw, neutral, then jump. Backpack-land and
	# splash are separate effects anchored to the destination water tile.
	var source_index: int = int([0, 1, 0, 3][clampi(stage, 0, 3)])
	return _dive_frame(gender, direction, source_index, atlas)


static func dive_effect_frame(gender: String, direction: String, splash: bool, atlas: Texture2D) -> AtlasTexture:
	return _dive_frame(gender, direction, 4 if splash else 2, atlas)


static func _dive_frame(gender: String, direction: String, index: int, atlas: Texture2D) -> AtlasTexture:
	var resolved_gender := gender if DIVE_REGIONS.has(gender) else "Male"
	var resolved_direction := "right" if direction == "left" else direction
	var regions: Array = DIVE_REGIONS[resolved_gender].get(resolved_direction, DIVE_REGIONS[resolved_gender]["down"])
	var frame := AtlasTexture.new()
	frame.atlas = atlas
	frame.region = regions[index]
	frame.filter_clip = true
	return frame
