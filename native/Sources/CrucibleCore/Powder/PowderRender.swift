/// Turning the grid into pixels.
///
/// ## Why this lives in the engine and not in the Metal code
///
/// Deciding what colour a cell should be is not graphics work — it is a pile of rules about
/// grain texture, mist blending, heat tinting and overlay modes, every one of which can be
/// got subtly wrong in a way that looks plausible. Kept here it compiles on any machine, is
/// covered by the same cell-by-cell comparison against the web engine as the physics, and
/// cannot drift.
///
/// What is left for Metal is genuinely just display: hand it these bytes as a texture and
/// stretch them over the screen. No colour decisions, nothing to verify.
///
/// The output is one 32-bit word per cell, laid out red, green, blue, alpha in memory. That
/// is what Metal's `rgba8Unorm` textures expect and also what a `Uint32Array` view over the
/// browser's image data produces, so both renderers consume the identical words.

/// How the grid should be coloured.
public enum PowderOverlayMode: String, Sendable, CaseIterable, Codable {
    /// Each cell in its element's own colour.
    case normal
    /// A heat map, ignoring what the cells are made of.
    ///
    /// Spelled `temp` on the wire, matching the web implementation, so a saved preference
    /// means the same thing in both.
    case temperature = "temp"
    /// Element colours, tinted toward red where hot and blue where cold.
    case temperatureOverlay = "temp_overlay"
    /// Each cell shaded by how heavy its element is.
    case density
}

extension PowderEngine {
    /// The lab background, behind everything. `#0a0a0c`.
    static let backgroundRed = 10
    static let backgroundGreen = 10
    static let backgroundBlue = 12

    /// Packs four channels the way the texture expects.
    @inline(__always)
    private static func pack(_ r: Int, _ g: Int, _ b: Int) -> UInt32 {
        UInt32(UInt8(clamping: r)) | UInt32(UInt8(clamping: g)) << 8
            | UInt32(UInt8(clamping: b)) << 16 | 0xFF00_0000
    }

    /// Draws the grid into `pixels`, which must hold at least ``cellCount`` words.
    ///
    /// One word per cell, row by row from the top. Nothing is allocated, so this is safe to
    /// call every frame from a display loop.
    public func render(into pixels: UnsafeMutablePointer<UInt32>, overlay: PowderOverlayMode = .normal) {
        guard cellCount > 0 else { return }
        let background = Self.pack(Self.backgroundRed, Self.backgroundGreen, Self.backgroundBlue)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = y * width + x
                let id = type[i]
                let temp = Double(temperature[i])

                switch overlay {
                case .temperature:
                    pixels[i] = Self.heatMap(temp)
                    continue

                case .density:
                    if id == Element.empty {
                        pixels[i] = background
                    } else {
                        // Scaled over nought to twenty, which covers everything from gas to
                        // the heaviest metal.
                        let density = elements[id].density
                        let normalised = min(1, max(0, density / 20))
                        pixels[i] = Self.pack(
                            Int((normalised * 255).rounded(.down)),
                            Int(((1 - normalised) * 200).rounded(.down)),
                            180
                        )
                    }
                    continue

                case .normal, .temperatureOverlay:
                    break
                }

                if id == Element.empty {
                    // Air is only drawn when it is notably hotter or colder than the room,
                    // and only in the tinted mode, so that a hot draught is visible.
                    if overlay == .temperatureOverlay, abs(temp - 20) > 10 {
                        pixels[i] = Self.airGlow(temp)
                    } else {
                        pixels[i] = background
                    }
                    continue
                }

                let physics = elements[id]
                var red = Int(physics.color.r)
                var green = Int(physics.color.g)
                var blue = Int(physics.color.b)

                // Speckling, for solid grains only.
                //
                // The noise is keyed to the cell's position, so a grain that stays put keeps
                // its speckle. Liquids, gases, plasma and energy move somewhere new every
                // tick, so keying their noise to where they happen to be makes them glitter
                // frantically frame to frame — they are drawn flat instead.
                let isGrain = physics.state == .solidMovable || physics.state == .solidFixed
                if isGrain, physics.colorVariation > 0 {
                    let jitter = grainJitter(x: x, y: y, variation: physics.colorVariation)
                    red = min(255, max(0, red + Int((Double(red) * jitter).rounded(.down))))
                    green = min(255, max(0, green + Int((Double(green) * jitter).rounded(.down))))
                    blue = min(255, max(0, blue + Int((Double(blue) * jitter).rounded(.down))))
                }

                // Gases and plasma are mist rather than solid colour, so they are blended
                // into the background. Steam is the thinnest, then smoke, then everything
                // else.
                if physics.state == .gas || physics.state == .plasma {
                    let alpha: Double = id == Element.steam ? 0.42 : (id == Element.smoke ? 0.5 : 0.62)
                    red = Int(JS.round(Double(red) * alpha + Double(Self.backgroundRed) * (1 - alpha)))
                    green = Int(JS.round(Double(green) * alpha + Double(Self.backgroundGreen) * (1 - alpha)))
                    blue = Int(JS.round(Double(blue) * alpha + Double(Self.backgroundBlue) * (1 - alpha)))
                }

                if overlay == .temperatureOverlay {
                    if temp > 100 {
                        let heat = min(0.7, (temp - 100) / 1000)
                        red = min(255, Int((Double(red) * (1 - heat) + 255 * heat).rounded(.down)))
                        green = min(255, Int((Double(green) * (1 - heat) + 120 * heat).rounded(.down)))
                        blue = Int((Double(blue) * (1 - heat)).rounded(.down))
                    } else if temp < -10 {
                        let cold = min(0.6, abs(temp + 10) / 150)
                        blue = min(255, Int((Double(blue) * (1 - cold) + 255 * cold).rounded(.down)))
                        green = min(255, Int((Double(green) * (1 - cold) + 200 * cold).rounded(.down)))
                    }
                }

                // A fan shows which way it is pointing, which it stores in its lifetime.
                if id == Element.fan {
                    switch Int(life[i]) % 4 {
                    case 0: (red, green, blue) = (180, 200, 220)
                    case 1: (red, green, blue) = (120, 150, 200)
                    case 2: (red, green, blue) = (200, 140, 120)
                    default: (red, green, blue) = (220, 220, 180)
                    }
                }

                pixels[i] = Self.pack(red, green, blue)
            }
        }
    }

    /// The speckle applied to one grain, as a fraction of its own brightness.
    private func grainJitter(x: Int, y: Int, variation: Double) -> Double {
        switch textureMode {
        case .diagonalMatrix:
            // A repeating diagonal pattern, which reads as a regular crystalline grain.
            return Double(((x * 3 + y * 7) % 19) - 9) * (variation / 100)

        case .naturalGrain:
            // A hash of the position. Integer arithmetic only: no trigonometry, and nothing
            // that changes between frames, so the speckle is fixed to the cell rather than
            // shimmering.
            let hash = (UInt32(truncatingIfNeeded: x &* 1_597_334_677))
                ^ (UInt32(truncatingIfNeeded: y &* 3_812_015_801))
            let noise = (Double(hash % 100) - 50) / 50
            return noise * (variation / 100)

        case .organicFlow:
            // A slow travelling wave, so the surface looks alive. The one mode that
            // deliberately changes with time.
            let wave = jsSin(Double(x) * 0.08 + Double(y) * 0.08 + Double(frameCount) * 0.05)
            return wave * (variation / 100)

        case .flat:
            return 0
        }
    }

    /// The heat map: deep blue through teal, green, yellow and orange to white.
    private static func heatMap(_ temp: Double) -> UInt32 {
        var r = 0
        var g = 0
        var b = 0
        if temp < 0 {
            let n = min(1, abs(temp) / 100)
            b = Int((150 + n * 105).rounded(.down))
            g = Int((n * 100).rounded(.down))
        } else if temp <= 40 {
            let n = temp / 40
            g = Int((100 + n * 100).rounded(.down))
            b = Int(((1 - n) * 150).rounded(.down))
        } else if temp <= 200 {
            let n = (temp - 40) / 160
            r = Int((n * 255).rounded(.down))
            g = Int((200 - n * 50).rounded(.down))
        } else if temp <= 800 {
            let n = (temp - 200) / 600
            r = 255
            g = Int((150 - n * 100).rounded(.down))
            b = Int((n * 30).rounded(.down))
        } else {
            let n = min(1, (temp - 800) / 2200)
            r = 255
            g = Int((50 + n * 205).rounded(.down))
            b = Int((30 + n * 225).rounded(.down))
        }
        return pack(r, g, b)
    }

    /// The faint glow shown for air that is much hotter or colder than the room.
    private static func airGlow(_ temp: Double) -> UInt32 {
        var r = backgroundRed
        var g = backgroundGreen
        var b = backgroundBlue
        if temp > 50 {
            let n = min(1, (temp - 50) / 800)
            r = Int((10 + n * 180).rounded(.down))
            g = Int((10 + n * 40).rounded(.down))
        } else if temp < 0 {
            let n = min(1, abs(temp) / 100)
            b = Int((12 + n * 180).rounded(.down))
            g = Int((10 + n * 80).rounded(.down))
        }
        return pack(r, g, b)
    }

    /// Draws the grid into an array, for callers with no buffer of their own.
    ///
    /// Allocates, so the display loop should use the pointer form above instead.
    public func renderToArray(overlay: PowderOverlayMode = .normal) -> [UInt32] {
        var pixels = [UInt32](repeating: 0, count: cellCount)
        pixels.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress { render(into: base, overlay: overlay) }
        }
        return pixels
    }
}
