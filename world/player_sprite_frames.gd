class_name PlayerSpriteFrames
extends RefCounted

# Explicit regions in the authored 1386x1169 atlas. No runtime content analysis.
#Overrides
#MSprite Walk 1: 147x264 Start: 700, 824 End: 845, 823
#MSprite Walk 2: 147x264 Start: 858, 823 End: 1004, 823
#
#FSprite Walk 1 L: 164x264 Start: 17, 824 End: 17, 824
#FSprite Walk 2 L: 164x264 Start: 181, 824 End: 181, 824
#FSprite Walk 1 R: 164x264 Start: 351, 824 End: 514, 824
#FSprite Walk 2 R: 164x264 Start: 517, 824 End: 680, 824

const REGIONS := {
	"Male": {
		"idle_down":[Rect2i(582,72,161,307)],
		"idle_up":[Rect2i(987,81,154,294)],
		"idle_right":[Rect2i(377,77,148,317)],
		"idle_left":[Rect2i(377,77,148,317)],
		"walk_down":[Rect2i(693,458,148,270),Rect2i(861,459,141,272)],
		"walk_up":[Rect2i(1042,462,149,262),Rect2i(1202,462,141,263)],
		"walk_right":[Rect2i(700,824,147,264),Rect2i(858,823,147,264)],
		"walk_left":[Rect2i(700,824,147,264),Rect2i(858,823,147,264)],
	},
	"Female": {
		"idle_down":[Rect2i(777,86,189,294)],
		"idle_up":[Rect2i(1189,93,159,283)],
		"idle_left":[Rect2i(33,82,160,332)],
		"idle_right":[Rect2i(200,83,176,327)],
		"walk_down":[Rect2i(329,466,170,265),Rect2i(495,465,184,266)],
		"walk_up":[Rect2i(1018,820,160,276),Rect2i(1205,820,150,273)],
		"walk_left":[Rect2i(17,824,164,264),Rect2i(181,824,164,264)],
		"walk_right":[Rect2i(351,824,164,264),Rect2i(517,824,164,264)],
	},
}

# Source-sheet rectangles: the neutral pose is stored separately from strides.
# Male left diagonals reuse right-facing art with whole-frame mirroring.
const DIAGONAL_REGIONS := {
	"Male": {
		"idle_up_right":[Rect2i(194,311,112,267)],
		"walk_up_right":[Rect2i(17,15,128,263),Rect2i(11,312,137,263)],
		"idle_up_left":[Rect2i(194,311,112,267)],
		"walk_up_left":[Rect2i(17,15,128,263),Rect2i(11,312,137,263)],
		"idle_down_right":[Rect2i(1486,317,149,268)],
		"walk_down_right":[Rect2i(561,12,149,278),Rect2i(601,312,148,278)],
		"idle_down_left":[Rect2i(1486,317,149,268)],
		"walk_down_left":[Rect2i(561,12,149,278),Rect2i(601,312,148,278)],
	},
	"Female": {
		"idle_up_right":[Rect2i(337,12,155,272)],
		"walk_up_right":[Rect2i(347,324,160,261),Rect2i(1049,315,168,266)],
		# Southeast neutral is on the lower row; the two upper poses stride.
		"idle_down_right":[Rect2i(835,309,153,272)],
		"walk_down_right":[Rect2i(780,13,179,270),Rect2i(1011,10,147,276)],
		"idle_up_left":[Rect2i(1475,8,154,280)],
		"walk_up_left":[Rect2i(1263,12,148,287),Rect2i(1269,327,164,262)],
		# Southwest neutral has both feet planted; the raised-leg pose strides.
		"idle_down_left":[Rect2i(1686,17,161,271)],
		"walk_down_left":[Rect2i(1883,15,151,275),Rect2i(1704,315,162,271)],
	},
}

static func is_diagonal(animation: String) -> bool:
	return animation.get_slice_count("_") == 3

static func frames(gender: String, animation: String, atlas: Texture2D) -> Array[AtlasTexture]:
	var result: Array[AtlasTexture] = []
	var catalog: Dictionary = DIAGONAL_REGIONS if is_diagonal(animation) else REGIONS
	var gender_regions: Dictionary = catalog.get(gender,catalog["Male"])
	assert(gender_regions.has(animation), "Missing player animation: %s" % animation)
	var regions: Array = gender_regions[animation]
	for region: Rect2i in regions:
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = region
		frame.filter_clip = true
		result.append(frame)
	return result
