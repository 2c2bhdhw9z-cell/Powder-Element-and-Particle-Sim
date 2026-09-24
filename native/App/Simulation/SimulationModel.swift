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
        set {
            engine.gravityX = newValue
            manualGravityX = newValue
        }
    }

    /// Whether the phone's tilt is currently deciding which way is down.
    ///
    /// The gravity control reads this so it can show that it is not in charge, rather than
    /// letting someone drag a slider whose value is overwritten sixty times a second.
    private(set) var isSteeredByTilt = false

    /// Where tilt readings come from.
    ///
    /// Injected rather than created here, because both chambers read the same phone and a second
    /// sensor would mean a second stream of readings for no benefit. Optional so the simulation
    /// runs perfectly well with no sensor at all, which is what every test does.
    var tilt: TiltSensor?

    /// Gravity as last set by hand, kept so that switching tilt off restores what was there
    /// before rather than leaving the world stuck at whatever angle the phone happened to be.
    private var manualGravityX: Double = 0
    private var manualGravityY: Double = 1

    /// How fast time runs. One is real time.
    ///
    /// Above one the world is stepped several times per frame; below one, some frames step it
    /// not at all. Both change how much simulation happens per second, which is the point —
    /// unlike a late frame, which must never be compensated for.
    var speed: Double = 1

    /// Ticks per second actually achieved, averaged over the last second.
    private(set) var ticksPerSecond: Int = 0
    /// How many cells are occupied. Updated once a second rather than every frame.
    private(set) var activeCells: Int = 0
    /// How long one step of the simulation took, in milliseconds, averaged over the last
    /// second. The number that matters: it is what has to fit inside a frame.
    private(set) var millisecondsPerTick: Double = 0
    /// The world's size, for the debug panel.
    var gridSize: (width: Int, height: Int) { (engine.width, engine.height) }
    /// How full the world is, nought to one.
    var fillFraction: Double {
        engine.cellCount > 0 ? Double(activeCells) / Double(engine.cellCount) : 0
    }

    private var ticksSinceSample = 0
    private var lastSampleTime = CFAbsoluteTimeGetCurrent()
    private var stepCredit: Double = 0
    /// Time spent inside the simulation since the last sample, so the cost of a step can be
    /// separated from everything else a frame does.
    private var simulationSeconds: Double = 0

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    init() {
        // A starting size that a phone can run at the full refresh rate with room to spare.
        // The real size is set from the view's dimensions as soon as it is laid out, so that
        // one cell lands on one screen pixel wherever that is achievable.
        engine = PowderEngine(width: 220, height: 380)
        history = PowderHistory(maximumSteps: 25)
        engine.textureMode = .naturalGrain
        loadScene(powderRecipes[0])
    }

    // MARK: - Tilt

    /// Hands gravity over to the phone's tilt, or takes it back.
    ///
    /// Called every frame with the current reading, or with nothing when tilt is off. Passing
    /// nothing is what restores the gravity that was set by hand — it is not enough to simply
    /// stop writing, because the world would stay frozen at whatever angle it was left at and
    /// switching the feature off would look like it had not worked.
    func steer(with tilt: TiltMapping?) {
        guard let tilt else {
            if isSteeredByTilt {
                isSteeredByTilt = false
                engine.gravityX = manualGravityX
                engine.gravityY = manualGravityY
            }
            return
        }

        if !isSteeredByTilt {
            isSteeredByTilt = true
            manualGravityX = engine.gravityX
            manualGravityY = engine.gravityY
        }

        engine.gravityX = tilt.gravityX
        engine.gravityY = tilt.gravityY
        // Only a real knock rattles the world. Below this the reading is the ordinary tremor of
        // a hand holding a phone, and feeding that in makes everything permanently restless.
        if tilt.shake > Self.shakeFloor {
            engine.jostle(tilt.shake)
        }
    }

    /// How hard the phone has to be moved before the world is shaken.
    private static let shakeFloor = 0.45

    // MARK: - Driving time forward

    /// Advances the simulation by one frame's worth of time.
    ///
    /// Called from the display's refresh signal. A frame that arrives late is not compensated
    /// for by running several ticks: catching up makes a slow device run the world *faster*
    /// than a quick one, which changes the physics rather than the smoothness.
    func tick() {
        // Before the pause check, so that tipping the phone still turns the world while time is
        // stopped. Gravity is the state of the world rather than an event in it, and watching a
        // paused pile hang at an angle is how you see what is about to happen when you unpause.
        steer(with: tilt?.isSteering == true ? tilt?.mapping : nil)

        guard isRunning else { return }

        // Whole steps this frame, plus a running remainder so a fractional speed averages out
        // rather than rounding to nothing. At a quarter speed this steps once every fourth
        // frame instead of never.
        stepCredit += max(0, speed)
        var steps = Int(stepCredit)
        stepCredit -= Double(steps)
        // Capped, so a high speed on a heavy world cannot spend an unbounded amount of time
        // inside one frame and freeze the interface.
        steps = min(steps, 8)
        guard steps > 0 else { return }

        let startedAt = CFAbsoluteTimeGetCurrent()
        for _ in 0 ..< steps { engine.step() }
        simulationSeconds += CFAbsoluteTimeGetCurrent() - startedAt

        ticksSinceSample += steps
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastSampleTime
        if elapsed >= 1 {
            ticksPerSecond = Int((Double(ticksSinceSample) / elapsed).rounded())
            millisecondsPerTick = ticksSinceSample > 0
                ? simulationSeconds / Double(ticksSinceSample) * 1000
                : 0
            // Counting occupied cells is a full pass over the grid, so it is sampled at the
            // same rate as the frame counter rather than every frame.
            activeCells = engine.activeParticleCount
            ticksSinceSample = 0
            simulationSeconds = 0
            lastSampleTime = now
        }
    }

    // MARK: - What the renderer needs

    /// An element's own colour, for the picker.
    ///
    /// Read from the same table the renderer draws from, so a swatch in the tray can never
    /// disagree with what appears on the canvas — including for an element someone has edited.
    func color(of id: ElementID) -> Color {
        if id == Element.empty { return Color.white.opacity(0.25) }
        let packed = engine.elements[id].color
        return Color(
            .sRGB,
            red: Double(packed.r) / 255,
            green: Double(packed.g) / 255,
            blue: Double(packed.b) / 255,
            opacity: 1
        )
    }

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
        activeCells = engine.activeParticleCount
    }

    func redo() {
        _ = history.redo(engine)
        activeCells = engine.activeParticleCount
    }

    /// Shakes the world, as a jolt of the phone would.
    func jostle() {
        engine.jostle(6)
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
