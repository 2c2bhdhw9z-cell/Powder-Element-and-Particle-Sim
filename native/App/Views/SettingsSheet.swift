import CrucibleCore
import SwiftUI

/// The lab's own panel: how it looks, what the physics does, and things that make something happen.
///
/// Opened from the button in the header, which is where the reference implementation puts it.
///
/// Built from the lab's own pieces rather than the system's grouped list. That list is quick to write
/// and looks like the Settings app — inset grey rows on a lighter grey — which is a different product
/// from a near-black room full of translucent glass.
struct SettingsSheet: View {
    let model: SimulationModel
    @Binding var glass: GlassLevel
    @Binding var showDebugOverlay: Bool
    @Binding var soundEnabled: Bool
    @Binding var bothChambersRun: Bool
    let onShowDiagnostics: () -> Void
    let onShowHelp: () -> Void

    /// Read straight from the same place the app's initialiser reads it, so the two cannot disagree
    /// about what was asked for.
    @AppStorage(DebugSettings.graphicsOverlayKey) private var graphicsOverlay = false

    var body: some View {
        LabSheet(title: "Lab", subtitle: "How it looks and how it behaves", glass: glass) {
            help
            appearance
            view
            world
            events
            health
            development
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

    // MARK: Appearance

    private var appearance: some View {
        LabGroup("Appearance", footnote: glass.explanation) {
            LabChoice(
                label: "Glass",
                selection: $glass,
                options: GlassLevel.allCases.map { (value: $0, title: $0.title) }
            )
        }
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
                : "Keeping both chambers running means the one you are not looking at carries on, at "
                    + "the cost of some of the other's speed. Pressure is the most expensive part of a "
                    + "moment; turning it off buys speed, and costs trapped gas its way out."
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
            LabSlider(
                label: "Room temperature",
                value: Binding(get: { model.ambientTemp }, set: { model.ambientTemp = $0 }),
                range: -40 ... 400,
                step: 5
            ) { "\($0.formatted(.number.precision(.fractionLength(0))))°C" }

            LabDivider()
            LabToggle(label: "Sound", isOn: $soundEnabled)
            LabDivider()
            LabToggle(label: "Keep both running", isOn: $bothChambersRun)
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

    private var events: some View {
        LabGroup("Make something happen", footnote: "Each of these is one undo away.") {
            ForEach(Array(PowderEventID.allCases.enumerated()), id: \.element) { index, event in
                if index > 0 { LabDivider() }
                LabAction(
                    label: Self.title(for: event),
                    detail: Self.explanation(for: event),
                    symbol: Self.symbol(for: event)
                ) {
                    model.run(event)
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
