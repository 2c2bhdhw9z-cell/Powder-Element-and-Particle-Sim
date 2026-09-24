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
    /// Connects the two chambers. Built once both models exist.
    @State private var bridge: ChamberBridge?
    /// Connects the powder chamber to a shared room. Built once the model exists.
    ///
    /// Always present, whether or not a room is open — it is what carries a stroke to the room and a
    /// world back, and it owns the tick hook the room is driven from. With no room open it does nothing.
    @State private var room: RoomBridge?

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
    @State private var showingPerformance = false
    @State private var showingRoom = false
    @State private var showingCloud = false
    @State private var showingWorkshop = false
    /// The account and the server address. One for the whole app: two would disagree about who is signed
    /// in, and the second one to be asked would look signed out.
    @State private var account = CloudAccount()
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
    /// Whether the chamber you are not looking at keeps running. Off by default, matching the
    /// reference: stepping a world nobody is watching spends the frame budget of the one they are.
    @AppStorage("bothChambersRun") private var bothChambersRun = false
    /// Remembered between launches, like the other preferences. Stored as its cell budget, which is
    /// the enumeration's own value, so an unrecognised number falls back to the default rather than
    /// refusing to start.
    @AppStorage("detail") private var detailRaw = SimulationModel.Detail.balanced.rawValue
    /// Whether the chambers affect one another. On by default, matching the reference.
    @AppStorage("chambersAffectEachOther") private var chambersAffectEachOther = true
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    /// Whether both chambers share the screen.
    ///
    /// Worth more than it first appears: the two chambers affect each other — explosions throw sparks
    /// across, bodies silt down into sand — and none of that is visible unless both are on screen at
    /// once.
    @AppStorage("isSplit") private var isSplit = false

    @Environment(\.scenePhase) private var scenePhase

    private var chamber: Chamber { Chamber(rawValue: chamberRaw) ?? .powder }
    private var glass: GlassLevel { GlassLevel(rawValue: glassRaw) ?? .full }
    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    /// One line describing the room, for the menu row.
    ///
    /// Worth having on the row rather than only inside the panel: a room left open keeps this phone
    /// sending its world to somebody, and that should be visible without going looking for it.
    private var roomSummary: String {
        guard let session = room?.session else { return "Paint in the same world as somebody nearby" }
        switch session.status {
        case .closed:
            return "Paint in the same world as somebody nearby"
        case .open:
            return "Open as \(session.code) — waiting for somebody"
        case .connected:
            let others = session.peers.count == 1 ? "1 other phone" : "\(session.peers.count) other phones"
            return session.isHost
                ? "\(session.code) — you are running the world, \(others)"
                : "\(session.code) — watching, \(others)"
        }
    }

    /// One line describing the server and account, for the menu row.
    private var cloudSummary: String {
        guard account.hasServer else { return "Keep worlds on a server, and share them" }
        if account.isSignedIn { return "Signed in at \(account.hostText)" }
        if account.status == nil { return "\(account.hostText) — not checked yet" }
        if account.canSignIn { return "\(account.hostText) — not signed in" }
        return "\(account.hostText) — accounts are switched off"
    }

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
                onShowMenu: { showingSettings = true },
                onShowPerformance: { showingPerformance = true },
                isSplit: isSplit,
                onToggleSplit: {
                    isSplit.toggle()
                    // The tray is closed on the way in and out: half a screen with an open tray leaves
                    // almost no world visible, which defeats the point of looking at both.
                    isDockOpen = false
                    updateCompanionStepping()
                }
            )

            if isSplit {
                // Stacked rather than side by side, because on a phone held upright two tall thin
                // chambers are far worse than two short wide ones. The reference does the same — its
                // side-by-side layout only applies from tablet widths up.
                VStack(spacing: 0) {
                    chamberPane(.powder)
                    Rectangle()
                        .fill(Palette.borderStrong)
                        .frame(height: 1)
                    chamberPane(.field)
                }
                .background(Palette.background)
            } else {
                chamberPane(chamber)
                    .background(Palette.background)
            }

            dock
        }
        // The background fills the whole screen; the *content* does not.
        //
        // This used to ignore the bottom safe area so the dock's backdrop reached under the home
        // indicator, and it took the dock's controls down there with it. The play button and the
        // clear button ended up sitting inside the home-indicator strip, where they are both clipped
        // and half-unusable — iOS takes the upward swipe from that band, so pressing them is a
        // gamble. Anything you can press has to stay above it.
        .background(Palette.background.ignoresSafeArea())
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
            powder.detail = SimulationModel.Detail(rawValue: detailRaw) ?? .balanced
            if bridge == nil {
                let connected = ChamberBridge(powder: powder, field: field)
                connected.isEnabled = chambersAffectEachOther
                bridge = connected
            }
            if room == nil {
                room = RoomBridge(powder: powder)
            }
            restoreAutosaveOnce()
            updateCompanionStepping()
        }
        // Re-wired whenever either the chamber or the setting changes, because which model needs the
        // hook depends on both.
        .onChange(of: chamberRaw) { _, _ in updateCompanionStepping() }
        .onChange(of: bothChambersRun) { _, _ in updateCompanionStepping() }
        // Joining or leaving a room changes whether the powder chamber has to keep running while
        // somebody looks at the field. See `updateCompanionStepping`.
        .onChange(of: isSharingRoom) { _, _ in updateCompanionStepping() }
        // Written back whenever it changes, so the panel drives the model and the model is the one
        // source of truth rather than the two being kept in step by hand.
        .onChange(of: powder.detail) { _, level in detailRaw = level.rawValue }
        .onChange(of: chambersAffectEachOther) { _, wanted in bridge?.isEnabled = wanted }
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
                bothChambersRun: $bothChambersRun,
                chambersAffectEachOther: $chambersAffectEachOther,
                temperatureUnit: Binding(
                    get: { temperatureUnit },
                    set: { temperatureUnitRaw = $0.rawValue }
                ),
                onShowDiagnostics: {
                    showingSettings = false
                    showingDiagnostics = true
                },
                onShowHelp: {
                    // Closed first: a sheet cannot sensibly present another on top of itself.
                    showingSettings = false
                    showingHelp = true
                },
                onShowRoom: {
                    showingSettings = false
                    showingRoom = true
                },
                roomSummary: roomSummary,
                onShowCloud: {
                    showingSettings = false
                    showingCloud = true
                },
                cloudSummary: cloudSummary,
                onRunEvent: runEvent
            )
        }
        .sheet(isPresented: $showingRoom) {
            if let room {
                RoomSheet(bridge: room, glass: glass)
            }
        }
        .sheet(isPresented: $showingCloud) {
            CloudSheet(
                account: account,
                powder: powder,
                field: field,
                chamber: chamber,
                glass: glass,
                onOpenWorkshop: {
                    // Closed first: a sheet cannot sensibly present another on top of itself.
                    showingCloud = false
                    showingWorkshop = true
                }
            )
        }
        .sheet(isPresented: $showingWorkshop) {
            WorkshopSheet(account: account, powder: powder, glass: glass)
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsSheet(model: powder, glass: glass, unit: temperatureUnit)
        }
        .sheet(isPresented: $showingHelp) {
            HelpSheet(glass: glass)
        }
        .sheet(isPresented: $showingPerformance) {
            PerformanceSheet(
                powder: powder,
                field: field,
                chamber: chamber,
                unit: temperatureUnit,
                glass: glass
            )
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
            //
            // It deliberately does **not** ignore the safe area. This used to, and the result was that
            // the preview's own close and Save buttons — which it lays out relative to the top of the
            // view it is given — sat up underneath the clock and the battery, overlapping them. That
            // view is ReplayKit's, not this app's, so there is no way to nudge its buttons down; the
            // only fix is to stop handing it the whole screen.
            RecordingPreview(controller: target.controller)
                .background(Color.black.ignoresSafeArea())
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

    // MARK: - A chamber on screen

    /// One chamber, with the controls that float over it.
    ///
    /// The same view whether it is filling the screen or sharing it, so the two layouts cannot drift
    /// apart — and so that a chamber sharing the screen is a real chamber rather than a preview of one.
    @ViewBuilder
    private func chamberPane(_ which: Chamber) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                surface(which, size: geometry.size)

                // The floating controls belong to whichever chamber has focus. Showing them on both
                // halves would be two sets of undo buttons doing different things.
                if which == chamber {
                    VStack(alignment: .leading, spacing: 8) {
                        tools
                        if showDebugOverlay { debugReadout }
                    }
                    .padding(.leading, 8)
                    .padding(.top, 8)
                }

                // The opposite corner from the tools. That used to be described here as meaning the two
                // could never collide, which was wrong: they are separate layers of the same stack, so
                // nothing stops one growing under the other — and the tools did exactly that, being
                // wider than the phone. The tools are two rows now and this keeps its corner; the
                // readout is also a single short line, so it cannot grow to meet them.
                if which == .powder, which == chamber {
                    HStack {
                        Spacer(minLength: 0)
                        InspectChip(
                            model: powder,
                            unit: temperatureUnit,
                            glass: glass
                        ) { id in
                            infoElement = ElementInfoTarget(id: id)
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                }
            }
            // Tapping the other half moves focus to it, which is how the dock and the tools follow
            // your attention. Only while split; otherwise this would swallow taps meant for the world.
            .contentShape(Rectangle())
            .onTapGesture {
                if isSplit, which != chamber { select(which) }
            }
        }
        .overlay {
            // A hairline round whichever has focus, so it is obvious which chamber the dock belongs to.
            if isSplit, which == chamber {
                Rectangle()
                    .strokeBorder(Palette.primary.opacity(0.35), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - What the header reads

    /// Whichever chamber is on screen decides what play, pause and the frame counter refer to.
    private var isRunning: Bool {
        chamber == .powder ? powder.isRunning : field.isRunning
    }

    private var framesPerSecond: Int {
        // While being shown somebody else's world this chamber is not ticking at all, so its own rate is
        // nought — which the header would draw in red as though the app had stopped. The honest number
        // then is how often a new world is arriving, because that is what the picture is changing at.
        if chamber == .powder, powder.isFollowingRoom, let session = room?.session {
            return session.framesPerSecond
        }
        return chamber == .powder ? powder.ticksPerSecond : field.ticksPerSecond
    }

    /// Sets off one of the four set-piece events, having first made it possible to see.
    ///
    /// Two things have to be true before the event starts, and neither was. The panel that offers them
    /// has to be out of the way, and the powder chamber has to be the one on screen — otherwise the
    /// meteor lands somewhere nobody is looking. Both were happening *behind* something, which looks
    /// exactly like an event that does nothing.
    private func runEvent(_ event: PowderEventID) {
        showingSettings = false
        if chamber != .powder, !isSplit { select(.powder) }

        Task { @MainActor in
            // Long enough for the panel to finish sliding away. A meteor falls for a moment before it
            // detonates, so the wait costs nothing — and starting underneath the panel costs the whole
            // thing.
            try? await Task.sleep(for: .milliseconds(380))
            powder.run(event)
        }
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

    /// Today's date in UTC, as the day's world is keyed by.
    ///
    /// UTC rather than local time, so that everybody changes over at the same moment. Keyed on local
    /// midnight, two people in different places would get different "same" worlds for several hours a
    /// day — which is the one thing the feature must not do.
    static var today: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Two chambers, one clock

    /// Points the visible chamber at the hidden one, or at nothing.
    ///
    /// Exactly one hook is ever set. Both models clear theirs first, so switching chambers cannot
    /// leave the old direction wired alongside the new one — which would have them stepping each
    /// other. They also refuse to re-enter, so even that could not hang the app, but not relying on
    /// the safety net is cheaper than relying on it.
    private func updateCompanionStepping() {
        powder.alsoStep = nil
        field.alsoStep = nil
        // While split, both chambers are on screen and each has a view driving its own clock. Wiring a
        // companion as well would step the hidden one twice per frame — it is not hidden — and it would
        // run at double speed.
        guard !isSplit else { return }

        switch chamber {
        case .powder:
            // The powder chamber's clock is the one running, so it carries the field along if that was
            // asked for. The timestamp is the same one the field's own view would have handed it.
            guard bothChambersRun else { return }
            field.tilt = tilt
            powder.alsoStep = { [field] in field.tick(now: CFAbsoluteTimeGetCurrent() * 1000) }
        case .field:
            // The field's clock is the one running, and it carries the powder chamber along for either
            // of two reasons.
            //
            // The second one is not optional. In a shared room, other people are watching this phone's
            // powder chamber — so it has to keep running even while this phone is looking at the field.
            // Without this, everybody else's view froze the moment somebody switched chamber, and
            // nothing anywhere said why.
            guard bothChambersRun || isSharingRoom else { return }
            field.alsoStep = { [powder] in powder.tick() }
        }
    }

    /// Whether a shared room is currently connected.
    ///
    /// Read as a plain value rather than reached for through the optional at each use, so it can also be
    /// watched for changes — the wiring above depends on it.
    private var isSharingRoom: Bool {
        room?.session.status == .connected
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
    private func surface(_ which: Chamber, size: CGSize) -> some View {
        switch which {
        case .powder:
            SimulationSurface(model: powder)
                // The whole surface jolts when something goes off. Only the simulation moves — the dock
                // and the tools stay put, because chrome that shakes reads as the app glitching rather
                // than as the world being hit.
                .offset(x: powder.screenShakeOffset.width, y: powder.screenShakeOffset.height)
                .onAppear { powder.resize(toViewSize: size, scale: UIScreen.main.scale) }
                .onChange(of: size) { _, new in
                    powder.resize(toViewSize: new, scale: UIScreen.main.scale)
                }
        case .field:
            FieldSurface(model: field)
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
                paletteVersion: paletteVersion,
                today: Self.today
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
                onShowSettings: { showingFieldSettings = true },
                today: Self.today,
                onSettleEverything: { _ = bridge?.settleEverything() }
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

    /// Two rows, for the same reason as the powder chamber's. See the note on `ToolCluster`: on one row
    /// this came to more than a phone is wide, so the tilt button sat on the screen's edge or past it.
    var body: some View {
        GlassGroup(level: glass) {
            VStack(alignment: .leading, spacing: 6) {
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

                HStack(spacing: 6) {
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
