/// Sand on a drum: a plate that sings, and sand that finds the places where it is still.
///
/// ## What happens, and why
///
/// Sprinkle sand on a metal plate and play a note on it, and the sand jumps into lines. The plate is not moving
/// all over: it rings in a pattern, with some places going up and down hard and others — lines across it — not
/// moving at all. Sand on a moving part is thrown about; sand on a still line stays. So every grain wanders until
/// it happens to land somewhere still, and stays, and the lines fill in. Change the note and the pattern changes,
/// the lines break up, and the sand sets off again to find the new ones. These are Chladni's figures.
///
/// Nothing here draws the lines. Each grain is only ever kicked in a random direction, as hard as the plate is
/// moving under it; the lines are simply where the kicking stops.
///
/// ## The pattern
///
/// A square plate free at its edges rings, for each pair of whole numbers, in the pattern
/// `cos(nπu)·cos(mπv) − cos(mπu)·cos(nπv)`, across it and down it from nought to one. Each pair is a note. Flat,
/// the plate is the screen seen from above and the kicks are across it; in 3D it is the floor of the box, the kicks
/// throw the sand up off it, and gravity brings it down somewhere new.
///
/// ## What it listens to
///
/// With the microphone on, loudness is how hard the plate rings — quiet, and the sand settles where it is — and how
/// bright the sound is, how much middle against how much low, picks the note. Without it, the drum plays itself, a
/// new note every eight seconds.
public struct ParticleDrumHearing: Sendable, Hashable {
    /// How loud, nought to one.
    public var loudness: Double
    /// How much of the sound is middle rather than low, nought to one.
    public var brightness: Double

    public init(loudness: Double, brightness: Double) {
        self.loudness = loudness.isFinite ? max(0, min(1, loudness)) : 0
        self.brightness = brightness.isFinite ? max(0, min(1, brightness)) : 0
    }
}

extension ParticleEngine {
    /// The notes the plate can ring in, lowest first, each a pair of whole numbers for the pattern.
    public static let drumNotes: [(m: Int, n: Int)] = [
        (1, 2), (1, 3), (2, 3), (1, 4), (3, 4), (2, 5), (1, 5), (3, 5), (4, 5), (2, 7), (3, 7), (4, 7),
    ]
    /// How long the drum holds a note by itself before moving to the next: eight seconds.
    public static let drumNoteLength = 480
    /// How long a note heard through the microphone is held before another is allowed: a second and a half, so a
    /// tune changes the pattern at the pace of the tune rather than flickering every moment.
    public static let drumShortestHeardNote = 90

    /// Whether the plate is ringing.
    public var drumEnabled: Bool { storedDrumEnabled }

    /// Which note it is ringing in, as a place in ``drumNotes``.
    public var drumNote: Int {
        get { storedDrumNote }
        set {
            let count = Self.drumNotes.count
            storedDrumNote = ((newValue % count) + count) % count
            storedDrumNoteAge = 0
        }
    }

    /// What the microphone is hearing, or nothing when it is off and the drum plays itself. Set by the app each
    /// moment while it listens.
    public var drumHearing: ParticleDrumHearing? {
        get { storedDrumHeard }
        set { storedDrumHeard = newValue }
    }

    /// How far the plate moves at a place, nought to one, for the note it is ringing in.
    ///
    /// - Parameters:
    ///   - u: across the plate, nought to one.
    ///   - v: down it (or into the box, in 3D), nought to one.
    public static func drumAmplitude(note: Int, u: Double, v: Double) -> Double {
        let pair = drumNotes[((note % drumNotes.count) + drumNotes.count) % drumNotes.count]
        let m = Double(pair.m) * Double.pi
        let n = Double(pair.n) * Double.pi
        let value = jsCos(n * u) * jsCos(m * v) - jsCos(m * u) * jsCos(n * v)
        // The largest the pattern reaches is two, so halved to run from nought to one.
        return min(1, abs(value) * 0.5)
    }

    /// Where the plate is: a square in the middle of what is on screen, flat; the floor of the box, in 3D.
    var drumPlate: (left: Double, top: Double, side: Double) {
        let side = min(layoutWidth, layoutHeight) * 0.9
        return (width * 0.5 - side * 0.5, height * 0.5 - side * 0.5, side)
    }

    /// Sand scattered evenly over a plate, and the plate ringing.
    public func spawnDrum() {
        if storedDepthEnabled { return spawnDrumInDepth() }
        beginScene("drum", gravityY: 0)
        // Heavily damped, so each kick is a hop rather than the start of a slide across the plate — which is what
        // lets a grain that lands on a still line stay on it.
        sceneSets(damping: 0.78, maxSpeed: 12 * sceneScale)
        storedDrumEnabled = true
        storedDrumNote = 0
        storedDrumNoteAge = 0
        let plate = drumPlate
        // The plate's edge, which the sand cannot cross. Walls rather than a rule of this scene's own, so the edge
        // is drawn and so a finger can still push sand up against it.
        if width > 0, height > 0 {
            let left = plate.left / width
            let right = (plate.left + plate.side) / width
            let top = plate.top / height
            let bottom = (plate.top + plate.side) / height
            addWall(fromFractionX: left, y: top, toFractionX: right, y: top)
            addWall(fromFractionX: right, y: top, toFractionX: right, y: bottom)
            addWall(fromFractionX: right, y: bottom, toFractionX: left, y: bottom)
            addWall(fromFractionX: left, y: bottom, toFractionX: left, y: top)
        }
        let total = min(24_000, patternRoom)
        for _ in 0 ..< total {
            let x = plate.left + plate.side * (0.02 + rng.next() * 0.96)
            let y = plate.top + plate.side * (0.02 + rng.next() * 0.96)
            if !placeLoose(x, y, hue: 42, saturation: 0.55, lightness: 0.72) { break }
        }
    }

    /// The floor of the box as the plate, with sand scattered over it.
    func spawnDrumInDepth() {
        beginScene("drum", gravityY: 0.35)
        sceneSets(damping: 0.9, maxSpeed: 12 * sceneScale)
        storedDrumEnabled = true
        storedDrumNote = 0
        storedDrumNoteAge = 0
        let total = min(20_000, patternRoom)
        let plate = drumPlate
        let depth = max(1, halfDepth * 0.92)
        for _ in 0 ..< total {
            let x = plate.left + plate.side * (0.02 + rng.next() * 0.96)
            let z = -depth + rng.next() * depth * 2
            let placed = swarm.append(
                x: x,
                y: height - 3 - rng.next() * 6,
                velocityX: 0,
                velocityY: 0,
                color: PackedColor(hue: 42, saturation: 0.55, lightness: 0.72).packedRGBA,
                budget: max(0, maxParticles - particles.count),
                z: z
            )
            if !placed { break }
        }
    }

    /// One moment of the plate ringing.
    func stepDrum() {
        guard storedDrumEnabled else { return }
        let notes = Self.drumNotes.count

        // Which note, and how hard.
        var loudness = 1.0
        storedDrumNoteAge += 1
        if let heard = storedDrumHeard {
            // Quiet is still: below a whisper nothing moves at all, so a silent room leaves the pattern standing.
            loudness = heard.loudness < 0.04 ? 0 : min(1, heard.loudness * 1.6)
            let wanted = min(notes - 1, Int((heard.brightness * Double(notes)).rounded(.down)))
            if wanted != storedDrumNote, storedDrumNoteAge >= Self.drumShortestHeardNote, loudness > 0 {
                storedDrumNote = wanted
                storedDrumNoteAge = 0
            }
        } else if storedDrumNoteAge >= Self.drumNoteLength {
            storedDrumNote = (storedDrumNote + 1) % notes
            storedDrumNoteAge = 0
        }
        guard loudness > 0 else { return }

        let count = swarm.count
        guard count > 0 else { return }
        let note = storedDrumNote
        let plate = drumPlate
        guard plate.side > 0 else { return }
        let inverseSide = 1 / plate.side
        // Measured against the plate, so a large plate's pattern forms in the same time as a small one's: a kick
        // is a share of the plate's width rather than a fixed number of pixels.
        let scale = plate.side / 360
        let positions = swarm.positions
        let velocities = swarm.velocities
        var random = rng

        if storedDepthEnabled && swarm.hasDepth {
            // The floor rings: sand near it is thrown up and a little sideways, as hard as the floor moves there.
            let depths = swarm.depths
            let depthVelocities = swarm.depthVelocities
            let depth = max(1, halfDepth)
            let floor = height
            let reach = 10.0 * max(1, scale)
            let kick = 3.4 * loudness * max(1, scale.squareRoot())
            for index in 0 ..< count {
                let pair = index * 2
                let y = Double(positions[pair + 1])
                // Only sand touching the floor feels it; sand in the air is on its way down.
                guard floor - y < reach else { continue }
                let u = (Double(positions[pair]) - plate.left) * inverseSide
                let v = (Double(depths[index]) + depth) / (depth * 2)
                guard u >= 0, u <= 1, v >= 0, v <= 1 else { continue }
                let strength = Self.drumAmplitude(note: note, u: u, v: v) * kick
                guard strength > 0.02 else { continue }
                let angle = random.next() * 6.283185307179586
                velocities[pair] = JS.toFloat32(Double(velocities[pair]) + jsCos(angle) * strength * 0.7 * scale)
                velocities[pair + 1] = JS.toFloat32(Double(velocities[pair + 1]) - strength * (0.5 + random.next()))
                depthVelocities[index] = JS.toFloat32(
                    Double(depthVelocities[index]) + jsSin(angle) * strength * 0.7 * scale
                )
            }
            rng = random
            return
        }

        let kick = 4.0 * loudness * scale
        for index in 0 ..< count {
            let pair = index * 2
            let u = (Double(positions[pair]) - plate.left) * inverseSide
            let v = (Double(positions[pair + 1]) - plate.top) * inverseSide
            guard u >= 0, u <= 1, v >= 0, v <= 1 else { continue }
            let strength = Self.drumAmplitude(note: note, u: u, v: v) * kick
            guard strength > 0.02 else { continue }
            let angle = random.next() * 6.283185307179586
            velocities[pair] = JS.toFloat32(Double(velocities[pair]) + jsCos(angle) * strength)
            velocities[pair + 1] = JS.toFloat32(Double(velocities[pair + 1]) + jsSin(angle) * strength)
        }
        rng = random
    }
}
