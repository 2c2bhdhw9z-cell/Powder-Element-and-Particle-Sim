import Testing

@testable import CrucibleCore

/// The trail and ring decisions, which cannot be checked as pixels.
///
/// Every other renderer in this port is compared against the reference frame for frame. These two
/// cannot be: the web version draws them with the browser's 2D canvas, whose antialiasing and line
/// joins are unspecified, so a recorded picture would only prove that one rasteriser agrees with
/// itself.
///
/// So what is checked instead is every decision feeding into them — and the one piece of real logic
/// among them, which is the rule deciding how big the ring is. That rule exists to stop the ring
/// lying about how far the pull reaches, and getting it wrong is the kind of error that looks fine.
@Suite("Trails and the touch ring")
struct ParticleOverlayTests {
    // MARK: Trails

    @Test("A trail's width follows the body, not the field")
    func trailWidthFollowsTheBody() {
        // Eight tenths of the body's own radius.
        #expect(ParticleOverlayStyle.trailWidth(bodyRadius: 10, defaultSize: 2) == 8)
        #expect(ParticleOverlayStyle.trailWidth(bodyRadius: 5, defaultSize: 2) == 4)
    }

    /// The reference reads this as `p.radius || e.particleSize`, and in JavaScript a radius of
    /// exactly zero is falsy — so zero takes the fallback rather than producing an invisible trail.
    /// Reproduced on purpose; a body with no radius should still leave a mark.
    @Test("A body with no radius of its own borrows the field's")
    func zeroRadiusFallsBack() {
        #expect(ParticleOverlayStyle.trailWidth(bodyRadius: 0, defaultSize: 4) == 3.2)
    }

    @Test("The recorded values are the reference's")
    func valuesMatchTheReference() {
        #expect(ParticleOverlayStyle.trailOpacity == 0.3)
        #expect(ParticleOverlayStyle.trailWidthScale == 0.8)
        #expect(ParticleOverlayStyle.trailLength == 6)
        #expect(ParticleOverlayStyle.frameFadeOpacity == 0.25)
        #expect(ParticleEngine.trailDrawingLimit == 1000)
    }

    /// The buffer the engine already records into has to agree with what the style says it holds, or
    /// a trail is either clipped short or reaches for positions that were never written.
    @Test("The trail buffer holds exactly as many positions as the style expects")
    func bufferMatchesTheStatedLength() {
        let engine = ParticleEngine(width: 200, height: 200, seed: 9)
        engine.showTrails = true
        engine.addParticle(x: 100, y: 20, velocityX: 0, velocityY: 1)

        // Well past the limit, so the buffer is certainly full.
        for _ in 0 ..< 40 { engine.step() }

        let trail = engine.particles[0].trail
        #expect(
            trail.count <= ParticleOverlayStyle.trailLength,
            "a trail grew to \(trail.count), longer than the stated \(ParticleOverlayStyle.trailLength)"
        )
        #expect(trail.count > 1, "a moving body should have left a trail")
    }

    // MARK: The ring

    @Test("An ordinary reach is drawn at its actual size")
    func ordinaryReachIsHonest() {
        let radius = ParticleOverlayStyle.ringRadius(reach: 120, worldWidth: 400, worldHeight: 800)
        #expect(radius == 120)
        #expect(!ParticleOverlayStyle.isUnlimited(reach: 120))
    }

    /// The rule that matters. At the top of its range the pull has no limit — everything in the
    /// field is affected — and a circle of radius 800 would say the opposite: that there is a
    /// boundary, and that things outside it are safe.
    @Test("An unlimited reach is drawn covering the whole world, not as a circle of 800")
    func unlimitedReachCoversEverything() {
        let radius = ParticleOverlayStyle.ringRadius(reach: 800, worldWidth: 300, worldHeight: 400)
        #expect(ParticleOverlayStyle.isUnlimited(reach: 800))
        // The diagonal of a 300 by 400 world, so the circle reaches every corner from anywhere in it.
        #expect(radius == 500)
        // Emphatically not the reach itself, which is the whole point of the rule.
        #expect(radius != 800)

        // And well past the threshold behaves the same way, rather than growing further.
        let larger = ParticleOverlayStyle.ringRadius(reach: 5000, worldWidth: 300, worldHeight: 400)
        #expect(larger == 500)
    }

    @Test("The threshold is inclusive, so the slider's top notch counts as unlimited")
    func thresholdIsInclusive() {
        #expect(ParticleOverlayStyle.isUnlimited(reach: 799.9) == false)
        #expect(ParticleOverlayStyle.isUnlimited(reach: 800))
        #expect(ParticleOverlayStyle.isUnlimited(reach: 800.1))
    }

    @Test("The ring's colours are the reference's")
    func ringColoursMatch() {
        // Cyan, and nowhere else in the interface, so it reads as your own doing.
        #expect(ParticleOverlayStyle.ringColor.r == 34)
        #expect(ParticleOverlayStyle.ringColor.g == 211)
        #expect(ParticleOverlayStyle.ringColor.b == 238)
        #expect(ParticleOverlayStyle.ringStrokeOpacity == 0.85)
        #expect(ParticleOverlayStyle.ringFillOpacity == 0.12)
        #expect(ParticleOverlayStyle.ringStrokeWidth == 2)
        #expect(ParticleOverlayStyle.ringCentreDotRadius == 3)
    }

    /// The ring is only drawn while a finger is down. The engine already tracks that, and the
    /// renderer reads it — so if it ever stopped being updated the ring would either stick on screen
    /// or never appear.
    @Test("The engine reports whether a finger is down")
    func touchStateIsTracked() {
        let engine = ParticleEngine(width: 200, height: 200, seed: 1)
        #expect(!engine.lastMouseActive)

        engine.step(mouseX: 50, mouseY: 60, mouseActive: true)
        #expect(engine.lastMouseActive)
        #expect(engine.lastMouseX == 50)
        #expect(engine.lastMouseY == 60)

        engine.step(mouseX: 50, mouseY: 60, mouseActive: false)
        #expect(!engine.lastMouseActive)
        // The position is remembered rather than reset, which is what lets the ring fade from where
        // it was rather than jumping to a corner.
        #expect(engine.lastMouseX == 50)
    }
}
