/// A small note of what the world was doing, kept up to date as somebody uses the app, so that a fault can be
/// reproduced afterwards.
///
/// ## Why this exists
///
/// When the app closes by itself, the phone writes down *where in the code* it happened — that report is already
/// kept, under Analytics Data in the privacy settings. What nobody has is *what the world was doing*: which chamber,
/// how big, what was in it, what was touched in the seconds before. Without that half, a report says a line number
/// and nothing that can be tried again.
///
/// So the app keeps this note, rewritten as it goes, and marks it unfinished until the app is put away properly. If
/// the next launch finds an unfinished one, the last session ended badly and the note describes it.
///
/// It is also what the "that looked wrong" button sends, for a fault with no crash at all — which is most of them.
///
/// ## What is deliberately not in it
///
/// Nothing about the person: no account, no address, no file names, no picture unless they choose to send one. Only
/// what the simulation was, which is the only part that helps.
public struct LabBreadcrumb: Codable, Sendable, Equatable {
    /// The shape of this note. A note written by a newer app is not read by an older one.
    public static let currentVersion = 1
    /// How many of the last things touched are kept. Enough to cover the seconds before a fault without the note
    /// growing without end.
    public static let mostActions = 40

    /// One thing worth knowing about the world, ready to be read as it stands.
    public struct Reading: Codable, Sendable, Equatable {
        public var name: String
        public var value: String

        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    /// Something that was touched, and how long into the session it happened.
    public struct Action: Codable, Sendable, Equatable {
        public var secondsIn: Double
        public var what: String

        public init(secondsIn: Double, what: String) {
            self.secondsIn = secondsIn.isFinite ? max(0, secondsIn) : 0
            self.what = what
        }
    }

    public var version: Int
    /// Which build of the app it was, so a note is not read against a different one.
    public var appVersion: String
    public var build: String
    /// Which phone, and which version of iOS. Both matter: almost every fault so far has been about a screen size.
    public var device: String
    public var system: String
    /// How long the session had been going when the note was last written, in seconds.
    public var seconds: Double
    /// Whether the app was put away properly. False in a note being kept up to date — which is exactly how the next
    /// launch knows the last session ended badly.
    public var endedCleanly: Bool
    /// What the world was, in the order it should be read.
    public var readings: [Reading]
    /// The last things touched, oldest first.
    public var actions: [Action]

    public init(
        version: Int = LabBreadcrumb.currentVersion,
        appVersion: String = "",
        build: String = "",
        device: String = "",
        system: String = "",
        seconds: Double = 0,
        endedCleanly: Bool = false,
        readings: [Reading] = [],
        actions: [Action] = []
    ) {
        self.version = version
        self.appVersion = appVersion
        self.build = build
        self.device = device
        self.system = system
        self.seconds = seconds.isFinite ? max(0, seconds) : 0
        self.endedCleanly = endedCleanly
        self.readings = readings
        self.actions = actions
    }

    /// Whether this note describes a session that never finished — the app closed by itself, or was killed by the
    /// phone — and so is worth offering to send.
    ///
    /// A note from a different shape of note, or from a session where nothing at all happened, is not worth offering:
    /// it can say nothing useful about a fault.
    public var describesABadEnding: Bool {
        version == Self.currentVersion && !endedCleanly && (!actions.isEmpty || seconds >= 2)
    }

    /// Adds something that was touched, letting the oldest go once there are too many.
    public mutating func note(_ what: String, secondsIn: Double) {
        actions.append(Action(secondsIn: secondsIn, what: what))
        if actions.count > Self.mostActions { actions.removeFirst(actions.count - Self.mostActions) }
    }

    /// Replaces what the world was.
    public mutating func describe(_ readings: [Reading]) {
        self.readings = readings
    }

    /// The note as something a person can read, and paste into a message.
    ///
    /// Plain text on purpose: whoever receives it should be able to read it without a tool, and whoever sends it
    /// should be able to see exactly what they are sending.
    public func text(title: String = "Crucible — what the world was doing") -> String {
        var lines = [title, ""]
        lines.append("App \(appVersion.isEmpty ? "unknown" : appVersion) (build \(build.isEmpty ? "unknown" : build))")
        if !device.isEmpty || !system.isEmpty {
            lines.append("\(device.isEmpty ? "Unknown device" : device), \(system.isEmpty ? "unknown system" : system)")
        }
        lines.append("Open for \(Self.spell(seconds))")
        lines.append(endedCleanly ? "Put away properly" : "Did not finish — the app closed by itself or was closed by the phone")
        if !readings.isEmpty {
            lines.append("")
            lines.append("The world:")
            for reading in readings { lines.append("  \(reading.name): \(reading.value)") }
        }
        if !actions.isEmpty {
            lines.append("")
            lines.append("The last things touched, oldest first:")
            for action in actions { lines.append("  \(Self.spell(action.secondsIn)) in — \(action.what)") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A length of time as somebody would say it.
    static func spell(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 seconds" }
        let whole = Int(seconds.rounded())
        if whole < 60 { return whole == 1 ? "1 second" : "\(whole) seconds" }
        let minutes = whole / 60
        let rest = whole % 60
        var said = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if rest > 0 { said += rest == 1 ? " 1 second" : " \(rest) seconds" }
        return said
    }
}
