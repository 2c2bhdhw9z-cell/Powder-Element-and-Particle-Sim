# Test fixtures

Data extracted verbatim from the web reference implementation, so the native port
can be verified against its actual source rather than against expectations
written out by hand.

Hand-written expectations would only prove that the transcription matches what
someone believed it should be. Comparing against the real table catches the
failure that actually matters: a mistyped digit in one of fifty elements'
properties, which compiles perfectly and quietly changes how something behaves.

## `web-default-elements.json`

All 50 built-in elements, as `DEFAULT_ELEMENTS` defines them in
`web/src/sim/element-registry.ts`.

Regenerate after any change to the web element table:

```bash
cd web
rm -rf /tmp/extract && mkdir -p /tmp/extract
npx tsc src/sim/element-registry.ts --outDir /tmp/extract \
  --module esnext --target es2022 --moduleResolution bundler --skipLibCheck
printf '{"type":"module"}' > /tmp/extract/package.json
( cd /tmp/extract && node -e "import('./element-registry.js').then(m => process.stdout.write(JSON.stringify(m.DEFAULT_ELEMENTS, null, 2) + '\n'))" ) \
  > ../native/Tests/CrucibleCoreTests/Fixtures/web-default-elements.json
```

`tsc` drops the type-only import automatically, so the emitted module runs under
plain Node. Importing it is safe outside a browser: the registry's constructor
checks for `window` before touching local storage.


## `web-powder-golden.json`

Eight powder scenarios run on the web engine, recording the resulting grid, the
cells carrying momentum, the occupied-cell count, the world fingerprint, and —
importantly — **how many random numbers the engine consumed**.

The draw count matters as much as the grid. Two engines can produce the same
picture while making their decisions at different points in the random stream; if
so they agree here by luck and will disagree somewhere else. Matching both means
the ported logic reaches the same branches in the same order.

Every scenario uses **only sand and bedrock**, and that restriction is what makes
the comparison meaningful. Neither element appears in any branch of
`reactions.ts`, has any declarative interaction, or matches any case in
`updatePhase`, and at ambient temperature heat diffusion has nothing to do. So
movement is the only subsystem with any effect, and the only one drawing from the
random stream. A scenario with water in it would consume draws in the water-spread
reaction, and the two streams would drift apart for reasons that say nothing about
whether the port is correct.

The generator lives at `web/src/sim/__tests__/golden-powder.spec.ts` and works in
both directions:

```bash
cd web
CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-powder   # regenerate the fixture
npx vitest run golden-powder                           # assert the web engine still matches it
```

Run without the variable it guards the *web* engine against drifting unnoticed.
So if a deliberate physics change is made on the web side, that test fails first,
the fixture gets regenerated, and the native suite then shows the same diff
instead of silently disagreeing.
