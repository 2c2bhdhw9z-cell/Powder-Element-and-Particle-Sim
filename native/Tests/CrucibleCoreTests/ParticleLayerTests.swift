import Foundation
import Testing

@testable import CrucibleCore

/// Several worlds in one world.
///
/// The feature is small to describe and easy to get subtly wrong, and every one of the ways it can go wrong is the kind
/// that looks fine: bodies that follow the wrong layer's colour after one is deleted, a hidden layer that is still
/// there when the world is saved, a locked layer that a second finger can still move, a layer tag that follows the
/// wrong body after something dies. Those are what these are for.
@Suite("Several worlds in one world")
struct ParticleLayerTests {
    private func field() -> ParticleEngine {
        let engine = ParticleEngine(width: 300, height: 300, seed: 21)
        engine.clear()
        return engine
    }

    /// Puts some crowd bodies in the current layer.
    private func addCrowd(_ engine: ParticleEngine, _ count: Int, at y: Double = 150) {
        for i in 0 ..< count {
            _ = engine.swarm.append(
                x: 20 + Double(i), y: y, velocityX: 0, velocityY: 0,
                color: 0xFFFF_FFFF, budget: engine.maxParticles,
                group: UInt8(engine.currentLayer)
            )
        }
    }

    @Test("A world starts with one layer and nobody has to know about it")
    func oneToStartWith() {
        let engine = field()
        #expect(engine.layers.count == 1)
        #expect(engine.hasLayers == false)
        #expect(engine.currentLayer == 0)
        // Nothing is stored for it, which is what makes a world with no layers cost nothing.
        #expect(engine.storedLayers.isEmpty)
        #expect(engine.swarm.hasGroups == false)
    }

    @Test("Bodies are born into whichever layer is current")
    func bodiesJoinTheCurrentLayer() {
        let engine = field()
        _ = engine.addParticle(x: 10, y: 10)
        _ = engine.addLayer(named: "Storm")
        _ = engine.addParticle(x: 20, y: 20)
        #expect(engine.particles[0].group == 0)
        #expect(engine.particles[1].group == 1)
        #expect(engine.bodiesInLayer(0) == 1)
        #expect(engine.bodiesInLayer(1) == 1)
    }

    @Test("There is a limit, and it is refused rather than exceeded")
    func thereIsALimit() {
        let engine = field()
        for i in 1 ..< ParticleLayer.most {
            #expect(engine.addLayer(named: "Layer \(i)") == i)
        }
        #expect(engine.layers.count == ParticleLayer.most)
        #expect(engine.addLayer(named: "One too many") == nil)
        #expect(engine.layers.count == ParticleLayer.most)
    }

    @Test("A layer with its own weight falls differently")
    func weightChangesHowItFalls() {
        let engine = field()
        engine.gravityY = 0.5
        engine.collisionsEnabled = false
        addCrowd(engine, 20, at: 50)
        _ = engine.addLayer(named: "Light")
        var light = engine.layers[1]
        light.weight = 0
        _ = engine.setLayer(1, to: light)
        addCrowd(engine, 20, at: 50)

        for _ in 0 ..< 120 { engine.step() }
        // The first twenty fell; the second twenty, which gravity does not pull on, did not.
        let heavy = Double(engine.swarm.positions[1])
        let floating = Double(engine.swarm.positions[(20 * 2) + 1])
        #expect(heavy > 80, "the ordinary layer did not fall")
        #expect(abs(floating - 50) < 1, "a weightless layer fell anyway: \(floating)")
    }

    @Test("A layer with thinner air keeps more of its speed")
    func thinnessChangesHowItSettles() {
        let engine = field()
        engine.gravityY = 0
        engine.damping = 0.9
        engine.collisionsEnabled = false
        addCrowd(engine, 10, at: 100)
        _ = engine.addLayer(named: "Thin")
        var thin = engine.layers[1]
        thin.thinness = 1.1
        _ = engine.setLayer(1, to: thin)
        addCrowd(engine, 10, at: 200)
        // Both sets given the same shove.
        for index in 0 ..< engine.swarm.count { engine.swarm.velocities[index * 2] = 10 }

        for _ in 0 ..< 30 { engine.step() }
        let thickAir = abs(Double(engine.swarm.velocities[0]))
        let thinAir = abs(Double(engine.swarm.velocities[10 * 2]))
        #expect(thinAir > thickAir, "a thinner layer settled as fast as the thick one")
    }

    @Test("A world whose layers are only named costs nothing in the step")
    func namesAloneAreFree() {
        // The claim worth holding: organising a world does not slow it down. The step reads a body's layer only when
        // some layer asks for different rules, and this is how that is stated.
        let engine = field()
        _ = engine.addLayer(named: "Just a name")
        #expect(engine.anyLayerChangesPhysics == false)
        #expect(engine.layerWeightTable.isEmpty)
        #expect(engine.layerThinnessTable.isEmpty)
        #expect(engine.anyLayerLocked == false)
        #expect(engine.lockedLayerTable.isEmpty)

        var changed = engine.layers[1]
        changed.weight = 0.5
        _ = engine.setLayer(1, to: changed)
        #expect(engine.anyLayerChangesPhysics)
        #expect(engine.layerWeightTable.count == ParticleLayer.most)
        #expect(engine.layerWeightTable[1] == 0.5)
    }

    @Test("A locked layer cannot be pushed by a finger")
    func lockedLayersAreOutOfReach() {
        let engine = field()
        engine.gravityY = 0
        engine.damping = 1
        engine.collisionsEnabled = false
        addCrowd(engine, 8, at: 150)
        _ = engine.addLayer(named: "Locked")
        addCrowd(engine, 8, at: 150)
        _ = engine.lockLayer(1, true)

        engine.mouseMode = .repel
        engine.mouseRadius = 400
        for _ in 0 ..< 20 { engine.step(mouseX: 150, mouseY: 150, mouseActive: true) }

        let free = abs(Double(engine.swarm.velocities[0]))
        // After restacking, the locked bodies may have moved in the list, so they are found by their layer.
        var lockedSpeed = 0.0
        for index in 0 ..< engine.swarm.count where engine.swarm.groups[index] == 1 {
            lockedSpeed = max(lockedSpeed, abs(Double(engine.swarm.velocities[index * 2])))
        }
        #expect(free > 0.01, "the unlocked layer was not pushed either, so this proves nothing")
        #expect(lockedSpeed == 0, "a locked layer was pushed anyway")

        // And unlocking lets it move again.
        _ = engine.lockLayer(1, false)
        for _ in 0 ..< 20 { engine.step(mouseX: 150, mouseY: 150, mouseActive: true) }
        var afterwards = 0.0
        for index in 0 ..< engine.swarm.count where engine.swarm.groups[index] == 1 {
            afterwards = max(afterwards, abs(Double(engine.swarm.velocities[index * 2])))
        }
        #expect(afterwards > 0, "unlocking did not put the layer back in reach")
    }

    @Test("A locked layer still runs — locking is not freezing")
    func lockingIsNotFreezing() {
        let engine = field()
        engine.gravityY = 0.5
        engine.collisionsEnabled = false
        _ = engine.addLayer(named: "Locked")
        addCrowd(engine, 10, at: 40)
        _ = engine.lockLayer(1, true)
        for _ in 0 ..< 60 { engine.step() }
        var lowest = 0.0
        for index in 0 ..< engine.swarm.count where engine.swarm.groups[index] == 1 {
            lowest = max(lowest, Double(engine.swarm.positions[index * 2 + 1]))
        }
        #expect(lowest > 60, "a locked layer stopped running, which is not what locking means")
    }

    @Test("Hiding a layer means fewer bodies are drawn, not dimmer ones")
    func hidingMovesRatherThanDims() {
        let engine = field()
        addCrowd(engine, 30)
        _ = engine.addLayer(named: "Hidden")
        addCrowd(engine, 20)
        #expect(engine.shownSwarmCount == 50)
        let coloursBefore = (0 ..< engine.swarm.count).map { engine.swarm.colors[$0] }

        _ = engine.showLayer(1, false)
        #expect(engine.shownSwarmCount == 30, "hiding a layer did not reduce what is drawn")
        // Every body drawn is from a shown layer.
        for index in 0 ..< engine.shownSwarmCount {
            #expect(engine.swarm.groups[index] == 0, "a hidden body was among the ones drawn")
        }
        // And the colours were not touched, which is the whole reason for moving them instead.
        let coloursAfter = (0 ..< engine.swarm.count).map { engine.swarm.colors[$0] }
        #expect(coloursAfter.sorted() == coloursBefore.sorted(), "hiding a layer rewrote colours")
        // Nothing was lost.
        #expect(engine.swarm.count == 50)

        _ = engine.showLayer(1, true)
        #expect(engine.shownSwarmCount == 50)
    }

    @Test("A hidden layer stays hidden after bodies die")
    func hidingSurvivesRemoval() {
        // The fault this is for: removing a body swaps the last one into the gap, and the last one may be hidden — so
        // a body from a hidden layer walks back into the part of the crowd that gets drawn.
        let engine = field()
        for i in 0 ..< 30 {
            _ = engine.swarm.append(
                x: 20 + Double(i), y: 100, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF,
                budget: engine.maxParticles, life: i < 10 ? 3 : -1, group: 0
            )
        }
        _ = engine.addLayer(named: "Hidden")
        addCrowd(engine, 20, at: 200)
        _ = engine.showLayer(1, false)
        #expect(engine.shownSwarmCount == 30)

        for _ in 0 ..< 10 { engine.step() }
        #expect(engine.swarm.count == 40, "the short-lived bodies did not go")
        #expect(engine.shownSwarmCount == 20, "the count of drawn bodies is wrong after some died")
        for index in 0 ..< engine.shownSwarmCount {
            #expect(engine.swarm.groups[index] == 0, "a hidden body came back among the drawn after a removal")
        }
    }

    @Test("A tag follows its own body when the crowd is reordered")
    func tagsFollowTheirBodies() {
        // Swapping bodies about means touching a dozen parallel lists, and missing one gives a body somebody else's
        // colour, weight or layer. Checked by giving every body a colour that says which layer it is on.
        let engine = field()
        for layer in 0 ..< 3 {
            if layer > 0 { _ = engine.addLayer(named: "Layer \(layer)") }
            for _ in 0 ..< 12 {
                _ = engine.swarm.append(
                    x: 50, y: 50, velocityX: Double(layer), velocityY: 0,
                    color: UInt32(layer) + 1, budget: engine.maxParticles,
                    mass: Double(layer) + 1, size: Double(layer) + 3,
                    group: UInt8(layer)
                )
            }
        }
        _ = engine.showLayer(1, false)
        for index in 0 ..< engine.swarm.count {
            let layer = engine.swarm.groups[index]
            #expect(engine.swarm.colors[index] == UInt32(layer) + 1, "a colour ended up on the wrong body")
            #expect(engine.swarm.masses[index] == Float(layer) + 1, "a weight ended up on the wrong body")
            #expect(engine.swarm.sizes[index] == Float(layer) + 3, "a size ended up on the wrong body")
            #expect(engine.swarm.velocities[index * 2] == Float(layer), "a speed ended up on the wrong body")
        }
    }

    @Test("Emptying a layer removes its bodies and leaves everything else")
    func emptyingLeavesTheRest() {
        let engine = field()
        addCrowd(engine, 15)
        _ = engine.addParticle(x: 10, y: 10)
        _ = engine.addLayer(named: "Second")
        addCrowd(engine, 25)
        _ = engine.addParticle(x: 20, y: 20)

        let removed = engine.emptyLayer(1)
        #expect(removed == 26)
        #expect(engine.swarm.count == 15)
        #expect(engine.particles.count == 1)
        #expect(engine.layers.count == 2, "emptying a layer removed the layer as well")
        #expect(engine.bodiesInLayer(1) == 0)
        #expect(engine.bodiesInLayer(0) == 16)
    }

    @Test("Duplicating a layer copies its bodies into a new one")
    func duplicatingCopies() {
        let engine = field()
        addCrowd(engine, 12)
        _ = engine.addParticle(x: 30, y: 40, radius: 5)
        var first = engine.layers[0]
        first.weight = 0.25
        _ = engine.setLayer(0, to: first)

        let made = engine.duplicateLayer(0)
        #expect(made == 1)
        #expect(engine.swarm.count == 24)
        #expect(engine.particles.count == 2)
        #expect(engine.bodiesInLayer(0) == 13)
        #expect(engine.bodiesInLayer(1) == 13)
        // The copy behaves like what it was copied from.
        #expect(engine.layers[1].weight == 0.25)
        // And the copied named body is its own body, not the same one twice.
        #expect(engine.particles[0].id != engine.particles[1].id)
        #expect(engine.particles[1].radius == engine.particles[0].radius)
    }

    @Test("Merging pours one layer into another and takes the empty one away")
    func mergingPoursAndRemoves() {
        let engine = field()
        addCrowd(engine, 10)
        _ = engine.addLayer(named: "Second")
        addCrowd(engine, 14)
        _ = engine.addLayer(named: "Third")
        addCrowd(engine, 6)

        #expect(engine.mergeLayer(1, into: 0))
        #expect(engine.layers.count == 2)
        #expect(engine.layers[1].name == "Third", "the wrong layer was renumbered after a merge")
        #expect(engine.bodiesInLayer(0) == 24)
        #expect(engine.bodiesInLayer(1) == 6)
        #expect(engine.swarm.count == 30, "merging lost bodies")
    }

    @Test("Deleting a layer renumbers the ones after it, bodies and all")
    func deletingRenumbers() {
        // The fault this is about: take the middle layer away without renumbering and every body on the layers after
        // it silently belongs to a different layer — different colour, different rules, and nothing to point at.
        let engine = field()
        addCrowd(engine, 5)
        _ = engine.addLayer(named: "Doomed")
        addCrowd(engine, 7)
        _ = engine.addLayer(named: "Survivor")
        addCrowd(engine, 9)
        var survivor = engine.layers[2]
        survivor.weight = 2
        _ = engine.setLayer(2, to: survivor)

        #expect(engine.deleteLayer(1))
        #expect(engine.layers.count == 2)
        #expect(engine.layers[1].name == "Survivor")
        #expect(engine.layers[1].weight == 2, "the surviving layer's rules were lost")
        #expect(engine.swarm.count == 14, "the wrong bodies went")
        #expect(engine.bodiesInLayer(1) == 9)
        for index in 0 ..< engine.swarm.count {
            #expect(engine.swarm.groups[index] < 2, "a body was left pointing at a layer that no longer exists")
        }
    }

    @Test("The first layer cannot be deleted or merged away")
    func theFirstOneStays() {
        let engine = field()
        addCrowd(engine, 5)
        _ = engine.addLayer(named: "Second")
        #expect(engine.deleteLayer(0) == false)
        #expect(engine.mergeLayer(0, into: 1) == false)
        #expect(engine.layers.count == 2)
        // And nonsense is refused rather than acted on.
        #expect(engine.deleteLayer(9) == false)
        #expect(engine.mergeLayer(1, into: 1) == false)
        #expect(engine.mergeLayer(1, into: 9) == false)
    }

    @Test("Moving a layer's contents empties it without removing it")
    func contentsCanBeMoved() {
        let engine = field()
        addCrowd(engine, 8)
        _ = engine.addLayer(named: "Second")
        addCrowd(engine, 11)
        #expect(engine.moveLayerContents(1, to: 0) == 11)
        #expect(engine.layers.count == 2)
        #expect(engine.bodiesInLayer(0) == 19)
        #expect(engine.bodiesInLayer(1) == 0)
    }

    @Test("A layer's colour tints its bodies and keeps their brightness")
    func tintKeepsBrightness() {
        let engine = field()
        _ = engine.addLayer(named: "Red", tint: PackedColor(r: 200, g: 40, b: 40))
        // One bright body and one dim one, both white, so only the brightness distinguishes them.
        _ = engine.swarm.append(x: 10, y: 10, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF,
                                budget: engine.maxParticles, group: 1)
        _ = engine.swarm.append(x: 20, y: 20, velocityX: 0, velocityY: 0, color: 0xFF44_4444,
                                budget: engine.maxParticles, group: 1)
        engine.applyLayerTints()

        func brightness(_ colour: UInt32) -> Double {
            Double(colour & 0xFF) * 0.2126 + Double((colour >> 8) & 0xFF) * 0.7152
                + Double((colour >> 16) & 0xFF) * 0.0722
        }
        let bright = engine.swarm.colors[0]
        let dim = engine.swarm.colors[1]
        // Both took the hue: more red than blue, which white was not.
        #expect(bright & 0xFF > (bright >> 16) & 0xFF, "the tint did not take")
        #expect(dim & 0xFF > (dim >> 16) & 0xFF)
        // And the dim one is still the dim one, which a flat replacement would have lost.
        #expect(brightness(bright) > brightness(dim) * 2, "the tint flattened the layer into one colour")
    }

    @Test("Giving a layer a colour can be taken back")
    func tintingCanBeUndone() {
        // Colouring a layer writes into its bodies, so the colours they had are gone. Everything else a layer can do
        // is reversible by doing it again; this one needs keeping.
        let engine = field()
        _ = engine.addLayer(named: "Red")
        _ = engine.swarm.append(x: 10, y: 10, velocityX: 0, velocityY: 0, color: 0xFF00_FF00,
                                budget: engine.maxParticles, group: 1)
        let before = engine.swarm.colors[0]

        var red = engine.layers[1]
        red.tint = PackedColor(r: 220, g: 50, b: 50)
        _ = engine.setLayer(1, to: red)
        #expect(engine.swarm.colors[0] != before, "the colour did not take")

        engine.undo()
        #expect(engine.swarm.colors[0] == before, "colouring a layer could not be taken back")
    }

    @Test("Touching a layer's other settings does not darken its colour")
    func tintingDoesNotDrift() {
        // Measured rather than assumed. The tint keeps a body's brightness exactly in arithmetic, but the answer has to
        // be rounded into three bytes, and applying it again and again compounds that rounding until the layer is
        // visibly darker. So the colour is only ever written when it has actually changed, and this is the check.
        let engine = field()
        _ = engine.addLayer(named: "Blue", tint: PackedColor(r: 60, g: 90, b: 240))
        _ = engine.swarm.append(x: 10, y: 10, velocityX: 0, velocityY: 0, color: 0xFFCC_CCCC,
                                budget: engine.maxParticles, group: 1)
        engine.applyLayerTints()
        let once = engine.swarm.colors[0]
        #expect(once != 0xFFCC_CCCC, "the colour never took")
        for _ in 0 ..< 20 { engine.applyLayerTints() }
        #expect(engine.swarm.colors[0] == once, "a layer's colour drifted when nothing had changed")

        // And the things somebody actually does to a layer all the time leave its colours alone.
        for _ in 0 ..< 10 {
            _ = engine.showLayer(1, false)
            _ = engine.showLayer(1, true)
            _ = engine.lockLayer(1, true)
            _ = engine.lockLayer(1, false)
            engine.setLayerWeightForTest(1, 0.5)
        }
        #expect(engine.swarm.colors[0] == once, "using a layer's switches repainted it")

        // Changing the colour on purpose does change it.
        var other = engine.layers[1]
        other.tint = PackedColor(r: 240, g: 90, b: 60)
        _ = engine.setLayer(1, to: other)
        #expect(engine.swarm.colors[0] != once)
    }

    @Test("Layers survive being saved and loaded")
    func theySurviveASave() throws {
        let engine = field()
        addCrowd(engine, 12)
        _ = engine.addParticle(x: 40, y: 40)
        _ = engine.addLayer(named: "Storm", tint: PackedColor(r: 80, g: 120, b: 255))
        addCrowd(engine, 9)
        _ = engine.addParticle(x: 60, y: 60)
        var storm = engine.layers[1]
        storm.weight = -0.5
        storm.thinness = 1.2
        storm.locked = true
        storm.shown = false
        _ = engine.setLayer(1, to: storm)

        let written = try JSONEncoder().encode(engine.captureState())
        let read = try JSONDecoder().decode(ParticleState.self, from: written)
        let other = ParticleEngine(width: 300, height: 300, seed: 99)
        #expect(other.apply(read))

        #expect(other.layers.count == 2)
        #expect(other.layers[1].name == "Storm")
        #expect(other.layers[1].locked)
        #expect(other.layers[1].shown == false)
        #expect(other.layers[1].weight == -0.5)
        #expect(other.layers[1].thinness == 1.2)
        #expect(other.layers[1].tint?.r == 80)
        #expect(other.bodiesInLayer(1) == 10, "bodies came back on the wrong layer")
        #expect(other.bodiesInLayer(0) == 13)
        #expect(other.shownSwarmCount == 12, "a hidden layer came back shown")
    }

    @Test("A world with no layers writes nothing about them")
    func nothingIsWrittenWhenThereAreNone() throws {
        // Every field added to the save format since the first version is left out when it is not in use, because a
        // file is text and a list of defaults per body is megabytes of nothing.
        let engine = field()
        addCrowd(engine, 20)
        _ = engine.addParticle(x: 10, y: 10)
        let state = engine.captureState()
        #expect(state.layers == nil)
        #expect(state.layerAt == nil)
        #expect(state.swarm?.layer == nil)
        #expect(state.particles.allSatisfy { $0.layer == nil })
    }

    @Test("A file claiming more layers than this build has is not trusted")
    func aStrangeFileIsTamed() throws {
        let engine = field()
        addCrowd(engine, 6)
        _ = engine.addLayer(named: "Second")
        addCrowd(engine, 6)
        var state = engine.captureState()
        // As though written by a build with far more layers: bodies pointing at layer forty.
        state.swarm?.layer = [UInt8](repeating: 40, count: 12)
        state.particles = state.particles.map {
            var record = $0
            record.layer = 40
            return record
        }
        let other = ParticleEngine(width: 300, height: 300, seed: 5)
        #expect(other.apply(state))
        for index in 0 ..< other.swarm.count {
            #expect(other.swarm.groups[index] < UInt8(other.layers.count),
                    "a body was left on a layer that does not exist here")
        }
        #expect(other.particles.allSatisfy { $0.group < UInt8(other.layers.count) })
    }

    @Test("Absurd layer settings are pulled into range")
    func absurdSettingsAreSettled() {
        let layer = ParticleLayer(
            name: String(repeating: "n", count: 200), weight: .nan, thinness: 900).sanitized
        #expect(layer.name.count == 24)
        #expect(layer.weight == 1)
        #expect(layer.thinness == 1.5)
        #expect(ParticleLayer(name: "   ").sanitized.name == "Layer")
    }

    @Test("Bodies added while the world is paused are drawn straight away")
    func newBodiesAreDrawnAtOnce() {
        // The count of what to draw is worked out when something changes, not every frame. That leaves it able to go
        // stale: add bodies to a paused world and the count is from before they existed, so they would not be drawn
        // until the world was set running again. The crowd counts its own changes, which is what catches it.
        let engine = field()
        addCrowd(engine, 10)
        _ = engine.addLayer(named: "Hidden")
        addCrowd(engine, 10)
        _ = engine.showLayer(1, false)
        #expect(engine.shownSwarmCount == 10)

        engine.currentLayer = 0
        addCrowd(engine, 5, at: 250)
        #expect(engine.shownSwarmCount == 15, "bodies added without the world running were not drawn")

        // And the same going the other way: bodies taken away.
        engine.swarm.remove(at: 0)
        #expect(engine.shownSwarmCount == 14)
    }

    @Test("A hidden layer is left out of a picture of the field")
    func hiddenLayersAreNotInThePicture() {
        let engine = field()
        addCrowd(engine, 40, at: 60)
        _ = engine.addLayer(named: "Hidden")
        addCrowd(engine, 40, at: 240)

        let background = ParticleEngine.backgroundColor
        let whole = engine.fieldPicture().count { $0 != background }
        _ = engine.showLayer(1, false)
        let half = engine.fieldPicture().count { $0 != background }
        #expect(half > 0)
        #expect(half < whole / 2 + 10, "a hidden layer was still in the picture")

        // And the half that is left is the top one, which is where the shown layer is.
        let pixels = engine.fieldPicture()
        var lowest = 0
        for y in 0 ..< 300 {
            for x in 0 ..< 300 where pixels[y * 300 + x] != background { lowest = max(lowest, y) }
        }
        #expect(lowest < 150, "the wrong layer was left in the picture")
    }
}

extension ParticleEngine {
    /// Setting one layer's weight, for the check that using a layer's controls does not repaint it.
    ///
    /// The app has its own version of this on its model; this is the same three lines so the test does not need the app.
    fileprivate func setLayerWeightForTest(_ index: Int, _ weight: Double) {
        guard index >= 0, index < layers.count else { return }
        var layer = layers[index]
        layer.weight = weight
        _ = setLayer(index, to: layer)
    }
}
