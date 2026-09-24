import CrucibleCore
import SwiftUI

/// The lab: the simulation filling the screen, with controls floating over it.
///
/// This is a first pass at the interface, not the finished one. The layout follows the web
/// version — full-bleed canvas, a floating control strip — and the glass treatment described
/// in the project README is still to come, along with its intensity setting. What is here is
/// enough to hold the app in your hand and paint with it.
struct ContentView: View {
    @State private var model = SimulationModel()
    @State private var showingScenes = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                SimulationSurface(model: model)
                    .ignoresSafeArea()
                    .onAppear {
                        model.resize(
                            toViewSize: geometry.size,
                            scale: UIScreen.main.scale
                        )
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        model.resize(toViewSize: newSize, scale: UIScreen.main.scale)
                    }

                controls
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .overlay(alignment: .topTrailing) {
                readout
                    .padding(.trailing, 14)
                    .padding(.top, 6)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingScenes) {
            ScenePicker { recipe in
                model.loadScene(recipe)
                showingScenes = false
            }
        }
    }

    /// Frames per second and how full the world is.
    ///
    /// Shown permanently for now. A performance figure that is only visible in a debug menu
    /// tends to be looked at only after someone complains.
    private var readout: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(model.ticksPerSecond) fps")
                .monospacedDigit()
            Text("\(model.activeCells) cells")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.7))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            elementStrip

            HStack(spacing: 14) {
                Button {
                    model.isRunning.toggle()
                } label: {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                        .frame(width: 22)
                }
                .accessibilityLabel(model.isRunning ? "Pause" : "Play")

                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .accessibilityLabel("Undo")

                Button {
                    showingScenes = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .accessibilityLabel("Scenes")

                Button {
                    model.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Clear")

                Divider().frame(height: 22)

                // Brush size, as a slider rather than stepped buttons: it is the control
                // reached for most often while drawing.
                HStack(spacing: 6) {
                    Image(systemName: "circle.dotted")
                        .font(.caption)
                    Slider(
                        value: Binding(
                            get: { Double(model.brushRadius) },
                            set: { model.brushRadius = Int($0.rounded()) }
                        ),
                        in: 1 ... 24
                    )
                    .frame(minWidth: 80)
                }
                .accessibilityLabel("Brush size")
            }
            .font(.title3)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// The elements most reached for, in a row.
    ///
    /// A shortlist, not all fifty. The full set needs a searchable picker with categories,
    /// which is part of the interface work still to come.
    private var elementStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ContentView.quickElements, id: \.id) { entry in
                    Button {
                        model.brushElement = entry.id
                    } label: {
                        Text(entry.name)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    model.brushElement == entry.id
                                        ? Color.accentColor.opacity(0.85)
                                        : Color.white.opacity(0.12)
                                )
                            )
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 34)
    }

    private struct QuickElement {
        let id: ElementID
        let name: String
    }

    private static let quickElements: [QuickElement] = [
        QuickElement(id: Element.sand, name: "Sand"),
        QuickElement(id: Element.water, name: "Water"),
        QuickElement(id: Element.lava, name: "Lava"),
        QuickElement(id: Element.fire, name: "Fire"),
        QuickElement(id: Element.stone, name: "Stone"),
        QuickElement(id: Element.wood, name: "Wood"),
        QuickElement(id: Element.oil, name: "Oil"),
        QuickElement(id: Element.acid, name: "Acid"),
        QuickElement(id: Element.ice, name: "Ice"),
        QuickElement(id: Element.plant, name: "Plant"),
        QuickElement(id: Element.c4, name: "C4"),
        QuickElement(id: Element.spark, name: "Spark"),
        QuickElement(id: Element.copper, name: "Copper"),
        QuickElement(id: Element.bedrock, name: "Bedrock"),
        QuickElement(id: Element.empty, name: "Erase"),
    ]
}

/// Picks one of the built-in scenes.
struct ScenePicker: View {
    let onSelect: (PowderRecipe) -> Void

    var body: some View {
        NavigationStack {
            List(powderRecipes, id: \.id) { recipe in
                Button(recipe.name) { onSelect(recipe) }
            }
            .navigationTitle("Scenes")
        }
        .presentationDetents([.medium])
    }
}
