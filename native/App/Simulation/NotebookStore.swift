import CrucibleCore
import SwiftUI

/// The notebook, kept on the phone.
///
/// ## Why the pages are the player's own files
///
/// The same split the rest of the app already draws. A world the player named goes in Documents, because it is theirs.
/// The autosave and the fault report go in Application Support, because they are the app's business and wiping them
/// loses nothing anybody chose. A notebook is plainly the first kind: it is a record of what somebody worked out, and
/// it should outlive a reinstall the way their saved worlds do.
///
/// ## Why a picture is a separate file
///
/// Copied from the gallery of kept worlds, which does the same thing for the same reason: the index is a small piece of
/// text that is read every launch, and a dozen pictures inside it would make that read a megabyte. So a page's picture
/// sits beside it, named after it, and a page with no picture is a page with a blank square — never a lost page.
@MainActor
@Observable
final class NotebookStore {
    /// What has been found.
    private(set) var notebook = DiscoveryNotebook()

    /// The most recent find, for showing a note on screen. Cleared by the interface once it has been shown.
    var justFound: Discovery?

    /// What went wrong the last time this was asked to write something, if anything.
    private(set) var lastProblem: String?

    private let files = FileManager.default

    /// Where the notebook and its pictures live.
    private var directory: URL? {
        guard let documents = files.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let folder = documents.appendingPathComponent("Notebook", isDirectory: true)
        // Made when it is first needed, so somebody who never finds anything is left with no folder at all.
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private var indexURL: URL? {
        directory?.appendingPathComponent("notebook.json", isDirectory: false)
    }

    /// Where one page's picture goes.
    func pictureURL(for id: String) -> URL? {
        directory?.appendingPathComponent("\(DiscoveryNotebook.safeName(id)).jpg", isDirectory: false)
    }

    /// The picture for a page, if one was kept.
    func picture(for id: String) -> UIImage? {
        guard let url = pictureURL(for: id), files.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    init() {
        read()
    }

    /// Reads the notebook from the phone.
    ///
    /// A notebook that will not decode is left alone rather than replaced: the file is the only copy of somebody's
    /// record, and overwriting it with an empty one because of a bad byte would destroy the thing this exists to keep.
    func read() {
        guard let url = indexURL, let data = try? Data(contentsOf: url) else { return }
        guard let read = try? JSONDecoder().decode(DiscoveryNotebook.self, from: data) else {
            lastProblem = "The notebook could not be read. It has been left as it is rather than started again."
            return
        }
        notebook = read
    }

    private func write() {
        guard let url = indexURL else { return }
        do {
            try JSONEncoder().encode(notebook).write(to: url, options: .atomic)
            lastProblem = nil
        } catch {
            lastProblem = "The notebook could not be saved: \(error.localizedDescription)"
        }
    }

    /// Notes a find, with a picture of the moment.
    ///
    /// - Parameter picture: made only when this turns out to be the first time, which is why it is a closure rather
    ///   than an image. Taking a picture of the world costs a render and a shrink, and this is called from the middle of
    ///   a frame for something that has usually been found already.
    /// - Returns: whether it was new.
    @discardableResult
    func note(_ discovery: Discovery, chamber: String, picture: () -> Data?) -> Bool {
        guard notebook.note(discovery.id, at: Date().timeIntervalSince1970, chamber: chamber) else { return false }
        if let data = picture(), let url = pictureURL(for: discovery.id) {
            // A picture that will not write is not a reason to lose the page.
            try? data.write(to: url, options: .atomic)
        }
        write()
        justFound = discovery
        return true
    }

    /// Notes a find by name.
    @discardableResult
    func note(_ id: String, chamber: String, picture: () -> Data?) -> Bool {
        guard let discovery = Discoveries.named(id) else { return false }
        return note(discovery, chamber: chamber, picture: picture)
    }

    /// Empties the notebook and its pictures.
    ///
    /// Offered because a notebook is a record of finding things out, and somebody handing the phone to a child who has
    /// not found any of it yet has a reasonable thing to ask for. The pictures go with it — leaving them would mean the
    /// next find quietly came with somebody else's photograph.
    func startAgain() {
        for page in notebook.pages {
            if let url = pictureURL(for: page.discovery) { try? files.removeItem(at: url) }
        }
        notebook = DiscoveryNotebook()
        justFound = nil
        write()
    }
}

extension DiscoveryNotebook {
    /// A discovery's name as something safe to use as a file name.
    ///
    /// The names are written in this program and are all plain lowercase words, so this changes nothing today. It is
    /// here because a name is what a page is filed under, and the day somebody adds a discovery called "sand/glass" is
    /// the day a page starts being written into a folder that does not exist.
    static func safeName(_ id: String) -> String {
        let usable = id.unicodeScalars.map { scalar -> Character in
            let character = Character(scalar)
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }
        let trimmed = String(usable).prefix(60)
        return trimmed.isEmpty ? "page" : String(trimmed)
    }
}
