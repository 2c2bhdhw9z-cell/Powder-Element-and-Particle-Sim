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

    // MARK: - Repainting from a colour ramp

    /// Where repainting the whole crowd every frame stops being free.
    ///
    /// Two hundred thousand, which measures at about 1.3 milliseconds — noticeable against a frame
    /// budget of 8.3 but not fatal. Below it the pass disappears into the noise; above it the figures
    /// climb steadily to 6.4 milliseconds at a million, which is most of a frame spent on colour.
    public static let repaintBudget = 200_000

    /// Roughly what one repaint costs, in milliseconds.
    ///
    /// Measured: 0.17ms at twenty-five thousand, 0.66 at a hundred thousand, 3.24 at five hundred
    /// thousand, 6.42 at a million. That is about 6.4 microseconds per thousand bodies and it stays
    /// linear, because the pass is one sweep of three arrays with a table lookup — nothing about it
    /// depends on how the bodies are arranged.
    public static func repaintMilliseconds(bodies: Int) -> Double {
        guard bodies > 0 else { return 0 }
        return Double(bodies) / 1000 * 0.0064
    }

    /// What to say about a colour ramp that has to be reapplied every frame, or `nil`.
    ///
    /// Only for the ramps that actually move. Speed and crowding change from frame to frame, so every
    /// body has to be looked at again; a fixed colour per body, or a colour from where a body sits in a
    /// still world, is painted once and left alone. The engine already makes that distinction — this is
    /// how it gets said out loud, because a whole frame of colour work at a million bodies is exactly
    /// the sort of cost that otherwise gets discovered as "it went slow when I changed the colours".
    public static func repaintWarning(bodies: Int, ramp: Bool, rampMoves: Bool) -> String? {
        guard ramp, rampMoves, bodies > repaintBudget else { return nil }
        let cost = repaintMilliseconds(bodies: bodies)
        return "A ramp driven by speed or crowding has to repaint all "
            + "\(bodies.formattedWithSeparators) bodies every frame, which costs about "
            + "\(String(tenths: cost))ms on its own. Colouring by Own, Place, Charge or Life is painted "
            + "once and costs nothing after that."
    }

    // MARK: - The liquid, and the pull between bodies

    /// How many bodies of liquid a world that size actually holds.
    ///
    /// This is the most useful thing to be able to say about the fluid, and it is not a performance
    /// figure — it is a fact about the settings. The rest crowding is mass per square pixel, so the area
    /// divided by it is how many bodies fit at the spacing the fluid is trying to keep. Ask for more than
    /// that and the fluid is not slow, it is impossible: there is nowhere for the bodies to go, so they
    /// stay squashed, every one of them has far more neighbours than the fluid was tuned for, and the
    /// cost climbs for a picture that is wrong anyway.
    ///
    /// A phone-sized field holds around ten thousand. That is a real, explainable limit, which is worth
    /// far more than a threshold picked to make the numbers look acceptable.
    public static func fluidCapacity(width: Double, height: Double, restDensity: Double) -> Int {
        guard width > 0, height > 0, restDensity > 0,
              width.isFinite, height.isFinite, restDensity.isFinite
        else { return 0 }
        return Int(width * height * restDensity)
    }

    /// Roughly what one moment of liquid costs, in milliseconds.
    ///
    /// Measured on the test machine, with the crowd settled first: 16ms at ten thousand, 79 at
    /// twenty-five thousand, 206 at fifty thousand, 450 at a hundred thousand. Not a straight line,
    /// because past the point where the world is full the bodies are squashed together and every one of
    /// them has more neighbours to compare itself against — so the cost grows faster than the crowd.
    /// Roughly the square of it, which is what the fit below says.
    public static func fluidMilliseconds(bodies: Int) -> Double {
        guard bodies > 0 else { return 0 }
        let thousands = Double(bodies) / 1000
        // About a millisecond per thousand while there is room, plus a term that takes over once there
        // is not.
        return thousands * 0.95 + thousands * thousands * 0.021
    }

    /// Roughly what one moment of pull between bodies costs, in milliseconds.
    ///
    /// Measured: 12ms at ten thousand, 32 at twenty-five thousand, 62 at fifty thousand, 116 at a
    /// hundred thousand, 227 at two hundred thousand. Very nearly a straight line, which is the point of
    /// how it is worked out — the expensive part is done once per square rather than once per body, so
    /// its cost does not grow with the crowd at all and what is left does.
    public static func bodyGravityMilliseconds(bodies: Int) -> Double {
        guard bodies > 0 else { return 0 }
        // A fixed cost for comparing every square with every other, plus a little over a millisecond
        // per thousand bodies for the near neighbours.
        return 1.5 + Double(bodies) / 1000 * 1.12
    }

    /// Where the liquid stops being smooth enough to be worth having.
    ///
    /// Sixteen milliseconds, which is sixty frames a second — the same line the collision budget is drawn
    /// at, and for the same reason: below it the field feels like a liquid, above it like a slideshow.
    public static let smoothMilliseconds = 16.0

    /// What to say about the liquid, or `nil` when there is nothing worth saying.
    ///
    /// Two different things, and which one matters depends on why there is a problem. Too much liquid for
    /// the world is a fact about the settings and has a proper answer — fewer bodies, or a looser rest
    /// spacing. Merely slow is a performance figure. Saying "this is slow" when the real problem is "you
    /// have asked for four times more water than the container holds" would send somebody looking in
    /// entirely the wrong place.
    public static func fluidWarning(
        bodies: Int,
        fluid: Bool,
        width: Double,
        height: Double,
        restDensity: Double
    ) -> String? {
        guard fluid, bodies > 0 else { return nil }

        let capacity = fluidCapacity(width: width, height: height, restDensity: restDensity)
        if capacity > 0, bodies > capacity * 5 / 4 {
            return "A field this size holds about \(capacity.formattedWithSeparators) bodies of liquid at "
                + "the spacing it is set to keep, and there are \(bodies.formattedWithSeparators). The "
                + "extra have nowhere to go, so they stay squashed — which both looks wrong and costs "
                + "more than it should. Fewer bodies, or a looser spacing, and it will settle."
        }

        let cost = fluidMilliseconds(bodies: bodies)
        guard cost > smoothMilliseconds else { return nil }
        let frames = cost > 0 ? Int((1000 / cost).rounded()) : 0
        return "Liquid over \(bodies.formattedWithSeparators) bodies costs about "
            + "\(Int(cost.rounded()))ms a moment — roughly \(frames) frames a second. It is two passes "
            + "over every body's neighbours, so the cost follows how tightly packed they are."
    }

    /// What to say about the pull between bodies, or `nil`.
    public static func bodyGravityWarning(bodies: Int, gravity: Bool) -> String? {
        guard gravity, bodies > 0 else { return nil }
        let cost = bodyGravityMilliseconds(bodies: bodies)
        guard cost > smoothMilliseconds else { return nil }
        let frames = cost > 0 ? Int((1000 / cost).rounded()) : 0
        return "Gravity between \(bodies.formattedWithSeparators) bodies costs about "
            + "\(Int(cost.rounded()))ms a moment — roughly \(frames) frames a second. Under "
            + "\(SwarmGravity.exactBelow.formattedWithSeparators) bodies it is worked out exactly; above "
            + "that, distant groups are treated as single lumps, which is what keeps it this affordable."
    }
}

extension String {
    /// A number written to one decimal place.
    ///
    /// By hand, because the engine has no Foundation and so no formatter. Rounded first so that 6.44
    /// reads as 6.4 rather than as 6.4000000000000004, which is what plain interpolation gives.
    init(tenths value: Double) {
        guard value.isFinite else {
            self = "0.0"
            return
        }
        let scaled = Int((value * 10).rounded())
        let whole = abs(scaled) / 10
        let fraction = abs(scaled) % 10
        self = (scaled < 0 ? "-" : "") + "\(whole).\(fraction)"
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
