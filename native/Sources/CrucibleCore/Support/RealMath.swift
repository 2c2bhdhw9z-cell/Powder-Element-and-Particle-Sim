#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

// Swift's standard library provides square roots but not powers or trigonometry,
// so these come from the platform's C maths library.
//
// That is the engine's only dependency beyond the standard library, and it is a
// deliberate limit: the C maths library exists identically on every platform this
// project touches, so importing it costs nothing in portability and the engine
// still builds and tests on Linux without Apple frameworks anywhere near it.
//
// Wrapped in named functions rather than called directly so that the dependency
// is visible in one place instead of scattered through the physics.

/// `Math.pow`.
@inlinable
func jsPow(_ base: Double, _ exponent: Double) -> Double {
    pow(base, exponent)
}

/// `Math.cos`.
@inlinable
func jsCos(_ radians: Double) -> Double {
    cos(radians)
}

/// `Math.sin`.
@inlinable
func jsSin(_ radians: Double) -> Double {
    sin(radians)
}
