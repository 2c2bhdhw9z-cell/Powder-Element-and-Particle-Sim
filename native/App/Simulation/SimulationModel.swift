import CrucibleCore
import Observation
import SwiftUI
// For UIImage, which a picture of the world is returned as.
import UIKit

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
    ///
    /// Reachable from elsewhere in the app only so that `Hybrid` can bridge the two chambers. Those
    /// bridges need both engines at once and belong to neither, so they cannot be methods on either —
    /// and the alternative, a second copy of the settling rules expressed in terms these models do
    /// expose, would mean the tested version and the shipping version were different code.
    ///
    /// Nothing else should reach for this. Everything the interface needs is a property or a method
    /// here, which is what keeps the views from acquiring opinions about how the simulation works.
    let engine: PowderEngine
    private let history: PowderHistory

    /// Whether time is running.
    var isRunning = true

    /// How the grid is coloured.
    var overlay: PowderOverlayMode = .normal

    // MARK: - Making the engine's settings visible to the interface

    /// Bumped whenever anything the engine holds is written through this model.
    ///
    /// The long version of why is on `ParticleFieldModel.engineRevision`. The short version: the engine
    /// imports nothing, Observation included, so a property that merely forwards to it is invisible to
    /// SwiftUI — reading it records no dependency and writing it notifies nobody. Every forwarding
    /// property therefore reads this on the way in and bumps it on the way out.
    ///
    /// It showed up worst in the particle chamber, where a whole panel of sliders moved without their
    /// numbers ever changing. Here it was subtler and arguably nastier: this panel also shows the cost of
    /// a tick, which is refreshed once a second, so the readouts did catch up — about a second late,
    /// intermittently, which reads as the app being slow rather than as anything being wrong.
    ///
    /// **The per-frame paths must not go through these properties.** `steer(with:)` and the chamber
    /// bridges write `engine.…` directly, which keeps this out of the render loop.
    private(set) var engineRevision = 0

    /// Records a dependency on the engine's settings. Called by every forwarding getter.
    private func observeEngine() {
        _ = engineRevision
    }

    /// Records that one of the engine's settings has changed. Called by every forwarding setter.
    private func engineDidChange() {
        engineRevision &+= 1
    }

    /// Sideways wind, blowing gases and light powders along. Clamped by the engine to −5...5.
    var wind: Double {
        get { observeEngine(); return engine.windX }
        set { engine.setWind(newValue); engineDidChange() }
    }

    /// The temperature the world settles back to, and what things are placed at.
    ///
    /// The range the web version offers is enormous on purpose — a room at 400° sets wood alight
    /// on contact, and one at −40° freezes a pond solid — because the ambient is the simplest way
    /// to change what the whole world does at once.
    var ambientTemp: Double {
        get { observeEngine(); return engine.ambientTemp }
        set { engine.ambientTemp = newValue; engineDidChange() }
    }

    /// Whether the pressure field is simulated.
    ///
    /// Worth a switch rather than being always on: it is the single most expensive part of a
    /// tick — about six milliseconds of eleven at full resolution — and a world of dry powder
    /// does not need it. Turning it off costs trapped gas its ability to find a way out.
    var pressureEnabled: Bool {
        get { observeEngine(); return engine.pressureEnabled }
        set { engine.pressureEnabled = newValue; engineDidChange() }
    }

    /// Whether heat spreads between cells.
    var heatConductionEnabled: Bool {
        get { observeEngine(); return engine.heatConductionEnabled }
        set { engine.heatConductionEnabled = newValue; engineDidChange() }
    }

    /// Which way gravity points, as one of five presets.
    enum GravityDirection: String, CaseIterable, Identifiable {
        case down, up, left, right, none

        var id: String { rawValue }

        var title: String {
            switch self {
            case .down: "Down"
            case .up: "Up"
            case .left: "Left"
            case .right: "Right"
            case .none: "None"
            }
        }

        var symbol: String {
            switch self {
            case .down: "arrow.down"
            case .up: "arrow.up"
            case .left: "arrow.left"
            case .right: "arrow.right"
            case .none: "circle.slash"
            }
        }

        /// The pair the engine wants. Sideways gravity is full strength rather than a fraction,
        /// which is what makes "left" read as the world having been turned on its side.
        var vector: (x: Double, y: Double) {
            switch self {
            case .down: (0, 1)
            case .up: (0, -1)
            case .left: (-1, 0)
            case .right: (1, 0)
            case .none: (0, 0)
            }
        }
    }

    /// Which of the five presets gravity currently matches, if any.
    ///
    /// Needed so the choice in the panel can show which one is active rather than always looking
    /// unset. Anything that is not one of the five — a value dragged in by the tilt, or set by a
    /// loaded scene — reports as the nearest, which for gravity means whichever axis dominates.
    var gravityDirection: GravityDirection {
        observeEngine()
        let x = engine.gravityX
        let y = engine.gravityY
        if x == 0 && y == 0 { return .none }
        if abs(y) >= abs(x) { return y > 0 ? .down : .up }
        return x > 0 ? .right : .left
    }

    /// Points gravity in one of the five preset directions.
    func setGravity(_ direction: GravityDirection) {
        let vector = direction.vector
        // Through the properties rather than the engine, so the manual values are remembered and
        // switching tilt off afterwards comes back to this rather than to whatever was set before.
        gravityX = vector.x
        gravityY = vector.y
    }

    /// Vertical gravity. One is down, minus one is up, nought is weightless.
    var gravityY: Double {
        get { observeEngine(); return engine.gravityY }
        set {
            engine.gravityY = newValue
            manualGravityY = newValue
            engineDidChange()
        }
    }

    /// How solid grains are speckled.
    var textureMode: PowderTextureMode {
        get { observeEngine(); return engine.textureMode }
        set { engine.textureMode = newValue; engineDidChange() }
    }

    /// What a touch paints.
    var brushElement: ElementID = Element.sand
    /// How wide a touch paints, in cells.
    var brushRadius: Int = 4
    /// The shape a touch paints.
    var brushShape: BrushShape = .circle

    /// Whether the next touch samples the material under it instead of painting.
    ///
    /// A one-shot rather than a mode: it switches itself off the moment it has taken a sample, which
    /// is what people expect of an eyedropper and saves a second tap to leave it.
    var isSampling = false

    /// While replacing, the material being replaced — sampled from the first cell of the stroke.
    ///
    /// Held across the stroke rather than looked up per touch, because it has to be whatever was
    /// under the *start* of the drag. Read afresh each touch, the brush would replace whatever it had
    /// just painted and so paint everything.
    private var replaceTarget: ElementID?

    /// Sideways gravity, as the world is tilted.
    var gravityX: Double {
        get { observeEngine(); return engine.gravityX }
        set {
            engine.gravityX = newValue
            manualGravityX = newValue
            engineDidChange()
        }
    }

    /// Whether the phone's tilt is currently deciding which way is down.
    ///
    /// The gravity control reads this so it can show that it is not in charge, rather than
    /// letting someone drag a slider whose value is overwritten sixty times a second.
    private(set) var isSteeredByTilt = false

    /// Where sounds are played, when the app has provided somewhere.
    ///
    /// Optional for the same reason the sensor is: the simulation runs perfectly well in silence,
    /// and every test does.
    var audio: LabAudio?

    // MARK: - Sharing a world

    /// Whether this device is being shown somebody else's world.
    ///
    /// When it is, this engine does not step and does not read the phone's tilt. Both would be fighting
    /// the frames arriving from the host, and the host's world is the one everybody is looking at.
    var isFollowingRoom = false

    /// Called whenever a stroke is painted here, so a shared room can pass it on.
    var onLocalStroke: (@MainActor (RoomStroke) -> Void)?

    /// Called at the end of every tick, whether or not time is running.
    ///
    /// A hook rather than a second timer, for the same reason `alsoStep` is one: two clocks drift, and the
    /// display's refresh is the only honest one.
    var onTicked: (@MainActor () -> Void)?

    /// How many arriving worlds did not match the fingerprint their sender included.
    ///
    /// Should be nought. Anything else means this build assembled a world its sender did not describe —
    /// a fault here rather than on the link, since the frame arrived intact enough to be read at all.
    /// Counted and shown, because a world that is quietly slightly wrong is the hardest kind of problem
    /// to notice.
    private(set) var roomMismatches = 0

    /// The world, packed for sending to the room.
    func roomWorld(sequence: UInt32) -> RoomWorld {
        engine.captureRoomWorld(sequence: sequence)
    }

    /// The settings a peer needs to match this world.
    func roomSettings() -> RoomSettings {
        engine.roomSettings()
    }

    /// Adopts a world sent by the host.
    ///
    /// - Returns: whether it could be used. `false` leaves this world untouched.
    @discardableResult
    func applyRemote(world: RoomWorld) -> Bool {
        guard engine.apply(roomWorld: world) else { return false }
        if engine.hashLite() != world.fingerprint { roomMismatches += 1 }

        // The readouts are normally refreshed by the tick, which a follower never runs — so they are
        // refreshed here instead, at the same once-a-second rate. Counting occupied cells is a full pass
        // over the grid and worlds arrive dozens of times a second; doing it per frame would cost more
        // than displaying them.
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastSampleTime >= 1 {
            activeCells = engine.activeParticleCount
            fillHistory.record(fillFraction * 100)
            heatHistory.record(hottestCell)
            lastSampleTime = now
        }
        return true
    }

    /// Applies a stroke somebody else painted.
    ///
    /// No undo point. Undo is for taking back what *you* did, and quietly filling somebody's history with
    /// other people's marks would make their own last action several taps away.
    func applyRemote(stroke: RoomStroke) {
        _ = engine.apply(stroke, now: CFAbsoluteTimeGetCurrent())
    }

    /// Adopts the host's settings.
    func applyRemote(settings: RoomSettings) {
        engine.apply(settings)
    }

    /// Something else to step whenever this one steps.
    ///
    /// Only one chamber is on screen, and only the chamber on screen has a Metal view driving a clock
    /// — so the other one stops. That is usually right: stepping a world nobody is looking at spends
    /// the frame budget of the world they are. But a field left mid-orbit while its owner builds
    /// something in the powder chamber is a reasonable thing to want, so this exists behind a setting.
    ///
    /// A hook rather than a second timer, because two clocks would drift and the display's refresh is
    /// the only honest one.
    var alsoStep: (@MainActor () -> Void)?

    /// Whether a step is already under way.
    ///
    /// Insurance rather than a mechanism. Only one chamber is ever given a companion, but if both
    /// were, they would step each other back and forth until the app hung — and a wiring mistake
    /// should not be able to do that.
    private var isStepping = false

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
    var gridSize: (width: Int, height: Int) {
        observeEngine()
        return (engine.width, engine.height)
    }
    /// How full the world is, nought to one.
    var fillFraction: Double {
        engine.cellCount > 0 ? Double(activeCells) / Double(engine.cellCount) : 0
    }

    /// A couple of minutes of readings at one a second, for the graphs.
    ///
    /// Sampled at the same rate as the counters rather than every frame: a graph of a hundred and twenty
    /// readings covers two minutes this way, which is long enough to see a slowdown build, and it costs
    /// nothing.
    private(set) var rateHistory = SampleHistory()
    private(set) var costHistory = SampleHistory()
    private(set) var fillHistory = SampleHistory()
    private(set) var heatHistory = SampleHistory()

    private var ticksSinceSample = 0
    private var lastSampleTime = CFAbsoluteTimeGetCurrent()
    private var stepCredit: Double = 0
    /// Time spent inside the simulation since the last sample, so the cost of a step can be
    /// separated from everything else a frame does.
    private var simulationSeconds: Double = 0

    /// Whether there is anything to go back to.
    ///
    /// The record is a plain object like the engine, so the same rule applies: reading it registers
    /// nothing on its own. Without this the two arrows stayed greyed out after the first stroke, until
    /// something unrelated happened to refresh them.
    var canUndo: Bool {
        observeEngine()
        return history.canUndo
    }

    var canRedo: Bool {
        observeEngine()
        return history.canRedo
    }

    init() {
        // A starting size that a phone can run at the full refresh rate with room to spare.
        // The real size is set from the view's dimensions as soon as it is laid out, so that
        // one cell lands on one screen pixel wherever that is achievable.
        // The registry is given somewhere to keep invented materials, so they survive a relaunch.
        engine = PowderEngine(width: 220, height: 380, registry: ElementRegistry(store: CustomElementFileStore()))
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
        guard !isStepping else { return }
        isStepping = true
        defer { isStepping = false }

        // Before the pause check, so that tipping the phone still turns the world while time is
        // stopped. Gravity is the state of the world rather than an event in it, and watching a
        // paused pile hang at an angle is how you see what is about to happen when you unpause.
        //
        // Skipped entirely while being shown somebody else's world: gravity then arrives in every frame
        // from the host, and tilting this phone would be two things fighting over which way is down.
        if !isFollowingRoom {
            steer(with: tilt?.isSteering == true ? tilt?.mapping : nil)
        }
        // Outside the pause check too: a shake left mid-decay when time stopped would hold the
        // whole screen at an offset until it started again.
        decayScreenShake()

        // Before this chamber's own pause is honoured, so each chamber's pause means only itself. The
        // companion decides for itself whether it is running.
        alsoStep?()

        // A follower does not simulate, and this is the line that makes that true. It cannot simulate:
        // the physics draws thousands of random numbers a tick from this engine's own stream, so two
        // engines stepping the same world come apart inside a single frame. The host's world is the
        // truth and this one is shown it.
        if isRunning, !isFollowingRoom {
            advanceTime()
        }

        // Last of all, so a shared room is offered the world as it now stands rather than as it was
        // before this tick. Called whether or not time is running: a paused host still has a world worth
        // sending, and a follower still needs a regular moment to notice the link has gone quiet.
        onTicked?()
    }

    /// Runs the simulation forward by this frame's share of time.
    private func advanceTime() {
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

            rateHistory.record(Double(ticksPerSecond))
            costHistory.record(millisecondsPerTick)
            fillHistory.record(fillFraction * 100)
            // The hottest cell, which is what tells you whether something is on fire somewhere off
            // screen. Sampled here rather than measured separately, since it is another full pass.
            heatHistory.record(hottestCell)

            ticksSinceSample = 0
            simulationSeconds = 0
            lastSampleTime = now
        }

    }

    /// The temperature of the hottest cell that holds anything.
    ///
    /// Empty cells are skipped: air sits at the room's temperature everywhere, so including it would
    /// make the reading say "the room is 20 degrees" no matter what was burning.
    private var hottestCell: Double {
        var hottest = -Double.infinity
        for i in 0 ..< engine.cellCount where engine.type[i] != Element.empty {
            hottest = max(hottest, Double(engine.temperature[i]))
        }
        return hottest.isFinite ? hottest : engine.ambientTemp
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

    /// One element's full description, for the info card and the picker.
    ///
    /// From the registry rather than the packed physics table: this is the authoring model, with
    /// the name and description on it, which the simulation itself deliberately never reads.
    func definition(of id: ElementID) -> ElementDefinition {
        engine.registry.element(id)
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

        // Sampling takes the material under the finger and then stops, rather than painting.
        if isSampling {
            guard engine.isValid(x, y) else { return }
            let found = engine.type[engine.index(x, y)]
            // Air included: picking up "nothing" selects the eraser, which is a reasonable thing to
            // want from tapping an empty space.
            brushElement = found
            isSampling = false
            inspect(x: x, y: y)
            return
        }

        let target = brushShape == .replace ? replaceTarget : nil
        engine.drawBrush(
            centerX: x,
            centerY: y,
            radius: brushRadius,
            elementID: brushElement,
            shape: brushShape,
            targetElementID: target,
            now: CFAbsoluteTimeGetCurrent()
        )

        // Passed on as the *instruction* rather than the cells it changed. Smaller, composes with
        // whatever else is happening at that moment in the host's world, and arrives as one stroke rather
        // than a scattering of unrelated changes.
        onLocalStroke?(
            RoomStroke(
                x: x,
                y: y,
                radius: brushRadius,
                elementID: brushElement,
                shape: brushShape,
                targetElementID: target
            )
        )

        // After painting, so it reports what is now there rather than what was there a moment ago.
        // That is what makes it a confirmation of what you placed as well as a readout.
        inspect(x: x, y: y)
    }

    /// Brings the readouts back in step with the world after something outside the tick changed it.
    ///
    /// The occupied count is normally sampled once a second, because counting is a full pass over the
    /// grid. Something that changes the world in one go should not have to wait up to a second for the
    /// readout to admit it.
    func refreshCounts() {
        activeCells = engine.activeParticleCount
    }

    /// Records a point to come back to, with no stroke involved.
    ///
    /// For anything that changes the world in one go — a repair, a scene, an event — as opposed to a
    /// drag, which has a starting point and needs ``beginStroke(atFractionX:fractionY:)``.
    func recordUndoPoint() {
        history.push(engine)
        // So the undo arrow lights up now rather than whenever something else happens to refresh it.
        engineDidChange()
    }

    /// Records a point to come back to, and sets up anything the stroke needs.
    ///
    /// Called once when a stroke begins, not per touch.
    func beginStroke(atFractionX fx: Double, fractionY fy: Double) {
        // Nothing to undo for a sample, which changes no cells.
        if !isSampling {
            recordUndoPoint()
        }

        // What "replace" replaces is whatever was under the start of the drag, captured now. Looked
        // up per touch instead, the brush would replace what it had just painted and so paint
        // everything it passed over.
        if brushShape == .replace {
            let x = Int((fx * Double(engine.width)).rounded(.down))
            let y = Int((fy * Double(engine.height)).rounded(.down))
            replaceTarget = engine.isValid(x, y) ? engine.type[engine.index(x, y)] : nil
        } else {
            replaceTarget = nil
        }
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

    // MARK: - What is under your finger

    /// What the last touch found.
    struct Inspection: Equatable {
        var elementID: ElementID
        var name: String
        /// In Celsius, as the grid stores it. The reader's preferred scale is applied when shown.
        var celsius: Double
        /// Which way a fan is pointing, as an arrow, or nothing for anything else.
        var fanArrow: String?
    }

    /// The cell the last touch landed on, or nothing if there has not been one.
    ///
    /// Updated on every touch rather than only at the start of a stroke, which is a small departure
    /// from the reference. Dragging across a world and watching the readout change is how you find out
    /// how hot the middle of a lava flow is, and that seems worth more than the calmer alternative.
    private(set) var inspected: Inspection?

    /// The four directions a fan can point, in the order its counter runs through them.
    private static let fanArrows = ["→", "↓", "←", "↑"]

    /// Records what is at a cell, for the readout.
    private func inspect(x: Int, y: Int) {
        guard isValid(x, y) else { return }
        let index = engine.index(x, y)
        let id = engine.type[index]
        let definition = engine.registry.element(id)

        // A fan keeps its direction in the same slot everything else uses for a countdown, so this is
        // the only way to know which way it is pointing — and without it a row of fans is four
        // identical squares doing four different things.
        var arrow: String?
        if id == Element.fan {
            arrow = Self.fanArrows[Int(engine.life[index]) % Self.fanArrows.count]
        }

        inspected = Inspection(
            elementID: id,
            name: id == Element.empty ? "Air" : definition.name,
            celsius: Double(engine.temperature[index]),
            fanArrow: arrow
        )
    }

    /// Whether a coordinate is inside the world.
    private func isValid(_ x: Int, _ y: Int) -> Bool {
        engine.isValid(x, y)
    }

    // MARK: - The day's world

    /// Lays out the scene everybody gets today.
    ///
    /// - Returns: its name, for saying which one it was.
    @discardableResult
    func loadDailyScene(day: String) -> String {
        recordUndoPoint()
        let choice = DailyWorld.applyPowder(forDay: day, to: engine)
        activeCells = engine.activeParticleCount
        return choice.name
    }

    /// Which scene today's would be, without laying it out.
    func dailySceneName(day: String) -> String {
        DailyWorld.powderRecipe(forDay: day).name
    }

    // MARK: - Screenshots

    /// A picture of the world exactly as it appears.
    ///
    /// Taken from the engine rather than by grabbing the screen, which is not a shortcut — it is the
    /// better source. The Metal view does nothing but stretch these very pixels without smoothing
    /// them, so this *is* what is on screen, and it is available even while the app is in the
    /// background or the view has not been laid out.
    ///
    /// Enlarged by whole numbers so a grain stays a crisp square, the way the display shows it.
    /// Blending on the way up would produce a soft picture that does not look like the thing that
    /// was shared.
    func snapshot() -> UIImage? {
        let width = engine.width
        let height = engine.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            engine.render(into: base, overlay: overlay)
        }

        // Aimed at roughly the width of a large phone screen, and never below the grid's own size,
        // so a picture is worth looking at rather than a postage stamp. The choice is made by the
        // engine's own arithmetic, which is tested — including that it always actually fits.
        let factor = PixelExport.enlargement(forWidth: width, targetWidth: 1200)
        return LabSnapshot.image(fromEngineColors: pixels, width: width, height: height, scale: factor)
    }

    /// A small picture of the world, in the form the workshop stores.
    ///
    /// A data URL holding a JPEG, which is what the web version puts in the same column — so a world
    /// published from the app shows a picture in a browser and the other way round.
    ///
    /// JPEG rather than PNG, and this is the one place in the app where that is the right choice. Every
    /// other picture Crucible produces is kept lossless because a grain should stay a crisp square; a
    /// thumbnail is looked at the size of a postage stamp, and a lossless one of the largest world would
    /// be several times the limit the server accepts.
    ///
    /// - Returns: `nil` if there is nothing to draw, or if it came out larger than the server will take.
    ///   A world without a picture still publishes perfectly well, and being refused outright over a
    ///   thumbnail would be a poor trade.
    func thumbnailDataURL() -> String? {
        let width = engine.width
        let height = engine.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            // Always the plain colours, whatever overlay happens to be on screen. A heat map is a reading
            // of a world rather than a picture of it, and publishing one would show everybody else a
            // world that does not look like the world.
            engine.render(into: base, overlay: .normal)
        }

        guard let image = LabSnapshot.image(fromEngineColors: pixels, width: width, height: height),
              let jpeg = image.jpegData(compressionQuality: 0.7)
        else { return nil }

        let encoded = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        return encoded.count <= CloudLimits.thumbnailLength ? encoded : nil
    }

    // MARK: - Saving and loading

    /// The world as something that can be written to a file.
    func captureState() -> PowderState {
        engine.captureState()
    }

    /// Any materials the person invented, so a scene using them still works elsewhere.
    var customElements: [ElementDefinition] {
        engine.registry.customElements
    }

    /// The categories that actually contain something, in the order the reference lists them.
    ///
    /// Computed rather than fixed, so the "Yours" category disappears when nothing has been invented
    /// instead of offering an empty list — and appears the moment something is.
    var populatedCategories: [ElementCategory] {
        ElementCategory.allCases.filter { category in
            engine.registry.paletteElements.contains { $0.category == category }
        }
    }

    /// The materials to offer, narrowed by category and by what has been typed.
    ///
    /// - Parameters:
    ///   - category: `nil` for everything.
    ///   - search: matched anywhere in the name, ignoring case and surrounding spaces. Anywhere
    ///     rather than only at the start, because "water" should find salt water.
    func paletteElements(category: ElementCategory?, search: String) -> [ElementDefinition] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return engine.registry.paletteElements.filter { element in
            if let category, element.category != category { return false }
            guard !needle.isEmpty else { return true }
            return element.name.lowercased().contains(needle)
        }
    }

    /// The fifty materials everyone has, for pickers that offer a choice of them.
    var builtInElements: [ElementDefinition] {
        engine.registry.allElements.filter { $0.id < Element.customIDStart }
    }

    /// How many invented-material slots are still free.
    var freeCustomSlots: Int {
        Int(Element.customIDEnd) - Int(Element.customIDStart) + 1 - customElements.count
    }

    /// Invents a material and registers it.
    ///
    /// Only the six properties the editor offers are taken; everything else keeps the engine's
    /// defaults. See `ElementEditorSheet` for why that is six and not twenty.
    ///
    /// - Returns: the slot it went into, or `nil` when all fifty are full.
    func createCustomElement(
        name: String,
        color: PackedColor,
        state: ElementState,
        density: Double,
        flammability: Double,
        gravityFactor: Double,
        interactions: [InteractionRule]
    ) -> ElementID? {
        guard let id = engine.registry.nextAvailableID else { return nil }
        let definition = ElementDefinition(
            id: id,
            name: name,
            category: .custom,
            state: state,
            color: color,
            density: density,
            flammability: flammability,
            gravityFactor: gravityFactor,
            interactions: interactions,
            info: "A material you invented."
        )
        guard engine.registry.register(definition) else { return nil }
        return id
    }

    /// Removes an invented material.
    ///
    /// Cells already holding it are left exactly where they are. They behave as air until something
    /// moves them, which is the engine's existing answer for an element that is not registered —
    /// quietly rewriting someone's world to tidy up after a deletion would be worse.
    func deleteCustomElement(_ id: ElementID) {
        guard engine.registry.deleteCustomElement(id) else { return }
        // Moved off the deleted material, or the brush would keep painting something that no longer
        // exists.
        if brushElement == id { brushElement = Element.sand }
    }

    /// Puts a saved world back.
    ///
    /// - Returns: whether it was applied. `false` leaves the current world untouched, which matters:
    ///   the alternative is wiping what someone was working on in order to fail.
    @discardableResult
    func apply(_ state: PowderState) -> Bool {
        // An undo point first, so loading the wrong scene is recoverable.
        history.push(engine)
        let applied = engine.apply(state)
        activeCells = engine.activeParticleCount
        return applied
    }

    /// Registers materials that came with a scene.
    ///
    /// Already-present ones are skipped rather than overwritten. A scene should not be able to
    /// silently redefine something the person made themselves.
    func adopt(_ elements: [ElementDefinition]) {
        for element in elements where !engine.registry.table[element.id].isDefined {
            _ = engine.registry.register(element)
        }
    }

    // MARK: - Health

    /// Examines the world and reports what is wrong with it.
    ///
    /// A full pass over the grid, so this is called when the report is asked for rather than kept
    /// continuously up to date.
    func inspect() -> PowderDiagnostics {
        engine.inspect()
    }

    /// The repairs, each returning how much it changed so the interface can say so.
    ///
    /// Passed straight through rather than wrapped, because the engine is where they are
    /// implemented and tested. Undo points are the caller's business — see `DiagnosticsSheet`.
    func flushStuckCells() -> Int { engine.flushStuckCells() }
    func normaliseTemperatures() -> Int { engine.normaliseTemperatures() }
    func extinguishFires() -> Int { engine.extinguishFires() }
    func neutraliseAcids() -> Int { engine.neutraliseAcids() }

    func coolAllCells() {
        engine.coolAllCells()
    }

    // MARK: - Set-piece events

    /// How hard the screen is currently being shaken, in points. Decays every frame.
    ///
    /// The engine reports how hard an event *wants* to shake and does the shaking itself not at
    /// all — it has no screen. This is the app's side of that.
    private(set) var screenShake: Double = 0

    /// Runs one of the four set-piece events: a meteor, a blast, a surge or a freeze.
    ///
    /// The world change, the shake and the timing of the delayed half all come from the engine,
    /// where they are compared against the web version cell for cell. All this does is record an
    /// undo point, start the shake, and wait to run the second half.
    func run(_ event: PowderEventID) {
        // One undo point for the whole event, taken before anything happens, so that a meteor and
        // the explosion it causes are undone together rather than needing two taps.
        history.push(engine)

        let start = engine.start(event)
        if start.shake > 0 { screenShake = start.shake }
        // The engine reports which sound the event wants and never plays one itself; it has no
        // speaker. This is the app's side of that.
        audio?.play(start.sound, intensity: start.soundIntensity)
        activeCells = engine.activeParticleCount

        guard let followUp = start.followUp else { return }
        Task { @MainActor in
            // A delay rather than a frame count, because the pause is measured in real time and
            // should look the same whether the world is running fast, slow or is paused outright.
            try? await Task.sleep(for: .seconds(followUp.delaySeconds))
            engine.finish(followUp)
            if followUp.shake > 0 { screenShake = followUp.shake }
            audio?.play(followUp.sound, intensity: followUp.soundIntensity)
            activeCells = engine.activeParticleCount
        }
    }

    /// Where the whole surface is currently offset to, in points.
    private(set) var screenShakeOffset: CGSize = .zero

    /// A generator used only for how things look.
    ///
    /// Deliberately **not** the engine's stream. The shake picks a random offset every frame, and
    /// drawing that from the simulation's generator would let a purely decorative effect change
    /// the physics — two worlds from the same seed would diverge depending on whether anything had
    /// been blown up on screen, which would also break replay and desynchronise a shared room.
    ///
    /// The web version does draw both from one global source, but only because it has no separate
    /// one; its determinism exists solely under test, where the view never runs.
    private var presentationRandom = Mulberry32()

    /// Eases the shake off, and picks the next offset. Called once per frame from the render loop.
    ///
    /// A point a frame, matching the web version, which decays it per animation frame rather than
    /// over a fixed duration — so a shake lasts as many frames as its strength in points.
    func decayScreenShake() {
        guard screenShake > 0 else {
            if screenShakeOffset != .zero { screenShakeOffset = .zero }
            return
        }
        screenShakeOffset = CGSize(
            width: (presentationRandom.next() - 0.5) * screenShake,
            height: (presentationRandom.next() - 0.5) * screenShake
        )
        screenShake = max(0, screenShake - 1)
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

    /// How fine the grid is.
    ///
    /// ## Why this is a choice rather than a number chosen for you
    ///
    /// The cost of a moment is almost entirely the number of cells that have something in them, and
    /// that is measured rather than guessed — the benchmark prints it on every build. On Apple
    /// hardware a thirty-percent-full world costs roughly 3.2 milliseconds at 86,000 cells and 13.2
    /// at 382,000. A frame at the display's full rate is 8.3 milliseconds *in total*, and the
    /// simulation does not get all of it.
    ///
    /// So there is a genuine trade — finer material against a smoother picture — and no single right
    /// answer. Somebody building a careful scene wants detail; somebody setting off explosions wants
    /// the frame rate. One cell per screen pixel would be over three million cells and about 124
    /// milliseconds a moment, which is why it is not on the list: it is not a setting, it is a
    /// different engine.
    enum Detail: Int, CaseIterable, Identifiable, Codable {
        /// Coarse and fast, with room to spare even on a crowded world.
        case fast = 60_000
        /// The default. Comfortably inside a frame at the full refresh rate.
        case balanced = 150_000
        /// Finer, and near the limit of a full-rate frame once the world fills up.
        case fine = 320_000
        /// Finest offered. Expect the frame rate to fall on a busy world.
        case finest = 600_000

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .fast: "Fast"
            case .balanced: "Balanced"
            case .fine: "Fine"
            case .finest: "Finest"
            }
        }

        /// What to expect, in terms of what someone will actually notice.
        var explanation: String {
            switch self {
            case .fast: "Chunky material, and the smoothest motion."
            case .balanced: "A good match for most worlds."
            case .fine: "Finer material. Motion may ease off on a busy world."
            case .finest: "The finest offered. Expect slower motion once it fills up."
            }
        }

        /// The most cells this level will ask for.
        var cellBudget: Int { rawValue }
    }

    /// The chosen level.
    ///
    /// Changing it re-fits the world immediately, using the size the view last reported, so the
    /// setting takes effect while the panel is still open and the result can be seen.
    var detail: Detail = .balanced {
        didSet {
            guard detail != oldValue else { return }
            applyLastKnownSize()
        }
    }

    /// The last size the view reported, so a change of detail can re-fit without waiting for one.
    private var lastViewSize: CGSize = .zero
    private var lastViewScale: CGFloat = 1

    /// Matches the world to the space it is being drawn in.
    ///
    /// The aim is one cell per screen pixel, capped by the chosen detail. The cap is on the number of
    /// cells rather than on either side, because that is what a moment actually costs.
    func resize(toViewSize size: CGSize, scale: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        lastViewSize = size
        lastViewScale = scale
        applyLastKnownSize()
    }

    private func applyLastKnownSize() {
        let size = lastViewSize
        let scale = lastViewScale
        guard size.width > 0, size.height > 0 else { return }

        var width = Double(size.width * scale)
        var height = Double(size.height * scale)
        let cells = width * height
        let budget = Double(detail.cellBudget)
        if cells > budget {
            // Scaled down keeping the shape, so the world still matches the screen.
            let factor = (budget / cells).squareRoot()
            width *= factor
            height *= factor
        }

        let newWidth = max(32, Int(width.rounded(.down)))
        let newHeight = max(32, Int(height.rounded(.down)))
        guard newWidth != engine.width || newHeight != engine.height else { return }
        engine.resize(width: newWidth, height: newHeight)
        activeCells = engine.activeParticleCount
        // The world that was there described a different shape, so coming back to it would mean
        // stretching it. Cleaner to start the record again.
        history.clear()
    }
}
