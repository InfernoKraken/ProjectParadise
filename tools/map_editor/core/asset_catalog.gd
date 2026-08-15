class_name AssetCatalog
extends RefCounted

var entries: Array = []
var by_id: Dictionary = {}
var error := ""

static func load_catalog(path: String) -> AssetCatalog:
	var catalog := AssetCatalog.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: catalog.error = "Could not open asset catalog."; return catalog
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		catalog.error = "Invalid asset catalog JSON."; return catalog
	catalog.entries = json.data.get("entries", [])
	for entry in catalog.entries: catalog.by_id[String(entry.get("type_id", ""))] = entry
	return catalog

func for_field(field: String) -> Dictionary:
	for entry in entries:
		for candidate in entry.get("serialization", {}).get("fields", []):
			if String(candidate) == field: return entry
	return {}

