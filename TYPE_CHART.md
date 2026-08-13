# Project Paradise Type Chart

The attacking type is listed on the left. Unlisted matchups deal neutral (`1x`) damage.

Fakemon may have one or two types. Dual-type defensive multipliers are multiplied together: two weaknesses receive `4x`, two resistances receive `0.25x`, and a weakness plus a resistance receives neutral `1x` damage. Data may continue using `"type": "Water"` for a single type; future dual-type Fakemon use `"types": ["Water", "Air"]`.

| Attacking type | Super effective (`2x`) | Resisted (`0.5x`) |
| --- | --- | --- |
| Fire | Plant, Air, Bug | Fire, Water |
| Water | Fire | Water, Plant, Light |
| Plant | Water, Light, Air | Plant, Fire, Bug |
| Normal | Bug | Ghost, Psychic |
| Light | Dark, Water, Ghost, Psychic | Plant, Bug |
| Dark | Ghost, Psychic | Light, Bug |
| Air | Fire, Bug, Fighting | Plant |
| Bug | Plant, Light, Dark | Fire, Normal, Air |
| Mystic | None yet | None yet |
| Ghost | Psychic | Normal, Light, Dark |
| Psychic | Normal, Fighting, Poison | Light, Dark, Ghost |
| Fighting | Normal, Bug | Ghost, Air, Psychic |
| Poison | Normal, Water, Plant | Psychic |

## Defensive summary for the new types

| Defending type | Weak to (`2x` received) | Resists (`0.5x` received) |
| --- | --- | --- |
| Air | Fire, Plant | Bug |
| Bug | Fire, Normal, Air | Plant, Light, Dark |
| Mystic | None yet | None yet |
| Ghost | Light, Dark | Normal |
| Psychic | Light, Dark, Ghost | Normal, Poison |
| Fighting | Air, Psychic | None yet |
| Poison | Psychic | None yet |

Last updated: 2026-08-13
