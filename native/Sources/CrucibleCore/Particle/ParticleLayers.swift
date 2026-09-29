// Several worlds in one world, each with its own name, colour and rules.
//
// ## What this is for
//
// Everything in the field has always been one undifferentiated crowd. That is fine while a world is one thing, and
// useless the moment somebody wants to build a world out of parts: a still globe with a storm orbiting it, a lattice
// with smoke drifting through it, a scene being built up while the last version is kept to compare against. Any of
// those means being able to say "this lot, not that lot" — and there was no way to say it.
//
// A layer is that: a name, a colour, whether it is shown, whether a finger may touch it, and two rules of its own —
// how hard gravity pulls on it and how much the air holds it back. Bodies are born into whichever layer is current.
// Layers can be hidden, locked, emptied, duplicated, merged and deleted.
//
// ## Why hiding moves bodies rather than dimming them
//
// The obvious way to hide a layer is to draw its bodies transparent. It is also wrong here, for a reason worth
// writing down: the crowd's colours are handed to the screen as the crowd's own memory, with no copy in between — that
// was a deliberate piece of work, because copying half a million colours a frame was costing more than the physics.
// Dimming would mean writing to those colours every frame, which puts the copy straight back.
//
// So hidden bodies are moved to the end of the crowd instead, and the screen is told to draw fewer. The crowd's order
// carries no meaning — it has no springs and nothing holds a position in it between moments, which is why removing a
// body swaps it with the last one — so moving bodies about costs nothing but the swap, and a world with nothing hidden
// does not even do that.
//
// ## Why eight
//
// A byte a body, and a world with no layers pays nothing for it because the byte is only allocated alongside the rest.
// Eight is as many as anybody can hold in their head at once, and a number that fits in the smallest thing that can
// hold it leaves the rest of the byte free for whatever comes later.

/// One named group of bodies, with its own look and its own rules.
public struct ParticleLayer: Sendable, Hashable, Codable {
    /// How many layers a world may have, counting the first.
    public static let most = 8

    /// What it is called.
    public var name: String
    /// A colour of its own, or nothing to leave every body the colour it already is.
    ///
    /// A tint rather than a replacement: a layer's bodies keep their own brightness and take the layer's hue, so a
    /// galaxy on a red layer still looks like a galaxy. Replacing the colour outright makes every layer a flat sheet
    /// of paint, which loses the thing the colours were saying.
    public var tint: PackedColor?
    /// Whether it is drawn.
    public var shown: Bool
    /// Whether a finger may push it about.
    ///
    /// Locking is not freezing: a locked layer still runs, still falls, still collides. It is only out of reach, which
    /// is what somebody wants when they are working on one part of a world and keep catching another by accident.
    public var locked: Bool
    /// How hard the world's gravity pulls on this layer, as a multiplier. One is the world's own.
    public var weight: Double
    /// How much of its speed this layer keeps each moment, as a multiplier on the world's own damping.
    ///
    /// Below one is thicker air — a layer that settles sooner. Above one is thinner, which is how a layer of smoke
    /// can drift while the sand beside it stops.
    public var thinness: Double

    public init(
        name: String,
        tint: PackedColor? = nil,
        shown: Bool = true,
        locked: Bool = false,
        weight: Double = 1,
        thinness: Double = 1
    ) {
        self.name = name
        self.tint = tint
        self.shown = shown
        self.locked = locked
        self.weight = weight
        self.thinness = thinness
    }

    /// The layer every world starts with, which cannot be removed.
    public static let first = ParticleLayer(name: "Everything")

    /// Every number pulled into a sensible range.
    public var sanitized: ParticleLayer {
        var copy = self
        copy.name = String(name.prefix(24))
        if copy.name.trimmed.isEmpty { copy.name = "Layer" }
        copy.weight = weight.isFinite ? max(-3, min(3, weight)) : 1
        copy.thinness = thinness.isFinite ? max(0.5, min(1.5, thinness)) : 1
        return copy
    }

    /// Whether this layer behaves any differently from the plain one.
    ///
    /// Read in the step to decide whether the whole per-layer pass can be skipped, which is what keeps a world with
    /// layers that are only *named* differently exactly as fast as a world with none.
    public var changesThePhysics: Bool {
        weight != 1 || thinness != 1
    }
}

extension ParticleEngine {
    /// The world's layers. There is always at least one.
    public var layers: [ParticleLayer] {
        storedLayers.isEmpty ? [ParticleLayer.first] : storedLayers
    }

    /// Which layer new bodies are born into, counting from nought.
    public var currentLayer: Int {
        get { min(max(0, storedCurrentLayer), layers.count - 1) }
        set { storedCurrentLayer = min(max(0, newValue), layers.count - 1) }
    }

    /// Whether the world has an explicit layer definition, including a customized first/only layer.
    public var hasLayers: Bool { !storedLayers.isEmpty }

    /// Installs layer definitions before loading bodies. Absent means the implicit plain first layer.
    func installLayerState(_ saved: [ParticleLayer]?, current: Int, colorsAlreadyTinted: Bool) {
        let cleaned = Array((saved ?? []).prefix(ParticleLayer.most).map(\.sanitized))
        storedLayers = cleaned.count == 1 && cleaned[0] == ParticleLayer.first ? [] : cleaned
        storedCurrentLayer = min(max(0, current), layers.count - 1)
        normalizeLayerTags(colorsAlreadyTinted: colorsAlreadyTinted)
    }

    /// Makes every body name a layer that exists and synchronizes the cheap group/tint/restack caches.
    func normalizeLayerTags(colorsAlreadyTinted: Bool) {
        let count = layers.count
        for index in particles.indices where Int(particles[index].group) >= count { particles[index].group = 0 }
        swarm.normalizeGroups(layerCount: count)
        if colorsAlreadyTinted {
            storedAppliedTints = [PackedColor?](repeating: nil, count: ParticleLayer.most)
            for index in storedLayers.indices where index < storedAppliedTints.count {
                storedAppliedTints[index] = storedLayers[index].tint
            }
        } else {
            storedAppliedTints = []
            applyLayerTints()
        }
        restackLayers()
    }

    /// A replacement scene owns a fresh undivided world. Manual Clear may keep a person's layer list; a preset may not.
    func resetLayersForNewScene() {
        storedLayers = []
        storedCurrentLayer = 0
        storedAppliedTints = []
        storedRecipe = nil
        storedRecipeSlots = []
        swarm.normalizeGroups(layerCount: 1)
        for index in particles.indices { particles[index].group = 0 }
        restackLayers()
    }

    /// Adds a layer and makes it the current one.
    ///
    /// - Returns: which layer it became, or nothing if there was no room for another.
    @discardableResult
    public func addLayer(named name: String, tint: PackedColor? = nil) -> Int? {
        var all = layers
        guard all.count < ParticleLayer.most else { return nil }
        all.append(ParticleLayer(name: name, tint: tint).sanitized)
        storedLayers = all
        storedCurrentLayer = all.count - 1
        return storedCurrentLayer
    }

    /// Changes one layer.
    @discardableResult
    public func setLayer(_ index: Int, to layer: ParticleLayer) -> Bool {
        var all = layers
        guard index >= 0, index < all.count else { return false }
        let wasShown = all[index].shown
        let wasTinted = all[index].tint
        let wanted = layer.sanitized
        let tintChanged = wasTinted != wanted.tint
        // The undo point must contain the old layer definition as well as the old body colours. It used to be taken
        // after storing the new tint, so Undo restored mismatched metadata and colours.
        if tintChanged { pushUndo() }
        all[index] = wanted
        storedLayers = all
        // New bodies go into the current layer. If that layer has just been hidden, whatever was added next was
        // invisible — clear, add five thousand, see nothing. The current layer moves to the first one still shown.
        if wasShown, !wanted.shown, currentLayer == index,
           let shown = all.indices.first(where: { all[$0].shown })
        {
            storedCurrentLayer = shown
        }
        if wasShown != all[index].shown { restackLayers() }
        applyLayerTints()
        return true
    }

    /// Hides or shows one layer.
    @discardableResult
    public func showLayer(_ index: Int, _ shown: Bool) -> Bool {
        guard index >= 0, index < layers.count else { return false }
        var layer = layers[index]
        guard layer.shown != shown else { return true }
        layer.shown = shown
        return setLayer(index, to: layer)
    }

    /// Locks or unlocks one layer.
    @discardableResult
    public func lockLayer(_ index: Int, _ locked: Bool) -> Bool {
        guard index >= 0, index < layers.count else { return false }
        var layer = layers[index]
        layer.locked = locked
        return setLayer(index, to: layer)
    }

    /// How many bodies are in one layer, crowd and named bodies together.
    public func bodiesInLayer(_ index: Int) -> Int {
        guard index >= 0, index < layers.count else { return 0 }
        let tag = UInt8(index)
        var found = 0
        if swarm.hasGroups {
            for i in 0 ..< swarm.count where swarm.groups[i] == tag { found += 1 }
        } else if index == 0 {
            found = swarm.count
        }
        for body in particles where body.group == tag { found += 1 }
        return found
    }

    /// Empties one layer, leaving the layer itself.
    @discardableResult
    public func emptyLayer(_ index: Int) -> Int {
        guard index >= 0, index < layers.count else { return 0 }
        pushUndo()
        let tag = UInt8(index)
        var removed = 0
        if swarm.hasGroups || index == 0 {
            // Backwards, because removing swaps the last body into the gap: going forwards would step over whatever
            // was just moved in.
            var i = swarm.count - 1
            while i >= 0 {
                if (swarm.hasGroups ? swarm.groups[i] : 0) == tag {
                    swarm.remove(at: i)
                    removed += 1
                }
                i -= 1
            }
        }
        // Through the one door, which rewrites every spring's ends. Filtering the list by hand is what sheared cloth
        // in the implementation this was ported from.
        removed += removeParticles { $0.group == tag }
        restackLayers()
        return removed
    }

    /// Copies a layer's bodies into a new layer.
    ///
    /// - Returns: which layer they went into, or nothing if there was no room for another layer or no bodies to copy.
    @discardableResult
    public func duplicateLayer(_ index: Int) -> Int? {
        guard index >= 0, index < layers.count, layers.count < ParticleLayer.most,
              bodiesInLayer(index) > 0
        else { return nil }
        let source = layers[index]
        pushUndo()
        let undoWas = undoSuppressed
        undoSuppressed = true
        defer { undoSuppressed = undoWas }

        guard let made = addLayer(named: "\(source.name) copy", tint: source.tint) else { return nil }
        var copy = layers[made]
        copy.shown = source.shown
        copy.locked = source.locked
        copy.weight = source.weight
        copy.thinness = source.thinness
        _ = setLayer(made, to: copy)

        let from = UInt8(index)
        let into = UInt8(made)
        // Read first, then write. Appending while walking the same list would copy the copies.
        let crowdWas = swarm.count
        var budget = maxParticles - particles.count - swarm.count
        var index2 = 0
        while index2 < crowdWas, budget > 0 {
            let inThis = (swarm.hasGroups ? swarm.groups[index2] : 0) == from
            if inThis {
                let pair = index2 * 2
                let role = Swarm.Role(rawValue: swarm.roles[index2] & Swarm.Role.known)
                let placed = swarm.append(
                    x: Double(swarm.positions[pair]),
                    y: Double(swarm.positions[pair + 1]),
                    velocityX: Double(swarm.velocities[pair]),
                    velocityY: Double(swarm.velocities[pair + 1]),
                    color: swarm.colors[index2],
                    budget: maxParticles - particles.count,
                    mass: Double(swarm.masses[index2]),
                    life: Double(swarm.lives[index2]),
                    role: role,
                    home: swarm.home(at: index2),
                    size: Double(swarm.sizes[index2]),
                    z: Double(swarm.depths[index2]),
                    velocityZ: Double(swarm.depthVelocities[index2]),
                    group: into
                )
                guard placed else { break }
                budget -= 1
            }
            index2 += 1
        }

        let bodiesWas = particles
        let springsWere = springs
        var copiedBody: [Int: Int] = [:]
        for (sourceIndex, body) in bodiesWas.enumerated() where body.group == from {
            guard particles.count + swarm.count < maxParticles else { break }
            var copy = body
            copy.group = into
            let newIndex = particles.count
            addCopy(of: copy)
            if particles.count > newIndex { copiedBody[sourceIndex] = newIndex }
        }
        // Cloth, ropes and creatures are held together by springs whose ends are positions in the object list. Copy
        // every spring whose two ends were copied, preserving muscles and thrust rather than rebuilding a plain spring.
        for spring in springsWere {
            guard let a = copiedBody[spring.a], let b = copiedBody[spring.b] else { continue }
            var copy = spring
            copy.a = a
            copy.b = b
            springs.append(copy)
        }
        restackLayers()
        applyLayerTints()
        return made
    }

    /// Pours one layer into another, and removes the emptied one.
    ///
    /// - Returns: whether it could be done. The first layer can be merged *into* but never away, because a world
    ///   always has one.
    @discardableResult
    public func mergeLayer(_ index: Int, into other: Int) -> Bool {
        let all = layers
        guard index > 0, index < all.count, other >= 0, other < all.count, index != other else { return false }
        pushUndo()
        let from = UInt8(index)
        let into = UInt8(other)
        let destinationTint = all[other].tint
        if swarm.hasGroups {
            for i in 0 ..< swarm.count where swarm.groups[i] == from {
                if let destinationTint { swarm.colors[i] = Self.tinted(swarm.colors[i], with: destinationTint) }
                swarm.setGroup(into, at: i)
            }
        }
        for i in particles.indices where particles[i].group == from {
            if let destinationTint {
                particles[i].color = PackedColor(
                    packedRGBA: Self.tinted(particles[i].color.packedRGBA, with: destinationTint)
                )
            }
            particles[i].group = into
        }
        removeLayerLeavingBodies(index)
        restackLayers()
        applyLayerTints()
        return true
    }

    /// Removes a layer and everything in it.
    @discardableResult
    public func deleteLayer(_ index: Int) -> Bool {
        guard index > 0, index < layers.count else { return false }
        _ = emptyLayer(index)
        let undoWas = undoSuppressed
        undoSuppressed = true
        defer { undoSuppressed = undoWas }
        removeLayerLeavingBodies(index)
        return true
    }

    /// Moves every body in one layer to another.
    @discardableResult
    public func moveLayerContents(_ index: Int, to other: Int) -> Int {
        let all = layers
        guard index >= 0, index < all.count, other >= 0, other < all.count, index != other else { return 0 }
        pushUndo()
        let from = UInt8(index)
        let into = UInt8(other)
        let destinationTint = all[other].tint
        var moved = 0
        if swarm.hasGroups || index == 0 {
            for i in 0 ..< swarm.count where (swarm.hasGroups ? swarm.groups[i] : 0) == from {
                if let destinationTint { swarm.colors[i] = Self.tinted(swarm.colors[i], with: destinationTint) }
                swarm.setGroup(into, at: i)
                moved += 1
            }
        }
        for i in particles.indices where particles[i].group == from {
            if let destinationTint {
                particles[i].color = PackedColor(
                    packedRGBA: Self.tinted(particles[i].color.packedRGBA, with: destinationTint)
                )
            }
            particles[i].group = into
            moved += 1
        }
        restackLayers()
        applyLayerTints()
        return moved
    }

    /// Takes a layer out of the list, renumbering the bodies of every layer after it.
    ///
    /// Private because it leaves bodies behind: the two callers each deal with them first, one by emptying and one by
    /// pouring them somewhere else. A version of this that did not renumber would leave bodies pointing at a layer
    /// that is now a different layer, which is a world that silently changes colour and rules.
    private func removeLayerLeavingBodies(_ index: Int) {
        var all = layers
        guard index > 0, index < all.count else { return }
        all.remove(at: index)
        storedLayers = all == [ParticleLayer.first] ? [] : all
        let gone = UInt8(index)
        if swarm.hasGroups {
            for i in 0 ..< swarm.count where swarm.groups[i] > gone {
                swarm.setGroup(swarm.groups[i] - 1, at: i)
            }
        }
        for i in particles.indices where particles[i].group > gone {
            particles[i].group -= 1
        }
        storedCurrentLayer = min(storedCurrentLayer, max(0, layers.count - 1))
        normalizeLayerTags(colorsAlreadyTinted: true)
    }

    // MARK: - What the rest of the engine asks

    /// Whether a body in this layer may be pushed by a finger or a tool.
    ///
    /// Read by every tool rather than each one deciding for itself, so a tool added later is locked out of a locked
    /// layer without anybody having to remember.
    public func layerAllowsTouching(_ group: UInt8) -> Bool {
        let all = layers
        let index = Int(group)
        guard index < all.count else { return true }
        return !all[index].locked
    }

    /// Whether the crowd's finger and tool passes need to check layers at all.
    var anyLayerLocked: Bool {
        !storedLayers.isEmpty && storedLayers.contains { $0.locked }
    }

    /// How hard gravity pulls on each layer, as the step wants it: empty when no layer asks for anything different.
    ///
    /// Empty rather than a table of ones, because the step checks for empty and then never looks at a body's layer at
    /// all. A world that has layers but only for organising is exactly as fast as a world with none.
    var layerWeightTable: [Double] {
        guard anyLayerChangesPhysics else { return [] }
        var table = [Double](repeating: 1, count: ParticleLayer.most)
        for (index, layer) in storedLayers.enumerated() where index < table.count {
            table[index] = layer.weight
        }
        return table
    }

    /// How much of its speed each layer keeps, in the same shape.
    var layerThinnessTable: [Double] {
        guard anyLayerChangesPhysics else { return [] }
        var table = [Double](repeating: 1, count: ParticleLayer.most)
        for (index, layer) in storedLayers.enumerated() where index < table.count {
            table[index] = layer.thinness
        }
        return table
    }

    /// Which layers a finger may not touch, as the crowd's passes want it: empty when every layer is reachable.
    var lockedLayerTable: [Bool] {
        guard anyLayerLocked else { return [] }
        var table = [Bool](repeating: false, count: ParticleLayer.most)
        for (index, layer) in storedLayers.enumerated() where index < table.count {
            table[index] = layer.locked
        }
        return table
    }

    /// Whether any layer changes how its bodies move.
    var anyLayerChangesPhysics: Bool {
        !storedLayers.isEmpty && storedLayers.contains { $0.changesThePhysics }
    }

    /// How many of the crowd's bodies are drawn: the ones at the front, once the hidden are moved behind them.
    public var shownSwarmCount: Int {
        guard !storedLayers.isEmpty, storedLayers.contains(where: { !$0.shown }) else { return swarm.count }
        // Worked out again if the crowd has changed since it was last worked out. Bodies can be added or taken away
        // between one moment and the next — a scene loaded, something painted in while the world is paused — and a
        // count from before that is too small, so the new bodies would not be drawn until the world was set running
        // again. The crowd counts its own changes, so this is a comparison rather than a search.
        if storedRestackedAt != swarm.generation { restackLayers() }
        return storedShownSwarmCount
    }

    /// Moves hidden bodies to the back of the crowd, so the screen can draw fewer rather than draw them faintly.
    ///
    /// Called when a layer is shown or hidden, when bodies change layer, and after anything that removes bodies —
    /// removal swaps the last body into the gap, which can put a hidden one back among the shown.
    /// Swaps two crowd bodies along with everything the engine keeps about them by position — the morph's two
    /// shapes and the recipe's places — so a body keeps its own target when the crowd is reordered.
    func exchangeCrowdBodies(_ first: Int, _ second: Int) {
        swarm.exchange(first, second)
        if first < storedMorphA.count, second < storedMorphA.count,
           storedMorphA.count == storedMorphB.count
        {
            storedMorphA.swapAt(first, second)
            storedMorphB.swapAt(first, second)
        }
        if first < storedRecipeSlots.count, second < storedRecipeSlots.count {
            storedRecipeSlots.swapAt(first, second)
        }
    }

    func restackLayers() {
        storedRestackedAt = swarm.generation
        guard !storedLayers.isEmpty, storedLayers.contains(where: { !$0.shown }) else {
            storedShownSwarmCount = swarm.count
            return
        }
        var hidden = [Bool](repeating: false, count: ParticleLayer.most)
        for (index, layer) in storedLayers.enumerated() where index < hidden.count {
            hidden[index] = !layer.shown
        }
        // A pass from both ends, swapping a hidden body at the front with a shown one at the back. One walk, no
        // allocation, and the crowd ends up shown-then-hidden.
        var front = 0
        var back = swarm.count - 1
        func isHidden(_ index: Int) -> Bool {
            let group = swarm.hasGroups ? Int(swarm.groups[index]) : 0
            return group < hidden.count && hidden[group]
        }
        while front <= back {
            if !isHidden(front) {
                front += 1
            } else if isHidden(back) {
                back -= 1
            } else {
                exchangeCrowdBodies(front, back)
                front += 1
                back -= 1
            }
        }
        storedShownSwarmCount = front
    }

    /// Gives every body in a newly coloured layer that layer's hue, keeping its own brightness.
    ///
    /// ## Why it is written into the colours rather than worked out while drawing
    ///
    /// The crowd's colours are handed to the screen as the crowd's own memory, with no copy in between. Deciding a
    /// colour while drawing would mean writing to half a million of them every frame, which is the copy that was
    /// deliberately taken out. So the decision is made once, here, when a layer's colour changes.
    ///
    /// ## Why it only ever applies a change
    ///
    /// Because the cost of that choice is that a body's own colour is gone once it has been tinted, and tinting an
    /// already-tinted colour is not free: the arithmetic keeps a body's brightness exactly, but the answer has to be
    /// rounded into three bytes, and that rounding compounds. Applied twenty times over, a layer visibly darkened —
    /// measured, not guessed, which is why this keeps track of what it last applied and does nothing at all when
    /// nothing has changed. Anything that merely touches a layer's other settings now leaves its colours alone.
    func applyLayerTints() {
        let all = storedLayers
        // What was last written into the bodies, one per layer, so a repeated call is a comparison and not a repaint.
        if storedAppliedTints.count != ParticleLayer.most {
            storedAppliedTints = [PackedColor?](repeating: nil, count: ParticleLayer.most)
        }
        var changed = [Bool](repeating: false, count: ParticleLayer.most)
        var any = false
        for index in 0 ..< ParticleLayer.most {
            let wanted = index < all.count ? all[index].tint : nil
            if wanted != nil, wanted != storedAppliedTints[index] {
                changed[index] = true
                any = true
            }
            storedAppliedTints[index] = wanted
        }
        guard any, !all.isEmpty else { return }

        for index in 0 ..< swarm.count {
            let group = Int(swarm.hasGroups ? swarm.groups[index] : 0)
            guard group < all.count, changed[group], let tint = all[group].tint else { continue }
            swarm.colors[index] = Self.tinted(swarm.colors[index], with: tint)
        }
        for index in particles.indices {
            let group = Int(particles[index].group)
            guard group < all.count, changed[group], let tint = all[group].tint else { continue }
            particles[index].color = PackedColor(packedRGBA: Self.tinted(particles[index].color.packedRGBA, with: tint))
        }
    }

    /// One colour wearing another's hue, at its own brightness.
    static func tinted(_ colour: UInt32, with tint: PackedColor) -> UInt32 {
        let red = Double(colour & 0xFF)
        let green = Double((colour >> 8) & 0xFF)
        let blue = Double((colour >> 16) & 0xFF)
        // How bright it was, weighted the way an eye weighs the channels.
        let level = (red * 0.2126 + green * 0.7152 + blue * 0.0722) / 255
        let tintLevel = (Double(tint.r) * 0.2126 + Double(tint.g) * 0.7152 + Double(tint.b) * 0.0722) / 255
        // Scaled so the tint keeps the body's own brightness rather than the tint's — otherwise a dark red layer
        // makes everything on it nearly black and a pale one washes it all out.
        let scale = tintLevel > 0.01 ? level / tintLevel : level
        let alpha = colour & 0xFF00_0000
        func channel(_ value: UInt8) -> UInt32 {
            UInt32(UInt8(max(0, min(255, (Double(value) * scale).rounded()))))
        }
        return channel(tint.r) | channel(tint.g) << 8 | channel(tint.b) << 16 | alpha
    }
}
