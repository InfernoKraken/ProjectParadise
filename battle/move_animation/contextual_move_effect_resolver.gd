class_name ContextualMoveEffectResolver
extends RefCounted

const BLOOM_ALIASES := {
	"bloom_bud": "bud",
	"bloom_flower": "flower"
}
const BLOOM_VARIANTS := {
	"generic": {
		"bud": "res://assets/move_effects/Attack_Bloom_Bud_Generic.png",
		"flower": "res://assets/move_effects/Attack_Bloom_Generic.png"
	},
	"orchid": {
		"bud": "res://assets/move_effects/Attack_Bloom_Bud_Orchid.png",
		"flower": "res://assets/move_effects/Attack_Bloom_Orchid.png"
	},
	"birdofparadise": {
		"bud": "res://assets/move_effects/Attack_Bloom_Bud_Birdofparadise.png",
		"flower": "res://assets/move_effects/Attack_Bloom_Birdofparadise.png"
	},
	"ginger": {
		"bud": "res://assets/move_effects/Attack_Bloom_Bud_Generic.png",
		"flower": "res://assets/move_effects/Attack_Bloom_Ginger.png"
	}
}

static func aliases() -> PackedStringArray:
	return PackedStringArray(BLOOM_ALIASES.keys())

static func is_contextual_asset(asset_reference: String) -> bool:
	return BLOOM_ALIASES.has(asset_reference)

static func resolve_asset(asset_reference: String, fakemon_data: Dictionary) -> String:
	if not is_contextual_asset(asset_reference): return asset_reference
	var flower_type := String(fakemon_data.get("flowerType", "")).strip_edges().to_lower()
	if not BLOOM_VARIANTS.has(flower_type): flower_type = "generic"
	var part := String(BLOOM_ALIASES[asset_reference])
	var resolved := String(BLOOM_VARIANTS[flower_type][part])
	if FileAccess.file_exists(resolved): return resolved
	var fallback := String(BLOOM_VARIANTS["generic"][part])
	push_warning("Bloom '%s' asset is missing for flowerType '%s'; using %s." % [part, flower_type, fallback.get_file()])
	return fallback
