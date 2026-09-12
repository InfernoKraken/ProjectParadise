class_name PlayerPalette
extends RefCounted

# The canonical, aligned inputs. Generated appearances are held only in memory.
const SOURCE_PATH := "res://assets/trainers/PlayerSprite.png"
const MASK_PATH := "res://assets/trainers/PlayerSprite_Mask_Aligned.png"
const DIAGONAL_SOURCE_PATH := "res://assets/trainers/Walking_Anim_Diagonal.png"
const DIAGONAL_MASK_PATH := "res://assets/trainers/Walking_Anim_Diagonal_RGB_Mask.png"
const SWIM_SOURCE_PATH := "res://assets/trainers/Player_Swimming Sprites.png"
const SWIM_MASK_PATH := "res://assets/trainers/Player_Swimming Sprites_Mask.png"
const DIVE_SOURCE_PATH := "res://assets/trainers/Diving In Sprite.png"
const DIVE_MASK_PATH := "res://assets/trainers/Diving In Sprite Mask.png"
const DEFAULT_PRESET := "medium"

# Source RGB -> semantic role. Inventories are intentionally material-specific.
const HAIR_SOURCE_ROLES := {
	"000000":"deepest", "010000":"deepest", "150b08":"deepest", "22120d":"deepest",
	"292018":"deep_shadow", "2f1811":"deep_shadow", "352a20":"shadow",
	"3b1f16":"shadow", "403529":"shadow", "48261b":"shadow",
	"4f3e2f":"base", "562c20":"base", "663524":"base",
	"5e4a38":"light", "6d5741":"light", "783f2a":"light", "8b5239":"light", "924325":"light",
	"7e674c":"highlight", "8b7a61":"highlight", "9f6346":"highlight", "ae512c":"highlight", "b27351":"highlight", "c75e32":"highlight",
	"a58d73":"shine", "c4815d":"shine", "c4a990":"shine", "cf916d":"shine", "da6b39":"shine", "e97942":"shine", "f3854c":"shine", "f89057":"shine", "f2d6c2":"shine", "f9eee2":"shine",
	"465544":"light", "606d59":"highlight",
}
const SKIN_SOURCE_ROLES := {
	"000000":"outline", "010000":"outline", "150b08":"outline", "22120d":"outline",
	"292018":"deep_shadow", "2f1811":"deep_shadow", "352a20":"deep_shadow", "3b1f16":"deep_shadow",
	"403529":"shadow", "48261b":"shadow", "562c20":"shadow",
	"4f3e2f":"deep_base", "5e4a38":"deep_base", "663524":"deep_base", "783f2a":"deep_base",
	"6d5741":"base", "7e674c":"base", "8b5239":"base", "924325":"base", "9f6346":"base", "ae512c":"base",
	"b27351":"light", "c4815d":"light", "c75e32":"light", "da6b39":"light",
	"cf916d":"highlight", "dea079":"highlight", "e97942":"highlight", "f3854c":"highlight", "f89057":"highlight",
	"c4a990":"shine", "eab089":"shine", "ebc0a6":"shine", "f8a370":"shine", "fa9960":"shine",
}

const SKIN_MEDIUM := {
	"outline":Color8(72,38,27), "deep_shadow":Color8(102,53,36),
	"shadow":Color8(146,67,37), "deep_base":Color8(174,81,44),
	"base":Color8(218,107,57), "light":Color8(233,121,66),
	"highlight":Color8(248,144,87), "shine":Color8(250,163,112),
}
const SKIN_LIGHT := {
	"outline":Color8(103,55,43), "deep_shadow":Color8(139,78,59),
	"shadow":Color8(178,108,78), "deep_base":Color8(205,133,96),
	"base":Color8(232,158,115), "light":Color8(244,177,135),
	"highlight":Color8(255,198,158), "shine":Color8(255,218,184),
}
const SKIN_DARK := {
	"outline":Color8(40,22,18), "deep_shadow":Color8(63,32,24),
	"shadow":Color8(91,46,31), "deep_base":Color8(119,60,39),
	"base":Color8(150,78,49), "light":Color8(181,101,65),
	"highlight":Color8(208,130,89), "shine":Color8(231,166,121),
}
const HAIR_MEDIUM_BROWN := {
	"deepest":Color8(21,11,8), "deep_shadow":Color8(34,18,13),
	"shadow":Color8(59,31,22), "base":Color8(86,44,32),
	"light":Color8(120,63,42), "highlight":Color8(159,99,70),
	"shine":Color8(196,129,93),
}
const HAIR_BLONDE := {
	"deepest":Color8(48,40,32), "deep_shadow":Color8(70,58,42),
	"shadow":Color8(96,82,55), "base":Color8(133,112,70),
	"light":Color8(184,157,97), "highlight":Color8(218,199,143),
	"shine":Color8(245,232,190),
}
const HAIR_RED := {
	"deepest":Color8(54,20,16), "deep_shadow":Color8(82,28,21),
	"shadow":Color8(117,40,28), "base":Color8(157,56,38),
	"light":Color8(193,77,52), "highlight":Color8(224,112,76),
	"shine":Color8(248,160,115),
}
const HAIR_BLACK := {
	"deepest":Color8(12,14,19), "deep_shadow":Color8(25,27,34),
	"shadow":Color8(38,40,48), "base":Color8(56,58,67),
	"light":Color8(73,76,85), "highlight":Color8(103,105,114),
	"shine":Color8(142,146,156),
}
const PRESETS := {
	"medium":{"skin":SKIN_MEDIUM,"hair":HAIR_MEDIUM_BROWN},
	"light_blonde":{"skin":SKIN_LIGHT,"hair":HAIR_BLONDE},
	"light_red":{"skin":SKIN_LIGHT,"hair":HAIR_RED},
	"dark_black":{"skin":SKIN_DARK,"hair":HAIR_BLACK},
}
static var _texture_cache: Dictionary = {}

static func create_texture(preset_name: String, sheet: String = "cardinal") -> Texture2D:
	assert(PRESETS.has(preset_name), "Player palette must name an explicit appearance: %s" % preset_name)
	assert(sheet in ["cardinal", "diagonal", "swim", "dive"], "Unknown player atlas: %s" % sheet)
	var resolved := preset_name
	var cache_key := sheet + ":" + resolved
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var source_paths := {"cardinal":SOURCE_PATH, "diagonal":DIAGONAL_SOURCE_PATH, "swim":SWIM_SOURCE_PATH, "dive":DIVE_SOURCE_PATH}
	var mask_paths := {"cardinal":MASK_PATH, "diagonal":DIAGONAL_MASK_PATH, "swim":SWIM_MASK_PATH, "dive":DIVE_MASK_PATH}
	var source := _load_png(source_paths[sheet])
	var mask := _load_png(mask_paths[sheet])
	assert(source.get_size() == mask.get_size(), "Player sprite and mask dimensions must match exactly.")
	# The canonical sheet is fully opaque RGB; RGBA is required for the exact
	# background pixel to become transparent in the generated runtime texture.
	source.convert(Image.FORMAT_RGBA8)
	var preset: Dictionary = PRESETS[resolved]
	var auxiliary_sheet := sheet in ["swim", "dive"]
	var tolerant_mask := sheet == "swim"
	for y in source.get_height():
		for x in source.get_width():
			var original := source.get_pixel(x,y)
			var source_rgb := original.to_html(false)
			var mask_color := mask.get_pixel(x,y)
			var mask_rgb := mask_color.to_html(false)
			var is_dive_chroma := sheet == "dive" and original.g > 0.9 and original.r < 0.1 and original.b < 0.1
			var is_hair := mask_rgb == "ff0000" or (tolerant_mask and mask_color.r > 0.5 and mask_color.r > mask_color.g * 1.5 and mask_color.r > mask_color.b * 1.5)
			var is_skin := mask_rgb == "00ff00" or (tolerant_mask and mask_color.g > 0.5 and mask_color.g > mask_color.r * 1.5 and mask_color.g > mask_color.b * 1.5)
			if is_dive_chroma:
				# The proportional diving art deliberately uses a pure-green source
				# background. Clear it before consulting the slightly offset semantic
				# mask so background between limbs/bags cannot become palette color.
				source.set_pixel(x,y,Color(original.r,original.g,original.b,0.0))
			elif is_hair and (HAIR_SOURCE_ROLES.has(source_rgb) or auxiliary_sheet):
				var hair_role: String = HAIR_SOURCE_ROLES.get(source_rgb, _auxiliary_role(original, true))
				source.set_pixel(x,y,preset["hair"][hair_role])
			elif is_skin and (SKIN_SOURCE_ROLES.has(source_rgb) or auxiliary_sheet):
				var skin_role: String = SKIN_SOURCE_ROLES.get(source_rgb, _auxiliary_role(original, false))
				source.set_pixel(x,y,preset["skin"][skin_role])
			elif mask_rgb == "ffffff" and (auxiliary_sheet or source_rgb == "010000" or source_rgb == "000000"):
				# Corrected auxiliary masks are authoritative for transparency.
				# Their source backgrounds contain antialiased near-black pixels,
				# so checking source RGB would leave rectangular crop fragments.
				source.set_pixel(x,y,Color(original.r,original.g,original.b,0.0))
	var texture := ImageTexture.create_from_image(source)
	_texture_cache[cache_key] = texture
	return texture


static func _auxiliary_role(color: Color, hair: bool) -> String:
	var value := maxf(color.r, maxf(color.g, color.b))
	if hair:
		if value < 0.05: return "deepest"
		if value < 0.12: return "deep_shadow"
		if value < 0.24: return "shadow"
		if value < 0.38: return "base"
		if value < 0.55: return "light"
		if value < 0.75: return "highlight"
		return "shine"
	if value < 0.08: return "outline"
	if value < 0.18: return "deep_shadow"
	if value < 0.32: return "shadow"
	if value < 0.46: return "deep_base"
	if value < 0.62: return "base"
	if value < 0.76: return "light"
	if value < 0.9: return "highlight"
	return "shine"

static func _load_png(path: String) -> Image:
	var image := Image.new()
	var error := image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	assert(error == OK, "Player palette PNG could not be read: %s" % path)
	return image
