import CrucibleCore
import Metal
import MetalKit
import UIKit
import simd

/// Draws the particle field.
///
/// Unlike the powder grid, which arrives as a finished picture, this is drawn as geometry — a
/// point per body and a line per spring — which is what lets the field hold a million bodies
/// without anything on the processor touching a pixel.
///
/// Three passes per frame: the swarm first, then the springs, then the object bodies on top, so
/// that a cloth's structure sits behind its nodes and the handful of individually interesting
/// bodies are never buried under the crowd.
@MainActor
final class FieldView: MTKView {
    /// Matches the layout the shader declares, field for field and in the same order.
    ///
    /// The two-component values come first, in pairs, because they want eight-byte alignment — put
    /// after the plain floats they would leave a hole whose size both sides have to agree about, and
    /// a disagreement there does not fail to compile. It reads the wrong fields and draws the field
    /// somewhere unexpected.
    private struct Uniforms {
        var worldSize: SIMD2<Float>
        var viewSize: SIMD2<Float>
        var pan: SIMD2<Float>
        /// Turn and tip, in radians.
        var orbit: SIMD2<Float>
        var pointSize: Float
        var zoom: Float
        /// Which silhouette. `ParticleShape.shaderIdentifier`.
        var shape: Int32
        /// Nothing, and here on purpose — see the note in the shader. Without it the struct ends on a
        /// four-byte boundary and each language pads the tail on its own; they agree today and neither
        /// is required to, and a disagreement about padding does not fail to compile.
        var reserved: Int32 = 0
    }

    /// Mirrors `DepthUniforms` in the shader, field for field and in the same order.
    ///
    /// The two four-component values first, since they want sixteen-byte alignment, and then four plain floats
    /// that fill the last sixteen bytes exactly — so there is no padding anywhere for the two sides to disagree
    /// about.
    private struct DepthUniforms {
        /// The cosine and sine of the turn round the box, then of the tip above it.
        var turn: SIMD4<Float>
        /// How much the far side fades, in the first. The rest is spare.
        var fog: SIMD4<Float>
        var worldDepth: Float
        /// Nought is no perspective.
        var eyeDistance: Float
        var radius: Float
        var nearLimit: Float
    }

    /// Everything drawing in 3D needs besides what the flat drawing has.
    ///
    /// Made alongside the flat drawing but kept apart from it, and allowed to be missing: if any of it could not
    /// be made, a field in 3D is drawn flat rather than the whole field failing to appear.
    private struct DepthDrawing {
        /// The crowd at one size: solid, and glowing.
        var points: MTLRenderPipelineState
        var pointsGlowing: MTLRenderPipelineState
        /// Bodies each at their own size.
        var bodies: MTLRenderPipelineState
        var bodiesGlowing: MTLRenderPipelineState
        /// Trails, streaks, the box and whatever has been drawn into it.
        var lines: MTLRenderPipelineState
        var linesGlowing: MTLRenderPipelineState
        var springs: MTLRenderPipelineState
        /// The ring and the fade, which do not move with the box but have to be drawn in the same pass as it.
        var ring: MTLRenderPipelineState
        var fade: MTLRenderPipelineState
        /// Nearer hides further, and this writes how far away it is so it can hide what comes after.
        var hidesWhatIsBehind: MTLDepthStencilState
        /// Hidden by what is nearer, but hides nothing itself — for lines, which are too thin to hide anything
        /// sensibly and would otherwise cut hairline gaps through bodies drawn after them.
        var isHiddenByWhatIsNearer: MTLDepthStencilState
        /// Neither: for glowing, and for the ring and the fade.
        var ignoresDepth: MTLDepthStencilState
    }

    /// Mirrors `RingUniforms` in the shader, field for field and in the same order.
    ///
    /// The colour is first because it needs sixteen-byte alignment: anywhere else and there is a
    /// hole in the struct whose size both sides have to agree about. Getting that wrong does not
    /// fail to compile — it reads the wrong fields and draws a ring somewhere unexpected.
    /// Mirrors `FadeUniforms` in the shader. One four-component colour, so there is no padding to
    /// disagree about.
    private struct FadeUniforms {
        var color: SIMD4<Float>
    }

    /// Mirrors `BackgroundUniforms` in the shader.
    private struct BackgroundUniforms {
        var kind: Int32
        /// Nothing, and here on purpose — see the note on `Uniforms`.
        var reserved: Int32 = 0
        var time: Float
        var strength: Float
    }

    /// Mirrors `GlowUniforms` in the shader. The two-component value comes first for its alignment.
    private struct GlowUniforms {
        var step: SIMD2<Float>
        var threshold: Float
        var strength: Float
    }

    private struct RingUniforms {
        var color: SIMD4<Float>
        var centre: SIMD2<Float>
        var radius: Float
        var strokeWidth: Float
        var centreDotRadius: Float
        var strokeOpacity: Float
        var fillOpacity: Float
    }

    private let model: ParticleFieldModel
    private let commandQueue: MTLCommandQueue
    private let pointPipeline: MTLRenderPipelineState
    /// The object bodies, each at its own size. See `bodyVertex` in the shader.
    private let bodyPipeline: MTLRenderPipelineState
    private let springPipeline: MTLRenderPipelineState
    private let trailPipeline: MTLRenderPipelineState
    private let ringPipeline: MTLRenderPipelineState
    private let fadePipeline: MTLRenderPipelineState
    private let backgroundPipeline: MTLRenderPipelineState
    private let glowBrightPipeline: MTLRenderPipelineState
    private let glowBlurPipeline: MTLRenderPipelineState
    private let fieldOverPipeline: MTLRenderPipelineState
    private let glowAddPipeline: MTLRenderPipelineState
    private let smoothSampler: MTLSamplerState
    /// Drawing in 3D, or nothing if it could not be set up — see `DepthDrawing`.
    private let depthDrawing: DepthDrawing?

    /// How far away whatever has been drawn at each pixel is, for the solid drawing in 3D.
    ///
    /// Only for the frame being drawn: it is cleared at the start of each and thrown away at the end, so on
    /// the phone it never leaves the graphics card's own fast memory at all. Made the first time a field in 3D
    /// is drawn, and never for a flat one.
    private var depthTexture: MTLTexture?
    private var depthTextureWidth = 0
    private var depthTextureHeight = 0

    /// The two small pictures the glow is built in.
    ///
    /// Half the width and height of the screen. A glow is a blurred thing, and blurring something that
    /// has already been shrunk costs a quarter as much for a result nobody can tell apart — the
    /// reference implementation blurs at full size, which is where most of its cost goes.
    ///
    /// Two of them because a blur is done in two passes, sideways then downward, and a pass cannot read
    /// and write the same picture.
    private var glowA: MTLTexture?
    private var glowB: MTLTexture?
    private var glowWidth = 0
    private var glowHeight = 0

    /// The picture that survives between frames.
    ///
    /// A screen's drawable cannot be used for this: the system hands out a different one each frame,
    /// so whatever was drawn last time is simply not there. Keeping the field's own texture is what
    /// lets the previous frame be dimmed rather than erased — which is the whole mechanism behind
    /// trails looking like motion rather than like six dots.
    private var accumulation: MTLTexture?
    private var accumulationWidth = 0
    private var accumulationHeight = 0

    // Held across frames and grown only when the field outgrows them, so a steady field
    // allocates nothing. At a million bodies these are megabytes; rebuilding them sixty times a
    // second would cost more than the simulation.
    private var positions: [Float] = []
    private var colors: [UInt32] = []
    /// How wide each object body is drawn, in pixels of the screen.
    private var sizes: [Float] = []
    private var springPositions: [Float] = []
    private var swarmPositions: [Float] = []
    private var swarmColors: [UInt32] = []
    /// How wide each body of the crowd is drawn, when any of them has a size of its own.
    private var swarmSizes: [Float] = []
    private var trailPositions: [Float] = []
    private var trailColors: [UInt32] = []
    /// The walls and the painted wind, as lines.
    private var guidePositions: [Float] = []
    private var guideColors: [UInt32] = []
    /// How far into the box everything is, filled only while the field is in 3D.
    private var depthBuffers = ParticleFieldModel.DepthBuffers()

    /// One frame's GPU-side copies. Reallocated only when they are too small.
    private struct FrameBuffers {
        var position: MTLBuffer?
        var color: MTLBuffer?
        var size: MTLBuffer?
        var spring: MTLBuffer?
        var swarmPosition: MTLBuffer?
        var swarmColor: MTLBuffer?
        var swarmSize: MTLBuffer?
        var trailPosition: MTLBuffer?
        var trailColor: MTLBuffer?
        var guidePosition: MTLBuffer?
        var guideColor: MTLBuffer?
        /// How far into the box, in 3D. Never made for a flat field.
        var bodyDepth: MTLBuffer?
        var swarmDepth: MTLBuffer?
        var springDepth: MTLBuffer?
        var trailDepth: MTLBuffer?
        var guideDepth: MTLBuffer?
    }

    /// How many frames may be on their way to the screen at once.
    ///
    /// ## Why there are three sets of buffers
    ///
    /// There used to be one. The graphics card draws a frame some time after it is handed over, and up to
    /// three can be queued — so the next frame's positions were being written into the very buffer the card
    /// was still reading the last frame from. On fast motion that drew bodies from a mixture of two moments:
    /// a faint sparkle and tearing that looked like the renderer being unreliable. Each frame now writes into
    /// its own set, and waits only if all three are still in use.
    private static let framesInFlight = 3
    private var frameBuffers = [FrameBuffers](repeating: FrameBuffers(), count: FieldView.framesInFlight)
    private var frameSlot = 0
    private let inFlight = DispatchSemaphore(value: FieldView.framesInFlight)

    /// The most recent frame, so a photograph can be composed from exactly what was on screen.
    private var lastFrame: ParticleFieldModel.Frame?

    init?(model: ParticleFieldModel) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let pointVertex = library.makeFunction(name: "particleVertex"),
              let bodyVertex = library.makeFunction(name: "bodyVertex"),
              let pointFragment = library.makeFunction(name: "particleFragment"),
              let springVertex = library.makeFunction(name: "springVertex"),
              let springFragment = library.makeFunction(name: "springFragment"),
              let trailVertex = library.makeFunction(name: "trailVertex"),
              let trailFragment = library.makeFunction(name: "trailFragment"),
              let ringVertex = library.makeFunction(name: "ringVertex"),
              let ringFragment = library.makeFunction(name: "ringFragment"),
              let fadeFragment = library.makeFunction(name: "fadeFragment"),
              let backgroundFragment = library.makeFunction(name: "backgroundFragment"),
              let glowBrightFragment = library.makeFunction(name: "glowBrightFragment"),
              let glowBlurFragment = library.makeFunction(name: "glowBlurFragment"),
              let fieldOverFragment = library.makeFunction(name: "fieldOverFragment"),
              let glowAddFragment = library.makeFunction(name: "glowAddFragment"),
              let sampler = device.makeSamplerState(descriptor: {
                  let descriptor = MTLSamplerDescriptor()
                  // Smoothed, which is what turns nine samples of a shrunken picture into a continuous
                  // blur rather than a grid of squares.
                  descriptor.minFilter = .linear
                  descriptor.magFilter = .linear
                  // Clamped, so sampling past the edge of the glow picture repeats the edge rather than
                  // wrapping round and putting a bright thing on one side into the other.
                  descriptor.sAddressMode = .clampToEdge
                  descriptor.tAddressMode = .clampToEdge
                  return descriptor
              }())
        else { return nil }

        /// How a pass combines what it draws with what is already there.
        enum Blending {
            /// Overlapping bodies build up rather than the last one drawn winning, and a spring can be a
            /// hairline rather than a hard white stripe.
            case over
            /// The colour is already multiplied by its opacity, so there is nothing to multiply again.
            case premultipliedOver
            /// Only ever brightens.
            case adding
            /// Replaces outright.
            case replace
            /// Scales what is there down, colour and coverage alike, and adds nothing.
            ///
            /// For fading the kept picture behind the trails. It used to use the ordinary blend, which fades
            /// the colours correctly but drives the coverage of every pixel on screen up toward the fade
            /// amount — so with trails on the stars, gradient or nebula behind the field dimmed to three
            /// quarters, and with the longest trails vanished entirely, behind a picture that had become an
            /// opaque sheet of black.
            case fade
            /// Adds light, for bodies glowing in 3D: where two overlap, the pixel is brighter than either.
            ///
            /// The colour is added weighted by its own opacity, and the coverage builds up the way it does for
            /// `over`, so the kept picture still holds colours already multiplied by their opacity — which is
            /// what laying it over the background expects.
            case glowing
        }

        func pipeline(
            _ vertex: MTLFunction,
            _ fragment: MTLFunction,
            blending: Blending = .over,
            inDepth: Bool = false
        ) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            // Every drawing in a pass has to agree with the pass about whether there is a record of how far away
            // things are, so the 3D pass has its own copy of everything drawn in it — the ring and the fade too.
            if inDepth { descriptor.depthAttachmentPixelFormat = .depth32Float }
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = blending != .replace
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            switch blending {
            case .over:
                attachment.sourceRGBBlendFactor = .sourceAlpha
                // One, not the source's opacity. The kept picture is later laid over the background as
                // already-multiplied colour, and for that its coverage has to be the plain sum of what was
                // drawn; multiplying by the opacity again stored it squared, so the background showed through
                // every half-transparent body far too strongly.
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            case .premultipliedOver:
                attachment.sourceRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            case .adding:
                attachment.sourceRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationRGBBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .one
            case .fade:
                attachment.sourceRGBBlendFactor = .zero
                attachment.sourceAlphaBlendFactor = .zero
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            case .glowing:
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationRGBBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            case .replace:
                break
            }
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        /// How a drawing in 3D treats the record of how far away things are.
        func depthState(compare: MTLCompareFunction, writes: Bool) -> MTLDepthStencilState? {
            let descriptor = MTLDepthStencilDescriptor()
            descriptor.depthCompareFunction = compare
            descriptor.isDepthWriteEnabled = writes
            return device.makeDepthStencilState(descriptor: descriptor)
        }

        /// The 3D drawing, all of it or nothing.
        func makeDepthDrawing() -> DepthDrawing? {
            guard let pointInDepth = library.makeFunction(name: "particleVertexInDepth"),
                  let bodyInDepth = library.makeFunction(name: "bodyVertexInDepth"),
                  let lineInDepth = library.makeFunction(name: "lineVertexInDepth"),
                  let springInDepth = library.makeFunction(name: "springVertexInDepth"),
                  let solidFragment = library.makeFunction(name: "solidParticleFragment"),
                  let points = pipeline(pointInDepth, solidFragment, inDepth: true),
                  let pointsGlowing = pipeline(pointInDepth, pointFragment, blending: .glowing, inDepth: true),
                  let bodies = pipeline(bodyInDepth, solidFragment, inDepth: true),
                  let bodiesGlowing = pipeline(bodyInDepth, pointFragment, blending: .glowing, inDepth: true),
                  let lines = pipeline(lineInDepth, trailFragment, inDepth: true),
                  let linesGlowing = pipeline(lineInDepth, trailFragment, blending: .glowing, inDepth: true),
                  let springs = pipeline(springInDepth, trailFragment, inDepth: true),
                  let ring = pipeline(ringVertex, ringFragment, inDepth: true),
                  let fade = pipeline(ringVertex, fadeFragment, blending: .fade, inDepth: true),
                  // Less than or equal rather than less, so two things at exactly the same depth — a body and the
                  // end of its own trail — are both drawn rather than whichever came first winning.
                  let hides = depthState(compare: .lessEqual, writes: true),
                  let hidden = depthState(compare: .lessEqual, writes: false),
                  let ignores = depthState(compare: .always, writes: false)
            else { return nil }
            return DepthDrawing(
                points: points,
                pointsGlowing: pointsGlowing,
                bodies: bodies,
                bodiesGlowing: bodiesGlowing,
                lines: lines,
                linesGlowing: linesGlowing,
                springs: springs,
                ring: ring,
                fade: fade,
                hidesWhatIsBehind: hides,
                isHiddenByWhatIsNearer: hidden,
                ignoresDepth: ignores
            )
        }

        guard let points = pipeline(pointVertex, pointFragment),
              let bodies = pipeline(bodyVertex, pointFragment),
              let springs = pipeline(springVertex, springFragment),
              let trails = pipeline(trailVertex, trailFragment),
              let ring = pipeline(ringVertex, ringFragment),
              // The fade reuses the ring's vertex function, which already covers the screen from the
              // vertex number alone and needs no geometry of its own.
              let fade = pipeline(ringVertex, fadeFragment, blending: .fade),
              // The background replaces whatever is under it, being the bottom layer.
              let background = pipeline(ringVertex, backgroundFragment, blending: .replace),
              let glowBright = pipeline(ringVertex, glowBrightFragment, blending: .replace),
              let glowBlur = pipeline(ringVertex, glowBlurFragment, blending: .replace),
              // The field's colours are already multiplied by their opacity, so laying it over the
              // background keeps all of the field and however much of the background still shows
              // through.
              let fieldOver = pipeline(ringVertex, fieldOverFragment, blending: .premultipliedOver),
              // And the glow only ever brightens.
              let glowAdd = pipeline(ringVertex, glowAddFragment, blending: .adding)
        else { return nil }

        self.model = model
        self.commandQueue = queue
        self.pointPipeline = points
        self.bodyPipeline = bodies
        self.springPipeline = springs
        self.trailPipeline = trails
        self.ringPipeline = ring
        self.fadePipeline = fade
        self.backgroundPipeline = background
        self.glowBrightPipeline = glowBright
        self.glowBlurPipeline = glowBlur
        self.fieldOverPipeline = fieldOver
        self.glowAddPipeline = glowAdd
        self.smoothSampler = sampler
        self.depthDrawing = makeDepthDrawing()
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        // Framebuffer-only, which lets the driver keep the drawable in its most efficient arrangement
        // and compress it losslessly on the way to the screen.
        //
        // This was off, with a note saying the finished picture is copied into the drawable and a
        // framebuffer-only drawable cannot be copied into. That was true once and is not now: the
        // drawable is only ever a render pass's colour attachment (see `encodeFinalPicture`), which is
        // exactly what framebuffer-only permits. The one copy left in this file reads the field's own
        // texture for a photograph, never the screen's. So the flag was paying for a copy nobody makes.
        framebufferOnly = true
        isOpaque = true
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        enableSetNeedsDisplay = false
        isPaused = false
        preferredFramesPerSecond = 120
        // The drawable's size is set by hand at the top of every frame, because the detail setting decides it
        // and the system's own answer is always "every pixel the screen has". Worked out from the bounds each
        // frame, so turning the phone is handled by the same line that handles the setting.
        autoResizeDrawable = false
        // The lab's own near-black, so the field sits in the same room as the powder grid.
        clearColor = MTLClearColor(red: 10 / 255, green: 10 / 255, blue: 12 / 255, alpha: 1)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("Crucible's field view is created in code, never from a storyboard.")
    }

    override func draw(_ rect: CGRect) {
        // How many pixels to draw for each point on screen. Set outright rather than by adjusting the view's
        // scale factor and letting the system work it out: this is the whole of the detail setting, and a
        // number written here is one that can be read back and checked.
        //
        // Everything else about the setting follows from the drawable being smaller — the glow's two pictures
        // and the trail picture that is kept between frames are all measured from it, and they are where the
        // per-pixel cost is. The system scales the finished picture back up to fill the view.
        let wantedScale = model.drawableScale > 0 ? model.drawableScale : Double(contentScaleFactor)
        let wantedSize = CGSize(
            width: (bounds.width * CGFloat(wantedScale)).rounded(),
            height: (bounds.height * CGFloat(wantedScale)).rounded()
        )
        if wantedSize.width >= 1, wantedSize.height >= 1, drawableSize != wantedSize {
            drawableSize = wantedSize
        }

        // The frame's own timestamp, handed to the simulation so that anything which reads the
        // clock — the painting tool picks its colour from it — is reproducible.
        model.tick(now: CFAbsoluteTimeGetCurrent() * 1000)

        guard let drawable = currentDrawable,
              let buffer = commandQueue.makeCommandBuffer(),
              let device
        else { return }

        let width = drawable.texture.width
        let height = drawable.texture.height
        guard let target = accumulationTexture(width: width, height: height, device: device) else {
            return
        }

        // Waits only if all three sets of buffers are still being drawn from, and gives this set back the
        // moment the card has finished with it.
        inFlight.wait()
        frameSlot = (frameSlot + 1) % Self.framesInFlight
        let released = inFlight
        buffer.addCompletedHandler { _ in released.signal() }

        var frame = prepare(device: device)
        // Measured from the drawable that actually arrived rather than from the setting, so the frame or two
        // after a change — while the old drawable is still being handed out — draws bodies the right size
        // instead of briefly doubling them.
        if frame.viewWidth > 0 {
            frame.pixelRatio = max(0.2, min(1, Double(width) / frame.viewWidth))
        }

        // Moving the camera invalidates whatever is left over from the previous frame. The kept
        // picture is in screen space, so when the view slides underneath it, what was a trail behind
        // a body becomes a streak across the screen belonging to nothing — and because each frame is
        // only dimmed, the streak stays there. Wiped once, and the model is told so it stops asking.
        let cameraMoved = model.trailHistoryIsStale
        if cameraMoved { model.clearedTrailHistory() }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].storeAction = .store
        if model.showTrails, !cameraMoved {
            // Kept, so the previous frame can be dimmed rather than erased. That dimming is what
            // makes a trail longer than the handful of positions a body remembers.
            pass.colorAttachments[0].loadAction = .load
        } else {
            // Wiped outright, which is both what the reference does with trails off and cheaper
            // than drawing a fully opaque rectangle over it. Wiped to *nothing*, not to black — see
            // `clearAccumulation`.
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        }

        // In 3D, drawn with a record of how far away whatever is at each pixel is, so the near side of the box
        // hides the far side. Should that not be possible the field is drawn flat — seen straight on — rather
        // than not drawn at all.
        var inDepth: (view: ParticleFieldModel.DepthView, drawing: DepthDrawing)?
        if let view = frame.depth, let drawing = depthDrawing,
           let record = depthRecord(width: width, height: height, device: device) {
            pass.depthAttachment.texture = record
            // Everything starts as far away as anything can be...
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1
            // ...and none of it is wanted once the frame is drawn.
            pass.depthAttachment.storeAction = .dontCare
            inDepth = (view, drawing)
        }

        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            // Committed even so, so the completion handler gives the buffers back.
            buffer.present(drawable)
            buffer.commit()
            return
        }

        if model.showTrails, !cameraMoved {
            encodeFade(frame, into: encoder, drawing: inDepth?.drawing)
        }
        if let inDepth {
            encodeInDepth(frame, view: inDepth.view, drawing: inDepth.drawing, into: encoder)
        } else {
            encode(frame, into: encoder)
        }
        encoder.endEncoding()

        // The glow, built from the field before anything is laid over it.
        let glow = model.glowStrength > 0
            ? encodeGlow(frame, from: target, in: buffer, device: device)
            : nil

        // And the finished picture: the background at the bottom, the field over it, the glow on top.
        //
        // Three full-screen draws rather than the single copy this used to be. The copy was enough when
        // the field was the whole picture; it cannot layer anything, and a background copied over would
        // hide the field rather than sit behind it.
        encodeFinalPicture(frame, field: target, glow: glow, to: drawable.texture, in: buffer)
        lastFrame = frame

        buffer.present(drawable)
        buffer.commit()
    }

    /// Builds the glow: pick out what is bright, blur it sideways, blur it downward.
    ///
    /// Returns the picture holding the result, or nothing if it could not be made — in which case the
    /// field is simply drawn without a glow, which is a reasonable thing for it to look like.
    private func encodeGlow(
        _ frame: ParticleFieldModel.Frame,
        from field: MTLTexture,
        in buffer: MTLCommandBuffer,
        device: MTLDevice
    ) -> MTLTexture? {
        // Half the width and height. A glow is blurred, so blurring it small costs a quarter as much for
        // a result nobody can tell apart.
        let width = max(1, field.width / 2)
        let height = max(1, field.height / 2)
        guard let first = glowTexture(&glowA, width: width, height: height, device: device),
              let second = glowTexture(&glowB, width: width, height: height, device: device)
        else { return nil }
        glowWidth = width
        glowHeight = height

        var uniforms = Self.uniforms(for: frame)
        // The passes read from a picture at half size, so what they think the view measures has to be
        // that picture rather than the screen — otherwise every sample lands in the wrong quarter of it.
        uniforms.viewSize = SIMD2<Float>(Float(width), Float(height))

        func pass(
            _ pipeline: MTLRenderPipelineState,
            from source: MTLTexture,
            to destination: MTLTexture,
            glow: GlowUniforms
        ) {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = destination
            descriptor.colorAttachments[0].loadAction = .dontCare
            descriptor.colorAttachments[0].storeAction = .store
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            var local = uniforms
            var settings = glow
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&local, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.setFragmentBytes(&local, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.setFragmentBytes(&settings, length: MemoryLayout<GlowUniforms>.stride, index: 0)
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentSamplerState(smoothSampler, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        // How far apart the samples sit. Measured in fractions of the picture, and scaled by the spread
        // setting rather than by the brightness — the reference implementation ties the two together, so
        // asking for a brighter glow there gives a wider one and turning it up reads as haze.
        let spread = Float(model.glowSpread)
        let acrossStep = SIMD2<Float>(spread / Float(width), 0)
        let downStep = SIMD2<Float>(0, spread / Float(height))
        let threshold = Float(model.glowThreshold)

        pass(
            glowBrightPipeline,
            from: field,
            to: first,
            glow: GlowUniforms(step: .zero, threshold: threshold, strength: 0)
        )
        pass(
            glowBlurPipeline,
            from: first,
            to: second,
            glow: GlowUniforms(step: acrossStep, threshold: threshold, strength: 0)
        )
        pass(
            glowBlurPipeline,
            from: second,
            to: first,
            glow: GlowUniforms(step: downStep, threshold: threshold, strength: 0)
        )
        return first
    }

    /// Draws the background, the field and the glow into the screen's own picture.
    private func encodeFinalPicture(
        _ frame: ParticleFieldModel.Frame,
        field: MTLTexture,
        glow: MTLTexture?,
        to destination: MTLTexture,
        in buffer: MTLCommandBuffer
    ) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = destination
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = clearColor
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        var uniforms = Self.uniforms(for: frame)

        // The background, when there is one. Straight onto the room's own black, which is what stays if
        // there is not.
        if frame.background != .none {
            var settings = BackgroundUniforms(
                kind: frame.background.shaderIdentifier,
                time: Float(frame.backgroundTime),
                strength: Float(frame.backgroundStrength)
            )
            encoder.setRenderPipelineState(backgroundPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.setFragmentBytes(
                &settings,
                length: MemoryLayout<BackgroundUniforms>.stride,
                index: 0
            )
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // The field over it.
        encoder.setRenderPipelineState(fieldOverPipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        encoder.setFragmentTexture(field, index: 0)
        encoder.setFragmentSamplerState(smoothSampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // And the glow on top.
        if let glow {
            var settings = GlowUniforms(
                step: .zero,
                threshold: 0,
                strength: Float(model.glowStrength)
            )
            encoder.setRenderPipelineState(glowAddPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.setFragmentBytes(&settings, length: MemoryLayout<GlowUniforms>.stride, index: 0)
            encoder.setFragmentTexture(glow, index: 0)
            encoder.setFragmentSamplerState(smoothSampler, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
    }

    /// One of the two small pictures the glow is built in, made or reused.
    private func glowTexture(
        _ held: inout MTLTexture?,
        width: Int,
        height: Int,
        device: MTLDevice
    ) -> MTLTexture? {
        if let existing = held, existing.width == width, existing.height == height { return existing }
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = colorPixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        held = device.makeTexture(descriptor: descriptor)
        return held
    }

    /// The persistent picture, rebuilt when the screen changes size.
    ///
    /// Rotating the phone or splitting the screen changes the drawable, and a texture of the old size
    /// cannot be copied into the new one. Rebuilding loses whatever was fading, which for a fraction
    /// of a second of trail is not worth any machinery to preserve.
    private func accumulationTexture(width: Int, height: Int, device: MTLDevice) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        if let accumulation, accumulationWidth == width, accumulationHeight == height {
            return accumulation
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = colorPixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.usage = [.renderTarget, .shaderRead]
        // Private: nothing on the processor reads this one, so the GPU can keep it in whatever
        // arrangement suits it.
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        accumulation = texture
        accumulationWidth = width
        accumulationHeight = height
        // Started empty rather than from whatever the memory held, which would otherwise show for one
        // frame as noise.
        clearAccumulation(texture)
        return texture
    }

    /// Empties a freshly made picture.
    ///
    /// Emptied rather than filled with the room's black, because this picture is now a *layer* — the
    /// field, on its own, with nothing behind it. Filling it with black would hide whatever background
    /// is meant to show through, and the field would sit in a box rather than in a scene.
    private func clearAccumulation(_ texture: MTLTexture) {
        guard let buffer = commandQueue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        buffer.commit()
    }

    /// The record of how far away things are for a field in 3D, made or reused.
    ///
    /// Kept only in the graphics card's own fast memory on a phone, which is possible because nothing reads it
    /// after the frame: it costs no memory the rest of the phone could use and no time spent writing it out.
    private func depthRecord(width: Int, height: Int, device: MTLDevice) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        if let depthTexture, depthTextureWidth == width, depthTextureHeight == height { return depthTexture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .renderTarget
        #if targetEnvironment(simulator)
        descriptor.storageMode = .private
        #else
        descriptor.storageMode = .memoryless
        #endif
        var made = device.makeTexture(descriptor: descriptor)
        if made == nil, descriptor.storageMode != .private {
            descriptor.storageMode = .private
            made = device.makeTexture(descriptor: descriptor)
        }
        depthTexture = made
        depthTextureWidth = made == nil ? 0 : width
        depthTextureHeight = made == nil ? 0 : height
        return made
    }

    /// Dims the previous frame by painting the background over it.
    ///
    /// - Parameter drawing: the 3D drawing, when the pass is one for a field in 3D — every drawing in a pass has
    ///   to be made for that kind of pass, the fade included.
    private func encodeFade(
        _ frame: ParticleFieldModel.Frame,
        into encoder: MTLRenderCommandEncoder,
        drawing: DepthDrawing? = nil
    ) {
        var uniforms = Self.uniforms(for: frame)
        // Nothing at all, at the fraction the reference uses. The engine owns that figure, alongside
        // everything else about how trails look.
        //
        // Transparent black rather than the room's near-black, now that this picture is a layer with a
        // background behind it. Painting near-black over it at a quarter would fade a trail *toward the
        // room's colour* — which, laid over a starfield, means every trail leaves a dark smear that
        // slowly blots out the stars behind it. Painting nothing at a quarter instead scales what is
        // there down to three quarters and leaves the background showing through, which is what a
        // fading trail should do.
        var fade = FadeUniforms(
            color: SIMD4<Float>(0, 0, 0, Float(frame.trailFade))
        )
        if let drawing {
            encoder.setRenderPipelineState(drawing.fade)
            encoder.setDepthStencilState(drawing.ignoresDepth)
        } else {
            encoder.setRenderPipelineState(fadePipeline)
        }
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        encoder.setFragmentBytes(&fade, length: MemoryLayout<FadeUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // MARK: - Capturing a picture

    /// Reads back the picture that is on screen.
    ///
    /// Copies the field's own persistent texture rather than drawing everything again. That is both
    /// simpler and strictly more faithful: with trails on, what is on screen includes a dozen frames
    /// of fading history, and a fresh render would show only the present moment — a screenshot
    /// missing the very effect someone took it to capture.
    ///
    /// It also means taking a picture cannot advance the simulation or disturb what is displayed. The
    /// texture is read, not rebuilt.
    func snapshot() -> UIImage? {
        guard let device,
              let field = accumulation,
              let frame = lastFrame,
              // Nothing has been drawn yet, so there is nothing to photograph. Honest emptiness
              // rather than a black rectangle that looks like a bug.
              accumulationWidth > 0, accumulationHeight > 0,
              let buffer = commandQueue.makeCommandBuffer()
        else { return nil }

        let width = accumulationWidth
        let height = accumulationHeight

        // The finished picture — background, field and glow — composed again into a picture of its own,
        // because the screen's own cannot be read back. A photograph used to be the field layer alone: no
        // stars, no glow, and every half-transparent body darker than it looked, since that layer's colours
        // are stored already multiplied by their opacity.
        let composedDescriptor = MTLTextureDescriptor()
        composedDescriptor.pixelFormat = colorPixelFormat
        composedDescriptor.width = width
        composedDescriptor.height = height
        composedDescriptor.usage = [.renderTarget, .shaderRead]
        composedDescriptor.storageMode = .private
        guard let source = device.makeTexture(descriptor: composedDescriptor) else { return nil }
        let glow = model.glowStrength > 0 && glowA != nil ? glowA : nil
        encodeFinalPicture(frame, field: field, glow: glow, to: source, in: buffer)

        // The picture on screen lives in memory only the GPU can reach, so it is copied into one the
        // processor can read before being handed over.
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = colorPixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let readable = device.makeTexture(descriptor: descriptor),
              let blit = buffer.makeBlitCommandEncoder()
        else { return nil }

        blit.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: readable,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        buffer.commit()
        // Waited on, because the bytes are wanted now. This is a button press, not a frame.
        buffer.waitUntilCompleted()

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            readable.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        return LabSnapshot.image(fromMetalBGRA: bytes, width: width, height: height)
    }

    // MARK: - Drawing

    /// Reads this frame out of the model and gets it onto the GPU.
    ///
    /// Separate from the encoding below so that both the live view and a still capture run exactly
    /// the same code. Two copies of a four-pass draw would drift apart, and the one that drifted
    /// would be the one nobody looks at until they share a picture.
    private func prepare(device: MTLDevice) -> ParticleFieldModel.Frame {
        let frame = model.fillFrame(
            positions: &positions,
            colors: &colors,
            sizes: &sizes,
            springPositions: &springPositions,
            swarmPositions: &swarmPositions,
            swarmColors: &swarmColors,
            swarmSizes: &swarmSizes,
            trailPositions: &trailPositions,
            trailColors: &trailColors,
            guidePositions: &guidePositions,
            guideColors: &guideColors,
            depths: &depthBuffers
        )

        var set = frameBuffers[frameSlot]
        upload(&set.position, from: positions, count: frame.bodyCount * 2, device: device)
        upload(&set.color, from: colors, count: frame.bodyCount, device: device)
        upload(&set.size, from: sizes, count: frame.bodyCount, device: device)
        upload(&set.spring, from: springPositions, count: frame.springCount * 4, device: device)
        upload(
            &set.swarmPosition,
            from: swarmPositions,
            count: frame.swarmCount * (frame.swarmIsStreaked ? 4 : 2),
            device: device
        )
        upload(
            &set.swarmColor,
            from: swarmColors,
            count: frame.swarmCount * (frame.swarmIsStreaked ? 2 : 1),
            device: device
        )
        if frame.swarmHasSizes {
            upload(&set.swarmSize, from: swarmSizes, count: frame.swarmCount, device: device)
        }
        upload(&set.trailPosition, from: trailPositions, count: frame.trailSegmentCount * 4, device: device)
        upload(&set.trailColor, from: trailColors, count: frame.trailSegmentCount * 2, device: device)
        upload(&set.guidePosition, from: guidePositions, count: frame.guideSegmentCount * 4, device: device)
        upload(&set.guideColor, from: guideColors, count: frame.guideSegmentCount * 2, device: device)
        // How far into the box everything is, one number per point drawn. Only in 3D: a flat field uploads exactly
        // what it always did.
        if frame.depth != nil {
            upload(&set.bodyDepth, from: depthBuffers.bodies, count: frame.bodyCount, device: device)
            upload(
                &set.swarmDepth,
                from: depthBuffers.swarm,
                count: frame.swarmCount * (frame.swarmIsStreaked ? 2 : 1),
                device: device
            )
            upload(&set.springDepth, from: depthBuffers.springs, count: frame.springCount * 2, device: device)
            upload(&set.trailDepth, from: depthBuffers.trails, count: frame.trailSegmentCount * 2, device: device)
            upload(&set.guideDepth, from: depthBuffers.guides, count: frame.guideSegmentCount * 2, device: device)
        }
        frameBuffers[frameSlot] = set

        return frame
    }

    /// Everything the shaders need to place a body, gathered in one place.
    ///
    /// One function rather than built twice, because the fading backdrop and the field itself must
    /// agree about the camera exactly. If they drifted apart, the fade would dim one part of the
    /// screen while the bodies were drawn in another, and trails would appear to stick.
    private static func uniforms(for frame: ParticleFieldModel.Frame) -> Uniforms {
        Uniforms(
            worldSize: SIMD2<Float>(Float(frame.worldWidth), Float(frame.worldHeight)),
            viewSize: SIMD2<Float>(Float(frame.viewWidth), Float(frame.viewHeight)),
            pan: SIMD2<Float>(Float(frame.camera.panX), Float(frame.camera.panY)),
            orbit: SIMD2<Float>(
                Float(ParticleCamera.radians(frame.camera.effectiveYaw)),
                Float(ParticleCamera.radians(frame.camera.pitch))
            ),
            // In pixels of the picture being drawn, which is not the screen's when the detail is turned
            // down. Everything else in this struct is either in world units or in screen pixels used only as
            // a ratio, so this is the one measurement that has to be converted.
            // A multiplier on each body's own size for the object bodies, which carry their sizes in a buffer
            // of their own; the crowd's pass replaces it with the crowd's size.
            //
            // Times the zoom — the zoom itself, not the picture's scale below. A body's size is a size in the
            // world, and zoomed out to add room the world is larger than the screen, so each of its pixels is
            // smaller on the screen and so is everything in it. Drawn at the picture's scale, which stays at one
            // then, bodies kept their size on the screen while the world grew round them — so pulling back to
            // make room made every body bigger compared with the room, which is the opposite of room.
            pointSize: Float(frame.pixelRatio * frame.camera.zoom),
            // The picture's scale, not the zoom. With zooming out set to add room the two differ, and the
            // processor — which places the finger and the ring — already used the picture's scale while this
            // used the zoom: so pulling back shrank the picture *and* grew the world, the field drew as a small
            // square in the middle of the screen, and a touch landed nowhere near what it was aimed at.
            zoom: Float(frame.camera.pictureScale),
            shape: frame.shape.shaderIdentifier
        )
    }

    /// The four passes, in the order that decides what sits in front of what.
    private func encode(_ frame: ParticleFieldModel.Frame, into encoder: MTLRenderCommandEncoder) {
        var uniforms = Self.uniforms(for: frame)
        let set = frameBuffers[frameSlot]

        // The swarm first and smallest: it is the crowd, and the few individually interesting
        // bodies should never be buried under it.
        if frame.swarmCount > 0,
           let swarmPositionBuffer = set.swarmPosition, let swarmColorBuffer = set.swarmColor {
            var swarmUniforms = uniforms
            // The size slider's width. This was fixed at one pixel, which is why the slider seemed to work on
            // scenes and not on anything added: added bodies are the crowd. Following the zoom, as every size
            // does — see `uniforms(for:)`.
            swarmUniforms.pointSize = Float(frame.swarmPointSize * frame.pixelRatio * frame.camera.zoom)
            if frame.swarmIsStreaked {
                // As lines along each body's own motion. The trail pipeline, because it is the one that takes
                // a colour per vertex — a spring line is one flat colour for all of them.
                encoder.setRenderPipelineState(trailPipeline)
                encoder.setVertexBuffer(swarmPositionBuffer, offset: 0, index: 0)
                encoder.setVertexBuffer(swarmColorBuffer, offset: 0, index: 1)
                encoder.setVertexBytes(&swarmUniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
                encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: frame.swarmCount * 2)
            } else if frame.swarmHasSizes, let swarmSizeBuffer = set.swarmSize {
                // One size per body, from the crowd's own list, drawn the way the object bodies are — with the
                // plain multiplier rather than the slider's width, since each body's size already has the slider
                // in it.
                encoder.setRenderPipelineState(bodyPipeline)
                encoder.setVertexBuffer(swarmPositionBuffer, offset: 0, index: 0)
                encoder.setVertexBuffer(swarmColorBuffer, offset: 0, index: 1)
                encoder.setVertexBuffer(swarmSizeBuffer, offset: 0, index: 3)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: frame.swarmCount)
            } else {
                encoder.setRenderPipelineState(pointPipeline)
                encoder.setVertexBuffer(swarmPositionBuffer, offset: 0, index: 0)
                encoder.setVertexBuffer(swarmColorBuffer, offset: 0, index: 1)
                encoder.setVertexBytes(&swarmUniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
                encoder.setFragmentBytes(&swarmUniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: frame.swarmCount)
            }
        }

        // Trails behind everything solid: they are where a body has been, and should never sit on
        // top of where it is now.
        if frame.trailSegmentCount > 0,
           let trailPositionBuffer = set.trailPosition, let trailColorBuffer = set.trailColor {
            encoder.setRenderPipelineState(trailPipeline)
            encoder.setVertexBuffer(trailPositionBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(trailColorBuffer, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.drawPrimitives(
                type: .line,
                vertexStart: 0,
                vertexCount: frame.trailSegmentCount * 2
            )
        }

        // Springs next, so a cloth's structure sits behind its nodes.
        if frame.springCount > 0, let springBuffer = set.spring {
            encoder.setRenderPipelineState(springPipeline)
            encoder.setVertexBuffer(springBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: frame.springCount * 2)
        }

        if frame.bodyCount > 0, let positionBuffer = set.position, let colorBuffer = set.color,
           let sizeBuffer = set.size {
            encoder.setRenderPipelineState(bodyPipeline)
            encoder.setVertexBuffer(positionBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
            encoder.setVertexBuffer(sizeBuffer, offset: 0, index: 3)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: frame.bodyCount)
        }

        // The walls and the painted wind, over the bodies. They are things somebody drew rather than part of
        // the simulation, so they belong in front of it — a wall hidden behind a dense crowd is a wall
        // somebody cannot tell they have drawn.
        if frame.guideSegmentCount > 0,
           let guidePositionBuffer = set.guidePosition, let guideColorBuffer = set.guideColor {
            encoder.setRenderPipelineState(trailPipeline)
            encoder.setVertexBuffer(guidePositionBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(guideColorBuffer, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.drawPrimitives(
                type: .line,
                vertexStart: 0,
                vertexCount: frame.guideSegmentCount * 2
            )
        }

        // The ring last, over everything, because it is a statement about what your finger is doing
        // rather than part of the field.
        if let ring = frame.touchRing {
            var ringUniforms = Self.ringUniforms(for: ring)
            encoder.setRenderPipelineState(ringPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.setFragmentBytes(
                &ringUniforms,
                length: MemoryLayout<RingUniforms>.stride,
                index: 0
            )
            // Four corners from the vertex number alone, as a strip. No vertex buffer needed for a
            // shape that is always the whole screen.
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    /// The ring's settings as the shader reads them.
    private static func ringUniforms(for ring: ParticleFieldModel.TouchRing) -> RingUniforms {
        RingUniforms(
            color: SIMD4<Float>(Float(ring.red), Float(ring.green), Float(ring.blue), 1),
            centre: SIMD2<Float>(Float(ring.x), Float(ring.y)),
            radius: Float(ring.radius),
            strokeWidth: Float(ring.strokeWidth),
            centreDotRadius: Float(ring.centreDotRadius),
            strokeOpacity: Float(ring.strokeOpacity),
            fillOpacity: Float(ring.fillOpacity)
        )
    }

    // MARK: - Drawing in 3D

    /// How the box is being looked at, as the shader reads it.
    ///
    /// The cosines and sines are worked out once here rather than for every one of a million bodies.
    private static func depthUniforms(for view: ParticleFieldModel.DepthView) -> DepthUniforms {
        DepthUniforms(
            turn: SIMD4<Float>(
                Float(cos(view.yaw)),
                Float(sin(view.yaw)),
                Float(cos(view.pitch)),
                Float(sin(view.pitch))
            ),
            fog: SIMD4<Float>(Float(view.fog), 0, 0, 0),
            worldDepth: Float(view.worldDepth),
            eyeDistance: Float(view.eyeDistance),
            radius: Float(view.radius),
            nearLimit: Float(ParticleCamera.depthNearLimit)
        )
    }

    /// The field in 3D. The same passes as a flat field, with every body and each end of every line at its own
    /// depth.
    ///
    /// Solid, the nearer hides the further, whatever order things are drawn in — so the crowd can hide a body
    /// behind it, which on a flat field it never may. Glowing, nothing hides anything and overlapping bodies add
    /// up to something brighter than either.
    private func encodeInDepth(
        _ frame: ParticleFieldModel.Frame,
        view: ParticleFieldModel.DepthView,
        drawing: DepthDrawing,
        into encoder: MTLRenderCommandEncoder
    ) {
        var uniforms = Self.uniforms(for: frame)
        var depthUniforms = Self.depthUniforms(for: view)
        let set = frameBuffers[frameSlot]
        let glows = view.glows
        let uniformLength = MemoryLayout<Uniforms>.stride
        let depthLength = MemoryLayout<DepthUniforms>.stride
        // What the bodies do with the record of depth, and what the lines do.
        let bodiesTreatDepth = glows ? drawing.ignoresDepth : drawing.hidesWhatIsBehind
        let linesTreatDepth = glows ? drawing.ignoresDepth : drawing.isHiddenByWhatIsNearer

        // Glowing, the box goes in first so the light is added on top of it. Solid, it goes in last, so each of
        // its edges is hidden wherever something nearer is in the way and shows wherever it is in front.
        if glows {
            encodeGuidesInDepth(frame, set: set, uniforms: uniforms, depth: depthUniforms, drawing: drawing, into: encoder)
        }

        if frame.swarmCount > 0,
           let positions = set.swarmPosition, let colours = set.swarmColor, let depths = set.swarmDepth {
            var swarmUniforms = uniforms
            // The crowd's one size, following the zoom, as on a flat field.
            swarmUniforms.pointSize = Float(frame.swarmPointSize * frame.pixelRatio * frame.camera.zoom)
            encoder.setDepthStencilState(bodiesTreatDepth)
            encoder.setVertexBuffer(positions, offset: 0, index: 0)
            encoder.setVertexBuffer(colours, offset: 0, index: 1)
            encoder.setVertexBuffer(depths, offset: 0, index: 4)
            encoder.setVertexBytes(&depthUniforms, length: depthLength, index: 5)
            if frame.swarmIsStreaked {
                encoder.setRenderPipelineState(glows ? drawing.linesGlowing : drawing.lines)
                encoder.setVertexBytes(&swarmUniforms, length: uniformLength, index: 2)
                encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: frame.swarmCount * 2)
            } else if frame.swarmHasSizes, let sizes = set.swarmSize {
                encoder.setRenderPipelineState(glows ? drawing.bodiesGlowing : drawing.bodies)
                encoder.setVertexBuffer(sizes, offset: 0, index: 3)
                encoder.setVertexBytes(&uniforms, length: uniformLength, index: 2)
                encoder.setFragmentBytes(&uniforms, length: uniformLength, index: 0)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: frame.swarmCount)
            } else {
                encoder.setRenderPipelineState(glows ? drawing.pointsGlowing : drawing.points)
                encoder.setVertexBytes(&swarmUniforms, length: uniformLength, index: 2)
                encoder.setFragmentBytes(&swarmUniforms, length: uniformLength, index: 0)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: frame.swarmCount)
            }
        }

        if frame.trailSegmentCount > 0,
           let positions = set.trailPosition, let colours = set.trailColor, let depths = set.trailDepth {
            encoder.setRenderPipelineState(glows ? drawing.linesGlowing : drawing.lines)
            encoder.setDepthStencilState(linesTreatDepth)
            encoder.setVertexBuffer(positions, offset: 0, index: 0)
            encoder.setVertexBuffer(colours, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: uniformLength, index: 2)
            encoder.setVertexBuffer(depths, offset: 0, index: 4)
            encoder.setVertexBytes(&depthUniforms, length: depthLength, index: 5)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: frame.trailSegmentCount * 2)
        }

        if frame.springCount > 0, let positions = set.spring, let depths = set.springDepth {
            encoder.setRenderPipelineState(drawing.springs)
            encoder.setDepthStencilState(linesTreatDepth)
            encoder.setVertexBuffer(positions, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: uniformLength, index: 2)
            encoder.setVertexBuffer(depths, offset: 0, index: 4)
            encoder.setVertexBytes(&depthUniforms, length: depthLength, index: 5)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: frame.springCount * 2)
        }

        if frame.bodyCount > 0, let positions = set.position, let colours = set.color,
           let sizes = set.size, let depths = set.bodyDepth {
            encoder.setRenderPipelineState(glows ? drawing.bodiesGlowing : drawing.bodies)
            encoder.setDepthStencilState(bodiesTreatDepth)
            encoder.setVertexBuffer(positions, offset: 0, index: 0)
            encoder.setVertexBuffer(colours, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: uniformLength, index: 2)
            encoder.setVertexBuffer(sizes, offset: 0, index: 3)
            encoder.setVertexBuffer(depths, offset: 0, index: 4)
            encoder.setVertexBytes(&depthUniforms, length: depthLength, index: 5)
            encoder.setFragmentBytes(&uniforms, length: uniformLength, index: 0)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: frame.bodyCount)
        }

        if !glows {
            encodeGuidesInDepth(frame, set: set, uniforms: uniforms, depth: depthUniforms, drawing: drawing, into: encoder)
        }

        // The ring over everything, as on a flat field. It is drawn on the glass, not in the box.
        if let ring = frame.touchRing {
            var ringUniforms = Self.ringUniforms(for: ring)
            encoder.setRenderPipelineState(drawing.ring)
            encoder.setDepthStencilState(drawing.ignoresDepth)
            encoder.setVertexBytes(&uniforms, length: uniformLength, index: 2)
            encoder.setFragmentBytes(&ringUniforms, length: MemoryLayout<RingUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    /// The box's edges and floor, and the walls, wind and glass drawn into it.
    private func encodeGuidesInDepth(
        _ frame: ParticleFieldModel.Frame,
        set: FrameBuffers,
        uniforms: Uniforms,
        depth: DepthUniforms,
        drawing: DepthDrawing,
        into encoder: MTLRenderCommandEncoder
    ) {
        guard frame.guideSegmentCount > 0,
              let positions = set.guidePosition, let colours = set.guideColor, let depths = set.guideDepth
        else { return }
        var uniforms = uniforms
        var depth = depth
        encoder.setRenderPipelineState(drawing.lines)
        encoder.setDepthStencilState(frame.depth?.glows == true ? drawing.ignoresDepth : drawing.isHiddenByWhatIsNearer)
        encoder.setVertexBuffer(positions, offset: 0, index: 0)
        encoder.setVertexBuffer(colours, offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        encoder.setVertexBuffer(depths, offset: 0, index: 4)
        encoder.setVertexBytes(&depth, length: MemoryLayout<DepthUniforms>.stride, index: 5)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: frame.guideSegmentCount * 2)
    }

    /// Copies a slice of an array into a GPU buffer, making a bigger one only when needed.
    private func upload<T>(
        _ buffer: inout MTLBuffer?,
        from source: [T],
        count wanted: Int,
        device: MTLDevice
    ) {
        // Never more than the array holds, so a list that fell short could not have memory past its end copied
        // onto the graphics card.
        let count = min(wanted, source.count)
        guard count > 0 else { return }
        let bytes = count * MemoryLayout<T>.stride
        if buffer == nil || buffer!.length < bytes {
            // Half again as much as is needed, so a field that is growing steadily does not
            // reallocate on every single frame.
            let generous = Int(Double(bytes) * 1.5)
            buffer = device.makeBuffer(length: max(generous, bytes), options: .storageModeShared)
        }
        guard let destination = buffer else { return }
        source.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            destination.contents().copyMemory(from: base, byteCount: bytes)
        }
    }
}
