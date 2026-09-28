import CrucibleCore
import SwiftUI

/// The notebook: what has been found, with a picture of the moment, and what is left to look for.
///
/// ## Why the unfound ones are shown at all
///
/// A list of only what you have found tells you nothing about what you have not, and the whole reason this exists is
/// that the lab is much larger than people realise — there is no menu anywhere that says sand becomes glass. So the
/// ones still to find are listed too, by name, each with something to try.
///
/// What they do *not* show is the answer. "Get sand very hot" is a thing to go and do; "heat sand above fourteen
/// hundred and fifty degrees" is the discovery itself, printed, which would leave nothing to find.
struct NotebookSheet: View {
    let store: NotebookStore

    @State private var confirmingStartAgain = false

    var body: some View {
        LabSheet(title: "Notebook", subtitle: "What you have worked out") {
            header
            if store.notebook.found > 0 { found }
            stillToFind
            if let problem = store.lastProblem {
                Text(problem)
                    .font(.labBody(10))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.notebook.found > 0 { startAgain }
        }
    }

    private var header: some View {
        LabGroup(
            footnote: "Nothing to unlock and no score. Keep playing and anything the world makes by itself for the "
                + "first time is written down here, with a picture of the moment. Painting something does not count — "
                + "making it happen does."
        ) {
            HStack(spacing: 10) {
                Text("\(store.notebook.found)")
                    .font(.labNumeric(28, .semiBold))
                    .foregroundStyle(Palette.foreground)
                Text("of \(store.notebook.howMany) found")
                    .font(.labBody(12))
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
            }
            .accessibilityIdentifier("notebook.count")
        }
    }

    private var found: some View {
        LabGroup("Found") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                ForEach(store.notebook.inOrder) { page in
                    if let discovery = Discoveries.named(page.discovery) {
                        card(discovery, page)
                    }
                }
            }
        }
    }

    private func card(_ discovery: Discovery, _ page: DiscoveryNotebook.Page) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Palette.subtle)
                if let picture = store.picture(for: discovery.id) {
                    Image(uiImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // A page whose picture could not be written is still a page. Never a gap in the list.
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.subtleForeground)
                }
            }
            .frame(height: 92)
            .clipped()

            Text(discovery.name)
                .font(.labBody(11, .semiBold))
                .foregroundStyle(Palette.foreground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(discovery.about)
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text(when(page.at))
                .font(.labNumeric(9))
                .foregroundStyle(Palette.subtleForeground)
        }
        .accessibilityIdentifier("notebook.found.\(discovery.id)")
    }

    private var stillToFind: some View {
        LabGroup(
            store.notebook.found > 0 ? "Still to find" : "To find",
            footnote: store.notebook.stillToFind.isEmpty
                ? "That is all of them."
                : "Something to try for each. Not the answer — that is the part worth finding."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.notebook.stillToFind) { discovery in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.subtleForeground)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(discovery.name)
                                .font(.labBody(11, .medium))
                                .foregroundStyle(Palette.muted)
                            Text(discovery.hint)
                                .font(.labBody(10))
                                .foregroundStyle(Palette.subtleForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityIdentifier("notebook.missing.\(discovery.id)")
                }
            }
        }
    }

    private var startAgain: some View {
        LabGroup(footnote: "Empties the notebook and its pictures, so somebody else can find it all themselves.") {
            Button {
                confirmingStartAgain = true
            } label: {
                Text("Start the notebook again")
                    .font(.labBody(11, .medium))
                    .foregroundStyle(Palette.danger)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notebook.startAgain")
            .confirmationDialog(
                "Empty the notebook?",
                isPresented: $confirmingStartAgain,
                titleVisibility: .visible
            ) {
                Button("Empty it", role: .destructive) { store.startAgain() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("The \(store.notebook.found) pages and their pictures go. Your worlds are not touched.")
            }
        }
    }

    /// When a page was written, in words rather than a timestamp.
    private func when(_ seconds: Double) -> String {
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// The small note that slides in when something is found.
///
/// Deliberately not a panel that has to be dismissed. Finding something happens in the middle of doing something else —
/// often in the middle of an explosion — and stopping the world to announce it would be the most annoying possible way
/// to reward somebody for playing.
struct DiscoveryNote: View {
    let discovery: Discovery
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.foreground)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Written down")
                        .font(.labBody(9))
                        .foregroundStyle(Palette.subtleForeground)
                    Text(discovery.name)
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.foreground)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Palette.elevated)
                    .overlay(Capsule().strokeBorder(Palette.border))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notebook.note")
    }
}
