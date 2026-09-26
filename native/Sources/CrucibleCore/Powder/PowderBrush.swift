/// The shapes a brush stroke can take.
public enum BrushShape: String, Sendable, Hashable, CaseIterable, Codable {
    /// A filled disc.
    case circle
    /// A filled square.
    case square
    /// A disc, but only about a quarter of its cells, for a scattered effect.
    case spray
    /// A single-cell line, used while dragging.
    case line
    /// Flood-fills the connected region under the touch.
    case fill
    /// Paints only over cells that already hold a chosen element.
    case replace
}

// Painting, flood filling, bulk spawning and shake.
//
// Ported from web/src/sim/powder/brush.ts.

extension PowderEngine {
    /// Gives every loose cell a random shove, scaled by how much shake energy is
    /// left.
    ///
    /// Structural material is exempt, as are stone, concrete, glass and copper —
    /// shaking a wall would be wrong, and shaking the world's furniture apart would
    /// make the gesture destructive rather than playful.
    func applyJostle() {
        guard cellCount > 0 else { return }
        let kick = jostleLeft * 6

        for i in 0 ..< cellCount {
            let cellType = type[i]
            switch cellType {
            case Element.empty, Element.bedrock, Element.stone,
                 Element.concrete, Element.glass, Element.copper:
                continue
            default:
                break
            }
            if elements[cellType].state == .solidFixed { continue }

            velocityX[i] = JS.toInt8(max(-18, min(18, velocityX[i].asDouble + (rng.next() - 0.5) * kick)))
            velocityY[i] = JS.toInt8(max(-18, min(18, velocityY[i].asDouble + (rng.next() - 0.5) * kick)))
        }
    }

    /// Replaces the connected region of whatever is under a point.
    ///
    /// Capped at eight thousand cells so that tapping empty space in a large world
    /// cannot stall a frame while it fills the entire grid.
    public func floodFill(startX: Int, startY: Int, elementID: ElementID) {
        guard isValid(startX, startY) else { return }
        let targetID = type[index(startX, startY)]
        if targetID == elementID { return }

        var stack: [(Int, Int)] = [(startX, startY)]
        let limit = 8000
        var filled = 0

        while filled < limit, let (x, y) = stack.popLast() {
            guard isValid(x, y) else { continue }
            let idx = index(x, y)
            if type[idx] == targetID {
                setElement(x, y, elementID)
                filled += 1
                stack.append((x + 1, y))
                stack.append((x - 1, y))
                stack.append((x, y + 1))
                stack.append((x, y - 1))
            }
        }
    }

    /// Paints a stroke.
    ///
    /// - Parameters:
    ///   - targetElementID: For the replace shape, the element that may be painted
    ///     over. Everything else is left alone.
    ///   - now: Current time in milliseconds, used only to rate-limit fan
    ///     rotation. Supplied by the caller because the engine has no clock of its
    ///     own — it imports no Foundation, and a physics engine that reads the wall
    ///     clock is not reproducible.
    public func drawBrush(
        centerX: Int,
        centerY: Int,
        radius: Int,
        elementID: ElementID,
        shape: BrushShape,
        targetElementID: ElementID? = nil,
        now: Double = 0
    ) {
        if shape == .fill {
            floodFill(startX: centerX, startY: centerY, elementID: elementID)
            return
        }

        guard radius >= 0 else { return }
        let radiusSquared = radius * radius

        let fanMayTurn = now - lastFanRotate > 350
        var turnedAFan = false
        defer { if turnedAFan { lastFanRotate = now } }

        for dy in -radius ... radius {
            for dx in -radius ... radius {
                let x = centerX + dx
                let y = centerY + dy
                guard isValid(x, y) else { continue }

                if shape == .circle && dx * dx + dy * dy > radiusSquared { continue }
                if shape == .spray {
                    // The draw is taken only after the disc test, matching the
                    // original's short-circuit.
                    if dx * dx + dy * dy > radiusSquared || rng.next() > 0.25 { continue }
                }

                // A target element filters the stroke whatever the shape is. The
                // original honoured it only for the replace shape, so passing one
                // alongside a circle or square silently painted over everything.
                if let targetElementID, type[index(x, y)] != targetElementID { continue }

                // Painting a fan onto an existing fan turns it rather than replacing
                // it, rate-limited so that one drag does not spin it repeatedly.
                //
                // The limit is checked once per stroke rather than per cell. Checked per cell, the first cell
                // turned reset the clock and every other cell of the same fan was refused, so a fan more than
                // one cell across turned one piece of itself and left the rest pointing the old way.
                if elementID == Element.fan && type[index(x, y)] == Element.fan {
                    if fanMayTurn {
                        let idx = index(x, y)
                        // Widened before adding: a lifetime of 65535 from a loaded file overflowed and crashed.
                        life[idx] = UInt16((Int(life[idx]) + 1) % 4)
                        turnedAFan = true
                    }
                    continue
                }

                setElement(x, y, elementID)
            }
        }
    }

    /// Scatters a quantity of an element across the world.
    ///
    /// Empty cells are preferred; once the attempts are used up the remainder is
    /// placed regardless of what is already there, so the requested amount always
    /// arrives.
    public func spawnAmount(elementID: ElementID, requested: Int) {
        guard cellCount > 0, requested > 0 else { return }
        // Clamped to the grid. An unclamped request burned three attempts per
        // particle before giving up, so asking for far more than could fit stalled a
        // frame achieving nothing.
        let amount = min(requested, cellCount)
        var placed = 0
        let maxAttempts = amount * 3

        var attempt = 0
        while attempt < maxAttempts && placed < amount && placed < cellCount {
            attempt += 1
            let x = rng.int(below: width)
            let y = rng.int(below: height)
            if type[index(x, y)] == Element.empty {
                setElement(x, y, elementID)
                placed += 1
            }
        }

        while placed < amount && placed < cellCount {
            let x = rng.int(below: width)
            let y = rng.int(below: height)
            setElement(x, y, elementID)
            placed += 1
        }
    }
}
