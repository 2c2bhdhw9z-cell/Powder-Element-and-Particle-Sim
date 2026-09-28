// A picture of the field that looks like the field.
//
// ## Why the one-pixel-per-body picture was not enough
//
// The engine has always been able to draw the field: ``ParticleEngine/render(into:)`` puts one pixel down per body.
// That exists to be compared against the web engine pixel for pixel, and for that job it is exactly right.
//
// As a *picture* it is close to useless, and this was found by looking at one rather than by reasoning about it. The
// day's shared field, written out at six hundred and sixty by fourteen hundred and ten, came back with all but a few
// hundred pixels set to the background — a black rectangle with a faint sprinkle of dust in it. Two hundred single
// pixels in nine hundred thousand is nothing to look at, and enlarging does not help, because enlarging a grid of
// single pixels gives single squares with the same emptiness between them.
//
// The screen does not draw it that way. Every body is a round dot as wide as the body actually is — a spark a few
// pixels across, the sun at the middle of a solar flare a hundred — and where dots overlap the light adds up, which is
// what makes a galaxy's core white and its arms faint. A picture made without a screen should do the same, and do it
// in the engine where it can be checked rather than in a phone where it cannot.
//
// ## What this is, honestly
//
// A likeness, not a copy. The screen also lays on a glow, trails behind fast bodies, and silhouettes other than a
// circle; those live on the GPU and are not reproduced. What *is* reproduced is everything that decides whether the
// picture reads as the same field: where each body is, how wide, what colour, and light adding up where bodies crowd.
//
// Two things are deliberately borrowed rather than reinvented, because they are the two that could silently drift:
// colours come from ``ParticleEngine/renderColor(of:density:)``, the one place in the program that decides what colour
// a body is, and a body's width is its diameter, which is the same number the app hands the GPU. Change either on the
// screen and the picture follows.

extension ParticleEngine {
    /// A picture of the field: a round dot per body at the size that body really is, light adding up where they
    /// overlap.
    ///
    /// - Parameters:
    ///   - scale: whole-number enlargement of the field's own dimensions. Dots grow with it, so enlarging gives a
    ///     bigger picture of the same scene rather than the same picture with wider gaps.
    ///   - glowing: whether to spread light out of the bright parts, the way the screen's glow does. Off by default,
    ///     matching the field's own setting, which is also off unless somebody turns it on.
    /// - Returns: one packed colour per pixel, rows top to bottom, or an empty array if there is nothing to draw.
    public func fieldPicture(scale: Int = 1, glowing: Bool? = nil) -> [UInt32] {
        let factor = max(1, scale)
        let outWidth = Int(width) * factor
        let outHeight = Int(height) * factor
        guard outWidth > 0, outHeight > 0, outWidth * outHeight <= 64_000_000 else { return [] }

        // Light is gathered before it is turned into colour, because that is the only way overlap can add up: once a
        // pixel has been squeezed into a byte it has forgotten how much light landed on it.
        var light = [Float](repeating: 0, count: outWidth * outHeight * 3)

        light.withUnsafeMutableBufferPointer { buffer in
            guard let out = buffer.baseAddress else { return }

            /// Lays one round dot down, fading to nothing at its edge.
            func dot(atX x: Double, y: Double, across: Double, red: Float, green: Float, blue: Float) {
                // Never smaller than most of a pixel, so a field of hairline bodies still gives round dots rather
                // than nothing at all.
                let reach = max(0.6, across * Double(factor) / 2)
                let reachSquared = Float(reach * reach)
                let centreX = x * Double(factor)
                let centreY = y * Double(factor)
                let fromX = max(0, Int((centreX - reach).rounded(.down)))
                let toX = min(outWidth - 1, Int((centreX + reach).rounded(.up)))
                let fromY = max(0, Int((centreY - reach).rounded(.down)))
                let toY = min(outHeight - 1, Int((centreY + reach).rounded(.up)))
                guard fromX <= toX, fromY <= toY else { return }
                for py in fromY ... toY {
                    let dy = Float(Double(py) + 0.5 - centreY)
                    let dySquared = dy * dy
                    let row = py * outWidth
                    for px in fromX ... toX {
                        let dx = Float(Double(px) + 0.5 - centreX)
                        let distance = dx * dx + dySquared
                        guard distance < reachSquared else { continue }
                        // Full strength in the middle, fading to nothing at the edge. Squared distance rather than
                        // distance, so there is no square root in the inner loop and the dot has a soft shoulder
                        // instead of a cone's hard point.
                        let strength = 1 - distance / reachSquared
                        let at = (row + px) * 3
                        out[at] += red * strength
                        out[at + 1] += green * strength
                        out[at + 2] += blue * strength
                    }
                }
            }

            // The crowd first, so the object bodies sit on top of it — the same order the screen draws them in.
            let crowd = swarm
            // Only as many as are shown. Hidden layers are kept at the back of the crowd, so this is a count rather
            // than a test per body — see `ParticleEngine.restackLayers()`.
            let drawn = shownSwarmCount
            if drawn > 0 {
                let everyOne = max(1.0, particleSize)
                for index in 0 ..< drawn {
                    let x = Double(crowd.positions[index * 2])
                    let y = Double(crowd.positions[index * 2 + 1])
                    guard x.isFinite, y.isFinite else { continue }
                    let packed = crowd.colors[index]
                    dot(
                        atX: x, y: y,
                        across: crowd.hasSizes ? max(1, Double(crowd.sizes[index])) : everyOne,
                        red: Float(packed & 0xFF),
                        green: Float((packed >> 8) & 0xFF),
                        blue: Float((packed >> 16) & 0xFF)
                    )
                }
            }

            let density = densityGridIfNeeded()
            let all = layers
            for body in particles {
                // A named body on a hidden layer is simply not drawn. There is no reordering to lean on here: the
                // named bodies are a list with springs into it, and moving them about would shear the springs.
                if all.count > 1, Int(body.group) < all.count, !all[Int(body.group)].shown { continue }
                // Skipped rather than converted, as in the pixel renderer: a body at an impossible coordinate would
                // otherwise pile into the corner and read as a bright dot that is really a fault.
                guard body.x.isFinite, body.y.isFinite else { continue }
                let colour = renderColor(of: body, density: density)
                dot(
                    atX: body.x, y: body.y,
                    // Its diameter, which is the number the app hands the GPU for the same body. Capped at the same
                    // ninety-six the app caps it at, so one enormous body cannot fill the whole picture.
                    across: max(1, min(96, body.radius * 2)),
                    red: Float(colour.r),
                    green: Float(colour.g),
                    blue: Float(colour.b)
                )
            }
        }

        if glowing ?? (glow.strength > 0) {
            addGlow(to: &light, width: outWidth, height: outHeight, scale: factor)
        }

        let backgroundRed = Float(Self.backgroundColor & 0xFF)
        let backgroundGreen = Float((Self.backgroundColor >> 8) & 0xFF)
        let backgroundBlue = Float((Self.backgroundColor >> 16) & 0xFF)
        var pixels = [UInt32](repeating: 0, count: outWidth * outHeight)
        for i in 0 ..< pixels.count {
            let at = i * 3
            let red = min(255, max(0, light[at] + backgroundRed))
            let green = min(255, max(0, light[at + 1] + backgroundGreen))
            let blue = min(255, max(0, light[at + 2] + backgroundBlue))
            pixels[i] = UInt32(UInt8(red))
                | UInt32(UInt8(green)) << 8
                | UInt32(UInt8(blue)) << 16
                | 0xFF00_0000
        }
        return pixels
    }

    /// Spreads light out of the bright parts and adds it back, the way the screen's glow does.
    ///
    /// The same three decisions the shader makes, in the same order: keep only what is bright enough, blur it across
    /// and then down, add it on at the chosen strength. Blurred in two sweeps rather than one square pass because a
    /// Gaussian separates, which turns a nine-by-nine into nine plus nine.
    private func addGlow(to light: inout [Float], width: Int, height: Int, scale: Int) {
        let settings = glow.sanitized
        let strength = Float(settings.strength)
        guard strength > 0 else { return }
        // The nine weights of the shader's blur, and the same normalisation.
        let weights: [Float] = [0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162]
        // How far apart the samples sit. The shader works on a half-size picture, so a step there covers twice the
        // ground; doubled here, and scaled with the enlargement so a bigger picture glows by the same proportion
        // rather than by the same number of pixels.
        let step = max(1, Int((settings.spread * 2 * Double(scale)).rounded()))
        let threshold = Float(settings.threshold) * 255
        let count = width * height

        // Only the bright parts, with a soft shoulder rather than a hard cut — a hard cut makes the glow appear along
        // a visible contour as something brightens, which reads as a fault in the picture.
        var bright = [Float](repeating: 0, count: count * 3)
        for i in 0 ..< count {
            let at = i * 3
            // Brightness weighted the way an eye weighs the three channels: green counts for most, blue least.
            let level = light[at] * 0.2126 + light[at + 1] * 0.7152 + light[at + 2] * 0.0722
            let knee = threshold + 0.25 * 255
            let amount: Float
            if level <= threshold {
                amount = 0
            } else if level >= knee {
                amount = 1
            } else {
                let t = (level - threshold) / (knee - threshold)
                amount = t * t * (3 - 2 * t)
            }
            guard amount > 0 else { continue }
            bright[at] = light[at] * amount
            bright[at + 1] = light[at + 1] * amount
            bright[at + 2] = light[at + 2] * amount
        }

        var across = [Float](repeating: 0, count: count * 3)
        for y in 0 ..< height {
            let row = y * width
            for x in 0 ..< width {
                let at = (row + x) * 3
                var red = bright[at] * weights[0]
                var green = bright[at + 1] * weights[0]
                var blue = bright[at + 2] * weights[0]
                for tap in 1 ..< 5 {
                    let offset = tap * step
                    // Clamped to the edge rather than wrapped, so a bright thing at one side does not glow at the
                    // other.
                    let left = (row + max(0, x - offset)) * 3
                    let right = (row + min(width - 1, x + offset)) * 3
                    let weight = weights[tap]
                    red += (bright[left] + bright[right]) * weight
                    green += (bright[left + 1] + bright[right + 1]) * weight
                    blue += (bright[left + 2] + bright[right + 2]) * weight
                }
                across[at] = red
                across[at + 1] = green
                across[at + 2] = blue
            }
        }

        for y in 0 ..< height {
            for x in 0 ..< width {
                let at = (y * width + x) * 3
                var red = across[at] * weights[0]
                var green = across[at + 1] * weights[0]
                var blue = across[at + 2] * weights[0]
                for tap in 1 ..< 5 {
                    let offset = tap * step
                    let up = (max(0, y - offset) * width + x) * 3
                    let down = (min(height - 1, y + offset) * width + x) * 3
                    let weight = weights[tap]
                    red += (across[up] + across[down]) * weight
                    green += (across[up + 1] + across[down + 1]) * weight
                    blue += (across[up + 2] + across[down + 2]) * weight
                }
                light[at] += red * strength
                light[at + 1] += green * strength
                light[at + 2] += blue * strength
            }
        }
    }
}
