import CrucibleCore
import SwiftUI
// For UIImage, which a picture of the world is returned as.
import UIKit

/// Which half of the lab is on screen.
enum Chamber: String, CaseIterable, Codable {
    case powder
    case field

    var title: String {
        switch self {
        case .powder: "Powder"
        case .field: "Field"
        }
    }

    var symbol: String {
        switch self {
        case .powder: "square.grid.3x3.fill"
        case .field: "circle.hexagongrid.fill"
        }
    }
}

/// The lab.
///
/// Two chambers sharing one screen: a grid of falling material, and a field of bodies with forces
/// between them. Whichever is on screen fills it, and everything else floats over the top —
/// tools at the upper left, a dock along the bottom. Same arrangement as the web version, and for
/// the same reason: the world is the thing, and the controls should stay out of its way.
///
/// The two chambers are kept as separate objects rather than behind one interface. They have
/// almost nothing in common — one is stepped cell by cell from the bottom up, the other is a list
/// of bodies pulling on one another — and an abstraction over both would have to be so thin as to
/// only obscure which was which.
struct ContentView: View {
    @State private var powder = SimulationModel()
    @State private var field = ParticleFieldModel()
    /// One sensor for both chambers. There is only one phone being tilted, and a second reader
    /// would mean a second stream of readings for nothing.
    @State private var tilt = TiltSensor()
    /// One speaker for the whole app.
    @State private var audio = LabAudio()
    @State private var store = SceneStore()
    @State private var recorder = ScreenRecorder()

    @State private var isDockOpen = false
    @State private var showingScenes = false
    @State private var showingPresets = false
    @State private var showingSettings = false
    @State private var showingDiagnostics = false
    @State private var showingPeriodic = false
    @State private var showingSaves = false
    @State private var showingEditor = false
    @State private var showingFieldSettings = false
    @State private var showingHelp = false
    /// Bumped when the set of materials changes, which is what makes the palette rebuild. The dock's
    /// rows are derived from the registry, and a registry is a class — SwiftUI cannot see inside it.
    @State private var paletteVersion = 0
    /// Whether the autosave has been read. Once only, and before anything else touches a world.
    @State private var hasRestored = false
    /// Which material's card is open, if any. Held as the element rather than a flag so the sheet
    /// cannot be shown without knowing what it is describing.
    @State private var infoElement: ElementInfoTarget?
    /// A picture waiting to be sent somewhere.
    @State private var shareTarget: ShareTarget?

    /// Remembered between launches. All three are preferences rather than state: coming back to
    /// the chamber you were in, the interface you chose, and the readout you left on.
    @AppStorage("chamber") private var chamberRaw = Chamber.powder.rawValue
    @AppStorage("glassLevel") private var glassRaw = GlassLevel.full.rawValue
    @AppStorage("showDebugOverlay") private var showDebugOverlay = false
    @AppStorage("soundEnabled") private var soundEnabled = true

    @Environment(\.scenePhase) private var scenePhase

    private var chamber: Chamber { Chamber(rawValue: chamberRaw) ?? .powder }
    private var glass: GlassLevel { GlassLevel(rawValue: glassRaw) ?? .full }

    var body: some View {
        // Header, world, dock — stacked, the way the reference arranges them. The world used to fill
        // the whole screen with the controls floating over it, which reads as a utility with things
        // stuck on it rather than as a place with a name.
        VStack(spacing: 0) {
            LabHeader(
                chamber: chamber,
                isRunning: isRunning,
                framesPerSecond: framesPerSecond,
                glass: glass,
                onToggleRunning: toggleRunning,
                onSelectChamber: select,
                onShowMenu: { showingSettings = true }
            )

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    surface(for: geometry.size)

                    VStack(alignment: .leading, spacing: 8) {
                        tools
                        if showDebugOverlay { debugReadout }
                    }
                    .padding(.leading, 8)
                    .padding(.top, 8)
                }
            }
            // The world keeps its own black even while a sheet is over it, so nothing shows through.
            .background(Palette.background)

            dock
        }
        // Only the bottom, so the dock's backdrop reaches under the home indicator. The top is left
        // alone deliberately: the header should sit below the island rather than under it.
        .ignoresSafeArea(edges: .bottom)
        .background(Palette.background)
        .preferredColorScheme(.dark)
        .tint(Palette.primary)
        .onAppear {
            // Handed to both models rather than read by the views, so gravity is applied at the
            // start of a tick — in step with the simulation instead of whenever SwiftUI happens
            // to notice a change.
            powder.tilt = tilt
            field.tilt = tilt
            powder.audio = audio
            audio.isEnabled = soundEnabled
            restoreAutosaveOnce()
        }
        // Every eight seconds, matching the web version.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SceneStore.autosaveInterval))
                writeAutosave()
            }
        }
        // And on the way out. A phone can kill a backgrounded app with no further warning, so this
        // is the last reliable moment to keep anything — a timer alone would lose up to eight
        // seconds of work every time.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { writeAutosave() }
        }
        .onChange(of: soundEnabled) { _, wanted in
            audio.isEnabled = wanted
        }
        .sheet(isPresented: $showingScenes) {
            ScenePicker(glass: glass) { recipe in
                powder.loadScene(recipe)
                showingScenes = false
            }
        }
        .sheet(isPresented: $showingPresets) {
            FieldPresetPicker(glass: glass) { preset in
                field.loadPreset(preset)
                showingPresets = false
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(
                model: powder,
                glass: Binding(get: { glass }, set: { glassRaw = $0.rawValue }),
                showDebugOverlay: $showDebugOverlay,
                soundEnabled: $soundEnabled,
                onShowDiagnostics: {
                    showingSettings = false
                    showingDiagnostics = true
                },
                onShowHelp: {
                    // Closed first: a sheet cannot sensibly present another on top of itself.
                    showingSettings = false
                    showingHelp = true
                }
            )
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsSheet(model: powder, glass: glass)
        }
        .sheet(isPresented: $showingHelp) {
            HelpSheet(glass: glass)
        }
        .sheet(isPresented: $showingPeriodic) {
            PeriodicSheet(model: powder, glass: glass) { id in
                powder.brushElement = id
                showingPeriodic = false
            }
        }
        .sheet(item: $infoElement) { target in
            ElementInfoSheet(model: powder, elementID: target.id, glass: glass)
        }
        .sheet(isPresented: $showingSaves) {
            SavesSheet(powder: powder, field: field, store: store, glass: glass)
        }
        .sheet(isPresented: $showingEditor) {
            ElementEditorSheet(model: powder, glass: glass) { paletteVersion += 1 }
        }
        .sheet(isPresented: $showingFieldSettings) {
            FieldSettingsSheet(model: field, glass: glass)
        }
        // Driven straight off the recorder, which publishes the preview already wrapped. The binding
        // writes nothing back except a dismissal, so the cover and the recorder cannot disagree about
        // whether a preview is showing.
        .fullScreenCover(
            item: Binding(
                get: { recorder.pending },
                set: { if $0 == nil { recorder.dismissPreview() } }
            )
        ) { target in
            // Full screen rather than a sheet, because the preview is a video player with its own
            // controls and a half-height card would leave it unusable.
            RecordingPreview(controller: target.controller)
                .ignoresSafeArea()
        }
        .alert(
            "Recording",
            isPresented: Binding(
                get: { recorder.problem != nil },
                set: { if !$0 { recorder.clearProblem() } }
            )
        ) {
            Button("All right") { recorder.clearProblem() }
        } message: {
            Text(recorder.problem ?? "")
        }
        .sheet(item: $shareTarget) { target in
            // The system's own share sheet, which is the one place it is right to look like iOS
            // rather than like Crucible — it is the phone's furniture, not the app's.
            ShareLink(item: target.url) {
                Label("Share this picture", systemImage: "square.and.arrow.up")
                    .font(.labBody(14, .medium))
            }
            .padding(24)
            .presentationDetents([.height(140)])
            .presentationBackground(Palette.background)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - What the header reads

    /// Whichever chamber is on screen decides what play, pause and the frame counter refer to.
    private var isRunning: Bool {
        chamber == .powder ? powder.isRunning : field.isRunning
    }

    private var framesPerSecond: Int {
        chamber == .powder ? powder.ticksPerSecond : field.ticksPerSecond
    }

    private func toggleRunning() {
        switch chamber {
        case .powder: powder.isRunning.toggle()
        case .field: field.isRunning.toggle()
        }
    }

    private func select(_ option: Chamber) {
        chamberRaw = option.rawValue
        // Closed on the way across, since the two trays hold different things and leaving one open
        // would swap its contents out from under your hand.
        isDockOpen = false
    }

    // MARK: - Keeping work

    /// Puts back whatever was on screen last time.
    ///
    /// Once per launch, and before anything else has touched a world — otherwise it would overwrite
    /// a scene someone had already started building in the same session.
    private func restoreAutosaveOnce() {
        guard !hasRestored else { return }
        hasRestored = true
        guard let scene = store.readAutosave() else { return }
        powder.adopt(scene.customElements)
        if let state = scene.powder { powder.apply(state) }
        if let state = scene.particle { field.apply(state) }
    }

    private func writeAutosave() {
        store.writeAutosave(
            LabScene(
                version: LabScene.currentVersion,
                savedAt: Date(),
                powder: powder.captureState(),
                particle: field.captureState(),
                customElements: powder.customElements
            )
        )
    }

    // MARK: - Pieces

    @ViewBuilder
    private func surface(for size: CGSize) -> some View {
        switch chamber {
        case .powder:
            SimulationSurface(model: powder)
                .ignoresSafeArea()
                // The whole surface jolts when something goes off. Only the simulation moves —
                // the dock and the tools stay put, because chrome that shakes reads as the app
                // glitching rather than as the world being hit.
                .offset(x: powder.screenShakeOffset.width, y: powder.screenShakeOffset.height)
                .onAppear { powder.resize(toViewSize: size, scale: UIScreen.main.scale) }
                .onChange(of: size) { _, new in
                    powder.resize(toViewSize: new, scale: UIScreen.main.scale)
                }
        case .field:
            FieldSurface(model: field)
                .ignoresSafeArea()
                .onAppear { field.resize(toViewSize: size, scale: UIScreen.main.scale) }
                .onChange(of: size) { _, new in
                    field.resize(toViewSize: new, scale: UIScreen.main.scale)
                }
        }
    }

    @ViewBuilder
    private var tools: some View {
        switch chamber {
        case .powder:
            ToolCluster(
                model: powder,
                tilt: tilt,
                recorder: recorder,
                glass: glass,
                shareTarget: $shareTarget
            )
        case .field:
            FieldToolCluster(
                model: field,
                tilt: tilt,
                recorder: recorder,
                glass: glass,
                shareTarget: $shareTarget
            )
        }
    }

    @ViewBuilder
    private var debugReadout: some View {
        switch chamber {
        case .powder: DebugOverlay(model: powder, glass: glass)
        case .field: FieldDebugOverlay(model: field, glass: glass)
        }
    }

    @ViewBuilder
    private var dock: some View {
        switch chamber {
        case .powder:
            ElementDock(
                model: powder,
                glass: glass,
                isOpen: $isDockOpen,
                onShowScenes: { showingScenes = true },
                onShowSettings: { showingSettings = true },
                onShowInfo: { infoElement = ElementInfoTarget(id: $0) },
                onShowPeriodic: { showingPeriodic = true },
                onShowSaves: { showingSaves = true },
                onShowEditor: { showingEditor = true },
                paletteVersion: paletteVersion
            )
        case .field:
            FieldDock(
                model: field,
                glass: glass,
                isOpen: $isDockOpen,
                onShowPresets: { showingPresets = true },
                // Its own sheet, not the powder world's. Almost nothing carries over between them —
                // there are no cells here, no temperature and no wind — so sharing one would be a
                // list of controls that mostly did not apply.
                onShowSettings: { showingFieldSettings = true }
            )
        }
    }
}

/// Picks one of the built-in powder scenes.
///
/// A grid of chips rather than a list of rows with chevrons. Thirteen scenes fit on one screen that
/// way, and none of them leads anywhere — each one just loads, so a chevron promising a further
/// screen is a small lie.
struct ScenePicker: View {
    let glass: GlassLevel
    let onSelect: (PowderRecipe) -> Void

    var body: some View {
        LabSheet(
            title: "Scenes",
            subtitle: "Thirteen worlds to start from",
            glass: glass
        ) {
            LabGroup(footnote: "Loading a scene replaces the world. Undo brings it back.") {
                LabFlow(spacing: 6) {
                    ForEach(powderRecipes, id: \.id) { recipe in
                        Button { onSelect(recipe) } label: {
                            Text(recipe.name)
                                .font(.labBody(12, .medium))
                                .foregroundStyle(Palette.foreground)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
    }
}

/// The floating tools for the particle chamber.
struct FieldToolCluster: View {
    let model: ParticleFieldModel
    let tilt: TiltSensor
    let recorder: ScreenRecorder
    let glass: GlassLevel
    @Binding var shareTarget: ShareTarget?

    private static let speeds: [Double] = [0.25, 0.5, 1, 2, 4]

    var body: some View {
        GlassGroup(level: glass) {
            HStack(alignment: .top, spacing: 6) {
                HStack(spacing: 0) {
                    button("arrow.uturn.backward", "Undo", enabled: model.canUndo) { model.undo() }
                    button("arrow.uturn.forward", "Redo", enabled: model.canRedo) { model.redo() }
                    button("camera", "Take a picture", enabled: true) {
                        // Asked of the Metal view, because the field is geometry the GPU assembles
                        // and none of it exists anywhere the processor can see.
                        guard let image = model.snapshot(),
                              let url = LabSnapshot.write(image, named: LabSnapshot.fileName())
                        else { return }
                        shareTarget = ShareTarget(url: url)
                    }
                    RecordButton(recorder: recorder)
                }
                .glassPanel(glass)

                HStack(spacing: 0) {
                    ForEach(Self.speeds, id: \.self) { value in
                        Button {
                            model.speed = value
                        } label: {
                            Text(ToolClusterLabels.speed(value))
                                .font(.labNumeric(11))
                                .foregroundStyle(
                                    model.speed == value ? Palette.foreground : Palette.muted
                                )
                                .frame(minWidth: 34, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .glassPanel(glass)

                TiltButton(tilt: tilt, glass: glass)
            }
        }
    }

    private func button(
        _ symbol: String,
        _ label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.labBody(14, .medium))
                .foregroundStyle(enabled ? Palette.muted : Palette.subtleForeground)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}

/// The performance readout for the particle chamber.
struct FieldDebugOverlay: View {
    let model: ParticleFieldModel
    let glass: GlassLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("fps", "\(model.ticksPerSecond)")
            row("ms/tick", model.millisecondsPerTick.formatted(.number.precision(.fractionLength(2))))
            row("bodies", model.bodyCount.formatted())
            row("speed", ToolClusterLabels.speed(model.speed))
        }
        .font(.labNumeric(10))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPanel(glass, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .fixedSize()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(Palette.subtleForeground)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Palette.foreground)
        }
        .frame(minWidth: 120)
    }
}
