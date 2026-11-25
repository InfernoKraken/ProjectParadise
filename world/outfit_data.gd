class_name OutfitData
extends Resource

@export var outfit_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_enum("Male", "Female") var body_type: String = "Male"
@export var atlas: Texture2D
## Animation name -> Array of Rect2 regions, indexed by the player's canonical
## pose index (zero based). Include all five poses for walk animations.
@export var frame_regions: Dictionary = {}
@export var icon: Texture2D
@export_range(0, 100000000) var price: int = 0
@export var category: String = "casual"
## Animation name -> Array of Texture2D masks by canonical pose index.
## Each mask covers the full frame canvas; alpha 1 hides base pixels only.
@export var visibility_masks: Dictionary = {}
## Every region is centered and foot-aligned within this common canvas.
@export var frame_size: Vector2i = Vector2i(208, 336)

var _frames: Dictionary = {}

func visibility_mask(animation: String, index: int) -> Texture2D:
	var masks: Array = visibility_masks.get(animation, [])
	if index < 0 or index >= masks.size():
		return null
	return masks[index] as Texture2D

func frame(animation: String, index: int) -> Texture2D:
	var regions: Array = frame_regions.get(animation, [])
	if atlas == null or index < 0 or index >= regions.size():
		return null
	var key := "%s:%d" % [animation, index]
	if _frames.has(key):
		return _frames[key]
	var region := Rect2(regions[index])
	if region.size.x <= 0 or region.size.y <= 0 or not Rect2(Vector2.ZERO, atlas.get_size()).encloses(region):
		return null
	if region.size.x > frame_size.x or region.size.y > frame_size.y:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = region
	texture.margin = Rect2(Vector2((frame_size.x - region.size.x) / 2.0, frame_size.y - region.size.y), Vector2(frame_size) - region.size)
	texture.filter_clip = true
	_frames[key] = texture
	return texture

## Call after changing atlas/regions on an existing resource at runtime.
func clear_frame_cache() -> void:
	_frames.clear()
