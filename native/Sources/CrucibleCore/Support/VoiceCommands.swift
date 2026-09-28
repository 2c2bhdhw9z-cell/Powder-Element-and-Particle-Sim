// Talking to the lab: what a sentence somebody said out loud asks it to do.
//
// ## Why this is here and not beside the microphone
//
// The phone turns speech into words; what the words *mean* is a question that can be answered and checked on any
// machine. "Make it rain", "give me some lava please", "boom", "turn it upside down" — each is a sentence a person
// says, not a command they have learnt, so understanding them is a matter of looking for the words that matter and
// ignoring the rest. Doing it here means every one of those sentences is in the checks.
//
// ## How it listens
//
// For the last thing said, not everything since the microphone opened: the phone hands over its best guess at the
// whole sentence so far, again and again as it goes, and the same command must not be carried out every time the
// guess is refined. ``VoiceCommandListener`` keeps track of what has already been acted on.

/// Something the lab can be asked to do out loud.
public enum LabVoiceCommand: Equatable, Sendable {
    case play
    case pause
    case clear
    case undo
    /// Paint with this material from now on.
    case choose(ElementID)
    /// Pour some of this in from the top.
    case pour(ElementID)
    /// Set something off in the middle.
    case explode
    /// Turn the world upside down.
    case flip
    case faster
    case slower
    case biggerBrush
    case smallerBrush
    /// Go to one of the two chambers.
    case powderChamber
    case fieldChamber
    /// Lay out one of the field's arrangements, by its identifier.
    case arrangement(String)
    /// Load one of the powder world's scenes, by its identifier.
    case scene(String)

    /// What the lab says back, so somebody knows they were understood.
    public func said(materialName: (ElementID) -> String) -> String {
        switch self {
        case .play: "Playing"
        case .pause: "Paused"
        case .clear: "Cleared"
        case .undo: "Undone"
        case let .choose(id): "Painting with \(materialName(id).lowercased())"
        case let .pour(id): "Pouring \(materialName(id).lowercased())"
        case .explode: "Boom"
        case .flip: "Turned over"
        case .faster: "Faster"
        case .slower: "Slower"
        case .biggerBrush: "Bigger brush"
        case .smallerBrush: "Smaller brush"
        case .powderChamber: "The powder world"
        case .fieldChamber: "The particle field"
        case let .arrangement(id): "The \(id)"
        case let .scene(id): "The \(id) scene"
        }
    }
}

public enum VoiceCommands {
    /// A thing that can be named out loud, and the identifier it stands for.
    public struct Name: Sendable {
        public var words: String
        public var id: String
        public init(_ words: String, id: String) {
            self.words = words
            self.id = id
        }
    }

    /// Every material by the names somebody might say: "Spark / Electricity" answers to spark and to electricity,
    /// "C4 Explosive" to C4 as well.
    public static func materialNames(_ definitions: [ElementDefinition]) -> [(ElementID, String)] {
        var names: [(ElementID, String)] = []
        for definition in definitions where definition.id != Element.empty {
            for part in definition.name.split(separator: "/") {
                let name = part.trimmedOfSpaces
                guard !name.isEmpty else { continue }
                names.append((definition.id, name))
            }
            // The first word of a name whose other words only describe it.
            let first = words(definition.name).first ?? ""
            if definition.name.hasSuffix(" Explosive") || definition.name.hasSuffix(" Gas")
                || definition.name.hasSuffix(" Liquid") || definition.name.hasSuffix(" Beam")
            {
                names.append((definition.id, first))
            }
        }
        return names
    }

    /// The words of a sentence, lowercased, with the punctuation and the filler taken out.
    static func words(_ heard: String) -> [String] {
        var cleaned = ""
        for character in heard.lowercased() {
            cleaned.append(character.isLetter || character.isNumber ? character : " ")
        }
        return cleaned.split(separator: " ").map(String.init)
    }

    /// Whether a run of words appears in a sentence, in order and next to each other.
    static func contains(_ phrase: String, in words: [String]) -> Bool {
        let wanted = self.words(phrase)
        guard !wanted.isEmpty, wanted.count <= words.count else { return false }
        for start in 0 ... (words.count - wanted.count) where Array(words[start ..< start + wanted.count]) == wanted {
            return true
        }
        return false
    }

    /// The longest name mentioned in a sentence, so "salt water" is salt water and not salt.
    static func mentioned<T>(_ names: [(words: String, value: T)], in words: [String]) -> T? {
        names
            .filter { contains($0.words, in: words) }
            .max { self.words($0.words).count < self.words($1.words).count }?
            .value
    }

    /// What a sentence asks for, if it asks for anything the lab can do.
    ///
    /// - Parameters:
    ///   - materials: the materials, by name, including any invented ones.
    ///   - arrangements: the field's arrangements, by name.
    ///   - scenes: the powder world's scenes, by name.
    public static func understand(
        _ heard: String,
        materials: [(ElementID, String)],
        arrangements: [Name] = [],
        scenes: [Name] = []
    ) -> LabVoiceCommand? {
        let words = self.words(heard)
        guard !words.isEmpty else { return nil }
        func any(_ phrases: [String]) -> Bool { phrases.contains { contains($0, in: words) } }

        // The ones that must win over a material named in the same breath: "clear the sand" is a clear.
        if any(["undo", "take that back", "go back"]) { return .undo }
        if any(["clear", "empty it", "start again", "wipe"]) { return .clear }
        if any(["pause", "stop", "freeze", "hold on", "wait"]) { return .pause }
        if any(["play", "go on", "carry on", "resume", "unpause", "keep going"]) { return .play }
        if any(["explode", "explosion", "boom", "blow it up", "bang", "kaboom"]) { return .explode }
        if any(["upside down", "flip", "turn it over", "turn over"]) { return .flip }
        if any(["faster", "speed up", "quicker"]) { return .faster }
        if any(["slower", "slow down", "slow motion"]) { return .slower }
        if any(["bigger brush", "bigger", "larger", "thicker"]) { return .biggerBrush }
        if any(["smaller brush", "smaller", "thinner", "tiny"]) { return .smallerBrush }
        if any(["particle field", "the field", "particles", "field"]) { return .fieldChamber }
        if any(["powder world", "the powder", "powder", "sandbox"]) { return .powderChamber }

        // Rain is water, snowing is snow: the weather words people actually use.
        let named = materials.map { (words: $0.1, value: $0.0) }
            + [
                (words: "rain", value: Element.water), (words: "raining", value: Element.water),
                (words: "snowing", value: Element.snow), (words: "on fire", value: Element.fire),
                (words: "flames", value: Element.fire), (words: "lightning", value: Element.spark),
            ]
        let material = mentioned(named, in: words)

        if let arrangement = mentioned(arrangements.map { (words: $0.words, value: $0.id) }, in: words),
           material == nil || any(["show", "make a", "arrangement"])
        {
            return .arrangement(arrangement)
        }
        if let scene = mentioned(scenes.map { (words: $0.words, value: $0.id) }, in: words),
           material == nil || any(["scene", "load"])
        {
            return .scene(scene)
        }
        guard let material else { return nil }
        // Asking for it to come down is pouring; asking for it in your hand is choosing it.
        if any(["pour", "rain", "raining", "drop", "fill", "snowing", "more", "lots of", "flood", "make it"]) {
            return .pour(material)
        }
        return .choose(material)
    }
}

/// Keeps track of what has already been acted on while one sentence is still being heard.
///
/// The phone's guess at a sentence grows as it is spoken — "make", "make it", "make it rain" — and is sometimes
/// revised. A command is acted on once the words for it have arrived, and not again for the same stretch of speech.
public struct VoiceCommandListener: Sendable {
    /// How many words of the current sentence have been used up by commands already acted on.
    private var usedWords = 0

    public init() {}

    /// A new stretch of speech has begun: nothing in it has been acted on yet.
    public mutating func newSentence() { usedWords = 0 }

    /// The phone's latest guess at the sentence. Returns a command if the words not yet used ask for one.
    public mutating func heard(
        _ sentence: String,
        materials: [(ElementID, String)],
        arrangements: [VoiceCommands.Name] = [],
        scenes: [VoiceCommands.Name] = []
    ) -> LabVoiceCommand? {
        let words = VoiceCommands.words(sentence)
        // Revised to something shorter: start again from where the guess now ends.
        if words.count < usedWords { usedWords = words.count }
        let fresh = words.dropFirst(usedWords).joined(separator: " ")
        guard let command = VoiceCommands.understand(
            fresh, materials: materials, arrangements: arrangements, scenes: scenes
        ) else { return nil }
        usedWords = words.count
        return command
    }
}

extension Substring {
    var trimmedOfSpaces: String {
        let characters = drop { $0 == " " }
        return String(characters.reversed().drop { $0 == " " }.reversed())
    }
}
