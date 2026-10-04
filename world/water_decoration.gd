extends RefCounted

# Filename families are the authoring contract. Semi-submerged is a later step.
static func kind(asset_path: String) -> String:
	var filename := asset_path.get_file().get_basename()
	if filename.begins_with("floater_"): return "floater"
	if filename.begins_with("submerged_"): return "submerged"
	return ""

static func render_band(water_kind: String) -> int:
	# Bed (-10), floor props (-3), swimmers (-2), surface (-1), world sprites (0).
	return -3 if water_kind == "submerged" else 0
