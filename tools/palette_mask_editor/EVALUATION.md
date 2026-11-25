# Initial protagonist evaluation

Source: `assets/trainers/PlayerSprite.png`; ground truth: `PlayerSprite_Mask_Aligned.png`, 1386 × 1169. Both are preserved.

Only four idle rectangles supply labels: male front (582,72,161,307), male back (987,81,154,294), female side (33,82,160,332), female front (777,86,189,294). This supplies 41 source RGB colors. All 14 unique walking frames are withheld from label/color sampling; mirrored duplicates are omitted. Their rectangles are recorded in `evaluation.json` and the runner verifies no training overlap. No runtime movement/animation scripts are loaded.

| Ground-truth class | Pixels | Suggested-label accuracy | Uncertain | Confident errors |
|---|---:|---:|---:|---:|
| Hair | 102,172 | 84.60% | 96,148 | 6,024 |
| Skin | 69,093 | 79.54% | 22,114 | 1,910 |
| Other visible | 139,224 | 82.31% | 37,681 | 1,982 |
| Background | 273,848 | 100.00% rounded | 8 | 0 |

Suggested-label accuracy includes tentative labels underneath uncertainty. It is not export-ready accuracy. If uncertainty counts as incorrect/abstained, correct confident coverage is **0% hair, 65.23% skin, 71.51% other**. Among confident decisions within each true class, accuracy is 0%, 95.93%, and 98.05% respectively. The hair figure reflects 6,024 confidently wrong hair pixels and zero confidently correct hair pixels; it must not be hidden by aggregate/background accuracy.

There are **155,951 uncertain pixels** across held-out rectangles (155,943 visible and 8 background). Exact locations are in `evaluation.json`, grouped by frame as inclusive `[sheet_y, sheet_x_start, sheet_x_end]` runs. Frame rectangles and per-frame counts are included. The editor independently highlights all uncertain sheet pixels in magenta, including outside evaluated rectangles.

The generator's first strict any-conflict rule abstained on every test pixel because even dominant training colors had minority labels. The final rule uses frequencies from the training rectangles and a fixed 90% dominance threshold. These results are exploratory development results, not a fresh blind benchmark after algorithm selection. Test pixels never enter the sample inventory, but a new sheet should be used for independent confirmation.

Conclusion: this checkpoint is useful for selective skin/clothing assistance, but **does not establish a meaningful reduction in total correction time**. About half of visible held-out pixels remain uncertain, plus 9,916 confident visible errors need correction. Automatic suggestions alone are insufficient for hair; visual review remains necessary even after resolving every highlighted pixel. Correction time has not been measured. Do not use this experiment to justify the outfit/animation overhaul yet. A next small checkpoint could evaluate spatially constrained labels or frame-local seeds on a new held-out set, followed by a timed manual-versus-assisted comparison.

Validation includes Godot scene smoke execution plus synthetic checks for shared-color ambiguity, transparent background, connected fill boundaries/connectivity, undo/redo of uncertainty, unresolved export rejection, exact-color PNG round trip, dimensions, and overwrite protection. The evaluation script reports check failures explicitly.
