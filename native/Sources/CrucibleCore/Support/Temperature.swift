// Showing a temperature to a reader.
//
// ## Why this is in the engine at all
//
// Converting Celsius to Fahrenheit is three operations, and putting it here rather than beside the
// label that displays it looks like over-organisation. It is not, for one specific reason: the result
// is rounded, and the temperatures in this simulation are routinely negative — the deep freeze sets
// everything to −200, and ice sits below zero all the time.
//
// JavaScript's rounding sends a half *upward*, toward positive infinity, so `Math.round(-40.5)` is
// −40. Swift's `rounded()` sends a half *away from zero*, so the same value gives −41. Every negative
// half disagrees. That is a difference of one degree on a readout, which nobody would ever report as a
// bug and which would quietly make the two versions disagree about what they are showing.
//
// So it lives here, uses ``JS/round(_:)``, and is tested against the values the reference produces.

/// Temperatures, as they are shown rather than as they are stored.
public enum Temperature {
    /// Celsius to Fahrenheit, rounded the way the reference rounds.
    ///
    /// Returns a whole number as a `Double`, because that is what gets displayed — the underlying
    /// value stays untouched.
    public static func fahrenheit(fromCelsius celsius: Double) -> Double {
        guard celsius.isFinite else { return celsius }
        return JS.round(celsius * 9 / 5 + 32)
    }

    /// Celsius, rounded the same way, so both units round alike.
    ///
    /// Without this the two scales would disagree about halves — Fahrenheit rounding one way and
    /// Celsius the other — which is the sort of inconsistency that is very hard to notice and
    /// impossible to explain once someone does.
    public static func celsius(_ celsius: Double) -> Double {
        guard celsius.isFinite else { return celsius }
        return JS.round(celsius)
    }
}
