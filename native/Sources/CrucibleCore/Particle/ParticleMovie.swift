// The movie studio: places to look from, how long to take getting to each, how fast the world runs on the way, and
// what to say when it gets there.
//
// ## What a movie is
//
// A list of stops. Each is a camera — where the field is seen from — with a caption, how long to stay, how long the
// journey there takes, and how fast the world itself runs while the camera is on its way and while it waits. A speed
// below one is slow motion: the camera still glides at its own pace while the world crawls, which is what makes a
// collision worth watching.
//
// Played, the first stop is cut to rather than travelled to; every stop after it is flown to along an eased path, so
// the camera sets off gently and arrives gently rather than lurching. Everything is worked out from one number — how
// far into the movie it is — so the same moment always looks the same, the whole thing can be scrubbed, and it can
// be checked on any machine.
//
// ## What the camera does not carry into a movie
//
// Two things, both deliberately.
//
// **The spin.** A camera turning by itself would be turning on top of the movie's own motion, so a stop keeps the
// angle the spin had reached and not the spin.
//
// **Room made by zooming out.** Pulling back past the whole world does not move the camera — it makes the world
// bigger, so the crowd has somewhere to go. Doing that on every frame of a journey would be resizing the world sixty
// times a second, walls and all, which is a change to the physics and not a camera move. So a stop remembers such a
// view as the whole world, which is what it was showing.

/// A movie made of camera stops.
public struct ParticleMovie: Sendable, Codable, Equatable {
    /// One place to look from.
    public struct Stop: Sendable, Codable, Equatable {
        /// Where the field is seen from.
        public var camera: ParticleCamera
        /// How long the journey here from the stop before takes, in seconds. Ignored on the first stop, which is cut
        /// to.
        public var travel: Double
        /// How long to stay here once arrived, in seconds.
        public var hold: Double
        /// How fast the world runs on the way here and while here. One is real time; a tenth is very slow motion.
        public var speed: Double
        /// What to say while here. Empty for nothing.
        public var caption: String

        public static let travelRange = 0.5 ... 20.0
        public static let holdRange = 0.0 ... 20.0
        public static let speedRange = 0.1 ... 2.0
        /// Long enough for a sentence, short enough to fit across a phone.
        public static let longestCaption = 90

        public init(camera: ParticleCamera, travel: Double = 3, hold: Double = 2, speed: Double = 1, caption: String = "") {
            self.camera = ParticleMovie.forMovie(camera)
            self.travel = Self.clamp(travel, Self.travelRange, fallback: 3)
            self.hold = Self.clamp(hold, Self.holdRange, fallback: 2)
            self.speed = Self.clamp(speed, Self.speedRange, fallback: 1)
            self.caption = String(caption.prefix(Self.longestCaption))
        }

        static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }

        private enum CodingKeys: String, CodingKey { case camera, travel, hold, speed, caption }

        /// Read with anything missing or out of range taken as its usual value, like the camera itself.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                camera: (try? c.decodeIfPresent(ParticleCamera.self, forKey: .camera)) ?? .identity,
                travel: (try? c.decodeIfPresent(Double.self, forKey: .travel)) ?? 3,
                hold: (try? c.decodeIfPresent(Double.self, forKey: .hold)) ?? 2,
                speed: (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? 1,
                caption: (try? c.decodeIfPresent(String.self, forKey: .caption)) ?? ""
            )
        }
    }

    /// What the movie looks like at one moment.
    public struct Moment: Sendable, Equatable {
        public var camera: ParticleCamera
        /// How fast the world should be running.
        public var speed: Double
        /// What is being said, if anything.
        public var caption: String?
        /// How visible the caption is, from nought to one: it fades in on arrival and out before leaving.
        public var captionOpacity: Double
        /// Which stop is being travelled to or waited at.
        public var stop: Int
        /// Whether the camera is on its way rather than waiting.
        public var isTravelling: Bool
        /// Whether the movie has run out.
        public var isFinished: Bool
    }

    public var stops: [Stop]

    /// As many stops as a tray can list and a person can keep track of.
    public static let mostStops = 12
    /// How long a caption takes to fade in, and out.
    public static let captionFade = 0.35

    public init(stops: [Stop] = []) {
        self.stops = Array(stops.prefix(Self.mostStops))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(stops: (try? c.decodeIfPresent([Stop].self, forKey: .stops)) ?? [])
    }

    private enum CodingKeys: String, CodingKey { case stops }

    public var isEmpty: Bool { stops.isEmpty }

    /// Whether there is enough to play: a movie of one stop is a photograph.
    public var canPlay: Bool { stops.count >= 2 }

    /// How long the whole movie runs, in seconds.
    public var duration: Double {
        stops.enumerated().reduce(0) { total, item in total + (item.offset > 0 ? item.element.travel : 0) + item.element.hold }
    }

    /// When the journey to each stop begins, and when it arrives.
    func timings() -> [(leaves: Double, arrives: Double, departs: Double)] {
        var clock = 0.0
        var result: [(leaves: Double, arrives: Double, departs: Double)] = []
        for (index, stop) in stops.enumerated() {
            let leaves = clock
            let arrives = index == 0 ? clock : clock + stop.travel
            let departs = arrives + stop.hold
            result.append((leaves, arrives, departs))
            clock = departs
        }
        return result
    }

    /// The movie at a moment, in seconds from its start.
    public func moment(at time: Double) -> Moment? {
        guard let first = stops.first else { return nil }
        let t = time.isFinite ? max(0, time) : 0
        let schedule = timings()
        let end = schedule.last?.departs ?? 0
        if t >= end {
            let last = stops[stops.count - 1]
            return Moment(
                camera: last.camera, speed: last.speed, caption: nil, captionOpacity: 0,
                stop: stops.count - 1, isTravelling: false, isFinished: true
            )
        }
        for (index, span) in schedule.enumerated() where t < span.departs {
            let stop = stops[index]
            if index > 0, t < span.arrives {
                // On the way.
                let previous = stops[index - 1]
                let share = Self.ease((t - span.leaves) / max(1e-9, span.arrives - span.leaves))
                return Moment(
                    camera: Self.blend(previous.camera, stop.camera, share),
                    speed: previous.speed + (stop.speed - previous.speed) * share,
                    caption: nil, captionOpacity: 0,
                    stop: index, isTravelling: true, isFinished: false
                )
            }
            // Arrived, and waiting.
            let caption = Self.trimmed(stop.caption)
            let since = t - span.arrives
            let until = span.departs - t
            let fade = min(1, min(since, until) / Self.captionFade)
            return Moment(
                camera: stop.camera, speed: stop.speed,
                caption: caption.isEmpty ? nil : caption,
                captionOpacity: caption.isEmpty ? 0 : max(0, fade),
                stop: index, isTravelling: false, isFinished: false
            )
        }
        return Moment(
            camera: first.camera, speed: first.speed, caption: nil, captionOpacity: 0,
            stop: 0, isTravelling: false, isFinished: false
        )
    }

    // MARK: - Editing

    /// Adds a stop looking from where the camera is now.
    @discardableResult
    public mutating func add(_ camera: ParticleCamera) -> Bool {
        guard stops.count < Self.mostStops else { return false }
        stops.append(Stop(camera: camera))
        return true
    }

    public mutating func remove(at index: Int) {
        guard stops.indices.contains(index) else { return }
        stops.remove(at: index)
    }

    /// Moves a stop one place earlier.
    public mutating func moveEarlier(_ index: Int) {
        guard index > 0, stops.indices.contains(index) else { return }
        stops.swapAt(index, index - 1)
    }

    /// Replaces one stop's settings, through the same limits as a new one.
    public mutating func update(_ index: Int, travel: Double? = nil, hold: Double? = nil, speed: Double? = nil, caption: String? = nil) {
        guard stops.indices.contains(index) else { return }
        let old = stops[index]
        stops[index] = Stop(
            camera: old.camera,
            travel: travel ?? old.travel,
            hold: hold ?? old.hold,
            speed: speed ?? old.speed,
            caption: caption ?? old.caption
        )
    }

    // MARK: - The camera's path

    /// A camera fit for a movie: the spin's angle kept and the spin stopped, and any room made by zooming out taken
    /// as the whole world. See the note at the top of this file.
    public static func forMovie(_ camera: ParticleCamera) -> ParticleCamera {
        var still = camera
        still.orbitYaw = ParticleCamera.wrapDegrees(camera.effectiveOrbitYaw)
        still.yaw = ParticleCamera.wrapDegrees(camera.effectiveYaw)
        still.autoOrbit = false
        still.autoOrbitAngle = 0
        if still.growsWorldWhenZoomedOut, still.zoom < 1 { still.zoom = 1 }
        return still
    }

    /// Without spaces or line breaks at either end. The engine has no Foundation to ask.
    static func trimmed(_ text: String) -> String {
        let blank: (Character) -> Bool = { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }
        guard let start = text.firstIndex(where: { !blank($0) }), let end = text.lastIndex(where: { !blank($0) })
        else { return "" }
        return String(text[start ... end])
    }

    /// Eases in and out: sets off gently, arrives gently.
    public static func ease(_ value: Double) -> Double {
        let x = value.isFinite ? max(0, min(1, value)) : 0
        return x * x * (3 - 2 * x)
    }

    /// The way round from one angle to another that turns the least.
    static func turn(from a: Double, to b: Double, _ share: Double) -> Double {
        var gap = ParticleCamera.wrapDegrees(b - a)
        // Exactly half a turn apart either way is the same distance; always go the same way so it cannot flicker.
        if gap == -180 { gap = 180 }
        return ParticleCamera.wrapDegrees(a + gap * share)
    }

    /// A camera part of the way from one to another.
    ///
    /// Zoom is blended by its logarithm, so going from one to eight passes two at the same pace as going from two to
    /// four — a zoom feels even when it doubles evenly, not when it adds evenly. Angles go the short way round.
    /// Switches, which cannot be half on, change at the halfway point.
    public static func blend(_ a: ParticleCamera, _ b: ParticleCamera, _ share: Double) -> ParticleCamera {
        let s = share.isFinite ? max(0, min(1, share)) : 0
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * s }
        let from = max(1e-6, a.zoom)
        let zoom = from * jsPow(max(1e-6, b.zoom) / from, s)
        let late = s >= 0.5 ? b : a
        return ParticleCamera(
            zoom: zoom,
            panX: mix(a.panX, b.panX),
            panY: mix(a.panY, b.panY),
            yaw: turn(from: a.yaw, to: b.yaw, s),
            pitch: mix(a.pitch, b.pitch),
            growsWorldWhenZoomedOut: late.growsWorldWhenZoomedOut,
            autoOrbit: false,
            autoOrbitAngle: 0,
            orbitYaw: turn(from: a.orbitYaw, to: b.orbitYaw, s),
            orbitPitch: mix(a.orbitPitch, b.orbitPitch),
            perspective: mix(a.perspective, b.perspective),
            fog: mix(a.fog, b.fog),
            showsBox: late.showsBox,
            glows: late.glows,
            spinRate: late.spinRate,
            sliceDepth: mix(a.sliceDepth, b.sliceDepth),
            sliceAt: mix(a.sliceAt, b.sliceAt),
            colorsByDistance: late.colorsByDistance,
            showsShadows: late.showsShadows,
            glassesTurn: mix(a.glassesTurn, b.glassesTurn),
            focusBlur: mix(a.focusBlur, b.focusBlur),
            focusAt: mix(a.focusAt, b.focusAt),
            flyIn: mix(a.flyIn, b.flyIn),
            centreX: mix(a.centreX, b.centreX),
            centreY: mix(a.centreY, b.centreY),
            centreZ: mix(a.centreZ, b.centreZ)
        )
    }
}
