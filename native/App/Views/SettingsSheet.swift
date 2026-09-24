import CrucibleCore
import SwiftUI

/// The settings tray.
///
/// Grouped by what you are changing rather than by what it is implemented as: how the lab
/// looks, what the physics does, and the tools that exist only while the app is being built.
struct SettingsSheet: View {
    let model: SimulationModel
    @Binding var glass: GlassLevel
    @Binding var showDebugOverlay: Bool

    /// Read straight from the same place the app's initialiser reads it, so the two cannot
    /// disagree about what was asked for.
    @AppStorage(DebugSettings.graphicsOverlayKey) private var graphicsOverlay = false

    var body: some View {
        NavigationStack {
            Form {
                appearance
                view
                physics
                world
                events
                development
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
        .tint(Palette.primary)
        .preferredColorScheme(.dark)
    }

    // MARK: - World

    /// The conditions the whole world sits in: which way is down, how hard the wind blows, how
    /// hot the room is, and whether pressure is simulated at all.
    private var world: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Which way is down")
                HStack(spacing: 6) {
                    ForEach(SimulationModel.GravityDirection.allCases) { direction in
                        Button {
                            model.setGravity(direction)
                        } label: {
                            Image(systemName: direction.symbol)
                                .font(.labBody(13, .medium))
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.foreground)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                .fill(Palette.subtle)
                        )
                        .accessibilityLabel(direction.title)
                    }
                }
                // Same reason as the gravity slider: the phone rewrites this many times a second
                // while it is steering, so a button here would appear to do nothing.
                .disabled(model.isSteeredByTilt)
                .opacity(model.isSteeredByTilt ? 0.4 : 1)
            }

            slider(
                "Wind",
                value: Binding(get: { model.wind }, set: { model.wind = $0 }),
                range: -5 ... 5,
                step: 1,
                format: { $0.formatted(.number.precision(.fractionLength(0))) }
            )

            slider(
                "Room temperature",
                value: Binding(get: { model.ambientTemp }, set: { model.ambientTemp = $0 }),
                range: -40 ... 400,
                step: 5,
                format: { "\($0.formatted(.number.precision(.fractionLength(0))))°C" }
            )

            Toggle("Pressure", isOn: Binding(
                get: { model.pressureEnabled },
                set: { model.pressureEnabled = $0 }
            ))
            Toggle("Heat spreads", isOn: Binding(
                get: { model.heatConductionEnabled },
                set: { model.heatConductionEnabled = $0 }
            ))
        } header: {
            Text("World")
        } footer: {
            Text(
                "Pressure is the most expensive part of a tick. Turning it off buys speed, and "
                    + "costs trapped gas its way out."
            )
            .font(.labBody(11))
        }
    }

    // MARK: - Events

    /// The four set-piece events.
    ///
    /// Buttons rather than switches: each one happens once and changes the world, so they belong
    /// with the scene picker in spirit. Each is a single undo point, meteor and its explosion
    /// together.
    private var events: some View {
        Section {
            ForEach(PowderEventID.allCases, id: \.self) { event in
                Button {
                    model.run(event)
                } label: {
                    HStack {
                        Image(systemName: Self.symbol(for: event))
                            .frame(width: 22)
                            .foregroundStyle(Palette.muted)
                        Text(Self.title(for: event))
                            .foregroundStyle(Palette.foreground)
                        Spacer()
                        Text(Self.explanation(for: event))
                            .font(.labBody(11))
                            .foregroundStyle(Palette.subtleForeground)
                    }
                }
            }
        } header: {
            Text("Make something happen")
        } footer: {
            Text("Each of these is one undo away.")
                .font(.labBody(11))
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

    /// A labelled slider with its value shown, which the world controls all want.
    private func slider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.labNumeric(12))
                    .foregroundStyle(Palette.muted)
            }
            Slider(value: value, in: range, step: step) { Text(label) }
        }
    }

    // MARK: - Appearance

    private var appearance: some View {
        Section {
            Picker("Glass", selection: $glass) {
                ForEach(GlassLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text(glass.explanation)
                .font(.labBody(12))
                .foregroundStyle(Palette.muted)
        } header: {
            Text("Appearance")
        } footer: {
            // Said plainly, because it is the reason the setting goes all the way down rather
            // than just dimming.
            Text(
                "Every blurred panel is pixels the graphics chip has to read back and filter "
                + "on each frame, out of the same budget the simulation draws from. Turning "
                + "glass off does not fade it — there is nothing left to blur."
            )
            .font(.labBody(11))
        }
        .listRowBackground(Palette.elevated)
    }

    // MARK: - View

    private var view: some View {
        Section("View") {
            Picker("Colour by", selection: overlayBinding) {
                Text("Element").tag(PowderOverlayMode.normal)
                Text("Heat").tag(PowderOverlayMode.temperature)
                Text("Element + heat").tag(PowderOverlayMode.temperatureOverlay)
                Text("Density").tag(PowderOverlayMode.density)
            }

            Picker("Grain", selection: textureBinding) {
                Text("Natural").tag(PowderTextureMode.naturalGrain)
                Text("Crystalline").tag(PowderTextureMode.diagonalMatrix)
                Text("Flowing").tag(PowderTextureMode.organicFlow)
                Text("Flat").tag(PowderTextureMode.flat)
            }
        }
        .listRowBackground(Palette.elevated)
    }

    // MARK: - Physics

    private var physics: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Sideways gravity")
                    Spacer()
                    Text(model.gravityX.formatted(.number.precision(.fractionLength(2))))
                        .font(.labNumeric(12))
                        .foregroundStyle(Palette.muted)
                }
                Slider(value: gravityBinding, in: -1 ... 1) {
                    Text("Sideways gravity")
                }
                // A tap on the label returns it to level, which is quicker than nudging a
                // slider back to exactly nothing.
                .onTapGesture(count: 2) { model.gravityX = 0 }
                // Turned off while the phone is steering, rather than left live. The tilt
                // rewrites gravity sixty times a second, so a slider here would snap back under
                // your finger and read as broken.
                .disabled(model.isSteeredByTilt)
                .opacity(model.isSteeredByTilt ? 0.4 : 1)
            }
        } header: {
            Text("Physics")
        } footer: {
            Text(
                model.isSteeredByTilt
                    ? "The phone's tilt is setting gravity. Tap Tilt twice more to take it back."
                    : "Double-tap the slider to return to level."
            )
            .font(.labBody(11))
        }
        .listRowBackground(Palette.elevated)
    }

    // MARK: - Development

    private var development: some View {
        Section {
            Toggle("Apple's graphics overlay", isOn: $graphicsOverlay)

            if graphicsOverlay != DebugSettings.graphicsOverlayIsActive {
                // Said in place, at the moment it becomes true, rather than as a permanent
                // caveat nobody reads.
                Label(
                    graphicsOverlay
                        ? "Reopen the app to show it."
                        : "Reopen the app to hide it.",
                    systemImage: "arrow.clockwise"
                )
                .font(.labBody(12))
                .foregroundStyle(Palette.warn)
            }

            Toggle("Simulation readout", isOn: $showDebugOverlay)
        } header: {
            Text("While this is being built")
        } footer: {
            Text(
                "Apple's overlay is the one with the GPU timings and the vertex and fragment "
                + "bars. It is built into the graphics system, which decides whether to draw it "
                + "once when the app starts and offers no way to change its mind — so this "
                + "switch is applied before the graphics system looks, and lands the next time "
                + "you open the app.\n\n"
                + "The simulation readout is this app's own, so it switches instantly. It shows "
                + "what Apple's cannot see: how long one step of the physics takes, and how much "
                + "of a frame that leaves.\n\n"
                + "This whole section comes out before release."
            )
            .font(.labBody(11))
        }
        .listRowBackground(Palette.elevated)
    }

    // MARK: - Bindings

    // Written out rather than using `$model.…` because the model is a reference type whose
    // properties are observed individually; a binding straight to one reads more cleanly here
    // and keeps the picker's tag types explicit.
    private var overlayBinding: Binding<PowderOverlayMode> {
        Binding(get: { model.overlay }, set: { model.overlay = $0 })
    }

    private var textureBinding: Binding<PowderTextureMode> {
        Binding(get: { model.textureMode }, set: { model.textureMode = $0 })
    }

    private var gravityBinding: Binding<Double> {
        Binding(get: { model.gravityX }, set: { model.gravityX = $0 })
    }
}
