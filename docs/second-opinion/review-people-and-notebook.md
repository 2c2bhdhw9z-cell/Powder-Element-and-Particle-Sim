# Second opinion: little people (84e3937) and the notebook (31c1a16)

The people are a short list kept beside the grid, and they read the grid to decide what to do. The notebook is a set of flags that get raised whenever a cell's material changes while the engine is running a tick, and the app empties them once per frame. Both engine halves replay the same way every time from a seed, and the iOS app builds on CI. The trouble is that the people never got wired into the engine's existing world-state machinery. Undo, save/load, clear, rewind and resize all ignore them, and two paths leave people outside the world, invisible but still alive. They can also fall through a one-cell floor. On the notebook side, the rule "an event is not painting" lets the Meteor button file two pages whose descriptions are false, and several tests would still pass if the code they check were broken.

**Watch for:** people are not part of any world snapshot (confirmed); people who can't be seen or grabbed, created by rotating/shrinking the world or by dragging someone off the edge (confirmed); falling through thin floors (confirmed); Meteor writes "Melted stone" and "Fire caught" pages (confirmed); three tests that pass on broken code (confirmed by mutation or trace).

**Verdict**: NEEDS_CHANGES

## High-level view

People are kept in `storedPeople`, and nothing outside `PowderPeople.swift` reads or writes that array. So undo/redo (`PowderHistory.Snapshot`), saving (`PowderState`), rewind (which uses the same snapshots), Clear (`resetGrid`), loading a scene, flipping, resizing and resampling all act on the cells and leave the people exactly where they were. The app treats adding someone and pressing "Nobody" as undoable steps, but undo can do nothing to people.

People only get clamped to the world after a successful walking step. Falling, being dropped and resizing never clamp them, and drawing and grabbing skip anyone outside the bounds. Someone can therefore end up alive but invisible and out of reach, still counted against the limit of twenty.

Movement is integer-truncated position plus a fall speed that can exceed one cell per moment. Nothing checks the cells the person passes through on the way down, so thin floors leak. A climb moves the person up before they have crossed into the next column, so they fall back and try again several times before they make it.

The notebook's "only while running" rule works for brushes and loading. `start(_ event:)` switches noticing on for the whole event, though, and the meteor event *places* lava and fire straight into the world. "Fire caught" and "Melted stone" then get filed with explanations of a process that never happened.

The test suites back up the happy path but not the claims they're named after. The smoke test never looks for smoke. The quench test accepts steam as a substitute for obsidian and still passes with the quench hook deleted. The painting test never runs a tick.

<details>
<summary>Issues (12)</summary>

1. **People outside undo/redo/rewind**: undo after adding someone leaves them standing; undo after "Nobody" doesn't bring anyone back. Either add people to `PowderHistory.Snapshot`, or stop recording an undo point for people actions.
2. **People outside save/load/clear**: saving drops everyone, while loading a world or pressing Clear keeps the old people standing in the new one. Add people to `PowderState`, and clear them in `resetGrid`/`apply`, or explicitly on load and clear.
3. **Ghosts after the world shrinks**: rotating or resizing leaves people at coordinates past the new edge, alive forever and never drawn or grabbable. Clamp or remove them in `resize`/`resample` (the thermometer is already moved in `toolsFollowResize`; people are not).
4. **Ghosts from dragging off the edge**: `carryHeldPeople` takes the unclamped touch point, so a person dropped past the edge walks outside the world forever. Clamp in `carryHeldPeople` or `dropHeldPeople`.
5. **Falling through thin floors**: a fall speed of up to 1.1 cells per moment skips over a one-cell floor in 10 of 100 trials, and in another 10 of 100 the person lands with their feet inside a two-cell floor. Sweep the cells between the old and new position before moving.
6. **Climbing a step bobs**: one single-cell step takes 44 moments and 3 fall-backs (flat walking covers about 6 cells in that time). Move the person's x into the step column when they climb, or check footing under the destination column.
7. **Meteor files false pages**: `start(.meteor)` on an empty world records "fire" and "lava", whose text says something caught alight or stone melted. Turn noticing off while an event *places* material, and on only for the rules it sets off.
8. **Limit message never shown**: `peopleNote` ("Twenty is as many people…") is set but nothing in the app displays it, so a tap at the limit does nothing silently. Show it, or remove it.
9. **Smoke test doesn't test smoke**: `theyLeaveSomethingBehind` passes with the smoke line deleted, and drowning (the most common death) never leaves smoke because the cell is water. Assert on smoke, and decide what a death underwater should leave.
10. **Quench test can't fail**: `obsidianIsFound` accepts steam, and it still passes with `noticeMade(Element.obsidian)` removed. Assert obsidian on its own, in a setup where the ordinary cooling rule can't produce it.
11. **Painting test never runs a tick**: `paintingIsNotDiscovering` checks right after painting, which by construction can't notice anything. Paint and then step, as the probe does; that probe already finds wet sponge reporting itself.
12. **People ignore world gravity**: people always fall down the screen, whatever the gravity setting, while sand follows it. Read `gravityY` (and treat sideways gravity as unsupported), or say so in the feature text.

</details>

<details>
<summary>Details</summary>

All proofs come from throwaway tests, kept beside this file as `ReviewProbesTests.swift.txt` (suites `ReviewProbes`, `ReviewProbes2`, `ReviewProbes3`). Copied into `native/Tests/CrucibleCoreTests/` (without the `.txt`) they run with `swift test --filter ReviewProbes`; they print what they find rather than failing. The repository was not modified.

### Proven faults

**1. People are invisible to undo, redo and rewind.** Severity: fault, confirmed.
`PowderHistory.Snapshot` (`PowderHistory.swift:17`) captures only cells and world settings. The app still treats people actions as undoable: `peopleBeganStroke` calls `recordUndoPoint()` after `addPerson`, and `clearPeople()` calls it before `engine.clearPeople()` (`SimulationModel+Tools.swift`, the people section). Each of those also empties the redo stack. Probe output:

```
PROBE undo-after-add: undid=true people=1
PROBE undo-after-Nobody: people=0
```

Undo reports success, the undo arrow lights up, and nobody comes back or goes away. Rewind uses the same snapshots (`PowderLabTools.swift:318/344`), so scrubbing back shows the present people standing in a past world. Keep that moment, and they carry on from wherever they happen to be in it, possibly inside sand that wasn't there before.

**2. People are invisible to save, load and Clear.** Severity: fault, confirmed.
`PowderState` (`PowderSerialization.swift:41`) has no people field, and `resetGrid` doesn't touch `storedPeople`. Probe output:

```
PROBE save/load: before=1 after=0
PROBE load-over: people kept after loading an empty world=2
PROBE resetGrid: people kept after clear=2
```

A saved or shared world arrives empty of people. Loading a scene or pressing Clear keeps the current people, who then fall through the new world. Tides were added to `PowderState` when they arrived, so there's a clear precedent for persisting a feature like this.

**3. Shrinking the world leaves people nobody can see or grab.** Severity: fault, confirmed.
`PowderEngine.resize` doesn't know about people. `SimulationModel.applyLastKnownSize` calls it on every rotation or detail change, followed by `toolsFollowResize`, which moves the thermometer but not the people. `resample` (used on load, `SimulationModel.swift:1192`) doesn't scale them either. Probe: a person at x=90 in a 100-wide world, which is then resized to 50 wide and run for 2,000 moments:

```
PROBE shrink: alive=true x=90.5 y=29.0 health=1.0 pixelsDrawn=0 grabbableFromEdge=false
```

Here's the trace. `isSolidFooting` treats any out-of-bounds cell below the world as floor, so they "land" at y=height−1. Every walking step then fails `isWalkable` (`x < width`) and turns them around. `keepInside` only runs after a successful step, so it never runs. `drawPeople` skips `x >= width`. The ghost uses up one of the twenty places, and the only way to get rid of it is "Nobody". Growing the world back later brings them back into view, standing somewhere unrelated to where they were.

**4. Dragging someone off the edge makes the same kind of ghost.** Severity: fault, confirmed.
`SimulationSurface.fraction(of:in:)` doesn't clamp, and UIKit keeps reporting pan locations after the finger leaves the view. `gridPoint` doesn't clamp either; only `gridCell` does, and people use `gridPoint`. `carryHeldPeople` (`PowderPeople.swift:193`) copies the point as it is. Probe: carry to x=−4, drop, run 3,000 moments:

```
PROBE off-edge: alive=true x-range=-4.0...-4.0 y=29.0 doing=walking count=1
```

They stay at x=−4 forever, turning around every moment. For −1 < x < 0, `Int()` truncates to column 0, so that person is drawn and simulated in column 0 while their stored x is negative. That's harmless but it isn't what the code intends.

**5. People fall through one-cell floors, and land inside two-cell floors.** Severity: fault, confirmed.
`move` (`PowderPeople.swift:350–352`) adds `fall` (terminal 1.1) to y, then checks only the cell below the *new* position. Take a person at y=10.95 above a floor at row 12: the check at row 11 says empty, so they fall and y becomes 12.05, inside the floor. The next check looks at row 13, which is empty, so they carry on falling. Probe: 100 drops from heights 2–21 onto glass floors at rows 80–84:

```
PROBE tunnelling: trials=100 passedThroughOneCellGlassFloor=10 landedWithFeetInsideTwoCellFloor=10
```

Players build thin floors all the time: a line of glass, a metal shelf. A person dropped from the top of the screen passes through about one time in ten. When they land inside a thicker floor, `feel` marks them as buried and takes health until they climb out.

**6. Climbing one step bobs and takes about ten times as long as it should.** Severity: fault (the behaviour contradicts the commit's own claim), confirmed.
The climb branch (`PowderPeople.swift:379`) raises y by one while x has moved only 0.14, so the person is still in their old column. On the next moment, `standing` (`:336`) looks under that old column, where they were just standing and which is now empty. They fall back, land, walk 0.14, and try again. Probe on the shipped test's own layout:

```
PROBE climb: fell back 3 times; took 44 moments to get on top of one step
```

The commit's point was that "a person who stopped at each [step] would never go anywhere". This is close to stopping at each one: 44 moments per step, against the 6-plus cells they'd walk on the flat in that time. The shipped `theyClimbAStep` gives them 200 moments and only checks where they end up, so it doesn't catch this.

**7. The Meteor button fills in two pages with false explanations.** Severity: fault, confirmed.
`start(_:)` wraps every event in `whileNoticing` (`PowderEvents.swift:78`). `startMeteor` places lava and fire directly (`PowderEvents.swift:124`, `setElement(... lava : fire, temp: 2800)`). Probe on an empty world:

```
PROBE meteor on an empty world: notebook pages = ["fire", "lava"]
```

The pages read "Stone past twelve hundred and fifty degrees melted into lava" and "Something reached the temperature it catches alight at, and lit itself". Neither happened. This is exactly the "painting is not discovering" case the design says it rules out, just with the paint put down by a button.

**8. The "twenty people" message is never shown.** Severity: fault (small), confirmed.
`peopleNote` is written in `peopleBeganStroke` and declared in `SimulationModel.swift:247`. A grep of `App/` and `UITests/` finds no reader. At the limit, a tap takes the stroke and does nothing, with no feedback. `canAddPerson` is dead code as well.

### Tests that pass on broken code

**9. `theyLeaveSomethingBehind` (`PowderPeopleTests.swift:263`)** only asserts `people.isEmpty`. With the smoke `setElement` at `PowderPeople.swift:232` replaced by a no-op in the scratch copy, the whole `Little people` suite still passes. There's a behaviour gap as well: smoke is placed only if the body cell is empty, and a drowning person's body cell is water, so drowning (the most common death in a lake world) leaves nothing. Probe: `drowned=true smoke=0`.

**10. `obsidianIsFound` (`DiscoveriesTests.swift:61`)** asserts `obsidian || steam`. With `noticeMade(Element.obsidian)` deleted from the quench path in the scratch copy, the test still passes, and the probe shows obsidian is *still* noticed (through the ordinary cooling rule's `setElement`). So the test can't detect whether the hand-written quench hook it's named after works at all, and the hook may be redundant.

**11. `paintingIsNotDiscovering` (`DiscoveriesTests.swift:21`)** paints and asks straight away, without stepping. Outside a tick, `noticeMade` returns early by construction, so this is a tautology. The real risk is a painted material re-creating itself during a tick. A probe that paints each of the 15 materials alone and runs 120 moments finds one: a painted blob of wet sponge squeezes itself (a wet sponge sitting on another is "heavy"), turns back into sponge, re-soaks, and files "A sponge that soaked" without the player adding any water. Severity: nit for the sponge; the test weakness is the actual finding. `theOrderIsStable` compares a static against itself inside one process, so it can't observe Dictionary order changing between runs. The code sorts anyway, so there's no fault behind it.

### Risks and nits (confirmed by reading, lower impact)

**12. People ignore the world's gravity.** Severity: risk. `PowderPeople.gravity` is a constant added to +y, and `isSolidFooting` looks at y+1, whatever `gravityX`/`gravityY` are set to. With tilt or reversed gravity, sand falls one way and people fall the other.

- **Adding a person uses the physics random number stream** (`addPerson`, `PowderPeople.swift:152`, `rng.chance(0.5)`). Replay is still identical (probe: `replay identical grid=true people=true`). But a person added far away and removed again changes where every grain of sand lands (`PROBE add-then-remove … changes where the sand lands: true`). Anything that reproduces a world from a seed plus recorded strokes will diverge the moment a person is added. Deriving `facing` from the person's id would avoid touching the stream. Severity: risk.
- **"Something that looks alive" goes to anyone who picks the preset** (`ParticleFieldModel.swift:1217`): `particleLifeEnabled && momentsSinceArrangement > 120` is about two seconds after choosing it. Severity: nit (design).
- **The notebook folder comment is wrong.** "Made when it is first needed, so somebody who never finds anything is left with no folder at all" (`NotebookStore.swift:36`), yet `init()` calls `read()`, which goes through `directory` and creates the folder on every launch. Separately, `NotebookSheet.card` calls `store.picture(for:)` from the view body, which does `createDirectory`, `fileExists` and a JPEG decode on the main thread for every card on every re-render. Severity: nit / possible performance risk (not measured).
- **A doc comment was split in two** (`SimulationModel.swift:438`): the new `onDiscovery` was inserted between "Ticks per second actually achieved…" and `ticksPerSecond`, so that comment now describes the discovery callback. Severity: nit.

### Checked, nothing found

Same-seed replay with people matches exactly after 600 moments. Physics doesn't depend on Dictionary or Set order, or on a clock. The iOS build passes on CI at `7f6d1f2`, and I couldn't prove any Swift 6 concurrency fault from Linux. Per-moment cost doesn't grow with world size. A single explosive blob doesn't trip "chain reaction".

### Entries for the handover note, under "Found by chat two" (added there)

- Undo, rewind, saving, loading and Clear all ignore the little people. Undo after adding someone leaves them there; undo after "Nobody" doesn't bring them back; a saved world opens with nobody in it; loading or clearing keeps the old people.
- Turning the phone or changing the detail can leave people outside the edge of the world. They stay alive for good, can't be seen or picked up, and count towards the twenty. Carrying someone past the edge of the screen and letting go does the same.
- People sometimes fall straight through a floor one cell thick (about one drop in ten from high up). Sometimes they land inside a thicker floor instead.
- Climbing a single step takes about forty moments, because the person keeps slipping back off it three or four times first.
- Pressing Meteor on an empty world writes "Melted stone" and "Fire caught" into the notebook, with explanations of things that never happened.
- The "Twenty is as many people as a world can hold" message is never shown on screen.
- Three checks would still pass if what they check were broken: the smoke one, the lava-quenching one, and "painting is not discovering". Drowning never leaves the puff of smoke.

</details>

<details>
<summary>File map</summary>

- `native/Sources/CrucibleCore/Powder/PowderPeople.swift`: new; the person model, their step (feel/decide/move) and drawing. Findings 3–6, 9, 12.
- `native/Sources/CrucibleCore/Powder/PowderEngine.swift`: people and noticing state; `stepPeople` at the end of the tick; noticing switched on for the tick.
- `native/Sources/CrucibleCore/Powder/PowderRender.swift`: people drawn over the finished frame.
- `native/Sources/CrucibleCore/Powder/PowderNoticing.swift`: new; drain-on-read flags and chain counting.
- `native/Sources/CrucibleCore/Powder/PowderEvents.swift`: events wrapped in noticing; freeze notices by hand. Finding 7.
- `native/Sources/CrucibleCore/Powder/PowderExplosion.swift`, `PowderPhaseChange.swift`: noticing around explosions; hand hooks for steam and obsidian. Finding 10.
- `native/Sources/CrucibleCore/Support/Discoveries.swift`: new; the 19 discoveries and the notebook model.
- `native/App/Simulation/SimulationModel+Tools.swift`, `SimulationModel.swift`: people tool, undo points, `peopleNote`, discovery callback. Findings 1, 8.
- `native/App/Simulation/NotebookStore.swift`, `native/App/Views/NotebookSheet.swift`, `ContentView.swift`, `ElementDock.swift`, `ParticleFieldModel.swift`: notebook storage, sheet, wiring, dock chips.
- Tests: `PowderPeopleTests.swift`, `DiscoveriesTests.swift`. Findings 9–11.
- Full diffs: `git show 84e3937` and `git show 31c1a16`.

</details>

**Verdict: NEEDS_CHANGES.** Both features work on the happy path, but people are left out of every world-state operation (undo, save, load, clear, rewind, resize), people fall through thin floors, and the notebook records meteor-placed material as discoveries.
