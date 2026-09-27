import CrucibleCore
import SwiftUI

/// The lab's own panel: how it looks, what the physics does, and things that make something happen.
///
/// Opened from the button in the header, which is where the reference implementation puts it.
///
/// Built from the lab's own pieces rather than the system's grouped list. That list is quick to write
/// and looks like the Settings app — inset grey rows on a lighter grey — which is a different product
/// from a near-black room.
struct SettingsSheet: View {
    let model: SimulationModel
    @Binding var showDebugOverlay: Bool
    @Binding var soundEnabled: Bool
    @Binding var bothChambersRun: Bool
    @Binding var chambersAffectEachOther: Bool
    @Binding var temperatureUnit: TemperatureUnit
    let onShowDiagnostics: () -> Void
    let onShowHelp: () -> Void
    let onShowRoom: () -> Void
    /// What the room row should say about itself, so somebody already in a room can see that from here.
    let roomSummary: String
    let onShowCloud: () -> Void
    /// What the server row should say, so being signed in somewhere is visible from here.
    let cloudSummary: String
    /// Runs one of the set-piece events. Not done here — see the note on `events`.
    let onRunEvent: (PowderEventID) -> Void

    /// Read straight from the same place the app's initialiser reads it, so the two cannot disagree
    /// about what was asked for.
    @AppStorage(DebugSettings.graphicsOverlayKey) private var graphicsOverlay = false
    /// Whether the phone buzzes: a tick when something is chosen, a tap for a button, a thump for an
    /// explosion. Read by `Haptics` everywhere else, so this one switch covers all of them.
    @AppStorage(Haptics.settingKey) private var hapticsEnabled = true

    /// A spreadsheet of measurements waiting to be sent somewhere.
    @State private var shareTarget: ShareTarget?

    var body: some View {
        LabSheet(title: "Lab", subtitle: "How it looks and how it behaves") {
            help
            room
            detail
            view
            world
            sea
            measure
            events
            health
            development
        }
        .sheet(item: $shareTarget) { target in
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

    // MARK: Sea

    /// A tide along one side of the world.
    ///
    /// Settings rather than a button, because a tide is a slow thing that is left running: a minute a rise and fall
    /// by default, so a sandcastle has time to be built before the water reaches it.
    private var sea: some View {
        LabGroup(
            "Sea",
            footnote: model.tideOn
                ? "The whole sea rises and falls, as a real one does: the water joined to that edge gets deeper, climbs "
                    + "the beach and runs back down, up to a third of the way up the world. A lake the sea has not "
                    + "reached is left alone until the water joins it. It needs gravity pointing down."
                : "A sea beyond one edge of the world that comes in and goes out, slowly, for ever. Build a sea wall, "
                    + "or don't."
        ) {
            LabToggle(label: "Tide", isOn: Binding(get: { model.tideOn }, set: { model.tideOn = $0 }))
            if model.tideOn {
                LabDivider()
                LabChoice(
                    label: "The sea is beyond",
                    selection: Binding(get: { model.tideSide }, set: { model.tideSide = $0 }),
                    options: [(.left, "The left edge"), (.right, "The right edge")]
                )
                LabDivider()
                LabSlider(
                    label: "One rise and fall takes",
                    value: Binding(
                        get: { min(600, max(15, model.tidePeriodSeconds)) },
                        set: { model.tidePeriodSeconds = $0 }
                    ),
                    range: 15 ... 600,
                    step: 15
                ) { RewindBar.seconds($0) }
                LabDivider()
                LabSlider(
                    label: "How fast the water comes in",
                    value: Binding(
                        get: { min(30, max(1, model.tideStrength)) },
                        set: { model.tideStrength = $0 }
                    ),
                    range: 1 ... 30,
                    step: 1
                ) { value in
                    let grains = Int(value.rounded())
                    return grains == 1 ? "a grain a moment" : "\(grains) grains a moment"
                }
            }
        }
    }

    // MARK: Measure

    /// Measurements out as numbers, for somebody learning: a graph they draw themselves says more than any picture.
    private var measure: some View {
        LabGroup(
            "Measure",
            footnote: "Once a second while the world runs: how many cells are full, the hottest, coldest and average "
                + "temperatures, the thermometer's reading if one is in, and how many cells there are of every "
                + "material. It opens in any spreadsheet, to draw your own graphs. Time counts only while the world "
                + "is running, and rewinding takes the rows after that moment away with it."
        ) {
            LabToggle(label: "Take measurements", isOn: Binding(get: { model.isMeasuring }, set: { model.isMeasuring = $0 }))
            LabDivider()
            LabRow(label: "Rows so far", value: model.measurementRows.formatted())
            LabDivider()
            LabAction(
                label: "Send as a spreadsheet",
                detail: model.measurementRows == 0 ? "Nothing measured yet" : "Temperatures in \(temperatureUnit.title)",
                symbol: "tablecells"
            ) {
                guard let url = model.measurementsFile(unit: temperatureUnit) else { return }
                shareTarget = ShareTarget(url: url)
            }
            .disabled(model.measurementRows == 0)
            .opacity(model.measurementRows == 0 ? 0.45 : 1)
            LabDivider()
            LabAction(label: "Start a fresh sheet", symbol: "arrow.counterclockwise") {
                model.restartMeasurements()
            }
            .disabled(model.measurementRows == 0)
            .opacity(model.measurementRows == 0 ? 0.45 : 1)
        }
    }

    // MARK: Help

    /// First, because someone opening this panel for the first time is more likely to be looking for
    /// an explanation than for the grain setting.
    private var help: some View {
        LabGroup {
            LabAction(
                label: "How to use this",
                detail: "What everything does, and what the materials do to each other",
                symbol: "questionmark.circle",
                action: onShowHelp
            )
        }
    }

    // MARK: Sharing

    /// Second, because it is the only thing in this panel that involves another person, and because the
    /// summary on the row is how somebody notices they are still in a room.
    private var room: some View {
        LabGroup {
            LabAction(
                label: "Shared room",
                detail: roomSummary,
                symbol: "person.2",
                action: onShowRoom
            )
            LabDivider()
            LabAction(
                label: "Your worlds and the workshop",
                detail: cloudSummary,
                symbol: "icloud",
                action: onShowCloud
            )
        }
    }

    // MARK: Detail

    /// How fine the grid is, with the consequence shown rather than described.
    ///
    /// The figures underneath are live: the actual grid size and the actual cost of a moment, measured
    /// on this phone with this world in it. That is worth far more than any adjective — somebody can
    /// raise the setting, watch what it does to the number, and decide for themselves.
    private var detail: some View {
        LabGroup(
            "Detail",
            footnote: model.detail.explanation
                + " Changing this re-fits the world to the new grid, so it will not look identical."
        ) {
            LabChoice(
                label: nil,
                selection: Binding(get: { model.detail }, set: { model.detail = $0 }),
                options: SimulationModel.Detail.allCases.map { (value: $0, title: $0.title) }
            )
            LabDivider()
            LabRow(
                label: "Grid",
                value: "\(model.gridSize.width) × \(model.gridSize.height)"
            )
            LabDivider()
            LabRow(
                label: "A moment costs",
                value: "\(model.millisecondsPerTick.formatted(.number.precision(.fractionLength(1)))) ms",
                tint: costTint
            )
            LabDivider()
            LabRow(label: "Moments a second", value: "\(model.ticksPerSecond)", tint: rateTint)
        }
    }

    /// A frame at the display's full rate is 8.3 milliseconds, and the simulation does not get all of
    /// it — so half of that is the point at which there is still comfortable room for everything else.
    private var costTint: Color {
        let cost = model.millisecondsPerTick
        if cost <= 4.2 { return Palette.ok }
        if cost <= 8.3 { return Palette.warn }
        return Palette.danger
    }

    private var rateTint: Color {
        if model.ticksPerSecond >= 100 { return Palette.ok }
        if model.ticksPerSecond >= 50 { return Palette.warn }
        return Palette.danger
    }

    private var view: some View {
        LabGroup("What you see") {
            LabChoice(
                label: "Colour by",
                selection: Binding(get: { model.overlay }, set: { model.overlay = $0 }),
                options: [
                    (.normal, "Material"),
                    (.temperatureOverlay, "Material + heat"),
                    (.temperature, "Heat"),
                    (.density, "Heaviness"),
                ]
            )
            LabDivider()
            LabChoice(
                label: "Temperatures in",
                selection: $temperatureUnit,
                options: TemperatureUnit.allCases.map { (value: $0, title: $0.title) }
            )
            LabDivider()
            LabChoice(
                label: "Grain",
                selection: Binding(get: { model.textureMode }, set: { model.textureMode = $0 }),
                options: [
                    (.naturalGrain, "Natural"),
                    (.organicFlow, "Flowing"),
                    (.diagonalMatrix, "Crystalline"),
                    (.flat, "Flat"),
                ]
            )
        }
    }

    // MARK: World

    private var world: some View {
        LabGroup(
            "World",
            footnote: model.isSteeredByTilt
                ? "The phone's tilt is setting gravity. Tap Tilt twice more to take it back."
                : "With the chambers affecting each other, explosions here throw sparks into the "
                    + "particle field, and bodies that come to rest there silt down into sand and "
                    + "water. Pressure is the most expensive part of a moment; turning it off buys "
                    + "speed, and costs trapped gas its way out."
        ) {
            LabChoice(
                label: "Which way is down",
                selection: Binding(
                    get: { model.gravityDirection },
                    set: { model.setGravity($0) }
                ),
                options: SimulationModel.GravityDirection.allCases.map {
                    (value: $0, title: $0.title)
                }
            )
            .disabled(model.isSteeredByTilt)
            .opacity(model.isSteeredByTilt ? 0.4 : 1)

            LabDivider()
            LabSlider(
                label: "Wind",
                value: Binding(get: { model.wind }, set: { model.wind = $0 }),
                range: -5 ... 5,
                step: 1
            ) { $0 == 0 ? "still" : $0.formatted(.number.precision(.fractionLength(0))) }

            LabDivider()
            // Read in whichever scale was chosen two rows above this one. It was fixed at Celsius, so
            // the panel showed "20°C" directly underneath its own switch set to Fahrenheit — and the
            // readout on the canvas, which does obey the switch, said 68°F for the same world at the
            // same moment. A setting the app contradicts on the very next line is worse than no setting.
            LabSlider(
                label: "Room temperature",
                value: Binding(get: { model.ambientTemp }, set: { model.ambientTemp = $0 }),
                range: -40 ... 400,
                step: 5
            ) { temperatureUnit.format(celsius: $0) }

            LabDivider()
            LabToggle(label: "Sound", isOn: $soundEnabled)
            LabDivider()
            LabToggle(label: "Haptics", isOn: $hapticsEnabled)
            LabDivider()
            LabToggle(label: "Keep both running", isOn: $bothChambersRun)
            LabDivider()
            LabToggle(label: "Chambers affect each other", isOn: $chambersAffectEachOther)
            LabDivider()
            LabToggle(
                label: "Pressure",
                isOn: Binding(get: { model.pressureEnabled }, set: { model.pressureEnabled = $0 })
            )
            LabDivider()
            LabToggle(
                label: "Heat spreads",
                isOn: Binding(
                    get: { model.heatConductionEnabled },
                    set: { model.heatConductionEnabled = $0 }
                )
            )
        }
    }

    // MARK: Events

    /// The four set-piece events.
    ///
    /// Handed upwards rather than run from here, and the reason is the whole point of these existing.
    /// They are the four things in the app worth *watching* — a meteor falls before it detonates, a
    /// blast goes off three times — and every one of them used to happen behind the panel that started
    /// it. You tapped Meteor, closed the panel, and found the crater. The event worked perfectly and was
    /// impossible to see, which is indistinguishable from it not working.
    private var events: some View {
        LabGroup(
            "Make something happen",
            footnote: "The panel closes so you can watch. Each one is a single undo away."
        ) {
            ForEach(Array(PowderEventID.allCases.enumerated()), id: \.element) { index, event in
                if index > 0 { LabDivider() }
                LabAction(
                    label: Self.title(for: event),
                    detail: Self.explanation(for: event),
                    symbol: Self.symbol(for: event)
                ) {
                    onRunEvent(event)
                }
            }
        }
    }

    private static func title(for event: PowderEventID) -> String {
        switch event {
        case .meteor: "Meteor"
        case .blast: "Blast"
        case .surge: "Surge"
        case .freeze: "Freeze"
        }
    }

    private static func symbol(for event: PowderEventID) -> String {
        switch event {
        case .meteor: "flame.fill"
        case .blast: "burst.fill"
        case .surge: "water.waves"
        case .freeze: "snowflake"
        }
    }

    private static func explanation(for event: PowderEventID) -> String {
        switch event {
        case .meteor: "falls, then detonates"
        case .blast: "three explosions"
        case .surge: "a wall of water"
        case .freeze: "everything to ice"
        }
    }

    // MARK: Health

    private var health: some View {
        LabGroup(
            "Health",
            footnote: "A world can go quietly wrong in ways that do not look wrong — a cell holding "
                + "a material that no longer exists, or a temperature that is not a number. This "
                + "finds those, and undoes them."
        ) {
            LabAction(label: "Check the world's health", symbol: "stethoscope", action: onShowDiagnostics)
        }
    }

    // MARK: Development

    private var development: some View {
        LabGroup(
            "While this is being built",
            footnote: "Apple's overlay is theirs, not ours, and it only appears after the app is "
                + "opened again. The readout is ours and appears at once."
        ) {
            LabToggle(label: "Apple's graphics overlay", isOn: $graphicsOverlay)
            LabDivider()
            LabToggle(label: "Simulation readout", isOn: $showDebugOverlay)
        }
    }
}
