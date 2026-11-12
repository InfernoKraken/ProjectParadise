extends RefCounted

const Template := preload("res://world/habitat_template.gd")
const Movement := preload("res://world/npc_movement.gd")
const Terrain := preload("res://world/terrain_transition_resolver.gd")

# Floor outline at the inner edge of the massive pen, with a small overlap
# under the rim so the museum floor cannot show through at the joins.
const FLOOR_OUTLINE := [
	Vector2(-1.9, -1.64), Vector2(1.9, -1.64),
	Vector2(2.28, -1.14), Vector2(2.28, 0.95),
	Vector2(1.9, 1.48), Vector2(-1.9, 1.48),
	Vector2(-2.28, 0.95), Vector2(-2.28, -1.14),
]

# Water can tint the lower rear wall. Keep it inside the inner side rails,
# where the foreground art cannot hide the translucent overlay.
const WATER_TINT_OUTLINE := [
	Vector2(-1.78, -1.91), Vector2(1.78, -1.91),
	Vector2(2.02, -1.54), Vector2(2.02, 0.95),
	Vector2(1.83, 1.48), Vector2(-1.83, 1.48),
	Vector2(-2.02, 0.95), Vector2(-2.02, -1.54),
]

static func water_tint_polygons(cell: Vector2i, region: Rect2, grid: Dictionary, floor_clip: PackedVector2Array) -> Array[PackedVector2Array]:
	var batcher := preload("res://world/terrain_mesh_batcher.gd")
	if floor_clip.is_empty():
		return batcher.clip_rect(region, floor_clip)
	# The standard pool's north row ends at -1.5. Extend only its
	# exposed edge, keeping the underlying water grid and collision intact.
	if cell.y == -1 and is_equal_approx(region.position.y, -1.5) and grid.get(cell + Vector2i.UP) != "water":
		var north := WATER_TINT_OUTLINE[0].y
		region.size.y += region.position.y - north
		region.position.y = north
	return batcher.clip_rect(region, PackedVector2Array(WATER_TINT_OUTLINE))

var game: Node
var slots: Dictionary = {}
var assignments: Dictionary = {}
var discovered: Dictionary = {}
var instances: Dictionary = {}
var templates: Dictionary = {}

func _init(world_game: Node) -> void:
	game = world_game

func record(mon: Dictionary) -> void:
	var species := String(mon.get("name", ""))
	if not species.is_empty():
		discovered[species] = true

func record_owned() -> void:
	for roster: Array in [game.party, game.cloud]:
		for mon: Dictionary in roster:
			record(mon)

func restore(saved_species: Variant, saved_slots: Variant) -> void:
	discovered.clear()
	if saved_species is Array:
		for species in saved_species:
			if species is String and not species.is_empty():
				discovered[species] = true
	record_owned()
	for slot in instances.keys():
		remove(slot)
	assignments.clear()
	for slot in slots:
		_update_lectern(slot)
	if saved_slots is Dictionary:
		for slot in saved_slots:
			var species: Variant = saved_slots[slot]
			if slots.has(slot) and species is String and not assignments.values().has(species) and discovered.has(species):
				var prepared := prepare(slot, species)
				if not prepared.has("error"):
					install(slot, species, prepared)
	game._set_active_visual_region(game._current_location())

func register(entry: Dictionary, authored: Dictionary, layer: int) -> void:
	var slot: Dictionary = entry.get("habitat_exhibit", {})
	var id := String(slot.get("id", ""))
	if not Template.valid_id(id) or slots.has(id):
		return
	var offset: Variant = slot.get("origin")
	var region: Variant = slot.get("bounds")
	if not Template._numbers(offset, 3) or not Template._numbers(region, 4):
		return
	var bounds := Rect2(region[0], region[1], region[2], region[3])
	if not bounds.has_area() or not Template.footprint().encloses(bounds):
		return
	var origin: Vector3 = game._array_to_vector3(authored.origin) + game._array_to_vector3(offset)
	slots[id] = {"origin": origin, "bounds": bounds, "layer": layer, "lectern": entry}
	entry["exhibit_slot"] = id
	entry["sort_offset_y"] = float(entry.get("sort_offset_y", 0.0)) + 0.12

func available(slot: String) -> Array:
	record_owned()
	var result := discovered.keys().filter(func(species):
		return (assignments.get(slot) == species or not assignments.values().has(species)) and not game._find_species(species).is_empty())
	result.sort()
	return result

func _load_templates() -> void:
	templates.clear()
	var directory := "res://" + Template.DIRECTORY
	if not DirAccess.dir_exists_absolute(directory):
		return
	for filename in DirAccess.get_files_at(directory):
		if filename.get_extension() != "json":
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(filename)))
		if not data is Dictionary or not Template.problem(data, "res://").is_empty():
			continue
		if data.get("objects", []).any(func(object):
			return object.has("asset_path") and not ResourceLoader.exists(object.asset_path, "Texture2D")):
			continue
		var type: String = data.habitat_type
		# Ambiguous templates are treated as incomplete.
		templates[type] = {} if templates.has(type) else data

func prepare(slot: String, species: String) -> Dictionary:
	if not slots.has(slot):
		return {"error": "This exhibit has no valid placement region."}
	if species.is_empty():
		return {}
	if not available(slot).has(species):
		return {"error": "This species is unavailable for this exhibit."}
	var definition: Dictionary = game._find_species(species)
	if game.npc_visual_resolver == null:
		game.npc_visual_resolver = game.NpcVisualResolver.new(ProjectSettings.globalize_path("res://"))
	if not game.npc_visual_resolver.available("fakemon", species):
		return {"error": "Overworld art is unavailable for " + species + "."}
	_load_templates()
	var layout: Dictionary = templates.get(definition.get("habitat", ""), {})
	if layout.is_empty() and instances.get(slot, {}).get("has_layout", false):
		return {"error": "This species has no habitat template. The current exhibit is still on display."}
	var limits: Rect2 = slots[slot].bounds
	var spawn := limits.get_center()
	if not layout.is_empty():
		var wander: Array = layout.wander_bounds
		limits = limits.intersection(Rect2(wander[0], wander[1], wander[2], wander[3]))
		spawn = Vector2(layout.npc_spawn[0], layout.npc_spawn[1])
	var safe_bounds := limits.grow_individual(-0.28, -0.23, -0.28, -0.23)
	if not safe_bounds.has_area():
		return {"error": "There is no room for this species to wander."}
	spawn = spawn.clamp(safe_bounds.position, safe_bounds.end)
	var prefix := "Habitat_" + slot
	var prepared := layout.duplicate(false)
	if prepared.has("objects"):
		prepared["objects"] = prepared.objects.filter(func(object):
			return object.get("asset_path") != "res://" + Template.PEN_TEXTURE)
	var grid := Terrain.terrain_grid(prepared)
	if not layout.is_empty():
		var base: String = layout.get("base_terrain_type", "forest_floor")
		var footprint := Template.footprint()
		for x in range(ceili(footprint.position.x + 0.5), floori(footprint.end.x - 0.5) + 1):
			for z in range(ceili(footprint.position.y + 0.5), floori(footprint.end.y - 0.5) + 1):
				var cell := Vector2i(x, z)
				if not grid.has(cell):
					grid[cell] = base
	prepared["_habitat_floor_clip"] = PackedVector2Array(FLOOR_OUTLINE)
	prepared["_terrain_grid"] = grid
	prepared["_terrain_transitions"] = Terrain.resolve(grid, prefix)
	var mode := "ground"
	var authored_mode: Variant = definition.get("movement_mode", "ground")
	if Movement.MODE_OFFSETS.has(authored_mode):
		mode = String(authored_mode)
	prepared["npc"] = {"id": 1, "type": "fakemon", "sprite": species, "facing": "down",
		"position": [spawn.x, 0.42, spawn.y], "movement_mode": mode,
		"movement": {"preset": "random", "range": [limits.size.x, limits.size.y]}}
	prepared["bounds"] = limits
	prepared["slot_id"] = slot
	return prepared

func install(slot: String, species: String, prepared: Dictionary) -> bool:
	if prepared.has("error") or not slots.has(slot):
		return false
	if species.is_empty():
		remove(slot)
		assignments.erase(slot)
		_update_lectern(slot)
		game._set_active_visual_region(game._current_location())
		return true
	if not available(slot).has(species) or prepared.get("slot_id") != slot or not prepared.has("npc") or prepared.npc.sprite != species:
		return false
	var config: Dictionary = slots[slot]
	var origin: Vector3 = config.origin
	var prefix := "Habitat_" + slot
	var start_nodes: int = game.world.get_child_count()
	var collections: Array = [game.tree_sort_entries, game.object_sort_entries, game.overlay_sort_entries,
		game.background_object_sort_entries, game.npc_sort_entries, game.bridge_sort_entries,
		game.attached_overlay_entries, game.traversal_surfaces]
	var starts := collections.map(func(entries): return entries.size())
	var runtime_key := prefix
	var old: Dictionary = instances.get(slot, {})
	# Stage with a distinct NPC key so a failed spawn leaves the old slot intact.
	runtime_key += "_next" if old.get("key", "") == prefix else ""
	prepared["_npc_map_file"] = runtime_key
	prepared["_resolved_npcs"] = [prepared.npc]
	game._build_habitat_layout(prepared, origin, runtime_key)
	var npc: Area3D = game.runtime_npcs.get(runtime_key, {}).get(1)
	var nodes: Array = game.world.get_children().slice(start_nodes)
	var records: Array = []
	for index in collections.size():
		var collection: Array = collections[index]
		var entries := collection.slice(starts[index])
		for entry: Dictionary in entries:
			entry["visual_layer"] = config.layer
		records.append([collection, entries])
	var generated := {"nodes": nodes, "records": records, "npc": npc, "key": runtime_key,
		"has_layout": prepared.has("habitat_type")}
	if npc == null:
		_dispose(generated)
		return false
	var bounds: Rect2 = prepared.bounds
	bounds.position += Vector2(origin.x, origin.z)
	npc.set_meta("habitat_occupant", true)
	npc.set_meta("wander_bounds", bounds)
	npc.set_meta("border_playable_bounds", bounds)
	if npc.get_meta("movement_mode") == "flying":
		# This rectangle fits inside the beveled floor at both ends.
		var frame := Rect2(FLOOR_OUTLINE[0], FLOOR_OUTLINE[4] - FLOOR_OUTLINE[0])
		frame.position += Vector2(origin.x, origin.z)
		npc.set_meta("habitat_flight_frame", frame)
	for node: Node in nodes:
		game._assign_visual_region(node, config.layer)
	if game.npc_water_surfaces.has(runtime_key):
		game.npc_water_surfaces[runtime_key]["visual_layer"] = config.layer
	remove(slot)
	instances[slot] = generated
	assignments[slot] = species
	_update_lectern(slot)
	game._attach_sorted_world_entries()
	game.collision_regions_dirty = true
	game._set_active_visual_region(game._current_location())
	game._update_sort_canvas()
	return true

func _update_lectern(slot: String) -> void:
	var entry: Dictionary = slots[slot].lectern
	if not entry.has("sort_root") or not entry.has("active_texture"):
		return
	var art := entry.sort_root.get_node("Visual") as Sprite2D
	art.texture = entry.active_texture if assignments.has(slot) else entry.texture

func remove(slot: String) -> void:
	if not instances.has(slot):
		return
	_dispose(instances[slot])
	instances.erase(slot)

func _dispose(generated: Dictionary) -> void:
	var npc: Area3D = generated.npc
	if is_instance_valid(npc):
		game.npc_dialogues.erase(npc.get_instance_id())
		game.npc_movement_states.erase(npc.get_instance_id())
	var key: String = generated.key
	game.runtime_npcs.erase(key)
	var surface: Dictionary = game.npc_water_surfaces.get(key, {})
	if is_instance_valid(surface.get("node")):
		surface.node.hide()
		surface.node.queue_free()
	game.npc_water_surfaces.erase(key)
	for record: Array in generated.records:
		for entry: Dictionary in record[1]:
			if entry.has("fallback_entry"):
				var fallback: Dictionary = entry.fallback_entry
				fallback.sort_root.hide()
				fallback.sort_root.queue_free()
				game.overlay_sort_entries.erase(fallback)
			for field in ["sort_root", "pivot"]:
				if is_instance_valid(entry.get(field)):
					entry[field].hide()
					entry[field].queue_free()
			record[0].erase(entry)
	for node: Node in generated.nodes:
		game.world.remove_child(node)
		node.queue_free()
	OverworldTextureAnimation.visibility_signature = []
	game.static_art_view_signature = []
	game.collision_regions_dirty = true
