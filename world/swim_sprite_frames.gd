class_name SwimSpriteFrames
extends RefCounted

# Explicit crops from the authored, labelled swimming and diving sheets. Keeping
# these here makes the runtime independent of image-content scanning.
const SWIM_REGIONS := {
	"Male": {
		"down": [Rect2i(180, 5, 350, 105), Rect2i(560, 5, 350, 105), Rect2i(945, 5, 350, 105), Rect2i(1325, 5, 350, 105)],
		"up": [Rect2i(180, 110, 350, 108), Rect2i(560, 110, 350, 108), Rect2i(945, 110, 350, 108), Rect2i(1325, 110, 350, 108)],
		"left": [Rect2i(180, 218, 350, 105), Rect2i(560, 218, 350, 105), Rect2i(945, 218, 350, 105), Rect2i(1325, 218, 350, 105)],
		"right": [Rect2i(180, 323, 350, 107), Rect2i(560, 323, 350, 107), Rect2i(945, 323, 350, 107), Rect2i(1325, 323, 350, 107)],
	},
	"Female": {
		"down": [Rect2i(180, 439, 350, 111), Rect2i(560, 439, 350, 111), Rect2i(945, 439, 350, 111), Rect2i(1325, 439, 350, 111)],
		"up": [Rect2i(180, 550, 350, 99), Rect2i(560, 550, 350, 99), Rect2i(945, 550, 350, 99), Rect2i(1325, 550, 350, 99)],
		"left": [Rect2i(180, 653, 350, 111), Rect2i(560, 653, 350, 111), Rect2i(945, 653, 350, 111), Rect2i(1325, 653, 350, 111)],
		"right": [Rect2i(180, 764, 350, 111), Rect2i(560, 764, 350, 111), Rect2i(945, 764, 350, 111), Rect2i(1325, 764, 350, 111)],
	},
}

const DIVE_REGIONS := {
	"Male": {
		"down": [Rect2i(84, 80, 105, 235), Rect2i(503, 80, 190, 235), Rect2i(1243, 80, 105, 235), Rect2i(1610, 80, 138, 235), Rect2i(2042, 80, 158, 235)],
		"up": [Rect2i(209, 80, 104, 235), Rect2i(725, 80, 192, 235), Rect2i(1348, 80, 120, 235), Rect2i(1761, 80, 133, 235), Rect2i(2202, 80, 146, 235)],
		"right": [Rect2i(337, 80, 98, 235), Rect2i(972, 80, 197, 235), Rect2i(1468, 80, 121, 235), Rect2i(1910, 80, 113, 235), Rect2i(2349, 80, 151, 235)],
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
