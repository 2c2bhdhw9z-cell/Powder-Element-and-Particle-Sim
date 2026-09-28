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
    /// What has been worked out so far. See `NotebookStore.swift`.
    @State private var notebook = NotebookStore()
    /// Which lab book experiments have been done. See `LabBookStore.swift`.
    @State private var labBook = LabBookStore()
    /// Why a world opened from elsewhere could not be used, while that is being said.
    @State private var arrivalProblem: String?
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
    @State private var showingNotebook = false
    @State private var showingLabBook = false
    @State private var showingParallel = false
    @State private var showingSenses = false
    /// Whether the powder world is standing on a table through the camera. A layer rather than a cover, like the
    /// introduction: a cover takes the world's own view out of the window and the world stops.
    @State private var showingTable = false
    /// Listening for things said to the lab. See `SpeechListener`.
    @State private var speech = SpeechListener()
    /// The front camera, for a hand and a head. See `CameraSenses`.
    @State private var cameraSenses = CameraSenses()
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
    /// Whether the introduction is on screen.
    @State private var showingWelcome = false
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
    /// Keeps the note of what the world is doing, for reporting a fault afterwards.
    @State private var breadcrumbs = Breadcrumbs()
    /// Watches how warm the phone is, whether it is saving power, and what the lab costs the battery.
    @State private var power = PowerSense()
    /// The phone's other senses: the air pressure, the day's walking, the sun, and how bright the room is.
    @State private var senses = RoomSenses()
    /// The field on a television, with the phone keeping the controls.
    @State private var bigScreen = BigScreen()
    /// A report waiting to be sent — either "that looked wrong" or last time's unfinished note.
    @State private var report: Breadcrumbs.Report?

    /// Remembered between launches. All three are preferences rather than state: coming back to
    /// the chamber you were in, the interface you chose, and the readout you left on.
    @AppStorage("chamber") private var chamberRaw = Chamber.powder.rawValue
    @AppStorage("showDebugOverlay") private var showDebugOverlay = false
    @AppStorage("soundEnabled") private var soundEnabled = true
    /// Whether the powder world makes its own sound as well as the one-off effects. See `Soundscape.swift`.
    @AppStorage("soundscapeEnabled") private var soundscapeEnabled = true
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
    /// Whether the lab eases off when the phone is hot or nearly empty. On by default: a phone that throttles itself
    /// while the app ploughs on looks like the app going bad, which is the whole reason this exists.
    @AppStorage("mindsThePhone") private var mindsThePhone = true
    /// Whether the lab is showing its smaller self. See `SimpleLab`.
    @AppStorage("isSimple") private var isSimple = false
    /// Whether the room's senses are part of the physics. Off by default: it asks a permission, and nothing should ask
    /// for one until somebody has said what it is for.
    @AppStorage("usesRoomSenses") private var usesRoomSenses = false
    /// Whether the introduction has been seen. The one thing here that is about the person rather than the lab.
    @AppStorage("hasBeenWelcomed") private var hasBeenWelcomed = false

    @Environment(\.scenePhase) private var scenePhase

    private var chamber: Chamber { Chamber(rawValue: chamberRaw) ?? .powder }
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

    /// ## Why this is four pieces rather than one chain
    ///
    /// Because the compiler refused the one chain. The screen is two chambers and a bar, and then some forty things
    /// hung off it: every panel, every alert, and every watcher that keeps two chambers, a room and a clock in step.
    /// Written as a single expression that is one problem the type checker has to solve in one go, and past a certain
    /// size it works at it for a while and then gives up outright — "unable to type-check this expression in
    /// reasonable time". The build machine refused the app twice before this was split.
    ///
    /// So: the world and its furniture, then what it watches (in three parts, since it outgrew one and then two), then
    /// the panels, then the alerts. Each is a property of its own, which is a separate problem for the compiler and
    /// reads better besides. Anything new belongs inside whichever of the six it is, rather than on the end of all of
    /// them — and when one grows long, split it again rather than wait for the compiler to refuse it.
    var body: some View {
        labWithPanels
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
        .alert(
            "That world could not be opened",
            isPresented: Binding(
                get: { arrivalProblem != nil },
                set: { if !$0 { arrivalProblem = nil } }
            )
        ) {
            Button("All right") { arrivalProblem = nil }
        } message: {
            Text(arrivalProblem ?? "")
        }
        // The offer to send last time's note, and the sheet that shows a report. In a piece of its own because this
        // body had reached the size where the compiler gives up type-checking it — see `Reporting`.
        .reporting(breadcrumbs, report: $report)
        .sheet(item: $shareTarget) { target in
            // The system's own share sheet, which is the one place it is right to look like iOS
            // rather than like Crucible — it is the phone's furniture, not the app's.
            // Worded for what it is: a picture, a poster, a line drawing for a plotter, or a spreadsheet.
            ShareLink(item: target.url) {
                Label(target.label, systemImage: target.symbol)
                    .font(.labBody(14, .medium))
            }
            .padding(24)
            .presentationDetents([.height(140)])
            .presentationBackground(Palette.background)
            .preferredColorScheme(.dark)
        }
    }

    /// The world itself: two chambers, the bar over them, and the tray under them.
    private var lab: some View {
        // The world reaches the top of the screen; the bar floats over it.
        //
        // ## Why this is not a stack of three any more
        //
        // It was, and the band above the title was the price. Keeping every piece of content inside the
        // safe area left the strip beside the sensor housing painted flat black and holding nothing at
        // all — on a tall phone that is a sixteenth of the screen doing no work, directly above a
        // simulation that wants every pixel it can get. The status bar is switched off in Info.plist, so
        // there was not even a clock up there to justify it.
        //
        // So the world is full-bleed at the top now and the bar sits over it. Two consequences, both
        // deliberate:
        //
        //   - The world runs *behind* the bar as well as above it. That cannot be avoided: filling the
        //     strip means reaching past where the bar is. The bar is solid, so those ninety-six points
        //     are not visible — the gain is the strip above it, and a world that is no longer boxed in.
        //   - The floating tools have to be pushed clear of the bar by hand, since they are no longer
        //     laid out below it. ``LabHeader/height`` is what they are pushed by, which is why that is a
        //     stated constant rather than whatever the bar's rows happen to add up to.
        //
        // The bottom is untouched. Anything pressable still stays above the home indicator.
        GeometryReader { screen in
            // How far down the floating controls have to start to clear the bar: the strip the bar sits
            // in, the bar itself, and the eight points everything floating uses as its margin.
            let clearance = screen.safeAreaInsets.top + LabHeader.height + 8
            // A wide screen has room for two chambers beside one another; an upright phone reads better stacked.
            let splitSideBySide = isSplit && screen.size.width >= 700

            // The whole stack reaches the top, and the bar is put back down by hand.
            //
            // Rather than letting only the world ignore the strip and leaving the bar to work out where it
            // belongs: a stack holding one child that ignores the safe area and one that does not has to
            // decide how big it is, and the answer is not obvious enough to rely on. A number does not have
            // that problem.
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Group {
                        if isSplit {
                            Group {
                                if splitSideBySide {
                                    HStack(spacing: 0) {
                                        chamberPane(.powder, topClearance: clearance, splitSideBySide: true)
                                        Rectangle().fill(Palette.borderStrong).frame(width: 1)
                                        chamberPane(.field, topClearance: clearance, splitSideBySide: true)
                                    }
                                } else {
                                    VStack(spacing: 0) {
                                        // Only the upper pane is under the bar, so only the upper pane's tools move.
                                        chamberPane(.powder, topClearance: clearance, splitSideBySide: false)
                                        Rectangle()
                                            .fill(Palette.borderStrong)
                                            .frame(height: 1)
                                        chamberPane(.field, topClearance: 8, splitSideBySide: false)
                                    }
                                }
                            }
                            .background(Palette.background)
                        } else {
                            chamberPane(chamber, topClearance: clearance, splitSideBySide: false)
                                .background(Palette.background)
                        }
                    }
                    // The note that something was written down, at the foot of the world and never over the tray.
                    //
                    // It used to hang off the whole screen ninety-six points up, which on every phone put it on top of
                    // the tray — exactly where a thumb is. Reaching for a tool while the starting world was busy
                    // finding fire and obsidian opened the notebook instead, and the walkthrough caught it doing so.
                    // Pinned to the world, it can only ever cover world.
                    .overlay(alignment: .bottom) { discoveryNote }
                    .animation(.easeOut(duration: 0.25), value: notebook.justFound)

                    dock
                }

                LabHeader(
                    chamber: chamber,
                    isRunning: isRunning,
                    framesPerSecond: framesPerSecond,
                    onToggleRunning: toggleRunning,
                    onSelectChamber: select,
                    onShowMenu: { showingSettings = true },
                    onShowPerformance: { showingPerformance = true },
                    isSplit: isSplit,
                    onToggleSplit: {
                        breadcrumbs.record(isSplit ? "went back to one chamber" : "split the screen")
                        isSplit.toggle()
                        // The tray is closed on the way in and out: half a screen with an open tray
                        // leaves almost no world visible, which defeats the point of looking at both.
                        isDockOpen = false
                        updateCompanionStepping()
                    }
                )
                // Down by exactly the strip the stack just reached up into, so the bar ends up where it
                // has always been while the world beneath it does not.
                .padding(.top, screen.safeAreaInsets.top)
            }
            // Upward only. This used to ignore the bottom safe area too, and it took the dock's controls
            // down with it: the play button and the clear button ended up inside the home-indicator strip,
            // where iOS takes the upward swipe and pressing them is a gamble.
            .ignoresSafeArea(edges: .top)
            // The introduction, over everything, on the first launch and whenever it is asked for again.
            //
            // A layer rather than a screen the system presents. It was the latter, and it quietly broke every panel in
            // the app: with a full-screen cover attached to the same view as the dozen sheets, tapping Lab afterwards
            // opened nothing at all — the tap-through check found it, and nothing else would have. A layer cannot
            // compete for the one slot the system gives a view.
            .overlay {
                if showingTable {
                    OnYourTable(model: powder) { showingTable = false }
                        .transition(.opacity)
                }
            }
            .overlay {
                if showingWelcome {
                    WelcomeSheet(
                        onFinish: {
                            withAnimation(.easeOut(duration: 0.2)) { showingWelcome = false }
                            hasBeenWelcomed = true
                        },
                        onWantsSimple: { isSimple = true }
                    )
                    .transition(.opacity)
                }
            }
            // The note that something was written down, low on the screen and out of the way of the tools.
            //
            // A note rather than a panel, and it takes itself away. Finding something happens in the middle of doing
            // something else — usually in the middle of an explosion — and stopping the world to announce it would be
            // the most irritating possible way to reward somebody for playing.
        }
        // Behind everything, including the strip at the top and the one at the bottom, so that nothing
        // the world does not reach is ever left showing through to white.
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Palette.primary)
    }

    /// The world, and everything the screen watches: the sensors, the two chambers keeping each other in step, the
    /// autosave, and the note of what is happening.
    private var labWithWatchers: some View {
        lab
        .onAppear {
            // Handed to both models rather than read by the views, so gravity is applied at the
            // start of a tick — in step with the simulation instead of whenever SwiftUI happens
            // to notice a change.
            powder.tilt = tilt
            field.tilt = tilt
            powder.audio = audio
            audio.isEnabled = soundEnabled
            audio.soundscapeEnabled = soundscapeEnabled
            powder.detail = SimulationModel.Detail(rawValue: detailRaw) ?? .balanced
            if bridge == nil {
                let connected = ChamberBridge(powder: powder, field: field)
                connected.isEnabled = chambersAffectEachOther
                bridge = connected
            }
            if room == nil {
                room = RoomBridge(powder: powder)
            }
            // One slow turn, recorded. The field is the only thing that knows when a full circle is complete;
            // recording is a thing the whole screen does. So the field says when, and this does it.
            field.onTurntableStart = { [recorder] in
                guard !recorder.isRecording else { return }
                recorder.toggle()
            }
            field.onTurntableFinish = { [recorder] in
                guard recorder.isRecording else { return }
                recorder.toggle()
            }
            restoreAutosaveOnce()
            updateCompanionStepping()
            describeTheWorld()
            power.isEnabled = mindsThePhone
            applyPowerAdvice()
            senses.isOn = usesRoomSenses
            applyRoomSenses()
            bigScreen.use(field)
            watchForDiscoveries()
            listenForSpeech()
            powder.onLabBookAnswered = { [labBook, breadcrumbs] run in
                breadcrumbs.record("answered the \(run.experiment.title) experiment")
                labBook.finish(run)
            }
            if !hasBeenWelcomed { showingWelcome = true }
        }
        .onChange(of: usesRoomSenses) { _, wanted in
            senses.isOn = wanted
            applyRoomSenses()
        }
        // The pressure moves slowly and the step count by the minute, so this fires rarely.
        .onChange(of: senses.pressure) { _, _ in applyRoomSenses() }
        .onChange(of: senses.steps) { _, _ in applyRoomSenses() }
        .onChange(of: senses.screenBrightness) { _, _ in applyRoomSenses() }
        // What the phone is asking for, passed on to both chambers whenever it changes.
        .onChange(of: power.inEffect) { _, _ in applyPowerAdvice() }
        .onChange(of: mindsThePhone) { _, wanted in power.isEnabled = wanted }
        // Re-wired whenever either the chamber or the setting changes, because which model needs the
        // hook depends on both.
        // A world file opened in Crucible from somewhere else. Everything else that might arrive as an address — the
        // sign-in's return — is handled where it is expected and ignored here.
        .onOpenURL { url in
            guard SceneStore.isWorldFile(url) else { return }
            openArrivedWorld(url)
        }
        .onChange(of: chamberRaw) { _, _ in
            updateCompanionStepping()
            describeTheWorld()
            // The world that is not on screen is not heard either. The powder world stops being ticked when it is
            // not on screen, so it cannot say so itself.
            if chamber != .powder, !isSplit { audio.setSoundscape(.silence) }
        }
        // Both counts are refreshed about once a second by whichever chamber is ticking, which is the beat the note is
        // kept on: often enough to describe what was happening, rarely enough to cost nothing.
        .onChange(of: powder.activeCells) { _, _ in
            describeTheWorld()
            breadcrumbs.writeIfWaiting()
        }
        .onChange(of: field.bodyCount) { _, _ in
            describeTheWorld()
            breadcrumbs.writeIfWaiting()
        }
    }

    /// The rest of what the screen watches: the clock the autosave keeps, the app going away and coming back, the
    /// sound, and the movie's clip. A piece of its own for the reason given on `body`: the watchers had grown past
    /// the size the compiler will type-check as one expression.
    private var labKeepingTime: some View {
        labWithWatchers
        .onChange(of: bothChambersRun) { _, _ in updateCompanionStepping() }
        // Joining or leaving a room changes whether the powder chamber has to keep running while
        // somebody looks at the field. See `updateCompanionStepping`.
        .onChange(of: isSharingRoom) { _, _ in updateCompanionStepping() }
        // With the phone showing Powder, its display callback becomes the television Field's one clock. The TV renderer
        // itself never steps physics, so connecting it cannot double the speed.
        .onChange(of: bigScreen.isShowing) { _, _ in updateCompanionStepping() }
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
            // The lab book has its own pause-aware active clock; it is the one thing here that must distinguish a
            // genuinely slow foreground frame from time the app spent away.
            powder.labBookSceneChanged(active: phase == .active)
            // Time spent away is not time the lab was costing anything, so what was being measured is thrown away.
            power.sceneChanged(active: phase == .active)
            if phase == .active { senses.cameBack() }
            if phase != .active {
                writeAutosave(now: true)
                // The last reliable moment: the phone can kill a backgrounded app with no further warning, and a note
                // still marked unfinished at the next launch is how that is told apart from a crash.
                breadcrumbs.putAway()
            } else {
                breadcrumbs.cameBack()
            }
        }
        .onChange(of: soundEnabled) { _, wanted in
            audio.isEnabled = wanted
        }
        .onChange(of: soundscapeEnabled) { _, wanted in audio.soundscapeEnabled = wanted }
    }

    /// What arrives from outside the screen: a hand and a head at the front camera, and the files made to be sent — a
    /// 3D moment, a movie's clip. A piece of its own for the same reason as the two before it.
    private var labSensing: some View {
        labKeepingTime
        // A hand waved at the front camera, touching whichever world is on screen.
        .onChange(of: cameraSenses.hand) { was, now in handMoved(from: was, to: now) }
        // A head moved in front of it, turning the field's view.
        .onChange(of: cameraSenses.headTurn.yaw) { _, _ in followHead() }
        .onChange(of: cameraSenses.headTurn.pitch) { _, _ in followHead() }
        .onChange(of: cameraSenses.watchesHead) { _, _ in followHead() }
        // A 3D moment, written, offered straight away to be sent.
        .onChange(of: field.momentFile) { _, file in
            guard let file else { return }
            breadcrumbs.record("made a 3D moment")
            field.momentFile = nil
            shareTarget = ShareTarget(url: file)
        }
        // A movie's clip, finished, offered straight away to be kept or sent.
        .onChange(of: field.finishedClip) { _, clip in
            guard let clip else { return }
            breadcrumbs.record("recorded a movie clip")
            field.finishedClip = nil
            shareTarget = ShareTarget(url: clip)
        }
    }

    /// Every panel that slides up over the world.
    private var labWithPanels: some View {
        labSensing
        .sheet(isPresented: $showingScenes) {
            ScenePicker(simple: isSimple) { recipe in
                breadcrumbs.record("loaded the \(recipe.name) scene")
                powder.loadScene(recipe)
                showingScenes = false
            }
        }
        .sheet(isPresented: $showingPresets) {
            FieldPresetPicker(current: field.arrangement, inDepth: field.depthEnabled) { preset in
                breadcrumbs.record("loaded the \(ParticleArrangement.named(preset)?.name ?? preset) arrangement")
                field.loadPreset(preset)
                showingPresets = false
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(
                model: powder,
                showDebugOverlay: $showDebugOverlay,
                soundEnabled: $soundEnabled,
                bothChambersRun: $bothChambersRun,
                chambersAffectEachOther: $chambersAffectEachOther,
                temperatureUnit: Binding(
                    get: { temperatureUnit },
                    set: { temperatureUnitRaw = $0.rawValue }
                ),
                isSimple: $isSimple,
                senses: senses,
                usesRoomSenses: $usesRoomSenses,
                onShowWelcome: {
                    showingSettings = false
                    showingWelcome = true
                },
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
                onShowSenses: {
                    showingSettings = false
                    showingSenses = true
                },
                roomSummary: roomSummary,
                onShowCloud: {
                    showingSettings = false
                    showingCloud = true
                },
                cloudSummary: cloudSummary,
                onRunEvent: runEvent,
                onSomethingLookedWrong: {
                    showingSettings = false
                    reportSomethingWrong()
                }
            )
        }
        .sheet(isPresented: $showingRoom) {
            if let room {
                RoomSheet(bridge: room)
            }
        }
        .sheet(isPresented: $showingCloud) {
            CloudSheet(
                account: account,
                powder: powder,
                field: field,
                chamber: chamber,
                onOpenWorkshop: {
                    // Closed first: a sheet cannot sensibly present another on top of itself.
                    showingCloud = false
                    showingWorkshop = true
                }
            )
        }
        .sheet(isPresented: $showingWorkshop) {
            WorkshopSheet(account: account, powder: powder)
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsSheet(model: powder, unit: temperatureUnit)
        }
        .sheet(isPresented: $showingHelp) {
            HelpSheet()
        }
        .sheet(isPresented: $showingPerformance) {
            PerformanceSheet(
                powder: powder,
                field: field,
                chamber: chamber,
                unit: temperatureUnit,
                power: power,
                mindsThePhone: $mindsThePhone,
                bigScreen: bigScreen
            )
        }
        .sheet(isPresented: $showingPeriodic) {
            PeriodicSheet(model: powder) { id in
                powder.brushElement = id
                showingPeriodic = false
            }
        }
        .sheet(item: $infoElement) { target in
            ElementInfoSheet(model: powder, elementID: target.id)
        }
        .sheet(isPresented: $showingNotebook) {
            NotebookSheet(store: notebook)
        }
        .sheet(isPresented: $showingSenses) {
            SensesSheet(speech: speech, camera: cameraSenses) {
                showingSenses = false
                // The back camera is the table's; the front one is let go first rather than fought over.
                cameraSenses.setWatchesHands(false)
                cameraSenses.setWatchesHead(false)
                if chamber != .powder { select(.powder) }
                breadcrumbs.record("put the powder world on a table")
                showingTable = true
            }
        }
        .sheet(isPresented: $showingParallel) {
            ParallelWorldsSheet { change in
                showingParallel = false
                breadcrumbs.record("made a parallel world with \(change.title.lowercased())")
                if chamber != .powder { select(.powder) }
                isDockOpen = false
                withAnimation(.easeOut(duration: 0.2)) { powder.beginParallel(change) }
            }
        }
        .sheet(isPresented: $showingLabBook) {
            LabBookSheet(store: labBook) { experiment in
                showingLabBook = false
                beginExperiment(experiment)
            }
        }
        .sheet(isPresented: $showingSaves) {
            SavesSheet(powder: powder, field: field, chamber: chamber, store: store)
        }
        .sheet(isPresented: $showingEditor) {
            ElementEditorSheet(model: powder) { paletteVersion += 1 }
        }
        .sheet(isPresented: $showingFieldSettings) {
            FieldSettingsSheet(model: field) {
                showingFieldSettings = false
                reportSomethingWrong()
            }
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
    }

    /// Passes on what the room says: the weather to the powder world, the dark to the field's glow.
    private func applyRoomSenses() {
        powder.applyRoomSenses(senses)
        field.isDarkRoom = senses.isOn && senses.isDarkRoom
    }

    /// Passes on what the phone is asking for. Both chambers hold it rather than reading it, so a tick never goes
    /// looking at the phone's state, and both can be tested in any of these states without a phone.
    private func applyPowerAdvice() {
        let advice = power.inEffect
        powder.powerAdvice = advice
        field.powerAdvice = advice
    }

    /// Sends a note of what is on screen now, with a picture of it, after a short wait for the panel to slide away so
    /// the picture is of the world rather than of the panel.
    private func reportSomethingWrong() {
        breadcrumbs.record("said that something looked wrong")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            let picture = chamber == .powder ? powder.snapshot() : field.snapshot()
            report = breadcrumbs.reportNow(picture: picture)
        }
    }

    // MARK: - Talk, wave, look

    /// Tells the speech listener every name it can be asked for, and what to do with what it understands.
    private func listenForSpeech() {
        speech.materials = VoiceCommands.materialNames(powder.paletteElements(category: nil, search: ""))
        speech.arrangements = ParticleArrangement.all.map { VoiceCommands.Name($0.name, id: $0.id) }
        speech.scenes = allPowderRecipes.map { VoiceCommands.Name($0.name, id: $0.id) }
        speech.onCommand = { command in perform(command) }
    }

    /// Does what was said.
    private func perform(_ command: LabVoiceCommand) {
        breadcrumbs.record("was told \(command.said { powder.definition(of: $0).name })")
        switch command {
        case .play: if !isRunning { toggleRunning() }
        case .pause: if isRunning { toggleRunning() }
        case .clear: if chamber == .powder { powder.clear() } else { field.clear() }
        case .undo: if chamber == .powder { powder.undo() } else { field.undo() }
        case let .choose(id):
            if chamber != .powder { select(.powder) }
            powder.brushElement = id
        case let .pour(id):
            if chamber != .powder { select(.powder) }
            powder.pour(id)
        case .explode: runEvent(.blast)
        case .flip:
            if chamber != .powder { select(.powder) }
            powder.flipUpsideDown()
        case .faster, .slower:
            let faster = command == .faster
            if chamber == .powder { powder.changeSpeed(faster: faster) } else {
                field.speed = max(0.25, min(4, faster ? field.speed * 2 : field.speed / 2))
            }
        case .biggerBrush: powder.changeBrush(bigger: true)
        case .smallerBrush: powder.changeBrush(bigger: false)
        case .powderChamber: select(.powder)
        case .fieldChamber: select(.field)
        case let .arrangement(id):
            if chamber != .field { select(.field) }
            field.loadPreset(id)
        case let .scene(id):
            if chamber != .powder { select(.powder) }
            if let recipe = allPowderRecipes.first(where: { $0.id == id }) { powder.loadScene(recipe) }
        }
        Haptics.selection()
    }

    /// A hand at the front camera: in the field it pushes or pulls; in the powder world a pinch paints.
    private func handMoved(from was: HandTouch?, to now: HandTouch?) {
        switch chamber {
        case .field:
            field.applyHand(now)
        case .powder:
            let wasPainting = was?.grabbing == true
            if let now, now.grabbing {
                if !wasPainting { powder.beginStroke(atFractionX: now.x, fractionY: now.y) }
                powder.paint(atFractionX: now.x, fractionY: now.y)
            } else if wasPainting {
                powder.endStroke()
            }
        }
    }

    /// Hands the head's turn to the field, or takes it away.
    private func followHead() {
        field.headLook = cameraSenses.watchesHead ? cameraSenses.headTurn : nil
    }

    // MARK: - The lab book

    /// Sets an experiment up in the powder world, on screen and with the tray out of the way.
    private func beginExperiment(_ experiment: LabExperiment) {
        breadcrumbs.record("began the \(experiment.title) experiment")
        if chamber != .powder { select(.powder) }
        isDockOpen = false
        withAnimation(.easeOut(duration: 0.2)) { powder.beginExperiment(experiment) }
    }

    // MARK: - The notebook

    /// The note that something was written down. Raised clear of the rewind slider and the lasso's bar, which share
    /// the foot of the world with it.
    @ViewBuilder
    private var discoveryNote: some View {
        if let found = notebook.justFound {
            DiscoveryNote(discovery: found) {
                notebook.justFound = nil
                showingNotebook = true
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 64)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: found.id) {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.easeOut(duration: 0.25)) { notebook.justFound = nil }
            }
        }
    }

    /// Listens to both chambers for something worth writing down.
    ///
    /// Set up once. Both models report rather than record — neither knows a notebook exists — so this is the one place
    /// that decides what counts as a discovery and what a page is worth taking a picture of.
    private func watchForDiscoveries() {
        powder.onDiscovery = { [notebook] made, chain, blast in
            for id in made {
                guard let discovery = Discoveries.forElement(id) else { continue }
                // The picture is a closure, and it is only called when the page turns out to be new. Rendering the
                // world costs a pass over every cell and a shrink, and most of what arrives here has been found
                // already — usually several times a second, in a world with a fire in it.
                notebook.note(discovery, chamber: "powder", picture: { notebookPicture(of: .powder) })
            }
            if chain >= 5 {
                notebook.note("chainreaction", chamber: "powder", picture: { notebookPicture(of: .powder) })
            }
            if blast >= 60 {
                notebook.note("bigblast", chamber: "powder", picture: { notebookPicture(of: .powder) })
            }
        }
        field.onDiscovery = { [notebook] id in
            notebook.note(id, chamber: "field", picture: { notebookPicture(of: .field) })
        }
    }

    /// A small picture of one chamber, for a notebook page.
    ///
    /// The same recipe the gallery of kept worlds uses: the engine's own pixels rather than a grab of the screen, so it
    /// works while a panel is open, and shrunk, because a notebook of full-size pictures would be tens of megabytes.
    private func notebookPicture(of which: Chamber) -> Data? {
        let image = which == .powder ? powder.snapshot() : field.snapshot()
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

    // MARK: - What the note says about the world

    /// Describes the world to the note: which chamber, how big, how full, what is being painted, and what the field is
    /// made of. Refreshed whenever one of the readouts changes, which is about once a second.
    private func describeTheWorld() {
        var readings: [LabBreadcrumb.Reading] = [
            .init("Chamber", isSplit ? "Both at once, \(chamber.title) has the tray" : chamber.title),
            .init("Detail", powder.detail.title),
            .init("Powder grid", "\(powder.gridSize.width) × \(powder.gridSize.height)"),
            .init("Cells filled", powder.activeCells.formatted()),
            .init("Painting", powder.definition(of: powder.brushElement).name),
            .init("Powder running", powder.isRunning ? "yes" : "no"),
            .init("Moments a second", "\(powder.ticksPerSecond)"),
            .init("Field bodies", field.bodyCount.formatted()),
            .init("Field arrangement", field.arrangementDetails?.name ?? "none"),
            .init("Field in 3D", field.depthEnabled ? "yes" : "no"),
            .init("Field running", field.isRunning ? "yes" : "no"),
            .init("Own materials", powder.customElements.count.formatted()),
        ]
        if powder.tideOn { readings.append(.init("Tide", "on")) }
        if powder.thermometer != nil { readings.append(.init("Thermometer", "in the world")) }
        if powder.isMeasuring { readings.append(.init("Measuring", "\(powder.measurementRows) rows")) }
        if recorder.isRecording { readings.append(.init("Recording", "yes")) }
        if isSharingRoom { readings.append(.init("Shared room", "connected")) }
        breadcrumbs.describe(readings)
    }

    // MARK: - A chamber on screen

    /// One chamber, with the controls that float over it.
    ///
    /// The same view whether it is filling the screen or sharing it, so the two layouts cannot drift
    /// apart — and so that a chamber sharing the screen is a real chamber rather than a preview of one.
    /// - Parameter topClearance: how far down the floating controls must start so the bar does not cover
    ///   them. The world itself ignores this and fills the pane, which is the whole point of the pane
    ///   reaching the top of the screen.
    @ViewBuilder
    private func chamberPane(_ which: Chamber, topClearance: CGFloat, splitSideBySide: Bool) -> some View {
        GeometryReader { geometry in
            let world = which == .powder
                ? CGSize(width: CGFloat(max(1, powder.engine.width)), height: CGFloat(max(1, powder.engine.height)))
                : CGSize(width: CGFloat(max(1, field.engine.width)), height: CGFloat(max(1, field.engine.height)))
            let scale = min(geometry.size.width / world.width, geometry.size.height / world.height)
            let fitted = CGSize(width: world.width * scale, height: world.height * scale)
            // What this pane would be at full single-chamber size. A persisted split can be the first layout after
            // launch; doubling its half gives the same canonical canvas without ever resizing an existing world later.
            let initialCanvas = isSplit
                ? (splitSideBySide
                    ? CGSize(width: geometry.size.width * 2 + 1, height: geometry.size.height)
                    : CGSize(width: geometry.size.width, height: geometry.size.height * 2 + 1))
                : geometry.size
            ZStack(alignment: .topLeading) {
                surface(which, size: fitted, initialCanvas: initialCanvas)
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // The floating controls belong to whichever chamber has focus. Showing them on both
                // halves would be two sets of undo buttons doing different things. None while two parallel worlds
                // run: every one of them would change the first world and not the second.
                if which == chamber, !(which == .powder && powder.parallel != nil) {
                    VStack(alignment: .leading, spacing: 8) {
                        tools
                        if showDebugOverlay { debugReadout }
                    }
                    .padding(.leading, 8)
                    .padding(.top, topClearance)
                }

                // The opposite corner from the tools. That used to be described here as meaning the two
                // could never collide, which was wrong: they are separate layers of the same stack, so
                // nothing stops one growing under the other — and the tools did exactly that, being
                // wider than the phone. The tools are two rows now and this keeps its corner; the
                // readout is also a single short line, so it cannot grow to meet them.
                if which == .powder, which == chamber, powder.parallel == nil {
                    HStack {
                        Spacer(minLength: 0)
                        InspectChip(
                            model: powder,
                            unit: temperatureUnit
                        ) { id in
                            infoElement = ElementInfoTarget(id: id)
                        }
                    }
                    .padding(.trailing, 8)
                    // The same clearance as the tools. It is in the same layer over the same world, so
                    // the bar would cover it just as thoroughly.
                    .padding(.top, topClearance)
                }
            }
            // The lab book's card, under the tools, over the part of the world every experiment leaves empty.
            .overlay(alignment: .top) {
                if which == .powder, which == chamber, powder.parallel == nil {
                    LabBookCardView(model: powder, onNext: { beginExperiment($0) })
                        .padding(.top, topClearance + 96)
                        .animation(.easeOut(duration: 0.2), value: powder.labBook)
                }
            }
            // Where you are inside the field, and the way back out, in the same place for the same reason.
            .overlay(alignment: .top) {
                if which == .field, which == chamber {
                    WorldWithinBanner(model: field)
                        .padding(.top, topClearance + 96)
                        .animation(.easeOut(duration: 0.2), value: field.whereInside)
                }
            }
            // The rewind's slider and the lasso's actions, along the bottom of the world just above the tray — where
            // the thumb already is, and away from the tools at the top.
            .overlay(alignment: .bottom) {
                if which == .powder, which == chamber, powder.parallel == nil {
                    PowderToolBars(model: powder)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
            // Tapping the other half moves focus to it, which is how the dock and the tools follow
            // your attention. Only while split; otherwise this would swallow taps meant for the world.
            //
            // A cover over the half without focus, catching the tap before the world beneath does. It used to
            // be a tap handler alongside the world's own, so the same tap also painted a stroke into the
            // powder or pushed the field — with an undo point — on the half you were only trying to look at.
            .overlay {
                if isSplit, which != chamber {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptics.selection()
                            select(which)
                        }
                }
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

    /// The particle field in a sentence, for VoiceOver.
    private var fieldDescription: String {
        let name = field.arrangementDetails?.name ?? "No arrangement"
        let depth = field.depthEnabled ? ", in 3D" : ""
        return "\(name)\(depth). \(field.bodyCount.formatted()) bodies."
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
        breadcrumbs.record("set off \(SettingsSheet.title(for: event))")
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
        breadcrumbs.record(isRunning ? "paused" : "pressed play")
        switch chamber {
        case .powder: powder.isRunning.toggle()
        case .field: field.isRunning.toggle()
        }
    }

    private func select(_ option: Chamber) {
        breadcrumbs.record("switched to the \(option.title) chamber")
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
            guard bothChambersRun || bigScreen.isShowing else { return }
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
    /// Opens a world handed to the app from elsewhere. The world it replaces is one undo away.
    private func openArrivedWorld(_ url: URL) {
        // So the autosave, if it has not been read yet, does not land on top of the world just opened.
        hasRestored = true
        guard let scene = store.openArrived(url) else {
            arrivalProblem = store.lastProblem ?? "That file could not be opened."
            return
        }
        powder.adopt(scene.customElements)
        if let state = scene.powder { _ = powder.apply(state) }
        if let state = scene.particle { _ = field.apply(state) }
        // Onto whichever chamber the file is really about: a world with nothing in its powder is a field.
        if scene.powder == nil, scene.particle != nil { select(.field) } else if scene.powder != nil { select(.powder) }
        Haptics.firm()
    }

    private func restoreAutosaveOnce() {
        guard !hasRestored else { return }
        hasRestored = true
        guard let scene = store.readAutosave() else { return }
        powder.adopt(scene.customElements)
        if let state = scene.powder, powder.apply(state) { powder.acceptStartupRestore() }
        if let state = scene.particle, field.apply(state) { field.acceptStartupRestore() }
    }

    private func writeAutosave(now: Bool = false) {
        store.writeAutosave(
            LabScene(
                version: LabScene.currentVersion,
                savedAt: Date(),
                powder: powder.captureState(),
                particle: field.captureState(),
                customElements: powder.customElements
            ),
            now: now
        )
    }

    // MARK: - Pieces

    @ViewBuilder
    private func surface(_ which: Chamber, size: CGSize, initialCanvas: CGSize) -> some View {
        switch which {
        case .powder:
            if let twin = powder.parallel, let change = powder.parallelChange {
                // Two worlds, each drawn whole. Neither is resized to its half — see `ParallelPowderView`.
                ParallelPowderView(first: powder, second: twin, change: change)
            } else {
                ShakenPowderSurface(model: powder, initialCanvas: initialCanvas, unit: temperatureUnit)
                    // Said to somebody using VoiceOver, who otherwise hears nothing at all about the world: what it is,
                    // what is in it, and what a drag does.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("The powder world")
                    .accessibilityValue("\(powder.activeCells.formatted()) cells filled. Painting \(powder.definition(of: powder.brushElement).name).")
                    .accessibilityHint("Drag to paint.")
                    .accessibilityAddTraits(.allowsDirectInteraction)
                    .accessibilityIdentifier("world.powder")
            }
        case .field:
            FieldWithLabels(model: field)
                .onAppear {
                    field.prepareInitialCanvas(toViewSize: initialCanvas, scale: UIScreen.main.scale)
                    field.updateViewport(toViewSize: size, scale: UIScreen.main.scale)
                }
                .onChange(of: initialCanvas) { _, new in
                    field.prepareInitialCanvas(toViewSize: new, scale: UIScreen.main.scale)
                }
                .onChange(of: size) { _, new in
                    field.updateViewport(toViewSize: new, scale: UIScreen.main.scale)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("The particle field")
                .accessibilityValue(fieldDescription)
                .accessibilityHint("Touch and hold to use the chosen tool.")
                .accessibilityAddTraits(.allowsDirectInteraction)
                .accessibilityIdentifier("world.field")
        }
    }

    /// The powder world, jolted when something goes off.
    ///
    /// ## Why this is its own view rather than three lines in `surface`
    ///
    /// Because of where the shake offset is *read*. It changes every frame for the length of a shake, and
    /// read from inside `ContentView.body` it made the whole screen rebuild every frame for as long as the
    /// jolt lasted — the header, both chambers, the tool cluster and the several hundred controls in the
    /// dock, sixty or a hundred and twenty times a second, because a rectangle needed moving four points.
    ///
    /// Read in here, the rebuild reaches this view and stops. The thing inside is a wrapper round a Metal
    /// view, so rebuilding it costs a struct and an offset.
    ///
    /// Only the simulation moves. The dock and the tools stay put, because chrome that shakes reads as the
    /// app glitching rather than as the world being hit.
    private struct ShakenPowderSurface: View {
        let model: SimulationModel
        let initialCanvas: CGSize
        let unit: TemperatureUnit

        var body: some View {
            SimulationSurface(model: model)
                // The lasso's loop and the thermometer are marks on the world, so they are shaken with it.
                .overlay { PowderWorldMarks(model: model, unit: unit) }
                .offset(x: model.screenShakeOffset.width, y: model.screenShakeOffset.height)
                .onAppear { model.prepareInitialCanvas(toViewSize: initialCanvas, scale: UIScreen.main.scale) }
                .onChange(of: initialCanvas) { _, new in
                    model.prepareInitialCanvas(toViewSize: new, scale: UIScreen.main.scale)
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
                shareTarget: $shareTarget
            )
        case .field:
            FieldToolCluster(
                model: field,
                tilt: tilt,
                recorder: recorder,
                shareTarget: $shareTarget
            )
        }
    }

    @ViewBuilder
    private var debugReadout: some View {
        switch chamber {
        case .powder: DebugOverlay(model: powder)
        case .field: FieldDebugOverlay(model: field)
        }
    }

    @ViewBuilder
    private var dock: some View {
        switch chamber {
        case .powder:
            ElementDock(
                model: powder,
                isOpen: $isDockOpen,
                onShowScenes: { showingScenes = true },
                onShowSettings: { showingSettings = true },
                onShowInfo: { infoElement = ElementInfoTarget(id: $0) },
                onShowPeriodic: { showingPeriodic = true },
                onShowSaves: { showingSaves = true },
                onShowNotebook: { showingNotebook = true },
                onShowLabBook: { showingLabBook = true },
                onShowParallel: { showingParallel = true },
                labBookDone: labBook.progress.doneCount,
                found: notebook.notebook.found,
                howMany: notebook.notebook.howMany,
                onShowEditor: { showingEditor = true },
                paletteVersion: paletteVersion,
                today: Self.today,
                isSimple: isSimple
            )
        case .field:
            FieldDock(
                model: field,
                isOpen: $isDockOpen,
                onShowPresets: { showingPresets = true },
                // Its own sheet, not the powder world's. Almost nothing carries over between them —
                // there are no cells here, no temperature and no wind — so sharing one would be a
                // list of controls that mostly did not apply.
                onShowSettings: { showingFieldSettings = true },
                today: Self.today,
                onSettleEverything: { _ = bridge?.settleEverything() },
                onShowPowderInTheBox: {
                    breadcrumbs.record("showed the powder world in the box")
                    _ = bridge?.showPowderInTheBox()
                }
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
    /// Whether to show the four on the short list rather than all of them. See `SimpleLab`.
    var simple = false
    let onSelect: (PowderRecipe) -> Void

    var body: some View {
        LabSheet(
            title: "Scenes",
            subtitle: simple ? "Four worlds to start from" : "\(allPowderRecipes.count) worlds to start from"
        ) {
            LabGroup(footnote: "Loading a scene replaces the world. Undo brings it back.") {
                chips(simple ? SimpleLab.scenes : powderRecipes)
            }
            // This app's own, kept apart from the thirteen it shares with the website: the day's world is chosen
            // from those, and these have never existed there.
            if !simple {
                LabGroup(
                    "Only here",
                    footnote: "Hourglass: the ⇅ button in the tools at the top turns the world over, and it pours again."
                ) {
                    chips(ownPowderRecipes)
                }
            }
        }
    }

    private func chips(_ recipes: [PowderRecipe]) -> some View {
        LabFlow(spacing: 6) {
            ForEach(recipes, id: \.id) { recipe in
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

/// The floating tools for the particle chamber.
struct FieldToolCluster: View {
    let model: ParticleFieldModel
    let tilt: TiltSensor
    let recorder: ScreenRecorder
    @Binding var shareTarget: ShareTarget?

    private static let speeds: [Double] = [0.25, 0.5, 1, 2, 4]

    /// Two rows, for the same reason as the powder chamber's. See the note on `ToolCluster`: on one row
    /// this came to more than a phone is wide, so the tilt button sat on the screen's edge or past it.
    var body: some View {
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
            .solidPanel()

            HStack(spacing: 6) {
                // One width for every step, and padding inside the pill. See the note on
                // `ToolCluster.speedDial` for why both.
                HStack(spacing: 0) {
                    ForEach(Self.speeds, id: \.self) { value in
                        Button {
                            Haptics.selection()
                            model.speed = value
                        } label: {
                            Text(ToolClusterLabels.speed(value))
                                .font(.labNumeric(11))
                                .foregroundStyle(
                                    model.speed == value ? Palette.foreground : Palette.muted
                                )
                                .frame(width: 42, height: 40)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 5)
                .solidPanel()

                TiltButton(tilt: tilt)
            }
        }
    }

    private func button(
        _ symbol: String,
        _ label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
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
        .solidPanel(in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
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
