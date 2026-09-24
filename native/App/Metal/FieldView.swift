import CrucibleCore
import Metal
import MetalKit
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
    /// Matches the layout the shader declares.
    private struct Uniforms {
        var worldSize: SIMD2<Float>
        var pointSize: Float
    }

    private let model: ParticleFieldModel
    private let commandQueue: MTLCommandQueue
    private let pointPipeline: MTLRenderPipelineState
    private let springPipeline: MTLRenderPipelineState

    // Held across frames and grown only when the field outgrows them, so a steady field
    // allocates nothing. At a million bodies these are megabytes; rebuilding them sixty times a
    // second would cost more than the simulation.
    private var positions: [Float] = []
    private var colors: [UInt32] = []
    private var springPositions: [Float] = []
    private var swarmPositions: [Float] = []
    private var swarmColors: [UInt32] = []

    /// The GPU-side copies. Reallocated only when they are too small.
    private var positionBuffer: MTLBuffer?
    private var colorBuffer: MTLBuffer?
    private var springBuffer: MTLBuffer?
    private var swarmPositionBuffer: MTLBuffer?
    private var swarmColorBuffer: MTLBuffer?

    init?(model: ParticleFieldModel) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let pointVertex = library.makeFunction(name: "particleVertex"),
              let pointFragment = library.makeFunction(name: "particleFragment"),
              let springVertex = library.makeFunction(name: "springVertex"),
              let springFragment = library.makeFunction(name: "springFragment")
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
              let springs = pipeline(springVertex, springFragment)
        else { return nil }

        self.model = model
        self.commandQueue = queue
        self.pointPipeline = points
        self.springPipeline = springs
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
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

        guard let descriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let buffer = commandQueue.makeCommandBuffer(),
              let device
        else { return }

        let frame = model.fillFrame(
            positions: &positions,
            colors: &colors,
            springPositions: &springPositions,
            swarmPositions: &swarmPositions,
            swarmColors: &swarmColors
        )

        var uniforms = Uniforms(
            worldSize: SIMD2<Float>(Float(frame.worldWidth), Float(frame.worldHeight)),
            pointSize: Float(frame.pointSize)
        )

        upload(&positionBuffer, from: positions, count: frame.bodyCount * 2, device: device)
        upload(&colorBuffer, from: colors, count: frame.bodyCount, device: device)
        upload(&springBuffer, from: springPositions, count: frame.springCount * 4, device: device)
        upload(&swarmPositionBuffer, from: swarmPositions, count: frame.swarmCount * 2, device: device)
        upload(&swarmColorBuffer, from: swarmColors, count: frame.swarmCount, device: device)

        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            buffer.present(drawable)
            buffer.commit()
            return
        }

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

        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
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
