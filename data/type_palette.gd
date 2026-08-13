## Shared, data-driven presentation colors for every elemental type.
## Keep these values dark enough for text on the Dex's light background while
## retaining enough saturation to read clearly in battle effects.
extends RefCounted

const COLORS := {
	"Normal": Color("#544b42"),
	"Fire": Color("#a72d20"),
	"Water": Color("#155ca5"),
	"Plant": Color("#176d32"),
	"Light": Color("#8a6500"),
	"Dark": Color("#4b3268"),
	"Air": Color("#176f96"),
	"Bug": Color("#4f7d18"),
	"Mystic": Color("#8d3fa5"),
	"Ghost": Color("#59458b"),
	"Psychic": Color("#af2f75"),
	"Fighting": Color("#9a3b32")
}

const FALLBACK_COLOR := Color("#18251f")


static func color_for(type_name: String) -> Color:
	return COLORS.get(type_name, FALLBACK_COLOR)
