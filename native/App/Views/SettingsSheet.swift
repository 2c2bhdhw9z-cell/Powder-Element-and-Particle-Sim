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
                .font(.system(size: 12))
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
            .font(.system(size: 11))
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
                .font(.system(size: 11))
        }
        .listRowBackground(Palette.elevated)
    }

    // MARK: - Development

    private var development: some View {
        Section {
            Toggle("Performance readout", isOn: $showDebugOverlay)
        } header: {
            Text("While this is being built")
        } footer: {
            Text(
                "Shows frame rate, the time one step of the simulation takes, and how much of "
                + "a frame that is. Separate from iOS's own Metal overlay, which stays under "
                + "your control in the Settings app. This whole section comes out before "
                + "release."
            )
            .font(.system(size: 11))
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
