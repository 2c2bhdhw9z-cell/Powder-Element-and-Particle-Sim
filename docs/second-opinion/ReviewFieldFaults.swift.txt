import Foundation
import Testing
@testable import CrucibleCore

// Throwaway proofs for the second opinion on afa9f4c (layers) and 71bbedc (recipes). Each test asserts the
// behaviour the commit/comments CLAIM; a failure is the evidence of a fault.
@Suite("Review field faults")
struct ReviewFieldFaults {
    private func field() -> ParticleEngine {
        let engine = ParticleEngine(width: 300, height: 300, seed: 21)
        engine.clear()
        engine.clearHistory()
        return engine
    }

    private func crowd(_ engine: ParticleEngine, _ count: Int, group: UInt8, y: Double = 150) {
        for i in 0 ..< count {
            _ = engine.swarm.append(x: 20 + Double(i) * 3, y: y, velocityX: 0, velocityY: 0,
                                    color: 0xFFFF_FFFF, budget: engine.maxParticles, group: group)
        }
    }

    // F1 — undo does not restore the layer list, so undoing a delete leaves bodies on the wrong layer.
    @Test("F1 undo of deleteLayer restores the layer and its bodies consistently")
    func undoDelete() {
        let engine = field()
        _ = engine.addLayer(named: "A")
        crowd(engine, 5, group: 1)
        _ = engine.addLayer(named: "B")
        crowd(engine, 7, group: 2)
        _ = engine.deleteLayer(1)
        #expect(engine.layers.count == 2)
        engine.undo()
        print("F1 after undo: layers=\(engine.layers.map(\.name)) inLayer1=\(engine.bodiesInLayer(1)) crowd=\(engine.swarm.count)")
        #expect(engine.layers.count == 3, "undo brought the bodies back but not layer A")
        #expect(engine.bodiesInLayer(1) == 5, "A's bodies are now counted as B's")
    }

    // F2 — undo of a tint restores colours but not the layer's tint, and the tint cache goes stale.
    @Test("F2 undo of a tint, then tinting again, tints again")
    func undoTint() {
        let engine = field()
        _ = engine.addLayer(named: "Red")
        crowd(engine, 1, group: 1)
        let before = engine.swarm.colors[0]
        var red = engine.layers[1]
        red.tint = PackedColor(r: 220, g: 50, b: 50)
        _ = engine.setLayer(1, to: red)
        let tinted = engine.swarm.colors[0]
        engine.undo()
        print("F2 after undo: colour restored=\(engine.swarm.colors[0] == before) layer tint still=\(String(describing: engine.layers[1].tint))")
        #expect(engine.layers[1].tint == nil, "the layer still claims to be red while its bodies are not")
        // Tint it again: user picks red once more.
        var again = engine.layers[1]
        again.tint = nil
        _ = engine.setLayer(1, to: again)
        again.tint = PackedColor(r: 220, g: 50, b: 50)
        _ = engine.setLayer(1, to: again)
        print("F2 re-tint took=\(engine.swarm.colors[0] == tinted)")
        #expect(engine.swarm.colors[0] == tinted, "choosing the same colour again did nothing")
    }

    // F3 — Swarm.spawn never writes groups[], and removeAll never clears hasGroups: new bodies inherit stale tags.
    @Test("F3 a crowd spawned after clearing is not born into an old hidden layer")
    func staleGroupsAfterClear() {
        let engine = field()
        _ = engine.addLayer(named: "Hidden")
        crowd(engine, 10, group: 1)
        _ = engine.showLayer(1, false)
        engine.clear()
        engine.spawnBatch(count: 5_000)
        var tagged = 0
        for i in 0 ..< engine.swarm.count where engine.swarm.groups[i] == 1 { tagged += 1 }
        print("F3 spawned=\(engine.swarm.count) shown=\(engine.shownSwarmCount) tagged-hidden=\(tagged)")
        #expect(engine.shownSwarmCount == engine.swarm.count, "freshly spawned bodies are invisible")
    }

    @Test("F3b emptying a layer then spawning")
    func staleGroupsAfterEmpty() {
        let engine = field()
        crowd(engine, 5, group: 0)
        _ = engine.addLayer(named: "Two")
        crowd(engine, 10, group: 1)
        _ = engine.emptyLayer(1)
        engine.currentLayer = 0
        engine.spawnBatch(count: 5_000)
        print("F3b layer0=\(engine.bodiesInLayer(0)) layer1=\(engine.bodiesInLayer(1))")
        #expect(engine.bodiesInLayer(1) == 0, "bodies spawned into layer 0 turned up in layer 1")
    }

    // F4 — "Bodies are born into whichever layer is current" is only true of named bodies, not the crowd.
    @Test("F4 a crowd batch is born into the current layer")
    func crowdIgnoresCurrentLayer() {
        let engine = field()
        _ = engine.addLayer(named: "Storm")
        #expect(engine.currentLayer == 1)
        engine.spawnBatch(count: 5_000)
        print("F4 layer0=\(engine.bodiesInLayer(0)) layer1=\(engine.bodiesInLayer(1))")
        #expect(engine.bodiesInLayer(1) == 5_000, "the crowd went into layer 0 regardless")
    }

    // F5 — the freeze tool ignores locks (the step's freeze stage has no layer check).
    @Test("F5 freeze does not stop a locked layer")
    func freezeIgnoresLock() {
        let engine = field()
        engine.gravityY = 0
        engine.damping = 1
        engine.collisionsEnabled = false
        _ = engine.addLayer(named: "Locked")
        for i in 0 ..< 8 {
            _ = engine.swarm.append(x: 140 + Double(i), y: 150, velocityX: 3, velocityY: 0,
                                    color: 0xFFFF_FFFF, budget: engine.maxParticles, group: 1)
        }
        _ = engine.lockLayer(1, true)
        engine.mouseMode = .freeze
        engine.mouseRadius = 400
        engine.step(mouseX: 150, mouseY: 150, mouseActive: true)
        let speed = abs(Double(engine.swarm.velocities[0]))
        print("F5 locked body speed after freeze = \(speed)")
        #expect(speed > 2, "a locked layer was frozen by the finger")
    }

    // F6 — in the flat step, the extra fingers / kaleidoscope copies call applyBrush without the lock table.
    @Test("F6 a second finger cannot push a locked layer")
    func extraFingerIgnoresLock() {
        let engine = field()
        engine.gravityY = 0
        engine.damping = 1
        engine.collisionsEnabled = false
        _ = engine.addLayer(named: "Locked")
        crowd(engine, 8, group: 1, y: 150)
        _ = engine.lockLayer(1, true)
        engine.mouseMode = .repel
        engine.mouseRadius = 60
        engine.extraFingers = [ParticleFingerPoint(x: 30, y: 150)]
        // Primary finger far away in a corner, extra finger on the crowd.
        for _ in 0 ..< 10 { engine.step(mouseX: 290, mouseY: 10, mouseActive: true) }
        var fastest = 0.0
        for i in 0 ..< engine.swarm.count { fastest = max(fastest, abs(Double(engine.swarm.velocities[i * 2]))) }
        print("F6 locked layer fastest speed = \(fastest)")
        #expect(fastest == 0, "a second finger pushed a locked layer")
    }

    // F7 — storedRecipe survives clear()/other scenes, so a recipe knob reshapes whatever is in the field now.
    @Test("F7 turning a rose knob after switching to a morph does not touch the morph")
    func recipeOutlivesItsScene() {
        let engine = field()
        _ = engine.spawnRecipe(ParticleRecipe.named("Rose")!)
        #expect(engine.spawnMorph(from: "sunflower", to: "ring"))
        print("F7 recipe after morph = \(engine.recipe?.title ?? "nil")")
        let homesBefore = (0 ..< min(200, engine.swarm.count)).map { engine.swarm.homes[$0 * Swarm.homeStride] }
        let turned = engine.turnRecipeKnob("b", to: 9)
        let homesAfter = (0 ..< min(200, engine.swarm.count)).map { engine.swarm.homes[$0 * Swarm.homeStride] }
        print("F7 turn accepted=\(turned) morph homes changed=\(homesBefore != homesAfter)")
        #expect(engine.recipe == nil, "the rose was still remembered after another scene replaced it")
        #expect(homesBefore == homesAfter, "a rose slider rewrote the morph's homes")
    }

    @Test("F7b undo of a recipe forgets the recipe")
    func recipeSurvivesUndo() {
        let engine = field()
        engine.spawnSwarmScene(count: 5_000)
        _ = engine.spawnRecipe(ParticleRecipe.named("Rose")!)
        engine.undo()
        print("F7b after undo: crowd=\(engine.swarm.count) recipe=\(engine.recipe?.title ?? "nil")")
        #expect(engine.recipe == nil)
    }

    // F8 — the order-carries-no-meaning claim is false for the morph: its targets are by index.
    @Test("F8 hiding a layer does not scramble which body goes where in a morph")
    func morphOrderMatters() {
        func travel(hide: Bool) -> Double {
            let engine = ParticleEngine(width: 300, height: 300, seed: 3)
            #expect(engine.spawnMorph(from: "sunflower", to: "ring"))
            _ = engine.addLayer(named: "Odd")
            for i in stride(from: 1, to: engine.swarm.count, by: 2) { engine.swarm.setGroup(1, at: i) }
            if hide { _ = engine.showLayer(1, false); _ = engine.showLayer(1, true) }
            let n = engine.swarm.count
            let startX = (0 ..< n).map { Double(engine.swarm.homes[$0 * Swarm.homeStride]) }
            let startY = (0 ..< n).map { Double(engine.swarm.homes[$0 * Swarm.homeStride + 1]) }
            engine.morphAt = 1
            var total = 0.0
            for i in 0 ..< n {
                let dx = Double(engine.swarm.homes[i * Swarm.homeStride]) - startX[i]
                let dy = Double(engine.swarm.homes[i * Swarm.homeStride + 1]) - startY[i]
                total += (dx * dx + dy * dy).squareRoot()
            }
            return total / Double(n)
        }
        let plain = travel(hide: false)
        let hidden = travel(hide: true)
        print("F8 mean walk to morph target: untouched=\(plain) after hide+show=\(hidden)")
        #expect(hidden < plain * 1.2, "after hiding and showing a layer, bodies walk to other bodies' targets")
    }

    // F9 — drawing (a getter) reorders the crowd; whether a frame was drawn changes the physics.
    @Test("F9 asking how many bodies to draw does not change what happens next")
    func renderQueryChangesPhysics() {
        func run(queryBetween: Bool) -> [Float] {
            let engine = ParticleEngine(width: 300, height: 300, seed: 7)
            engine.clear()
            engine.gravityY = 0.3
            engine.collisionsEnabled = true
            _ = engine.addLayer(named: "Hidden")
            for i in 0 ..< 200 {
                _ = engine.swarm.append(x: 100 + Double(i % 20) * 4, y: 60 + Double(i / 20) * 4,
                                        velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF,
                                        budget: engine.maxParticles, group: UInt8(i % 2))
            }
            _ = engine.showLayer(1, false)
            for _ in 0 ..< 5 { engine.step() }
            // Something added between moments (a paint stroke while paused, a scene piece).
            for i in 0 ..< 40 {
                _ = engine.swarm.append(x: 120 + Double(i % 10) * 4, y: 40 + Double(i / 10) * 4,
                                        velocityX: 0, velocityY: 1, color: 0xFFFF_FFFF,
                                        budget: engine.maxParticles, group: 1)
            }
            _ = engine.swarm.append(x: 110, y: 50, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF,
                                    budget: engine.maxParticles, group: 0)
            if queryBetween { _ = engine.shownSwarmCount }   // what one drawn frame does
            for _ in 0 ..< 120 { engine.step() }
            var all: [Float] = []
            for i in 0 ..< engine.swarm.count {
                all.append(engine.swarm.positions[i * 2]); all.append(engine.swarm.positions[i * 2 + 1])
            }
            return all.sorted()
        }
        let a = run(queryBetween: false)
        let b = run(queryBetween: true)
        var differ = 0
        for i in 0 ..< min(a.count, b.count) where a[i] != b[i] { differ += 1 }
        print("F9 coordinates that differ between drawn and not-drawn runs: \(differ) of \(a.count)")
        #expect(differ == 0, "a frame being drawn changed the simulation")
    }

    // F10 — the engine accepts recipe-only words in a force (check lives only in the app), incl. on load.
    @Test("F10 the engine refuses a force written in a shape's words")
    func engineAcceptsUInForce() throws {
        let engine = field()
        var state = engine.captureState()
        state.writtenForceAcross = "sin(u * 4) * 3"
        let other = ParticleEngine(width: 300, height: 300, seed: 1)
        #expect(other.apply(state))
        print("F10 loaded force = '\(other.writtenForceAcross.source)'")
        #expect(other.writtenForceAcross.isEmpty, "a saved force in u was loaded as a silent force of nothing")
    }

    // F11 — non-finite formula output is never left out: the compiler already turned it into nought.
    @Test("F11 bodies whose formula is nonsense are left out, not stacked on one line")
    func nonsenseIsStackedNotLeftOut() {
        let engine = field()
        let recipe = ParticleRecipe(title: "Half", across: "sqrt(u - 0.5)", down: "u", count: 1_000)
        let placed = (try? engine.spawnRecipe(recipe).get()) ?? -1
        var xs: [Float: Int] = [:]
        for i in 0 ..< engine.swarm.count { xs[engine.swarm.positions[i * 2], default: 0] += 1 }
        let biggestStack = xs.values.max() ?? 0
        print("F11 placed=\(placed) of 1000, largest number sharing one x=\(biggestStack)")
        #expect(biggestStack < 10, "half the bodies are a single vertical stripe")
    }

    // F12 — deleting a layer shifts the tint cache, so later layers get repainted.
    @Test("F12 deleting a layer does not repaint the layers after it")
    func deleteRepaints() {
        let engine = field()
        _ = engine.addLayer(named: "Red", tint: PackedColor(r: 220, g: 40, b: 40))
        crowd(engine, 3, group: 1)
        _ = engine.addLayer(named: "Blue", tint: PackedColor(r: 40, g: 60, b: 230))
        crowd(engine, 3, group: 2)
        engine.applyLayerTints()
        var blue: [UInt32] = []
        for i in 0 ..< engine.swarm.count where engine.swarm.groups[i] == 2 { blue.append(engine.swarm.colors[i]) }
        _ = engine.deleteLayer(1)
        var after: [UInt32] = []
        for i in 0 ..< engine.swarm.count where engine.swarm.groups[i] == 1 { after.append(engine.swarm.colors[i]) }
        print("F12 blue before=\(blue.map { String($0, radix: 16) }) after=\(after.map { String($0, radix: 16) })")
        #expect(blue.sorted() == after.sorted(), "the blue layer was repainted when the red one was deleted")
    }

    // F13 — merging/moving leaves bodies in the colour of the layer they left.
    @Test("F13 bodies moved to a coloured layer take its colour")
    func moveKeepsOldTint() {
        let engine = field()
        _ = engine.addLayer(named: "Red", tint: PackedColor(r: 220, g: 40, b: 40))
        _ = engine.addLayer(named: "Blue", tint: PackedColor(r: 40, g: 60, b: 230))
        crowd(engine, 3, group: 2)
        engine.applyLayerTints()
        let blueColour = engine.swarm.colors[0]
        _ = engine.mergeLayer(2, into: 1)
        print("F13 group=\(engine.swarm.groups[0]) colour unchanged=\(engine.swarm.colors[0] == blueColour)")
        #expect(engine.swarm.colors[0] != blueColour, "a body on the red layer is still blue")
    }

    // F14 — duplicating a layer with a joined shape copies the bodies but not the springs.
    @Test("F14 duplicating a layer copies its springs")
    func duplicateDropsSprings() {
        let engine = field()
        _ = engine.addLayer(named: "Cloth")
        let a = engine.addParticle(x: 50, y: 50)
        let b = engine.addParticle(x: 60, y: 50)
        _ = (a, b)
        engine.springs.append(Spring(a: 0, b: 1, rest: 10, k: 0.2))
        let before = engine.springs.count
        _ = engine.duplicateLayer(1)
        print("F14 bodies=\(engine.particles.count) springs before=\(before) after=\(engine.springs.count)")
        #expect(engine.springs.count == before * 2, "the copy is loose bodies")
    }
}
