# Shared map layouts

Checkpoint: one authored map JSON supplies the geometry for multiple independently
identified interiors. Existing maps and warps keep their behavior.

In the map editor's MAP header, enable **Shared Layout**. Edit the instance JSON
array and click **Apply Instances**, then save the map normally. Layout editing
still edits the common map. Instance editing currently uses JSON rather than
canvas selection. Disabling sharing retains the array but stops loading instances.

For `jalovea_city_house_standard.json`, an example array is:

```json
[
  {
    "id": "west_house",
    "npcs": [{"id": 1, "position": [2, 0, 1], "facing": "down"}],
    "script_source": "Block Greeting\n  End",
    "script_interactions": {"npc:1": "Greeting"},
    "warp_destinations": {
      "return_warp": {
        "entrance_map": "jalovea_city.json",
        "entrance_map_warp_id": 2
      }
    }
  },
  {
    "id": "east_house",
    "npcs": [],
    "script_source": "",
    "script_interactions": {},
    "warp_destinations": {
      "return_warp": {
        "entrance_map": "jalovea_city.json",
        "entrance_map_warp_id": 3
      }
    }
  }
]
```

The root JSON stores `"shared_layout": true` and `"layout_instances": [...]`.
IDs must be nonempty, unique within the template, and contain no `#`.
NPC definitions remain in the template's existing `_NPC_Data.json` companion;
the instance array supplies placements using those definition IDs.

An omitted field inherits the template. Supplied arrays/tables replace that field
completely; use empty arrays/objects to remove inherited behavior. Supported
overrides are `npcs`, `script_source`, `script_interactions`, `script_sprite_names`,
`script_paths`, `map_script_header`, and `map_script_headers`. Return-warp
destinations override only routing, retaining the shared warp position and ID.
Geometry overrides are ignored.

On each city entrance warp, select the template as **Entrance Map**, enter
`west_house` or `east_house` as **Entrance Instance ID (shared layout)**, press
Enter, and choose its destination warp ID. A blank instance ID uses the base map.
Each instance should supply return destinations pointing to its own city door.

Runtime identities use `template.json#instance` and the indexed map ID plus
`#instance`, keeping scripts, NPC movement, and saved locations independent.
Geometry is stored once on disk; the existing runtime builds separate copies in
isolated world-space slots. This checkpoint does not implement streamed interiors.
The example warp IDs and NPC IDs must match the actual authored city and companion.

## Instance UI helper

With Shared Layout enabled, choose an instance from the SHARED INSTANCES list.
Use + Add Instance to create another named house with an explicitly empty NPC
list. Tick the NPCs that belong in the selected instance. The checklist includes
NPCs from the base layout, other instances, and the shared NPC companion file.
Existing placements are reused; a definition with no placement starts at [0,0,0].

For each exit, choose the destination map and named warp from dropdowns. For
example, house_1 can return to jalovea_city / warp_4, while house_2 returns to
warp_5. Show entrance rug controls the shared return_warp visual for every
instance. Changes support Undo/Redo and are persisted by the normal Save button.

On the city entrance warp, choose the house template and select house_1 or
house_2 in the Entrance Instance dropdown. Base map is an explicit separate
choice. Save the city as well as the interior; setting an interior exit does not
automatically modify the city's entrance. Custom instance ID remains available
for advanced cases.

Advanced JSON is collapsed by default. It preserves script overrides and allows
custom NPC coordinates. The canvas continues to show the base map, not a preview
of the selected instance. The helper updates the existing layout_instances JSON
array and does not introduce another data format.
