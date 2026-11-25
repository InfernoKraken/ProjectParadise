# Palette Mask Editor (experimental checkpoint)

Standalone Godot 4 project using built-in Image APIs. Source artwork and reference files are read only. Output remains exact RGB red (hair), green (skin), black (other), white (background); no runtime player integration.

```powershell
godot --rendering-driver opengl3 --path tools/palette_mask_editor
```

## New image with no reference?

Read the [practical user guide](USER_GUIDE.md) first. The current tool is assisted labeling, not automatic hair/skin recognition from an unlabeled image.

1. **Load source**, then turn **Review overlay** on.
2. Select **Label source sample** in the tool dropdown (not Brush).
3. Choose Hair and click representative hair shades; repeat for Skin, Other, and opaque Background.
4. Click **RGB baseline** to generate suggestions, then correct them with Brush or Connected region fill.
5. Resolve uncertainty, inspect the predictions, and **Export PNG** to a new file.

No reference is required for that workflow. **Add reference labels**, **Aligned Reference Copy**, **Generate spatial target**, and **Hybrid experiment** do require a loaded mask. Painting one frame does not yet make it an in-memory spatial reference. The guide explains this limitation, shared-color ambiguity, and why a fill may select only an outline.

## Independent operations

**Aligned Reference Copy**: load source and its pixel-aligned mask, then click this button and confirm replacement. Copies every reference RGB label directly, clears uncertainty, and confirms every pixel. No classifier or RGB voting is involved. Use only for corresponding aligned artwork; matching dimensions alone cannot prove semantic alignment. The operation replaces current corrections and is undoable. PNG export still runs independent background validation. Exact copies and PNG round trips are tested across all four protagonist masks. The existing swimming mask has at least one transparent-source pixel labeled nonwhite, so copying is exact but export correctly reports that coverage conflict rather than silently changing the copied label.

**RGB baseline**: kept for comparison. Use the reference sample rectangle and **Add reference labels**, or click individual source pixels with **Label source sample**. Samples are counts per RGB/class, default tolerance 18 in Euclidean byte RGB. Labels within 3 RGB units of the closest color contribute frequency-weighted votes. Dominance below 90%, or no color in tolerance, is uncertain. Loading a reference alone does not add RGB samples. Sample configuration is not undoable.

**Generate spatial target**: load source and an aligned reference containing the completed training frame. Enter the labeled source frame rectangle in the reference rectangle fields and an unlabeled target frame rectangle in the spatial row. Rectangles are sheet pixel `(x,y,width,height)` coordinates. They must be nonempty, inside the sheet, and disjoint. You do not need to click **Add reference labels** for spatial generation. Only the selected training crop's label coordinates enter prediction; the full mask and target labels are not passed to the predictor. Output changes only the target rectangle, preserving manually confirmed pixels.

The spatial predictor normalizes frame-relative pixel centers, searches a 13×13 neighborhood in the training frame, and weights class evidence by spatial proximity and RGB distance within tolerance. Dominance below 90%, or absence of matching local evidence, remains reviewable. A four-connected exact-source-color component can propagate a label when at least two confident pixels agree and no confident class conflicts. Conflicts block propagation and retain independent local decisions. Components never merge disconnected regions. Transparent target pixels become white; partial alpha is visible. No antialiasing or image resizing is applied.

Optional landmarks use paired **frame-local integer pixel coordinates**:

```text
sourceX,sourceY,targetX,targetY; sourceX,sourceY,targetX,targetY
```

For example, corresponding head centers can initialize translation after frame-size normalization. Several landmarks blend normalized displacement by inverse squared distance. They are entered manually from artwork, not inferred from target masks; this is a simple experimental warp rather than skeletal or pose estimation. Points must lie inside their respective frames. Empty input uses normalized rectangles only.

## Hybrid experiment (opt in)

Use the same labeled source rectangle, target rectangle, and optional landmarks as spatial transfer, then click **Hybrid experiment**. Existing RGB baseline, spatial transfer, and aligned copy remain separate. **Strict hybrid agreement** is off for fallback fusion and on for the conservative agreement variant; it affects only the hybrid button.

Source-only segmentation first uses alpha-zero where transparency exists. On fully opaque frames it floods the dominant exact border color when at least 60% of the border agrees. Enclosed color matches remain candidates, not automatically white. Spatial hair evidence is prioritized; confident RGB/spatial disagreements and foreground/background conflicts become uncertain. Fallback can accept a single confident skin/other prediction; strict mode requires agreement except for confident spatial hair. Both preserve manual confirmations and are undoable. See [HYBRID_EVALUATION.md](HYBRID_EVALUATION.md) for all per-class counts, enclosed-background limitations, and correction-effort comparisons. No runtime integration or replacement of the earlier modes is made.

Reproduce the investigation with:

```powershell
godot --headless --rendering-driver opengl3 --text-driver Dummy --accessibility-driver dummy --path tools/palette_mask_editor --script res://evaluate_background.gd --log-file background_evaluation.log
godot --headless --rendering-driver opengl3 --text-driver Dummy --accessibility-driver dummy --path tools/palette_mask_editor --script res://evaluate_hybrid.gd --log-file hybrid_evaluation.log
godot --headless --rendering-driver opengl3 --text-driver Dummy --accessibility-driver dummy --path tools/palette_mask_editor --script res://hybrid_tests.gd --log-file hybrid_tests.log
```

## Editing and export

Wheel zoom and middle-drag pan are synchronized. Either pane accepts painting. Magenta is a separate uncertainty overlay, never exported. Brush and connected fill confirm decisions; both generation modes preserve those confirmations. Erase clears confirmation and restores uncertainty. Explicit manual painting/fill can replace an earlier confirmation. Undo/redo stores labels, uncertainty, and confirmation state, up to 30 full-image checkpoints. Loading another source resets all work. Work remains in memory; there is no session save.

Export checks dimensions, exact colors, alpha-zero background coverage, and uncertainty. Resolve uncertain pixels before export; confident predictions can still be wrong and should be inspected. Opaque backgrounds require labeled/spatial evidence and visual review. A new RGB PNG is created; existing paths, source, and reference are protected. Aligned copy is an explicit whole-mask replacement, while generation replaces only unconfirmed predictions.

## Validation

```powershell
godot --headless --rendering-driver opengl3 --text-driver Dummy --accessibility-driver dummy --path tools/palette_mask_editor --script res://evaluate_spatial.gd --log-file spatial_evaluation.log
godot --headless --rendering-driver opengl3 --text-driver Dummy --accessibility-driver dummy --path tools/palette_mask_editor --script res://copy_landmark_tests.gd --log-file copy_landmark_tests.log
godot --headless --rendering-driver opengl3 --text-driver Dummy --accessibility-driver dummy --path tools/palette_mask_editor --script res://evaluate.gd --log-file evaluation.log
godot --headless --rendering-driver opengl3 --text-driver Dummy --accessibility-driver dummy --path tools/palette_mask_editor --quit-after 5 --log-file spatial_smoke.log
```

The dummy text driver avoids a local startup failure. On Windows wait for Godot completion and inspect logs for `CHECK FAILURES: 0`; launcher exit status alone is insufficient. [SPATIAL_EVALUATION.md](SPATIAL_EVALUATION.md) and [spatial_evaluation.json](spatial_evaluation.json) describe the current controlled comparison. [EVALUATION.md](EVALUATION.md) records the earlier RGB-only experiment using a different training selection.


