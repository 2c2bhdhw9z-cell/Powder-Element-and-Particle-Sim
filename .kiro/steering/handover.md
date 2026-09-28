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
- **No web or browser version.** The owner does not want one, so do not build one or suggest one. The `web/` folder
  stays only as the reference the phone's engine is checked against: nobody uses it, it gets no new features, and a
  fault found in it is fixed there as well as in `native/`, as above.
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

Possible, but only with a boundary. Almost every app feature touches the main screen, the two trays and the two models,
so two conversations editing those will lose each other's work.

**Push with `sh scripts/push-to-main.sh`.** It looks up what the main line is called, replays the work on top of
anything that arrived meanwhile, and refuses rather than guessing if that will not go cleanly. Never `--force`.

- **Chat one — the app.** Owns `native/App/`, `native/Sources/`, `native/Tests/` (the recorded comparisons included),
  `native/UITests/`, `native/Package.swift`, and `web/src/` (fixing both engines is its job). Does "Still to build" in
  order and adds a walkthrough for each feature, then the Field tray crash, then the performance work. The tablet and
  sideways pictures (#32) are its too: they come from the walkthrough, and any fix they need is app code.
- **Chat two — everything around the app.** Owns `docs/`, `scripts/`, `.github/workflows/`, `README.md` and
  `PORT-STATUS.md`. Does #34 `METHOD.md` and #35 the second opinion, and keeps `docs/lab-ideas.md`, `PORT-STATUS.md`
  and the README's test count current. If it finds a real fault in the app, it writes it under "Found by chat two"
  below rather than fixing it.
- If either has to touch the other's files, make that one change on its own and push it straight away.
- **This file is shared.** Add to it rather than rewriting, and push at once. When chat one finishes something it adds a
  line under "Shipped"; that is how chat two knows what to tick off.

### Done by chat two

- `METHOD.md` (#34), and a first second opinion (#35) in `docs/second-opinion.md` — findings below.
- `docs/lab-ideas.md`: what is built added to the shortlist, where Round 7 stands (checked against the repository),
  the duplicated "Tried and not shipped" section removed. `PORT-STATUS.md` and the README: counts run and corrected
  (then 1,215 engine tests; now 1,288 in 100 suites, plus 151 reference and 93 script tests), all the checks
  listed, the old "never edit web/" rule marked superseded.

### Found by chat two

- ~~The engine does not compile for a 32-bit machine (three constants too big for a whole number there).~~
  **Withdrawn — nothing to do.** It only mattered for the browser version, which the owner does not want. The browser
  work was stopped before anything of it was committed; there is no `browser/` folder and no browser check.

**From the second opinion (28 Sep), every one proved by a failing throwaway test that was run twice.** Details, file
and line for each, in `docs/second-opinion/`; the tests themselves are the `.txt` files there — copy one into
`native/Tests/CrucibleCoreTests/` without the `.txt`, fix, and it becomes the regression check.

Little people (`84e3937`) and the notebook (`31c1a16`):
- Undo, redo, rewind, saving, loading and Clear all ignore people (`PowderHistory.Snapshot`, `PowderState` and
  `resetGrid` never touch `storedPeople`). Undo after adding someone leaves them; undo after "Nobody" brings nobody
  back; a saved world opens empty of people; loading or clearing keeps the old people.
- Rotating the phone or changing the detail (`resize`/`resample`) can leave people past the new edge: alive for good,
  never drawn, impossible to pick up, and counted in the twenty. Carrying someone past the edge and letting go does the
  same (`carryHeldPeople` takes the unclamped touch point).
- People fall through a floor one cell thick in about one drop in ten, and land inside a two-cell floor as often
  (`PowderPeople.swift` ~350: only the cell under the *new* position is checked, and falling reaches 1.1 cells a moment).
- Climbing one step takes about 44 moments with three slips back: the climb raises them before they have moved into
  the step's column.
- Meteor on an empty world files "Melted stone" and "Fire caught": noticing is on for the whole event, and the event
  places lava and fire itself (`PowderEvents.swift` ~78 and ~124).
- The "Twenty is as many people…" message (`peopleNote`) is set and never shown.
- Three checks pass on broken code: `theyLeaveSomethingBehind` never looks for smoke (and a drowned person leaves
  none), `obsidianIsFound` accepts steam instead, `paintingIsNotDiscovering` never runs a moment. Run for real, a painted
  wet sponge files "A sponge that soaked" by itself.
- Smaller: people always fall down the screen whatever the world's gravity; adding a person draws from the world's own
  random numbers, so it changes where the sand lands. Also seen: five separate explosions set off while paused count
  as one chain of five.

- **A note that disagrees with itself:** "Confirmed already built" above lists the *tiny planet*, but no such scene
  exists — only the gravity toward the middle shipped, and `docs/lab-ideas.md` ("Tried and not shipped") records why
  the world itself did not. The ideas list is right; the "confirmed" line is wrong. Do not rebuild the gravity; the
  planet itself is still open, and is blocked on the physics that note describes.

Layers (`afa9f4c`) and shape recipes (`71bbedc`):
- Undo restores bodies but not the layer list, current layer or colour memory (`makeSnapshot`/`apply(_ snapshot:)` in
  `ParticleEngine.swift`). Undoing a delete leaves A's bodies counted as B's; undoing a colour leaves the layer
  claiming the colour.
- `Swarm.spawn` never writes the layer tag and `removeAll()` never resets `hasGroups`, so new crowd bodies inherit tags
  of removed ones: hide a layer, clear, add 5,000 and only 4,990 show.
- The crowd is never born into the current layer (only `addParticle` reads it); the layer tests hide this by passing the
  layer in by hand.
- Locks leak: freeze stops locked crowd bodies (`Swarm.swift` freeze stage, flat and 3D), and in the flat step the
  second finger and the kaleidoscope push locked layers (`ParticleStep.swift` ~805 omits `lockedLayers:`).
- A recipe outlives its scene: `storedRecipe` survives `clear()`, new scenes and undo, and its sliders bend a morph into
  the old shape.
- Hiding and showing a layer reorders the crowd, and the morph and recipe hand out targets by position, so bodies walk a
  third further and criss-cross.
- Bodies merged or moved onto a coloured layer keep their old colour; bodies that join a coloured layer after its first
  repaint are never coloured.
- The recipe code meant to leave out unusable values can never run (the formula already turns them into nought), so
  `sqrt(u - 0.5)` stacks half the bodies on one line.
- Hidden cloth still draws its springs (`ParticleFieldModel.swift` ~1529, read not run). Duplicating a layer drops its
  springs, and duplicating an empty layer still makes one.
- The engine and the save loader accept a force written in a shape's words (`sin(u * 4)`), which then silently does
  nothing; the "both directions" check lives only in the app's text box.

## Commands

```
cd native && swift build --build-tests && swift test --skip-build    # ~230 s, 1,288 tests / 100 suites (28 Sep)
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
- `ContentView.body` is split six ways — `lab` → `labWithWatchers` → `labKeepingTime` → `labSensing` →
  `labWithPanels` → `body` — because the compiler refused it as one expression (it refused `labWithWatchers` again
  once it grew). Put anything new **inside** whichever of the six it belongs to, and split again rather than lengthen
  one past about a dozen modifiers.
- A closure handed to something that calls it off the main thread — an audio node, a camera, a canvas — must be made
  in a `nonisolated static func` (see `LabAudio.soundscapeNode`, `SpeechListener.tap`). Written inline in a
  main-actor class it belongs to the main thread and the first call from elsewhere closes the app.
- The welcome screen must be an overlay, not `.fullScreenCover`: the cover took the view's one presentation slot and
  silently broke *every* panel in the app. Found only by the App tour.
- `git checkout <file>` throws away uncommitted work. It has cost real work here once.
- **Never run a command that waits in a loop** (check the build, sleep, check again). The chat window freezes behind it
  and shows a spinner for an hour after the command has finished. Check once, do other work, check again later.
- Long conversations freeze and then refuse to continue. Commit and push after every piece of work, keep this note
  current, and start a fresh conversation before one gets long.

## Where things stand (28 September 2026)

Everything below is committed and pushed. Use `git log -1 --oneline` for the exact latest commit; an old hash here
went stale while the same handover already described thirty-one newer commits.

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

Shipped by chat one on 28 September, second session, newest last:

- `7f6d1f2` Walkthrough fixes: the discovery note sat over the tray and a thumb reaching for a tool opened the notebook
  (moved to the foot of the world); a fresh start now forgets last time's note like a new install; the walkthrough
  scrolls with slow drags instead of flicks that flew past sliders.
- `d4a85bb` **Guided lab book** (#1 below) — `Powder/PowderLabBook.swift`, `App/Views/LabBookSheet.swift`,
  `App/Simulation/SimulationModel+LabBook.swift`, `LabBookStore.swift`; "Lab book" in the powder tray; walkthrough
  `testLabBook`. Eight experiments; checks prove each answers when done and never by itself.
- `9289ef3` + `bb34b29` **Movie studio** (#2) — `Particle/ParticleMovie.swift`, `App/Views/MovieStudio.swift`,
  `App/Metal/ClipWriter.swift` (writes the world alone into an .mp4 on the graphics chip, no copy back), movie saved
  with the world; `NSPhotoLibraryAddUsageDescription` added (saving from the share sheet used to close the app);
  walkthrough `testMovieStudio`.
- `24dd560` **Living soundscape** (#3) — `Audio/Soundscape.swift` (listener + synth, tested), `SoundscapeVoice` and
  an `AVAudioSourceNode` in `LabAudio.swift`; switch "The world's own sound" under Sound; walkthrough
  `testSoundscape`.
- `f230b20` + `715745c` **Creature builder** (#4) — `Particle/ParticleCreatures.swift` (plans, ready-made walker /
  table / tumbler, floor grip for creatures only, saved with the world), `App/Views/CreatureBuilder.swift`;
  walkthrough `testCreatures`.

**Confirmed already built** (checked against the code, not remembered): slice of the box, turntable video,
atom, marbling, pendulum wave, solar system, jellyfish, kaleidoscope, physics lens, shadows in 3D, colour by distance,
floating labels, ten fingers, hourglass, sand on a drum, foxes and rabbits, particle life, galaxy crash, supernova,
light painting, real down, camera focus, fly inside, slingshot, jelly pen, recorded force loops, arrangement morphing,
popcorn, soap, sponge, conveyor belt, magnet, sand art. **Do not rebuild these.**

## Status check, 28 September (later)

Checked against the repository, not remembered: items 5 to 9 below are **all built** — parallel worlds (`710c5a5`),
worlds within worlds (`796f666`), talk / wave / look / table (`9d9b2fa`), 3D moment and Live Photo (`218fb86`), lava
lamp (`0bdc177`); red-and-blue glasses, the clock, photo colours, photo into powder and relax mode were built earlier.
Also seen, part of #12: an arrangement chosen with the Field tray open is laid out in the smaller world above the tray,
and closing the tray grows the world with a plain `resize` that moves nothing — so the galaxy's black hole ends up a
third of the way down the screen, not in the middle. The worlds-within walk now searches for it instead of failing.
The iPad and sideways picture review is done. Text and controls stay readable, panels fit, and parallel/worlds-within
views use the space well. It also exposed a real layout fault: the opening galaxy was made at a temporary phone-sized
area, then a battery/darkness setting falsely marked it edited before the real screen arrived, leaving most of an iPad
or sideways field empty. Fixed in `16dafe3`; the picture check now looks at the clear body of the world rather than
letting overlaid buttons disguise a blank area. The powder opening and tray animation still resize/shift worlds and can
overlap controls; fold those into #12's resize fix.

~~What is genuinely left~~ — superseded by "Done late 28 September" at the end of this file.

A full audit found one still higher-priority omission not in the second opinion: a field may hold one million crowd
bodies, but a save silently keeps only 24,000, and an undo snapshot above 200,000 omits the crowd then restores that
omission as an empty crowd. The app does not warn about either. Do this before the other remaining work: data must not
quietly disappear. The same audit found the public Vercel server is still on an older production commit and currently
reports temporary storage and accounts off; that half needs the owner to update Vercel's Production Branch and supply
the variables in `ONLINE-PLAN.md`.

Automation fixed during the audit: the server workflow now checks every web/server path and runs typing, style, all
244 reference/script tests and a production build; daily picture releases are prereleases so they cannot replace the
latest app-download link; app release notes no longer claim the separate engine/tour checks already passed. A
high-severity flaw reported in the server's YAML reader was pinned to its repaired version; `npm audit` now finds none.

Fixed in this check: the day's-world job had never once passed (no Python in its machine, then a too-strict colour
rule for a calm world's heat picture). Several App tour failures were faults in the walk itself: the movie could finish
before it tried Stop, the share sheet was swiped in the wrong place, the Photos permission question was never answered,
layers were scrolled in the wrong area, and a valid sparse world was called blank for having two colours. The lab
book exposed a real app fault: “Show me” waited on simulation/display progress, so a very slow phone could wait forever.
It now uses a separate active foreground clock, pauses when the world or app pauses, and publishes help without waiting
for another physics step. The final app code at `16dafe3` passed all 1,288 engine tests in plain and optimised builds,
built into `build-159`, and completed all sixteen walkthrough journeys on both iPhone and iPad. One first iPad runner
failed to launch the app and then froze inside Xcode for four hours; it was canceled and a clean replacement passed.

## Still to build, in this order

1. ~~**Guided lab book**~~ — **shipped `d4a85bb`.** Hands-on experiments that set something up, let the player find the answer, then explain it
   using their own world.
2. ~~**Movie studio**~~ — **shipped.** — camera stops, travel speed between them, slow motion, captions, export a clip.
3. ~~**Living soundscape**~~ — **shipped.** — water, fire, glass, electricity, impacts, mixed by what the simulation is doing.
4. ~~**Creature builder**~~ — **shipped.** — bones, joints and muscles that have to balance. `Spring` already carries `pulse`, `beat`,
   `phase`, `thrust`, so the step already supports it; what is missing is the building.
5. ~~**Parallel worlds**~~ — **shipped `710c5a5`.** Two copies from the same moment, one change, run together.
6. ~~**Worlds within worlds**~~ — **shipped `796f666`.**
7. ~~**Talk / wave / look with your head / put it on a table**~~ — **shipped `9d9b2fa`.** Built and permissioned,
   but camera, microphone and AR behaviour still need a real-device check; do not claim they were proved here.
8. ~~**Send a 3D moment / Live Photo**~~ — **shipped `218fb86`.** Live Photo still needs a real photo-library check.
9. ~~**Smaller ones**~~ — **all shipped:** red-and-blue glasses, lava lamp, body clock, photo colours, photo into
   powder, and relax mode.
10. ~~**Review the iPad and sideways pictures**~~ — done in the audit. Panels and text fit. The field's off-corner
    opening scene was fixed in `16dafe3`; tray/powder resizing and animation overlap remain under #12. #34 `METHOD.md`
    and #35 the second opinion shipped in `447e6ac`. **#21, the engine in a browser, is dropped: the owner does not want
    a web or browser version.**
11. ~~**Status notes**~~ — updated after the full audit. Before more features: fix silent large-world save/undo loss,
    then every proved people/notebook/layers/recipes fault under “Found by chat two.”
12. **Then, as the owner ordered:** the crash when the up arrow on the Field tray's header is tapped (the app closes to
    the home screen; the Powder tray's arrow is fine). It does **not** reproduce on a simulator — it is device-only, so
    read `App/Views/FieldDock.swift` (`header`, `expanded`, `isDockOpen`) and the resize-on-open rather than trying to
    reproduce it. Also make opening a tray stop resizing the world, which currently wipes undo and rewind.
13. **Then maximum performance.** Re-measure everything, push it as far as it goes, update `native/bench-baseline.json`
    if the numbers genuinely moved. The owner cares about this most; it is deliberately after the crash because the
    crash fix may change what is worth measuring. Advice relayed from another AI, already judged: removing CPU→GPU
    round trips was done (the double copy is gone, glow is two passes not three); moving the physics onto the GPU was
    **rejected** and should stay rejected — it would destroy the golden comparisons against the web reference,
    replay-from-seed, shared rooms, and the ability to check the physics on Linux.

Waiting on the owner, so not to be started: Vercel's Production Branch and server variables (#6), TestFlight and the
paid account (#11, #12, #49),
anything needing an app extension (#44 to #46), "say 1.0" (#29), where the public face lives (#19).

## Field controls: both styles (28 September, late)

The owner wants **both** ways of opening the Field's controls, with a choice: the list menu ("Particle field — Choose
one part to change") and the original one scrolling tray. `FieldDock.Presentation` has `.dock`, `.tray` and `.menu`;
the choice is `@AppStorage(FieldDock.listMenuKey)` (default: list menu) and a swap row sits at the top of each. The App
tour launches with `-fieldControlsUseListMenu NO` so it keeps walking the tray. The Physics part closed the app on a
real iPhone from both styles (never on the simulator). It now lives in `App/Views/FieldPhysicsControls.swift` as many
small separate views with range-clamped sliders and safe number text; every tray section and menu page is also wrapped
separately. Not yet confirmed on the owner's phone.

## Done late 28 September (second chat of the evening)

- Tray resizing: already fixed by `45d20c2`/`af89e09` — the world is sized once; trays, split and rotation only change
  the viewport, never the world or undo/rewind.
- `25d7959` people: fall is swept row by row (no falling through one-cell floors), climbing moves onto the step
  (about 20 moments, no slips), fall follows the world's downward pull (none or upward = they hang), drowning leaves
  smoke, "Twenty is as many people…" is shown (`people.limitNote`), Meteor no longer files Fire/Melted stone. Weak
  checks rewritten (painting now runs 120 moments; obsidian alone; meteor, drowning, thin floors, pull, climb speed).
- `abf0592` layers/recipes: hiding the current layer moves "current" to a shown one; hide/show keeps morph and recipe
  targets with their bodies (`exchangeCrowdBodies`, `storedRecipeSlots`); formula places with no real answer are left
  out (`shapeValue(for:)`); the engine refuses forces that read shape words. Every second-opinion probe was re-run:
  everything else on that list was already fixed. The field probes live on as `LayerAndRecipeRegressionTests*.swift`.
  F15 was a false alarm (the probe repainted a body by hand).
- `8197c3d` the open powder tray is drawn over the world like the Field tray (`ElementDock.Presentation`), not on the
  upside-down alignment guide; the walk drags inside `tray.expanded`. The Field tray is a plain stack loaded four parts
  at a time: as a lazy stack it hung the iPhone simulator for minutes when scrolled far down — on a phone that is the
  system closing the app, so it may have been the real "tray crash".
- `332c807` speed: release builds of CrucibleCore use `-enforce-exclusivity=unchecked` (the profiler showed ~38% of
  time in access checks; debug and every test keep them on), and the crowd step and collisions hold their buffers in
  locals. Same Linux machine, before → after: powder 200×430 5.9 → 2.9 ms, 420×910 25.4 → 12.6 ms, 25,000 colliding
  36 → 28 ms, 500,000 free 3.6 → 3.3 ms. `bench-baseline.json` not changed: it was recorded on the CI machine, whose
  gate will show the real figures. 1,309 tests pass in plain and optimised builds.
