import CrucibleCore
import Foundation
import SwiftUI
import UIKit

/// Keeps the note of what the world is doing, notices when the last session ended badly, and makes the files that
/// either kind of report is sent as.
///
/// The note itself, and everything decided about it, is `LabBreadcrumb` in the engine, where it is tested. This is the
/// part that needs a phone: which phone it is, where the file goes, when to write it, and when the app is being put
/// away.
///
/// ## Why it is written while the app runs rather than when something goes wrong
///
/// Because when something goes wrong there is nothing running to write anything. A crashed app does not get a last
/// word. So the note is kept up to date as it goes and marked unfinished until the app is put away properly; a note
/// still marked unfinished at the next launch is the evidence.
///
/// ## Why the writing is throttled
///
/// It is a small file, but it is written from the main thread's view of the world and would otherwise be rewritten on
/// every tap. Two seconds is far shorter than anybody can act in, and the file is also written at once whenever the
/// app goes into the background — which is the moment before the phone is most likely to kill it.
@MainActor
@Observable
final class Breadcrumbs {
    /// The note being kept now.
    private(set) var current: LabBreadcrumb
    /// The note left by a session that never finished, if the last one did not. What the offer to send describes.
    private(set) var unfinished: LabBreadcrumb?

    /// Whether to offer to send the unfinished note. Cleared once the offer has been answered, either way.
    var offersLastTime = false

    private let files = FileManager.default
    private let startedAt = CFAbsoluteTimeGetCurrent()
    private var lastWrite = 0.0
    private var writeWanted = false
    /// How long between writes, at most.
    private static let writeEvery = 2.0

    init() {
        let device = UIDevice.current
        current = LabBreadcrumb(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            // The kind of phone, which is what matters, rather than anything that identifies this one.
            device: Self.model,
            system: "\(device.systemName) \(device.systemVersion)"
        )

        // Whatever was left from last time, read before anything overwrites it.
        if let url = Self.noteURL(files: files), let data = try? Data(contentsOf: url),
           let previous = try? JSONDecoder().decode(LabBreadcrumb.self, from: data), previous.describesABadEnding
        {
            unfinished = previous
            offersLastTime = true
        }
        write(now: true)
    }

    /// What kind of phone this is — "iPhone17,2" and the like, which says exactly which model without saying whose.
    private static var model: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            raw.prefix { $0 != 0 }.map { UInt8($0) }
        }
        let name = String(decoding: machine, as: UTF8.self)
        return name.isEmpty ? UIDevice.current.model : name
    }

    /// How long this session has been open.
    private var seconds: Double { CFAbsoluteTimeGetCurrent() - startedAt }

    // MARK: - Keeping it up to date

    /// Notes something that was touched. Short, plain words: this is read by a person.
    func record(_ what: String) {
        current.note(what, secondsIn: seconds)
        write()
    }

    /// Replaces what the world is, from whatever the interface knows. Called on the same beat as the readouts.
    func describe(_ readings: [LabBreadcrumb.Reading]) {
        current.describe(readings)
        write()
    }

    /// The app is being put away properly, so the note is marked finished. Anything after this marks it unfinished
    /// again, which is right: the app is running again.
    func putAway() {
        current.endedCleanly = true
        write(now: true)
    }

    /// The app is on screen again after being put away.
    func cameBack() {
        current.endedCleanly = false
        record("came back to the app")
    }

    /// The offer to send last time's note has been answered.
    func stopOffering() {
        offersLastTime = false
    }

    // MARK: - Writing

    private func write(now: Bool = false) {
        current.seconds = seconds
        let moment = CFAbsoluteTimeGetCurrent()
        if !now {
            guard moment - lastWrite >= Self.writeEvery else {
                writeWanted = true
                return
            }
        }
        lastWrite = moment
        writeWanted = false
        guard let url = Self.noteURL(files: files), let data = try? JSONEncoder().encode(current) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Writes the note if one was wanted while the last was too recent. Called on the once-a-second beat.
    func writeIfWaiting() {
        guard writeWanted else { return }
        write()
    }

    /// Throws away last time's note before anything reads it, for a start that is meant to look like a new install.
    ///
    /// A newly installed app has no last time, so it has nothing to offer to send. Without this, every part of the
    /// walkthrough after the first opened to "Last time ended badly" — the walkthrough closes the app between parts,
    /// which is exactly what a crash looks like from the inside — and the system's own handler dismissing that offer
    /// was a tap landing somewhere on the screen that nobody chose.
    nonisolated static func forgetBeforeLaunch() {
        let files = FileManager.default
        guard let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? files.removeItem(at: support.appendingPathComponent("breadcrumb.json", isDirectory: false))
    }

    private static func noteURL(files: FileManager) -> URL? {
        guard let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? files.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("breadcrumb.json", isDirectory: false)
    }

    // MARK: - Sending one

    /// Everything a report is made of: the note as text, and a picture of the world when there is one.
    struct Report: Identifiable {
        let id = UUID()
        var urls: [URL]
        /// What the sheet says it is sending.
        var title: String
        /// The note itself, shown so somebody can read what they are about to send.
        var text: String
    }

    /// The note of what is happening now, with a picture of the world: the "that looked wrong" button.
    func reportNow(picture: UIImage?) -> Report? {
        var note = current
        note.seconds = seconds
        return report(note, title: "That looked wrong", named: "crucible-report", picture: picture)
    }

    /// Last time's unfinished note, as a report to send.
    func reportLastTime() -> Report? {
        guard let unfinished else { return nil }
        return report(unfinished, title: "Last time ended badly", named: "crucible-last-time")
    }

    private func report(_ note: LabBreadcrumb, title: String, named name: String, picture: UIImage? = nil) -> Report? {
        let text = note.text(title: "Crucible — \(title.lowercased())")
        guard let url = LabSnapshot.write(text: text, named: "\(name)-\(LabSnapshot.fileName())", extension: "txt") else {
            return nil
        }
        var urls = [url]
        if let picture, let shot = LabSnapshot.write(picture, named: "\(name)-\(LabSnapshot.fileName())") {
            urls.append(shot)
        }
        return Report(urls: urls, title: title, text: text)
    }

}
