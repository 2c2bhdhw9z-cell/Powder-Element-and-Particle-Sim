// The world everybody gets today.
//
// Ported from web/src/sim/daily-seed.ts.
//
// One scene a day, the same for everyone, chosen by hashing the date. It costs nothing to run and it
// is the only thing in the lab that is shared — two people on opposite sides of the world comparing
// what they did with the same starting point.
//
// ## Why the date is passed in
//
// This module cannot read a clock: the engine imports nothing, not even Foundation. That turns out to
// be exactly right rather than merely necessary — a feature whose whole point is "the same for
// everyone on a given day" is one you want to be able to test on an arbitrary day, and a function
// that reads the clock itself cannot be.

/// Choosing the day's world.
public enum DailyWorld {
    /// What the day's powder scene and particle arrangement turned out to be.
    public struct Choice: Sendable, Hashable {
        /// The day it was chosen for, as `YYYY-MM-DD`.
        public var day: String
        /// The scene or arrangement's name, for showing on a chip.
        public var name: String
        /// The hash the choice came from, which is what makes it reproducible.
        public var hash: UInt32
    }

    /// The arrangements the daily particle field chooses between.
    ///
    /// A shorter list than the full set on purpose: these are the ones that look like something the
    /// moment they appear, rather than needing to be interfered with first.
    public static let particlePresets = [
        "galaxy", "blackhole", "vortex", "flare", "fountain", "synchrotron", "waterfall",
    ]

    // MARK: The hash

    /// A hash of a string, the FNV-1a way.
    ///
    /// Not chosen for any cryptographic property — it just has to scatter consecutive dates across
    /// different scenes, which a simpler sum would not. Arithmetic is 32-bit and wraps, matching the
    /// reference's `Math.imul` exactly.
    public static func hash(of text: String) -> UInt32 {
        var value: UInt32 = 2_166_136_261
        // Over UTF-16 code units, which is what the reference's `charCodeAt` gives. For a date every
        // character is plain ASCII, so this is the same as walking the bytes — but being explicit
        // means a caller passing something else does not quietly diverge.
        for unit in text.utf16 {
            value ^= UInt32(unit)
            value = value &* 16_777_619
        }
        return value
    }

    /// The hash for one day.
    public static func hash(forDay day: String) -> UInt32 {
        hash(of: "crucible:\(day)")
    }

    // MARK: Powder

    /// Which scene the day gets.
    public static func powderRecipe(forDay day: String) -> PowderRecipe {
        let value = hash(forDay: day)
        // The scene list's order is part of this: reordering it changes which scene a given day gets,
        // and two people on different versions would then disagree about the shared daily.
        let index = Int(value % UInt32(powderRecipes.count))
        return powderRecipes[index]
    }

    /// Lays out the day's scene.
    ///
    /// The generator is seeded from the day rather than left to chance. One of the thirteen scenes
    /// scatters its material at random, and in the reference that scene read the global random
    /// source — so on roughly one day in thirteen the "daily" world, whose entire point is that
    /// everyone gets the same one, was different for every player while the interface went on
    /// announcing it by name. Seeding from the day is the fix, and it is why this takes a day at all.
    @discardableResult
    public static func applyPowder(forDay day: String, to engine: PowderEngine) -> Choice {
        let value = hash(forDay: day)
        let recipe = powderRecipe(forDay: day)
        var generator = Mulberry32(seed: value)
        recipe.apply(to: engine, random: &generator)
        return Choice(day: day, name: recipe.name, hash: value)
    }

    // MARK: Particles

    /// Which arrangement the day gets.
    ///
    /// Shifted eight bits before being reduced, so the two chambers do not move in step — otherwise a
    /// given day's scene would always come with the same arrangement, and the pairings would repeat
    /// every thirteen days instead of feeling like a fresh combination.
    public static func particlePreset(forDay day: String) -> String {
        let value = hash(forDay: day)
        let index = Int((value >> 8) % UInt32(particlePresets.count))
        return particlePresets[index]
    }

    /// Fills the field with the day's arrangement.
    ///
    /// Seeded from the day, like the powder scene. It used to draw from whatever state the field's random
    /// stream happened to be in, so two people opening the same day's arrangement got two different fields
    /// while the chip told both of them it was the shared one.
    @discardableResult
    public static func applyParticle(forDay day: String, to engine: ParticleEngine) -> Choice {
        let value = hash(forDay: day)
        let preset = particlePreset(forDay: day)
        engine.rng = Mulberry32(seed: value ^ 0x9E37_79B9)
        engine.loadArrangement(preset)
        return Choice(day: day, name: preset, hash: value)
    }
}
