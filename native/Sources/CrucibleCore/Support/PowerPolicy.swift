/// What to do when the phone is hot, on its last few percent, or has been asked to save power.
///
/// ## Why the decision is here rather than where the readings are
///
/// The readings can only come from the phone: how warm it says it is, whether Low Power Mode is on, how much charge is
/// left, whether it is plugged in. The *decision* — what to give up, in what order, and when to give it back — is
/// arithmetic, and arithmetic can be tested. Left in the app it would be untestable and, worse, invisible: when a phone
/// throttles itself the app simply looks as though it has gone bad, which is precisely the complaint this is meant to
/// answer.
///
/// ## What it gives up, and in what order
///
/// Cheapest-looking first, most-missed last:
///
///   1. the frame rate, halved — the largest saving available and the least noticed, since the simulation still runs at
///      its own pace;
///   2. the picture's little luxuries — the soft shadows, the glow, the fog in the box;
///   3. how much is simulated per frame, which is the only one that changes the world rather than the picture.
///
/// Nothing is ever given up silently: ``Advice/reason`` says which reading caused it, in words meant to be shown.
public struct PowerPolicy: Sendable, Hashable {
    /// How warm the phone says it is. The phone's own words, in the order it uses them.
    public enum Heat: Int, Sendable, Hashable, Codable, CaseIterable, Comparable {
        case nominal = 0
        case fair = 1
        case serious = 2
        case critical = 3

        public static func < (a: Heat, b: Heat) -> Bool { a.rawValue < b.rawValue }
    }

    /// Everything read from the phone.
    public struct Readings: Sendable, Hashable {
        public var heat: Heat
        /// Whether Low Power Mode is on.
        public var lowPower: Bool
        /// How much charge is left, nought to one, or nothing when the phone will not say.
        public var charge: Double?
        /// Whether it is plugged in. A plugged-in phone is not saved from itself: it is being filled.
        public var isCharging: Bool

        public init(heat: Heat = .nominal, lowPower: Bool = false, charge: Double? = nil, isCharging: Bool = false) {
            self.heat = heat
            self.lowPower = lowPower
            self.charge = charge.flatMap { $0.isFinite ? max(0, min(1, $0)) : nil }
            self.isCharging = isCharging
        }
    }

    /// What to do about them.
    public struct Advice: Sendable, Hashable {
        /// How many frames a second to ask the display for. Sixty rather than a hundred and twenty is the one big saving.
        public var framesPerSecond: Int
        /// Whether the picture keeps its luxuries: shadows, glow, fog.
        public var keepsTheLuxuries: Bool
        /// How much of the usual simulation to do each frame, as a share. One is all of it.
        public var shareOfTheWork: Double
        /// Why, in words meant to be shown, or nothing when nothing is being given up.
        public var reason: String?

        /// Whether anything at all is being given up.
        public var isHoldingBack: Bool { reason != nil }
    }

    /// The charge below which, unplugged, the app eases off: one in ten.
    public static let lowCharge = 0.10
    /// And below which it eases off hard: one in twenty.
    public static let veryLowCharge = 0.05

    /// What to do, given what the phone says.
    ///
    /// Written as one function of the readings rather than as a set of switches that turn each other on and off,
    /// because the readings change back as well as forth: a phone that cools down must get everything back, and a rule
    /// that only ever takes things away is how an app ends up permanently at half speed after one warm afternoon.
    public static func advice(for readings: Readings) -> Advice {
        // Plugged in and merely warm is not a reason to hold back — but a phone that is seriously hot is, plugged in or
        // not. It will throttle itself whatever the app does, and holding back is how the app stays smooth instead of
        // stuttering.
        switch readings.heat {
        case .critical:
            return Advice(
                framesPerSecond: 30,
                keepsTheLuxuries: false,
                shareOfTheWork: 0.5,
                reason: "The phone is very hot, so the lab is running at a third of its usual pace. It will pick up as "
                    + "it cools."
            )
        case .serious:
            return Advice(
                framesPerSecond: 60,
                keepsTheLuxuries: false,
                shareOfTheWork: 0.75,
                reason: "The phone is hot, so the lab has eased off. It will pick up as it cools."
            )
        case .fair, .nominal:
            break
        }

        if readings.lowPower {
            return Advice(
                framesPerSecond: 60,
                keepsTheLuxuries: false,
                shareOfTheWork: 1,
                reason: "Low Power Mode is on, so the lab is drawing sixty times a second instead of a hundred and "
                    + "twenty. The worlds still run at their usual pace."
            )
        }

        if !readings.isCharging, let charge = readings.charge {
            if charge <= veryLowCharge {
                return Advice(
                    framesPerSecond: 30,
                    keepsTheLuxuries: false,
                    shareOfTheWork: 0.75,
                    reason: "The battery is nearly empty, so the lab has eased off a long way to keep going as long as "
                        + "it can."
                )
            }
            if charge <= lowCharge {
                return Advice(
                    framesPerSecond: 60,
                    keepsTheLuxuries: false,
                    shareOfTheWork: 1,
                    reason: "The battery is low, so the lab is drawing sixty times a second instead of a hundred and "
                        + "twenty."
                )
            }
        }

        // A warm phone that is not hot: the luxuries go, nothing else. Cheap, and it often stops the phone getting hot
        // at all, which is better than waiting until it has.
        if readings.heat == .fair, !readings.isCharging {
            return Advice(
                framesPerSecond: 120,
                keepsTheLuxuries: false,
                shareOfTheWork: 1,
                reason: "The phone is warming up, so the shadows and the glow are off for now."
            )
        }

        return Advice(framesPerSecond: 120, keepsTheLuxuries: true, shareOfTheWork: 1, reason: nil)
    }
}

// MARK: - What the battery costs

/// How much charge the lab is using, measured rather than guessed.
///
/// ## Why it is measured this way
///
/// A phone will not tell an app how many watts it is drawing. What it will give is how much charge is left, in steps of
/// one percent. So this watches that number fall and divides by the time it took: with the app on screen and running,
/// that is what the lab costs, near enough to be worth saying. Nothing is inferred from anything else — no guess from
/// the frame rate, no table of what a chip is supposed to use.
///
/// The first reading needs a whole percent to have gone, which on a phone doing this much work is a couple of minutes.
/// Until then it says it does not know yet, which is honest.
public struct BatteryCost: Sendable, Hashable {
    /// One reading of the charge, with when it was taken.
    private struct Mark: Sendable, Hashable {
        var charge: Double
        var seconds: Double
    }

    private var first: Mark?
    private var latest: Mark?
    /// How far the charge has fallen since the first reading, as a share.
    private var fallen = 0.0

    public init() {}

    /// The soonest a figure is offered: a whole percent of charge, and at least this long.
    public static let leastSeconds = 45.0

    /// Takes a reading. Anything that cannot be used — no charge given, plugged in, the charge going up — starts the
    /// measurement again rather than being averaged into it, because a phone being filled says nothing about what the
    /// app costs.
    public mutating func note(charge: Double?, isCharging: Bool, seconds: Double) {
        guard let charge, charge.isFinite, !isCharging, seconds.isFinite else {
            forget()
            return
        }
        let mark = Mark(charge: max(0, min(1, charge)), seconds: max(0, seconds))
        guard let start = first else {
            first = mark
            latest = mark
            fallen = 0
            return
        }
        // Filled, or a new session: start again.
        guard mark.charge <= start.charge, mark.seconds >= start.seconds else {
            first = mark
            latest = mark
            fallen = 0
            return
        }
        latest = mark
        fallen = start.charge - mark.charge
    }

    /// Forgets what has been measured. For when the phone is plugged in, or the app put away.
    public mutating func forget() {
        first = nil
        latest = nil
        fallen = 0
    }

    /// How long the app has been measuring, in seconds.
    public var seconds: Double {
        guard let first, let latest else { return 0 }
        return latest.seconds - first.seconds
    }

    /// How much charge the lab uses an hour, as a share — or nothing until enough has been used to say.
    public var shareAnHour: Double? {
        guard fallen >= 0.01, seconds >= Self.leastSeconds else { return nil }
        return fallen / seconds * 3_600
    }

    /// How much longer the battery would last at this rate, in hours, or nothing until there is a figure.
    public func hoursLeft(charge: Double?) -> Double? {
        guard let rate = shareAnHour, rate > 0, let charge, charge.isFinite, charge > 0 else { return nil }
        return charge / rate
    }
}
