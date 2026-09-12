# Fakemon Anchor Editor v1

Run from the repository root with:

```text
godot --path . tools/fakemon_anchor_editor/anchor_editor.tscn
```

The source sprite and its same-dimension `.anchors.png` companion in
`assets/fakemon/battle/` are authoring inputs. The anchor PNG is the source of
truth; `data/generated_battle_anchors.json` is generated output and should not
be hand-edited or reconstructed at battle runtime.
`battle/generated_anchor_repository.gd` reads that generated file and resolves
missing optional anchors to `origin`, with sprite center only as a malformed-data
last resort. Existing battles do not depend on anchor data yet.

Naming is `<ArtId>_Player.png` / `<ArtId>_Player.anchors.png` and independently
`<ArtId>_Wild.png` / `<ArtId>_Wild.anchors.png`. `head` and `origin` are required.
Mouth, neck, wings, tail, and any number of `custom_N` anchors are optional and
may fall back to `origin` in a future runtime resolver.

Save validates the v1 signature, dimensions, marker colors and uniqueness,
then applies the shared `BattleSpriteGeometry` rules with nearest-neighbor
marker sampling and writes centroid coordinates. Changing the processing cap
and saving again regenerates coordinates from authoring pixels.

To add a fixed semantic anchor, add its name and stable color only in
`core/anchor_encoding.gd`, then add it to `OPTIONAL` or `REQUIRED`. Do not change
existing colors within encoding version 1. Custom IDs use a reversible 22-bit
encoding rather than a small fixed palette.

## Battle Scene Anchors

The second tab edits the scene definitions in `data/battle_scenes.json`. The
included `rainforest_default` scene previews
`assets/battle/battle_background.png`. `BACKGROUND_CENTER`, `FIELD_CENTER`,
`ALLY_FIELD`, and `ENEMY_FIELD` are authored points. `RANDOM_SCREEN` and
`RANDOM_GROUND` are authored rectangles: drag inside to move one or drag its
lower-right square handle to resize it.

`SCREEN_TOP`, `SCREEN_BOTTOM`, `SCREEN_LEFT`, `SCREEN_RIGHT`, and
`SCREEN_CENTER` are deliberately read-only and resolution-derived. The weather
renderer uses `BattleSceneAnchorRepository`, so saved scene points and spawn
regions are runtime data rather than editor-only decorations.
