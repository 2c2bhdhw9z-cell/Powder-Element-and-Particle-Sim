/// A name that hangs in the field, beside the thing it names.
///
/// ## Why the engine holds these rather than the app
///
/// Because only the field knows where the thing is. A label on Jupiter has to be on Jupiter, and Jupiter is going
/// round the Sun — so a label cannot be a place, it has to be a *body*, and only the engine has the bodies. The app
/// turns each one into a position on the screen and draws the words, which is all it can usefully do.
///
/// Labels are part of what an arrangement is, so they are cleared when the field is, and set again when a scene
/// that has them is laid out.
public struct ParticleLabel: Sendable, Hashable {
    public var text: String
    /// Which object body it names, if it names one. That body's place is where the label goes, so the label follows
    /// it however it moves.
    public var body: Int?
    /// Where it goes when it names no particular body — a region rather than a thing.
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ text: String, body: Int? = nil, x: Double = 0, y: Double = 0, z: Double = 0) {
        self.text = text
        self.body = body
        self.x = x
        self.y = y
        self.z = z
    }
}

extension ParticleEngine {
    /// The names hanging in the field. Empty for almost every scene.
    public var labels: [ParticleLabel] {
        get { storedLabels }
        set { storedLabels = newValue.count > 40 ? Array(newValue.prefix(40)) : newValue }
    }

    /// Whether names are shown at all. Off by default: a field of a million bodies is not a diagram.
    public var showsLabels: Bool {
        get { storedShowsLabels }
        set { storedShowsLabels = newValue }
    }

    /// Each label with the place it currently belongs, in the world's own coordinates.
    ///
    /// A label whose body has gone — eaten by a black hole, or expired — is dropped rather than left hanging over
    /// nothing, which is why this is worked out afresh rather than stored.
    public func labelPlaces() -> [(text: String, x: Double, y: Double, z: Double)] {
        guard storedShowsLabels, !storedLabels.isEmpty else { return [] }
        var found: [(text: String, x: Double, y: Double, z: Double)] = []
        found.reserveCapacity(storedLabels.count)
        for label in storedLabels {
            if let index = label.body {
                guard index >= 0, index < particles.count else { continue }
                let body = particles[index]
                guard body.isFinite else { continue }
                // A little above the body, so the words do not sit on top of the thing they name.
                found.append((label.text, body.x, body.y - body.radius - 10, body.z))
            } else {
                guard label.x.isFinite, label.y.isFinite, label.z.isFinite else { continue }
                found.append((label.text, label.x, label.y, label.z))
            }
        }
        return found
    }
}
