// Turning the way a phone is being held into which way things fall.
//
// Ported from web/src/sim/gyro.ts.
//
// ## Why the split falls here
//
// Reading the hardware is the app's job — it needs CoreMotion, which this module cannot
// import — but the *tuning* is not. Every number below was chosen by feel against the web
// version, and they are what decide whether tipping the phone behaves the way someone
// remembers. Those belong with the simulation, where they can be tested on any machine,
// rather than buried in a sensor callback that only runs on a device.
//
// So the app converts the hardware's reading into the same two angles a browser reports,
// and everything from there on happens here.

/// How the phone's attitude and jolts become gravity.
///
/// The angles are the two a browser's orientation event reports, in degrees:
///
///   - **beta** is the front-to-back tilt. Zero is flat on a table, ninety is upright
///     facing you, and it runs from −180 up to (not including) 180.
///   - **gamma** is the left-to-right roll, from −90 to 90.
///
/// ## The tuning, and why it looks odd
///
/// Gravity is neutral at a beta of 40° rather than at upright, and saturates 50° either
/// side. Hold the phone the way people actually hold a phone and material falls gently
/// downward; stand it upright and it falls at full strength; tip it *past* flat and
/// everything floats upward. Reading the arithmetic, "flat on the table means gravity points
/// up" looks like a mistake. It is not — it is what makes the control feel like tipping a
/// tray rather than like rotating a picture of one.
///
/// Roll saturates at only 32°, much sooner than the tilt does, because sideways gravity
/// needs far less travel to be useful and a wrist does not rotate comfortably.
public struct TiltMapping: Sendable, Equatable {
    // MARK: Output

    /// Sideways gravity for the powder world, −1 to 1.
    public private(set) var gravityX: Double = 0
    /// Vertical gravity for the powder world, −1 to 1. One is down.
    public private(set) var gravityY: Double = 1

    /// Sideways gravity for the particle field.
    public private(set) var particleGravityX: Double = 0
    /// Vertical gravity for the particle field.
    ///
    /// The resting value is deliberately not the powder world's. A field of free bodies under
    /// full gravity simply falls to the floor and stops being interesting, so it is given a
    /// fraction of it.
    public private(set) var particleGravityY: Double = 0.28

    /// Remaining energy from a physical jolt, 0 to 3.
    ///
    /// The powder world reads this to shake its contents loose. It is not gravity: a sharp
    /// knock should rattle a pile without changing which way down is.
    public private(set) var shake: Double = 0

    public init() {}

    // MARK: Tuning
    //
    // Named rather than left inline, because each is a decision someone might want to
    // reconsider and none of them is guessable from context.

    /// Roll at which sideways gravity reaches full strength.
    public static let rollSaturationDegrees = 32.0
    /// The tilt at which gravity is neutral — roughly how a phone is held while reading.
    public static let neutralTiltDegrees = 40.0
    /// How far either side of neutral the tilt has to travel to reach full strength.
    public static let tiltSaturationDegrees = 50.0
    /// The share of the powder world's gravity the particle field gets.
    public static let particleGravityScale = 0.42

    /// Acceleration, in metres per second squared, above which a movement counts as a jolt.
    ///
    /// Gravity alone is about 9.8, so this is a little over two g — brisk enough that setting
    /// the phone down firmly does not trigger it.
    public static let shakeThreshold = 22.0
    /// How much shake energy each unit of excess acceleration contributes.
    public static let shakeGain = 0.08
    /// The most shake energy that can accumulate.
    public static let shakeCeiling = 3.0
    /// What fraction of the shake survives each quiet reading.
    ///
    /// Tied to the *rate readings arrive*, not to time, exactly as the original is. At the
    /// sixty readings a second a browser delivers, this decays a full shake to nothing in
    /// about half a second. The app therefore asks CoreMotion for sixty readings a second, so
    /// that a jolt lasts as long as it does on the web — a faster update rate would make the
    /// same knock die away sooner, which is a real behaviour difference hiding in what looks
    /// like a performance setting.
    public static let shakeDecay = 0.86

    // MARK: Input

    /// Takes a new attitude.
    ///
    /// Call this only while tilt is enabled and unlocked. Locking deliberately freezes
    /// gravity where it is — that is the whole point of it, so that a world can be tipped and
    /// then examined without having to hold the phone still.
    public mutating func apply(betaDegrees: Double, gammaDegrees: Double) {
        // Not-a-number would otherwise propagate into gravity and from there into every
        // position in the world, which is unrecoverable. A reading that is not a number is
        // treated as the resting posture, which is what a browser reports for an axis its
        // hardware cannot measure.
        let gamma = gammaDegrees.isFinite ? gammaDegrees : 0
        let beta = betaDegrees.isFinite ? betaDegrees : 90

        let x = Self.clampToUnit(gamma / Self.rollSaturationDegrees)
        let y = Self.clampToUnit((beta - Self.neutralTiltDegrees) / Self.tiltSaturationDegrees)

        gravityX = x
        gravityY = y
        particleGravityX = x * Self.particleGravityScale
        particleGravityY = y * Self.particleGravityScale
    }

    /// Takes a new acceleration reading, including gravity, in metres per second squared.
    ///
    /// Keeps running while tilt is locked, because a lock is about holding *gravity* still.
    /// Shaking a locked world should still rattle it.
    public mutating func apply(accelerationX x: Double, y: Double, z: Double) {
        let magnitude = Self.magnitude(x, y, z)
        if magnitude > Self.shakeThreshold {
            shake = min(
                Self.shakeCeiling,
                shake + (magnitude - Self.shakeThreshold) * Self.shakeGain
            )
        } else {
            shake *= Self.shakeDecay
        }
    }

    /// Returns to the resting posture, for when tilt is switched off.
    ///
    /// Gravity goes back to straight down rather than staying wherever the phone happened to
    /// be pointing. Leaving it tilted means switching the feature off has no visible effect,
    /// which reads as the button being broken.
    public mutating func reset() {
        self = TiltMapping()
    }

    // MARK: Arithmetic

    private static func clampToUnit(_ value: Double) -> Double {
        // Ordered so that a value which is not a number becomes −1 rather than passing
        // through, matching how the original's nested min/max behaves.
        max(-1, min(1, value))
    }

    /// The length of a three-component vector.
    ///
    /// Written out rather than using a library hypotenuse, both because this module imports
    /// nothing and because the careful, overflow-avoiding version would answer differently.
    /// Accelerometer readings are single digits, nowhere near where that matters.
    private static func magnitude(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let safeX = x.isFinite ? x : 0
        let safeY = y.isFinite ? y : 0
        let safeZ = z.isFinite ? z : 0
        return (safeX * safeX + safeY * safeY + safeZ * safeZ).squareRoot()
    }
}
