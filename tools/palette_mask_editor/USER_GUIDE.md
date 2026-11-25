# Palette Mask Editor: practical user guide

The editor currently provides **assisted labeling**, not automatic recognition of hair and skin from a new image. You can create a mask without an existing reference, but you must supply initial class labels through color samples or manual painting. Spatial and hybrid transfer currently require a loaded reference mask containing a labeled frame.

## Start here: an image with no mask

1. Click **Load source** and select your sprite PNG. Do not load a reference.
2. Turn **Review overlay** on. Magenta means unresolved/reviewable; it is not exported. A black-looking mask with the overlay off does not mean the image has been fully classified as Other.
3. Change the left tool dropdown from **Brush** to **Label source sample**.
4. Choose **Hair** in the class dropdown. Click individual representative hair pixels in the **SOURCE** pane: dark, middle, and light shades. Each click adds the clicked source RGB as a labeled example. Clicking this tool does not paint the mask; the status message confirms that a sample was added. Dragging does not continuously collect samples.
5. Choose **Skin** and click representative skin shades. Then choose **Other** and click clothing, eyes, backpack, accessories, and any other colors to preserve.
6. Choose **Background** and sample the background if it is opaque, such as the black background in the supplied screenshot. Background means **white in the mask**, even when the artwork's background is black. Fully transparent source pixels are handled automatically; partial transparency is considered visible.
7. Leave **RGB tolerance** at 18 initially. Click **RGB baseline**. This generates suggestions across the entire source sheet using your samples. You do not need **Add reference labels**, the rectangle fields, landmarks, or either spatial/hybrid button for this workflow.
8. Inspect the result with **Review overlay** on. If a missing shade has no good sample, add samples with **Label source sample** and click **RGB baseline** again. A larger tolerance allows more distant RGB matches but can confuse materials; it does not add understanding of hair or skin.
9. Correct the mask with **Brush** or **Connected region fill**, selecting Hair, Skin, Other, or Background as appropriate. These actions confirm pixels. Automatic regeneration preserves manually confirmed pixels. To remove a confirmation, use **Erase decision**; visible erased pixels become uncertain again. Undo/redo works for painting, filling, erasing, and generation, but not for collecting/clearing samples.
10. Once all uncertainty is resolved, inspect confident predictions too, then click **Export PNG** and choose a new filename. Export writes a same-size RGB mask and refuses to overwrite existing files. It blocks export while uncertain pixels remain.

The four exported classes are exactly:

| Class selector | Mask color | Meaning |
|---|---|---|
| Hair | Red `#FF0000` | Recolor hair |
| Skin | Green `#00FF00` | Recolor skin |
| Other | Black `#000000` | Preserve visible clothing, eyes, accessories, etc. |
| Background | White `#FFFFFF` | Ignore background |

### Why this may still require substantial painting

Color sampling classifies by source RGB, not by recognizing the depicted object. If one brown appears in hair, skin, and clothing, the RGB baseline cannot reliably tell those locations apart. Sampling that brown under several classes is legitimate, but creates ambiguity. Keep those pixels reviewable and correct their locations manually. Merely adding many clicks on the same color does not teach the model its shape or position; it changes the global class vote for that RGB.

**Brush is not the sampling tool.** Brush labels/locks the specific pixels you paint. It does not add RGB training examples. Conversely, **Label source sample** adds color examples without labeling/locking the clicked location in the output. These are separate actions.

**Connected region fill is not an object-selection tool.** It starts at the clicked source pixel and follows four-connected source colors within tolerance of that seed. A shaded head of hair may contain many different colors and disconnected regions. Filling a dark outline can produce only a thin red outline, as in the screenshot, rather than identifying all the hair inside it. Use multiple fills or brush corrections; increasing tolerance can spill into skin or clothes.

## Which buttons need a reference?

| Operation | Needs an existing aligned mask? | Intended use |
|---|---|---|
| Brush / Connected region fill | No | Build or correct labels by hand |
| Label source sample + RGB baseline | No | Suggest labels from your own color examples |
| Add reference labels | Yes | Collect RGB/class counts inside a rectangle from an existing mask |
| Aligned Reference Copy | Yes | Reproduce the exact existing mask for identical aligned artwork |
| Generate spatial target | Yes | Transfer labels from a completed frame to a different frame on the same sheet |
| Hybrid experiment | Yes | Combine that frame transfer with RGB and source-background evidence |

The message **Load an aligned reference first** means you selected a reference-dependent operation. For an image with no reference, use the sample-tool/RGB workflow above instead. The experimental source-background detector is currently part of hybrid prediction and diagnostic tests; there is no separate background-only button in the UI.

## Using an existing mask correctly

### Reproduce a known mask

Load the source, load its matching mask with **Load aligned reference**, then use **Aligned Reference Copy** and confirm the replacement. This directly copies pixel labels; it does not infer anything. The operation replaces current corrections and can be undone. Matching dimensions alone do not establish that two different pieces of art are aligned.

### Transfer a completed frame to another frame

1. Load a source sheet and an aligned mask of the same overall dimensions that contains the completed reference frame.
2. Set **Reference sample rectangle (x,y,width,height)** to the completed frame's rectangle. Here this rectangle selects the spatial training frame; the default `(0,0,200,400)` is only an example and does not automatically select the character you intend.
3. Set **Spatial target (x,y,w,h)** to the new frame's rectangle. Both rectangles must be inside the sheet and must not overlap. Select similar direction, pose, and proportions where possible.
4. Leave landmarks empty initially. Click **Generate spatial target** or **Hybrid experiment**. You do not need to click **Add reference labels** first. Only the selected reference frame supplies labels; target-frame labels are not read.
5. Review/correct the target. Hybrid's **Strict hybrid agreement** option trades more uncertainty for fewer confident errors in the development benchmark. It affects only the hybrid button.

Optional landmarks pair matching points measured in **frame-local pixels**, not whole-sheet coordinates:

```text
sourceX,sourceY,targetX,targetY; sourceX,sourceY,targetX,targetY
```

For example, corresponding head centers can help align two frames. Landmarks position a local search; they do not identify body parts automatically.

**Current bootstrap limitation:** painting one frame in the live mask does not automatically make it the spatial reference. Spatial/hybrid read the loaded reference image, not the in-memory painted mask. To reuse a mask you created here, export it and load that file with **Load aligned reference**. Current export requires the whole source sheet to have no unresolved pixels, so there is no convenient “paint one frame, propagate immediately” workflow yet. The tool also does not currently load a differently sized reference-frame image or a separate target sheet for transfer. Do not mark unresolved areas as Other merely to bypass export validation.

## Coordinates and controls

- Rectangle `(x,y,width,height)` values use whole-sheet pixels, origin at the top left. `(0,0,200,400)` covers x=0–199 and y=0–399.
- **Add reference labels** samples only that rectangle, and repeated sampling accumulates counts. RGB baseline still predicts the whole sheet. **Clear samples** clears the RGB sample inventory, not painted mask labels.
- Mouse wheel zooms both panes. Middle drag pans both panes. Left drag paints with Brush/Erase; left click uses fill or adds one source sample. Either pane accepts edits, though the source pane is easier for sampling actual material colors.
- `Ctrl+Z` / `Ctrl+Y` undo/redo corrections and generation. Brush radius 1 paints a single pixel; larger settings paint a square footprint.
- Source and reference files are never edited. Export creates a new file. Work is held in memory; loading a different source resets it, and there is no session-save feature.

## Practical expectations

For a brand-new illustrated sprite sheet, start with a few color examples and inspect whether RGB suggestions save work. It is normal for a shared palette to require manual corrections. Spatial/hybrid assistance becomes available only after supplying a labeled reference frame in an aligned mask. The benchmark improvements reported in the evaluation documents were measured with completed idle-frame labels, not from an unlabeled image alone.
