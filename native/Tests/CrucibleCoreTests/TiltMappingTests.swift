import Testing

@testable import CrucibleCore

/// The tilt tuning, checked against the reference implementation's arithmetic.
///
/// There is no recorded comparison for this one, and there cannot be: the input is a sensor
/// reading rather than anything the simulation produces, so there is no shared world to run in
/// both engines. What *is* shared is the arithmetic, so these check the figures the web version
/// computes for the same angles — worked out from `web/src/sim/gyro.ts` by hand — plus the
/// handling of readings a browser would report but the original never considered.
@Suite("Tilt becomes gravity the same way the web version does")
struct TiltMappingTests {
    /// Where it sits before any reading arrives.
    ///
    /// Matters more than it looks: if tilt is switched on and the phone is perfectly still, no
    /// orientation event may arrive for some time, and the world has to behave sensibly
    /// meanwhile. Straight down at full strength is the only reasonable answer.
    @Test("At rest, gravity points straight down")
    func restingPosture() {
        let tilt = TiltMapping()
        #expect(tilt.gravityX == 0)
        #expect(tilt.gravityY == 1)
        #expect(tilt.particleGravityX == 0)
        // Deliberately not 1 * 0.42 — the field starts gentler than the tuning would give it.
        #expect(tilt.particleGravityY == 0.28)
        #expect(tilt.shake == 0)
    }

    @Test("Held upright, gravity is fully down")
    func uprightIsFullGravity() {
        var tilt = TiltMapping()
        tilt.apply(betaDegrees: 90, gammaDegrees: 0)
        // (90 - 40) / 50 = 1
        #expect(tilt.gravityY == 1)
        #expect(tilt.gravityX == 0)
        #expect(tilt.particleGravityY == 0.42)
    }

    @Test("Held at the neutral angle, nothing falls")
    func neutralAngleIsWeightless() {
        var tilt = TiltMapping()
        tilt.apply(betaDegrees: 40, gammaDegrees: 0)
        #expect(tilt.gravityY == 0)
        #expect(tilt.particleGravityY == 0)
    }

    /// The consequence that reads as a bug and is not: past flat, gravity inverts.
    @Test("Tipped forward past flat, things fall upward")
    func flatOnATableLiftsThings() {
        var tilt = TiltMapping()
        tilt.apply(betaDegrees: 0, gammaDegrees: 0)
        // (0 - 40) / 50 = -0.8
        #expect(tilt.gravityY == -0.8)
    }

    @Test("Rolling sideways pushes gravity sideways, and saturates sooner than tilt does")
    func rollMapsToSidewaysGravity() {
        var tilt = TiltMapping()
        tilt.apply(betaDegrees: 40, gammaDegrees: 16)
        // 16 / 32 = 0.5
        #expect(tilt.gravityX == 0.5)
        #expect(tilt.particleGravityX == 0.5 * 0.42)

        tilt.apply(betaDegrees: 40, gammaDegrees: -16)
        #expect(tilt.gravityX == -0.5)
    }

    @Test("Beyond the saturation angles, gravity stops growing")
    func gravityIsClamped() {
        var tilt = TiltMapping()
        tilt.apply(betaDegrees: 179, gammaDegrees: 89)
        #expect(tilt.gravityX == 1)
        #expect(tilt.gravityY == 1)

        tilt.apply(betaDegrees: -179, gammaDegrees: -89)
        #expect(tilt.gravityX == -1)
        #expect(tilt.gravityY == -1)
    }

    /// A browser reports `null` for an axis it cannot measure, which the original turns into
    /// zero for roll and ninety for tilt. Not-a-number is the equivalent here, and letting it
    /// through would put it into gravity and from there into every position in the world.
    @Test("An unreadable angle falls back to the resting posture rather than poisoning gravity")
    func unreadableAnglesFallBack() {
        var tilt = TiltMapping()
        tilt.apply(betaDegrees: .nan, gammaDegrees: .nan)
        #expect(tilt.gravityY == 1)
        #expect(tilt.gravityX == 0)
        #expect(!tilt.gravityX.isNaN)
        #expect(!tilt.gravityY.isNaN)

        tilt.apply(betaDegrees: .infinity, gammaDegrees: 0)
        #expect(tilt.gravityY == 1)
    }

    // MARK: Shake

    @Test("A gentle reading leaves no shake behind")
    func gentleMotionDoesNotShake() {
        var tilt = TiltMapping()
        // About one g, which is what lying still on a desk reads.
        tilt.apply(accelerationX: 0, y: 0, z: 9.81)
        #expect(tilt.shake == 0)
    }

    @Test("A jolt accumulates shake, up to a ceiling")
    func joltAccumulates() {
        var tilt = TiltMapping()
        // Magnitude 32, which is 10 above the threshold: 10 * 0.08 = 0.8
        tilt.apply(accelerationX: 32, y: 0, z: 0)
        #expect(abs(tilt.shake - 0.8) < 1e-12)

        // Repeated jolts pile up but cannot pass the ceiling.
        for _ in 0 ..< 20 { tilt.apply(accelerationX: 32, y: 0, z: 0) }
        #expect(tilt.shake == 3)
    }

    /// The decay is per *reading*, not per second. That is what ties the feel of a jolt to the
    /// sensor's update rate, and why the app has to ask for the same rate a browser delivers.
    @Test("Shake decays once per quiet reading")
    func shakeDecaysPerReading() {
        var tilt = TiltMapping()
        tilt.apply(accelerationX: 32, y: 0, z: 0)
        let afterJolt = tilt.shake

        tilt.apply(accelerationX: 0, y: 0, z: 0)
        #expect(abs(tilt.shake - afterJolt * 0.86) < 1e-12)

        // Sixty quiet readings — one second at a browser's rate — all but extinguishes it.
        for _ in 0 ..< 59 { tilt.apply(accelerationX: 0, y: 0, z: 0) }
        #expect(tilt.shake < 0.001)
    }

    @Test("An unreadable acceleration axis counts as zero rather than spreading")
    func unreadableAccelerationIsSurvivable() {
        var tilt = TiltMapping()
        tilt.apply(accelerationX: .nan, y: 32, z: .nan)
        #expect(!tilt.shake.isNaN)
        #expect(abs(tilt.shake - 0.8) < 1e-12)
    }

    // MARK: Switching off

    @Test("Switching tilt off returns gravity to straight down")
    func resetRestoresTheRestingPosture() {
        var tilt = TiltMapping()
        tilt.apply(betaDegrees: 0, gammaDegrees: 30)
        tilt.apply(accelerationX: 40, y: 0, z: 0)
        #expect(tilt.gravityY != 1)
        #expect(tilt.shake > 0)

        tilt.reset()
        // Not left pointing wherever the phone happened to be — that would make switching the
        // feature off look like it had not worked.
        #expect(tilt == TiltMapping())
        #expect(tilt.gravityY == 1)
        #expect(tilt.shake == 0)
    }
}
