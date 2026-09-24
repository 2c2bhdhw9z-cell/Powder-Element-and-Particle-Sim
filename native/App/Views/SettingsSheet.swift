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
            }
        } header: {
            Text("Physics")
        } footer: {
            Text("Double-tap the slider to return to level.")
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
