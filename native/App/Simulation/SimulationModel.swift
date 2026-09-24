import CrucibleCore
import Observation
import SwiftUI

/// Owns the simulation and drives it forward.
///
/// ## Where the work happens
///
/// The engine is not thread-safe and does not need to be: one tick is a single pass over the
/// grid, and it is only ever entered from here. Everything in this type runs on the main
/// actor, which sounds wrong for a physics loop and is not — the tick is driven by the
/// display's own refresh signal, so it is already synchronised to when a frame is wanted,
/// and moving it to another thread would buy nothing except the need to copy the grid.
///
/// When the grid grows past what one core can manage in a frame, the work to spread will be
/// inside the tick itself, across bands of rows. That is a change to the engine, not to this.
@MainActor
@Observable
final class SimulationModel {
    /// The world. Sized to something a phone can run at full speed; see `resize`.
    private let engine: PowderEngine
    private let history: PowderHistory

    /// Whether time is running.
    var isRunning = true

    /// How the grid is coloured.
    var overlay: PowderOverlayMode = .normal

    /// How solid grains are speckled.
    var textureMode: PowderTextureMode {
        get { engine.textureMode }
        set { engine.textureMode = newValue }
    }

    /// What a touch paints.
    var brushElement: ElementID = Element.sand
    /// How wide a touch paints, in cells.
    var brushRadius: Int = 4
    /// The shape a touch paints.
    var brushShape: BrushShape = .circle

    /// Sideways gravity, as the world is tilted.
    var gravityX: Double {
        get { engine.gravityX }
        set { engine.gravityX = newValue }
    }

    /// Ticks per second actually achieved, averaged over the last second.
    private(set) var ticksPerSecond: Int = 0
    /// How many cells are occupied. Updated once a second rather than every frame.
    private(set) var activeCells: Int = 0

    private var ticksSinceSample = 0
    private var lastSampleTime = CFAbsoluteTimeGetCurrent()

    var canUndo: Bool { history.canUndo }

    init() {
        // A starting size that a phone can run at the full refresh rate with room to spare.
        // The real size is set from the view's dimensions as soon as it is laid out, so that
        // one cell lands on one screen pixel wherever that is achievable.
        engine = PowderEngine(width: 220, height: 380)
        history = PowderHistory(maximumSteps: 25)
        engine.textureMode = .naturalGrain
        loadScene(powderRecipes[0])
    }

    // MARK: - Driving time forward

    /// Advances the simulation by one frame's worth of time.
    ///
    /// Called from the display's refresh signal. A frame that arrives late is not compensated
    /// for by running several ticks: catching up makes a slow device run the world *faster*
    /// than a quick one, which changes the physics rather than the smoothness.
    func tick() {
        guard isRunning else { return }
        engine.step()

        ticksSinceSample += 1
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastSampleTime
        if elapsed >= 1 {
            ticksPerSecond = Int((Double(ticksSinceSample) / elapsed).rounded())
            // Counting occupied cells is a full pass over the grid, so it is sampled at the
            // same rate as the frame counter rather than every frame.
            activeCells = engine.activeParticleCount
            ticksSinceSample = 0
            lastSampleTime = now
        }
    }

    // MARK: - What the renderer needs

    /// The world's dimensions and how it should be coloured, read once per frame.
    func gridGeometry() -> (width: Int, height: Int, overlay: PowderOverlayMode) {
        (engine.width, engine.height, overlay)
    }

    /// Draws the current state into a buffer the caller owns.
    func renderGrid(into pixels: UnsafeMutablePointer<UInt32>, overlay: PowderOverlayMode) {
        engine.render(into: pixels, overlay: overlay)
    }

    // MARK: - Touch

    /// Paints at a point given in fractions of the view, from its top-left corner.
    ///
    /// Fractions rather than pixels, because the view and the grid are different sizes and
    /// the conversion belongs wherever the sizes are both known — which is here.
    func paint(atFractionX fx: Double, fractionY fy: Double) {
        let x = Int((fx * Double(engine.width)).rounded(.down))
        let y = Int((fy * Double(engine.height)).rounded(.down))
        engine.drawBrush(
            centerX: x,
            centerY: y,
            radius: brushRadius,
            elementID: brushElement,
            shape: brushShape,
            now: CFAbsoluteTimeGetCurrent()
        )
    }

    /// Records a point to come back to. Called once when a stroke begins, not per touch.
    func beginStroke() {
        history.push(engine)
    }

    func undo() {
        _ = history.undo(engine)
    }

    // MARK: - Scenes

    func loadScene(_ recipe: PowderRecipe) {
        history.push(engine)
        var generator = Mulberry32()
        recipe.apply(to: engine, random: &generator)
        activeCells = engine.activeParticleCount
    }

    func clear() {
        history.push(engine)
        engine.resetGrid()
        activeCells = 0
    }

    /// Matches the world to the space it is being drawn in.
    ///
    /// The aim is one cell per screen pixel, capped so that an unexpectedly large view cannot
    /// ask for a grid too big to simulate in a frame. The cap is on the number of cells
    /// rather than on either side, because that is what the tick actually costs.
    func resize(toViewSize size: CGSize, scale: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        // Chosen from measurement, not taste. On Apple hardware the engine simulates a
        // thirty-percent-full world at roughly 3.2ms for 86,000 cells and 13.2ms for 382,000
        // — see the Benchmark step of the Engine workflow, which prints this on every run.
        //
        // A 120fps frame is 8.33ms in total and the simulation does not get all of it, so
        // 150,000 cells leaves the drawing and the interface a real share. That is a long way
        // short of one cell per screen pixel, which on this phone is over three million cells
        // and currently 124ms a tick: reaching it needs the tick spread across processor
        // cores, which is a change to the engine rather than a number to raise here.
        let maximumCells = 150_000.0

        var width = Double(size.width * scale)
        var height = Double(size.height * scale)
        let cells = width * height
        if cells > maximumCells {
            // Scaled down keeping the shape, so the world still matches the screen.
            let factor = (maximumCells / cells).squareRoot()
            width *= factor
            height *= factor
        }

        let newWidth = max(32, Int(width.rounded(.down)))
        let newHeight = max(32, Int(height.rounded(.down)))
        guard newWidth != engine.width || newHeight != engine.height else { return }
        engine.resize(width: newWidth, height: newHeight)
        // The world that was there described a different shape, so coming back to it would
        // mean stretching it. Cleaner to start the record again.
        history.clear()
    }
}
