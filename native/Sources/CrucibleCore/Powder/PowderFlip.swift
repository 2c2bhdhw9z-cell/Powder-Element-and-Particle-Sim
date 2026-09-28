/// Turning the whole world upside down, as you would turn an hourglass over.
extension PowderEngine {
    /// Turns the world upside down: the top row becomes the bottom one, and everything in it with it.
    ///
    /// Every grain keeps what it is, how hot it is, how long it has left, its own colour and the pressure around
    /// it — only its place changes. Gravity is not touched, which is the point: what was resting on the floor is now
    /// hanging from the ceiling, and falls. Turned over twice, the world is exactly as it was.
    ///
    /// Two things are turned over with it rather than simply moved:
    ///
    /// - Anything moving up or down is now moving the other way, as it would be if the world had been picked up
    ///   and turned.
    /// - A fan pointing down now points up, and one pointing up points down. A fan keeps its direction in its
    ///   lifetime, so moving it without turning it would leave it blowing into what used to be the floor.
    public func flipUpsideDown() {
        guard width > 0, height > 1 else { return }
        for top in 0 ..< height / 2 {
            let bottom = height - 1 - top
            for x in 0 ..< width {
                let a = top * width + x
                let b = bottom * width + x
                exchangeForFlip(a, b)
            }
        }
        // The middle row of an odd-height world stays where it is, but what moves in it and which way its fans
        // point still turn over.
        if height % 2 == 1 {
            let middle = height / 2
            for x in 0 ..< width { turnOver(middle * width + x) }
        }
        flipPeopleUpsideDown()
    }

    /// Swaps two cells completely and turns both over. Unlike ``swapCells(_:_:)`` it marks nothing as moved: this
    /// happens between moments, not during one.
    private func exchangeForFlip(_ a: Int, _ b: Int) {
        (type[a], type[b]) = (type[b], type[a])
        (temperature[a], temperature[b]) = (temperature[b], temperature[a])
        (life[a], life[b]) = (life[b], life[a])
        (velocityX[a], velocityX[b]) = (velocityX[b], velocityX[a])
        (velocityY[a], velocityY[b]) = (velocityY[b], velocityY[a])
        (pressure[a], pressure[b]) = (pressure[b], pressure[a])
        (tint[a], tint[b]) = (tint[b], tint[a])
        turnOver(a)
        turnOver(b)
    }

    /// Reverses what is moving up or down in one cell, and which way a fan in it points.
    private func turnOver(_ i: Int) {
        let rising = velocityY[i]
        // The most negative byte has no positive twin, so it becomes the most positive one rather than overflowing.
        velocityY[i] = rising == Int8.min ? Int8.max : -rising
        if type[i] == Element.fan {
            // Right, down, left, up: down and up change places, right and left stay.
            switch Int(life[i]) % 4 {
            case 1: life[i] = 3
            case 3: life[i] = 1
            default: break
            }
        }
    }
}
