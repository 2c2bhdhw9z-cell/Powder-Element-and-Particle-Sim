import Testing

@testable import CrucibleCore

/// A picture of the field that looks like the field.
///
/// The engine's older renderer puts one pixel down per body, which is right for comparing against the web engine and
/// useless as a picture: the day's field came out as a black rectangle with two hundred specks in it. This is the
/// picture meant for looking at, so what it is held to is the things that made the old one useless — that a body is as
/// wide as it really is, that overlapping light adds up, and that a field with something in it is not mostly empty.
@Suite("A picture of the field")
struct ParticleFieldPictureTests {
    private let background = ParticleEngine.backgroundColor

    private func bare(_ width: Double = 60, _ height: Double = 40) -> ParticleEngine {
        let engine = ParticleEngine(width: width, height: height, seed: 5)
        engine.clear()
        return engine
    }

    private func brightness(_ pixel: UInt32) -> Int {
        Int(pixel & 0xFF) + Int((pixel >> 8) & 0xFF) + Int((pixel >> 16) & 0xFF)
    }

    @Test("An empty field is the background and nothing else")
    func emptyIsEmpty() {
        let pixels = bare().fieldPicture()
        #expect(pixels.count == 60 * 40)
        #expect(pixels.allSatisfy { $0 == background })
    }

    @Test("A body is as wide as the body is")
    func widthFollowsTheBody() {
        // Two bodies, one four times the other's radius, nothing else in the field.
        let engine = bare(200, 60)
        _ = engine.addParticle(x: 50, y: 30, velocityX: 0, velocityY: 0, radius: 2, mass: 1,
                           color: PackedColor(r: 255, g: 255, b: 255), isFixed: true)
        _ = engine.addParticle(x: 150, y: 30, velocityX: 0, velocityY: 0, radius: 8, mass: 1,
                           color: PackedColor(r: 255, g: 255, b: 255), isFixed: true)
        let pixels = engine.fieldPicture()

        /// How many lit pixels sit in one half of the picture.
        func lit(from: Int, to: Int) -> Int {
            var count = 0
            for y in 0 ..< 60 {
                for x in from ..< to where pixels[y * 200 + x] != background { count += 1 }
            }
            return count
        }
        let small = lit(from: 0, to: 100)
        let large = lit(from: 100, to: 200)
        #expect(small > 0, "a small body left no mark")
        // Four times the radius is sixteen times the area. Not asserted exactly — a disc of pixels is a rough disc —
        // but the ratio has to be in the right country, and a single shared size would make it one.
        #expect(large > small * 8, "a big body was drawn no bigger than a small one")
        #expect(large < small * 30)
    }

    @Test("Light adds up where bodies overlap")
    func overlapAddsUp() {
        // The point of gathering light before squeezing it into bytes: a crowd's middle is brighter than its edge, which
        // is what makes a galaxy's core white.
        let one = bare(40, 40)
        _ = one.addParticle(x: 20, y: 20, velocityX: 0, velocityY: 0, radius: 6, mass: 1,
                        color: PackedColor(r: 60, g: 60, b: 60), isFixed: true)
        let alone = one.fieldPicture()[20 * 40 + 20]

        let several = bare(40, 40)
        for _ in 0 ..< 4 {
            _ = several.addParticle(x: 20, y: 20, velocityX: 0, velocityY: 0, radius: 6, mass: 1,
                                color: PackedColor(r: 60, g: 60, b: 60), isFixed: true)
        }
        let piled = several.fieldPicture()[20 * 40 + 20]
        #expect(brightness(piled) > brightness(alone), "four bodies in one place were no brighter than one")
    }

    @Test("A dot is round and fades at its edge")
    func dotsAreRoundAndSoft() {
        let engine = bare(40, 40)
        _ = engine.addParticle(x: 20, y: 20, velocityX: 0, velocityY: 0, radius: 8, mass: 1,
                           color: PackedColor(r: 200, g: 200, b: 200), isFixed: true)
        let pixels = engine.fieldPicture()
        let middle = brightness(pixels[20 * 40 + 20])
        let partWay = brightness(pixels[20 * 40 + 26])
        let justInside = brightness(pixels[20 * 40 + 27])
        #expect(middle > partWay)
        #expect(partWay > justInside, "the dot had a hard edge rather than fading")
        // Round, not square: the corner of the dot's box is empty while its side is not.
        #expect(pixels[(20 - 7) * 40 + 13] == background, "the dot was drawn square")
        #expect(pixels[20 * 40 + 14] != background)
    }

    @Test("Enlarging makes a bigger picture of the same scene, not a sparser one")
    func enlargingFillsProportionally() {
        let engine = bare(50, 50)
        for i in 0 ..< 20 {
            _ = engine.addParticle(x: Double(i * 2 + 5), y: 25, velocityX: 0, velocityY: 0, radius: 3, mass: 1,
                               color: PackedColor(r: 180, g: 120, b: 90), isFixed: true)
        }
        let small = engine.fieldPicture()
        let big = engine.fieldPicture(scale: 4)
        #expect(small.count == 2_500)
        #expect(big.count == 2_500 * 16)
        let smallShare = Double(small.count { $0 != background }) / Double(small.count)
        let bigShare = Double(big.count { $0 != background }) / Double(big.count)
        // The same fraction of the picture covered, within a bit: dots grew with it. If the dots had stayed one pixel,
        // the enlarged picture would be a sixteenth as full.
        #expect(bigShare > smallShare * 0.7, "enlarging thinned the picture out")
        #expect(bigShare < smallShare * 1.4)
    }

    @Test("The crowd is drawn as well as the named bodies")
    func theCrowdIsDrawn() {
        // A field's half-million-strong crowd lives apart from its named bodies, and leaving it out of the picture
        // would mean the busiest scenes came out the emptiest.
        let engine = bare(80, 80)
        let withoutCrowd = engine.fieldPicture().count { $0 != background }
        #expect(withoutCrowd == 0)
        engine.spawnSwarmScene(count: 4_000)
        let withCrowd = engine.fieldPicture().count { $0 != background }
        #expect(withCrowd > 500, "the crowd left nothing in the picture")
    }

    @Test("A glow spreads light past the bodies it came from")
    func glowSpreads() {
        let engine = bare(60, 60)
        _ = engine.addParticle(x: 30, y: 30, velocityX: 0, velocityY: 0, radius: 3, mass: 1,
                           color: PackedColor(r: 255, g: 255, b: 255), isFixed: true)
        let plain = engine.fieldPicture(glowing: false)
        engine.glow.strength = 2
        let glowing = engine.fieldPicture()
        #expect(glowing.count { $0 != background } > plain.count { $0 != background },
                "turning the glow on lit nothing extra")
        // Well clear of the body, where only a glow reaches.
        let away = 30 * 60 + 44
        #expect(plain[away] == background)
        #expect(glowing[away] != background, "the glow did not reach past the body")
        // And it follows the setting rather than being decided here.
        engine.glow.strength = 0
        #expect(engine.fieldPicture()[away] == background)
    }

    @Test("A dim field does not glow, however bright the setting")
    func dimThingsDoNotGlow() {
        // The threshold exists so that a wash of dim bodies does not lift the black and flatten the picture.
        let engine = bare(60, 60)
        engine.glow = ParticleGlow(strength: 3, spread: 3, threshold: 0.9)
        _ = engine.addParticle(x: 30, y: 30, velocityX: 0, velocityY: 0, radius: 3, mass: 1,
                           color: PackedColor(r: 30, g: 30, b: 30), isFixed: true)
        #expect(engine.fieldPicture()[30 * 60 + 46] == background, "something far too dim to glow glowed")
    }

    @Test("Colours come from the one place that decides them")
    func coloursAreNotDecidedTwice() {
        // Not "the colour is right" — "the colour is the same one the screen would use". A second set of colour rules
        // in the picture path is the thing this is guarding against.
        let engine = bare(40, 40)
        _ = engine.addParticle(x: 20, y: 20, velocityX: 0, velocityY: 0, radius: 5, mass: 1,
                           color: PackedColor(r: 210, g: 40, b: 120), isFixed: true)
        let wanted = engine.renderColor(of: engine.particles[0], density: nil)
        let middle = engine.fieldPicture()[20 * 40 + 20]
        // The middle of a lone dot is its own colour at full strength, plus the background it sits on.
        #expect(Int(middle & 0xFF) >= Int(wanted.r) - 2)
        #expect(Int((middle >> 8) & 0xFF) >= Int(wanted.g) - 2)
        #expect(Int((middle >> 16) & 0xFF) >= Int(wanted.b) - 2)
        #expect(Int(middle & 0xFF) > Int((middle >> 8) & 0xFF), "the channels came out in the wrong order")
    }

    @Test("A body at an impossible place is left out rather than piled in the corner")
    func brokenBodiesAreSkipped() {
        let engine = bare(40, 40)
        _ = engine.addParticle(x: .nan, y: 20, velocityX: 0, velocityY: 0, radius: 5, mass: 1,
                           color: PackedColor(r: 255, g: 255, b: 255), isFixed: true)
        _ = engine.addParticle(x: 20, y: .infinity, velocityX: 0, velocityY: 0, radius: 5, mass: 1,
                           color: PackedColor(r: 255, g: 255, b: 255), isFixed: true)
        #expect(engine.fieldPicture().allSatisfy { $0 == background },
                "a body with no real position was drawn somewhere")
    }

    @Test("The day's shared field comes out as something to look at")
    func theDailyFieldIsNotBlack() {
        // The check that would have caught the original fault. A near-empty picture passes every test about pixels and
        // fails the only thing that matters.
        let engine = ParticleEngine(width: 220, height: 470, seed: 1)
        DailyWorld.applyParticle(forDay: "2026-12-25", to: engine)
        for _ in 0 ..< 240 { engine.step() }
        let pixels = engine.fieldPicture(scale: 3)
        let lit = pixels.count { $0 != background }
        #expect(lit > pixels.count / 100, "the day's field came out all but black")
        // And it is not a flat wash either — there is a bright part and a dim part.
        let brightest = pixels.map(brightness).max() ?? 0
        #expect(brightest > 400)
    }

    @Test("A field too big to draw is refused rather than attempted")
    func absurdSizesAreRefused() {
        let engine = ParticleEngine(width: 9_000, height: 9_000, seed: 1)
        #expect(engine.fieldPicture().isEmpty)
        #expect(engine.pngBytes() == nil)
        #expect(ParticleEngine(width: 0, height: 0, seed: 1).fieldPicture().isEmpty)
    }
}
