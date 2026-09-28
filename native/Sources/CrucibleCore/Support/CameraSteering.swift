// Steering the lab with the front camera: a hand waved at the field, and a head moved to look round it.
//
// ## What the phone does and what this does
//
// The phone finds a hand or a face in each picture from the front camera and says where it is, as fractions of the
// picture, already mirrored so that a hand moved to the right moves to the right on the screen, as in a mirror. What
// that *means* for the lab is here, where it can be checked: how much to smooth a hand that trembles, when a pinch is
// a pinch, how long a hand can go missing before the touch lets go, and how far a head moved is how far the view
// turns.

/// Where a hand is, as the phone saw it in one picture.
public struct HandSighting: Sendable, Equatable {
    /// The tip of the first finger, as fractions of the picture from its top left.
    public var x: Double
    public var y: Double
    /// How far apart the thumb and first finger tips are, as a share of the picture's width.
    public var pinch: Double

    public init(x: Double, y: Double, pinch: Double) {
        self.x = x
        self.y = y
        self.pinch = pinch
    }
}

/// A hand touching the field: where, as fractions of the view, and whether it is pinching.
public struct HandTouch: Sendable, Equatable {
    public var x: Double
    public var y: Double
    /// Pinching pulls; an open hand pushes.
    public var grabbing: Bool
}

/// Turns sightings of a hand into a steady touch.
public struct HandSteering: Sendable {
    private var x = 0.5
    private var y = 0.5
    private var seen = false
    private var grabbing = false
    private var lastSeen = -Double.infinity

    /// How much of the way toward the latest sighting the touch moves each time: enough to follow a wave, little
    /// enough that a trembling hand does not shake the field.
    public static let smoothing = 0.45
    /// A pinch closes below this and opens again above the second, so a hand held half-closed does not flicker
    /// between the two.
    public static let pinchCloses = 0.05
    public static let pinchOpens = 0.09
    /// How long a hand can go unseen — a blur, a finger across the lens — before the touch lets go, in seconds.
    public static let patience = 0.35

    public init() {}

    /// Takes the latest picture: a hand in it, or none. Returns the touch as it now stands, or nothing if there is
    /// no hand.
    public mutating func sighted(_ hand: HandSighting?, at time: Double) -> HandTouch? {
        if let hand, hand.x.isFinite, hand.y.isFinite {
            let wantedX = max(0, min(1, hand.x))
            let wantedY = max(0, min(1, hand.y))
            if seen {
                x += (wantedX - x) * Self.smoothing
                y += (wantedY - y) * Self.smoothing
            } else {
                // A hand arriving is put where it is, not glided in from wherever the last one left.
                x = wantedX
                y = wantedY
                grabbing = false
            }
            if hand.pinch.isFinite {
                if grabbing, hand.pinch > Self.pinchOpens { grabbing = false }
                if !grabbing, hand.pinch < Self.pinchCloses { grabbing = true }
            }
            seen = true
            lastSeen = time
        } else if seen, time - lastSeen > Self.patience {
            seen = false
            grabbing = false
        }
        return seen ? HandTouch(x: x, y: y, grabbing: grabbing) : nil
    }
}

/// Turns where a face is into how far round the view has turned, like looking through a window.
///
/// Move your head to the right and you see more of the box's right side; lift it and you look down into it. Where the
/// head was when looking began is straight on.
public struct HeadLook: Sendable {
    private var reference: (x: Double, y: Double)?
    private var yaw = 0.0
    private var pitch = 0.0
    private var lastSeen = -Double.infinity

    /// The furthest the view turns either way, the same as looking round by tipping the phone.
    public static let largestTurn = 28.0
    /// How far the head has to move across the picture, as a share of it, to turn the view all the way.
    public static let fullReach = 0.3
    public static let smoothing = 0.25
    /// After this long with no face the view drifts back to straight on, in seconds.
    public static let patience = 1.0

    public init() {}

    /// Takes the head as it is now as straight on.
    public mutating func recentre() { reference = nil }

    /// Takes the latest picture: where the middle of a face is, as fractions of the picture from its top left, or
    /// nothing. Returns how far to turn the view, in degrees.
    public mutating func sighted(faceX: Double?, faceY: Double?, at time: Double) -> (yaw: Double, pitch: Double) {
        if let faceX, let faceY, faceX.isFinite, faceY.isFinite {
            let start = reference ?? (faceX, faceY)
            reference = start
            let reach = Self.largestTurn / Self.fullReach
            let wantedYaw = max(-Self.largestTurn, min(Self.largestTurn, (faceX - start.x) * reach))
            // Up the picture is looking down into the box, as lifting your head to see over a wall would.
            let wantedPitch = max(-Self.largestTurn, min(Self.largestTurn, (start.y - faceY) * reach))
            yaw += (wantedYaw - yaw) * Self.smoothing
            pitch += (wantedPitch - pitch) * Self.smoothing
            lastSeen = time
        } else if time - lastSeen > Self.patience {
            yaw *= 1 - Self.smoothing
            pitch *= 1 - Self.smoothing
        }
        return (yaw, pitch)
    }
}
