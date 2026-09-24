import CrucibleCore
import Foundation
import Observation

/// One saved lab: both chambers, and what they were set to.
///
/// Both together rather than one file each, matching the web version's scene format. Splitting them
/// would mean a saved "world" could be half-restored — and the two chambers can hand material to
/// one another, so a pairing is a thing someone might have built on purpose.
struct LabScene: Codable, Sendable {
    /// The format's version.
    ///
    /// Checked on the way in. A file from a later build is refused rather than guessed at: reading
    /// unknown fields as nothing produces a world that looks loaded and is quietly wrong, which is
    /// the failure this whole format exists to avoid.
    var version: Int
    var savedAt: Date
    var powder: PowderState?
    var particle: ParticleState?
    /// Any materials the person invented, so a scene using them still works on another phone.
    var customElements: [ElementDefinition]

    static let currentVersion = 1
}

/// Saved scenes on disk, and the autosave.
///
/// ## Where things go
///
/// Named saves live in Documents, because they are the person's own work and should survive the
/// system reclaiming space. The autosave lives in Application Support: it is the app's business
/// rather than theirs, and it should not appear in a file browser as clutter next to the things they
/// deliberately kept.
///
/// ## Why the autosave is written on the way out, not on a timer alone
///
/// The web version autosaves every eight seconds and again when the page is hidden. A phone is
/// harsher: an app can be killed while in the background with no further warning. So this writes on
/// the same interval *and* whenever the app leaves the foreground, which is the last reliable moment
/// to do anything.
@MainActor
@Observable
final class SceneStore {
    /// One entry in the saves list.
    struct Entry: Identifiable, Sendable {
        var id: String { name }
        var name: String
        var savedAt: Date
        var url: URL
    }

    private(set) var saves: [Entry] = []
    /// What went wrong with the last thing asked of this, if anything. Shown to the reader.
    private(set) var lastProblem: String?

    /// How often the autosave is rewritten, matching the web version.
    static let autosaveInterval: TimeInterval = 8

    private let files = FileManager.default

    private var savesDirectory: URL? {
        guard let documents = files.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = documents.appendingPathComponent("Scenes", isDirectory: true)
        // Created on demand rather than at launch, so a build that never saves anything leaves no
        // trace in the person's files.
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var autosaveURL: URL? {
        guard let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        try? files.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("autosave.json", isDirectory: false)
    }

    // MARK: Coding

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Not pretty-printed. A full world is a large array of numbers and the indentation would
        // several times the file size for something nobody reads.
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Listing

    /// Rebuilds the list of saved scenes.
    func refresh() {
        guard let directory = savesDirectory else {
            saves = []
            return
        }
        let contents = (try? files.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        saves = contents
            .filter { $0.pathExtension == "json" }
            .map { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return Entry(
                    name: url.deletingPathExtension().lastPathComponent,
                    savedAt: modified ?? .distantPast,
                    url: url
                )
            }
            // Newest first, which is what someone looking for what they were just doing wants.
            .sorted { $0.savedAt > $1.savedAt }
    }

    // MARK: Named saves

    /// Writes a scene under a name, replacing any scene already using it.
    @discardableResult
    func save(_ scene: LabScene, as name: String) -> Bool {
        let safe = Self.safeFileName(name)
        guard !safe.isEmpty, let directory = savesDirectory else {
            lastProblem = "That name cannot be used."
            return false
        }
        do {
            let data = try encoder.encode(scene)
            try data.write(to: directory.appendingPathComponent("\(safe).json"), options: .atomic)
            lastProblem = nil
            refresh()
            return true
        } catch {
            lastProblem = "Could not save: \(error.localizedDescription)"
            return false
        }
    }

    /// Reads a scene back.
    func load(_ entry: Entry) -> LabScene? {
        load(from: entry.url)
    }

    /// Reads a scene from anywhere, which is also how an imported file arrives.
    func load(from url: URL) -> LabScene? {
        do {
            let scene = try decoder.decode(LabScene.self, from: try Data(contentsOf: url))
            guard scene.version <= LabScene.currentVersion else {
                lastProblem = "That scene was saved by a newer version of Crucible."
                return nil
            }
            lastProblem = nil
            return scene
        } catch {
            // Deliberately specific about it being the *file* that is the problem. A scene someone
            // hand-edited or a download that was cut short both land here, and "could not be read"
            // is more useful than a silent failure to load.
            lastProblem = "That file could not be read as a Crucible scene."
            return nil
        }
    }

    func delete(_ entry: Entry) {
        try? files.removeItem(at: entry.url)
        refresh()
    }

    /// Writes a scene somewhere it can be shared from, and returns where.
    ///
    /// Into the temporary directory: it is a copy made for the purpose of handing it to something
    /// else, and the system clears it up afterwards.
    func exportForSharing(_ scene: LabScene) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let url = files.temporaryDirectory.appendingPathComponent("crucible-\(stamp).json")
        do {
            try encoder.encode(scene).write(to: url, options: .atomic)
            lastProblem = nil
            return url
        } catch {
            lastProblem = "Could not prepare that scene for sharing."
            return nil
        }
    }

    // MARK: Autosave

    /// Writes the autosave, off the main thread.
    ///
    /// The capture itself has to happen on the main actor, because it reads the live world. Turning
    /// it into JSON does not, and that is the expensive half — a world is over a hundred thousand
    /// cells, and encoding that takes long enough to drop frames. Doing it here on the main thread
    /// would mean a visible stutter every eight seconds, for a file nobody is waiting for.
    ///
    /// Failures are swallowed deliberately. An autosave that cannot be written is not worth
    /// interrupting anyone over, and the next attempt is eight seconds away.
    func writeAutosave(_ scene: LabScene) {
        guard let url = autosaveURL else { return }
        Task.detached(priority: .background) {
            // Built inside the task rather than captured: an encoder is not safe to share across
            // threads, and it costs nothing to make.
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(scene) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func readAutosave() -> LabScene? {
        guard let url = autosaveURL, files.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let scene = try? decoder.decode(LabScene.self, from: data),
              scene.version <= LabScene.currentVersion
        else {
            // A damaged autosave is removed rather than left to fail on every launch. It is a
            // convenience, and one that cannot be read has no value to preserve.
            try? files.removeItem(at: url)
            return nil
        }
        return scene
    }

    func clearAutosave() {
        guard let url = autosaveURL else { return }
        try? files.removeItem(at: url)
    }

    // MARK: Names

    /// Turns whatever someone typed into something that can be a file name.
    ///
    /// Slashes and colons cannot appear in one, a leading dot hides the file, and the length has a
    /// limit. Rather than refusing the name, it is reduced to the nearest usable version — a save
    /// button that rejects what you typed is more annoying than one that tidies it.
    static func safeFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.map { character -> Character in
            if character == "/" || character == ":" || character == "\\" { return "-" }
            return character
        }
        var name = String(cleaned)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.count > 60 { name = String(name.prefix(60)) }
        return name
    }

    /// A name for a scene nobody has named, so saving never demands typing.
    static func defaultName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, HH-mm"
        return formatter.string(from: date)
    }
}
