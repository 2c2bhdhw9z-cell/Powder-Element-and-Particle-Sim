/// A lava lamp: soft blobs of wax that warm at the bottom, rise, cool at the top, and sink again, for ever.
///
/// ## How the wax moves
///
/// Each blob is a jelly (see `ParticleJellyPen.swift`) on a flat field and a sprung ball in 3D, so it wobbles,
/// squashes against the glass and stretches as it goes, and each has a warmth of its own from nought, cold, to one, hot. Resting in the bottom fifth of the lamp, where
/// the bulb is, a blob warms; in the top fifth it cools; in between it keeps what it has, which is what carries a warm
/// blob all the way up and a cold one all the way down rather than leaving both hovering in the middle. Warm wax is
/// lighter than the liquid round it and cold wax heavier, so a blob's warmth decides how hard it is pushed up against
/// gravity: half warm floats, hotter rises, colder sinks. The colour follows the warmth, deep red to orange.
///
/// The blobs are known by the identities of their bodies, which a saved file does not keep, so a lamp opened from a
/// file is wax that has been switched off: the blobs are there and sit still. Choosing the lamp again lights it.
extension ParticleEngine {
    /// How much warmer a blob gets each moment at the bottom, and colder at the top.
    static let lampHeating = 0.006
    /// How many blobs of wax.
    static let lampBlobs = 5

    func spawnLavaLamp() {
        beginScene("lavalamp", gravityY: 0.1)
        // Thick liquid round the wax, so the blobs drift rather than fly.
        sceneSets(damping: 0.95, maxSpeed: 3)
        let wasSuppressed = undoSuppressed
        undoSuppressed = true
        defer { undoSuppressed = wasSuppressed }
        let size = min(layoutWidth, layoutHeight)
        var blobs: [[Int]] = []
        for blob in 0 ..< Self.lampBlobs {
            let x = layoutLeft + layoutWidth * (0.25 + 0.5 * (Double(blob) + 0.5) / Double(Self.lampBlobs))
            let y = down(0.15 + 0.7 * rng.next())
            let first = particles.count
            if storedDepthEnabled {
                // In the box, a soft ball of wax: the jelly is a flat thing, the sprung ball is its form in depth.
                let z = (rng.next() - 0.5) * worldDepth * 0.5
                addBlobInDepth(nodes: 30, centreX: x, centreY: y, centreZ: z)
            } else {
                let radius = size * (0.07 + 0.02 * rng.next())
                var outline: [ParticleFingerPoint] = []
                for step in 0 ..< 28 {
                    let angle = Double(step) / 28 * 2 * 3.141592653589793
                    outline.append(ParticleFingerPoint(x: x + jsCos(angle) * radius, y: y + jsSin(angle) * radius * 1.15))
                }
                _ = makeJelly(outline: outline)
            }
            blobs.append(particles[min(first, particles.count)...].map(\.id))
        }
        storedLampBlobs = blobs.filter { !$0.isEmpty }
        storedLampWarmth = storedLampBlobs.map { _ in rng.next() }
        colourTheWax()
    }

    /// Every blob warming or cooling, and pushed up by its warmth. Before the bodies move.
    func stepLavaLamp() {
        guard arrangement == "lavalamp", !storedLampBlobs.isEmpty else {
            if !storedLampWarmth.isEmpty || !storedLampBlobs.isEmpty {
                storedLampWarmth = []
                storedLampBlobs = []
            }
            return
        }
        if storedLampWarmth.count != storedLampBlobs.count {
            storedLampWarmth = storedLampBlobs.map { _ in 0.5 }
        }
        var place: [Int: Int] = [:]
        for (index, body) in particles.enumerated() { place[body.id] = index }
        let top = layoutTop
        let tall = max(1, layoutHeight)
        for (index, blob) in storedLampBlobs.enumerated() {
            let members = blob.compactMap { place[$0] }
            guard !members.isEmpty else { continue }
            let middleY = members.reduce(0) { $0 + particles[$1].y } / Double(members.count)
            let depth = (middleY - top) / tall
            var warmth = storedLampWarmth[index]
            if depth > 0.8 { warmth += Self.lampHeating } else if depth < 0.2 { warmth -= Self.lampHeating }
            warmth = max(0, min(1, warmth))
            storedLampWarmth[index] = warmth
            // Half warm floats; hot rises against gravity, cold sinks with it.
            let lift = gravityY * 2 * warmth
            for member in members where !particles[member].isFixed {
                particles[member].velocityY -= lift
            }
        }
        if Int(springMoment) % 6 == 0 { colourTheWax() }
    }

    /// Deep red when cold, orange when hot.
    func colourTheWax() {
        guard storedLampWarmth.count == storedLampBlobs.count else { return }
        var place: [Int: Int] = [:]
        for (index, body) in particles.enumerated() { place[body.id] = index }
        for (index, blob) in storedLampBlobs.enumerated() {
            let warmth = storedLampWarmth[index]
            let colour = PackedColor(hue: 2 + 30 * warmth, saturation: 0.9, lightness: 0.42 + 0.16 * warmth)
            for id in blob {
                if let member = place[id] { particles[member].color = colour }
            }
        }
    }

    /// How warm each blob of a lava lamp is, nought to one.
    public var lampWarmth: [Double] { storedLampWarmth }
    /// Which bodies each blob is made of, by identifier.
    public var lampBlobs: [[Int]] { storedLampBlobs }
}
