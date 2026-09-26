/// Recording how the field should change over time.
///
/// Every setting in the field is a single value: the gravity is whatever it is until somebody drags the
/// slider. A timeline is the other way of saying it — this at the start, that four seconds in, something
/// else after eight — and the field works out everything in between. It is what turns an arrangement into
/// a piece that unfolds.
///
/// ## Two things done differently from the reference implementation
///
///   - **Keyframes carry a curve.** The reference blends everything in a straight line and its keyframes
///     have nowhere to record anything else, so adding easing to it later would change the file format and
///     break every saved timeline. The field for it is here from the start, and it is used: something that
///     eases in and out reads as deliberate where a straight blend reads as mechanical.
///   - **Which settings can be animated is stated once.** The reference lists them in three places — the
///     tweened ones, the stepped ones, and the reader that validates a saved file — so a setting can be
///     added to two of the three and silently never animate. Here there is one list.
public struct ParticleKeyframe: Sendable, Hashable, Codable {
    /// How a value approaches this keyframe.
    public enum Curve: String, Sendable, Hashable, CaseIterable, Codable {
        /// A straight blend. Mechanical, and right for something that should read as machinery.
        case straight
        /// Slow to leave, slow to arrive. What most things should be.
        case smooth
        /// Slow to leave, arriving at full speed.
        case easeIn
        /// Leaving at full speed, slow to arrive.
        case easeOut
        /// No blend at all — the value jumps at this keyframe and holds.
        case hold

        public var displayName: String {
            switch self {
            case .straight: return "Straight"
            case .smooth: return "Smooth"
            case .easeIn: return "Ease in"
            case .easeOut: return "Ease out"
            case .hold: return "Jump"
            }
        }

        /// Reshapes a fraction of the way between two keyframes.
        ///
        /// In and out: nought stays nought and one stays one for every curve, which is what keeps a
        /// keyframe's own value exact no matter which curve leads to it. A curve that did not have that
        /// property would mean the field never quite reached the value somebody set.
        public func shape(_ fraction: Double) -> Double {
            guard fraction.isFinite else { return 0 }
            let t = max(0, min(1, fraction))
            switch self {
            case .straight:
                return t
            case .smooth:
                // Three t squared minus two t cubed: flat at both ends, steepest in the middle.
                return t * t * (3 - 2 * t)
            case .easeIn:
                return t * t
            case .easeOut:
                return 1 - (1 - t) * (1 - t)
            case .hold:
                // Everything before the keyframe keeps the previous value; the jump happens on arrival.
                return t >= 1 ? 1 : 0
            }
        }
    }

    /// When, in seconds from the start.
    public var at: Double
    /// How the values approach this keyframe.
    public var curve: Curve
    /// The values being set. Anything absent is left to whatever the neighbouring keyframes say.
    public var values: [ParticleTimeline.Setting: Double]

    public init(at: Double, curve: Curve = .smooth, values: [ParticleTimeline.Setting: Double]) {
        self.at = at
        self.curve = curve
        self.values = values
    }
}

/// A whole timeline.
public struct ParticleTimeline: Sendable, Hashable, Codable {
    /// Something a timeline can change.
    ///
    /// One list, used by the sampler, the interface and the reader alike. The reference implementation keeps
    /// three separate lists, so a setting can be added to two of them and silently never animate.
    public enum Setting: String, Sendable, Hashable, CaseIterable, Codable {
        case gravityX
        case gravityY
        /// How much speed survives each moment.
        case drag
        case swirl
        case speedLimit
        case particleSize
        case glow
        case backdropStrength
        case windStrength
        case bounciness

        public var displayName: String {
            switch self {
            case .gravityX: return "Gravity sideways"
            case .gravityY: return "Gravity downward"
            case .drag: return "Drag"
            case .swirl: return "Swirl"
            case .speedLimit: return "Speed limit"
            case .particleSize: return "Particle size"
            case .glow: return "Glow"
            case .backdropStrength: return "Backdrop"
            case .windStrength: return "Wind"
            case .bounciness: return "Bounciness"
            }
        }

        /// The range the interface offers, and the range a saved value is pulled into.
        public var range: (low: Double, high: Double) {
            switch self {
            case .gravityX, .gravityY: return (-1.2, 1.2)
            case .drag: return (0.9, 1)
            case .swirl: return (-8, 8)
            case .speedLimit: return (4, 80)
            case .particleSize: return (1, 8)
            case .glow: return (0, 4)
            case .backdropStrength: return (0, 2)
            case .windStrength: return (0, 8)
            case .bounciness: return (0, 1)
            }
        }
    }

    /// The keyframes, always in order of time.
    public private(set) var keyframes: [ParticleKeyframe]
    /// Whether playback starts again at the end.
    public var loops: Bool

    public init(keyframes: [ParticleKeyframe] = [], loops: Bool = true) {
        self.keyframes = Self.tidied(keyframes)
        self.loops = loops
    }

    /// How close two keyframes have to be to count as the same moment.
    ///
    /// A ten-thousandth of a second. Recording over the playhead should replace what is there rather than
    /// leaving two keyframes a millionth of a second apart, which would blend between them in no time at
    /// all and read as a jump.
    public static let sameMoment = 1e-4

    /// How long the whole thing runs.
    public var duration: Double { keyframes.last?.at ?? 0 }

    /// How far past the last keyframe the playhead may be moved, in seconds, to record the next one.
    public static let roomToRecord = 30.0

    /// Whether there is anything to play.
    public var isEmpty: Bool { keyframes.isEmpty }

    /// Puts keyframes in order, drops what cannot be used, and pulls values into range.
    ///
    /// Sorted by time with the original order breaking ties, because Swift's own sort makes no promise
    /// about ties and a timeline that reordered itself between launches would be baffling.
    static func tidied(_ keyframes: [ParticleKeyframe]) -> [ParticleKeyframe] {
        var kept: [(frame: ParticleKeyframe, order: Int)] = []
        kept.reserveCapacity(keyframes.count)
        for (order, frame) in keyframes.enumerated() {
            guard frame.at.isFinite else { continue }
            var values: [Setting: Double] = [:]
            for (setting, value) in frame.values where value.isFinite {
                let range = setting.range
                values[setting] = max(range.low, min(range.high, value))
            }
            guard !values.isEmpty else { continue }
            kept.append((
                ParticleKeyframe(at: max(0, frame.at), curve: frame.curve, values: values),
                order
            ))
        }
        kept.sort { left, right in
            left.frame.at == right.frame.at ? left.order < right.order : left.frame.at < right.frame.at
        }
        return kept.map(\.frame)
    }

    /// Adds a keyframe, replacing any already at that moment.
    public mutating func record(_ frame: ParticleKeyframe) {
        var next = keyframes.filter { abs($0.at - frame.at) > Self.sameMoment }
        next.append(frame)
        keyframes = Self.tidied(next)
    }

    /// Removes the keyframe at a position in the list.
    public mutating func remove(at index: Int) {
        guard index >= 0, index < keyframes.count else { return }
        var next = keyframes
        next.remove(at: index)
        keyframes = Self.tidied(next)
    }

    /// Removes everything.
    public mutating func clear() {
        keyframes = []
    }

    /// What every animated setting should be at a given moment.
    ///
    /// Before the first keyframe and after the last, the end value holds — it is not carried on past the
    /// end, which would run a setting off into its limit and read as a fault rather than as a choice.
    ///
    /// A setting only some keyframes mention is blended between the ones that do, skipping over the ones
    /// that do not. That is what makes it possible to animate the gravity over eight seconds and flash the
    /// glow twice in the middle without the two having to share keyframes.
    public func values(at moment: Double) -> [Setting: Double] {
        guard !keyframes.isEmpty else { return [:] }
        let when = moment.isFinite ? max(0, moment) : 0

        var result: [Setting: Double] = [:]
        for setting in Setting.allCases {
            guard let value = self.value(of: setting, at: when) else { continue }
            result[setting] = value
        }
        return result
    }

    /// One setting's value at a moment, or nothing if no keyframe mentions it.
    public func value(of setting: Setting, at moment: Double) -> Double? {
        let mentioning = keyframes.filter { $0.values[setting] != nil }
        guard let first = mentioning.first, let last = mentioning.last else { return nil }

        let when = moment.isFinite ? max(0, moment) : 0
        if when <= first.at { return first.values[setting] }
        if when >= last.at { return last.values[setting] }

        for index in 0 ..< (mentioning.count - 1) {
            let low = mentioning[index]
            let high = mentioning[index + 1]
            guard when >= low.at, when <= high.at else { continue }
            guard let from = low.values[setting], let to = high.values[setting] else { continue }
            let span = high.at - low.at
            let fraction = span <= Self.sameMoment ? 1 : (when - low.at) / span
            // The curve belongs to the keyframe being *approached*, which is the one that decides how the
            // value should arrive. Taking it from the one being left would mean a keyframe's curve affected
            // what came before it rather than what came after.
            return from + (to - from) * high.curve.shape(fraction)
        }
        return last.values[setting]
    }
}

// MARK: - Playing it

/// Where a timeline has got to.
public struct ParticlePlayhead: Sendable, Hashable, Codable {
    public var isPlaying: Bool
    /// Where it is, in seconds.
    public var at: Double

    public init(isPlaying: Bool = false, at: Double = 0) {
        self.isPlaying = isPlaying
        self.at = at
    }

    /// Moves it on by however long has passed.
    ///
    /// - Returns: the playhead after moving. A new one rather than changing this one, so a caller can
    ///   decide whether to keep the result.
    public func advanced(by seconds: Double, through timeline: ParticleTimeline) -> ParticlePlayhead {
        guard isPlaying else { return self }
        let step = seconds.isFinite ? max(0, seconds) : 0
        let duration = timeline.duration
        // Nothing to play, or everything at one moment: park at the start rather than running on forever.
        guard duration > ParticleTimeline.sameMoment else {
            return ParticlePlayhead(isPlaying: timeline.loops && !timeline.isEmpty, at: 0)
        }

        let moved = at + step
        guard moved >= duration else { return ParticlePlayhead(isPlaying: true, at: moved) }
        guard timeline.loops else {
            // Stopped at the end rather than wrapping, and *at* the end rather than past it — so the last
            // keyframe's values are what is left showing.
            return ParticlePlayhead(isPlaying: false, at: duration)
        }
        // The overshoot is kept rather than thrown away, so a slow frame does not gradually shift the loop
        // earlier and earlier relative to everything else.
        return ParticlePlayhead(isPlaying: true, at: moved.truncatingRemainder(dividingBy: duration))
    }

    /// Moves it to a particular moment, without starting or stopping it.
    public func scrubbed(to moment: Double, through timeline: ParticleTimeline) -> ParticlePlayhead {
        let when = moment.isFinite ? moment : 0
        // Past the last keyframe as well, by up to ``ParticleTimeline/roomToRecord``. Clamped to the end, a
        // timeline with one keyframe at the start had no length at all, so the playhead could not be moved
        // anywhere to record the second one.
        return ParticlePlayhead(
            isPlaying: isPlaying,
            at: max(0, min(timeline.duration + ParticleTimeline.roomToRecord, when))
        )
    }
}

extension ParticleEngine {
    /// The recorded changes over time.
    public var timeline: ParticleTimeline {
        get { storedTimeline }
        set { storedTimeline = newValue }
    }

    /// Where the timeline has got to.
    public var playhead: ParticlePlayhead {
        get { storedPlayhead }
        set { storedPlayhead = newValue }
    }

    /// What every animated setting is right now, as a keyframe would record it.
    ///
    /// Used when somebody presses record: the point is to capture what they are looking at, so this has to
    /// read the same settings the timeline writes.
    public func currentTimelineValues() -> [ParticleTimeline.Setting: Double] {
        [
            .gravityX: gravityX,
            .gravityY: gravityY,
            .drag: damping,
            .swirl: vortexForce,
            .speedLimit: maxSpeed,
            .particleSize: particleSize,
            .glow: glow.strength,
            .backdropStrength: backdropStrength,
            .windStrength: flowSettings.strength,
            .bounciness: elasticity,
        ]
    }

    /// Applies a set of values to the field.
    ///
    /// The one place a timeline touches the settings, so the list of what can be animated and the list of
    /// what actually gets set cannot drift apart.
    public func applyTimelineValues(_ values: [ParticleTimeline.Setting: Double]) {
        for (setting, value) in values {
            guard value.isFinite else { continue }
            switch setting {
            case .gravityX: gravityX = value
            case .gravityY: gravityY = value
            case .drag: damping = value
            case .swirl: vortexForce = value
            case .speedLimit: maxSpeed = value
            case .particleSize: particleSize = value
            case .glow: glow.strength = value
            case .backdropStrength: backdropStrength = value
            case .windStrength: flowSettings.strength = value
            case .bounciness: elasticity = value
            }
        }
    }

    /// Moves the timeline on by one tick and applies whatever it says.
    ///
    /// Called from the tick, so the timeline advances with the simulation rather than with the wall clock —
    /// which means a recorded piece plays back the same whatever the field is doing to the frame rate.
    public func advanceTimeline() {
        // Only while it plays. It used to apply itself every moment even while stopped, so once a single
        // keyframe existed every setting it records was pinned: drag a slider and it snapped back within a
        // frame, which made recording a second, different keyframe impossible. Scrubbing applies what is
        // under the playhead on its own, so a stopped timeline still shows where it has been moved to.
        guard !timeline.isEmpty, playhead.isPlaying else { return }
        playhead = playhead.advanced(by: 1.0 / 60.0, through: timeline)
        applyTimelineValues(timeline.values(at: playhead.at))
    }
}
