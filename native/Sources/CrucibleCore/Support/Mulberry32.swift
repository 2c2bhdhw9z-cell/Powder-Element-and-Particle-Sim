/// A seedable pseudo-random generator, bit-for-bit identical to the `mulberry32`
/// implementation used by the web reference implementation
/// (`web/src/sim/__tests__/helpers.ts`).
///
/// ## Why this exists rather than `SystemRandomNumberGenerator`
///
/// The web engine calls the global `Math.random()` everywhere, and its test
/// suite monkey-patches that global to make runs reproducible. Reproducing that
/// trick here would be both slow (every draw an opaque global call) and fragile.
///
/// Instead the generator is a plain value type that the engine stores inline.
/// That gives us three properties the web version only has in its tests:
///
/// - **Determinism in production, not just under test.** A world plus a seed
///   replays exactly. That is the foundation the daily-seed feature, scene
///   sharing and any future lockstep multiplayer all need.
/// - **Speed.** Every member is `@inlinable` and operates on a single `UInt32`,
///   so draws compile down to a handful of register operations with no
///   allocation, no existential dispatch and no global state.
/// - **Bit-exact agreement with the oracle.** The ported test suite can only
///   verify the physics if both implementations consume the same number stream.
///
/// ## Fidelity contract
///
/// Every helper on this type consumes **exactly one** draw and mirrors the
/// corresponding JavaScript expression exactly, including rounding. When
/// porting engine code, match the helper to the JavaScript idiom rather than
/// rewriting the arithmetic — the number of draws and their order is part of the
/// observable behavior.
public struct Mulberry32: Sendable, Hashable {
    /// The full internal state. Exposed so a run can be snapshotted and resumed
    /// (needed for undo, replay and save files), and so the type stays
    /// `@inlinable`.
    public var state: UInt32

    /// Creates a generator from a seed. Every seed is valid, including zero.
    @inlinable
    public init(seed: UInt32) {
        self.state = seed
    }

    /// Creates a generator seeded from the system's random source, for
    /// production use where reproducibility is not wanted.
    @inlinable
    public init() {
        self.state = UInt32.random(in: UInt32.min ... UInt32.max)
    }

    /// Advances the stream and returns the raw 32 bits.
    ///
    /// The wrapping operators (`&+`, `&*`) reproduce JavaScript's `| 0` integer
    /// coercion and `Math.imul`; the unsigned shifts reproduce `>>>`. Because
    /// the bit patterns agree, so do the results.
    @inlinable
    public mutating func nextBits() -> UInt32 {
        state = state &+ 0x6d2b_79f5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return t ^ (t >> 14)
    }

    /// A value in `0 ..< 1`. Equivalent to `Math.random()`.
    ///
    /// The scale factor is a power of two and therefore exactly representable,
    /// so multiplying matches JavaScript's division result bit for bit while
    /// avoiding the divide.
    @inlinable
    public mutating func next() -> Double {
        Double(nextBits()) * (1.0 / 4_294_967_296.0)
    }

    /// An integer in `0 ..< bound`. Equivalent to
    /// `Math.floor(Math.random() * bound)`.
    ///
    /// Returns zero for a non-positive bound, matching JavaScript's behavior
    /// rather than trapping, because the engine computes bounds from live state.
    @inlinable
    public mutating func int(below bound: Int) -> Int {
        guard bound > 0 else {
            _ = nextBits()
            return 0
        }
        // The product is non-negative, so truncation and `floor` agree.
        return Int(next() * Double(bound))
    }

    /// One of `-1`, `0`, `1`. Equivalent to
    /// `Math.floor(Math.random() * 3) - 1`, the web engine's idiom for picking a
    /// random horizontal nudge.
    @inlinable
    public mutating func nudge() -> Int {
        int(below: 3) - 1
    }

    /// Either `-1` or `1`. Equivalent to `Math.random() < 0.5 ? -1 : 1`.
    @inlinable
    public mutating func sign() -> Int {
        next() < 0.5 ? -1 : 1
    }

    /// `true` with the given probability. Equivalent to
    /// `Math.random() < probability`.
    @inlinable
    public mutating func chance(_ probability: Double) -> Bool {
        next() < probability
    }

    /// `true` with the given percentage likelihood. Equivalent to
    /// `Math.random() * 100 < percent`, which is how the registry's
    /// `flammability` and `acidResistance` values are consumed.
    ///
    /// Kept separate from ``chance(_:)`` even though the two are mathematically
    /// equivalent, so ported code reads like the original and the scale of the
    /// stored property stays obvious at the call site.
    @inlinable
    public mutating func percentChance(_ percent: Double) -> Bool {
        next() * 100 < percent
    }

    /// A value in `-1 ..< 1`. Equivalent to `Math.random() * 2 - 1`.
    @inlinable
    public mutating func signedUnit() -> Double {
        next() * 2 - 1
    }

    /// A value in `lower ..< upper`. Equivalent to
    /// `lower + Math.random() * (upper - lower)`.
    @inlinable
    public mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + next() * (upper - lower)
    }
}
