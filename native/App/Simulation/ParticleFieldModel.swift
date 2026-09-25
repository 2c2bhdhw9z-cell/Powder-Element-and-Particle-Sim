import CrucibleCore
import Observation
import SwiftUI
// For UIImage, which a picture of the world is returned as.
import UIKit

/// Owns the particle field and drives it forward.
///
/// The counterpart to `SimulationModel`, which owns the powder grid. They are kept apart
/// because they have almost nothing in common: one is a grid of cells stepped bottom-up, the
/// other a list of bodies with forces between them, and the only thing they share is that
/// something has to tick them and draw them.
@MainActor
@Observable
final class ParticleFieldModel {
    /// The engine keeps its own undo record, which already knows to capture the springs, the
    /// swarm and the toggles alongside the bodies — so there is nothing for this to duplicate.
    /// The field.
    ///
    /// Reachable from elsewhere in the app only so that `Hybrid` can bridge the two chambers — see the
    /// longer note on the powder model's. Nothing else should reach for it.
    let engine: ParticleEngine

    var isRunning = true

    /// How fast time runs. One is real time.
    var speed: Double = 1

    // MARK: - Making the engine's settings visible to the interface

    /// Bumped whenever anything the engine holds is written through this model.
    ///
    /// ## Why this has to exist
    ///
    /// Every setting below is a property that simply forwards to the engine — one place where a value
    /// lives, which is the right arrangement and is the reason a slider can never show a number the
    /// simulation is not using.
    ///
    /// But the engine is deliberately not observable. It imports nothing at all, Observation included,
    /// so that the physics compiles and is tested on any machine. And SwiftUI's observation only watches
    /// **stored** properties: a computed one that reads `engine.something` registers no dependency when
    /// it is read, and notifies nobody when it is written.
    ///
    /// The result was a settings panel that did nothing. You dragged Bounciness from one end to the
    /// other and the number beside it never moved — not because the value had not changed, but because
    /// nothing told the screen to look again. The slider's knob stayed where your finger left it, since
    /// nothing redrew it either, so it looked exactly like a control that had been ignored. Every slider
    /// in the field's panel behaved that way, and so did the choice of what happens at the edges.
    ///
    /// So this is one stored property that every one of them reads on the way in and bumps on the way
    /// out. Coarser than per-property tracking — a change to any of them refreshes anything reading any
    /// of them — which costs nothing, because all of these change only when somebody moves a control.
    ///
    /// **The per-frame paths must not go through these properties.** Tilt steering and the chamber
    /// bridges write `engine.…` directly, which is what keeps this out of the render loop.
    private(set) var engineRevision = 0

    /// Records a dependency on the engine's settings. Called by every forwarding getter.
    private func observeEngine() {
        // Reading it is the entire point: that is what registers the dependency.
        _ = engineRevision
    }

    /// Records that one of the engine's settings has changed. Called by every forwarding setter.
    private func engineDidChange() {
        engineRevision &+= 1
    }

    /// What decides each body's colour.
    var colorMode: ParticleColorMode {
        get { observeEngine(); return engine.colorMode }
        set {
            engine.colorMode = newValue
            repaintSwarmIfNeeded()
            engineDidChange()
        }
    }

    /// How far a body of liquid looks for its neighbours, in pixels.
    var fluidSmoothing: Double {
        get { observeEngine(); return engine.fluidSettings.smoothing }
        set { engine.fluidSettings.smoothing = newValue; engineDidChange() }
    }

    /// The spacing the liquid tries to keep, expressed as bodies per square pixel.
    var fluidRestDensity: Double {
        get { observeEngine(); return engine.fluidSettings.restDensity }
        set { engine.fluidSettings.restDensity = newValue; engineDidChange() }
    }

    /// How hard the liquid resists being squashed.
    var fluidStiffness: Double {
        get { observeEngine(); return engine.fluidSettings.stiffness }
        set { engine.fluidSettings.stiffness = newValue; engineDidChange() }
    }

    /// How thick the liquid is.
    var fluidViscosity: Double {
        get { observeEngine(); return engine.fluidSettings.viscosity }
        set { engine.fluidSettings.viscosity = newValue; engineDidChange() }
    }

    /// How much the liquid beads up rather than spreading out.
    var fluidCohesion: Double {
        get { observeEngine(); return engine.fluidSettings.cohesion }
        set { engine.fluidSettings.cohesion = newValue; engineDidChange() }
    }

    /// How strong the pull between bodies is.
    var bodyGravityStrength: Double {
        get { observeEngine(); return engine.bodyGravitySettings.strength }
        set { engine.bodyGravitySettings.strength = newValue; engineDidChange() }
    }

    /// How close two bodies may get before the pull stops growing.
    var bodyGravitySoftening: Double {
        get { observeEngine(); return engine.bodyGravitySettings.softening }
        set { engine.bodyGravitySettings.softening = newValue; engineDidChange() }
    }

    /// What to say about the liquid or the pull, or nothing when there is nothing worth saying.
    var forceWarning: String? {
        observeEngine()
        return SwarmCost.fluidWarning(
            bodies: bodyCount,
            fluid: engine.fluidEnabled,
            width: engine.width,
            height: engine.height,
            restDensity: engine.fluidSettings.restDensity
        ) ?? SwarmCost.bodyGravityWarning(bodies: bodyCount, gravity: engine.nbodyEnabled)
    }

    // MARK: - The timeline

    /// The recorded changes over time.
    var timeline: ParticleTimeline {
        get { observeEngine(); return engine.timeline }
        set { engine.timeline = newValue; engineDidChange() }
    }

    /// Where the timeline has got to.
    var playhead: ParticlePlayhead {
        get { observeEngine(); return engine.playhead }
        set { engine.playhead = newValue; engineDidChange() }
    }

    /// Records everything the field currently is, at the playhead.
    ///
    /// Everything rather than only what has changed, because "what has changed" would need a record of what
    /// it changed *from*, and the honest version of that is the previous keyframe — which is exactly what
    /// somebody pressing record is about to create.
    func recordKeyframe(curve: ParticleKeyframe.Curve = .smooth) {
        var next = engine.timeline
        next.record(
            ParticleKeyframe(
                at: engine.playhead.at,
                curve: curve,
                values: engine.currentTimelineValues()
            )
        )
        engine.timeline = next
        engineDidChange()
    }

    /// Starts or stops playback.
    func setTimelinePlaying(_ shouldPlay: Bool) {
        var head = engine.playhead
        head.isPlaying = shouldPlay
        // Back to the start if it was sitting at the end, so pressing play there replays rather than doing
        // nothing at all.
        if shouldPlay, head.at >= engine.timeline.duration - ParticleTimeline.sameMoment {
            head.at = 0
        }
        engine.playhead = head
        engineDidChange()
    }

    /// Moves the playhead, without starting or stopping it.
    func scrubTimeline(to moment: Double) {
        engine.playhead = engine.playhead.scrubbed(to: moment, through: engine.timeline)
        // Applied at once, so dragging the playhead shows what is there rather than waiting for the next
        // tick — which, on a paused field, would be never.
        engine.applyTimelineValues(engine.timeline.values(at: engine.playhead.at))
        engineDidChange()
    }

    /// Removes one keyframe.
    func removeKeyframe(at index: Int) {
        var next = engine.timeline
        next.remove(at: index)
        engine.timeline = next
        engineDidChange()
    }

    /// Removes the whole timeline.
    func clearTimeline() {
        var next = engine.timeline
        next.clear()
        engine.timeline = next
        engine.playhead = ParticlePlayhead()
        engineDidChange()
    }

    // MARK: - Music

    /// The microphone, when the field is listening.
    ///
    /// Made only when asked for. Holding one from the start would show the microphone indicator in the
    /// status bar for the whole life of the app, which is alarming and untrue.
    private(set) var listener: AudioListener?

    /// Which signals drive which settings.
    var audioMappings: [ParticleAudioMapping] = ParticleAudio.defaultMappings
    /// How strongly sound affects the field overall.
    var audioSensitivity: Double = 1

    /// Whether the field is reacting to sound.
    var isListening: Bool {
        listener?.isListening == true
    }

    /// Why it is not, if it is not.
    var listeningProblem: String? {
        listener?.problem
    }

    /// What the microphone is hearing, for the interface to show.
    var heardSignal: ParticleAudioSignal {
        listener?.signal ?? .silence
    }

    /// Starts or stops listening.
    func setListening(_ shouldListen: Bool) {
        if shouldListen {
            if listener == nil { listener = AudioListener() }
            listener?.start()
        } else {
            listener?.stop()
            // Put back whatever sound was changing, so switching it off restores the field exactly.
            restoreFromMusic()
            listener = nil
        }
        engineDidChange()
    }

    /// What the settings were before sound started changing them.
    ///
    /// Sound never writes into a setting — it works out a value for one frame from the resting one — so this
    /// is what "resting" means. Taken when listening starts and put back when it stops, so a session of
    /// music cannot leave the sliders somewhere they were never dragged to. The reference implementation
    /// writes into its live settings, so its sliders drift while music plays and stay drifted afterwards.
    private var restingValues: ParticleAudioBaseline?
    /// When a burst of bodies was last thrown in, in seconds of the field's own clock.
    private var lastBurstAt: Double = -1

    /// Applies what the microphone is hearing to the field, for this frame.
    private func applyMusic() {
        guard let listener, listener.isListening else { return }

        if restingValues == nil {
            restingValues = ParticleAudioBaseline(
                particleSize: engine.particleSize,
                gravityY: engine.gravityY,
                swirl: engine.vortexForce,
                glowStrength: engine.glow.strength
            )
        }
        guard let resting = restingValues else { return }

        let response = ParticleAudio.respond(
            to: listener.signal,
            mappings: audioMappings,
            sensitivity: audioSensitivity,
            baseline: resting
        )
        engine.particleSize = response.particleSize
        engine.gravityY = response.gravityY
        engine.vortexForce = response.swirl
        engine.glow.strength = response.glowStrength

        // The colour shift is expressed as a tint that walks round the ramp, which is the only way to move
        // every body's colour at once without recolouring a million of them.
        if response.colourShift > 0, engine.paletteEnabled {
            let turn = response.colourShift * 360
            engine.palette.tint = PackedColor(hue: turn, saturation: 0.35, lightness: 0.72)
        }

        // Bursts, spaced out so one drum hit spread over several frames fires once.
        let count = ParticleAudio.burstCount(strength: response.burst)
        if count > 0, engine.elapsedSeconds - lastBurstAt >= ParticleAudio.burstInterval {
            lastBurstAt = engine.elapsedSeconds
            engine.spawnBurst(count: count, x: engine.width * 0.5, y: engine.height * 0.5)
        }
    }

    /// Puts back whatever sound was changing.
    private func restoreFromMusic() {
        guard let resting = restingValues else { return }
        engine.particleSize = resting.particleSize
        engine.gravityY = resting.gravityY
        engine.vortexForce = resting.swirl
        engine.glow.strength = resting.glowStrength
        engine.palette.tint = PackedColor(r: 255, g: 255, b: 255)
        restingValues = nil
    }

    /// Whether pulling the camera back makes the world larger instead of the picture smaller.
    var zoomAddsSpace: Bool {
        get { observeEngine(); return storedCamera.growsWorldWhenZoomedOut }
        set {
            var next = storedCamera
            next.growsWorldWhenZoomedOut = newValue
            camera = next
        }
    }

    /// How many times larger the world is than the screen right now.
    var worldScale: Double {
        observeEngine()
        return storedCamera.worldScale
    }

    // MARK: - Flocking

    /// How hard bodies avoid crowding their neighbours.
    var flockSeparation: Double {
        get { observeEngine(); return engine.flockSettings.separation }
        set { engine.flockSettings.separation = newValue; engineDidChange() }
    }

    /// How hard they match their neighbours' direction.
    var flockAlignment: Double {
        get { observeEngine(); return engine.flockSettings.alignment }
        set { engine.flockSettings.alignment = newValue; engineDidChange() }
    }

    /// How hard they move toward the middle of their neighbours.
    var flockCohesion: Double {
        get { observeEngine(); return engine.flockSettings.cohesion }
        set { engine.flockSettings.cohesion = newValue; engineDidChange() }
    }

    /// How far a body can see.
    var flockVision: Double {
        get { observeEngine(); return engine.flockSettings.vision }
        set { engine.flockSettings.vision = newValue; engineDidChange() }
    }

    /// How close is too close.
    var flockPersonalSpace: Double {
        get { observeEngine(); return engine.flockSettings.personalSpace }
        set { engine.flockSettings.personalSpace = newValue; engineDidChange() }
    }

    /// How many bodies take part.
    var flockLimit: Double {
        get { observeEngine(); return Double(engine.flockSettings.limit) }
        set { engine.flockSettings.limit = Int(newValue.rounded()); engineDidChange() }
    }

    // MARK: - Trails

    /// How much of the previous frame is replaced each time — the trail length, backwards.
    var trailFade: Double {
        get { observeEngine(); return engine.trailSettings.fade }
        set { engine.trailSettings.fade = newValue; engineDidChange() }
    }

    /// How solid the line behind a body is.
    var trailOpacity: Double {
        get { observeEngine(); return engine.trailSettings.opacity }
        set { engine.trailSettings.opacity = newValue; engineDidChange() }
    }

    /// How thick that line is.
    var trailWidth: Double {
        get { observeEngine(); return engine.trailSettings.width }
        set { engine.trailSettings.width = newValue; engineDidChange() }
    }

    /// How far a body is stretched along its own motion. Nought draws it as a dot.
    var streakLength: Double {
        get { observeEngine(); return engine.trailSettings.streak }
        set { engine.trailSettings.streak = newValue; engineDidChange() }
    }

    // MARK: - Sources

    /// How many sources are pouring.
    var emitterCount: Int {
        observeEngine()
        return engine.emitters.count
    }

    /// A short description of each source, for the list.
    var emitterSummaries: [String] {
        observeEngine()
        return engine.emitters.enumerated().map { index, emitter in
            "\(index + 1). \(emitter.summary)\(emitter.isRunning ? "" : " — stopped")"
        }
    }

    /// How fast a newly placed source pours.
    var sourceRate: Double {
        get { observeEngine(); return engine.emitterTemplate.rate }
        set { setOnEveryEmitter { $0.rate = newValue } }
    }

    /// How wide a fan it sprays.
    var sourceSpread: Double {
        get { observeEngine(); return engine.emitterTemplate.spread }
        set { setOnEveryEmitter { $0.spread = newValue } }
    }

    /// How fast the bodies leave.
    var sourceSpeed: Double {
        get { observeEngine(); return engine.emitterTemplate.speed }
        set { setOnEveryEmitter { $0.speed = newValue } }
    }

    /// How much that speed varies.
    var sourceSpeedVariation: Double {
        get { observeEngine(); return engine.emitterTemplate.speedVariation }
        set { setOnEveryEmitter { $0.speedVariation = newValue } }
    }

    /// How long each body lasts. Nought means forever.
    var sourceLifespan: Double {
        get { observeEngine(); return engine.emitterTemplate.lifespan }
        set { setOnEveryEmitter { $0.lifespan = newValue } }
    }

    /// How heavy each body is.
    var sourceWeight: Double {
        get { observeEngine(); return engine.emitterTemplate.weight }
        set { setOnEveryEmitter { $0.weight = newValue } }
    }

    /// What colour, as a hue. Negative takes a random one per body.
    var sourceHue: Double {
        get { observeEngine(); return engine.emitterTemplate.hue }
        set { setOnEveryEmitter { $0.hue = newValue } }
    }

    /// Changes one number on the template *and* on every source already placed.
    ///
    /// Both, because a slider that only affected the next source somebody placed would be useless for the
    /// one they are looking at — and finding it in a list to change it there is exactly the friction the
    /// template was meant to remove.
    private func setOnEveryEmitter(_ change: (inout ParticleEmitter) -> Void) {
        var template = engine.emitterTemplate
        change(&template)
        engine.emitterTemplate = template.sanitized

        var placed = engine.emitters
        for index in placed.indices {
            change(&placed[index])
            placed[index] = placed[index].sanitized
        }
        engine.emitters = placed
        engineDidChange()
    }

    /// Stops or starts one source.
    func setEmitterRunning(_ running: Bool, at index: Int) {
        var placed = engine.emitters
        guard index >= 0, index < placed.count else { return }
        placed[index].isRunning = running
        engine.emitters = placed
        engineDidChange()
    }

    /// Removes one source.
    func removeEmitter(at index: Int) {
        recordUndoPoint()
        engine.removeEmitter(at: index)
        engineDidChange()
    }

    /// Removes every source.
    func clearEmitters() {
        recordUndoPoint()
        engine.clearEmitters()
        engineDidChange()
    }

    // MARK: - Contact

    /// How wide a body counts as for touching. Nought means work it out.
    var contactSize: Double {
        get { observeEngine(); return engine.contactSettings.size }
        set { engine.contactSettings.size = newValue; engineDidChange() }
    }

    /// How many times a tick the crowd is pushed apart.
    var contactPasses: Double {
        get { observeEngine(); return Double(engine.contactSettings.passes) }
        set { engine.contactSettings.passes = Int(newValue.rounded()); engineDidChange() }
    }

    /// How much speed survives a collision.
    var contactBounciness: Double {
        get { observeEngine(); return engine.contactSettings.bounciness }
        set { engine.contactSettings.bounciness = newValue; engineDidChange() }
    }

    /// How much sideways speed is rubbed off when two bodies scrape past.
    var contactFriction: Double {
        get { observeEngine(); return engine.contactSettings.friction }
        set { engine.contactSettings.friction = newValue; engineDidChange() }
    }

    /// Whether the wind blows.
    var flowEnabled: Bool {
        get { observeEngine(); return engine.flowEnabled }
        set { engine.flowEnabled = newValue; engineDidChange() }
    }

    /// How hard the wind pushes.
    var flowStrength: Double {
        get { observeEngine(); return engine.flowSettings.strength }
        set { engine.flowSettings.strength = newValue; engineDidChange() }
    }

    /// How large the eddies are.
    var flowScale: Double {
        get { observeEngine(); return engine.flowSettings.scale }
        set { engine.flowSettings.scale = newValue; engineDidChange() }
    }

    /// How fast the pattern itself changes.
    var flowDrift: Double {
        get { observeEngine(); return engine.flowSettings.drift }
        set { engine.flowSettings.drift = newValue; engineDidChange() }
    }

    /// How hard a written force pushes.
    var writtenForceStrength: Double {
        get { observeEngine(); return engine.writtenForceStrength }
        set { engine.writtenForceStrength = newValue; engineDidChange() }
    }

    /// The text of the sideways written force, exactly as typed.
    ///
    /// Kept separately from the compiled force, not read back off it. An expression is half-finished for
    /// most of the time it is being written — `sin(y *` is not valid and neither is `sin(y * 4` — so a box
    /// whose contents came from the last thing that compiled would erase what somebody was in the middle
    /// of typing, on nearly every keystroke.
    var writtenForceAcross: String = "" {
        didSet { setWrittenForce(writtenForceAcross, across: true) }
    }

    /// The text of the vertical written force, exactly as typed.
    var writtenForceDown: String = "" {
        didSet { setWrittenForce(writtenForceDown, across: false) }
    }

    /// What is wrong with the sideways expression, or nothing when it is fine.
    private(set) var writtenForceAcrossProblem: String?
    /// What is wrong with the vertical expression.
    private(set) var writtenForceDownProblem: String?

    /// Compiles what somebody typed, and keeps the explanation when it does not work.
    ///
    /// The last expression that *did* work stays in force while the text is broken, for the same reason
    /// the text is kept separately: a field that went dead at every intermediate keystroke would be
    /// impossible to type into. Clearing the box is the exception — an empty box means no force, and that
    /// compiles successfully, so it takes effect immediately.
    private func setWrittenForce(_ text: String, across: Bool) {
        switch ParticleForceExpression.compile(text) {
        case .success(let expression):
            if across {
                engine.writtenForceAcross = expression
                writtenForceAcrossProblem = nil
            } else {
                engine.writtenForceDown = expression
                writtenForceDownProblem = nil
            }
        case .failure(let why):
            if across {
                writtenForceAcrossProblem = why.message
            } else {
                writtenForceDownProblem = why.message
            }
        }
        engineDidChange()
    }

    /// What is drawn behind the field.
    var backdrop: ParticleBackdrop {
        get { observeEngine(); return engine.backdrop }
        set { engine.backdrop = newValue; engineDidChange() }
    }

    /// How brightly the backdrop is drawn.
    var backdropStrength: Double {
        get { observeEngine(); return engine.backdropStrength }
        set { engine.backdropStrength = newValue; engineDidChange() }
    }

    /// How bright the glow is. Nought switches it off.
    var glowStrength: Double {
        get { observeEngine(); return engine.glow.sanitized.strength }
        set { engine.glow.strength = newValue; engineDidChange() }
    }

    /// How far the glow spreads.
    var glowSpread: Double {
        get { observeEngine(); return engine.glow.sanitized.spread }
        set { engine.glow.spread = newValue; engineDidChange() }
    }

    /// How bright something has to be before it glows.
    var glowThreshold: Double {
        get { observeEngine(); return engine.glow.sanitized.threshold }
        set { engine.glow.threshold = newValue; engineDidChange() }
    }

    /// What silhouette bodies are drawn as.
    var particleShape: ParticleShape {
        get { observeEngine(); return engine.particleShape }
        set { engine.particleShape = newValue; engineDidChange() }
    }

    /// Whether a colour ramp replaces the hue arithmetic.
    var paletteEnabled: Bool {
        get { observeEngine(); return engine.paletteEnabled }
        set {
            engine.paletteEnabled = newValue
            repaintSwarmIfNeeded()
            engineDidChange()
        }
    }

    /// Which ramp the field is drawn in.
    var palette: ParticlePalette {
        get { observeEngine(); return engine.palette.palette }
        set {
            engine.palette.palette = newValue
            repaintSwarmIfNeeded()
            engineDidChange()
        }
    }

    /// The whole colour description, for the parts of the interface that edit more than the ramp.
    var paletteSpec: ParticlePaletteSpec {
        get { observeEngine(); return engine.palette }
        set {
            engine.palette = newValue
            repaintSwarmIfNeeded()
            engineDidChange()
        }
    }

    /// Whether the chosen ramp has to be reapplied every frame.
    ///
    /// Read by the warning in the dock, so it can say what a moving ramp costs at a large crowd.
    var paletteRampMoves: Bool {
        observeEngine()
        return engine.swarmColorsAreDynamic
    }

    /// Repaints the swarm after a colour change that the tick will not pick up on its own.
    ///
    /// Swarm colours are stored per body. When the ramp is driven by something that moves, the tick
    /// repaints them every frame anyway; when it is driven by a fixed position per body or by where
    /// a body sits, nothing would repaint them and the swarm would keep the colours it was spawned
    /// with — so changing the ramp would appear to do nothing at all while the field was paused.
    private func repaintSwarmIfNeeded() {
        guard engine.paletteEnabled, !engine.swarmColorsAreDynamic else { return }
        engine.recolorSwarm()
    }

    /// What a touch does.
    var mouseMode: ParticleMouseMode {
        get { observeEngine(); return engine.mouseMode }
        set { engine.mouseMode = newValue; engineDidChange() }
    }

    /// How far a touch reaches.
    var mouseRadius: Double {
        get { observeEngine(); return engine.mouseRadius }
        set { engine.mouseRadius = newValue; engineDidChange() }
    }

    /// What happens at the edges of the world.
    var boundaryMode: ParticleBoundaryMode {
        get { observeEngine(); return engine.boundaryMode }
        set { engine.boundaryMode = newValue; engineDidChange() }
    }

    var gravityX: Double {
        get { observeEngine(); return engine.gravityX }
        set {
            engine.gravityX = newValue
            manualGravityX = newValue
            engineDidChange()
        }
    }

    var gravityY: Double {
        get { observeEngine(); return engine.gravityY }
        set {
            engine.gravityY = newValue
            manualGravityY = newValue
            engineDidChange()
        }
    }

    /// Whether the phone's tilt is currently deciding which way is down.
    private(set) var isSteeredByTilt = false

    /// Where tilt readings come from. Shared with the powder chamber — one phone, one sensor.
    var tilt: TiltSensor?

    /// Something else to step whenever this one steps. See the note on the powder model's.
    var alsoStep: (@MainActor () -> Void)?

    /// Whether a step is already under way.
    ///
    /// Insurance rather than a mechanism. Only one chamber is ever given a companion, but if both
    /// were, they would step each other back and forth until the app hung — and a wiring mistake
    /// should not be able to do that.
    private var isStepping = false

    /// Gravity as last set by hand, restored when tilt is switched off.
    ///
    /// The resting value is the field's own gentle default rather than the powder world's full
    /// strength: a field of free bodies under real gravity just falls to the floor and stops.
    private var manualGravityX: Double = 0
    private var manualGravityY: Double = 0.28

    /// Hands gravity over to the phone's tilt, or takes it back.
    ///
    /// The field gets a fraction of the tilt the powder world does, for the same reason its
    /// resting gravity is gentler. See ``TiltMapping``.
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

        engine.gravityX = tilt.particleGravityX
        engine.gravityY = tilt.particleGravityY
    }

    /// The field as something that can be written to a file.
    ///
    /// The camera is added here rather than by the engine, because the engine does not have one — it
    /// knows nothing about views or screens, and that is deliberate.
    func captureState() -> ParticleState {
        var state = engine.captureState()
        state.camera = storedCamera
        return state
    }

    /// Puts a saved field back.
    ///
    /// - Returns: whether it was applied. `false` leaves the current field alone.
    @discardableResult
    func apply(_ state: ParticleState) -> Bool {
        // An undo point first, so loading the wrong scene is recoverable.
        recordUndoPoint()
        let applied = engine.apply(state)
        if applied {
            // A file with no camera in it was written before there was one to save, and the right
            // reading of that is the resting view rather than whatever the last scene happened to
            // leave behind.
            camera = state.camera ?? .identity
        }
        bodyCount = engine.bodyCount
        return applied
    }

    /// How much speed survives each moment. One is frictionless; below about 0.97 the field
    /// visibly congeals.
    var damping: Double {
        get { observeEngine(); return engine.damping }
        set { engine.damping = newValue; engineDidChange() }
    }

    /// How much of its speed a body keeps when it bounces off a wall.
    var elasticity: Double {
        get { observeEngine(); return engine.elasticity }
        set { engine.elasticity = newValue; engineDidChange() }
    }

    /// How strongly charged bodies push and pull on one another.
    var electrostaticFactor: Double {
        get { observeEngine(); return engine.electrostaticFactor }
        set { engine.electrostaticFactor = newValue; engineDidChange() }
    }

    /// A whole-field swirl. Negative spins the other way.
    var vortexForce: Double {
        get { observeEngine(); return engine.vortexForce }
        set { engine.vortexForce = newValue; engineDidChange() }
    }

    /// The fastest anything may travel, which is what stops a close encounter flinging a body off
    /// the screen.
    var maxSpeed: Double {
        get { observeEngine(); return engine.maxSpeed }
        set { engine.maxSpeed = newValue; engineDidChange() }
    }

    /// How hard a finger pulls or pushes.
    var mouseForceMultiplier: Double {
        get { observeEngine(); return engine.mouseForceMultiplier }
        set { engine.mouseForceMultiplier = newValue; engineDidChange() }
    }

    /// How quickly bodies with a lifespan fade away. Zero means they never do.
    var decaySpeed: Double {
        get { observeEngine(); return engine.decaySpeed }
        set { engine.decaySpeed = newValue; engineDidChange() }
    }

    /// Whether the reach is effectively unlimited, so the interface can say so rather than showing a
    /// number that suggests a boundary.
    var hasUnlimitedReach: Bool {
        observeEngine()
        return ParticleOverlayStyle.isUnlimited(reach: engine.mouseRadius)
    }

    /// Where a picture of the field comes from.
    ///
    /// Set by the Metal view when it appears, because the field is drawn as real geometry on the GPU
    /// — discs, trails, springs and the ring — and none of that exists anywhere the simulation can
    /// reach. The powder chamber needs no such arrangement: its renderer produces finished pixels,
    /// so a picture of it can be made from the engine alone.
    ///
    /// Optional, so the model works with no view attached, which is what every test does.
    /// Marked as belonging to the main actor, because drawing is: the closure reaches a Metal view.
    /// Left unannotated, a stored closure could in principle be called from anywhere.
    var snapshotProvider: (@MainActor () -> UIImage?)?

    /// A picture of the field exactly as it appears, or nothing if there is no view to ask.
    func snapshot() -> UIImage? {
        snapshotProvider?()
    }

    /// Lays out the arrangement everybody gets today.
    ///
    /// - Returns: its name.
    @discardableResult
    func loadDailyArrangement(day: String) -> String {
        recordUndoPoint()
        let choice = DailyWorld.applyParticle(forDay: day, to: engine)
        bodyCount = engine.bodyCount
        return choice.name
    }

    var showTrails: Bool {
        get { observeEngine(); return engine.showTrails }
        set { engine.showTrails = newValue; engineDidChange() }
    }

    /// Whether bodies behave as a fluid, pressing on one another like water.
    ///
    /// A genuinely different physics rather than a visual option — it is what makes the pouring
    /// arrangement look like water instead of like falling beads. Expensive, and off by default, which
    /// is why the arrangements that want it switch it on themselves.
    var fluidEnabled: Bool {
        get { observeEngine(); return engine.fluidEnabled }
        set { engine.fluidEnabled = newValue; engineDidChange() }
    }

    /// Whether bodies steer by their neighbours, as a flock of birds does.
    var flockEnabled: Bool {
        get { observeEngine(); return engine.flockEnabled }
        set { engine.flockEnabled = newValue; engineDidChange() }
    }

    /// Whether every body pulls on every other, as masses do.
    ///
    /// The most expensive thing here by a wide margin: the work grows with the square of the number of
    /// bodies, so it is meant for a few hundred rather than a few hundred thousand.
    var nbodyEnabled: Bool {
        get { observeEngine(); return engine.nbodyEnabled }
        set { engine.nbodyEnabled = newValue; engineDidChange() }
    }

    /// Drops a gravity well wherever the last touch was, or in the middle if there has not been one.
    ///
    /// A well is a body like any other as far as the field is concerned; it simply pulls hard enough to
    /// organise everything around it, which is the quickest way to turn a scattered field into
    /// something worth watching.
    func dropWell() {
        recordUndoPoint()
        let x = engine.lastMouseActive || engine.lastMouseX != 0 ? engine.lastMouseX : engine.width / 2
        let y = engine.lastMouseActive || engine.lastMouseY != 0 ? engine.lastMouseY : engine.height / 2
        engine.placeWell(x: x, y: y)
        bodyCount = engine.bodyCount
    }

    var collisionsEnabled: Bool {
        get { observeEngine(); return engine.collisionsEnabled }
        set { engine.collisionsEnabled = newValue; engineDidChange() }
    }

    /// How wide a body is drawn, in pixels.
    var particleSize: Double {
        get { observeEngine(); return engine.particleSize }
        set { engine.particleSize = newValue; engineDidChange() }
    }

    private(set) var ticksPerSecond = 0
    private(set) var millisecondsPerTick: Double = 0
    private(set) var bodyCount = 0

    /// A couple of minutes of readings, for the graphs.
    private(set) var rateHistory = SampleHistory()
    private(set) var costHistory = SampleHistory()
    private(set) var populationHistory = SampleHistory()
    private(set) var speedHistory = SampleHistory()

    private var ticksSinceSample = 0
    private var simulationSeconds: Double = 0
    private var lastSampleTime = CFAbsoluteTimeGetCurrent()
    private var stepCredit: Double = 0

    /// Where the touch is, and whether it is down. Read by the tick.
    private var touchX: Double = 0
    private var touchY: Double = 0
    private var touchActive = false

    var canUndo: Bool {
        observeEngine()
        return engine.canUndo
    }

    var canRedo: Bool {
        observeEngine()
        return engine.canRedo
    }

    var worldSize: (width: Double, height: Double) {
        observeEngine()
        return (engine.width, engine.height)
    }

    init() {
        engine = ParticleEngine(width: 400, height: 700)
        engine.spawnGalaxy(count: 400)
        bodyCount = engine.bodyCount
    }

    // MARK: - Time

    func tick(now: Double) {
        guard !isStepping else { return }
        isStepping = true
        defer { isStepping = false }

        // Before the pause check, so tipping the phone still turns the field while time is
        // stopped. See the same note in SimulationModel.
        steer(with: tilt?.isSteering == true ? tilt?.mapping : nil)

        // Also before the pause check, and for the same reason: the automatic spin is a way of
        // looking at the field, not part of it. Somebody who pauses to study an arrangement should
        // still be able to turn it round and see the shape of it.
        advanceCameraSpin(now: now)

        // Sound is applied before the pause check as well: a paused field reacting to music is a
        // perfectly sensible thing to want, and it is how somebody would set the mappings up in the first
        // place — by watching what each one does without the field also flying about.
        applyMusic()

        // And the backdrop keeps moving while paused too. Stars that stopped twinkling the moment time
        // stopped would make a paused field look broken rather than paused.
        if let last = lastBackdropTime, now > last {
            backdropSeconds += min(0.1, (now - last) / 1000)
        }
        lastBackdropTime = now

        // Before this chamber's own pause is honoured, so each chamber's pause means only itself. The
        // companion decides for itself whether it is running.
        alsoStep?()

        guard isRunning else { return }
        stepCredit += max(0, speed)
        var steps = Int(stepCredit)
        stepCredit -= Double(steps)
        // Capped so a high speed on a crowded field cannot spend an unbounded amount of time
        // inside one frame and freeze the interface.
        steps = min(steps, 6)
        guard steps > 0 else { return }

        let startedAt = CFAbsoluteTimeGetCurrent()
        for _ in 0 ..< steps {
            engine.step(
                mouseX: touchActive ? touchX : nil,
                mouseY: touchActive ? touchY : nil,
                mouseActive: touchActive,
                now: now
            )
        }
        simulationSeconds += CFAbsoluteTimeGetCurrent() - startedAt

        ticksSinceSample += steps
        let sampledAt = CFAbsoluteTimeGetCurrent()
        let elapsed = sampledAt - lastSampleTime
        if elapsed >= 1 {
            ticksPerSecond = Int((Double(ticksSinceSample) / elapsed).rounded())
            millisecondsPerTick = ticksSinceSample > 0
                ? simulationSeconds / Double(ticksSinceSample) * 1000
                : 0
            bodyCount = engine.bodyCount

            rateHistory.record(Double(ticksPerSecond))
            costHistory.record(millisecondsPerTick)
            populationHistory.record(Double(bodyCount))
            speedHistory.record(fastestBody)

            ticksSinceSample = 0
            simulationSeconds = 0
            lastSampleTime = sampledAt
        }

    }

    // MARK: - What the renderer needs

    /// Everything the renderer reads in one go, so it makes a single call per frame.
    struct Frame {
        var worldWidth: Double
        var worldHeight: Double
        /// The view's own size, in points. The camera's pan is measured in these.
        var viewWidth: Double
        var viewHeight: Double
        /// Where the field is being looked at from.
        var camera: ParticleCamera
        /// What silhouette bodies are drawn as.
        var shape: ParticleShape
        /// What is drawn behind the field.
        var background: ParticleBackdrop
        /// How brightly that is drawn.
        var backgroundStrength: Double
        /// How much of the previous frame is replaced each time — the trail length control.
        var trailFade: Double
        /// Seconds since the field started, for the twinkle and the drift.
        ///
        /// Seconds rather than the millisecond clock the rest of the tick uses, because a shader's
        /// arithmetic is single precision: a millisecond count reaches seven figures within a couple of
        /// minutes, and at that size single precision cannot tell one millisecond from the next — so the
        /// twinkle would visibly seize up the longer the app was left running.
        var backgroundTime: Double
        var bodyCount: Int
        var springCount: Int
        var pointSize: Double
        var swarmCount: Int
        /// How many line segments of trail there are to draw. Two points and two colours each.
        var trailSegmentCount: Int
        /// Whether the crowd is drawn as streaks along its motion rather than as dots.
        ///
        /// A trail says where something has been; a streak says how fast it is going now. A field of fast
        /// bodies drawn as dots reads as a static scatter however quickly it is moving, because a dot has no
        /// direction.
        var swarmIsStreaked: Bool
        /// How many line segments of drawn walls and painted wind there are.
        ///
        /// Drawn as lines in the same way the trails are, and for the same reason: they are structure rather
        /// than substance, and a line is the cheapest honest way to show a direction.
        var guideSegmentCount: Int
        /// Where the ring should be drawn, or nothing while no finger is down.
        var touchRing: TouchRing?
    }

    /// The ring round a finger.
    ///
    /// Measured in screen points, not world units. It used to be world units, because the world was
    /// the screen and the two were the same thing — but with a camera a ring specified in world units
    /// would be transformed along with the bodies, and under a tilt a circle does not stay a circle.
    /// The ring would arrive as a lopsided egg drawn round a perfectly round finger. So the centre
    /// goes through the camera here and the sizes stay constant on screen, which is what an interface
    /// affordance should do.
    struct TouchRing {
        var x: Double
        var y: Double
        var radius: Double
        var strokeWidth: Double
        var centreDotRadius: Double
        var red: Double
        var green: Double
        var blue: Double
        var strokeOpacity: Double
        var fillOpacity: Double
    }

    /// Fills the caller's buffers and reports what it wrote.
    ///
    /// The buffers belong to the renderer, which holds them across frames so that a steady
    /// field allocates nothing. Grown here only when the field outgrows them.
    func fillFrame(
        positions: inout [Float],
        colors: inout [UInt32],
        springPositions: inout [Float],
        swarmPositions: inout [Float],
        swarmColors: inout [UInt32],
        trailPositions: inout [Float],
        trailColors: inout [UInt32],
        guidePositions: inout [Float],
        guideColors: inout [UInt32]
    ) -> Frame {
        let bodies = engine.particles

        let neededPositions = bodies.count * 2
        if positions.count < neededPositions {
            positions.append(contentsOf: repeatElement(0, count: neededPositions - positions.count))
        }
        engine.fillRenderColors(into: &colors)
        for (index, body) in bodies.enumerated() {
            positions[index * 2] = Float(body.x)
            positions[index * 2 + 1] = Float(body.y)
        }

        // Two ends per spring, as a plain list of line endpoints.
        let springs = engine.springs
        let neededSprings = springs.count * 4
        if springPositions.count < neededSprings {
            springPositions.append(
                contentsOf: repeatElement(0, count: neededSprings - springPositions.count)
            )
        }
        var written = 0
        for spring in springs {
            guard spring.a < bodies.count, spring.b < bodies.count else { continue }
            springPositions[written * 4] = Float(bodies[spring.a].x)
            springPositions[written * 4 + 1] = Float(bodies[spring.a].y)
            springPositions[written * 4 + 2] = Float(bodies[spring.b].x)
            springPositions[written * 4 + 3] = Float(bodies[spring.b].y)
            written += 1
        }

        // The swarm is already stored as the GPU wants it — interleaved pairs of single
        // precision floats — so it is copied straight across rather than converted.
        let swarmCount = engine.swarm.count
        let neededSwarm = swarmCount * 2
        if swarmPositions.count < neededSwarm {
            swarmPositions.append(
                contentsOf: repeatElement(0, count: neededSwarm - swarmPositions.count)
            )
        }
        if swarmColors.count < swarmCount {
            swarmColors.append(
                contentsOf: repeatElement(0, count: swarmCount - swarmColors.count)
            )
        }
        // Drawn as streaks or as dots. A streak is two points per body and two colours, a dot is one of
        // each, so the buffers are filled differently — and the alternative, always filling two and drawing
        // one, would double the work of the most expensive upload in the app for nothing.
        let streak = engine.trailSettings.sanitized.streak
        let streaked = streak > 0 && swarmCount > 0
        if streaked {
            let wanted = swarmCount * 4
            if swarmPositions.count < wanted {
                swarmPositions.append(contentsOf: repeatElement(0, count: wanted - swarmPositions.count))
            }
            if swarmColors.count < swarmCount * 2 {
                swarmColors.append(
                    contentsOf: repeatElement(0, count: swarmCount * 2 - swarmColors.count)
                )
            }
            for index in 0 ..< swarmCount {
                let pair = index * 2
                let x = engine.swarm.positions[pair]
                let y = engine.swarm.positions[pair + 1]
                // Behind the body, along the way it came, rather than ahead of it. A streak drawn ahead puts
                // the bright end where the body is not, and the eye follows the wrong end.
                let tailX = x - engine.swarm.velocities[pair] * Float(streak)
                let tailY = y - engine.swarm.velocities[pair + 1] * Float(streak)
                let at = index * 4
                swarmPositions[at] = tailX.isFinite ? tailX : x
                swarmPositions[at + 1] = tailY.isFinite ? tailY : y
                swarmPositions[at + 2] = x
                swarmPositions[at + 3] = y
                let colour = engine.swarm.colors[index]
                swarmColors[index * 2] = colour
                swarmColors[index * 2 + 1] = colour
            }
        } else {
            for i in 0 ..< neededSwarm { swarmPositions[i] = engine.swarm.positions[i] }
            for i in 0 ..< swarmCount { swarmColors[i] = engine.swarm.colors[i] }
        }

        let trailSegments = fillTrails(
            positions: &trailPositions,
            colors: &trailColors,
            bodies: bodies
        )

        return Frame(
            worldWidth: engine.width,
            worldHeight: engine.height,
            // The view's own size, which is *not* the world's any more: pulling the camera back grows the
            // world beyond the screen so the crowd has more room. The pan is measured in screen pixels, so
            // it needs the screen.
            viewWidth: viewPixelWidth > 0 ? viewPixelWidth : engine.width,
            viewHeight: viewPixelHeight > 0 ? viewPixelHeight : engine.height,
            camera: camera,
            shape: engine.particleShape,
            background: engine.backdrop,
            backgroundStrength: engine.backdropStrength,
            trailFade: engine.trailSettings.sanitized.fade,
            backgroundTime: backdropSeconds,
            bodyCount: bodies.count,
            springCount: written,
            pointSize: max(1, engine.particleSize * 2),
            swarmCount: swarmCount,
            swarmIsStreaked: streaked,
            trailSegmentCount: trailSegments,
            guideSegmentCount: fillGuides(positions: &guidePositions, colors: &guideColors),
            touchRing: currentTouchRing()
        )
    }

    /// Turns the walls and the painted wind into line segments.
    ///
    /// Both are invisible otherwise, and an invisible control is not a control — somebody painting wind needs
    /// to see where they have painted, and somebody who has drawn twelve walls needs to see the twelve.
    private func fillGuides(positions: inout [Float], colors: inout [UInt32]) -> Int {
        let walls = engine.walls
        let current = engine.current
        let showCurrent = !current.isEmpty
        let arrowCount = showCurrent ? current.resolution * current.resolution : 0
        let needed = (walls.count + arrowCount) * 4
        guard needed > 0 else { return 0 }

        if positions.count < needed {
            positions.append(contentsOf: repeatElement(0, count: needed - positions.count))
        }
        let neededColors = (walls.count + arrowCount) * 2
        if colors.count < neededColors {
            colors.append(contentsOf: repeatElement(0, count: neededColors - colors.count))
        }

        var segments = 0

        /// One line, in world coordinates, with a colour at each end.
        func line(_ fromX: Double, _ fromY: Double, _ toX: Double, _ toY: Double, _ colour: UInt32) {
            let at = segments * 4
            positions[at] = Float(fromX)
            positions[at + 1] = Float(fromY)
            positions[at + 2] = Float(toX)
            positions[at + 3] = Float(toY)
            colors[segments * 2] = colour
            colors[segments * 2 + 1] = colour
            segments += 1
        }

        // The wind first, so a wall drawn across it reads as being in front.
        if showCurrent {
            // Long enough to see, short enough that a full field of them does not become a solid block.
            let reach = min(engine.width, engine.height) / Double(current.resolution) * 0.42
            let arrowColour = PackedColor(r: 0x38, g: 0xBD, b: 0xF8, a: 0x8C).packedRGBA
            for row in 0 ..< current.resolution {
                for column in 0 ..< current.resolution {
                    let acrossFraction = (Double(column) + 0.5) / Double(current.resolution)
                    let downFraction = (Double(row) + 0.5) / Double(current.resolution)
                    let push = current.sample(atFractionX: acrossFraction, y: downFraction)
                    let length = (push.x * push.x + push.y * push.y).squareRoot()
                    // Unpainted squares are skipped rather than drawn as dots, so the picture shows where the
                    // wind is and not where the grid is.
                    guard length > 0.04 else { continue }
                    let atX = acrossFraction * engine.width
                    let atY = downFraction * engine.height
                    line(
                        atX - push.x * reach * 0.5,
                        atY - push.y * reach * 0.5,
                        atX + push.x * reach * 0.5,
                        atY + push.y * reach * 0.5,
                        arrowColour
                    )
                }
            }
        }

        let wallColour = PackedColor(r: 0xFB, g: 0xBF, b: 0x24, a: 0xD9).packedRGBA
        for wall in walls {
            line(
                wall.fromX * engine.width,
                wall.fromY * engine.height,
                wall.toX * engine.width,
                wall.toY * engine.height,
                wallColour
            )
        }

        return segments
    }

    /// Turns each body's remembered positions into line segments.
    ///
    /// A segment rather than a connected strip, because one draw call cannot hold several separate
    /// polylines without either an index buffer or a restart marker — and a flat list of segments is
    /// simpler than both for something at most six points long.
    ///
    /// Only below the drawing limit, matching the reference implementation: above a thousand bodies
    /// it stops drawing shapes altogether, and a thousand trails would be thousands of lines for a
    /// picture too dense to read anyway.
    private func fillTrails(
        positions: inout [Float],
        colors: inout [UInt32],
        bodies: [ParticleObject]
    ) -> Int {
        let trail = engine.trailSettings.sanitized
        guard engine.showTrails, bodies.count <= trail.lineLimit else { return 0 }

        // The colour a trail is drawn in is the body's current colour under whichever colour mode is
        // selected, so a trail agrees with the thing that left it.
        let density = engine.densityGridIfNeeded()
        let opacity = UInt32(max(0, min(255, (trail.opacity * 255).rounded())))

        var segments = 0
        for body in bodies {
            let trail = body.trail
            guard trail.count > 1 else { continue }
            // The alpha is baked into the colour rather than set as a pipeline constant, so a single
            // draw call can carry every trail.
            let packed = engine.renderColor(of: body, density: density)
            let colour = UInt32(packed.r) | (UInt32(packed.g) << 8) | (UInt32(packed.b) << 16)
                | (opacity << 24)

            for i in 1 ..< trail.count {
                guard let from = trail.point(at: i - 1), let to = trail.point(at: i) else { continue }
                let needed = (segments + 1) * 4
                if positions.count < needed {
                    positions.append(contentsOf: repeatElement(0, count: needed - positions.count))
                }
                if colors.count < (segments + 1) * 2 {
                    colors.append(
                        contentsOf: repeatElement(0, count: (segments + 1) * 2 - colors.count)
                    )
                }
                positions[segments * 4] = from.x
                positions[segments * 4 + 1] = from.y
                positions[segments * 4 + 2] = to.x
                positions[segments * 4 + 3] = to.y
                colors[segments * 2] = colour
                colors[segments * 2 + 1] = colour
                segments += 1
            }
        }
        return segments
    }

    /// The ring, while a finger is down.
    ///
    /// Its size comes from the engine, which knows the rule that stops it lying about how far the
    /// pull reaches — at the top of the range there is no limit, and a modest circle would suggest
    /// there was.
    private func currentTouchRing() -> TouchRing? {
        guard engine.lastMouseActive else { return nil }
        let colour = ParticleOverlayStyle.ringColor

        // Where the finger is in the world, put back through the camera, so the ring follows the
        // body it is acting on rather than staying where the finger happens to be on a tilted view.
        let placed = camera.project(
            x: engine.lastMouseX,
            y: engine.lastMouseY,
            worldWidth: engine.width,
            worldHeight: engine.height,
            viewWidth: engine.width,
            viewHeight: engine.height
        )
        let worldRadius = ParticleOverlayStyle.ringRadius(
            reach: engine.mouseRadius,
            worldWidth: engine.width,
            worldHeight: engine.height
        )

        return TouchRing(
            x: (placed.x + 1) * 0.5 * engine.width,
            y: (1 - placed.y) * 0.5 * engine.height,
            // The reach is a distance in the world, so it grows and shrinks with the view. Under a
            // tilt it is also drawn at the depth its centre sits at — a circle on a tilted plane is
            // properly an ellipse, and this is one number rather than two, so it is an approximation
            // and is stated as one. It is an aiming aid, not a measurement.
            radius: worldRadius * camera.drawScale(depthScale: placed.depthScale),
            // These two do not scale. They are parts of the interface rather than parts of the
            // world, and a hairline that thickened as you zoomed in would read as a fault.
            strokeWidth: ParticleOverlayStyle.ringStrokeWidth,
            centreDotRadius: ParticleOverlayStyle.ringCentreDotRadius,
            red: Double(colour.r) / 255,
            green: Double(colour.g) / 255,
            blue: Double(colour.b) / 255,
            strokeOpacity: ParticleOverlayStyle.ringStrokeOpacity,
            fillOpacity: ParticleOverlayStyle.ringFillOpacity
        )
    }

    // MARK: - Touch

    /// Where the finger was last, for the tools that draw a stroke rather than apply a force.
    private var strokeFromX: Double?
    private var strokeFromY: Double?
    /// Whether this drag has already placed a source.
    ///
    /// One per drag. Without it, dragging across the field would leave a source every few pixels and reach the
    /// limit of twelve before the finger had moved an inch.
    private var placedSourceThisStroke = false

    /// Which way a pair of offsets points, in radians.
    ///
    /// By hand, because the engine has no inverse tangent — it imports nothing, not even the C maths library.
    /// This is the standard rational approximation, good to about a thousandth of a radian, which for aiming a
    /// source with a fingertip is far finer than the gesture itself.
    private func jsAtan2Approximate(_ y: Double, _ x: Double) -> Double {
        guard x.isFinite, y.isFinite, x != 0 || y != 0 else { return 0 }
        let absX = abs(x)
        let absY = abs(y)
        let smallOverLarge = absY < absX ? absY / absX : absX / absY
        let squared = smallOverLarge * smallOverLarge
        var angle = ((-0.013_480_47 * squared + 0.057_477_314) * squared - 0.121_239_071) * squared
        angle = ((angle + 0.195_635_925) * squared - 0.332_994_597) * squared
        angle = (angle + 0.999_995_630) * smallOverLarge
        if absY >= absX { angle = 1.570_796_326_794_896_6 - angle }
        if x < 0 { angle = 3.141_592_653_589_793 - angle }
        return y < 0 ? -angle : angle
    }

    func beginTouch(atFractionX fx: Double, fractionY fy: Double) {
        recordUndoPoint()
        strokeFromX = nil
        strokeFromY = nil
        placedSourceThisStroke = false
        updateTouch(atFractionX: fx, fractionY: fy)
    }

    func updateTouch(atFractionX fx: Double, fractionY fy: Double) {
        // Through the camera, so a tool lands where it was aimed. Without this, tilting or zooming
        // the view would leave the brush acting on a body somewhere else entirely — and a tool that
        // lands somewhere other than where it was pointed is worse than one that cannot be pointed.
        let place = camera.unproject(
            screenX: fx * engine.width,
            screenY: fy * engine.height,
            worldWidth: engine.width,
            worldHeight: engine.height,
            viewWidth: engine.width,
            viewHeight: engine.height
        )
        touchX = place.x
        touchY = place.y

        // The two drawing tools change the world rather than pushing the bodies, so they are handled here
        // and the force machinery is left switched off — otherwise drawing a wall would also drag every body
        // near the line along with it.
        if engine.mouseMode.drawsIntoTheWorld {
            touchActive = false
            continueStroke(toX: place.x, y: place.y)
            return
        }
        touchActive = true
    }

    /// Carries a drawn stroke on from wherever it was.
    ///
    /// A stroke needs two points — a direction to paint, or two ends for a wall — so the first touch of a
    /// drag only records where it started. That is why nothing happens until the finger moves, which is
    /// correct for these two and would be wrong for a force.
    private func continueStroke(toX x: Double, y: Double) {
        defer {
            strokeFromX = x
            strokeFromY = y
        }
        guard let fromX = strokeFromX, let fromY = strokeFromY else { return }
        let dx = x - fromX
        let dy = y - fromY
        // A minimum length, so a finger resting still does not paint the same square a hundred times a
        // second — which with a brush that moves toward what is asked for would saturate it instantly, and
        // for walls would fill the list with slivers.
        guard (dx * dx + dy * dy).squareRoot() > 6 else { return }

        switch engine.mouseMode {
        case .current:
            engine.paintCurrent(atX: x, y: y, directionX: dx, directionY: dy)
        case .wall:
            guard engine.width > 0, engine.height > 0 else { return }
            engine.addWall(
                fromFractionX: fromX / engine.width,
                y: fromY / engine.height,
                toFractionX: x / engine.width,
                y: y / engine.height
            )
        case .source:
            // One per drag, placed where the finger went down and pointing where it was dragged — so the
            // gesture that creates it is also the gesture that aims it.
            guard !placedSourceThisStroke else { return }
            placedSourceThisStroke = true
            engine.addEmitter(atX: fromX, y: fromY, direction: jsAtan2Approximate(dy, dx))
        default:
            break
        }
        engineDidChange()
    }

    func endTouch() {
        touchActive = false
        strokeFromX = nil
        strokeFromY = nil
    }

    // MARK: - What has been drawn

    /// How hard the painted wind pushes.
    var currentStrength: Double {
        get { observeEngine(); return engine.currentSettings.strength }
        set { engine.currentSettings.strength = newValue; engineDidChange() }
    }

    /// How wide a stroke of it is.
    var currentBrushRadius: Double {
        get { observeEngine(); return engine.currentSettings.brushRadius }
        set { engine.currentSettings.brushRadius = newValue; engineDidChange() }
    }

    /// How strongly one stroke paints.
    var currentBrushStrength: Double {
        get { observeEngine(); return engine.currentSettings.brushStrength }
        set { engine.currentSettings.brushStrength = newValue; engineDidChange() }
    }

    /// How finely the wind is painted.
    var currentResolution: Double {
        get { observeEngine(); return Double(engine.current.resolution) }
        set {
            var field = engine.current
            field.setResolution(Int(newValue.rounded()))
            engine.current = field
            engineDidChange()
        }
    }

    /// Whether any wind has been painted.
    var hasPaintedCurrent: Bool {
        observeEngine()
        return !engine.current.isEmpty
    }

    /// Wipes the painted wind.
    func clearCurrent() {
        recordUndoPoint()
        engine.clearCurrent()
        engineDidChange()
    }

    /// How bouncy the walls are.
    var wallBounciness: Double {
        get { observeEngine(); return engine.wallSettings.bounciness }
        set { engine.wallSettings.bounciness = newValue; engineDidChange() }
    }

    /// How much a wall slows something sliding along it.
    var wallFriction: Double {
        get { observeEngine(); return engine.wallSettings.friction }
        set { engine.wallSettings.friction = newValue; engineDidChange() }
    }

    /// How thick the walls are.
    var wallThickness: Double {
        get { observeEngine(); return engine.wallSettings.thickness }
        set { engine.wallSettings.thickness = newValue; engineDidChange() }
    }

    /// How many walls have been drawn.
    var wallCount: Int {
        observeEngine()
        return engine.walls.count
    }

    /// Removes every wall.
    func clearWalls() {
        recordUndoPoint()
        engine.clearWalls()
        engineDidChange()
    }

    // MARK: - The camera

    /// Where the field is being looked at from.
    ///
    /// Held on the model rather than in the engine: it changes nothing about the simulation, and the
    /// engine deliberately knows nothing about views or screens. It is saved with a scene, though, so
    /// a view somebody set up carefully comes back.
    private var storedCamera = ParticleCamera.identity

    /// How many pixels a point is, so a gesture measured in points can be applied in pixels.
    private var viewScale: Double = 2
    /// The view's own size in pixels, before any world growth.
    ///
    /// Kept because the world's size is now the view's size times however far out the camera is pulled, so
    /// the view's own size has to be remembered separately — otherwise growing the world once would make the
    /// next growth compound on top of it.
    private var viewPixelWidth: Double = 0
    private var viewPixelHeight: Double = 0

    var camera: ParticleCamera {
        get { observeEngine(); return storedCamera }
        set {
            let grew = newValue.worldScale != storedCamera.worldScale
            storedCamera = newValue
            if grew { matchWorldToCamera() }
            cameraDidChange()
        }
    }

    /// Resizes the world to match how far out the camera is pulled.
    ///
    /// This is what makes zooming out mean *more room* rather than a smaller picture. Pull back to a quarter
    /// and the world becomes four times as wide and four times as tall — sixteen times the space — with the
    /// bodies still drawn at their true size, so the screen stays full and the freed room is somewhere the
    /// crowd can actually go.
    ///
    /// Whatever is already in the field is shifted to stay in the middle, so the new space appears evenly
    /// all round the existing scene rather than the scene sitting in one corner of it.
    private func matchWorldToCamera() {
        guard viewPixelWidth > 0, viewPixelHeight > 0 else { return }
        let scale = storedCamera.worldScale
        engine.resizeKeepingContentsCentred(
            width: viewPixelWidth * scale,
            height: viewPixelHeight * scale
        )
    }

    /// Whether the view is anything other than looking straight down at the whole world.
    ///
    /// Read by the interface, so the button that puts it back can hide itself when there is nothing
    /// to put back.
    var cameraIsMoved: Bool {
        observeEngine()
        return !storedCamera.isIdentity
    }

    /// Moving the camera invalidates the faded picture left over from the previous frame.
    ///
    /// Without this, panning across the field drags a smear of every previous frame with it — the
    /// accumulated picture is in screen space, so when the view moves underneath it, what was a
    /// trail behind a body becomes a streak across the screen that has nothing to do with any body.
    private func cameraDidChange() {
        trailHistoryIsStale = true
        engineDidChange()
    }

    /// Set when the camera moves, cleared once the renderer has wiped the leftover picture.
    private(set) var trailHistoryIsStale = false

    func clearedTrailHistory() {
        trailHistoryIsStale = false
    }

    /// How long the field has been running, in seconds, for the backdrop's own movement.
    ///
    /// Counted here rather than read from a clock, so it starts at nought — see the note on the frame's
    /// own copy of it for why that matters.
    private var backdropSeconds: Double = 0

    /// When the backdrop was last moved on, in milliseconds.
    private var lastBackdropTime: Double?

    /// When the spin was last moved on, in milliseconds. Nothing means it has not started.
    private var lastSpinTime: Double?

    /// Moves the automatic spin on by however long has passed.
    ///
    /// By real elapsed time rather than a fixed step per frame, so the spin turns at the rate it says
    /// whether the field is running at thirty frames a second or a hundred and twenty. The camera
    /// itself clamps a long gap, so coming back from the background does not jump the view round.
    private func advanceCameraSpin(now: Double) {
        guard storedCamera.autoOrbit else {
            lastSpinTime = nil
            return
        }
        defer { lastSpinTime = now }
        guard let last = lastSpinTime, now > last else { return }
        var next = storedCamera
        next.advance(bySeconds: (now - last) / 1000)
        storedCamera = next
        // Deliberately not through `camera`, which would wipe the leftover picture every frame and
        // so destroy trails for as long as the spin was running. A spin is a continuous change; the
        // smear it leaves is the same smear a moving body leaves, which is the point of a trail.
        engineDidChange()
    }

    /// Zooms about the middle of the view, the way a pinch does.
    func zoomCamera(by factor: Double) {
        var next = storedCamera
        next.zoom(by: factor)
        camera = next
    }

    /// Shifts the view by a drag measured in points.
    func panCamera(byPointsX dx: Double, y dy: Double) {
        var next = storedCamera
        next.pan(byX: dx * viewScale, y: dy * viewScale)
        camera = next
    }

    /// Turns the view by a twist measured in radians, as a rotation gesture reports it.
    func rotateCamera(byRadians radians: Double) {
        var next = storedCamera
        next.rotate(byYaw: radians * 180 / .pi, pitch: 0)
        camera = next
    }

    /// How far the plane is tipped, in degrees.
    var cameraPitch: Double {
        get { observeEngine(); return storedCamera.pitch }
        set {
            var next = storedCamera
            next.pitch = ParticleCamera.clampPitch(newValue)
            camera = next
        }
    }

    /// Whether the view turns by itself.
    var cameraAutoOrbit: Bool {
        get { observeEngine(); return storedCamera.autoOrbit }
        set {
            var next = storedCamera
            next.autoOrbit = newValue
            camera = next
        }
    }

    /// Back to looking straight down at the whole world.
    func resetCamera() {
        var next = storedCamera
        next.reset()
        camera = next
    }

    /// Zooms and shifts the view so that everything in the field is on screen.
    ///
    /// This is the thing the reference implementation does not have: its "fill frame" never looks at
    /// where the bodies actually are. Here the extent is measured, ignoring the wildest few — one
    /// body flung out of a supernova must not frame the scene around itself — and the view is fitted
    /// around what is left.
    ///
    /// Both stores are measured. A scene can be a handful of object bodies, a swarm of a million, or
    /// both, and fitting to only one of them would put half the field off screen.
    func fitCameraToContent() {
        var frame = ParticleCamera.framing(
            positions: engine.swarm.positions,
            count: engine.swarm.count,
            worldWidth: engine.width,
            worldHeight: engine.height
        )

        if !engine.particles.isEmpty {
            var flat: [Float] = []
            flat.reserveCapacity(engine.particles.count * 2)
            for body in engine.particles {
                flat.append(Float(body.x))
                flat.append(Float(body.y))
            }
            let objects = flat.withUnsafeBufferPointer { buffer -> ParticleFraming in
                guard let base = buffer.baseAddress else { return frame }
                return ParticleCamera.framing(
                    positions: base,
                    count: engine.particles.count,
                    worldWidth: engine.width,
                    worldHeight: engine.height
                )
            }
            frame = Self.union(frame, objects)
        }

        guard !frame.isEmpty else { return }
        var next = storedCamera
        next.fit(
            to: frame,
            worldWidth: engine.width,
            worldHeight: engine.height,
            viewWidth: engine.width,
            viewHeight: engine.height
        )
        camera = next
    }

    /// The smallest box holding both, or whichever one is not empty.
    private static func union(_ left: ParticleFraming, _ right: ParticleFraming) -> ParticleFraming {
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return ParticleFraming(
            minX: min(left.minX, right.minX),
            minY: min(left.minY, right.minY),
            maxX: max(left.maxX, right.maxX),
            maxY: max(left.maxY, right.maxY),
            bodyCount: left.bodyCount + right.bodyCount
        )
    }

    // MARK: - Scenes

    /// The presets, in the order the interface shows them.
    static let presets: [(id: String, name: String)] = [
        ("galaxy", "Galaxy"), ("blackhole", "Black hole"), ("vortex", "Double vortex"),
        ("flare", "Solar flare"), ("synchrotron", "Synchrotron"), ("shockwave", "Shockwave"),
        ("fountain", "Cosmic fountain"), ("waterfall", "Waterfall"), ("pour", "Pour"),
        ("lattice", "Quantum lattice"), ("helix", "DNA helix"), ("flock", "Flock"),
        ("nbody", "N-body"), ("cloth", "Cloth"), ("rope", "Rope"), ("blob", "Blob"),
        ("burst", "Burst"), ("swarm", "Swarm"),
        // The twelve pattern scenes. Kept together and after the rest, because they are a different kind
        // of thing: the ones above are about a centre and a force, and these are about a shape.
        ("sunflower", "Sunflower"), ("mandala", "Mandala"), ("snowflakes", "Snowflakes"),
        ("tornado", "Tornado"), ("lightning", "Lightning"), ("aurora", "Aurora"),
        ("supernova", "Supernova"), ("sierpinski", "Sierpinski"), ("fireworks", "Fireworks"),
        ("magma", "Magma"), ("confetti", "Confetti"), ("molecules", "Molecules"),
        // The last four from the read. Fire and smoke are continuous rather than arrangements — what makes a
        // fire a fire is that it keeps burning — so they place a source as well, which is why they had to wait
        // for sources to exist.
        ("ring", "Ring"), ("water", "Water"), ("fire", "Fire"), ("smoke", "Smoke"),
    ]

    /// The limit on how many bodies the field will hold.
    ///
    /// Read-only through the engine, because lowering it has to trim what is already there — and the
    /// swarm as well as the objects, which the reference forgot.
    var maxBodies: Int {
        get { observeEngine(); return engine.maxParticles }
        set {
            engine.setMaxParticles(newValue)
            bodyCount = engine.bodyCount
            engineDidChange()
        }
    }

    /// The choices offered for the limit, as round numbers.
    static let bodyCapChoices = [50_000, 100_000, 250_000, 500_000, 1_000_000]

    /// The choices offered for how many to add at once.
    static let batchChoices = [1_000, 10_000, 50_000, 100_000, 500_000]

    /// Scatters more bodies into the field.
    ///
    /// Asks for no more than there is room for, so tapping it against the limit does nothing rather
    /// than quietly discarding most of what was asked for.
    func spawn(_ count: Int) {
        let room = max(0, engine.maxParticles - engine.bodyCount)
        guard room > 0 else { return }
        engine.spawnBatch(count: min(count, room))
        bodyCount = engine.bodyCount
    }

    /// How much room is left before the limit.
    var remainingRoom: Int {
        observeEngine()
        return max(0, engine.maxParticles - engine.bodyCount)
    }

    func loadPreset(_ id: String) {
        // Every preset but the burst clears the field first, and clearing already records an
        // undo point — so one is only needed for the two that do not.
        if id == "burst" { recordUndoPoint() }
        let count = engine.width < 500 ? 220 : 380
        switch id {
        case "galaxy": engine.spawnGalaxy(count: count)
        case "blackhole": engine.spawnBlackHole(count: count)
        case "vortex": engine.spawnDoubleVortex(count: count)
        case "flare": engine.spawnSolarFlare(count: count)
        case "synchrotron": engine.spawnSynchrotron(count: count)
        case "shockwave": engine.spawnShockwave(count: count)
        case "fountain": engine.spawnCosmicFountain(count: count)
        case "waterfall": engine.spawnWaterfall(count: count)
        case "pour": engine.spawnPour(count: count)
        case "lattice": engine.spawnQuantumLattice()
        case "helix": engine.spawnDnaHelix()
        case "flock": engine.spawnFlock()
        case "nbody": engine.spawnNbody()
        case "cloth": engine.spawnCloth()
        case "rope": engine.spawnRope()
        case "blob": engine.spawnBlob()
        case "burst": engine.spawnBurst(count: count)
        case "swarm":
            engine.clear()
            engine.spawnBatch(count: 120_000)

        // The pattern scenes. These are crowds rather than a handful of bodies — a sunflower is its
        // seeds and a mandala is its petals, and a few hundred of either would be a sketch of one. So
        // they clear the field and ask for thousands, and they place into the swarm where thousands are
        // affordable.
        case "sunflower": engine.clear(); engine.spawnSunflower()
        case "mandala": engine.clear(); engine.spawnMandala()
        case "snowflakes": engine.clear(); engine.spawnSnowflakes()
        case "tornado": engine.clear(); engine.spawnTornado()
        case "lightning": engine.clear(); engine.spawnLightning()
        case "aurora": engine.clear(); engine.spawnAurora()
        case "supernova": engine.clear(); engine.spawnSupernova()
        case "sierpinski": engine.clear(); engine.spawnSierpinski()
        case "fireworks": engine.clear(); engine.spawnFireworks()
        case "magma": engine.clear(); engine.spawnMagma()
        case "confetti": engine.clear(); engine.spawnConfetti()
        case "molecules": engine.clear(); engine.spawnMolecules()
        case "ring": engine.clear(); engine.spawnRing()
        case "water": engine.clear(); engine.spawnWaterPool()
        case "fire": engine.clear(); engine.spawnFire()
        case "smoke": engine.clear(); engine.spawnSmoke()
        default: break
        }
        bodyCount = engine.bodyCount
    }

    func clear() {
        recordUndoPoint()
        engine.clear()
        bodyCount = 0
    }

    func undo() {
        _ = engine.undo()
        bodyCount = engine.bodyCount
    }

    func redo() {
        _ = engine.redo()
        bodyCount = engine.bodyCount
    }

    /// How fast the quickest body is travelling.
    ///
    /// Worth watching: a field that has gone unstable shows up here long before it looks wrong, as one
    /// body accelerating away while everything else carries on normally.
    private var fastestBody: Double {
        var fastest = 0.0
        for body in engine.particles {
            let speed = body.velocityX * body.velocityX + body.velocityY * body.velocityY
            if speed.isFinite { fastest = max(fastest, speed) }
        }
        return fastest.squareRoot()
    }

    /// Brings the readout back in step after something outside the tick changed the field.
    func refreshCounts() {
        bodyCount = engine.bodyCount
    }

    /// Records a point to come back to, for the chamber bridge.
    ///
    /// The private one is for this model's own actions; this is the same thing spelled out for the one
    /// outside caller that legitimately needs it, rather than opening the private one to everybody.
    func recordUndoPointForBridge() {
        recordUndoPoint()
    }

    private func recordUndoPoint() {
        engine.pushUndo()
    }

    // MARK: - Size

    func resize(toViewSize size: CGSize, scale: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        // Kept so that a drag measured in points can be turned into the pixels the camera works in.
        if scale > 0 { viewScale = Double(scale) }
        // Full resolution, unlike the powder grid. The cost here is per body rather than per
        // cell, so a larger world is not a slower one — it is simply more room.
        viewPixelWidth = Double(size.width * scale)
        viewPixelHeight = Double(size.height * scale)
        // Through the camera, because the world is the view's size times however far out it is pulled. A
        // plain resize here would silently undo the extra room the moment the phone was turned.
        let worldScale = storedCamera.worldScale
        engine.resize(width: viewPixelWidth * worldScale, height: viewPixelHeight * worldScale)
    }
}
