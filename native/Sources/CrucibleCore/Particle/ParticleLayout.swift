/// Where arrangements are laid out, and what a finger's forces are measured against.
///
/// ## Why arrangements are laid out on the screen rather than in the whole world
///
/// Zooming out makes the world larger, so there is more room. Every arrangement used to be laid out to fill
/// the whole world, so choosing one after zooming out simply filled the new room up again — and the ones that
/// scale with the world laid their bodies out larger to match. Zooming out to get room, then choosing a
/// galaxy, gave a galaxy exactly as big as the screen with bigger stars, which is the opposite of room.
///
/// So arrangements are laid out on a region the size of the screen, in the middle of the world, and are the
/// same size whether or not the world has grown. The ones that stand on the floor — a pool, a fire — stand
/// on the world's floor, and the ones that hang from the top hang from its top. With the world the size of
/// the screen, which is how every recorded comparison and test runs, the region is the whole world and
/// nothing is laid out differently at all.
extension ParticleEngine {
    /// The width of the screen the field is shown on, in the world's pixels at no zoom. Nought until the app
    /// says, which means the whole world.
    public var screenWidth: Double {
        get { storedScreenWidth }
        set { storedScreenWidth = newValue.isFinite ? max(0, newValue) : 0 }
    }

    /// The height of that screen. See ``screenWidth``.
    public var screenHeight: Double {
        get { storedScreenHeight }
        set { storedScreenHeight = newValue.isFinite ? max(0, newValue) : 0 }
    }

    /// The width of the region arrangements are laid out in.
    var layoutWidth: Double {
        storedScreenWidth > 0 ? min(width, storedScreenWidth) : width
    }

    /// The height of that region.
    var layoutHeight: Double {
        storedScreenHeight > 0 ? min(height, storedScreenHeight) : height
    }

    /// Where the region starts across the world. It is centred, so this is half the room either side.
    var layoutLeft: Double { (width - layoutWidth) * 0.5 }

    /// Where it starts down the world.
    var layoutTop: Double { (height - layoutHeight) * 0.5 }

    /// A place across the region: nought at its left edge, one at its right.
    func across(_ fraction: Double) -> Double { layoutLeft + layoutWidth * fraction }

    /// A place down the region, which sits in the middle of the world: nought at its top, one at its bottom.
    func down(_ fraction: Double) -> Double { layoutTop + layoutHeight * fraction }

    /// A place down a region the screen's height standing on the world's floor. For what stands on the ground.
    func aboveFloor(_ fraction: Double) -> Double { height - layoutHeight * (1 - fraction) }

    /// A place down a region the screen's height hanging from the world's top. For what hangs or falls.
    func belowCeiling(_ fraction: Double) -> Double { layoutHeight * fraction }

    /// One screen height, in the world's pixels: what a finger's forces are measured against.
    ///
    /// Helion measures its brush in screen heights, and that is why its tools feel the same on any screen.
    /// Measured against the screen rather than the world, so a world grown by zooming out does not make the
    /// finger stronger.
    public var brushUnit: Double {
        storedScreenHeight > 0 ? storedScreenHeight : height
    }
}
