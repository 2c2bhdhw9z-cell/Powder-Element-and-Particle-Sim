/// Ribbons of light drawn through the field by hand, which stay where they are put.
///
/// ## What they are for
///
/// Everything else in this field moves. A ribbon does not: it is a mark somebody made, and it stays exactly where it
/// was made, which is what lets a box be drawn *in* rather than only looked at. In 3D, turning the view round a
/// ribbon is the whole point — a line drawn from one moment's angle becomes a shape in the box, and you only see what
/// you drew once you look at it from somewhere else.
///
/// ## Why they are not bodies
///
/// Because a body is something the physics owns: it falls, it is pushed, it can be flung out of the world. A ribbon
/// has to survive all of that untouched, so it is not in either store — it sits with the walls and the painted wind,
/// among the things somebody drew, and is drawn as lines the way they are.
public struct ParticleRibbon: Sendable, Hashable {
    /// The places the finger went, in the world's own coordinates.
    public var pointsX: [Double]
    public var pointsY: [Double]
    public var pointsZ: [Double]
    /// The colour it was drawn in.
    public var color: UInt32

    public init(color: UInt32) {
        self.pointsX = []
        self.pointsY = []
        self.pointsZ = []
        self.color = color
    }

    /// How many places it has.
    public var count: Int { pointsX.count }

    /// How many line segments it draws.
    public var segments: Int { max(0, count - 1) }
}

extension ParticleEngine {
    /// How many ribbons may be drawn, and how long each may be.
    ///
    /// Capped because a ribbon costs a line every frame for ever and a finger held down for a minute would draw
    /// three and a half thousand of them. When the oldest is dropped to make room, it is dropped whole rather than
    /// trimmed: half a ribbon is a mark nobody made.
    public static let ribbonLimit = 40
    public static let ribbonPointLimit = 600

    /// The ribbons drawn so far.
    public var ribbons: [ParticleRibbon] { storedRibbons }

    /// How many line segments all the ribbons come to, for whatever has to draw them.
    public var ribbonSegments: Int {
        storedRibbons.reduce(0) { $0 + $1.segments }
    }

    /// Starts a new ribbon in a colour of its own.
    ///
    /// - Parameter now: the clock, so the colour is the same one the painting tool would have chosen at that moment.
    ///   The two agree on purpose: a ribbon drawn alongside painted bodies should belong with them.
    public func beginRibbon(now: Double) {
        if storedRibbons.count >= Self.ribbonLimit { storedRibbons.removeFirst() }
        storedRibbons.append(ParticleRibbon(color: ParticleBrush.paintColor(now: now, index: storedRibbons.count).packedRGBA))
    }

    /// Adds a place to the ribbon being drawn.
    ///
    /// Places closer together than a couple of pixels are dropped: a finger resting still would otherwise add
    /// hundreds of points in the same spot, and the ribbon would reach its limit without going anywhere.
    public func extendRibbon(toX x: Double, y: Double, z: Double = 0) {
        guard x.isFinite, y.isFinite, z.isFinite else { return }
        guard !storedRibbons.isEmpty else { return }
        var ribbon = storedRibbons[storedRibbons.count - 1]
        if let lastX = ribbon.pointsX.last, let lastY = ribbon.pointsY.last, let lastZ = ribbon.pointsZ.last {
            let dx = x - lastX
            let dy = y - lastY
            let dz = z - lastZ
            guard dx * dx + dy * dy + dz * dz > 4 else { return }
        }
        guard ribbon.count < Self.ribbonPointLimit else { return }
        ribbon.pointsX.append(x)
        ribbon.pointsY.append(y)
        ribbon.pointsZ.append(z)
        storedRibbons[storedRibbons.count - 1] = ribbon
    }

    /// Throws away any ribbon that never became a line, so a tap does not leave an invisible mark behind.
    public func finishRibbon() {
        guard let last = storedRibbons.last, last.segments == 0 else { return }
        storedRibbons.removeLast()
    }

    /// Rubs them all out.
    public func clearRibbons() {
        storedRibbons.removeAll()
    }
}
