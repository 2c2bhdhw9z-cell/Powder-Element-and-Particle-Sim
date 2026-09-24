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
final class GridRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    /// The texture the grid is uploaded into, rebuilt when the world changes size.
    private var texture: MTLTexture?
    private var textureWidth = 0
    private var textureHeight = 0

    /// Where the engine writes its pixels before they are uploaded.
    ///
    /// Held rather than allocated per frame: at one cell per pixel on a large world this is
    /// megabytes, and allocating it sixty times a second would dominate the frame.
    private var pixels: UnsafeMutablePointer<UInt32>?
    private var pixelCapacity = 0

    /// What to draw, and how. Owned elsewhere; read on the main actor each frame.
    private let source: SimulationModel

    init?(view: MTKView, source: SimulationModel) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        guard let queue = device.makeCommandQueue() else { return nil }

        // The shader library is compiled into the app at build time, not from source at
        // launch — compiling at launch would add a visible pause to the first frame and can
        // fail on a device in ways that never show up in a simulator.
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "gridVertex"),
              let fragmentFunction = library.makeFunction(name: "gridFragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.pipeline = pipeline
        self.source = source
        super.init()
    }

    deinit {
        pixels?.deallocate()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Nothing to do. The world's size is decided by the simulation, not by the view: the
        // texture is stretched to whatever the view happens to be, so a rotation or a split
        // screen costs nothing here.
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = commandQueue.makeCommandBuffer()
        else { return }

        uploadGrid()

        if let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor), let texture {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        buffer.present(drawable)
        buffer.commit()
    }

    /// Asks the engine for this frame's pixels and copies them into the texture.
    private func uploadGrid() {
        let (width, height, overlay) = source.gridGeometry()
        guard width > 0, height > 0 else { return }

        if textureWidth != width || textureHeight != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = .shaderRead
            // Written by the processor every frame and read by the GPU, so it lives where
            // both can see it without a copy.
            descriptor.storageMode = .shared
            texture = device.makeTexture(descriptor: descriptor)
            textureWidth = width
            textureHeight = height
        }

        let needed = width * height
        if pixelCapacity < needed {
            pixels?.deallocate()
            pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: needed)
            pixelCapacity = needed
        }
        guard let pixels, let texture else { return }

        source.renderGrid(into: pixels, overlay: overlay)

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
    }
}
