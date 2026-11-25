# Hybrid classification investigation

This checkpoint adds source-only background segmentation and two opt-in hybrid policies. RGB baseline, spatial transfer, and aligned reference copy remain available. Their classification implementations were not replaced. RGB and spatial per-class TP, FP, uncertain, and confidently wrong counts reproduce the previous spatial benchmark exactly. No source assets or runtime rendering code were changed.

## Background stage, evaluated first

Input is only the source image. If any alpha-zero pixels exist, alpha-zero pixels are background and nonzero alpha is not guessed as background. For fully opaque images, the most frequent exact RGBA border color must cover at least 60% of border pixels. Four-connected flooding of that exact color starts at the border. Unreached pixels of the same color are enclosed candidates, not confirmed background. No RGB tolerance, dilation, or hole filling is applied. A busy border without dominance produces no opaque background guess.

Ground-truth exterior/enclosed regions are computed only for scoring by flooding white pixels in the reference from the image border. They are never prediction inputs. The stage is intentionally conservative about enclosed holes: an identical-colored interior region may be background, an outline, hair, or clothing.

| Source asset | Stage | BG precision | BG recall | False BG | Enclosed true BG | Detected enclosed BG | Enclosed candidates |
|---|---|---:|---:|---:|---:|---:|---:|
| Diving In Sprite.png | opaque_exterior_exact | 99.99% | 99.90% | 144 | 1,129 | 0 | 1,002 |
| PlayerSprite.png | opaque_exterior_exact | 99.94% | 99.92% | 612 | 356 | 2 | 333 |
| Player_Swimming Sprites.png | alpha | 99.98% | 76.15% | 212 | 8,686 | 0 | 0 |
| Walking_Anim_Diagonal.png | opaque_exterior_exact | 99.95% | 98.99% | 443 | 1,486 | 1 | 803 |

The cardinal stage finds 333 of 356 enclosed true-background pixels as candidates, not confident white. Two enclosed reference pixels are exterior-reachable in source-color topology because source and reference boundaries differ. The diagonal and diving stages also leave most enclosed white regions unconfirmed. These results rule out blindly treating an exterior flood as complete segmentation. Exact-color detection also misses antialiased/near-background colors. The swimming sheet mixes transparency and opaque authored backgrounds, so alpha-only recall is 76.15%; 212 alpha-zero pixels have nonwhite reference labels. Alpha is authoritative to the editor contract, but those disagreements count as false background against the supplied reference. This inconsistency is reported, not repaired in the source or reference.

Synthetic opaque-ring and transparent-hole tests verify that an opaque enclosed hole stays a candidate while alpha-zero identifies an enclosed transparent hole. A busy-border test verifies abstention without a dominant border color.

## Hybrid policies

- Spatial hair is preferred when spatial classification is confident and RGB has no confident contradictory label. When two confident semantic predictions differ, the pixel is uncertain; tentative disagreement with an already-uncertain predictor is not a confident conflict.
- Fallback policy: accept confident RGB/spatial agreement; otherwise allow a single confident method to supply skin/other/remaining classifications. This compares the available evidence instead of always trusting spatial skin or other.
- Strict agreement policy: keep the spatial-hair exception, but require two confident agreeing semantic predictions for other classes. A single confident skin/other result is reviewable.
- Alpha-zero always produces white. Opaque exterior-background evidence produces white unless either semantic predictor confidently says foreground; that conflict becomes uncertain. An enclosed background-color candidate becomes confidently white only when both semantic predictors confidently agree on white; otherwise it remains reviewable.
- Manually confirmed labels are never overwritten. Only the selected target rectangle changes, and labels, uncertainty, and confirmation state participate in undo/redo. Export retains the four exact RGB colors. Background segmentation is evidence, not an excuse to erase conflicting foreground labels silently.

The segmented-spatial ablation uses the same background rules with spatial evidence alone, showing how much improvement comes from background handling rather than RGB/spatial fusion.

## Same withheld-frame protocol

The seven idle training rectangles and fourteen unique walking targets are exactly those in SPATIAL_EVALUATION.md. Each target uses its same-direction idle training frame. Every target is checked for overlap against every training rectangle. No target labels, landmarks, or manual corrections enter benchmark inference. The predictor receives only the labeled training crop and target artwork. Source-only segmentation uses no target mask. Target truth is cropped separately for scoring afterward. Tests poison all nontraining reference labels white, then black, and require identical hybrid output and uncertainty. Exact frame rectangles, per-frame metrics, and conflict counts are in hybrid_evaluation.json. This is development-set evidence, not a fresh external generalization benchmark.

Precision is TP/(TP+FP) over confident predictions. Recall is TP/all true pixels of the class, so uncertainty is an abstention. Uncertainty and confidently wrong counts below are grouped by ground-truth class. The correction-effort proxy is uncertain pixels + confidently wrong pixels, counted once each. It is not mouse clicks, fill operations, or timed effort; finding confident errors can require reviewing the entire frame.

| Method | Class | Precision | Recall | Uncertain | Uncertain % | Confidently wrong | Review/correct proxy |
|---|---|---:|---:|---:|---:|---:|---:|
| rgb | Hair | 83.33% | 0.04% | 98,106 | 96.02% | 4,026 | 102,132 |
| rgb | Skin | 98.13% | 61.24% | 24,900 | 36.04% | 1,878 | 26,778 |
| rgb | Other | 95.97% | 67.11% | 43,831 | 31.48% | 1,957 | 45,788 |
| rgb | Background | 98.87% | 100.00% | 8 | 0.00% | 0 | 8 |
| spatial | Hair | 97.47% | 87.34% | 9,247 | 9.05% | 3,690 | 12,937 |
| spatial | Skin | 92.88% | 59.42% | 23,301 | 33.72% | 4,738 | 28,039 |
| spatial | Other | 92.82% | 74.13% | 31,690 | 22.76% | 4,322 | 36,012 |
| spatial | Background | 99.24% | 83.41% | 42,987 | 15.70% | 2,451 | 45,438 |
| segmented_spatial | Hair | 98.37% | 87.27% | 9,329 | 9.13% | 3,675 | 13,004 |
| segmented_spatial | Skin | 93.72% | 59.42% | 23,302 | 33.73% | 4,737 | 28,039 |
| segmented_spatial | Other | 93.87% | 74.10% | 31,739 | 22.80% | 4,321 | 36,060 |
| segmented_spatial | Background | 99.35% | 99.08% | 2,505 | 0.91% | 2 | 2,507 |
| hybrid_fallback | Hair | 98.80% | 85.73% | 9,365 | 9.17% | 5,219 | 14,584 |
| hybrid_fallback | Skin | 94.90% | 75.17% | 11,916 | 17.25% | 5,239 | 17,155 |
| hybrid_fallback | Other | 93.52% | 84.59% | 17,108 | 12.29% | 4,352 | 21,460 |
| hybrid_fallback | Background | 98.98% | 99.09% | 2,500 | 0.91% | 2 | 2,502 |
| hybrid_agreement | Hair | 98.81% | 85.69% | 13,945 | 13.65% | 676 | 14,621 |
| hybrid_agreement | Skin | 99.45% | 44.67% | 37,063 | 53.64% | 1,166 | 38,229 |
| hybrid_agreement | Other | 99.28% | 56.08% | 59,558 | 42.78% | 1,591 | 61,149 |
| hybrid_agreement | Background | 99.40% | 99.08% | 2,507 | 0.92% | 0 | 2,507 |

## Overall correction-effort comparison

There are 584,337 evaluated pixels: 310,489 foreground and 273,848 background.

| Method | All uncertain | All confidently wrong | Whole-frame proxy | Foreground proxy | Foreground proxy % |
|---|---:|---:|---:|---:|---:|
| rgb | 166,845 | 7,861 | 174,706 | 174,698 | 56.27% |
| spatial | 107,225 | 15,201 | 122,426 | 76,988 | 24.80% |
| segmented_spatial | 66,875 | 12,735 | 79,610 | 77,103 | 24.83% |
| hybrid_fallback | 40,889 | 14,812 | 55,701 | 53,199 | 17.13% |
| hybrid_agreement | 113,073 | 3,433 | 116,506 | 113,999 | 36.72% |

Fallback lowers the whole-frame proxy by 54.50% versus spatial and 68.12% versus RGB. Foreground proxy is 17.13%, compared with 24.80% spatial and 56.27% RGB. This is a measurable improvement in this proxy, not proof of editing-time savings. Fallback makes 14,812 confident errors, only slightly fewer than spatial (15,201) and substantially more than RGB (7,861). Hair recall is slightly lower than spatial; skin and other recall improve. Strict agreement cuts confident errors to 3,433 but increases uncertainty to 113,073; it remains a distinct conservative option rather than silently changing fallback behavior. Background accounts for much of the gain versus spatial, while fusion improves the foreground proxy further.

No existing mode is replaced or promoted to a new default. Use Hybrid experiment explicitly; Strict hybrid agreement chooses the conservative variant. The results support further assisted-editing trials, especially for hair and explicit background handling, with a timed comparison and a fresh sheet before any runtime use. Existing enclosed and antialiased background ambiguities and reference-alpha inconsistencies remain visible limitations.

## Verification

Godot runners: evaluate_background.gd (four masks and enclosed holes), evaluate_hybrid.gd (14 frames, five methods, target-label isolation, manual protection and history), hybrid_tests.gd (conflict rules, hair priority, skin fallback, strict policy, alpha, enclosed candidates, both model API routes), evaluate.gd (retained RGB/export regressions). UI smoke: hybrid_smoke.log. Each test runner reports CHECK FAILURES: 0. All outputs use built-in Godot Image APIs; no external services or model dependencies.
