import CrucibleCore
import SwiftUI
// For shrinking a picture of the world for the gallery.
import UIKit
import UniformTypeIdentifiers

/// Saving, loading, and handing a scene to something else.
///
/// A scene holds both chambers together, because the two can pass material to one another and a
/// pairing is something someone might have built on purpose.
struct SavesSheet: View {
    let powder: SimulationModel
    let field: ParticleFieldModel
    /// Which chamber is on screen, so the picture kept with a world is of what was being looked at.
    let chamber: Chamber
    let store: SceneStore

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var confirmingDelete: SceneStore.Entry?
    @State private var shareTarget: ShareTarget?
    @State private var isImporting = false
    @State private var note: String?

    var body: some View {
        LabSheet(title: "Your work", subtitle: "Kept here, and shared elsewhere") {
            saving
            list
            transfer
        }
        .onAppear {
            store.refresh()
            // Pre-filled with the date and time, so saving never demands typing. Someone who wants
            // to name it can; someone who just wants it kept can tap once.
            if name.isEmpty { name = SceneStore.defaultName() }
        }
        .confirmationDialog(
            "Delete “\(confirmingDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = confirmingDelete { store.delete(entry) }
                confirmingDelete = nil
            }
            Button("Keep it", role: .cancel) { confirmingDelete = nil }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [Self.worldType, .json]) { result in
            switch result {
            case let .success(url):
                // The picker hands back a URL the app may not otherwise be allowed to read, so
                // access has to be claimed around the read and given back afterwards.
                let claimed = url.startAccessingSecurityScopedResource()
                defer { if claimed { url.stopAccessingSecurityScopedResource() } }
                if let scene = store.load(from: url) {
                    restore(scene)
                } else {
                    note = store.lastProblem
                }
            case .failure:
                note = "That file could not be opened."
            }
        }
        .sheet(item: $shareTarget) { target in
            ShareLink(item: target.url) {
                Label("Share this scene", systemImage: "square.and.arrow.up")
            }
            .padding()
            .presentationDetents([.height(120)])
            .presentationBackground(Palette.background)
        }
    }

    /// A Crucible world file, as the app declares it. Files from before it had a kind of their own are plain JSON,
    /// and still open.
    static let worldType = UTType(exportedAs: "com.crucible.lab.world", conformingTo: .json)

    // MARK: Sections

    private var saving: some View {
        LabGroup(
            "Keep",
            footnote: note ?? "Both chambers are kept together, along with any materials you invented."
        ) {
            HStack(spacing: 8) {
                TextField("Name", text: $name)
                    .font(.labBody(13))
                    .foregroundStyle(Palette.foreground)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)

            LabDivider()
            LabAction(label: "Keep this scene", symbol: "square.and.arrow.down") {
                let scene = currentScene()
                if store.save(scene, as: name, picture: picture()) {
                    note = "Kept as “\(SceneStore.safeFileName(name))”."
                } else {
                    note = store.lastProblem
                }
            }
            .disabled(SceneStore.safeFileName(name).isEmpty)
            .opacity(SceneStore.safeFileName(name).isEmpty ? 0.4 : 1)
        }
    }

    @ViewBuilder
    private var list: some View {
        LabGroup(
            "Kept",
            footnote: store.saves.isEmpty
                ? nil
                : "Tap a world to load it, which is one undo away. Hold one for the ways to send or delete it."
        ) {
            if store.saves.isEmpty {
                Text("Nothing kept yet.")
                    .font(.labBody(12))
                    .foregroundStyle(Palette.subtleForeground)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // A gallery rather than a list of names, because a name is not what anybody remembers about a world
                // they built. Worlds kept before there were pictures show as a plain square with their name on it,
                // which is what they always were.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(store.saves) { entry in
                        card(for: entry)
                    }
                }
                .padding(14)
            }
        }
    }

    /// One kept world, as a picture with its name under it.
    ///
    /// Tapping loads it. Sending and deleting are behind a hold, with the names of both spelled out, rather than two
    /// small buttons crowding every card — and deleting asks first, because a tap on a small square should not be able
    /// to throw away something somebody built.
    private func card(for entry: SceneStore.Entry) -> some View {
        Button {
            Haptics.selection()
            if let scene = store.load(entry) {
                restore(scene)
                note = "Loaded “\(entry.name)”. Undo brings back what was there."
            } else {
                note = store.lastProblem
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    if let picture = entry.pictureURL, let image = UIImage(contentsOfFile: picture.path) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.labBody(18))
                            .foregroundStyle(Palette.subtleForeground)
                    }
                }
                .frame(height: 104)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .stroke(Palette.border, lineWidth: 1)
                )

                Text(entry.name)
                    .font(.labBody(12, .medium))
                    .foregroundStyle(Palette.foreground)
                    .lineLimit(1)
                Text(entry.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.labNumeric(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("kept.\(entry.name)")
        .accessibilityHint("Double tap to load. Touch and hold for the ways to send or delete it.")
        .contextMenu {
            Button {
                guard let scene = store.load(entry), let url = store.exportForSharing(scene) else {
                    note = store.lastProblem ?? "That world could not be sent."
                    return
                }
                shareTarget = ShareTarget(url: url)
            } label: {
                Label("Send a copy", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                // Asked first, and by name: a world somebody built should not go because of one tap on a small square.
                confirmingDelete = entry
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// A small picture of whichever chamber is on screen, for the gallery.
    ///
    /// Made from the engine's own pixels rather than by grabbing the screen, like every other picture here, and shrunk
    /// to something a gallery can hold: a full-size one of each kept world would be megabytes apiece.
    private func picture() -> Data? {
        let image = chamber == .powder ? powder.snapshot() : field.snapshot()
        guard let image else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 320 / longest)
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let shrunk = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return shrunk.jpegData(compressionQuality: 0.8)
    }

    private var transfer: some View {
        LabGroup(
            "Elsewhere",
            footnote: "Crucible keeps your work by itself every few seconds and whenever you leave "
                + "the app, and puts it back next time. That is separate from the scenes above."
        ) {
            LabAction(label: "Send this scene somewhere", symbol: "square.and.arrow.up") {
                if let url = store.exportForSharing(currentScene()) {
                    shareTarget = ShareTarget(url: url)
                }
            }
            LabDivider()
            LabAction(label: "Open a scene file", symbol: "folder") {
                isImporting = true
            }
            LabDivider()
            LabAction(
                label: "Forget the automatic save",
                symbol: "clock.badge.xmark",
                isDestructive: true
            ) {
                store.clearAutosave()
                note = "The automatic save has been forgotten. Nothing more is saved automatically until "
                    + "Crucible is next opened."
            }
        }
    }

    // MARK: Pieces

    private func currentScene() -> LabScene {
        LabScene(
            version: LabScene.currentVersion,
            savedAt: Date(),
            powder: powder.captureState(),
            particle: field.captureState(),
            customElements: powder.customElements
        )
    }

    /// Puts a scene back into both chambers.
    ///
    /// The invented materials go in **before** the worlds, or a cell referring to one of them lands
    /// in a world that does not know what it is and is quietly turned into air.
    private func restore(_ scene: LabScene) {
        powder.adopt(scene.customElements)
        if let state = scene.powder, !powder.apply(state) {
            note = "That scene's powder world could not be used."
            return
        }
        if let state = scene.particle, !field.apply(state) {
            note = "That scene's particle field could not be used."
            return
        }
        note = nil
    }
}

/// A file about to be handed to something else, made presentable as a sheet.
///
/// A wrapper rather than making `URL` itself identifiable. Conforming a type from Foundation to a
/// protocol it does not declare is the kind of thing that compiles today and collides with a future
/// SDK — and it would affect every URL in the app, to serve one sheet.
struct ShareTarget: Identifiable {
    let id = UUID()
    let url: URL

    /// What the button that sends it says, from what kind of file it is — so a spreadsheet of measurements is not
    /// offered as "this picture".
    var label: String {
        switch url.pathExtension.lowercased() {
        case "svg": "Share the line drawing"
        case "csv": "Share the measurements"
        case "png": url.lastPathComponent.contains("-poster") ? "Share the poster" : "Share this picture"
        case "crucible", "json": "Share this world"
        case "mp4", "mov": "Share the clip"
        case "usdz": "Share this moment in 3D"
        default: "Share"
        }
    }

    /// The picture on that button.
    var symbol: String {
        switch url.pathExtension.lowercased() {
        case "svg": "pencil.and.outline"
        case "csv": "tablecells"
        case "png": "photo"
        case "mp4", "mov": "film"
        case "usdz": "cube"
        default: "square.and.arrow.up"
        }
    }
}
