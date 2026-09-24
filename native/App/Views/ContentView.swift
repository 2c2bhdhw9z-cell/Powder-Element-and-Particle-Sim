import CrucibleCore
import SwiftUI

/// The lab.
///
/// The simulation fills the screen and everything else floats over it: tools at the top-left,
/// a dock along the bottom. Same arrangement as the web version, so the two read as one
/// product — and the same reasoning behind it, which is that the world is the thing and the
/// controls should stay out of its way.
struct ContentView: View {
    @State private var model = SimulationModel()
    @State private var isDockOpen = false
    @State private var showingScenes = false
    @State private var showingSettings = false

    /// Remembered between launches. Both of these are preferences, not state — coming back to
    /// a flat interface you chose, or a readout you left on, is the point.
    @AppStorage("glassLevel") private var glassRaw = GlassLevel.full.rawValue
    @AppStorage("showDebugOverlay") private var showDebugOverlay = false

    private var glass: GlassLevel {
        GlassLevel(rawValue: glassRaw) ?? .full
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Palette.background.ignoresSafeArea()

                SimulationSurface(model: model)
                    .ignoresSafeArea()
                    .onAppear { matchWorld(to: geometry.size) }
                    .onChange(of: geometry.size) { _, size in matchWorld(to: size) }

                // Floating chrome. Laid out from the top-left and the bottom separately so
                // neither has to know about the other.
                VStack(alignment: .leading, spacing: 8) {
                    ToolCluster(model: model, glass: glass)
                    if showDebugOverlay {
                        DebugOverlay(model: model, glass: glass)
                    }
                }
                .padding(.leading, 10)
                .padding(.top, 8)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ElementDock(
                        model: model,
                        glass: glass,
                        isOpen: $isDockOpen,
                        onShowScenes: { showingScenes = true },
                        onShowSettings: { showingSettings = true }
                    )
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Palette.background)
        .preferredColorScheme(.dark)
        .tint(Palette.primary)
        .sheet(isPresented: $showingScenes) {
            ScenePicker { recipe in
                model.loadScene(recipe)
                showingScenes = false
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(
                model: model,
                glass: Binding(get: { glass }, set: { glassRaw = $0.rawValue }),
                showDebugOverlay: $showDebugOverlay
            )
        }
    }

    private func matchWorld(to size: CGSize) {
        // `UIScreen.main` is deprecated and gives the wrong answer on an external display, but
        // the scale of the screen the view is actually on is not available from a SwiftUI
        // layout. The trait environment carries it; until that is wired through, this is the
        // scale of the device's own screen, which is right for every case the app has today.
        model.resize(toViewSize: size, scale: UIScreen.main.scale)
    }
}

/// Picks one of the built-in scenes.
struct ScenePicker: View {
    let onSelect: (PowderRecipe) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(powderRecipes, id: \.id) { recipe in
                        Button {
                            onSelect(recipe)
                        } label: {
                            HStack {
                                Text(recipe.name)
                                    .foregroundStyle(Palette.foreground)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.subtleForeground)
                            }
                        }
                        .listRowBackground(Palette.elevated)
                    }
                } footer: {
                    Text("Loading a scene replaces the world. Undo brings it back.")
                        .font(.system(size: 11))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
        .preferredColorScheme(.dark)
    }
}
