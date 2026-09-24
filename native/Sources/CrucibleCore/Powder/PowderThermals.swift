// Heat, wind and pressure.
//
// Ported from web/src/sim/powder/thermals.ts.
//
// Every temperature here is read at double precision, computed at double
// precision, and narrowed back to single precision on store — because the grid
// holds temperatures as 32-bit floats and so rounds on every write. That rounding
// is load-bearing: the chemistry has hard thresholds, and 700°C is what decides
// whether lava becomes obsidian.

extension PowderEngine {
    /// Spreads heat between neighbouring cells.
    ///
    /// Sampled rather than exhaustive — every second cell in each direction, so a
    /// quarter of the grid per pass — which is why it runs on alternate ticks.
    ///
    /// Two corrections over the original:
    ///
    /// 1. **The sampled lattice shifts every pass.** It used to start at (1, 1) and
    ///    stride by two forever, so only odd/odd cells ever acted as a diffusion
    ///    centre — and because all four neighbours of an odd/odd cell sit at even
    ///    coordinates, those neighbours were never sampled themselves. Heat flowed
    ///    one way out of a fixed lattice and pooled where it could not be
    ///    redistributed, leaving a permanent checkerboard in the temperature field.
    ///    Cycling the offset visits all four sub-lattices.
    /// 2. **Heat is conserved.** The centre cell gained `delta` while each of its
    ///    four neighbours gave up only `delta * 0.15` — six tenths of it — so every
    ///    pass quietly destroyed heat around hot cells and invented it around cold
    ///    ones, despite the original's comment claiming to conserve.
    func diffuseHeat() {
        guard width > 2, height > 2 else { return }

        // This runs on every second tick, so halving the frame count gives a pass
        // counter; four passes cover all four sub-lattices.
        let phase = (frameCount / 2) % 4
        let offsetX = phase % 2
        let offsetY = (phase >> 1) % 2

        var y = 1 + offsetY
        while y < height - 1 {
            var x = 1 + offsetX
            while x < width - 1 {
                let idx = index(x, y)
                let cellType = type[idx]
                if cellType == Element.empty {
                    x += 2
                    continue
                }

                let conductivity = elements[cellType].heatConductivity
                // Poor conductors are skipped entirely; the effect would be
                // invisible and it is most of the grid.
                if conductivity <= 0.05 {
                    x += 2
                    continue
                }

                let own = temperature[idx].asDouble
                let neighbours = [
                    index(x + 1, y),
                    index(x - 1, y),
                    index(x, y + 1),
                    index(x, y - 1),
                ]

                var sum = own
                var count = 1.0
                for neighbour in neighbours where neighbour >= 0 && neighbour < cellCount {
                    sum += temperature[neighbour].asDouble
                    count += 1
                }

                let average = sum / count
                let delta = (average - own) * conductivity * 0.15
                temperature[idx] = JS.toFloat32(own + delta)

                // Take back from the neighbours exactly what this cell gained, so
                // heat is moved rather than created or destroyed.
                let contributors = count - 1
                if contributors > 0 {
                    let share = delta / contributors
                    for neighbour in neighbours where neighbour >= 0 && neighbour < cellCount {
                        temperature[neighbour] = JS.toFloat32(temperature[neighbour].asDouble - share)
                    }
                }

                x += 2
            }
            y += 2
        }
    }

    /// Moves heat rapidly along copper and metal, and leaks it into whatever they
    /// touch.
    ///
    /// This is what makes copper a heat pipe: it carries temperature without
    /// carrying mass, so a copper run can warm something at the far end of the
    /// world.
    func pipeHeat() {
        guard width > 2, height > 2 else { return }

        for y in 1 ..< (height - 1) {
            for x in 1 ..< (width - 1) {
                let i = y * width + x
                let cellType = type[i]
                guard cellType == Element.copper || cellType == Element.metal else { continue }

                let own = temperature[i].asDouble
                let neighbours = [i - 1, i + 1, i - width, i + width]

                var pipeSum = own
                var pipeCount = 1.0
                var dumpSum = 0.0
                var dumpCount = 0.0

                for neighbour in neighbours {
                    let neighbourType = type[neighbour]
                    if neighbourType == Element.copper || neighbourType == Element.metal {
                        pipeSum += temperature[neighbour].asDouble
                        pipeCount += 1
                    } else if neighbourType != Element.empty && neighbourType != Element.bedrock {
                        dumpSum += temperature[neighbour].asDouble
                        dumpCount += 1
                    }
                }

                // Copper equalises much faster than plain metal.
                let mix = cellType == Element.copper ? 0.55 : 0.22
                let pipeAverage = pipeSum / pipeCount
                temperature[i] = JS.toFloat32(own + (pipeAverage - own) * mix)

                if dumpCount > 0 {
                    // Read back the stored value rather than reusing the computed
                    // one: it has been rounded to single precision, and the
                    // original reads the array here too.
                    let afterMixing = temperature[i].asDouble
                    let leak = (afterMixing - dumpSum / dumpCount) * (cellType == Element.copper ? 0.18 : 0.08)
                    temperature[i] = JS.toFloat32(afterMixing - leak)

                    let share = leak / dumpCount
                    for neighbour in neighbours {
                        let neighbourType = type[neighbour]
                        if neighbourType != Element.copper && neighbourType != Element.metal
                            && neighbourType != Element.empty && neighbourType != Element.bedrock
                        {
                            temperature[neighbour] = JS.toFloat32(temperature[neighbour].asDouble + share)
                        }
                    }
                }
            }
        }
    }

    /// Pushes gases and light powders sideways.
    func applyWindDrift() {
        let wind = windX
        if wind == 0 { return }
        // A grid narrower than two columns has nowhere to drift to. The guard is
        // not merely an optimisation: the original's loop bounds are computed from
        // the width, and on a zero-width grid its termination condition can never
        // be reached.
        guard cellCount > 0, width > 1 else { return }

        let direction = wind > 0 ? 1 : -1
        let strength = wind < 0 ? -wind : wind

        for y in 0 ..< height {
            // Walk into the wind, so a cell cannot be pushed twice in one pass by
            // catching up with itself.
            let startX = direction > 0 ? width - 2 : 1
            let endX = direction > 0 ? -1 : width
            let stepX = direction > 0 ? -1 : 1

            var x = startX
            while x != endX {
                defer { x += stepX }

                let idx = index(x, y)
                let cellType = type[idx]
                if cellType == Element.empty { continue }

                let definition = elements[cellType]
                let isLight = definition.state == .gas
                    || definition.state == .plasma
                    || definition.density < 12
                if !isLight { continue }

                // Stronger wind moves a larger share of eligible cells each pass.
                if rng.next() > 0.4 * strength { continue }

                let targetX = x + direction
                guard isValid(targetX, y) else { continue }
                let targetIdx = index(targetX, y)
                if type[targetIdx] == Element.empty {
                    swapCells(idx, targetIdx)
                    visited[targetIdx] = 1
                }
            }
        }
    }

    /// Builds and relaxes the pressure field, and detonates sealed pockets of gas.
    ///
    /// Pressure is what makes gases find their way out of a container and what
    /// makes a trapped steam pocket explode instead of quietly compressing.
    func updatePressure() {
        guard cellCount > 0 else { return }

        // Accumulate: occupied cells press outward according to what they are,
        // empty space bleeds off, and the void actively sucks.
        for i in 0 ..< cellCount {
            let cellType = type[i]

            if cellType == Element.empty {
                pressure[i] = JS.toFloat32(pressure[i].asDouble * 0.82)
                continue
            }
            if cellType == Element.void {
                pressure[i] = JS.toFloat32(min(pressure[i].asDouble, -4))
                continue
            }

            let definition = elements[cellType]
            var add = definition.density * 0.012
            if definition.state == .gas || definition.state == .plasma { add += 0.35 }
            if cellType == Element.fire || cellType == Element.steam || cellType == Element.plasma { add += 1.2 }
            if cellType == Element.lava { add += 0.6 }

            pressure[i] = JS.toFloat32(max(-8, min(24, pressure[i].asDouble * 0.92 + add)))
        }

        // Relax: weighted average with the four neighbours, written into the
        // scratch buffer so every cell sees the same generation of input.
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = y * width + x
                // The cell itself counts double, which keeps the field from
                // smearing flat in a single pass.
                var sum = pressure[i].asDouble * 2
                var count = 2.0
                if x > 0 {
                    sum += pressure[i - 1].asDouble
                    count += 1
                }
                if x < width - 1 {
                    sum += pressure[i + 1].asDouble
                    count += 1
                }
                if y > 0 {
                    sum += pressure[i - width].asDouble
                    count += 1
                }
                if y < height - 1 {
                    sum += pressure[i + width].asDouble
                    count += 1
                }
                pressureNext[i] = JS.toFloat32(sum / count)
            }
        }

        // The relaxed field becomes the live one. Exchanging the buffers rather
        // than copying is how the original does it, and it is free.
        swapPressureBuffers()

        guard frameCount % 4 == 0 else { return }

        // A pocket of gas that is both over-pressurised and boxed in lets go.
        // At most one per check, so a badly sealed world does not chain-detonate
        // in a single tick.
        for i in 0 ..< cellCount {
            if pressure[i].asDouble < 12 { continue }

            let cellType = type[i]
            guard cellType == Element.steam || cellType == Element.oxygen
                || cellType == Element.hydrogen || cellType == Element.smoke
            else { continue }

            let x = i % width
            let y = i / width

            // Checked as coordinates, not raw offsets. At x = 0 the offset i - 1 is
            // the last cell of the row above: not adjacent, yet the original counted
            // it toward "sealed", so pockets against the left and right walls
            // detonated on the wrong evidence.
            var walls = 0
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                // Off the grid counts as a wall — the world's edges contain
                // pressure just as stone does.
                guard isValid(nx, ny) else {
                    walls += 1
                    continue
                }
                switch type[index(nx, ny)] {
                case Element.stone, Element.metal, Element.concrete,
                     Element.bedrock, Element.glass, Element.copper:
                    walls += 1
                default:
                    break
                }
            }

            if walls >= 3 {
                triggerExplosion(centerX: x, centerY: y, radius: 8, shockwaveForce: 14, maxHeat: 900)
                break
            }
        }
    }
}
