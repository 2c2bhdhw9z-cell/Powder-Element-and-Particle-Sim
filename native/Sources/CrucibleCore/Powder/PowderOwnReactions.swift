/// How this app's own materials behave.
///
/// Kept apart from `PowderReactions` for the same reason `OwnElements` is kept apart from `DefaultElements`: that
/// file is compared, cell for cell, against recordings of the reference implementation, and the agreement is worth
/// more than the convenience of having everything in one place. Nothing here can disturb it, because none of it runs
/// unless one of this app's own materials is actually in the world.
extension PowderEngine {
    /// Everything this app's own materials do, for one cell.
    ///
    /// - Returns: whether the cell has already been dealt with, so the ordinary movement pass leaves it alone.
    func updateOwnReactions(x: Int, y: Int, id: ElementID) -> Bool {
        switch id {
        case Element.kernel: return popKernel(x: x, y: y)
        case Element.soap: return foamSoap(x: x, y: y)
        case Element.sponge: return soakSponge(x: x, y: y)
        case Element.wetSponge: return squeezeSponge(x: x, y: y)
        case Element.belt: return runBelt(x: x, y: y)
        case Element.magnet: return pullIron(x: x, y: y)
        default: return false
        }
    }

    // MARK: - Popcorn

    /// Hot enough for long enough and the water inside a kernel turns to steam and bursts it open.
    ///
    /// What comes out is bigger and far lighter than what went in, so a popped pile climbs out of whatever it was
    /// heated in — which is the whole of why popcorn is entertaining. The extra piece is placed above, if there is
    /// room, because a kernel that doubles in size has to put the new part somewhere.
    private func popKernel(x: Int, y: Int) -> Bool {
        let index = y * width + x
        guard temperature[index] >= 180 else { return false }
        let heat = Double(temperature[index])
        setElement(x, y, Element.popcorn, temp: heat)
        // A jump, because popping is a small explosion: the corn leaves the pan.
        velocityY[index] = -6
        velocityX[index] = Int8(clamping: rng.int(below: 5) - 2)
        // And a second piece above it when there is room, so a pan of kernels becomes a heap of popcorn rather than
        // the same number of paler grains.
        if y > 0 {
            let above = (y - 1) * width + x
            if type[above] == Element.empty {
                setElement(x, y - 1, Element.popcorn, temp: heat)
                velocityY[above] = -7
            }
        }
        return true
    }

    // MARK: - Soap and foam

    /// Soap next to water makes foam, and foam makes more of itself where it meets more water.
    ///
    /// Slowly, and only where the two actually touch, so a drop of soap in a full tank works its way through rather
    /// than turning the lot to foam in a moment.
    private func foamSoap(x: Int, y: Int) -> Bool {
        var made = false
        for (dx, dy) in Self.aroundFour {
            let nx = x + dx
            let ny = y + dy
            guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
            let neighbour = ny * width + nx
            guard type[neighbour] == Element.water else { continue }
            guard rng.chance(0.12) else { continue }
            setElement(nx, ny, Element.foam)
            made = true
        }
        // The soap itself is used up eventually, which is what stops one drop foaming a whole sea for ever.
        if made, rng.chance(0.04) {
            setElement(x, y, Element.foam)
            return true
        }
        return false
    }

    // MARK: - Sponge

    /// A dry sponge takes in water it is touching and becomes a wet one.
    private func soakSponge(x: Int, y: Int) -> Bool {
        for (dx, dy) in Self.aroundFour {
            let nx = x + dx
            let ny = y + dy
            guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
            let neighbour = ny * width + nx
            guard type[neighbour] == Element.water else { continue }
            // The water goes into the sponge: it is gone from where it was, not copied.
            setElement(nx, ny, Element.empty)
            setElement(x, y, Element.wetSponge)
            return true
        }
        return false
    }

    /// A wet sponge with something heavy resting on it gives its water back.
    ///
    /// Squashing is what releases it, so weight on top is the test. Left alone in the air it keeps what it has —
    /// which is what a sponge does, and is why this is not simply a timer.
    private func squeezeSponge(x: Int, y: Int) -> Bool {
        guard y > 0 else { return false }
        let above = (y - 1) * width + x
        let resting = type[above]
        guard resting != Element.empty, resting != Element.water, resting != Element.foam else { return false }
        // Heavy enough to squash it. A feather of smoke sitting on a sponge should not wring it out.
        guard elements[resting].density > 40 else { return false }
        // Out of the bottom or the sides, wherever there is room — water leaves a squeezed sponge downward.
        for (dx, dy) in [(0, 1), (-1, 0), (1, 0)] {
            let nx = x + dx
            let ny = y + dy
            guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
            guard type[ny * width + nx] == Element.empty else { continue }
            guard rng.chance(0.25) else { return false }
            setElement(nx, ny, Element.water)
            setElement(x, y, Element.sponge)
            return true
        }
        return false
    }

    // MARK: - Conveyor belt

    /// A belt nudges whatever is sitting on it along, one cell at a time.
    ///
    /// Which way it goes is kept the way a fan's direction is — in the cell's own spare number — so painting a belt
    /// over a belt turns it round, exactly as painting a fan over a fan does.
    private func runBelt(x: Int, y: Int) -> Bool {
        guard y > 0 else { return false }
        // One cell every third moment. Every moment was sixty cells a second, which carried a grain the length of
        // the screen before anybody could see it was on a belt at all.
        guard frameCount % 3 == 0 else { return false }
        let index = y * width + x
        // Nought or two is rightward, one is leftward. Read the same way a fan's is.
        let step = life[index] % 2 == 1 ? -1 : 1
        let above = (y - 1) * width + x
        let carried = type[above]
        guard carried != Element.empty else { return false }
        // Not the machinery itself: a belt does not carry another belt along.
        guard carried != Element.belt, carried != Element.magnet, carried != Element.bedrock else { return false }
        // Not something another piece of belt has already moved this moment. Without this, the grain carried one
        // cell along was met by the next piece of belt in the same sweep and carried again, and again — so it crossed
        // the whole belt in a single moment and dropped off the far end before anybody saw it move.
        guard visited[above] == 0 else { return false }
        let toX = x + step
        guard toX >= 0, toX < width else { return false }
        let target = (y - 1) * width + toX
        guard type[target] == Element.empty else { return false }
        swapCells(above, target)
        return true
    }

    // MARK: - Magnet

    /// Iron dust near a magnet is drawn toward it, and stands up in spikes along the way.
    ///
    /// Each magnet looks around itself rather than each grain looking for a magnet, because there are a handful of
    /// magnets and there may be thousands of grains — and the answer is the same either way.
    ///
    /// The spikes are not drawn: they are what happens when grains all move toward the same place and then cannot
    /// pass through each other, so they pile outward along the lines they arrived on.
    private func pullIron(x: Int, y: Int) -> Bool {
        let reach = 8
        for dy in -reach ... reach {
            for dx in -reach ... reach {
                guard dx != 0 || dy != 0 else { continue }
                let nx = x + dx
                let ny = y + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let neighbour = ny * width + nx
                guard type[neighbour] == Element.ironDust else { continue }
                // Stronger close up, as a magnet is: right beside it the grains barely move at all because they
                // are already there, and at the edge of its reach they only twitch.
                let away = max(1, abs(dx) + abs(dy))
                guard away <= reach, rng.chance(min(1, 1.8 / Double(away))) else { continue }
                // One step toward the magnet, along whichever direction is furthest off.
                let stepX = abs(dx) >= abs(dy) ? (dx > 0 ? -1 : 1) : 0
                let stepY = abs(dy) > abs(dx) ? (dy > 0 ? -1 : 1) : 0
                let toX = nx + stepX
                let toY = ny + stepY
                guard toX >= 0, toX < width, toY >= 0, toY < height else { continue }
                let target = toY * width + toX
                // Into space, or swapping with anything lighter that is in the way.
                if type[target] == Element.empty {
                    swapCells(neighbour, target)
                } else if elements[type[target]].density < 30, type[target] != Element.ironDust,
                          type[target] != Element.magnet {
                    swapCells(neighbour, target)
                }
            }
        }
        return false
    }

    /// The four cells sharing an edge. Edges only, because a material should not reach round a corner.
    static let aroundFour: [(Int, Int)] = [(0, -1), (0, 1), (-1, 0), (1, 0)]
}
