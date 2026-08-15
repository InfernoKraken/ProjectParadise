# Project Paradise Type Chart

The attacking type is listed on the left. Matchups not listed deal neutral (`1x`) damage. There are currently no type immunities.

Fakemon may have one or two types. Dual-type defensive multipliers are multiplied together: two weaknesses receive `4x`, two resistances receive `0.25x`, and a weakness plus a resistance receives neutral `1x` damage. Data may use `"type": "Water"` for a single type or `"types": ["Water", "Air"]` for two types.

| Attacking type | Super effective (`2x`) | Resisted (`0.5x`) |
| --- | --- | --- |
| Fire | Ancient, Plant, Air, Bug, Steel, Ice | Fire, Water, Rock |
| Water | Fire, Ancient, Rock, Steel | Water, Plant, Light, Poison, Normal |
| Plant | Water, Light, Air, Rock, Ancient | Plant, Fire, Bug, Poison |
| Light | Dark, Water, Ghost, Psychic, Ancient | Plant, Bug, Rock, Light |
| Dark | Ghost, Psychic, Mystic, Ancient, Fighting | Light, Bug, Dark |
| Normal | Bug, Mystic, Plant | Ghost, Psychic, Steel, Ancient, Rock, Fighting |
| Air | Fire, Bug, Fighting, Rock | Plant, Electric, Ice, Normal, Air |
| Bug | Plant, Light, Dark, Mystic, Psychic | Fire, Normal, Air, Steel, Dragon, Ice, Bug, Fighting |
| Mystic | Ghost, Ancient, Dragon | Normal, Dark, Mystic, Fighting, Bug |
| Ghost | Psychic, Fighting, Steel | Ancient, Light, Mystic, Ghost |
| Psychic | Normal, Fighting, Poison, Steel | Light, Dark, Ghost, Ancient, Bug |
| Fighting | Normal, Bug, Mystic, Rock, Dark | Ghost, Air, Psychic, Steel |
| Poison | Normal, Water, Plant | Psychic, Steel, Rock, Air, Ice |
| Steel | Fighting, Bug, Rock, Ice, Dragon | Fire, Water, Psychic, Electric, Steel |
| Ancient | Ghost, Electric, Normal, Psychic, Ice | Water, Plant, Light |
| Electric | Steel, Water, Air, Fighting | Ancient, Plant, Rock, Electric |
| Rock | Fire, Bug, Ice, Light, Electric | Plant, Steel, Fighting, Ancient, Rock |
| Ice | Plant, Bug, Dragon, Air | Fire, Steel, Rock, Ancient, Ice |
| Dragon | Fighting, Normal, Electric | Steel, Mystic |

## Battle move indicators

When selecting a damaging move, the battle menu shows a green `▲` for a super-effective matchup and a red `▼` for a resisted matchup. The preview accounts for dual types, active weakness suppression, resistance-ignoring moves, and Light/Dark exposure. Status moves and neutral matchups have no indicator.

Last updated: 2026-08-15
