import CrucibleCore
import Foundation

/// Which lab book experiments have been done, kept on the phone beside the notebook.
///
/// In Documents, like the notebook, because it is a record of somebody's own work rather than the app's business.
@MainActor
@Observable
final class LabBookStore {
    private(set) var progress = LabBookProgress()
    /// What went wrong the last time this was asked to write, if anything.
    private(set) var lastProblem: String?

    private var url: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LabBook.json", isDirectory: false)
    }

    init() {
        guard let url, let data = try? Data(contentsOf: url) else { return }
        // Left alone rather than replaced if it will not read, for the same reason as the notebook: it is the only copy.
        if let read = try? JSONDecoder().decode(LabBookProgress.self, from: data) {
            progress = read
        } else {
            lastProblem = "The lab book's record could not be read. It has been left as it is."
        }
    }

    /// Writes an experiment down as done.
    func finish(_ run: LabBookRun) {
        progress.finish(run.experiment.id, guessedRight: run.guessedRight ?? false, at: Date().timeIntervalSince1970)
        guard let url else { return }
        do {
            try JSONEncoder().encode(progress).write(to: url, options: .atomic)
            lastProblem = nil
        } catch {
            lastProblem = "The lab book could not be saved: \(error.localizedDescription)"
        }
    }
}
