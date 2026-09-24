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
    let glass: GlassLevel

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var confirmingDelete: SceneStore.Entry?
    @State private var shareTarget: ShareTarget?
    @State private var isImporting = false
    @State private var note: String?

    var body: some View {
        LabSheet(title: "Your work", subtitle: "Kept here, and shared elsewhere", glass: glass) {
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
    }

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
                if store.save(scene, as: name) {
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
                : "Tap to load, which is one undo away. The arrow sends a copy elsewhere."
        ) {
            if store.saves.isEmpty {
                Text("Nothing kept yet.")
                    .font(.labBody(12))
                    .foregroundStyle(Palette.subtleForeground)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(store.saves.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { LabDivider() }
                    row(for: entry)
                }
            }
        }
    }

    /// One kept scene.
    ///
    /// The share and delete actions are buttons on the row rather than hidden behind a swipe. A swipe
    /// needs the system's list, which is what this panel deliberately is not — and a hidden gesture is
    /// a poor place to put the only way to delete something.
    private func row(for entry: SceneStore.Entry) -> some View {
        HStack(spacing: 4) {
            Button {
                if let scene = store.load(entry) {
                    restore(scene)
                    dismiss()
                } else {
                    note = store.lastProblem
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(.labBody(13))
                        .foregroundStyle(Palette.foreground)
                    Text(entry.savedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.labNumeric(10))
                        .foregroundStyle(Palette.subtleForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            iconAction("square.and.arrow.up", "Share “\(entry.name)”") {
                if let scene = store.load(entry), let url = store.exportForSharing(scene) {
                    shareTarget = ShareTarget(url: url)
                }
            }
            iconAction("trash", "Delete “\(entry.name)”", tint: Palette.danger) {
                confirmingDelete = entry
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
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
                note = "The automatic save has been forgotten."
            }
        }
    }

    private func iconAction(
        _ symbol: String,
        _ label: String,
        tint: Color = Palette.muted,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.labBody(13, .medium))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
