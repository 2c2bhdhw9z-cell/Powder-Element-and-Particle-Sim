import CrucibleCore
import Metal
import MetalKit

/// Puts the simulation on the screen.
///
/// The whole job is: ask the engine for a grid of finished pixels, hand them to the GPU as a
/// texture, and stretch that texture over the view. There are no colour decisions here —
/// those all live in the engine, where they are checked against the reference implementation
/// cell by cell. Shader and renderer code is the hardest code in this project to test, so it
/// has been left with as little judgement in it as possible.
///
/// ## Why this is a view subclass rather than a delegate
///
/// MetalKit offers both. The delegate protocol is not marked as belonging to the main thread,
/// even though the view calls it there, so conforming to it means either asserting that fact
/// at every entry point or giving up the compiler's checking. A view is already main-thread
/// by definition, so overriding its drawing method states the same thing with nothing to
/// assert and nothing to get wrong.
@MainActor
final class GridView: MTKView {
    /// What to draw, and how.
    private let model: SimulationModel

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    /// The texture the grid is uploaded into, rebuilt when the world changes size.
    private var gridTexture: MTLTexture?
    private var textureWidth = 0
    private var textureHeight = 0

    /// Where the engine writes its pixels before they are uploaded.
    ///
    /// Held rather than allocated per frame: at one cell per pixel this is megabytes, and
    /// allocating it sixty times a second would cost more than the simulation does.
    private var pixels: UnsafeMutablePointer<UInt32>?
    private var pixelCapacity = 0

    /// Fails only when the device has no usable Metal support, which the app declares it
    /// requires — so in practice this succeeds or the app was never installable.
    init?(model: SimulationModel) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              // Compiled into the app at build time, not from source at launch. Compiling at
              // launch would add a visible pause to the first frame and can fail on a device
              // in ways that never appear in a simulator.
              let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "gridVertex"),
              let fragmentFunction = library.makeFunction(name: "gridFragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        self.model = model
        self.commandQueue = queue
        self.pipeline = pipeline
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isOpaque = true
        // No depth buffer and no multisampling: this draws one flat quad.
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        // Driven by the display's own refresh signal rather than a timer, so the simulation
        // advances exactly once per frame shown — and stops entirely when nothing is on
        // screen, which is what anyone would expect and what a timer gets wrong.
        enableSetNeedsDisplay = false
        isPaused = false
        preferredFramesPerSecond = 120
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("Crucible's grid view is created in code, never from a storyboard.")
    }

    deinit {
        pixels?.deallocate()
    }

    override func draw(_ rect: CGRect) {
        // One tick then one frame, from the same signal, so the two cannot drift apart.
        model.tick()

        guard let descriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let buffer = commandQueue.makeCommandBuffer()
        else { return }

        uploadGrid()

        if let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor),
           let gridTexture {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(gridTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        buffer.present(drawable)
        buffer.commit()
    }

    /// Asks the engine for this frame's pixels and copies them into the texture.
    private func uploadGrid() {
        let geometry = model.gridGeometry()
        let width = geometry.width
        let height = geometry.height
        guard width > 0, height > 0, let device else { return }

        if textureWidth != width || textureHeight != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = .shaderRead
            // Written by the processor every frame and read by the GPU, so it lives where both
            // can reach it without a copy.
            descriptor.storageMode = .shared
            gridTexture = device.makeTexture(descriptor: descriptor)
            textureWidth = width
            textureHeight = height
        }

        let needed = width * height
        if pixelCapacity < needed {
            pixels?.deallocate()
            pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: needed)
            pixelCapacity = needed
        }
        guard let pixels, let gridTexture else { return }

        model.renderGrid(into: pixels, overlay: geometry.overlay)

        gridTexture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
    }
}
