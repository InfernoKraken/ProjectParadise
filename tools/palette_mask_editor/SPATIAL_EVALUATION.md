# Spatial transfer checkpoint: validation

Two independent operations are now available: authoritative aligned reference copy and experimental spatial prediction. The original RGB classifier remains unchanged in its classification math and is exposed as **RGB baseline**. Both generation modes now preserve manual confirmations; aligned copying is an explicit undoable replacement.

## Aligned copy

Zero RGB differences and exact PNG save/load round trips passed for all four existing protagonist source/mask pairs: cardinal PlayerSprite, diagonal walking, swimming, and diving. No source or reference image is modified. Cardinal copying also passes undo/redo and export validation.

The completed swimming mask labels at least one transparent source pixel nonwhite at `(797,360)`. Copying preserves that label exactly. Independent export background validation reports the conflict instead of normalizing or silently altering the copy. The test uses direct PNG serialization to verify the copy's exact RGB round trip even in this case; it does not bypass the editor's export validation.

## Withheld-frame protocol

Ground truth is `assets/trainers/PlayerSprite_Mask_Aligned.png`. Seven unique idle crops (male front/back/side and female front/back/left/right) provide paired source colors, pixel coordinates, and labels. Fourteen unique walking frames are wholly withheld from both RGB training and spatial propagation references, using the same-direction idle crop for each target. Mirrored duplicate frames are omitted. Every training/target rectangle and per-frame spatial scores are recorded in `spatial_evaluation.json`. The runner checks target rectangles against **all** training rectangles for overlap.

The predictor receives only training source crop, training mask crop, target source crop, tolerance, and optional landmark pairs. It never receives target mask data. Scoring occurs afterward against a separate ground-truth crop. A model-path regression additionally fills all reference pixels outside the selected training frame with white, then black, and verifies identical whole-mask predictions and uncertainty. Thus target labels cannot affect inference even though the UI's reference file may contain them.

Both methods use RGB tolerance 18. Spatial search radius is 6 training pixels, dominance threshold 90%, with four-connected exact-source-color refinement. No manual landmarks or manual corrections are supplied in the benchmark. A separate synthetic translated-point test verifies that a manual landmark moves the spatial search to its corresponding labeled source location. Landmarks are an optional manual artwork alignment aid; their performance is not measured by this benchmark.

## Per-class results

Precision measures correct confident predictions divided by all confident predictions of that class. Recall measures correct confident predictions divided by all true pixels of that class; uncertain pixels count as abstentions/missed recall. Uncertainty percentages use each true class's pixel count. These are not suggested-label accuracy metrics, and uncertainty is not silently counted as correct.

| Class | RGB precision | RGB recall | RGB uncertain | Spatial precision | Spatial recall | Spatial uncertain |
|---|---:|---:|---:|---:|---:|---:|
| Hair | 83.33% | 0.04% | 96.02% | 97.47% | 87.34% | 9.05% |
| Skin | 98.13% | 61.24% | 36.04% | 92.88% | 59.42% | 33.72% |
| Other visible | 95.97% | 67.11% | 31.48% | 92.82% | 74.13% | 22.76% |
| Background | 98.87% | 100.00% rounded | 0.003% | 99.24% | 83.41% | 15.70% |

There are 310,489 foreground pixels and 273,848 background pixels across held-out frames. Spatial uncertain foreground is **64,238 / 310,489 = 20.69%**, versus RGB **166,837 / 310,489 = 53.73%**. Whole-frame uncertainty is 107,225 spatial versus 166,845 RGB.

## Correction effort proxy

Count each uncertain pixel as requiring review, then add confidently wrong pixels that require correction. This counts unique pixels, not clicks, brush strokes, or elapsed time; region fill may handle many pixels at once. It also assumes ground truth is available to discover confident errors, so real review effort can be greater.

| Scope | RGB review or correction | Spatial review or correction |
|---|---:|---:|
| Hair | 102,132 | 12,937 |
| Skin | 26,778 | 28,039 |
| Other visible | 45,788 | 36,012 |
| Background | 8 | 45,438 |
| Foreground total | 174,698 (56.27%) | 76,988 (24.80%) |
| Entire held-out frames | 174,706 | 122,426 |

The whole-frame proxy falls by **29.92%** and the foreground proxy by **55.93%**, predominantly from hair. However, confidently wrong pixels **increase from 7,861 to 15,201**, and tentative suggested-label errors increase from 54,015 to 75,834. Spatial transfer trades excellent global opaque-background handling and some skin accuracy for much better hair coverage. A reduction in uncertainty alone is not proof of higher total classification accuracy or time saved. Inspect confident labels too.

## Limits and checks

These are exploratory development results on the cardinal protagonist sheet, not an untouched external benchmark. The first spatial run marked entire conflicted color components uncertain; after observing its excessive background abstention, refinement was changed to block propagation while retaining independent local classifications. The table reports the rerun. A fresh sheet and timed manual-versus-assisted editing are required before claiming real productivity improvement. The other three masks were tested for exact copying, not held-out spatial generalization. No experiment has been integrated into runtime player rendering, movement, animation, or recoloring.

Godot checks pass for zero-difference copying, exact-color PNG round trips, landmarks, disjoint-frame and landmark validation, target-label isolation, preservation of manual confirmed pixels, spatial undo/redo, the original RGB/export regressions, and the editor scene smoke run. Undo includes confirmation state. Remaining known export limitation: source alpha and reference coverage can disagree, as in the swimming asset above.

See `README.md` for commands, field formats, and operation semantics. `evaluate_spatial.gd`, `copy_landmark_tests.gd`, and `evaluate.gd` are reproducible Godot-only runners.

