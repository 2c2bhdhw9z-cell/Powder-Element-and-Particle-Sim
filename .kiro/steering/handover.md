---
inclusion: always
---

# Handover: work in progress

Written so a new conversation can carry on exactly where the last one stopped. Long conversations in the Kiro app
freeze and have twice refused to continue. Keep this file up to date as items are finished — it is the only thing a
fresh conversation has.

## How to work here

- **The owner does not read code.** Talk in plain, everyday English. No snippets, no jargon. Describe what things do.
- **Do not stop to report while work is unfinished.** Do not ration work, weaken tests, or scale anything down. There
  is no time limit. Finish every outstanding item before summarising.
- **Never excuse a defect by saying the reference implementation does the same.** "My port is faithful" is not an
  answer. If something looks or behaves wrong, fix it — in *both* engines (`native/` and `web/`), and re-record the
  comparison fixtures.
- **Push straight to the project's main line.** No branches, no pull requests. The main line has been renamed several
  times and a branch called `main` was deleted on purpose — never recreate it. Look the name up before every push:
  `/projects/sandbox/logs/push-main.sh` does this (it refuses if somebody else has pushed).
- If a bot merges something that breaks the project on purpose again, undo it with `git revert` (never force-push),
  say so in one plain line, and keep going. This happened with pull requests #6 and #7 (the "arena" bot); undone in
  commit `3aae16a`.
- The app itself only compiles on the checks' Macs (Swift 6, warnings are errors, iOS 17, no entitlements, no app
  extensions). On this Linux box, syntax-check app files with `swiftc -parse <file>` — it will not catch type errors,
  so expect CI to find those.

## If two conversations are working at once

Possible, and useful, but only with a boundary — otherwise both will edit the same handful of files and one of them will
lose work. Almost every app feature touches `App/Views/ContentView.swift`, the two trays, and the two models, so those
cannot be shared.

**Push with `sh scripts/push-to-main.sh`.** It looks up what the main line is called, replays the work on top of
anything that arrived meanwhile, and refuses rather than guessing if that will not go cleanly. Never `--force`.

The boundary that actually works:

- **The building conversation** owns everything under `native/App/` and `native/Sources/CrucibleCore/`, and its own new
  test files. It does the features, then the Field tray crash, then the performance work — in that order, because the
  last two touch the same files the features do.
- **The other conversation** owns `docs/`, `scripts/`, `.github/workflows/`, `native/UITests/`, and anything new in a
  folder of its own. That is: the engine in a browser, `METHOD.md`, the second opinion, the pictures of the app on a
  tablet and sideways, and ticking off what is built in `docs/lab-ideas.md`.
- **This file is shared.** Whoever edits it should push immediately rather than holding it, and should add rather than
  rewrite, so the two never disagree about the same paragraph.
- Neither should touch `native/Tests/.../Fixtures/` without saying so: those are recorded comparisons, and two
  conversations re-recording them at once produces a file that matches neither engine.

## Commands

```
cd native && swift build --build-tests && swift test --skip-build    # ~150 s, 1,205 tests / 89 suites
swift test --skip-build --filter <SuiteStruct>                       # one suite
swift build -c release --product crucible-daily                      # the day's-world drawer
swift run -c release --skip-build crucible-bench                     # ~17 min; use run_in_background
swift run -c release crucible-bench --gate bench-baseline.json       # the speed gate
cd web && source ~/.nvm/nvm.sh >/dev/null && npx vitest run          # 151 tests
CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-render                 # re-record a comparison
python3 scripts/check-png.py pictures/*.png                          # checks a PNG with somebody else's code
gh api "repos/2c2bhdhw9z-cell/Powder-Element-and-Particle-Sim/actions/runs?per_page=8" \
  --jq '.workflow_runs[]|"\(.name) \(.head_sha[0:7]) \(.status) \(.conclusion)"'
gh run view <id> -R 2c2bhdhw9z-cell/Powder-Element-and-Particle-Sim --log-failed
```

`gh run download` fails with HTTP 401 — read the logs instead. The App tour prints the whole screen's contents on
failure via its own `report(_:_:)`, which is how to see what was actually on screen.

## Pitfalls already paid for

- `#expect(cond, "text")` needs a single literal comment — no `+` joining, no `.joined()`.
- `#expect` cannot be handed a call that changes the thing it is looking at. Assign to a local first.
- `deinit` in a `@MainActor` class may not touch actor-isolated stored properties. The pattern used is a separate
  non-isolated holder class (`PowerWatchers`, `SenseWatchers`, `BigScreenWatchers`).
- `ContentView.body` is split four ways — `lab` → `labWithWatchers` → `labWithPanels` → `body` — because the compiler
  refused it as one expression. Put anything new **inside** whichever of the four it belongs to.
- The welcome screen must be an overlay, not `.fullScreenCover`: the cover took the view's one presentation slot and
  silently broke *every* panel in the app. Found only by the App tour.
- `git checkout <file>` throws away uncommitted work. It has cost real work here once.

## Where things stand (28 September 2026)

Everything below is committed and pushed. Latest commit `84e3937`.

Shipped this session, newest last:

- `b1cb5f4` A world can become a picture with no phone and nothing imported — a PNG writer in the engine, using
  stored zlib blocks so it needs no compression library. Verified by `file(1)` and Python's own zlib.
- `360bd05` The day's world drawn and published by a machine (`.github/workflows/daily.yml`,
  `Sources/CrucibleDaily/`). Plus two views that looked like nothing now look like something: the **heat view** was a
  flat green rectangle because it painted empty air (fixed in both engines, render golden re-recorded), and the
  **field picture** was a black rectangle because it drew one pixel per body instead of the body's real size.
- `71bbedc` Shape from a formula (`ParticleRecipeBox.swift`) — ten recipes, each declaring its own sliders. Reuses the
  force compiler and adds five words to it (`u`, `v`, `a`, `b`, `c`) plus a check in both directions that a formula is
  not using words meaningless where it sits.
- `afa9f4c` Layers (`ParticleLayers.swift`) — eight named groups, each with colour, hidden, locked, weight and air.
  Hiding moves bodies to the back of the crowd rather than dimming them, so the no-copy drawing path survives.
- `31c1a16` The discoveries notebook (`Support/Discoveries.swift`, `Powder/PowderNoticing.swift`,
  `App/Simulation/NotebookStore.swift`, `App/Views/NotebookSheet.swift`) — nineteen things to find, noticed only while
  the world is running its own rules, so painting glass is not discovering glass.
- `5f9bedc` Two checks that were failing for the wrong reason: the day's-world tool asked for a time zone spelling too
  new for the declared macOS, and the App tour's panel-scroll finder probed a point that fell in the gap above the
  panel's contents, so nothing ever scrolled and every control below the fold read as missing.
- `84e3937` Little people (`Powder/PowderPeople.swift`) — walk, climb one step, flee fire, fall, burn, drown, be
  carried. Two faults found by the checks and fixed in the engine: being afraid was a *posture* so anyone who saw
  danger while falling landed calm; and water only weakened gravity, so a long drop into a lake was still fatal.

Before this session: the powder lab tools, field measurements, speed gate, quick check, release notes, server contract
check, build cache, crash-log help, the App tour on iPhone and iPad, breadcrumbs and "That looked wrong", long runs,
power/thermal/battery, first run and Simple, the gallery of kept worlds, room senses, bad-link room tests, sleeping
bodies, the removal of the draw double-copy, glow folded from three passes to two, the powder world as a slab, the
television, `docs/IF-THIS-STOPS.md`.

**Confirmed already built** (checked against the code, not remembered): slice of the box, turntable video, tiny planet,
atom, marbling, pendulum wave, solar system, jellyfish, kaleidoscope, physics lens, shadows in 3D, colour by distance,
floating labels, ten fingers, hourglass, sand on a drum, foxes and rabbits, particle life, galaxy crash, supernova,
light painting, real down, camera focus, fly inside, slingshot, jelly pen, recorded force loops, arrangement morphing,
popcorn, soap, sponge, conveyor belt, magnet, sand art. **Do not rebuild these.**

## Still to build, in this order

1. **Guided lab book** — hands-on experiments that set something up, let the player find the answer, then explain it
   using their own world.
2. **Movie studio** — camera stops, travel speed between them, slow motion, captions, export a clip.
3. **Living soundscape** — water, fire, glass, electricity, impacts, mixed by what the simulation is doing.
4. **Creature builder** — bones, joints and muscles that have to balance. `Spring` already carries `pulse`, `beat`,
   `phase`, `thrust`, so the step already supports it; what is missing is the building.
5. **Parallel worlds** — two copies from the same moment, one thing changed, run together. The engine is already safe
   for this (final classes, per-instance seeded random, no singletons anywhere in `CrucibleCore`); the limit is that
   the app layer is one-engine-shaped (`ParticleFieldModel`, `ChamberBridge`, `RoomBridge`, `bigScreen`).
6. **Worlds within worlds** — zoom into one body, find another whole simulation inside it.
7. **Talk to it** (speech), **wave at it** (front camera), **look round with your head** (front camera), **on your
   table** (ARKit). These need permission strings in the app's Info.plist, which the agent adds itself — but they
   cannot be proved to work on this machine, which has no camera or microphone. Say so plainly; do not claim tested.
8. **Send a 3D moment** (USDZ), **Live Photo**.
9. Smaller ones: red-and-blue glasses 3D, a lava lamp, a clock spelt in bodies, colours taken from a photo (the engine
   can already recolour — it needs a button), a picture turned into real sand and water, relax mode.
10. Round 7 leftovers: **#21 the engine in a browser** (SwiftWasm may be unavailable offline — if so do the honest
    alternative and say exactly what was done instead), **#32 pictures of the app on iPad and sideways** from the
    tour, **#34 METHOD.md**, **#35 a second opinion** (another provider is not available; use the `semantic_reviewer`
    sub-agent and say so plainly).
11. Notes: mark what is built in `docs/lab-ideas.md`, `PORT-STATUS.md`, the README's test count, this file.
12. **LAST, as the owner ordered:** the crash when the up arrow on the Field tray's header is tapped (the app closes to
    the home screen; the Powder tray's arrow is fine). It does **not** reproduce on a simulator — it is device-only, so
    read `App/Views/FieldDock.swift` (`header`, `expanded`, `isDockOpen`) and the resize-on-open rather than trying to
    reproduce it. Also make opening a tray stop resizing the world, which currently wipes undo and rewind.
13. **Then maximum performance.** Re-measure everything, push it as far as it goes, update `native/bench-baseline.json`
    if the numbers genuinely moved. The owner cares about this most; it is deliberately after the crash because the
    crash fix may change what is worth measuring. Advice relayed from another AI, already judged: removing CPU→GPU
    round trips was done (the double copy is gone, glow is two passes not three); moving the physics onto the GPU was
    **rejected** and should stay rejected — it would destroy the golden comparisons against the web reference,
    replay-from-seed, shared rooms, and the ability to check the physics on Linux.

Waiting on the owner, so not to be started: server variables (#6), TestFlight and the paid account (#11, #12, #49),
anything needing an app extension (#44 to #46), "say 1.0" (#29), where the public face lives (#19).
