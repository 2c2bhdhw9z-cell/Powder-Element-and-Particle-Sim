// What a crowd of bodies actually costs, and when to say so.
//
// ## Why this is written down rather than left to be discovered
//
// The field offers up to a million bodies. Measured on the machine that runs the tests — about 1.2×
// slower than the phone — one moment of simulation costs:
//
// | bodies  | pushing apart | not pushing apart |
// | ------- | ------------- | ----------------- |
// | 50,000  | **55 ms**     | 0.2 ms            |
// | 100,000 | **114 ms**    | 0.4 ms            |
// | 200,000 | **201 ms**    | 0.8 ms            |
// | 500,000 | **273 ms**    | 2.1 ms            |
//
// Two hundred milliseconds is five frames a second. Without collisions the same crowd costs under a
// millisecond — the difference is a factor of two hundred and fifty.
//
// ## And it is not an implementation fault
//
// Worth stating, because the obvious next move is to go and optimise it. The pass is already bounded:
// a uniform grid, nine neighbouring cells, at most eight candidates examined per cell. It comes out at
// roughly seven nanoseconds per candidate, which for reads scattered across a megabyte and a half is
// about what the memory can do.
//
// Laying the bodies out in the order the grid visits them would help — perhaps three times — and it
// would also change the order pairs are resolved in, which changes the simulation. Even then two
// hundred thousand bodies each overlapping dozens of others, resolved twice a frame, is not a
// hundred-and-twenty-frame workload. There is no version of this that is both that crowded and smooth.
//
// So the honest thing is not to pretend. The app offers the crowd *and* says what it will cost, and
// when the two settings together cannot work it says so plainly and offers the one tap that fixes it.

/// What a crowd of bodies costs, and what to say about it.
public enum SwarmCost {
    /// Where pushing bodies apart stops being affordable.
    ///
    /// Sixteen thousand, which is where a moment reaches about sixteen milliseconds — sixty frames a
    /// second, and the last point at which the field still feels like a fluid rather than a slideshow.
    /// Above it the figures climb straight past: twenty-five thousand is already twenty-one
    /// milliseconds, and fifty thousand is fifty-eight.
    ///
    /// Every preset in the app spawns a few hundred, so none of them ever trips this. One tap of
    /// "Add 10k" does not either. Two does, which is exactly when somebody should be told.
    public static let collisionBudget = 16_000

    /// Whether this combination of crowd and collisions can run smoothly.
    public static func isAffordable(bodies: Int, collisions: Bool) -> Bool {
        !collisions || bodies <= collisionBudget
    }

    /// Roughly what one moment will cost, in milliseconds.
    ///
    /// Straight-line fits to the measurements above rather than anything clever. It is here so the
    /// interface can show a number that turns out to be true, instead of an adjective.
    public static func estimatedMilliseconds(bodies: Int, collisions: Bool) -> Double {
        guard bodies > 0 else { return 0 }
        let thousands = Double(bodies) / 1000
        guard collisions else {
            // About four microseconds per thousand bodies, and it stays linear all the way up.
            return thousands * 0.004
        }
        // About a millisecond per thousand up to the point where only every other body is resolved,
        // after which it flattens out.
        return bodies > 250_000 ? 240 + thousands * 0.07 : thousands * 1.05
    }

    /// What to tell somebody, or `nil` when there is nothing worth saying.
    ///
    /// The number is included deliberately. "This may be slow" is an adjective somebody can disagree
    /// with; "about 200 milliseconds a moment, which is 5 frames a second" is a fact they can act on.
    public static func warning(bodies: Int, collisions: Bool) -> String? {
        guard collisions, bodies > collisionBudget else { return nil }
        let cost = estimatedMilliseconds(bodies: bodies, collisions: collisions)
        let frames = cost > 0 ? Int((1000 / cost).rounded()) : 0
        return "With \(bodies.formattedWithSeparators) bodies pushing each other apart, one moment costs "
            + "about \(Int(cost.rounded()))ms — roughly \(frames) frames a second. Switching Collide off "
            + "brings that under a millisecond and changes nothing else."
    }
}

extension Int {
    /// Digits grouped with commas.
    ///
    /// By hand because the engine has no Foundation, and because the alternative — handing the interface
    /// a bare `200000` — is a number nobody reads at a glance.
    public var formattedWithSeparators: String {
        let digits = Array(String(self < 0 ? -self : self))
        var out = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return (self < 0 ? "-" : "") + out
    }
}
