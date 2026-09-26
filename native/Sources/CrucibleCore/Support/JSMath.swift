/// Exact Swift equivalents of the JavaScript numeric operations the simulation
/// depends on.
///
/// Most arithmetic translates between the two languages without comment. These
/// operations do not, and each difference is a silent behavior change rather than
/// a compile error — which is why they are collected here with their reasoning
/// instead of being inlined at each call site.
///
/// The three that matter most:
///
/// - **Rounding halves.** JavaScript's `Math.round` rounds a half *upward*, toward
///   positive infinity: `Math.round(-1.5)` is `-1`. Swift's `rounded()` rounds a
///   half *away from zero*: `(-1.5).rounded()` is `-2`. The movement code rounds
///   negative positions constantly, so using the wrong one makes particles drift
///   differently depending on which way they are travelling.
///
/// - **Storing into narrow integer arrays.** Assigning to a JavaScript
///   `Int8Array` silently truncates and wraps rather than trapping. Swift's
///   `Int8(_:)` traps on overflow. The momentum code multiplies velocities by
///   fractions and stores them back, so values legitimately leave the range.
///
/// - **Storing into `Float32Array`.** The web grid holds temperatures and
///   pressures as 32-bit floats, so every store *rounds*. Arithmetic happens in
///   double precision and only the result is narrowed. Keeping the native grid at
///   double precision throughout would accumulate different values, and the
///   chemistry has hard temperature thresholds — 700°C decides whether lava
///   becomes obsidian — so drift eventually flips real decisions.
public enum JS {
    /// JavaScript's `Math.round`.
    ///
    /// Defined by the language specification as `floor(x + 0.5)`, which rounds a
    /// half toward positive infinity. Swift's own `rounded()` rounds a half away
    /// from zero and disagrees for every negative half.
    @inlinable
    public static func round(_ x: Double) -> Double {
        guard x.isFinite else { return x }
        return (x + 0.5).rounded(.down)
    }

    /// JavaScript's `Math.trunc` — toward zero.
    @inlinable
    public static func trunc(_ x: Double) -> Double {
        guard x.isFinite else { return x }
        return x.rounded(.towardZero)
    }

    /// JavaScript's `Math.sign`: `-1`, `0` or `1`, and not-a-number passed through.
    ///
    /// Returning zero for zero is the part that matters. The engine relies on it
    /// through JavaScript's `||` operator — `Math.sign(g) || fallback` — so that
    /// zero gravity falls through to a per-state default. See
    /// ``signOrFallback(_:fallback:)``.
    @inlinable
    public static func sign(_ x: Double) -> Double {
        if x.isNaN { return x }
        if x > 0 { return 1 }
        if x < 0 { return -1 }
        return x  // preserves -0, as JavaScript does
    }

    /// `Math.sign(x) || fallback`, the idiom the movement code uses to pick a
    /// direction.
    ///
    /// In JavaScript both zero and not-a-number are falsy, so either one selects
    /// the fallback. Writing it out avoids reproducing that subtlety by hand at
    /// each call site.
    @inlinable
    public static func signOrFallback(_ x: Double, fallback: Int) -> Int {
        if x > 0 { return 1 }
        if x < 0 { return -1 }
        return fallback  // covers +0, -0 and not-a-number
    }

    /// JavaScript's `Math.hypot` for two arguments.
    @inlinable
    public static func hypot(_ x: Double, _ y: Double) -> Double {
        (x * x + y * y).squareRoot()
    }

    /// Assignment into an `Int8Array`.
    ///
    /// JavaScript truncates toward zero and then wraps modulo 256 into signed
    /// range; anything not finite becomes zero. Swift's `Int8(_:)` would trap
    /// instead, and the momentum code genuinely produces out-of-range values.
    ///
    /// The reduction happens in floating point before converting, so an
    /// enormous input cannot overflow `Int` on the way through.
    @inlinable
    public static func toInt8(_ value: Double) -> Int8 {
        guard value.isFinite else { return 0 }
        let wrapped = value.rounded(.towardZero).truncatingRemainder(dividingBy: 256)
        return Int8(truncatingIfNeeded: Int(wrapped))
    }

    /// Assignment into a `Uint16Array`: truncate toward zero, wrap modulo 65536,
    /// not-finite becomes zero.
    @inlinable
    public static func toUInt16(_ value: Double) -> UInt16 {
        guard value.isFinite else { return 0 }
        let wrapped = value.rounded(.towardZero).truncatingRemainder(dividingBy: 65536)
        return UInt16(truncatingIfNeeded: Int(wrapped))
    }

    /// JavaScript's `value | 0`: truncate toward zero, wrap modulo 2³² into signed range, not-finite
    /// becomes zero.
    ///
    /// Swift's `Int(_:)` traps on anything past about nine quintillion and on infinity, and several values
    /// that reach this kind of conversion arrive from files or from another phone. One packet claiming a
    /// gravity of 10³⁰⁰ used to be enough to crash the receiver.
    @inlinable
    public static func toInt32(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let wrapped = value.rounded(.towardZero).truncatingRemainder(dividingBy: 4_294_967_296)
        return Int32(truncatingIfNeeded: Int64(wrapped))
    }

    /// A whole number from a double that cannot trap: not-finite becomes `fallback`, and anything outside
    /// the given range is pulled into it before converting.
    @inlinable
    public static func clampedInt(_ value: Double, _ low: Int, _ high: Int, fallback: Int = 0) -> Int {
        guard value.isFinite else { return fallback }
        if value <= Double(low) { return low }
        if value >= Double(high) { return high }
        return Int(value)
    }

    /// Which way a pair of offsets points, in radians, from minus a half turn to a half turn.
    ///
    /// The engine imports no maths library, so it has no inverse tangent of its own. A rational estimate
    /// gets within about a thousandth of a radian, and one Newton step using the engine's own sine and
    /// cosine then takes it to the last few digits — which matters when the answer is used to place a
    /// body on a circle hundreds of pixels across, where a thousandth of a radian is half a pixel out.
    public static func atan2(_ y: Double, _ x: Double) -> Double {
        guard x.isFinite, y.isFinite, x != 0 || y != 0 else { return 0 }
        let absX = Swift.abs(x)
        let absY = Swift.abs(y)
        let ratio = absY < absX ? absY / absX : absX / absY
        let squared = ratio * ratio
        var angle = ((-0.013_480_47 * squared + 0.057_477_314) * squared - 0.121_239_071) * squared
        angle = ((angle + 0.195_635_925) * squared - 0.332_994_597) * squared
        angle = (angle + 0.999_995_630) * ratio
        if absY >= absX { angle = 1.570_796_326_794_896_6 - angle }
        if x < 0 { angle = 3.141_592_653_589_793 - angle }
        if y < 0 { angle = -angle }
        // One Newton step on the angle whose direction is (x, y): the error is the sideways component of
        // (x, y) against the estimate, over its component along it.
        let c = jsCos(angle)
        let s = jsSin(angle)
        let along = x * c + y * s
        if along > 0 { angle += (y * c - x * s) / along }
        return angle
    }

    /// Assignment into a `Float32Array`: narrow to single precision.
    ///
    /// Always narrow on *store* and widen on *load*, computing in between at
    /// double precision, exactly as JavaScript does. Rounding at a different
    /// point produces different temperatures, and the chemistry has hard
    /// thresholds.
    @inlinable
    public static func toFloat32(_ value: Double) -> Float {
        Float(value)
    }
}

extension Int8 {
    /// Reads a velocity component for arithmetic at double precision, mirroring
    /// how JavaScript widens a typed-array element the moment it is read.
    @inlinable
    public var asDouble: Double { Double(self) }
}

extension Float {
    /// Reads a temperature or pressure for arithmetic at double precision.
    @inlinable
    public var asDouble: Double { Double(self) }
}
