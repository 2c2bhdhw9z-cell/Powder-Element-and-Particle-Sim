import CrucibleCore
import SwiftUI
import UniformTypeIdentifiers

/// Saving, loading, and handing a scene to something else.
///
/// A scene holds both chambers together, because the two can pass material to one another and a
/// pairing is something someone might have built on purpose.
struct SavesSheet: View {
    let powder: SimulationModel
    let field: ParticleFieldModel
    let store: SceneStore

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var confirmingDelete: SceneStore.Entry?
    @State private var shareTarget: ShareTarget?
    @State private var isImporting = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            Form {
                saving
                list
                transfer
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            store.refresh()
            // Pre-filled with the date and time, so saving never demands typing. Someone who wants
            // to name it can; someone who just wants it kept can tap once.
            if name.isEmpty { name = SceneStore.defaultName() }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
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
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
        .tint(Palette.primary)
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private var saving: some View {
        Section {
            TextField("Name", text: $name)
                .font(.labBody(14))
                .submitLabel(.done)
            Button {
                let scene = currentScene()
                if store.save(scene, as: name) {
                    note = "Kept as “\(SceneStore.safeFileName(name))”."
                } else {
                    note = store.lastProblem
                }
            } label: {
                Label("Keep this scene", systemImage: "square.and.arrow.down")
            }
            .disabled(SceneStore.safeFileName(name).isEmpty)
        } header: {
            Text("Keep")
        } footer: {
            if let note {
                Text(note)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.ok)
            } else {
                Text("Both chambers are kept together, along with any materials you invented.")
                    .font(.labBody(11))
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        Section {
            if store.saves.isEmpty {
                Text("Nothing kept yet.")
                    .font(.labBody(12))
                    .foregroundStyle(Palette.subtleForeground)
            } else {
                ForEach(store.saves) { entry in
                    Button {
                        if let scene = store.load(entry) {
                            restore(scene)
                            dismiss()
                        } else {
                            note = store.lastProblem
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .foregroundStyle(Palette.foreground)
                            Text(entry.savedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.labNumeric(10))
                                .foregroundStyle(Palette.subtleForeground)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            if let scene = store.load(entry),
                               let url = store.exportForSharing(scene) {
                                shareTarget = ShareTarget(url: url)
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        } header: {
            Text("Kept")
        } footer: {
            Text("Tap to load. Swipe a row for sharing and deleting. Loading is one undo away.")
                .font(.labBody(11))
        }
    }

    private var transfer: some View {
        Section {
            Button {
                if let url = store.exportForSharing(currentScene()) {
                    shareTarget = ShareTarget(url: url)
                }
            } label: {
                Label("Send this scene somewhere", systemImage: "square.and.arrow.up")
            }
            Button {
                isImporting = true
            } label: {
                Label("Open a scene file", systemImage: "square.and.arrow.down.on.square")
            }
            Button(role: .destructive) {
                store.clearAutosave()
                note = "The automatic save has been forgotten."
            } label: {
                Label("Forget the automatic save", systemImage: "clock.badge.xmark")
            }
        } header: {
            Text("Elsewhere")
        } footer: {
            Text(
                "Crucible keeps your work automatically every few seconds and when you leave the "
                    + "app, and puts it back next time. That is separate from the scenes above."
            )
            .font(.labBody(11))
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
}
