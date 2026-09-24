// Sine, cosine and powers, computed identically on every platform.
//
// ## Why this file exists
//
// The physics in this engine is verified against the web reference implementation by
// running the same world in both and comparing every body. That comparison is only
// meaningful if both sides agree exactly, and they do not agree if each defers to its
// host's C maths library:
//
//   - JavaScript engines do not use the host's library. V8 carries its own port of
//     Sun's Freely Distributable Math Library (fdlibm) precisely so that results are
//     identical on every operating system and processor.
//   - Swift has no `sin` of its own, so it calls the platform's. On Linux that is
//     glibc; on Apple platforms it is Darwin's. These differ from each other, and both
//     differ from fdlibm.
//
// Measured against V8 over four thousand arguments drawn the way the presets draw
// them, glibc disagreed on 3.3% of sines, 3.5% of cosines and 7.8% of powers. Always
// by a single unit in the last place — the smallest possible difference — which sounds
// harmless and is not. The particle presets are orbits: a body's position feeds the
// force on it, which feeds its next position. In that loop a last-bit difference
// doubles every few steps, so after a couple of hundred frames two runs that started
// identical are visibly different pictures.
//
// That has two consequences, and the second is the serious one:
//
//   1. Cross-checking the port against the web would need a tolerance, and a tolerance
//      cannot tell a genuine porting mistake from a last-bit difference that grew. The
//      verification would stop proving anything for exactly the chaotic scenes where
//      proof is most wanted.
//   2. Verifying on the Linux test host would say nothing about the iPhone, because
//      Darwin's library is a third implementation again. The physics would be checked
//      on one machine and shipped on another.
//
// So the engine brings its own. These are ports of fdlibm's `__ieee754_*` routines —
// the same algorithms V8 uses — written against the published public-domain sources
// from Sun. Every one is checked bit-for-bit against recorded JavaScript output in
// `FDLibmTests`; that test, not this comment, is what establishes they are right.
//
// A side benefit worth stating: once the engine owns these, its physics is pinned
// forever. Chromium is currently considering moving V8 onto LLVM's maths library,
// which would change JavaScript's answers. It cannot change ours.
//
// ## Scope
//
// Only what the simulation calls: `sin`, `cos` and `pow`, plus the argument reduction
// and scaling they need. `sqrt` is absent deliberately — the IEEE 754 standard
// requires it to be correctly rounded, so every implementation already agrees and the
// standard library's is both exact and hardware-accelerated.
//
// ## One honest caveat about `pow`
//
// `sin` and `cos` here reproduce V8 exactly, on every one of the several thousand
// recorded arguments. `pow` does not, and cannot: V8 uses fdlibm for the trigonometry
// but a more accurate power function of its own. That was not a guess — the same
// algorithm was transcribed into JavaScript and run inside V8 against V8's own
// `Math.pow`, and the two disagreed on about 4% of arguments by one step in the last
// place, the same rate this file disagrees. So the gap is V8 being more accurate, not
// this being wrong, and no further work here would close it.
//
// That is fine, because agreeing with a browser was never the goal — computing the same
// answer on every device was, and this does. The residual gap also provably changes
// nothing: `pow` is called in exactly one place in the whole engine, the explosion
// falloff, whose result is rounded to a whole number before it is stored. The golden
// powder scenarios, several of which detonate charges, match the web engine cell for
// cell with this implementation in place.
//
// ## Reading this code
//
// It is deliberately a close transcription rather than an idiomatic rewrite, because
// its only job is to reproduce another implementation exactly and a transcription can
// be checked against the original line by line. Hence the terse names, the magic
// constants and the bit fiddling. The structure is:
//
//   - `Bits`             raw access to the halves of a `Double`
//   - `fdScalbn`         multiply by a power of two
//   - `kernelSin/Cos`    polynomial cores, valid on a narrow interval around zero
//   - `remainderPiOver2` reduce any argument onto that interval
//   - `jsSin/jsCos/jsPow` the entry points the physics calls

// MARK: - Raw bit access

/// The halves of a `Double`, named as the original sources name them.
///
/// fdlibm works on the two 32-bit words of a double directly, testing exponent ranges
/// by integer comparison and building results by assembling words. These helpers keep
/// that possible without scattering shifts through the algorithms.
private enum Bits {
    /// The top 32 bits, signed — sign bit, exponent, and the high mantissa bits.
    @inline(__always)
    static func high(_ x: Double) -> Int32 {
        Int32(bitPattern: UInt32(truncatingIfNeeded: x.bitPattern >> 32))
    }

    /// The bottom 32 bits of the mantissa.
    @inline(__always)
    static func low(_ x: Double) -> UInt32 {
        UInt32(truncatingIfNeeded: x.bitPattern)
    }

    /// `x` with its top 32 bits replaced.
    @inline(__always)
    static func settingHigh(_ x: Double, _ high: Int32) -> Double {
        Double(bitPattern: UInt64(UInt32(bitPattern: high)) << 32 | UInt64(low(x)))
    }

    /// `x` with its bottom 32 bits replaced.
    @inline(__always)
    static func settingLow(_ x: Double, _ low: UInt32) -> Double {
        Double(bitPattern: x.bitPattern & 0xFFFF_FFFF_0000_0000 | UInt64(low))
    }

    /// Builds a double from both halves.
    @inline(__always)
    static func assemble(high: Int32, low: UInt32) -> Double {
        Double(bitPattern: UInt64(UInt32(bitPattern: high)) << 32 | UInt64(low))
    }
}

/// Truncation toward zero, as a C cast to `int32_t` performs it.
///
/// C leaves an out-of-range conversion undefined; the algorithms here never produce
/// one, but Swift would trap rather than quietly misbehave, so the range is clamped.
@inline(__always)
private func toInt32(_ value: Double) -> Int32 {
    if value.isNaN { return 0 }
    let truncated = value < 0 ? value.rounded(.up) : value.rounded(.down)
    if truncated >= 2_147_483_647 { return .max }
    if truncated <= -2_147_483_648 { return .min }
    return Int32(truncated)
}

/// `x` with the sign of `y`.
@inline(__always)
private func fdCopysign(_ x: Double, _ y: Double) -> Double {
    Double(bitPattern: x.bitPattern & 0x7FFF_FFFF_FFFF_FFFF | y.bitPattern & 0x8000_0000_0000_0000)
}

// MARK: - scalbn

/// `x` multiplied by two raised to `n`, computed by adjusting the exponent field.
///
/// A port of fdlibm's `s_scalbn.c`. Written out rather than delegated to the platform
/// so that this file depends on nothing outside the Swift standard library.
func fdScalbn(_ x: Double, _ n: Int32) -> Double {
    let two54 = 1.80143985094819840000e+16
    let twom54 = 5.55111512312578270212e-17
    let hugeValue = 1.0e300
    let tinyValue = 1.0e-300

    var x = x
    var hx = Bits.high(x)
    let lx = Bits.low(x)
    var k = (hx & 0x7FF0_0000) >> 20

    if k == 0 {
        // Zero or subnormal: scale up into the normal range first, then correct.
        if lx | UInt32(bitPattern: hx & 0x7FFF_FFFF) == 0 { return x }
        x *= two54
        hx = Bits.high(x)
        k = ((hx & 0x7FF0_0000) >> 20) - 54
        if n < -50000 { return tinyValue * x }
    }
    if k == 0x7FF { return x + x } // Not a number, or infinite.
    k = k &+ n
    if k > 0x7FE { return hugeValue * fdCopysign(hugeValue, x) }
    if k > 0 {
        return Bits.settingHigh(x, hx & Int32(bitPattern: 0x800F_FFFF) | k << 20)
    }
    if k <= -54 {
        // Guarded against `n` being large enough that `k + n` wrapped.
        return n > 50000
            ? hugeValue * fdCopysign(hugeValue, x)
            : tinyValue * fdCopysign(tinyValue, x)
    }
    k = k &+ 54 // Subnormal result.
    return Bits.settingHigh(x, hx & Int32(bitPattern: 0x800F_FFFF) | k << 20) * twom54
}

// MARK: - Polynomial kernels

/// Sine on `|x| <= pi/4`, as fdlibm's `k_sin.c`.
///
/// - Parameters:
///   - x: The reduced argument.
///   - y: The tail of the reduced argument — the part that did not fit in `x`.
///   - iy: Zero when `y` is known to be zero, which skips the correction term.
private func kernelSin(_ x: Double, _ y: Double, _ iy: Int32) -> Double {
    // Written exactly as the original spells them, with no digit grouping. Grouping
    // these by threes is how a dropped digit hides: an early draft of this file had
    // one 3 too few in S2 and every sine in the program was quietly wrong.
    let half = 0.5
    let S1 = -1.66666666666666324348e-01
    let S2 = 8.33333333332248946124e-03
    let S3 = -1.98412698298579493134e-04
    let S4 = 2.75573137070700676789e-06
    let S5 = -2.50507602534068634195e-08
    let S6 = 1.58969099521155010221e-10

    let ix = Bits.high(x) & 0x7FFF_FFFF
    if ix < 0x3E40_0000 { // |x| < 2**-27
        if toInt32(x) == 0 { return x }
    }
    let z = x * x
    let v = z * x
    let r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
    if iy == 0 {
        return x + v * (S1 + z * r)
    }
    return x - ((z * (half * y - v * r) - y) - v * S1)
}

/// Cosine on `|x| <= pi/4`, as fdlibm's `k_cos.c`.
private func kernelCos(_ x: Double, _ y: Double) -> Double {
    let one = 1.0
    let C1 = 4.16666666666666019037e-02
    let C2 = -1.38888888888741095749e-03
    let C3 = 2.48015872894767294178e-05
    let C4 = -2.75573143513906633035e-07
    let C5 = 2.08757232129817482790e-09
    let C6 = -1.13596475577881948265e-11

    let ix = Bits.high(x) & 0x7FFF_FFFF
    if ix < 0x3E40_0000 { // |x| < 2**-27
        if toInt32(x) == 0 { return one }
    }
    let z = x * x
    let r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
    if ix < 0x3FD3_3333 { // |x| < 0.3
        return one - (0.5 * z - (z * r - x * y))
    }
    let qx: Double
    if ix > 0x3FE9_0000 { // |x| > 0.78125
        qx = 0.281_25
    } else {
        // x/4, built by lowering the exponent rather than dividing.
        qx = Bits.assemble(high: ix - 0x0020_0000, low: 0)
    }
    let hz = 0.5 * z - qx
    let a = one - qx
    return a - (hz - (z * r - x * y))
}

// MARK: - Argument reduction

/// The first 66 words of `2/pi` in 24-bit pieces, for reducing huge arguments.
///
/// From fdlibm's `e_rem_pio2.c`. Enough precision that the reduction stays exact for
/// every finite double.
private let twoOverPi: [Int32] = [
    0xA2_F983, 0x6E_4E44, 0x15_29FC, 0x27_57D1, 0xF5_34DD, 0xC0_DB62,
    0x95_993C, 0x43_9041, 0xFE_5163, 0xAB_DEBB, 0xC5_61B7, 0x24_6E3A,
    0x42_4DD2, 0xE0_0649, 0x2E_EA09, 0xD1_921C, 0xFE_1DEB, 0x1C_B129,
    0xA7_3EE8, 0x82_35F5, 0x2E_BB44, 0x84_E99C, 0x70_26B4, 0x5F_7E41,
    0x39_91D6, 0x39_8353, 0x39_F49C, 0x84_5F8B, 0xBD_F928, 0x3B_1FF8,
    0x97_FFDE, 0x05_980F, 0xEF_2F11, 0x8B_5A0A, 0x6D_1F6D, 0x36_7ECF,
    0x27_CB09, 0xB7_4F46, 0x3F_669E, 0x5F_EA2D, 0x75_27BA, 0xC7_EBE5,
    0xF1_7B3D, 0x07_39F7, 0x8A_5292, 0xEA_6BFB, 0x5F_B11F, 0x8D_5D08,
    0x56_0330, 0x46_FC7B, 0x6B_ABF0, 0xCF_BC20, 0x9A_F436, 0x1D_A9E3,
    0x91_615E, 0xE6_1B08, 0x65_9985, 0x5F_14A0, 0x68_408D, 0xFF_D880,
    0x4D_7327, 0x31_0606, 0x15_56CA, 0x73_A8C9, 0x60_E27B, 0xC0_8C6B,
]

/// High words of the first 32 multiples of `pi/2`, used to spot the arguments where
/// the cheap reduction loses too much precision.
private let npio2High: [Int32] = [
    0x3FF9_21FB, 0x4009_21FB, 0x4012_D97C, 0x4019_21FB, 0x401F_6A7A, 0x4022_D97C,
    0x4025_FDBB, 0x4029_21FB, 0x402C_463A, 0x402F_6A7A, 0x4031_475C, 0x4032_D97C,
    0x4034_6B9C, 0x4035_FDBB, 0x4037_8FDB, 0x4039_21FB, 0x403A_B41B, 0x403C_463A,
    0x403D_D85A, 0x403F_6A7A, 0x4040_7E4C, 0x4041_475C, 0x4042_106C, 0x4042_D97C,
    0x4043_A28C, 0x4044_6B9C, 0x4045_34AC, 0x4045_FDBB, 0x4046_C6CB, 0x4047_8FDB,
    0x4048_58EB, 0x4049_21FB,
].map { Int32(bitPattern: UInt32($0)) }

/// `pi/2` split into eight successively smaller pieces, for the table-driven path.
private let piOver2Pieces: [Double] = [
    1.57079625129699707031e+00,
    7.54978941586159635335e-08,
    5.39030252995776476554e-15,
    3.28200341580791294123e-22,
    1.27065575308067607349e-29,
    1.22933308981111328932e-36,
    2.73370053816464559624e-44,
    2.16741683877804819444e-51,
]

/// Reduces a huge argument modulo `pi/2` using the `2/pi` table.
///
/// A port of fdlibm's `k_rem_pio2.c`. `x` holds the argument split into 24-bit pieces;
/// the result is written to `y` and the return value is the quadrant, modulo 8.
private func kernelRemainderPiOver2(
    _ x: [Double],
    _ y: inout (Double, Double),
    _ e0: Int32,
    _ nx: Int,
    _ prec: Int
) -> Int32 {
    let initJk = [2, 3, 4, 6]
    let zero = 0.0
    let one = 1.0
    let two24 = 1.67772160000000000000e+07
    let twon24 = 5.96046447753906250000e-08

    let jk = initJk[prec]
    let jp = jk

    // Working arrays. fdlibm sizes these at 20, which its own analysis shows is enough.
    var iq = [Int32](repeating: 0, count: 20)
    var f = [Double](repeating: 0, count: 20)
    var q = [Double](repeating: 0, count: 20)
    var fq = [Double](repeating: 0, count: 20)

    let jx = nx - 1
    var jv = (e0 - 3) / 24
    if jv < 0 { jv = 0 }
    var q0 = e0 - 24 * (jv + 1)

    // Load the slice of the 2/pi table this argument needs.
    var j = Int(jv) - jx
    let m = jx + jk
    for i in 0 ... m {
        f[i] = j < 0 ? zero : Double(twoOverPi[j])
        j += 1
    }

    // The first jk+1 partial products.
    for i in 0 ... jk {
        var fw = 0.0
        for j in 0 ... jx { fw += x[j] * f[jx + i - j] }
        q[i] = fw
    }

    var jz = jk
    var n: Int32 = 0
    var ih: Int32 = 0
    var z = 0.0

    recompute: while true {
        // Distil q[] into 24-bit integer pieces, most significant last.
        var i = 0
        j = jz
        z = q[jz]
        while j > 0 {
            let fw = Double(toInt32(twon24 * z))
            iq[i] = toInt32(z - two24 * fw)
            z = q[j - 1] + fw
            i += 1
            j -= 1
        }

        // The quadrant.
        z = fdScalbn(z, q0)
        z -= 8.0 * (z * 0.125).rounded(.down)
        n = toInt32(z)
        z -= Double(n)
        ih = 0
        if q0 > 0 {
            let i = iq[jz - 1] >> (24 - q0)
            n = n &+ i
            iq[jz - 1] -= i << (24 - q0)
            ih = iq[jz - 1] >> (23 - q0)
        } else if q0 == 0 {
            ih = iq[jz - 1] >> 23
        } else if z >= 0.5 {
            ih = 2
        }

        if ih > 0 {
            // The remainder exceeds a half, so round up and negate: q -> 1 - q.
            n = n &+ 1
            var carry: Int32 = 0
            for i in 0 ..< jz {
                let j = iq[i]
                if carry == 0 {
                    if j != 0 {
                        carry = 1
                        iq[i] = 0x100_0000 - j
                    }
                } else {
                    iq[i] = 0xFF_FFFF - j
                }
            }
            if q0 > 0 {
                switch q0 {
                case 1: iq[jz - 1] &= 0x7F_FFFF
                case 2: iq[jz - 1] &= 0x3F_FFFF
                default: break
                }
            }
            if ih == 2 {
                z = one - z
                if carry != 0 { z -= fdScalbn(one, q0) }
            }
        }

        // If the result cancelled to zero, more table terms are needed.
        if z == zero {
            var j: Int32 = 0
            for i in stride(from: jz - 1, through: jk, by: -1) { j |= iq[i] }
            if j == 0 {
                var k = 1
                while iq[jk - k] == 0 { k += 1 }
                for i in (jz + 1) ... (jz + k) {
                    f[jx + i] = Double(twoOverPi[Int(jv) + i])
                    var fw = 0.0
                    for j in 0 ... jx { fw += x[j] * f[jx + i - j] }
                    q[i] = fw
                }
                jz += k
                continue recompute
            }
        }
        break
    }

    // Trim trailing zero pieces, or split a final piece that is too wide.
    if z == 0.0 {
        jz -= 1
        q0 -= 24
        while iq[jz] == 0 {
            jz -= 1
            q0 -= 24
        }
    } else {
        z = fdScalbn(z, -q0)
        if z >= two24 {
            let fw = Double(toInt32(twon24 * z))
            iq[jz] = toInt32(z - two24 * fw)
            jz += 1
            q0 += 24
            iq[jz] = toInt32(fw)
        } else {
            iq[jz] = toInt32(z)
        }
    }

    // Back to floating point.
    var fw = fdScalbn(one, q0)
    for i in stride(from: jz, through: 0, by: -1) {
        q[i] = fw * Double(iq[i])
        fw *= twon24
    }

    // Multiply by pi/2, piece by piece.
    for i in stride(from: jz, through: 0, by: -1) {
        var sum = 0.0
        var k = 0
        while k <= jp && k <= jz - i {
            sum += piOver2Pieces[k] * q[i + k]
            k += 1
        }
        fq[jz - i] = sum
    }

    switch prec {
    case 0:
        var sum = 0.0
        for i in stride(from: jz, through: 0, by: -1) { sum += fq[i] }
        y.0 = ih == 0 ? sum : -sum
    default:
        var sum = 0.0
        for i in stride(from: jz, through: 0, by: -1) { sum += fq[i] }
        y.0 = ih == 0 ? sum : -sum
        sum = fq[0] - sum
        for i in 1 ... max(1, jz) where i <= jz { sum += fq[i] }
        y.1 = ih == 0 ? sum : -sum
    }
    return n & 7
}

/// Reduces `x` modulo `pi/2`, as fdlibm's `e_rem_pio2.c`.
///
/// Returns the quadrant; `y` receives the remainder as a head and a tail, which
/// together carry more precision than a single double could.
private func remainderPiOver2(_ x: Double, _ y: inout (Double, Double)) -> Int32 {
    let zero = 0.0
    let half = 0.5
    let two24 = 1.67772160000000000000e+07
    let invpio2 = 6.36619772367581382433e-01
    let pio2_1 = 1.57079632673412561417e+00
    let pio2_1t = 6.07710050650619224932e-11
    let pio2_2 = 6.07710050630396597660e-11
    let pio2_2t = 2.02226624879595063154e-21
    let pio2_3 = 2.02226624871116645580e-21
    let pio2_3t = 8.47842766036889956997e-32

    let hx = Bits.high(x)
    let ix = hx & 0x7FFF_FFFF

    if ix <= 0x3FE9_21FB { // |x| <= pi/4, nothing to do
        y.0 = x
        y.1 = 0
        return 0
    }

    if ix < 0x4002_D97C { // |x| < 3pi/4, so the quadrant is exactly +/-1
        if hx > 0 {
            var z = x - pio2_1
            if ix != 0x3FF9_21FB {
                y.0 = z - pio2_1t
                y.1 = (z - y.0) - pio2_1t
            } else { // Very close to pi/2, so take an extra term.
                z -= pio2_2
                y.0 = z - pio2_2t
                y.1 = (z - y.0) - pio2_2t
            }
            return 1
        }
        var z = x + pio2_1
        if ix != 0x3FF9_21FB {
            y.0 = z + pio2_1t
            y.1 = (z - y.0) + pio2_1t
        } else {
            z += pio2_2
            y.0 = z + pio2_2t
            y.1 = (z - y.0) + pio2_2t
        }
        return -1
    }

    if ix <= 0x4139_21FB { // |x| <= 2**19 * (pi/2): reduce arithmetically
        let t = abs(x)
        var n = toInt32(t * invpio2 + half)
        let fn = Double(n)
        var r = t - fn * pio2_1
        var w = fn * pio2_1t
        if n < 32 && ix != npio2High[Int(n) - 1] {
            y.0 = r - w
        } else {
            let j = ix >> 20
            y.0 = r - w
            var high = Bits.high(y.0)
            var i = j - ((high >> 20) & 0x7FF)
            if i > 16 { // A second pass, good to 118 bits.
                let t2 = r
                w = fn * pio2_2
                r = t2 - w
                w = fn * pio2_2t - ((t2 - r) - w)
                y.0 = r - w
                high = Bits.high(y.0)
                i = j - ((high >> 20) & 0x7FF)
                if i > 49 { // A third, good to 151 bits.
                    let t3 = r
                    w = fn * pio2_3
                    r = t3 - w
                    w = fn * pio2_3t - ((t3 - r) - w)
                    y.0 = r - w
                }
            }
        }
        y.1 = (r - y.0) - w
        if hx < 0 {
            y.0 = -y.0
            y.1 = -y.1
            n = 0 &- n
            return n
        }
        return n
    }

    if ix >= 0x7FF0_0000 { // Infinite or not a number
        y.0 = x - x
        y.1 = y.0
        return 0
    }

    // Everything larger: split into 24-bit pieces and use the table.
    var z = Bits.settingLow(0, Bits.low(x))
    let e0 = (ix >> 20) - 1046 // ilogb(z) - 23
    z = Bits.settingHigh(z, ix - (e0 << 20))
    var tx = [Double](repeating: 0, count: 3)
    for i in 0 ..< 2 {
        tx[i] = Double(toInt32(z))
        z = (z - tx[i]) * two24
    }
    tx[2] = z
    var nx = 3
    while nx > 1, tx[nx - 1] == zero { nx -= 1 }
    let n = kernelRemainderPiOver2(tx, &y, e0, nx, 2)
    if hx < 0 {
        y.0 = -y.0
        y.1 = -y.1
        return 0 &- n
    }
    return n
}

// MARK: - Entry points

/// `Math.sin`, computed identically on every platform.
public func jsSin(_ x: Double) -> Double {
    let ix = Bits.high(x) & 0x7FFF_FFFF
    if ix <= 0x3FE9_21FB { // |x| <= pi/4
        return kernelSin(x, 0, 0)
    }
    if ix >= 0x7FF0_0000 { // Infinite or not a number
        return x - x
    }
    var y = (0.0, 0.0)
    let n = remainderPiOver2(x, &y)
    switch n & 3 {
    case 0: return kernelSin(y.0, y.1, 1)
    case 1: return kernelCos(y.0, y.1)
    case 2: return -kernelSin(y.0, y.1, 1)
    default: return -kernelCos(y.0, y.1)
    }
}

/// `Math.cos`, computed identically on every platform.
public func jsCos(_ x: Double) -> Double {
    let ix = Bits.high(x) & 0x7FFF_FFFF
    if ix <= 0x3FE9_21FB {
        return kernelCos(x, 0)
    }
    if ix >= 0x7FF0_0000 {
        return x - x
    }
    var y = (0.0, 0.0)
    let n = remainderPiOver2(x, &y)
    switch n & 3 {
    case 0: return kernelCos(y.0, y.1)
    case 1: return -kernelSin(y.0, y.1, 1)
    case 2: return -kernelCos(y.0, y.1)
    default: return kernelSin(y.0, y.1, 1)
    }
}



/// `Math.pow`, computed identically on every platform.
///
/// A port of fdlibm's `e_pow.c`. The shape is: settle every special case exactly as the
/// standard requires, then compute `x**y` as `2**(y * log2(x))`, carrying both the
/// logarithm and the exponent in a high and a low part so the product keeps enough
/// precision for the answer to be right to within one bit of the true value.
///
/// Transcribed closely from the original, including its habit of reusing variables, so
/// that it can be checked against the source line by line.
public func jsPow(_ x: Double, _ y: Double) -> Double {
    let bp = [1.0, 1.5]
    let dp_h = [0.0, 5.84962487220764160156e-01]
    let dp_l = [0.0, 1.35003920212974897128e-08]
    let zero = 0.0
    let one = 1.0
    let two = 2.0
    let two53 = 9007199254740992.0
    let hugeValue = 1.0e300
    let tinyValue = 1.0e-300
    // Coefficients for (3/2) * (log(x) - 2s - (2/3)s**3).
    let L1 = 5.99999999999994648725e-01
    let L2 = 4.28571428578550184252e-01
    let L3 = 3.33333329818377432918e-01
    let L4 = 2.72728123808534006489e-01
    let L5 = 2.30660745775561754067e-01
    let L6 = 2.06975017800338417784e-01
    let P1 = 1.66666666666666019037e-01
    let P2 = -2.77777777770155933842e-03
    let P3 = 6.61375632143793436117e-05
    let P4 = -1.65339022054652515390e-06
    let P5 = 4.13813679705723846039e-08
    let lg2 = 6.93147180559945286227e-01
    let lg2_h = 6.93147182464599609375e-01
    let lg2_l = -1.90465429995776804525e-09
    let ovt = 8.0085662595372944372e-17 // -(1024 - log2(overflow + half an ulp))
    let cp = 9.61796693925975554329e-01 // 2 / (3 log 2)
    let cp_h = 9.61796700954437255859e-01
    let cp_l = -7.02846165095275826516e-09
    let ivln2 = 1.44269504088896338700e+00 // 1 / log 2
    let ivln2_h = 1.44269502162933349609e+00
    let ivln2_l = 1.92596299112661746887e-08

    let hx = Bits.high(x)
    let lx = Bits.low(x)
    let hy = Bits.high(y)
    let ly = Bits.low(y)
    var ix = hx & 0x7FFF_FFFF
    let iy = hy & 0x7FFF_FFFF

    // Anything raised to the power zero is one — even a NaN, which the standard
    // requires and which is the one case that must be settled before the NaN test.
    if (UInt32(bitPattern: iy) | ly) == 0 { return one }

    // Either operand not a number now gives a NaN.
    if ix > 0x7FF0_0000 || (ix == 0x7FF0_0000 && lx != 0)
        || iy > 0x7FF0_0000 || (iy == 0x7FF0_0000 && ly != 0) {
        return x + y
    }

    // When the base is negative the answer's sign depends on whether the exponent is a
    // whole number, and whether that number is odd. 0 means not whole, 1 odd, 2 even.
    var yisint: Int32 = 0
    if hx < 0 {
        if iy >= 0x4340_0000 {
            yisint = 2 // Too large to be anything but an even whole number.
        } else if iy >= 0x3FF0_0000 {
            let k = (iy >> 20) - 0x3FF // The exponent.
            if k > 20 {
                let shift = UInt32(52 - k)
                let j = ly >> shift
                if (j << shift) == ly { yisint = 2 - Int32(j & 1) }
            } else if ly == 0 {
                let shift = UInt32(20 - k)
                let j = UInt32(bitPattern: iy) >> shift
                if (j << shift) == UInt32(bitPattern: iy) { yisint = 2 - Int32(j & 1) }
            }
        }
    }

    // Special values of the exponent.
    if ly == 0 {
        if iy == 0x7FF0_0000 { // The exponent is infinite.
            if (UInt32(bitPattern: ix) | lx) == 0x3FF0_0000 {
                return y - y // One raised to an infinite power is a NaN.
            }
            if ix >= 0x3FF0_0000 {
                return hy > 0 ? y : zero
            }
            return hy < 0 ? -y : zero
        }
        if iy == 0x3FF0_0000 { // The exponent is plus or minus one.
            return hy < 0 ? one / x : x
        }
        if hy == 0x4000_0000 { return x * x } // Squared.
        if hy == 0x3FE0_0000, hx >= 0 { // A square root, of a non-negative base.
            return x.squareRoot()
        }
    }

    var ax = abs(x)

    // Special values of the base: zero, infinite, or plus or minus one.
    if lx == 0, ix == 0x7FF0_0000 || ix == 0 || ix == 0x3FF0_0000 {
        var z = ax
        if hy < 0 { z = one / z }
        if hx < 0 {
            if ((ix - 0x3FF0_0000) | yisint) == 0 {
                z = (z - z) / (z - z) // Minus one to a fractional power is a NaN.
            } else if yisint == 1 {
                z = -z // A negative base to an odd power stays negative.
            }
        }
        return z
    }

    // The sign of the result.
    var s = one
    if hx < 0 {
        if yisint == 0 {
            return (x - x) / (x - x) // A negative base to a fractional power is a NaN.
        }
        if yisint == 1 { s = -one }
    }

    var t1: Double
    var t2: Double

    if iy > 0x4190_0000 { // |y| > 2**26: the result overflows unless x is near one.
        if iy > 0x4300_0000 { // |y| > 2**49
            if ix <= 0x3FEF_FFFF {
                return hy < 0 ? hugeValue * hugeValue : tinyValue * tinyValue
            }
            if ix >= 0x3FF0_0000 {
                return hy > 0 ? hugeValue * hugeValue : tinyValue * tinyValue
            }
        }
        if ix < 0x3FEF_FFFF {
            return hy < 0 ? s * hugeValue * hugeValue : s * tinyValue * tinyValue
        }
        if ix > 0x3FF0_0000 {
            return hy > 0 ? s * hugeValue * hugeValue : s * tinyValue * tinyValue
        }
        // |1 - x| is now at most 2**-20, so a short series gives log(x).
        let t = ax - one
        let w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25))
        let u = ivln2_h * t
        let v = t * ivln2_l - w * ivln2
        t1 = Bits.settingLow(u + v, 0)
        t2 = v - (t1 - u)
    } else {
        var n: Int32 = 0
        if ix < 0x0010_0000 { // A subnormal base: scale it into the normal range.
            ax *= two53
            n -= 53
            ix = Bits.high(ax)
        }
        n += (ix >> 20) - 0x3FF
        let j = ix & 0x000F_FFFF
        // Bring the base into [sqrt(2)/2, sqrt(2)] and choose which of the two
        // reference points, 1 or 1.5, to expand the logarithm around.
        ix = j | 0x3FF0_0000
        let k: Int
        if j <= 0x3_988E {
            k = 0 // |x| < sqrt(3/2)
        } else if j < 0xB_B67A {
            k = 1 // |x| < sqrt(3)
        } else {
            k = 0
            n += 1
            ix -= 0x0010_0000
        }
        ax = Bits.settingHigh(ax, ix)

        // The logarithm, carried as a high and a low part throughout.
        let u = ax - bp[k]
        let v = one / (ax + bp[k])
        let ss = u * v
        let s_h = Bits.settingLow(ss, 0)
        var t_h = Bits.settingHigh(zero, ((ix >> 1) | 0x2000_0000) + 0x0008_0000 + (Int32(k) << 18))
        let t_l = ax - (t_h - bp[k])
        let s_l = v * ((u - s_h * t_h) - s_h * t_l)
        var s2 = ss * ss
        var r = s2 * s2 * (L1 + s2 * (L2 + s2 * (L3 + s2 * (L4 + s2 * (L5 + s2 * L6)))))
        r += s_l * (s_h + ss)
        s2 = s_h * s_h
        t_h = Bits.settingLow(3.0 + s2 + r, 0)
        let t_l2 = r - ((t_h - 3.0) - s2)
        // u2 + v2 = ss * (1 + ...)
        let u2 = s_h * t_h
        let v2 = s_l * t_h + t_l2 * ss
        // 2 / (3 log 2) * (ss + ...)
        let p_h = Bits.settingLow(u2 + v2, 0)
        let p_l = v2 - (p_h - u2)
        let z_h = cp_h * p_h
        let z_l = cp_l * p_h + p_l * cp + dp_l[k]
        // log2(ax) = n + dp_h + z_h + z_l
        let t = Double(n)
        t1 = Bits.settingLow(((z_h + z_l) + dp_h[k]) + t, 0)
        t2 = z_l - (((t1 - t) - dp_h[k]) - z_h)
    }

    // Split the exponent into two halves, then form 2**(p_h + p_l).
    let y1 = Bits.settingLow(y, 0)
    let p_l = (y - y1) * t1 + y * t2
    var p_h = y1 * t1
    var z = p_l + p_h
    var j = Bits.high(z)
    let i = Bits.low(z)

    if j >= 0x4090_0000 { // z >= 1024
        if ((UInt32(bitPattern: j) &- 0x4090_0000) | i) != 0 {
            return s * hugeValue * hugeValue // Overflow.
        }
        if p_l + ovt > z - p_h {
            return s * hugeValue * hugeValue
        }
    } else if (j & 0x7FFF_FFFF) >= 0x4090_CC00 { // z <= -1075
        if ((UInt32(bitPattern: j) &- 0xC090_CC00) | i) != 0 {
            return s * tinyValue * tinyValue // Underflow.
        }
        if p_l <= z - p_h {
            return s * tinyValue * tinyValue
        }
    }

    // 2**(p_h + p_l), by taking out the whole part and expanding the remainder.
    let iz = j & 0x7FFF_FFFF
    var k = (iz >> 20) - 0x3FF
    var n: Int32 = 0
    if iz > 0x3FE0_0000 { // |z| > 0.5, so n becomes the nearest whole number to z.
        n = j + (0x0010_0000 >> (k + 1))
        k = ((n & 0x7FFF_FFFF) >> 20) - 0x3FF
        let t = Bits.settingHigh(zero, n & ~(0x000F_FFFF >> k))
        n = ((n & 0x000F_FFFF) | 0x0010_0000) >> (20 - k)
        if j < 0 { n = 0 &- n }
        p_h -= t
    }
    let t = Bits.settingLow(p_l + p_h, 0)
    let u = t * lg2_h
    let v = (p_l - (t - p_h)) * lg2 + t * lg2_l
    z = u + v
    let w = v - (z - u)
    let tz = z * z
    let t1b = z - tz * (P1 + tz * (P2 + tz * (P3 + tz * (P4 + tz * P5))))
    let r = (z * t1b) / (t1b - two) - (w + z * w)
    z = one - (r - z)
    j = Bits.high(z)
    j += n << 20
    if (j >> 20) <= 0 {
        z = fdScalbn(z, n) // A subnormal result needs the general scaling.
    } else {
        z = Bits.settingHigh(z, j)
    }
    return s * z
}
