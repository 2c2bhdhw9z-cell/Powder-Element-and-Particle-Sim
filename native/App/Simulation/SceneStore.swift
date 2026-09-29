import CrucibleCore
import Foundation
import Observation
import UIKit

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

    static let currentVersion = 2
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
        /// A small picture of the world, written beside the file when it was kept. Nothing for a world kept before
        /// there were pictures, or one whose picture could not be made.
        var pictureURL: URL?
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

    /// Removes the world kept from last time, before anything has been read. For the tap-through test, which starts every
    /// run from nothing — see `CrucibleApp`.
    nonisolated static func forgetAutosaveBeforeLaunch() {
        let files = FileManager.default
        guard let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? files.removeItem(at: support.appendingPathComponent("autosave.json", isDirectory: false))
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
                let picture = url.deletingPathExtension().appendingPathExtension("jpg")
                return Entry(
                    name: url.deletingPathExtension().lastPathComponent,
                    savedAt: modified ?? .distantPast,
                    url: url,
                    pictureURL: files.fileExists(atPath: picture.path) ? picture : nil
                )
            }
            // Newest first, which is what someone looking for what they were just doing wants.
            .sorted { $0.savedAt > $1.savedAt }
    }

    // MARK: Named saves

    /// Writes a scene under a name, replacing any scene already using it.
    /// Keeps a scene under a name, with a small picture of it beside it.
    ///
    /// - Parameter picture: what the world looked like, as a JPEG. Optional, and a failure to write it is not a failure
    ///   to keep the world: the world is the thing being kept, and a gallery with one blank square in it is better than
    ///   losing somebody's work over a picture.
    @discardableResult
    func save(_ scene: LabScene, as name: String, picture: Data? = nil) -> Bool {
        let safe = Self.safeFileName(name)
        guard !safe.isEmpty, let directory = savesDirectory else {
            lastProblem = "That name cannot be used."
            return false
        }
        do {
            let data = try encoder.encode(scene)
            try data.write(to: directory.appendingPathComponent("\(safe).json"), options: .atomic)
            let pictureURL = directory.appendingPathComponent("\(safe).jpg")
            if let picture {
                try? picture.write(to: pictureURL, options: .atomic)
            } else {
                // Kept again with no picture: the old one described a world that is no longer there.
                try? files.removeItem(at: pictureURL)
            }
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
        if let picture = entry.pictureURL { try? files.removeItem(at: picture) }
        refresh()
    }

    /// Writes a scene somewhere it can be shared from, and returns where.
    ///
    /// Into the temporary directory: it is a copy made for the purpose of handing it to something
    /// else, and the system clears it up afterwards.
    func exportForSharing(_ scene: LabScene) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        // Its own kind of file, so whoever receives it can open it in Crucible with a tap. The contents are the
        // same as ever, and files of the old kind still open — see ``worldType``.
        let url = files.temporaryDirectory.appendingPathComponent("crucible-\(stamp).\(Self.worldExtension)")
        do {
            try encoder.encode(scene).write(to: url, options: .atomic)
            lastProblem = nil
            return url
        } catch {
            lastProblem = "Could not prepare that scene for sharing."
            return nil
        }
    }

    // MARK: Worlds arriving from elsewhere

    /// The name world files end in.
    static let worldExtension = "crucible"

    /// Whether something handed to the app is a world file, rather than any other address that might arrive.
    static func isWorldFile(_ url: URL) -> Bool {
        url.isFileURL && ["crucible", "json"].contains(url.pathExtension.lowercased())
    }

    /// Reads a world file somebody opened in Crucible from elsewhere — a message, Files, another app.
    ///
    /// The copy the phone makes for the app is removed once read, so worlds opened this way do not pile up unseen.
    func openArrived(_ url: URL) -> LabScene? {
        let claimed = url.startAccessingSecurityScopedResource()
        defer { if claimed { url.stopAccessingSecurityScopedResource() } }
        let scene = load(from: url)
        if url.path.contains("/Inbox/") { try? files.removeItem(at: url) }
        return scene
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
    ///
    /// - Parameter now: write it before returning rather than in the background. For the moment the app
    ///   is leaving the screen: a background write started then could be frozen along with the app before it
    ///   ran, and lost for good if the phone then closed the app to reclaim memory.
    /// The newest captured autosave. At most one is being encoded and one newer capture is waiting; an eight-second
    /// timer can never build an unbounded queue of giant worlds on a slow or hot phone.
    private var autosaveGeneration = 0
    private var pendingAutosave: (scene: LabScene, generation: Int, url: URL)?
    private var autosaveTask: Task<Void, Never>?
    private var backgroundSave: UIBackgroundTaskIdentifier = .invalid
    private var autosaveIsBlocked = false

    func writeAutosave(_ scene: LabScene, now: Bool = false) {
        guard let url = autosaveURL, !autosaveIsForgotten, !autosaveIsBlocked else { return }
        autosaveGeneration &+= 1
        pendingAutosave = (scene, autosaveGeneration, url)

        if now, backgroundSave == .invalid {
            // The phone may suspend the app moments after it leaves the screen. Ask for enough time to finish the one
            // coalesced write, rather than blocking the main thread at exactly the moment iOS is watching it.
            backgroundSave = UIApplication.shared.beginBackgroundTask(withName: "Keep Crucible world") { [weak self] in
                Task { @MainActor in self?.finishBackgroundSave() }
            }
        }
        guard autosaveTask == nil else { return }
        autosaveTask = Task { @MainActor [weak self] in
            await self?.drainAutosaves()
        }
    }

    private func drainAutosaves() async {
        while !Task.isCancelled, let pending = pendingAutosave {
            pendingAutosave = nil
            let data = await Task.detached(priority: .utility) {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                return try? encoder.encode(pending.scene)
            }.value
            guard let data,
                  pending.generation == autosaveGeneration,
                  !autosaveIsForgotten,
                  !autosaveIsBlocked
            else { continue }

            // Disk I/O is off the main actor too. The old code moved only JSON encoding away, then atomically wrote a
            // potentially huge file on the interface thread every eight seconds.
            _ = await Task.detached(priority: .utility) {
                do {
                    try data.write(to: pending.url, options: .atomic)
                    return true
                } catch {
                    return false
                }
            }.value
        }
        autosaveTask = nil
        finishBackgroundSave()
    }

    private func finishBackgroundSave() {
        guard backgroundSave != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundSave)
        backgroundSave = .invalid
    }

    func readAutosave() -> LabScene? {
        guard let url = autosaveURL, files.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let scene = try decoder.decode(LabScene.self, from: data)
            guard scene.version <= LabScene.currentVersion else {
                preserveUnreadableAutosave(url, reason: "The automatic save came from a newer version and was kept for recovery.")
                return nil
            }
            lastProblem = nil
            return scene
        } catch {
            preserveUnreadableAutosave(url, reason: "The automatic save could not be read and was kept for recovery.")
            return nil
        }
    }

    /// Moves a save this build cannot read aside instead of deleting it. If even that fails, all later autosaves are
    /// blocked for this run so the only remaining copy can never be overwritten by the opening scene.
    private func preserveUnreadableAutosave(_ url: URL, reason: String) {
        let recovery = url.deletingLastPathComponent()
            .appendingPathComponent("autosave-recovery-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try files.moveItem(at: url, to: recovery)
            lastProblem = reason
        } catch {
            autosaveIsBlocked = true
            lastProblem = "The automatic save could not be read. It was left untouched and new automatic saves are paused."
        }
    }

    /// Removes the autosave, and stops it being written again until the app is next opened.
    ///
    /// Deleting the file alone did nothing lasting: the eight-second timer, or leaving the app, wrote it
    /// straight back, and the world "forgotten" came back on the next launch.
    func clearAutosave() {
        autosaveGeneration &+= 1
        pendingAutosave = nil
        autosaveIsForgotten = true
        guard let url = autosaveURL else { return }
        let active = autosaveTask
        // If a disk write is already in flight, remove the file after it finishes so it cannot reappear behind Clear.
        Task { @MainActor [weak self] in
            _ = await active?.value
            try? FileManager.default.removeItem(at: url)
            self?.finishBackgroundSave()
        }
    }

    /// Set once the autosave has been forgotten, for the rest of this run of the app.
    private(set) var autosaveIsForgotten = false

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
