# Move Creator v0.1

Launch from the repository root:

```text
godot --path . tools/move_creator/move_creator.tscn
```

The **Move Data** tab edits the canonical `moves` object inside `data/battle_data.json`. Select an existing move and Load it, or choose **New Move** and provide a stable lowercase `snake_case` ID, name, type, and damage class. **Save Move** validates and merges only the selected move into the complete database; it never replaces the database with one move.

Supported controls cover Name, Description, Power, Type, Damage Class, custom Animation ID, Fallback Animation, Condition and Condition Chance, Priority, and self Stat Changes. Stat-change amounts use the engine's existing signed fractional values. Engine fields without dedicated controls can be edited as an **Additional Engine Fields** JSON key-value module. The full raw move JSON can also be edited; both editors require valid JSON objects before changes are applied.

Animation IDs refer to definitions in `data/move_animations/`. **None / Use Fallback** removes `animation_id`. **Edit Animation** opens the selected definition in the embedded Animation tab. **New Animation** suggests the current move ID; save it separately in that tab, then use **Assign Current Animation to Move** and Save Move. Move and animation saves remain independent.

**Delete Move** first confirms removal of the selected move entry. It counts remaining `animation_id` references before deleting anything else: shared animations are always preserved, while an animation used only by the deleted move receives a second explicit “Also delete unreferenced animation …?” confirmation. The reference count is checked again immediately before file deletion. Move-effect PNG assets are never removed by this workflow.

Move-effect assets live in `assets/move_effects/`. `Attack_Projectile_*` and `Attack_Beam_*` PNGs are authored once in their Wild-side orientation and automatically flip horizontally when the animation User/caster is on the Player side. `Attack_Particle_*` assets remain unchanged on both sides. This rule is shared by preview and runtime and does not require duplicate imports or per-animation mirror fields.

The Animation tab also supports Beam events: a PNG is stretched and rotated automatically between semantic From/To anchors, with independent pixel width, lifetime, and semantic layering. Player-side beam textures are horizontally mirrored while their endpoint-driven geometry remains unchanged. Its nested draggable splits keep events, scrollable properties, preview, and playback controls usable at 1366 × 768 and larger.

Scale Battler supplies temporary Stretch/Shrink loops for the semantic User or Target. Vertical Sprite supplies anchored falling or rising PNG motion. Texture-backed creation events expose a white-default Tint using standard Godot modulation.

Fallback Animation writes the canonical `fallback_animation` field. Existing `animation_kind` values are displayed as their canonical fallback and migrated when that move is saved. The game engine—not this editor—owns fallback selection and animation playback behavior.

Conditions come from the canonical condition registry in battle data. Types are discovered from existing canonical moves. Unknown or specialized move fields are informational, not errors.

## Multi-Hit and Scheduled Effects

Multi-Hit is optional and serializes the engine's canonical integer `min_hits` and `max_hits` range. Disabling it removes those two fields. Each hit is resolved separately by the battle engine; the Initial Move Animation remains the move-level animation used by the existing per-hit sequencer. There is no accuracy or editor-owned sequencing configuration.

Scheduled Effect is also optional and authors the engine's single `scheduled_effect` recipe. Owners are User Battler, Target Battler, or Battle; triggers are Start of Turn or End of Turn. Delay Turns postpones matching trigger phases and Repeat Count determines the number of activations. Payloads use the implemented heal, damage, condition, or stat-change forms. `replace_group` is the only currently implemented stacking rule, so no unsupported stacking choices are shown.

Effect ID is an identity used for runtime bookkeeping and animation callbacks. The engine has no closed effect-ID registry, so Move Creator discovers existing IDs such as `seed` and `prayer` as guidance while permitting a non-empty custom ID. Effect Group is likewise data-defined; recipes currently use `after_move_effect` so effects on the same owner replace one another according to the runtime rule.

Initial Move Animation plays when the move is used. Scheduled Effect Activation Animation is the nested recipe `animation_id` and plays later when that effect activates. Its Edit/New actions use the same Animation tab without overwriting the initial animation assignment.

The game engine remains responsible for hit resolution, triggering, payload execution, ownership cleanup, and replacement behavior. Weather, hazards, Torment, and other legacy specialist fields not yet normalized as `scheduled_effect` remain visible and editable under Additional Engine Fields and survive load/save unchanged.

Current limitations: no move learnset/distribution editing, target stat-change editor, weather editor, arbitrary engine-field editor, balance analysis, or new gameplay-mechanic creation. A gameplay mechanic must exist in the engine and be added to the approved field registry before Move Creator exposes it.

Tests:

```text
godot --headless --path . --script res://tools/move_creator/tests/move_creator_model_test.gd
godot --headless --path . --script res://tools/move_creator/tests/move_creator_integration_test.gd
godot --headless --path . --script res://tools/move_creator/tests/normalized_move_authoring_test.gd
godot --headless --path . --script res://tools/move_creator/tests/move_animation_editor_model_test.gd
godot --headless --path . --script res://tools/move_creator/tests/pre_migration_features_test.gd
godot --headless --path . --script res://tools/move_creator/tests/beam_event_test.gd
godot --headless --path . --script res://tools/move_creator/tests/sprite_transform_events_test.gd
godot --headless --path . --script res://tools/move_creator/tests/move_effect_mirroring_test.gd
godot --headless --path . --script res://tools/move_creator/tests/structured_authoring_acceptance_test.gd
```
