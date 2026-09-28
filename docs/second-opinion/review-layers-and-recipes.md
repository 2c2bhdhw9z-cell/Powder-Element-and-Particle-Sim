# Second opinion: Layers (afa9f4c) and shape recipes (71bbedc)

Layers split the world into up to eight named groups. Each group has its own colour, can be shown, hidden or locked, and has its own weight and air. Hiding a group moves its crowd bodies to the back of the list so the screen can draw fewer of them. Recipes make the crowd hold a shape worked out from two formulas, and the shape's own sliders reshape it. The basic path works and the author's tests pass. But undo, clearing the world, the crowd's own ways of adding bodies, and the less common tools were never tested against layers, and several of the commit messages' claims turn out to be false. **16 of the 18 proof tests I wrote failed against the code as committed.**

Watch for: undo brings the bodies back but not the layer list, so undoing a delete leaves the bodies on the wrong layer (confirmed). New crowd bodies take on a layer tag left over from bodies that were removed earlier, so a fresh scene can be partly invisible (confirmed). The crowd is never born into the current layer (confirmed). Locked layers can still be frozen by the finger and pushed by a second finger (confirmed). A recipe's sliders keep working after the recipe has been replaced, and bend whatever scene is now on screen into the recipe's shape (confirmed).

**Verdict**: NEEDS_CHANGES

## High-level view

The layer list and the per-body layer tags are kept in two places that undo treats differently. Undo's saved copy holds every body's tag but not the list of layers, the chosen layer or the colour memory. Every layer action that can be undone (colour, empty, copy, merge, delete) therefore comes back half-undone. Saving and loading are fine, because the save file does carry the list.

The crowd's layer tag was added to the one way of adding a single body, but not to the batch way of adding thousands at once, and clearing the world never resets the "some bodies have tags" switch. Batches, scenes and the 3D ball therefore pick up whatever tags earlier bodies left in memory. The layer-choice code only ever reaches named bodies, so every crowd body is born into the first layer, whichever layer is chosen.

"The crowd's order carries no meaning" is the premise that makes cheap hiding work, and it is false. The morph and the recipe sliders both give out targets by position in the list. Once hiding a layer has reordered the crowd, they hand each body another body's target.

Locking only covers the main finger's push. The freeze stage and the flat-world second finger / kaleidoscope copies skip the lock check.

The recipe is never forgotten: clearing the world, choosing another scene and undo all keep it. The slider handler only compares titles, so a stale Rose reshapes a morph. On the formula side, only the recipe side actually refuses the other side's words inside the engine. For forces, the refusal lives only in the app's text box. The "unusable numbers are left out" code can never run, because the formula compiler already turns every unusable number into nought.

Several of the author's tests pass without testing their claim. The layer tests add crowd bodies by passing the layer in by hand, which hides the "never born into the current layer" fault. The tint-undo test checks colours but not the layer's own colour setting. The "nonsense is left out" test uses a formula that produces no nonsense. The "check goes both ways" test only does set arithmetic and never calls an engine path.

<details>
<summary>Issues (14)</summary>

1. **Undo forgets layers** — `makeSnapshot`/`apply(_ snapshot:)` do not carry `storedLayers`, `storedCurrentLayer` or `storedAppliedTints`. Add all three to `Snapshot` and restack after restoring.
2. **Stale layer tags on spawned bodies** — `Swarm.spawn` never writes `groups[i]` (flat or 3D), and `removeAll()` never resets `hasGroups`. Write the tag in `spawn` and reset the switch in `removeAll`.
3. **Crowd ignores the current layer** — `spawnBatch` (≥4000), scenes, emitters and every other `swarm.append`/`spawn` use layer 0. Route the current layer through, or stop claiming it.
4. **Freeze ignores locks** — the step's freeze stage (Swarm.swift:1255 flat, :1477 depth) has no layer check. Check the lock table there too.
5. **Second finger ignores locks (flat)** — ParticleStep.swift:805 calls `applyBrush` without `lockedLayers:`. Pass `locks` as the 3D path already does.
6. **Recipe outlives its scene** — `storedRecipe` is not cleared by `clear()`/`beginScene`, and is not part of undo. Clear it in `clear()` and include it in the snapshot.
7. **Morph and recipe targets are by position** — restacking scrambles which body goes to which target (measured 34% longer walks). Restack only between scenes, or have `settleMorph`/`turnRecipeKnob` skip hidden bodies and restack the targets too.
8. **Merge/move keep the old colour** — bodies poured into a coloured layer keep the colour of the layer they left. Re-tint moved bodies to their new layer.
9. **Tint applied once only** — bodies that join a coloured layer later are never tinted. Tint a body when it joins (in `addParticle` and in the crowd path).
10. **Force check lives only in the app** — the engine and the save loader accept `sin(u*4)` as a force, which comes out as a force of nothing. Do the check in `ParticleEngine` (setter and `apply(state)`).
11. **"Left out" code is dead** — `recipePlaces`' `isFinite` guard can never fire, so bad values land on one line (500 of 1000 bodies in one stripe in my test). Either make the evaluator report bad values, or drop the claim and fix the test.
12. **Hidden cloth still shows its springs** — the app draws every spring whatever layer its ends are on (ParticleFieldModel.swift:1529). Skip springs whose ends are both hidden.
13. **Duplicate drops springs and ignores "nothing to copy"** — copies are loose bodies, and an empty layer is still duplicated even though the doc says `nil`. Copy springs between copied bodies (with new index numbers), and return nil when nothing was copied.
14. **Tests that don't test the claim** — `addCrowd` passes the group in by hand, `tintingCanBeUndone` never checks the layer's tint, `unusableNumbersAreLeftOut` uses a good formula, and `theCheckGoesBothWays` never calls the engine. Rewrite each to go through the real path.

</details>

<details><summary>Details</summary>

All proofs are throwaway tests, kept beside this file as `ReviewFieldFaults.swift.txt` and `ReviewFieldFaults2.swift.txt`. Copied into `native/Tests/CrucibleCoreTests/` (without the `.txt`) they run with `swift test --filter ReviewFieldFaults`. Each test asserts what the commit or its comments claim, so a failing test is the evidence. Each output line starts with the name of the scratch test that printed it, and those names do not match the finding numbers below. Nothing in the repository was changed.

## Proven faults

### F1. Undo brings bodies back onto the wrong layer. Fault, confirmed.
**Where:** `ParticleEngine.swift:862` `makeSnapshot` / `:899` `apply(_ snapshot:)`. `storedLayers` does not appear in either.

Undo restores every body's layer tag but leaves the layer list as it is now. Take layers A and B and delete A. Undo brings A's 5 bodies back still tagged 1. The list is still `[Everything, B]`, so those bodies now count as B's, take B's rules, and B's own 7 bodies point at a layer that no longer exists. This is exactly the "bodies silently belonging to a different layer" the commit says the renumbering prevents.
```
F1 after undo: layers=["Everything", "B"] inLayer1=5 crowd=12
Expectation failed: (engine.layers.count → 2) == 3
```
The same gap breaks the commit's "colouring a layer can be undone" (F2). Undo puts the colours back, but the layer still says it is red:
```
F2 after undo: colour restored=true layer tint still=Optional(#dc3232)
```
The colour memory (`storedAppliedTints`) is not restored either. After an undo, choosing the colour the layer already shows is treated as "no change" and nothing is painted. Undoing an empty, copy or merge leaves the layer list in its after-state in the same way.

### F2. New crowd bodies pick up layer tags left behind by removed bodies. Fault, confirmed.
**Where:** `Swarm.swift:601` `spawn`. Both loops (`:633` 3D, `:665` flat) write every per-body list except `groups`. `Swarm.swift:460` `removeAll()` resets `hasRoles`, `hasSizes` and `hasDepth`, but not `hasGroups`.

The layer tag's memory is reused. A body spawned where an earlier body lived inherits that body's layer. `clear()` does not reset the layers, and a new scene calls `clear()`, so the hidden layer is still hidden and the new bodies are invisible:
```
F3  spawned=5000 shown=4990 tagged-hidden=10        (hide a layer, clear, add a crowd)
F3b layer0=4995 layer1=10                           (empty layer 1, choose layer 0, add a crowd)
```
The same happens in 3D (same code) and for anything built on `spawn`: `spawnSwarmScene`, `spawnBatch`, joining (`ParticleJoining.swift:258`). The tags also reach the physics, so the stray bodies get the other layer's weight and air.

### F3. The crowd is never born into the current layer. Fault, confirmed.
**Where:** `ParticleEngine.swift:687` is the only place `currentLayer` is read when a body is made, and it is in `addParticle`. `Swarm.append` defaults `group: 0`, and no engine caller passes the current layer: arrangements, emitters, morph, recipe, `spawnBatch`. `spawn` takes no group at all.
```
F4 layer0=5000 layer1=0     (add layer "Storm", which becomes current, then add 5,000 bodies)
```
The crowd is what hiding by reordering was built for, yet the only ways to get crowd bodies onto another layer are to move a whole layer's contents, merge, or copy. The author's tests never catch this, because their `addCrowd` helper (`ParticleLayerTests.swift:21-26`) passes `group: UInt8(engine.currentLayer)` by hand.

### F4. Locked layers can still be frozen, and pushed by a second finger. Fault, confirmed.
**Where:** freeze: `Swarm.swift:1255` (flat) and `:1477` (depth) stop every crowd body in reach with no layer check. Extra fingers: `ParticleStep.swift:805` calls `swarm.applyBrush(...)` without `lockedLayers:`. The 3D step passes it.
```
F5 locked body speed after freeze = 0.0             (was 3; the lock should have kept it out of reach)
F6 locked layer fastest speed = 10.2                (main finger in a far corner, second finger on the locked crowd)
```
The `layerAllowsTouching` doc says it is "read by every tool … so a tool added later is locked out without anybody having to remember". Two tools already forget, and the crowd's passes do not read it at all. The kaleidoscope's copies go through the same unguarded call, so a kaleidoscope pushes locked layers too.

### F5. A recipe's sliders keep reshaping the field after the recipe is gone. Fault, confirmed.
**Where:** `ParticleRecipeBox.swift:415/451` set `storedRecipe`. Nothing clears it: `clear()` (`ParticleEngine.swift:554`), `beginScene`, undo and load all leave it. The app's `turnRecipeKnob` (`ParticleFieldModel.swift`, "Shapes described by formula") only checks `engine.recipe?.title == recipeDraft.title`.

Make a Rose, then start a morph. The tray still shows Rose's sliders and the "shove it and it pulls itself back together" text. Moving "Petals" rewrites the morph's targets into a rose:
```
F7  recipe after morph = Rose ; turn accepted=true ; morph homes changed=true
F7b after undo: crowd=5000 recipe=Rose
```
Any held scene (arrangements, text, morph) is bent into the old recipe's shape the moment the slider is touched.

### F6. "The crowd's order carries no meaning" is false: the morph and recipe targets go by position. Fault, confirmed.
**Where:** the premise is stated at `ParticleLayers.swift` (header) and `Swarm.swift:877`. `ParticleMorph.swift:168` `settleMorph` writes `storedMorphA[i]/storedMorphB[i]` into crowd slot `i`, and `turnRecipeKnob` writes `places[i]` into slot `i`. Both were laid out in spawn order, and restacking breaks that order.

The morph pairs each body with a nearby target on purpose (`sortedRoundTheMiddle`). Hiding and then re-showing a layer once is enough to break the pairing:
```
F8 mean walk to morph target: untouched=72.1 px, after hide+show=96.5 px   (+34%)
```
On screen the morph's slider sends bodies criss-crossing, and a recipe's along-the-line colouring gets scrambled against the shape. The same applies to anything else that keeps a per-slot list next to the crowd. `previousSwarmPositions` is safe only because it is re-recorded at the start of every step.

### F7. Merging or moving bodies onto a coloured layer leaves them in their old colour. Fault, confirmed.
**Where:** `ParticleLayers.swift:276` `mergeLayer` and `:306` `moveLayerContents` call `applyLayerTints()`, which only repaints layers whose colour changed (`:468`). The receiving layer's colour did not change, so nothing is repainted.
```
F13 group=1 colour unchanged=true      (blue layer merged into red layer; bodies stay blue)
```

### F8. A layer's colour reaches only the bodies that were on it at the first repaint. Fault, confirmed.
**Where:** the same "only when the colour changed" rule. The app's Add always gives a new layer a colour (`ParticleFieldModel.addLayer`). `engine.addLayer` does not paint. The first hide, lock or slider change paints whatever is on the layer at that moment, and bodies added after that are never painted:
```
F15 first=ffff6543 second=fff27b5a            (two bodies born the same colour on the same blue layer; only the first turned blue)
    with an explicitly red second body: second=ff1414fa after hide/show/lock — still red on the blue layer
```
The fix for colours darkening over time (commit text, third fault) swapped one wrong look for another. A body's layer colour depends on when it arrived, not on which layer it is on.

### F9. The engine accepts shape words in a force. Risk, confirmed.
**Where:** the "other direction" check exists only in the app (`ParticleFieldModel.setWrittenForce`). `ParticleSerialization.swift:526` (load), the public `writtenForceAcross/Down` setters and anything else that sets a force skip it:
```
F10 loaded force = 'sin(u * 4) * 3'      (a saved/shared world carrying this runs as a silent force of nothing)
```
The commit says the check goes "in both directions" and blames silence for "the fault this port keeps finding". The engine is still silent here, and the test meant to cover it (`theCheckGoesBothWays`) only does set arithmetic.

### F10. The code that should leave out unusable recipe values never runs. Fault, confirmed.
**Where:** `ParticleRecipeBox.swift:504` `guard x.isFinite, y.isFinite else { continue }`. `ParticleForceExpression.value(for:)` already replaces every non-finite number with 0 in `push`, and returns 0 for division by zero and for the square root of a negative number. The guard can never fire, so the "stripe of bodies … that reads as part of the shape" that its comment promises to prevent happens every time:
```
F11 placed=1000 of 1000, largest number sharing one x=500     (across: "sqrt(u - 0.5)")
```
The test that claims to cover this (`ParticleRecipeBoxTests.swift:196`) lays out a plain circle with no unusable values, so it passes without testing anything. Huge but finite values also get through: the fitting then scales the whole shape down to a dot next to a single far-away body. That is the user's own formula, but nothing warns about it.

### F11. Hidden cloth still shows its springs. Fault, confirmed by reading the code.
**Where:** `ParticleFieldModel.swift:1529` draws every spring. Only body sizes are set to 0 for hidden layers. A hidden cloth or rope therefore stays on screen as a web of lines with no bodies. `fieldPicture` does not draw springs, so the engine's picture test cannot see this. The app code does not build on this machine, so there is no running proof; the trace above is the evidence.

### F12. Duplicating a layer drops springs, and duplicates empty layers. Risk, confirmed.
**Where:** `ParticleLayers.swift:210-268`. Named bodies are copied with `addCopy` but no springs, jellies or labels come with them. The doc says it returns "nothing if there was … no bodies to copy", but `:268` returns `made` regardless. The app's "or nothing on that one to copy" message can therefore never appear, and an empty "X copy" layer is created.
```
F14 bodies=4 springs before=1 after=1
F16 duplicate of empty layer -> Optional(2), layers=3
```

## Checked and not a fault
- The per-body lists stay together through a swap. `Swarm.exchange` moves every per-body list, including sleep state, rest places, homes, depths, sizes, roles and tags. Removing a body and restoring from a snapshot handle tags consistently. Springs are not affected, because crowd bodies have none and named bodies are never reordered.
- Deleting a middle layer did not repaint the layers after it for the colours I tried (scratch test "F12" passed). The colour-memory shift is still there in the code, but I could not make it visible.
- Drawing a frame (`shownSwarmCount` is a getter that reorders the crowd) did not change the physics in my collision test (0 of 482 coordinates differed). Still a smell: a read-only question that changes the simulation's order is a replay and shared-room hazard, but I could not prove divergence.
- No clocks, unseeded random numbers, or set/dictionary iteration in the physics was added. `variablesUsed` returns a Set, but both callers sort it before use.
- Nothing in the new app code looks like a Swift 6 concurrency violation. The layer count per row scans the crowd, but only when the engine revision changes, not every frame.

## Suspicions, not proven
- Saved crowd tags are limited to fewer than 8, not to the number of layers in the file (`Swarm.restore`). A file with 3 layers and a crowd tag of 5 loads bodies that no layer counts, that are always shown and can always be touched. The author's "strange file" test only uses tag 40.
- `Swarm.remove(at:)` does not lower `sleepingCount` when it removes a sleeping body, so emptying a layer of sleeping bodies may leave the "saving" readout too high.

</details>

<details><summary>Files</summary>

- `Particle/ParticleLayers.swift`: new. Layer model, layer actions, restacking, tinting.
- `Particle/Swarm.swift`: `groups` list, `exchange`, `remove(at:)`, per-layer weight and air in both steps, lock table in the brush.
- `Particle/ParticleStep.swift`, `ParticleStepDepth.swift`: pass layer tables, check locks for named bodies, restack after each step.
- `Particle/ParticleSerialization.swift`: save and load the layers and tags.
- `Particle/ParticleEngine.swift`, `ParticleModel.swift`, `ParticleBrush.swift`, `ParticleFingerRay.swift`, `ParticleFieldPicture.swift`: storage, `addCopy`, lock parameter, picture leaves out hidden layers.
- `Particle/ParticleRecipeBox.swift`: new. Recipes, layout, knob turning.
- `Particle/ParticleForceExpression.swift`: `u v a b c`, `variablesUsed`, the two word sets.
- `App/Simulation/ParticleFieldModel.swift`, `App/Views/FieldDock.swift`, `App/Metal/FieldShaders.metal`: tray controls, hidden named bodies drawn at size 0, the force-side word check.
- Tests: `ParticleLayerTests.swift`, `ParticleRecipeBoxTests.swift`. Full diff: `git show afa9f4c 71bbedc`.

</details>

## For the handover note, "Found by chat two" (added there)

- Undo brings back a layer's bodies but not the layer itself, so after undoing a delete the bodies belong to the wrong layer, and after undoing a colour the layer still says it is that colour.
- Adding a big batch of bodies, or starting a new scene, can give some of them the layer of bodies that were removed earlier. If that layer is hidden, part of the new scene is invisible. The crowd is also never put on the chosen layer.
- A locked layer can still be frozen by the finger, and pushed by a second finger or by the kaleidoscope.
- After making a shape recipe and then choosing another scene, the recipe's sliders still show, and moving one bends the new scene into the old shape.
- Hiding a layer shuffles which body goes where in a morph or a recipe, so the bodies criss-cross.
- Bodies moved onto a coloured layer, or added to it after its first use, do not take its colour.
- A hidden cloth still shows its springs as lines.
- A saved world can carry a force written in a shape's words, and it loads as a force that does nothing, with no message.

**Verdict: NEEDS_CHANGES.** Layers break under undo, clearing and batch spawning, locks leak, and recipes outlive their scene (9 faults and 2 risks proven by failing tests, 1 fault by reading the code).
