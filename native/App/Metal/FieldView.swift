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
    private let springPipeline: MTLRenderPipelineState
    private let trailPipeline: MTLRenderPipelineState
    private let ringPipeline: MTLRenderPipelineState
    private let fadePipeline: MTLRenderPipelineState

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
    private var springPositions: [Float] = []
    private var swarmPositions: [Float] = []
    private var swarmColors: [UInt32] = []
    private var trailPositions: [Float] = []
    private var trailColors: [UInt32] = []

    /// The GPU-side copies. Reallocated only when they are too small.
    private var positionBuffer: MTLBuffer?
    private var colorBuffer: MTLBuffer?
    private var springBuffer: MTLBuffer?
    private var swarmPositionBuffer: MTLBuffer?
    private var swarmColorBuffer: MTLBuffer?
    private var trailPositionBuffer: MTLBuffer?
    private var trailColorBuffer: MTLBuffer?

    init?(model: ParticleFieldModel) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let pointVertex = library.makeFunction(name: "particleVertex"),
              let pointFragment = library.makeFunction(name: "particleFragment"),
              let springVertex = library.makeFunction(name: "springVertex"),
              let springFragment = library.makeFunction(name: "springFragment"),
              let trailVertex = library.makeFunction(name: "trailVertex"),
              let trailFragment = library.makeFunction(name: "trailFragment"),
              let ringVertex = library.makeFunction(name: "ringVertex"),
              let ringFragment = library.makeFunction(name: "ringFragment"),
              let fadeFragment = library.makeFunction(name: "fadeFragment")
        else { return nil }

        func pipeline(_ vertex: MTLFunction, _ fragment: MTLFunction) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            // Blended, so overlapping bodies build up rather than the last one drawn winning,
            // and so a spring can be a hairline rather than a hard white stripe.
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        guard let points = pipeline(pointVertex, pointFragment),
              let springs = pipeline(springVertex, springFragment),
              let trails = pipeline(trailVertex, trailFragment),
              let ring = pipeline(ringVertex, ringFragment),
              // The fade reuses the ring's vertex function, which already covers the screen from the
              // vertex number alone and needs no geometry of its own.
              let fade = pipeline(ringVertex, fadeFragment)
        else { return nil }

        self.model = model
        self.commandQueue = queue
        self.pointPipeline = points
        self.springPipeline = springs
        self.trailPipeline = trails
        self.ringPipeline = ring
        self.fadePipeline = fade
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        // The finished picture is copied in from the field's own texture rather than drawn straight
        // into the drawable, and a drawable that is framebuffer-only cannot be copied into.
        framebufferOnly = false
        isOpaque = true
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        enableSetNeedsDisplay = false
        isPaused = false
        preferredFramesPerSecond = 120
        // The lab's own near-black, so the field sits in the same room as the powder grid.
        clearColor = MTLClearColor(red: 10 / 255, green: 10 / 255, blue: 12 / 255, alpha: 1)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("Crucible's field view is created in code, never from a storyboard.")
    }

    override func draw(_ rect: CGRect) {
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

        let frame = prepare(device: device)

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
            // than drawing a fully opaque rectangle over it.
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = clearColor
        }

        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            buffer.present(drawable)
            buffer.commit()
            return
        }

        if model.showTrails, !cameraMoved {
            encodeFade(frame, into: encoder)
        }
        encode(frame, into: encoder)
        encoder.endEncoding()

        // Copied across rather than drawn twice. A blit is the cheapest way to move a whole texture
        // and needs no pipeline of its own.
        if let blit = buffer.makeBlitCommandEncoder() {
            blit.copy(
                from: target,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: drawable.texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blit.endEncoding()
        }

        buffer.present(drawable)
        buffer.commit()
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
        // Started from the room's own black rather than from whatever the memory held, which would
        // otherwise show for one frame as noise.
        clearAccumulation(texture)
        return texture
    }

    /// Fills a freshly made picture with the background colour.
    private func clearAccumulation(_ texture: MTLTexture) {
        guard let buffer = commandQueue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = clearColor
        pass.colorAttachments[0].storeAction = .store
        buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        buffer.commit()
    }

    /// Dims the previous frame by painting the background over it.
    private func encodeFade(
        _ frame: ParticleFieldModel.Frame,
        into encoder: MTLRenderCommandEncoder
    ) {
        var uniforms = Self.uniforms(for: frame)
        // The room's own near-black, at the fraction of itself the reference uses. The engine owns
        // that figure, alongside everything else about how trails look.
        var fade = FadeUniforms(
            color: SIMD4<Float>(
                Float(10.0 / 255.0),
                Float(10.0 / 255.0),
                Float(12.0 / 255.0),
                Float(ParticleOverlayStyle.frameFadeOpacity)
            )
        )
        encoder.setRenderPipelineState(fadePipeline)
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
              let source = accumulation,
              // Nothing has been drawn yet, so there is nothing to photograph. Honest emptiness
              // rather than a black rectangle that looks like a bug.
              accumulationWidth > 0, accumulationHeight > 0,
              let buffer = commandQueue.makeCommandBuffer()
        else { return nil }

        let width = accumulationWidth
        let height = accumulationHeight

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
            springPositions: &springPositions,
            swarmPositions: &swarmPositions,
            swarmColors: &swarmColors,
            trailPositions: &trailPositions,
            trailColors: &trailColors
        )

        upload(&positionBuffer, from: positions, count: frame.bodyCount * 2, device: device)
        upload(&colorBuffer, from: colors, count: frame.bodyCount, device: device)
        upload(&springBuffer, from: springPositions, count: frame.springCount * 4, device: device)
        upload(&swarmPositionBuffer, from: swarmPositions, count: frame.swarmCount * 2, device: device)
        upload(&swarmColorBuffer, from: swarmColors, count: frame.swarmCount, device: device)
        upload(&trailPositionBuffer, from: trailPositions, count: frame.trailSegmentCount * 4, device: device)
        upload(&trailColorBuffer, from: trailColors, count: frame.trailSegmentCount * 2, device: device)

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
            pointSize: Float(frame.pointSize),
            zoom: Float(frame.camera.zoom)
        )
    }

    /// The four passes, in the order that decides what sits in front of what.
    private func encode(_ frame: ParticleFieldModel.Frame, into encoder: MTLRenderCommandEncoder) {
        var uniforms = Self.uniforms(for: frame)

        // The swarm first and smallest: it is the crowd, and the few individually interesting
        // bodies should never be buried under it.
        if frame.swarmCount > 0,
           let swarmPositionBuffer, let swarmColorBuffer {
            var swarmUniforms = uniforms
            swarmUniforms.pointSize = 1
            encoder.setRenderPipelineState(pointPipeline)
            encoder.setVertexBuffer(swarmPositionBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(swarmColorBuffer, offset: 0, index: 1)
            encoder.setVertexBytes(&swarmUniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: frame.swarmCount)
        }

        // Trails behind everything solid: they are where a body has been, and should never sit on
        // top of where it is now.
        if frame.trailSegmentCount > 0,
           let trailPositionBuffer, let trailColorBuffer {
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
        if frame.springCount > 0, let springBuffer {
            encoder.setRenderPipelineState(springPipeline)
            encoder.setVertexBuffer(springBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: frame.springCount * 2)
        }

        if frame.bodyCount > 0, let positionBuffer, let colorBuffer {
            encoder.setRenderPipelineState(pointPipeline)
            encoder.setVertexBuffer(positionBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: frame.bodyCount)
        }

        // The ring last, over everything, because it is a statement about what your finger is doing
        // rather than part of the field.
        if let ring = frame.touchRing {
            var ringUniforms = RingUniforms(
                color: SIMD4<Float>(
                    Float(ring.red),
                    Float(ring.green),
                    Float(ring.blue),
                    1
                ),
                centre: SIMD2<Float>(Float(ring.x), Float(ring.y)),
                radius: Float(ring.radius),
                strokeWidth: Float(ring.strokeWidth),
                centreDotRadius: Float(ring.centreDotRadius),
                strokeOpacity: Float(ring.strokeOpacity),
                fillOpacity: Float(ring.fillOpacity)
            )
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

    /// Copies a slice of an array into a GPU buffer, making a bigger one only when needed.
    private func upload<T>(
        _ buffer: inout MTLBuffer?,
        from source: [T],
        count: Int,
        device: MTLDevice
    ) {
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
