extends RefCounted

# Shared by the standalone map editor and gameplay. Paths are project-relative.
const DEFAULT := "generic"
const INDOOR := {
	"generic": {"label": "Generic (default)", "texture": "assets/overworld/warp_building_generic.png"},
	"jalovea": {"label": "Jalovea Rug", "texture": "assets/overworld/rug_warp_jalovea.png"},
}

static func texture_path(variation: String) -> String:
	return String(INDOOR.get(variation, INDOOR[DEFAULT]).texture)
