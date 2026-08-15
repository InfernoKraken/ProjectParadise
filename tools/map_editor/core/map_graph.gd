class_name MapGraph
extends RefCounted

const CONNECTIONS := [
	["rainforest_clearing.json", "canopy_route.json", "north_warp", "entry", "exit_warp", "north_return"],
	["canopy_route.json", "eastern_rainforest_route.json", "east_warp", "entry", "return_warp", "east_return"],
	["canopy_route.json", "western_rainforest_route.json", "west_warp", "entry", "return_warp", "west_return"],
	["canopy_route.json", "mossvale_city.json", "north_warp", "entry", "return_warp", "north_return"],
	["eastern_rainforest_route.json", "vinestone_cave.json", "cave_warp", "entry", "exit_warp", "cave_return"]
]

const WARP_ENDPOINTS := {
	"rainforest_clearing.json|$.north_warp": {"map":"canopy_route.json", "target_path":"$.entry", "label":"Enter Canopy Route"},
	"canopy_route.json|$.exit_warp": {"map":"rainforest_clearing.json", "target_path":"$.north_return", "label":"Return to Rainforest Clearing"},
	"canopy_route.json|$.east_warp": {"map":"eastern_rainforest_route.json", "target_path":"$.entry", "label":"Enter Eastern Rainforest Route"},
	"canopy_route.json|$.west_warp": {"map":"western_rainforest_route.json", "target_path":"$.entry", "label":"Enter Western Rainforest Route"},
	"canopy_route.json|$.north_warp": {"map":"mossvale_city.json", "target_path":"$.entry", "label":"Enter Mossvale City"},
	"eastern_rainforest_route.json|$.return_warp": {"map":"canopy_route.json", "target_path":"$.east_return", "label":"Return to Canopy Route"},
	"eastern_rainforest_route.json|$.cave_warp": {"map":"vinestone_cave.json", "target_path":"$.entry", "label":"Enter Vinestone Cave"},
	"western_rainforest_route.json|$.return_warp": {"map":"canopy_route.json", "target_path":"$.west_return", "label":"Return to Canopy Route"},
	"vinestone_cave.json|$.exit_warp": {"map":"eastern_rainforest_route.json", "target_path":"$.cave_return", "label":"Exit Vinestone Cave"},
	"mossvale_city.json|$.return_warp": {"map":"canopy_route.json", "target_path":"$.north_return", "label":"Return to Canopy Route"},
	"rainforest_clearing.json|$.building.door": {"map":"rainforest_medical_ward.json", "target_path":"$.entry", "label":"Enter Medical Ward"},
	"rainforest_medical_ward.json|$.exit_door": {"map":"rainforest_clearing.json", "target_path":"$.exterior_return", "target_source":"rainforest_medical_ward.json", "label":"Exit Medical Ward"},
	"rainforest_house.json|$.door": {"map":"rainforest_house.json", "target_path":"$.entry", "label":"Enter Rainforest House"},
	"rainforest_house.json|$.exit_door": {"map":"rainforest_clearing.json", "target_path":"$.exterior_return", "target_source":"rainforest_house.json", "label":"Exit Rainforest House"},
	"mossvale_medical_ward.json|$.door": {"map":"mossvale_medical_ward.json", "target_path":"$.entry", "label":"Enter Mossvale Medical Ward"},
	"mossvale_medical_ward.json|$.exit_door": {"map":"mossvale_city.json", "target_path":"$.exterior_return", "target_source":"mossvale_medical_ward.json", "label":"Exit Mossvale Medical Ward"},
	"mossvale_orchid_house.json|$.door": {"map":"mossvale_orchid_house.json", "target_path":"$.entry", "label":"Enter Orchid House"},
	"mossvale_orchid_house.json|$.exit_door": {"map":"mossvale_city.json", "target_path":"$.exterior_return", "target_source":"mossvale_orchid_house.json", "label":"Exit Orchid House"},
	"mossvale_family_house.json|$.door": {"map":"mossvale_family_house.json", "target_path":"$.entry", "label":"Enter Family House"},
	"mossvale_family_house.json|$.exit_door": {"map":"mossvale_city.json", "target_path":"$.exterior_return", "target_source":"mossvale_family_house.json", "label":"Exit Family House"}
}

static func destination_for(filename: String, json_path: String, map_directory := "") -> Dictionary:
	if not map_directory.is_empty():
		var doc := MapDocument.load_file(map_directory.path_join(filename))
		if doc.parse_error.is_empty():
			var warp := json_path.trim_prefix("$.")
			for value: Variant in doc.data.get("outdoor_connections", []):
				if value is Dictionary and String(value.get("warp", "")) == warp:
					return {"map":String(value.get("destination_map", "")), "target_path":"$.arrival_points.%s" % String(value.get("arrival", "")), "legacy_target_path":"$.%s" % String(value.get("arrival", "")), "label":"Follow %s" % String(value.get("id", warp)), "connection":value}
	return Dictionary(WARP_ENDPOINTS.get(filename + "|" + json_path, {}))

static func scan(map_directory: String) -> Dictionary:
	var result := {"maps": {}, "connections": [], "issues": []}
	var index_path := map_directory.path_join("map_index.json")
	var index_doc := MapDocument.load_file(index_path)
	if not index_doc.parse_error.is_empty(): result.issues.append({"severity":"error", "path":index_path, "message":index_doc.parse_error}); return result
	var files := [String(index_doc.data.get("root", ""))]
	for value in Dictionary(index_doc.data.get("sections", {})).values(): files.append(String(value))
	for children in Dictionary(index_doc.data.get("nested_sections", {})).values():
		for value in Dictionary(children).values(): files.append(String(value))
	for filename in files:
		var full := map_directory.path_join(filename)
		if not FileAccess.file_exists(full): result.issues.append({"severity":"error", "path":filename, "message":"Referenced map is missing."})
		else:
			result.maps[filename] = MapDocument.load_file(full)
			var seen_markers := {}
			for field in result.maps[filename].data:
				if MapSchema.is_marker_field(String(field)) and result.maps[filename].data[field] is Array and result.maps[filename].data[field].size() >= 3:
					var p: Array = result.maps[filename].data[field]
					var key := "%s,%s,%s" % [p[0],p[1],p[2]]
					if seen_markers.has(key): result.issues.append({"severity":"warning", "path":"%s.$.%s" % [filename,field], "message":"Coincident/duplicate marker position with %s." % seen_markers[key]})
					else: seen_markers[key] = field
	var links := {}
	var endpoint_owners := {}
	for filename: String in result.maps:
		var doc: MapDocument = result.maps[filename]
		for i in doc.data.get("outdoor_connections", []).size():
			var value: Variant = doc.data.outdoor_connections[i]
			var path := "%s.$.outdoor_connections[%d]" % [filename, i]
			if not value is Dictionary: result.issues.append({"severity":"error","path":path,"message":"Connection must be an object."}); continue
			var link: Dictionary = value
			var id := String(link.get("id", "")); var warp := String(link.get("warp", "")); var target := String(link.get("destination_map", "")); var arrival := String(link.get("arrival", ""))
			if id.is_empty() or warp.is_empty() or target.is_empty() or arrival.is_empty(): result.issues.append({"severity":"error","path":path,"message":"Connection is missing id, warp, destination_map, or arrival."}); continue
			if links.has(id): result.issues.append({"severity":"error","path":path,"message":"Duplicate connection id '%s'." % id})
			else: links[id] = {"owner":filename,"data":link,"path":path}
			var endpoint_key := filename + "|" + warp
			if endpoint_owners.has(endpoint_key): result.issues.append({"severity":"error","path":path,"message":"Duplicate link for warp '%s'." % warp})
			else: endpoint_owners[endpoint_key] = id
			if not doc.data.has(warp): result.issues.append({"severity":"error","path":path + ".warp","message":"Warp marker '%s' is missing." % warp})
			if not result.maps.has(target): result.issues.append({"severity":"error","path":path + ".destination_map","message":"Destination map is missing."})
			else:
				var target_data: Dictionary = result.maps[target].data
				if not Dictionary(target_data.get("arrival_points", {})).has(arrival) and not target_data.has(arrival): result.issues.append({"severity":"error","path":path + ".arrival","message":"Destination arrival point is missing."})
	if links.is_empty():
		for spec in CONNECTIONS: result.connections.append({"from":spec[0],"to":spec[1],"from_warp":spec[2],"to_entry":spec[3],"return_warp":spec[4],"return_entry":spec[5],"facing":"fixed by runtime","transition":"unsupported"})
		return result
	var paired := {}
	for id: String in links:
		var item: Dictionary = links[id]; var link: Dictionary = item.data; var reverse := String(link.get("reverse", ""))
		if reverse.is_empty() or not links.has(reverse): result.issues.append({"severity":"error","path":item.path + ".reverse","message":"Connection is one-way; reverse link is missing."}); continue
		var back: Dictionary = links[reverse]
		if String(back.data.get("reverse", "")) != id or String(back.data.get("destination_map", "")) != String(item.owner): result.issues.append({"severity":"error","path":item.path + ".reverse","message":"Reverse link does not point back to this map/connection."}); continue
		var pair_key := id + "|" + reverse if id < reverse else reverse + "|" + id
		if paired.has(pair_key): continue
		paired[pair_key] = true
		result.connections.append({"from":item.owner,"to":back.owner,"from_warp":link.warp,"to_entry":link.arrival,"return_warp":back.data.warp,"return_entry":back.data.arrival,"facing":link.get("facing","generic"),"transition":link.get("transition","instant")})
	return result
