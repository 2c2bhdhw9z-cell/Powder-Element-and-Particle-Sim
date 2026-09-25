import Foundation
import Testing

@testable import CrucibleCore

/// The colour ramps, the hand-made gradients, and the numbers that drive them.
///
/// These are worth testing carefully because a colour fault is not a crash — it is a field that
/// looks slightly wrong, and every interface fault this project has had was found by somebody
/// looking at the screen rather than by a test. The cheapest ones to catch are the ones with a
/// definite right answer: the ends of a ramp, the order of stops, what happens to a number that is
/// not a number.
struct ParticlePaletteTests {
    // MARK: - The named ramps

    @Test("Every ramp begins and ends on its own first and last colour")
    func rampEndsAreExact() {
        for palette in ParticlePalette.allCases {
            let stops = palette.stops
            #expect(stops.count >= 2, "\(palette.rawValue) needs at least two colours")
            #expect(
                palette.sample(0) == stops[0],
                "\(palette.rawValue) does not start on its first colour"
            )
            #expect(
                palette.sample(1) == stops[stops.count - 1],
                "\(palette.rawValue) does not end on its last colour"
            )
        }
    }

    @Test("A position outside the ramp is pulled back to the nearest end")
    func rampClampsOutOfRange() {
        for palette in ParticlePalette.allCases {
            #expect(palette.sample(-4) == palette.sample(0), "\(palette.rawValue) below nought")
            #expect(palette.sample(9) == palette.sample(1), "\(palette.rawValue) above one")
        }
    }

    @Test("A position that is not a number still produces a colour")
    func rampSurvivesUnusableNumbers() {
        // Reached from the drawing path with whatever the physics produced. A body whose velocity
        // has gone wrong asks for a position of not-a-number, and turning that into a byte traps —
        // which used to take the whole app down from inside the renderer, where the health report
        // that would have named the body could never be reached.
        for palette in ParticlePalette.allCases {
            #expect(palette.sample(.nan) == palette.sample(0))
            #expect(palette.sample(.infinity) == palette.sample(0))
            #expect(palette.sample(-.infinity) == palette.sample(0))
        }
    }

    @Test("The middle of a two-colour ramp is the plain average")
    func blendIsLinearInOrdinarySpace() {
        // Deliberately not corrected for brightness. Mixing black and white gives mid-grey, which
        // is *not* halfway in light — doing it properly makes every ramp read paler through the
        // middle, and the ramps were chosen by eye against this blend. The test exists so that if
        // somebody improves it, they find out here rather than by the field changing colour.
        let black = PackedColor(r: 0, g: 0, b: 0)
        let white = PackedColor(r: 255, g: 255, b: 255)
        let middle = ParticlePalette.sample(stops: [black, white], at: 0.5)
        #expect(middle.r == 128)
        #expect(middle.g == 128)
        #expect(middle.b == 128)
    }

    @Test("Stops are evenly spaced across the ramp")
    func rampStopsAreEvenlySpaced() {
        // Three colours means the middle one sits at exactly one half.
        let stops = [
            PackedColor(r: 10, g: 0, b: 0),
            PackedColor(r: 20, g: 0, b: 0),
            PackedColor(r: 30, g: 0, b: 0),
        ]
        #expect(ParticlePalette.sample(stops: stops, at: 0.5).r == 20)
        #expect(ParticlePalette.sample(stops: stops, at: 0.25).r == 15)
        #expect(ParticlePalette.sample(stops: stops, at: 0.75).r == 25)
    }

    @Test("No two ramps are the same")
    func rampsAreDistinct() {
        var seen: [String: String] = [:]
        for palette in ParticlePalette.allCases {
            let signature = (0 ..< 16)
                .map { palette.sample(Double($0) / 15).hexString }
                .joined(separator: ",")
            if let twin = seen[signature] {
                Issue.record("\(palette.rawValue) is identical to \(twin)")
            }
            seen[signature] = palette.rawValue
        }
    }

    // MARK: - Hand-made gradients

    @Test("Stops are sorted, clamped, and cleaned of what cannot be used")
    func stopsAreNormalized() {
        let messy = [
            ParticleGradientStop(position: 0.8, color: PackedColor(r: 1, g: 0, b: 0)),
            ParticleGradientStop(position: .nan, color: PackedColor(r: 2, g: 0, b: 0)),
            ParticleGradientStop(position: -3, color: PackedColor(r: 3, g: 0, b: 0)),
            ParticleGradientStop(position: 5, color: PackedColor(r: 4, g: 0, b: 0)),
            ParticleGradientStop(position: 0.2, color: PackedColor(r: 5, g: 0, b: 0)),
        ]
        let clean = ParticleGradientStop.normalized(messy)

        #expect(clean.count == 4, "the stop with an unusable position should be dropped")
        #expect(clean.map(\.position) == [0, 0.2, 0.8, 1])
        #expect(clean.map(\.color.r) == [3, 5, 1, 4])
    }

    @Test("Stops sharing a position keep the order they were given in")
    func normalizingIsStable() {
        // Swift's own sort makes no promise about ties, so the order is carried along and used to
        // break them. Without that, two stops dropped at the same place could swap on any given
        // run, and a saved gradient would come back looking different for no visible reason.
        let tied = (0 ..< 8).map {
            ParticleGradientStop(position: 0.5, color: PackedColor(r: UInt8($0), g: 0, b: 0))
        }
        let clean = ParticleGradientStop.normalized(tied)
        #expect(clean.map(\.color.r) == [0, 1, 2, 3, 4, 5, 6, 7])
    }

    @Test("Fewer than two stops is not a gradient")
    func oneStopIsNotAGradient() {
        #expect(!ParticleGradientStop.describesGradient([]))
        #expect(
            !ParticleGradientStop.describesGradient([
                ParticleGradientStop(position: 0.4, color: PackedColor(r: 1, g: 2, b: 3))
            ])
        )
        #expect(
            ParticleGradientStop.describesGradient([
                ParticleGradientStop(position: 0.4, color: PackedColor(r: 1, g: 2, b: 3)),
                ParticleGradientStop(position: 0.9, color: PackedColor(r: 4, g: 5, b: 6)),
            ])
        )
    }

    @Test("Beyond the end stops the end colour holds rather than running on")
    func gradientHoldsAtItsEnds() {
        // Continuing the last pair's slope past the end would drive a channel into its clamp and
        // read as a flat block of red or white, which looks like a fault rather than a choice.
        let stops = ParticleGradientStop.normalized([
            ParticleGradientStop(position: 0.3, color: PackedColor(r: 60, g: 0, b: 0)),
            ParticleGradientStop(position: 0.7, color: PackedColor(r: 200, g: 0, b: 0)),
        ])
        #expect(ParticleGradientStop.sample(normalized: stops, at: 0).r == 60)
        #expect(ParticleGradientStop.sample(normalized: stops, at: 0.3).r == 60)
        #expect(ParticleGradientStop.sample(normalized: stops, at: 0.5).r == 130)
        #expect(ParticleGradientStop.sample(normalized: stops, at: 0.7).r == 200)
        #expect(ParticleGradientStop.sample(normalized: stops, at: 1).r == 200)
    }

    @Test("Two stops at the same place do not divide by nothing")
    func coincidentStopsAreSafe() {
        let stops = ParticleGradientStop.normalized([
            ParticleGradientStop(position: 0, color: PackedColor(r: 10, g: 0, b: 0)),
            ParticleGradientStop(position: 0.5, color: PackedColor(r: 20, g: 0, b: 0)),
            ParticleGradientStop(position: 0.5, color: PackedColor(r: 30, g: 0, b: 0)),
            ParticleGradientStop(position: 1, color: PackedColor(r: 40, g: 0, b: 0)),
        ])
        let middle = ParticleGradientStop.sample(normalized: stops, at: 0.5)
        #expect(middle.r == 20, "the first stop at that position should win")
    }

    // MARK: - The whole description

    @Test("A gradient beats a two-colour fade, which beats the named ramp")
    func precedenceIsGradientThenFadeThenRamp() {
        // Precedence rather than a mode switch, because that is how the editor behaves: dropping a
        // second stop in should start using the gradient without also hunting for a toggle.
        var spec = ParticlePaletteSpec(palette: .ice)
        #expect(spec.sample(0) == ParticlePalette.ice.stops[0], "with nothing else set, the ramp")

        spec.fadeFrom = PackedColor(r: 1, g: 1, b: 1)
        spec.fadeTo = PackedColor(r: 9, g: 9, b: 9)
        #expect(spec.sample(0) == PackedColor(r: 1, g: 1, b: 1), "a fade beats the ramp")

        spec.stops = [
            ParticleGradientStop(position: 0, color: PackedColor(r: 70, g: 0, b: 0)),
            ParticleGradientStop(position: 1, color: PackedColor(r: 80, g: 0, b: 0)),
        ]
        #expect(spec.sample(0) == PackedColor(r: 70, g: 0, b: 0), "a gradient beats a fade")
    }

    @Test("Two identical fade colours are not a fade")
    func equalFadeColoursFallThroughToTheRamp() {
        var spec = ParticlePaletteSpec(palette: .ember)
        spec.fadeFrom = PackedColor(r: 33, g: 33, b: 33)
        spec.fadeTo = PackedColor(r: 33, g: 33, b: 33)
        #expect(spec.sample(0.5) == ParticlePalette.ember.sample(0.5))
    }

    @Test("A white tint changes nothing and a grey tint dims everything")
    func tintMultiplies() {
        var spec = ParticlePaletteSpec(palette: .mono)
        let untinted = spec.sample(1)
        spec.tint = PackedColor(r: 255, g: 255, b: 255)
        #expect(spec.sample(1) == untinted, "white is no tint at all")

        spec.tint = PackedColor(r: 128, g: 255, b: 0)
        let tinted = spec.sample(1)
        #expect(tinted.r == UInt8((Double(untinted.r) * 128 / 255).rounded()))
        #expect(tinted.g == untinted.g)
        #expect(tinted.b == 0)
    }

    @Test("A baked table matches sampling the palette directly")
    func bakedTableAgreesWithSampling() {
        // The drawing path reads the table and the tests read the sampler; if they disagree, what
        // is verified is not what is drawn.
        for palette in ParticlePalette.allCases {
            let spec = ParticlePaletteSpec(palette: palette, tint: PackedColor(r: 200, g: 255, b: 90))
            let table = spec.bakeLookup()
            #expect(table.count == ParticlePaletteSpec.lookupSize)
            for index in [0, 1, 64, 127, 128, 200, 254, 255] {
                let position = Double(index) / Double(table.count - 1)
                #expect(
                    table[index] == spec.sample(position).packedRGBA,
                    "\(palette.rawValue), entry \(index)"
                )
            }
        }
    }

    @Test("A baked table is opaque from end to end")
    func bakedTableIsOpaque() {
        // A transparent entry would draw nothing, and the fault would look like missing particles
        // rather than like a colour problem.
        for palette in ParticlePalette.allCases {
            let table = ParticlePaletteSpec(palette: palette).bakeLookup()
            for entry in table {
                #expect(PackedColor(packedRGBA: entry).a == 255, "\(palette.rawValue)")
            }
        }
    }

    // MARK: - Pulling a palette out of a picture

    @Test("The most common colours in a picture come back first")
    func imageColoursAreRankedByPopularity() {
        let red = PackedColor(r: 250, g: 10, b: 10).packedRGBA
        let blue = PackedColor(r: 10, g: 10, b: 250).packedRGBA
        let green = PackedColor(r: 10, g: 250, b: 10).packedRGBA
        var pixels: [UInt32] = []
        pixels.append(contentsOf: repeatElement(blue, count: 5))
        pixels.append(contentsOf: repeatElement(red, count: 20))
        pixels.append(contentsOf: repeatElement(green, count: 12))

        let found = ParticlePaletteSpec.colors(inImage: pixels, count: 3)
        #expect(found.count == 3)
        #expect(found[0].r > 200 && found[0].g < 50, "red is commonest")
        #expect(found[1].g > 200, "green next")
        #expect(found[2].b > 200, "blue last")
    }

    @Test("Near-identical shades count as one colour")
    func nearbyShadesAreLumpedTogether() {
        // The whole point of throwing away the low bits: a photograph of a red wall is one colour,
        // not four thousand.
        var pixels: [UInt32] = []
        for offset in 0 ..< 8 {
            pixels.append(PackedColor(r: UInt8(240 + offset), g: 4, b: 4).packedRGBA)
        }
        pixels.append(contentsOf: repeatElement(PackedColor(r: 4, g: 4, b: 240).packedRGBA, count: 3))

        let found = ParticlePaletteSpec.colors(inImage: pixels, count: 4)
        #expect(found.count == 2, "eight shades of red plus one blue is two colours")
        #expect(found[0].r > 200, "the reds, averaged, come first")
    }

    @Test("Fully transparent pixels are ignored")
    func transparentPixelsAreSkipped() {
        // A cut-out on a transparent background would otherwise come back as a palette whose
        // commonest colour is invisible.
        var pixels = [UInt32](repeating: PackedColor(r: 0, g: 0, b: 0, a: 0).packedRGBA, count: 500)
        pixels.append(contentsOf: repeatElement(PackedColor(r: 90, g: 180, b: 40).packedRGBA, count: 6))

        let found = ParticlePaletteSpec.colors(inImage: pixels, count: 3)
        #expect(found.count == 1)
        #expect(found[0].g > 150)
    }

    @Test("An empty picture yields no colours rather than a black one")
    func emptyImageYieldsNothing() {
        #expect(ParticlePaletteSpec.colors(inImage: [], count: 5).isEmpty)
        #expect(ParticlePaletteSpec.colors(inImage: [1, 2, 3], count: 0).isEmpty)
    }

    @Test("A picture becomes a gradient with evenly spaced stops")
    func imageBecomesAGradient() {
        var pixels: [UInt32] = []
        pixels.append(contentsOf: repeatElement(PackedColor(r: 240, g: 0, b: 0).packedRGBA, count: 9))
        pixels.append(contentsOf: repeatElement(PackedColor(r: 0, g: 240, b: 0).packedRGBA, count: 6))
        pixels.append(contentsOf: repeatElement(PackedColor(r: 0, g: 0, b: 240).packedRGBA, count: 3))

        let spec = ParticlePaletteSpec.fromImage(pixels, stopCount: 3)
        #expect(spec.stops.count == 3)
        #expect(spec.stops.map(\.position) == [0, 0.5, 1])
        #expect(ParticleGradientStop.describesGradient(spec.stops))
    }

    @Test("The same picture always gives the same palette")
    func imagePaletteIsRepeatable() {
        // Buckets are ordered by population, and ties broken by which colour was seen first, so a
        // picture with two equally common colours does not hand back a different gradient each
        // time it is opened.
        var pixels: [UInt32] = []
        for _ in 0 ..< 10 {
            pixels.append(PackedColor(r: 200, g: 20, b: 20).packedRGBA)
            pixels.append(PackedColor(r: 20, g: 20, b: 200).packedRGBA)
        }
        let first = ParticlePaletteSpec.colors(inImage: pixels, count: 2)
        for _ in 0 ..< 6 {
            #expect(ParticlePaletteSpec.colors(inImage: pixels, count: 2) == first)
        }
    }

    // MARK: - Saving and loading

    @Test("A palette description survives being written down and read back")
    func specRoundTrips() throws {
        let spec = ParticlePaletteSpec(
            palette: .plasma,
            stops: [
                ParticleGradientStop(position: 0.1, color: PackedColor(r: 1, g: 2, b: 3)),
                ParticleGradientStop(position: 0.9, color: PackedColor(r: 4, g: 5, b: 6)),
            ],
            fadeFrom: PackedColor(r: 7, g: 8, b: 9),
            fadeTo: PackedColor(r: 10, g: 11, b: 12),
            tint: PackedColor(r: 13, g: 14, b: 15)
        )
        let encoded = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(ParticlePaletteSpec.self, from: encoded)
        #expect(decoded == spec)
    }
}
