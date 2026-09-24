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
