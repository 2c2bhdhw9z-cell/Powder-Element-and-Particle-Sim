import CrucibleCore
import Foundation

/// The slingshot's aim, the jelly pen's outline, recorded loops, the drum's note, and the herd.
///
/// Everything that decides anything — where a throw goes, what an outline becomes, what a loop does — is in the
/// engine and tested there. This is the part that shows it and the buttons that ask for it.
extension ParticleFieldModel {
    // MARK: - What the finger is doing, drawn

    /// One line to draw over the field, in the world's pixels.
    struct AimSegment {
        var fromX: Double
        var fromY: Double
        var toX: Double
        var toY: Double
        var colour: UInt32
    }

    /// The throw being aimed — the band pulled back and the dotted path the body will take — and the outline being
    /// drawn with the jelly pen.
    func aimingSegments() -> [AimSegment] {
        var segments: [AimSegment] = []
        if engine.mouseMode == .slingshot, let anchor = slingAnchor, let pull = slingPull {
            let band = PackedColor(r: 0xFD, g: 0xE6, b: 0x8A, a: 0xE0).packedRGBA
            segments.append(AimSegment(fromX: anchor.x, fromY: anchor.y, toX: pull.x, toY: pull.y, colour: band))
            let speed = ParticleEngine.slingshotVelocity(anchorX: anchor.x, anchorY: anchor.y, pullX: pull.x, pullY: pull.y)
            let path = engine.predictedPath(fromX: anchor.x, y: anchor.y, velocityX: speed.x, velocityY: speed.y)
            // Every other moment drawn and every other left out, which is what makes it read as dots — a promise
            // of where it will go rather than a line somebody drew.
            let dots = PackedColor(r: 0xFF, g: 0xFF, b: 0xFF, a: 0x9C).packedRGBA
            var index = 1
            while index < path.count {
                segments.append(AimSegment(
                    fromX: path[index - 1].x, fromY: path[index - 1].y,
                    toX: path[index].x, toY: path[index].y,
                    colour: dots
                ))
                index += 3
            }
        }
        let outline = engine.jellyOutline
        if engine.mouseMode == .jelly, outline.count > 1 {
            let pen = PackedColor(r: 0x86, g: 0xEF, b: 0xAC, a: 0xD9).packedRGBA
            for index in 1 ..< outline.count {
                segments.append(AimSegment(
                    fromX: outline[index - 1].x, fromY: outline[index - 1].y,
                    toX: outline[index].x, toY: outline[index].y,
                    colour: pen
                ))
            }
            // And faintly, the line that will close it, so it is clear the shape will be joined up.
            let closing = PackedColor(r: 0x86, g: 0xEF, b: 0xAC, a: 0x55).packedRGBA
            if let first = outline.first, let last = outline.last {
                segments.append(AimSegment(fromX: last.x, fromY: last.y, toX: first.x, toY: first.y, colour: closing))
            }
        }
        return segments
    }

    // MARK: - Loops

    /// Whether the next finger movement will be recorded.
    var isRecordingLoop: Bool {
        observeEngine()
        return engine.isRecordingLoop
    }

    /// How many recorded movements are playing.
    var loopCount: Int {
        observeEngine()
        return engine.forceLoops.count
    }

    /// Whether the chosen tool is one a loop can be made of.
    var toolCanLoop: Bool {
        observeEngine()
        return ParticleBrush.touchesBodies(engine.mouseMode) && !usesLens && !(engine.depthEnabled && turnsView)
    }

    /// Records the next finger movement, or stops waiting for one.
    func toggleLoopRecording() {
        if engine.isRecordingLoop {
            engine.cancelLoopRecording()
        } else {
            _ = engine.beginLoopRecording()
        }
        engineDidChange()
    }

    /// Stops the loop made most recently.
    func removeLastLoop() {
        engine.removeLastForceLoop()
        engineDidChange()
    }

    /// Stops every loop.
    func clearLoops() {
        engine.clearForceLoops()
        engineDidChange()
    }

    // MARK: - The drum

    /// Whether the field is a ringing plate.
    var isDrum: Bool {
        observeEngine()
        return engine.drumEnabled
    }

    /// The note the plate is ringing in, as the pattern's two numbers.
    var drumNoteName: String {
        observeEngine()
        let pair = ParticleEngine.drumNotes[engine.drumNote]
        return "\(pair.m) and \(pair.n)"
    }

    /// Moves the plate on to its next note.
    func nextDrumNote() {
        engine.drumNote += 1
        engineDidChange()
    }

    // MARK: - The herd

    /// Whether the field is foxes and rabbits.
    var isHerd: Bool {
        observeEngine()
        return engine.predatorsEnabled
    }
}
