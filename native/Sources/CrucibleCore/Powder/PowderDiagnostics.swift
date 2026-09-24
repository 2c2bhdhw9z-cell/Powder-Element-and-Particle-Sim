/// Inspecting the powder world's health, and putting it right.
///
/// These are the tools behind the debug panel: a read-only report, a set of individual
/// repairs, an automatic pass that picks the ones that apply, and a few injectors that
/// deliberately break things so the repairs can be exercised.
///
/// ## A repair has a higher bar than ordinary code
///
/// This is what someone reaches for when the world has already gone wrong, so a repair
/// that reports success without repairing anything, or that damages something unrelated
/// on the way past, is worse than having no repair at all — it removes the evidence and
/// the motivation to look further. Several of the notes below record exactly that
/// happening in the web reference.

/// What an inspection found.
public struct PowderDiagnostics: Sendable {
    public var width: Int
    public var height: Int
    public var totalCells: Int
    /// Cells holding something other than empty space.
    public var activeCells: Int
    /// Cells that are wrong in at least one way. Never more than one per cell.
    public var corruptCellCount: Int
    /// Cells holding an element id the registry cannot describe.
    public var corruptTypeCount: Int
    /// Cells whose temperature is not a number.
    public var unreadableTempCount: Int
    public var loadPercentage: Int
    public var maxTemp: Int
    public var minTemp: Int
    public var avgTemp: Int
    public var memoryBytes: Int
    public var frameCount: Int
    public var gravityX: Double
    public var gravityY: Double
    public var isHealthy: Bool { issues.isEmpty }
    public var issues: [String]
}

extension PowderEngine {
    /// Bytes of grid state per cell.
    ///
    /// Element 2, temperature 4, lifetime 2, visited mark 1, two momentum bytes, and two
    /// pressure fields at 4 each. Checked against the eight buffers rather than guessed.
    static let bytesPerCell = 19

    /// The temperature above which a reading counts as an extreme.
    static let hottestReasonable = 3000.0
    /// Absolute zero, below which a reading is meaningless.
    static let coldestReasonable = -273.0

    /// Looks over the whole world without changing it.
    public func inspect() -> PowderDiagnostics {
        var activeCells = 0
        // Counted apart, then combined once per cell.
        //
        // A single counter incremented in both places double-counted any cell that was
        // wrong in both ways — which is exactly what the corrupt-cell injector produces,
        // so twenty damaged cells were reported as forty and the repair that followed
        // then truthfully claimed twenty, reading like a failure. Keeping them apart also
        // lets the automatic pass tell the two faults apart, which it must: they need
        // different repairs.
        var corruptTypeCount = 0
        var unreadableTempCount = 0
        var corruptCellCount = 0

        // Tracked with a "have we seen one yet" flag rather than sentinel starting
        // values. Starting at the extremes and mapping them back afterwards meant a world
        // genuinely uniform at absolute zero reported room temperature.
        var sawTemp = false
        var maxTemp = 0.0
        var minTemp = 0.0
        var sumTemp = 0.0
        var readableTempCount = 0

        for i in 0 ..< cellCount {
            var cellIsCorrupt = false
            let id = type[i]
            if id != Element.empty {
                activeCells += 1
                // Bounded by what the registry can describe. A looser bound left a band of
                // ids that drew as air, behaved as air, were invisible to this count,
                // could not be cleared by any repair, and still counted as real particles
                // forever.
                if id > Element.customIDEnd {
                    corruptTypeCount += 1
                    cellIsCorrupt = true
                }
            }
            let t = Double(temperature[i])
            if t.isNaN {
                unreadableTempCount += 1
                cellIsCorrupt = true
            } else {
                if !sawTemp || t > maxTemp { maxTemp = t }
                if !sawTemp || t < minTemp { minTemp = t }
                sawTemp = true
                sumTemp += t
                readableTempCount += 1
            }
            if cellIsCorrupt { corruptCellCount += 1 }
        }

        // Averaged over the cells that contributed. Dividing by every cell while skipping
        // the unreadable ones dragged the figure toward zero in proportion to the damage,
        // so it was least trustworthy exactly when someone was consulting it.
        let avgTemp = readableTempCount > 0
            ? JS.round(sumTemp / Double(readableTempCount))
            : JS.round(ambientTemp)

        var issues: [String] = []
        if corruptCellCount > 0 {
            issues.append("Detected \(corruptCellCount) corrupted or unreadable grid cells")
        }
        if sawTemp, maxTemp > Self.hottestReasonable || minTemp < Self.coldestReasonable {
            issues.append(
                "Thermal extremes detected (\(Int(JS.round(minTemp)))°C to \(Int(JS.round(maxTemp)))°C)"
            )
        }
        if totalCellsExceedDensity(activeCells) {
            issues.append("Grid density near maximum capacity (>95%)")
        }

        return PowderDiagnostics(
            width: width,
            height: height,
            totalCells: cellCount,
            activeCells: activeCells,
            corruptCellCount: corruptCellCount,
            corruptTypeCount: corruptTypeCount,
            unreadableTempCount: unreadableTempCount,
            loadPercentage: cellCount > 0
                ? Int(JS.round(Double(activeCells) / Double(cellCount) * 100))
                : 0,
            maxTemp: Int(sawTemp ? JS.round(maxTemp) : JS.round(ambientTemp)),
            minTemp: Int(sawTemp ? JS.round(minTemp) : JS.round(ambientTemp)),
            avgTemp: Int(avgTemp),
            memoryBytes: cellCount * Self.bytesPerCell,
            frameCount: frameCount,
            gravityX: gravityX,
            gravityY: gravityY,
            issues: issues
        )
    }

    private func totalCellsExceedDensity(_ activeCells: Int) -> Bool {
        cellCount > 0 && Double(activeCells) > Double(cellCount) * 0.95
    }

    // MARK: - Individual repairs

    /// Empties every cell holding an element nothing can describe.
    @discardableResult
    public func flushStuckCells() -> Int {
        var cleared = 0
        visited.update(repeating: 0, count: cellCount)
        for i in 0 ..< cellCount where type[i] > Element.customIDEnd {
            // Emptied completely. Clearing only the element and its temperature left the
            // cell holding the lifetime and momentum of whatever had been there, so the
            // next thing to occupy it inherited a stranger's motion and a countdown to
            // decay.
            type[i] = Element.empty
            temperature[i] = JS.toFloat32(ambientTemp)
            life[i] = 0
            velocityX[i] = 0
            velocityY[i] = 0
            cleared += 1
        }
        return cleared
    }

    /// Returns unreadable and absurd temperatures to the world's ambient.
    @discardableResult
    public func normaliseTemperatures() -> Int {
        var fixed = 0
        let ambient = JS.toFloat32(ambientTemp)
        for i in 0 ..< cellCount {
            let t = Double(temperature[i])
            if t.isNaN || t > Self.hottestReasonable || t < Self.coldestReasonable {
                // The world's own ambient, not a hardcoded room temperature. Half the
                // repairs used one and half the other, so on a world set to forty below
                // they disagreed with each other and with the physics being restored.
                temperature[i] = ambient
                fixed += 1
            }
        }
        return fixed
    }

    /// Clears anything wedged against the frame of the world.
    @discardableResult
    public func purgeOutOfBounds() -> Int {
        guard width > 0, height > 0 else { return 0 }
        var purged = 0
        let ambient = JS.toFloat32(ambientTemp)

        func clear(_ x: Int, _ y: Int) {
            guard isValid(x, y) else { return }
            let i = index(x, y)
            // Bedrock is left alone: it is the wall, not something stuck against it.
            guard type[i] != Element.empty, type[i] != Element.bedrock else { return }
            type[i] = Element.empty
            temperature[i] = ambient
            life[i] = 0
            velocityX[i] = 0
            velocityY[i] = 0
            purged += 1
        }

        for x in 0 ..< width {
            clear(x, 0)
            clear(x, height - 1)
        }
        for y in 0 ..< height {
            clear(0, y)
            clear(width - 1, y)
        }
        return purged
    }

    /// Puts out every fire, and makes explosives inert.
    @discardableResult
    public func extinguishFires() -> Int {
        var count = 0
        let ambient = JS.toFloat32(ambientTemp)
        for i in 0 ..< cellCount {
            let id = type[i]
            if id == Element.fire || id == Element.smoke || id == Element.spark {
                type[i] = Element.empty
                temperature[i] = ambient
                life[i] = 0
                count += 1
            } else if id == Element.gunpowder || id == Element.c4 {
                // Turned to stone, at ambient. Turning an explosive into water at 250
                // degrees — which is what this used to do — is above boiling, so "making
                // it safe" produced a steam burst on the very next tick.
                type[i] = Element.stone
                temperature[i] = ambient
                life[i] = 0
                count += 1
            }
        }
        return count
    }

    /// Turns acid into water.
    @discardableResult
    public func neutraliseAcids() -> Int {
        var count = 0
        let ambient = JS.toFloat32(ambientTemp)
        for i in 0 ..< cellCount where type[i] == Element.acid {
            type[i] = Element.water
            temperature[i] = ambient
            life[i] = 0
            count += 1
        }
        return count
    }

    /// Walls the world in with bedrock.
    ///
    /// Deliberately never part of the automatic pass. This is not a repair — it replaces
    /// whatever was around the edge, and every built-in scene leaves the top and the upper
    /// side walls open on purpose, so running it over a scene destroys its shape. The web
    /// reference ran it on any unhealthy world, including one whose only complaint was
    /// being nearly full.
    @discardableResult
    public func sealBedrockBorders() -> Int {
        // A world with no cells has no border. Without this guard the loops computed an
        // index of minus one, whose write goes nowhere while the read beside it returns
        // nothing — so the count rose for writes that never landed.
        guard width > 0, height > 0 else { return 0 }
        var changed = 0
        let ambient = JS.toFloat32(ambientTemp)

        func seal(_ x: Int, _ y: Int) {
            guard isValid(x, y) else { return }
            let i = index(x, y)
            guard type[i] != Element.bedrock else { return }
            type[i] = Element.bedrock
            // Bedrock does not burn, decay or move, so the state of whatever it replaced
            // goes with it. Left behind, a burning cell became bedrock that was still at
            // nine hundred degrees with a decay countdown running, quietly cooking its
            // neighbours from inside something meant to be inert.
            temperature[i] = ambient
            life[i] = 0
            velocityX[i] = 0
            velocityY[i] = 0
            changed += 1
        }

        for x in 0 ..< width {
            seal(x, 0)
            seal(x, height - 1)
        }
        for y in 0 ..< height {
            seal(0, y)
            seal(width - 1, y)
        }
        return changed
    }

    /// Returns every cell to the world's ambient temperature.
    public func coolAllCells() {
        guard cellCount > 0 else { return }
        temperature.update(repeating: JS.toFloat32(ambientTemp), count: cellCount)
    }

    /// Discards the per-tick movement marks and the cached image.
    public func resetScratchBuffers() {
        guard cellCount > 0 else { return }
        visited.update(repeating: 0, count: cellCount)
    }

    // MARK: - Injectors, for exercising the repairs

    /// Drops a block of fire at an impossible temperature in the middle of the world.
    public func injectThermalSpike() {
        let cx = width / 2
        let cy = height / 2
        for dy in -10 ... 10 {
            for dx in -10 ... 10 where isValid(cx + dx, cy + dy) {
                // Placed properly, so the fire gets its decay countdown. Written straight
                // into the grid the countdown stayed at zero, and anything decaying with a
                // spent countdown becomes its successor immediately — so the whole spike
                // turned to smoke on the first tick, erasing the extreme it exists to
                // create.
                setElement(cx + dx, cy + dy, Element.fire, temp: 2800)
            }
        }
    }

    /// Floods the lower part of the world with acid.
    public func injectAcidFlood() {
        guard width > 2, height > 1 else { return }
        let startY = Int(Double(height) * 0.7)
        for y in startY ..< (height - 1) {
            for x in 1 ..< (width - 1) {
                // Through the normal placement path, so the acid arrives at its own
                // temperature instead of inheriting the cell's. Poured over lava it used
                // to start well above boiling and flash straight to steam.
                setElement(x, y, Element.acid)
            }
        }
    }

    /// Writes cells that hold nonsense, to give the repairs something to find.
    public func injectCorruptCells() {
        let cx = width / 2
        let cy = height / 2
        for offset in 0 ..< 20 {
            guard isValid(cx + offset, cy) else { break }
            let i = index(cx + offset, cy)
            type[i] = 9999
            temperature[i] = Float.nan
        }
    }

    // MARK: - The automatic pass

    /// Runs whichever repairs the world's condition calls for.
    ///
    /// - Returns: a log of what it did, for the debug panel.
    @discardableResult
    public func runAutoFix() -> [String] {
        var logs = ["Initiating powder diagnostics pass..."]

        let before = inspect()
        if before.isHealthy {
            logs.append("✓ All grid buffers and temperatures verified normal.")
            logs.append("✓ No anomalies detected.")
            return logs
        }

        var steps: [String] = []

        if before.corruptTypeCount > 0 {
            steps.append("Cleared \(flushStuckCells()) cells holding an unusable element.")
        }

        // Unreadable temperatures are part of the condition.
        //
        // Gated on the hottest and coldest readings alone, an unreadable temperature is
        // neither — it is excluded from both — so a world whose only fault was unreadable
        // temperatures had its thermal repair skipped, was told it had recovered, and
        // still reported itself unhealthy the moment anyone looked again.
        if before.unreadableTempCount > 0
            || Double(before.maxTemp) > Self.hottestReasonable
            || Double(before.minTemp) < Self.coldestReasonable {
            steps.append("Returned \(normaliseTemperatures()) unusable temperatures to ambient.")
        }

        let purged = purgeOutOfBounds()
        if purged > 0 {
            steps.append("Cleared \(purged) cells wedged against the world frame.")
        }

        // Note: the perimeter is deliberately not sealed here. See `sealBedrockBorders`.

        resetScratchBuffers()
        steps.append("Reset the per-tick movement marks.")

        for (i, message) in steps.enumerated() {
            logs.append("✓ Step \(i + 1)/\(steps.count): \(message)")
        }

        // Says what is left rather than dressing a failure as a success. The old message
        // announced recovery even when the world was still broken, which is the one case
        // where the detail matters.
        let after = inspect()
        if after.isHealthy {
            logs.append("Diagnostics pass complete. World health: fully operational.")
        } else {
            logs.append("Diagnostics pass complete, but \(after.issues.count) issue(s) could not be repaired:")
            for issue in after.issues { logs.append("  • \(issue)") }
        }
        return logs
    }
}
