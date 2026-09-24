import CrucibleCore
import Foundation

/// Keeps the materials someone invented, between launches.
///
/// The engine deliberately cannot touch a filesystem — it imports no Foundation — so it asks for
/// somewhere to put these instead. The web version uses the browser's local storage; this is the
/// same idea backed by a file.
///
/// ## Why one damaged entry must not cost the rest
///
/// These are read at launch, before anything is on screen, and they are a list. Decoding the list as
/// a whole means a single entry written by an older build takes every other material down with it —
/// so each is decoded on its own and anything unreadable is dropped. Someone who invented twelve
/// materials should lose the one that broke, not the twelve.
final class CustomElementFileStore: CustomElementStore {
    private let url: URL?

    init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Application Support rather than Documents: these are the app's record of what someone
            // made, not a document they manage themselves, and they should not clutter a file
            // browser next to the scenes they deliberately kept.
            url = directory.appendingPathComponent("custom-elements.json", isDirectory: false)
        } else {
            url = nil
        }
    }

    func loadCustomElements() -> [ElementDefinition] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }

        // Decoded to an intermediate array of raw values first, so each element can then be decoded
        // on its own and a single bad one can be skipped.
        guard let fragments = try? JSONDecoder().decode([RawElement].self, from: data) else {
            return []
        }
        return fragments.compactMap(\.decoded)
    }

    func saveCustomElements(_ elements: [ElementDefinition]) {
        guard let url else { return }
        guard let data = try? JSONEncoder().encode(elements) else { return }
        // Written whole or not at all. A partial write is exactly the corruption the per-entry
        // decoding above exists to survive, and there is no reason to invite it.
        try? data.write(to: url, options: .atomic)
    }

    /// One entry, held as raw JSON so its neighbours can be read even if it cannot.
    private struct RawElement: Decodable {
        let decoded: ElementDefinition?

        init(from decoder: any Decoder) throws {
            // A failure here is the point, not an accident: it is caught and becomes nothing.
            decoded = try? ElementDefinition(from: decoder)
        }
    }
}
