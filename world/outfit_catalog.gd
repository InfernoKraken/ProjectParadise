extends RefCounted

const Outfit := preload("res://world/outfit_data.gd")
const DIRECTORY := "res://data/outfits"

static func find(outfit_id: String) -> Resource:
	if outfit_id.is_empty():
		return null
	for filename in ResourceLoader.list_directory(DIRECTORY):
		if not filename.ends_with(".tres"):
			continue
		var outfit := load(DIRECTORY.path_join(filename)) as Outfit
		if outfit != null and outfit.outfit_id == outfit_id:
			return outfit
	return null
