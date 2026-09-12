class_name AnchorEncoding
extends RefCounted

const VERSION := 1
const REQUIRED := [&"head", &"origin"]
const OPTIONAL := [&"mouth", &"neck", &"left_wing", &"right_wing", &"tail"]
const SEMANTIC_COLORS := {
	"head": Color8(255, 32, 32), "origin": Color8(32, 255, 32),
	"mouth": Color8(32, 96, 255), "neck": Color8(255, 224, 32),
	"left_wing": Color8(255, 32, 224), "right_wing": Color8(32, 255, 224),
	"tail": Color8(255, 128, 32),
}
const SIGNATURE := [Color8(65, 78, 67), Color8(72, 79, 82), Color8(1, 0, 0)]


static func color_for(anchor_name: String) -> Color:
	if SEMANTIC_COLORS.has(anchor_name):
		return SEMANTIC_COLORS[anchor_name]
	if anchor_name.begins_with("custom_") and anchor_name.trim_prefix("custom_").is_valid_int():
		var custom_id := int(anchor_name.trim_prefix("custom_"))
		if custom_id > 0 and custom_id <= 4194303:
			return Color8(192 + ((custom_id >> 16) & 63), (custom_id >> 8) & 255, custom_id & 255)
	return Color(0, 0, 0, 0)


static func name_for(color: Color) -> String:
	var packed := color.to_rgba32()
	for anchor_name: String in SEMANTIC_COLORS:
		if (SEMANTIC_COLORS[anchor_name] as Color).to_rgba32() == packed:
			return anchor_name
	var r := color.r8
	if color.a8 == 255 and r >= 192:
		var custom_id := ((r - 192) << 16) | (color.g8 << 8) | color.b8
		if custom_id > 0:
			return "custom_%d" % custom_id
	return ""


static func is_signature_color(color: Color) -> bool:
	for signature_color: Color in SIGNATURE:
		if signature_color.to_rgba32() == color.to_rgba32():
			return true
	return false
