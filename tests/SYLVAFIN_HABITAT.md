# Sylvafin habitat tests

Run from the repository root:

```powershell
pwsh -File tests/run_sylvafin_tests.ps1
pwsh -File tests/run_sylvafin_tests.ps1 -RegressionOnly
```

The default command includes final-contract checks and intentionally fails while
the current traversal checkpoint differs from the supplied final specification.
RegressionOnly tests existing functionality without accepting those differences
as final behavior. No gameplay code or authored habitat is modified.

Coverage: legacy/default/additive elevations; companion load and JSON round trip;
four centralized Sylvafin directions; deterministic frame sequence; 500 shared
animation textures created at different times; central rate changes and zero-delta
pause; live physics shoreline rejection, empty/decorative water traversal, and
solid rock collision; authored placement isolation and duplicate-build protection.
Labels reference specification acceptance IDs, but multiple checks per ID are
not separate acceptance tests. The 500-texture fixture verifies shared clock
behavior, not rendering throughput or 500 instantiated map nodes.

Final-contract checks expose shifted interaction anchors, missing named-region
validation, absent canonical basin/surface map records, the authored height/region
configuration, and 5 FPS rather than the requested approximately 4 FPS default.

Remaining acceptance coverage is explicitly unverified: polygon editor operations,
invalid/concave/standardized polygons (7–11), editor placement commits (12–13),
overlay-disable independence (17), actual interaction dispatch (18), pixel rendering
and Y-sort/mask/foreground checks (19–23, 30–31), attached/broken-host overlays
(24–25), instantiated-node timer inspection (28), map reload phase policy (32),
missing-direction diagnostic/fallback fixtures (34), full unload/reload cleanup
(35), and rendered-node performance (36). These need dedicated editor, rendering,
or lifecycle fixtures; data assertions must not be reported as pixel tests.
Manual artistic/editor checks 37–42 remain an in-editor acceptance pass.

The fixture companion is written temporarily under tests and removed after load.
Godot uses OpenGL3 with an explicit workspace log path. The Windows certificate
store warning is environmental; script errors and missing completion summaries
still fail the runner.
