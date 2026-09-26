/// More than one finger on the field at once, and the kaleidoscope built on top of it.
///
/// ## Why the engine holds a list rather than the app sending several touches
///
/// Because two different features want the same thing. Ten fingers means ten real touches, each doing what the
/// chosen tool does. A kaleidoscope means one real touch copied several times round the middle of the world, so
/// that every stroke comes out as a snowflake. Those are the same thing to the physics — several places where
/// the tool is being applied this moment — so there is one list, and the app fills it either from the extra
/// touches on the glass or from the kaleidoscope's reflections, or both.
///
/// Empty by default, and everything that reads it is skipped while it is empty, so a field with one finger on it
/// behaves exactly as it did before this existed.
public struct ParticleFingerPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double
    /// How far into the box, for 3D. Ignored on a flat field.
    public var z: Double

    public init(x: Double, y: Double, z: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
    }
}

extension ParticleEngine {
    /// Extra places the tool is being applied this moment, besides the main finger.
    ///
    /// Set by the app each moment, from the other fingers on the glass. Cleared by the app, not here: the engine
    /// has no way to know that a finger has been lifted.
    public var extraFingers: [ParticleFingerPoint] {
        get { storedExtraFingers }
        set { storedExtraFingers = newValue.count > Self.fingerLimit ? Array(newValue.prefix(Self.fingerLimit)) : newValue }
    }

    /// How many extra places are allowed at once.
    ///
    /// Twelve: ten fingers is the most anybody has, and the kaleidoscope's folds go up to twelve. Capped because
    /// each one costs another sweep of the crowd, and a mistake in the app that appended without clearing would
    /// otherwise slow the field to a halt rather than merely looking wrong.
    public static let fingerLimit = 12

    /// How many times a stroke is copied round the middle of the world. One is off.
    ///
    /// At six, a single line drawn anywhere comes out as a six-pointed snowflake, because the same push is
    /// applied at six places turned evenly about the centre. Every fold is a real application of the tool, so a
    /// kaleidoscope made of Push genuinely blows six holes and one made of Paint colours six arcs.
    public var kaleidoscopeFolds: Int {
        get { storedKaleidoscopeFolds }
        set { storedKaleidoscopeFolds = max(1, min(12, newValue)) }
    }

    /// Whether every other fold is also mirrored, which is what makes a true kaleidoscope rather than a pinwheel.
    ///
    /// A pinwheel turns the stroke round and round, so the pattern has a direction and looks like it is spinning.
    /// Mirroring every other copy gives the pattern a line of symmetry through each fold, which is what the
    /// inside of a kaleidoscope actually does and what makes the result read as a snowflake.
    public var kaleidoscopeMirrors: Bool {
        get { storedKaleidoscopeMirrors }
        set { storedKaleidoscopeMirrors = newValue }
    }

    /// The places the kaleidoscope copies a finger to, given where the finger is.
    ///
    /// The main finger is not included: it is applied by the ordinary path, and this is what is applied on top.
    func kaleidoscopePoints(fingerX: Double, fingerY: Double, fingerZ: Double) -> [ParticleFingerPoint] {
        let folds = storedKaleidoscopeFolds
        guard folds > 1, fingerX.isFinite, fingerY.isFinite else { return [] }
        let centreX = width * 0.5
        let centreY = height * 0.5
        let dx = fingerX - centreX
        let dy = fingerY - centreY
        var points: [ParticleFingerPoint] = []
        points.reserveCapacity(folds - 1)
        for fold in 1 ..< folds {
            let turn = Double(fold) / Double(folds) * 6.283185307179586
            let cosTurn = jsCos(turn)
            let sinTurn = jsSin(turn)
            // Mirrored on the odd folds, which puts a line of symmetry through each one.
            let acrossward = storedKaleidoscopeMirrors && fold % 2 == 1 ? -dx : dx
            points.append(
                ParticleFingerPoint(
                    x: centreX + acrossward * cosTurn - dy * sinTurn,
                    y: centreY + acrossward * sinTurn + dy * cosTurn,
                    z: fingerZ
                )
            )
        }
        return points
    }

    /// Every extra place the tool is applied this moment: the app's other fingers, plus the kaleidoscope's copies
    /// of the main one.
    func activeExtraFingers(fingerX: Double, fingerY: Double, fingerZ: Double) -> [ParticleFingerPoint] {
        let mirrored = kaleidoscopePoints(fingerX: fingerX, fingerY: fingerY, fingerZ: fingerZ)
        if storedExtraFingers.isEmpty { return mirrored }
        if mirrored.isEmpty { return storedExtraFingers }
        // Each of the app's own fingers is folded too, so a kaleidoscope drawn with two fingers is still a
        // kaleidoscope rather than one snowflake and one loose scribble.
        var all = storedExtraFingers
        all.append(contentsOf: mirrored)
        for point in storedExtraFingers {
            all.append(contentsOf: kaleidoscopePoints(fingerX: point.x, fingerY: point.y, fingerZ: point.z))
        }
        return all.count > Self.fingerLimit * 2 ? Array(all.prefix(Self.fingerLimit * 2)) : all
    }
}

extension ParticleEngine {
    /// The extra places the tool is applied, in 3D, each as a line into the box.
    ///
    /// Every extra place is a spot on the glass, so its line runs into the box the same way the main finger's
    /// does — parallel to it, not converging on it. Built from the main line so that whatever the view is doing,
    /// the copies agree with it.
    func extraFingerRays(besides main: ParticleFingerRay) -> [ParticleFingerRay] {
        let cursor = main.cursor
        let points = activeExtraFingers(fingerX: cursor.x, fingerY: cursor.y, fingerZ: cursor.z)
        guard !points.isEmpty else { return [] }
        return points.map { point in
            ParticleFingerRay(
                // Shifted across and down by as much as the copy is from the main finger, and starting from the
                // same distance in front of the box.
                originX: main.originX + (point.x - cursor.x),
                originY: main.originY + (point.y - cursor.y),
                originZ: main.originZ,
                directionX: main.directionX,
                directionY: main.directionY,
                directionZ: main.directionZ,
                focusDistance: main.focusDistance,
                widens: main.widens
            )
        }
    }
}
