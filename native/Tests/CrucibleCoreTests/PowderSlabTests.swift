import Testing

@testable import CrucibleCore

/// The powder world laid out as a slab of cubes for the box's camera.
@Suite("The powder world as a slab")
struct PowderSlabTests {
    private func world(width: Int = 60, height: Int = 40) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: 5)
        return engine
    }

    @Test("Only the grains with air beside them are drawn, and every one of them is")
    func drawsTheSurfaceOnly() {
        let engine = world()
        // A solid block: ten by ten of stone, so the shell is the edge and the inside is hidden.
        for y in 10 ..< 20 {
            for x in 10 ..< 20 { engine.setElement(x, y, Element.stone) }
        }
        #expect(engine.activeParticleCount == 100)
        // A ten by ten block's shell is its outer ring: a hundred less the eight by eight inside it.
        #expect(engine.surfaceCellCount() == 36)

        let shape = PowderSlab.Shape(width: 60, height: 40)
        let cubes = engine.slabCubes(shape: shape)
        #expect(cubes.count == 36)
        // Nothing from the middle of the block.
        #expect(!cubes.contains { abs($0.x - (15.5 - 30)) < 0.5 && abs($0.y - (15.5 - 20)) < 0.5 })
        // And nothing where there is only air.
        #expect(engine.slabCubes(shape: shape).allSatisfy { $0.color != 0 })
    }

    @Test("A grain at the world's edge counts as on the surface")
    func theWorldsEdgeIsSurface() {
        let engine = world(width: 4, height: 4)
        for y in 0 ..< 4 {
            for x in 0 ..< 4 { engine.setElement(x, y, Element.stone) }
        }
        // Filled to the brim: the twelve round the edge are surface, and only the four in the middle are enclosed. A
        // world filled solid would otherwise have no surface at all and be drawn as nothing.
        #expect(engine.surfaceCellCount() == 12)
        #expect(engine.slabCubes(shape: PowderSlab.Shape(width: 4, height: 4)).count == 12)

        // Even in a three by three, the one in the very middle is walled in on all four sides and cannot be seen, so
        // it is not drawn. Eight of nine.
        let tiny = world(width: 3, height: 3)
        for y in 0 ..< 3 {
            for x in 0 ..< 3 { tiny.setElement(x, y, Element.stone) }
        }
        #expect(tiny.surfaceCellCount() == 8)
    }

    @Test("The slab is laid out round the middle of the box, with the world's shape kept")
    func laidOutAroundTheMiddle() {
        let engine = world(width: 60, height: 40)
        for x in 0 ..< 60 { engine.setElement(x, 39, Element.sand) }
        let shape = PowderSlab.Shape(width: 120, height: 80, thickness: 0.1)
        let cubes = engine.slabCubes(shape: shape)
        #expect(cubes.count == 60)
        let across = cubes.map(\.x)
        let down = cubes.map(\.y)
        // Across the whole width, centred on nought.
        #expect((across.min() ?? 0) < -58 && (across.max() ?? 0) > 58)
        #expect(abs((across.min() ?? 0) + (across.max() ?? 0)) < 1e-9, "the slab is not centred")
        // The floor of the world is at the bottom of the slab.
        #expect((down.min() ?? 0) > 38 && (down.max() ?? 0) <= 40)
        // The thickness gives it relief, and never more than it was told.
        let deepest = cubes.map { abs($0.z) }.max() ?? 0
        #expect(deepest > 0 && deepest <= 120 * 0.1 / 2 + 1e-9, "\(deepest)")
        // A flat slab is exactly flat.
        #expect(engine.slabCubes(shape: PowderSlab.Shape(width: 120, height: 80, thickness: 0)).allSatisfy { $0.z == 0 })
    }

    @Test("Turning the box shows the same relief every time")
    func theReliefHoldsStill() {
        let engine = world()
        engine.drawBrush(centerX: 30, centerY: 20, radius: 8, elementID: Element.sand, shape: .circle)
        let shape = PowderSlab.Shape(width: 60, height: 40)
        #expect(engine.slabCubes(shape: shape) == engine.slabCubes(shape: shape))
    }

    @Test("The colours are the flat picture's own, so a heat view carries across")
    func coloursComeFromTheOneRenderer() {
        let engine = world()
        engine.setElement(5, 5, Element.lava, temp: 1_200)
        engine.setElement(6, 5, Element.ice, temp: -20)
        let shape = PowderSlab.Shape(width: 60, height: 40)

        var pixels = [UInt32](repeating: 0, count: engine.cellCount)
        pixels.withUnsafeMutableBufferPointer { engine.render(into: $0.baseAddress!, overlay: .normal) }
        let plain = engine.slabCubes(shape: shape, overlay: .normal)
        #expect(plain.contains { $0.color == pixels[engine.index(5, 5)] })

        pixels.withUnsafeMutableBufferPointer { engine.render(into: $0.baseAddress!, overlay: .temperature) }
        let heat = engine.slabCubes(shape: shape, overlay: .temperature)
        #expect(heat.contains { $0.color == pixels[engine.index(5, 5)] })
        #expect(heat.map(\.color) != plain.map(\.color), "the heat view drew the same colours as the material view")

        // And a grain painted in somebody's own colour keeps it.
        engine.setTint(5, 5, PowderEngine.tintWord(red: 250, green: 10, blue: 120))
        pixels.withUnsafeMutableBufferPointer { engine.render(into: $0.baseAddress!, overlay: .normal) }
        #expect(engine.slabCubes(shape: shape).contains { $0.color == pixels[engine.index(5, 5)] })
    }

    @Test("A world too big to draw whole is thinned evenly rather than cut off")
    func aBigWorldIsThinned() {
        let engine = PowderEngine(width: 400, height: 600, seed: 2)
        // Every other row filled, so almost everything is surface: 120,000 grains of shell.
        for y in stride(from: 0, to: 600, by: 2) {
            for x in 0 ..< 400 { engine.setElement(x, y, Element.sand) }
        }
        let surface = engine.surfaceCellCount()
        #expect(surface > 100_000)
        #expect(engine.slabStride() == 1, "a world this size fits whole")
        // Against a smaller ceiling it is thinned, and what comes back is spread over the whole world rather than
        // being the first corner of it.
        let stride = engine.slabStride(limit: 20_000)
        #expect(stride > 1)
        let cubes = engine.slabCubes(shape: PowderSlab.Shape(width: 400, height: 600), every: stride)
        #expect(cubes.count <= 30_000, "\(cubes.count)")
        #expect((cubes.map(\.x).max() ?? 0) > 150 && (cubes.map(\.y).max() ?? 0) > 250, "only one corner was drawn")
        // Never more than the ceiling, whatever is asked for.
        let everything = engine.slabCubes(shape: PowderSlab.Shape(width: 400, height: 600))
        #expect(everything.count <= PowderSlab.mostCubes)
    }

    @Test("An empty world draws nothing, and nonsense is refused rather than crashing")
    func nothingAndNonsense() {
        let engine = world()
        #expect(engine.slabCubes(shape: PowderSlab.Shape(width: 60, height: 40)).isEmpty)
        #expect(engine.surfaceCellCount() == 0)
        // A shape made of nonsense still gives a usable slab.
        let mad = PowderSlab.Shape(width: .nan, height: -5, thickness: .infinity)
        #expect(mad.width == 1 && mad.height == 1 && mad.thickness == 0.1)
        engine.setElement(1, 1, Element.sand)
        #expect(engine.slabCubes(shape: mad).count == 1)
    }
}
