import Testing

@testable import CrucibleCore

/// The temperature conversion, which exists in the engine for one reason.
///
/// The arithmetic is trivial. The rounding is not: JavaScript sends a half toward positive infinity
/// and Swift sends it away from zero, so they disagree about **every negative half** — and this
/// simulation is full of negative temperatures. The deep freeze sets everything to −200, and ice sits
/// below zero permanently.
///
/// A one-degree disagreement on a readout is not something anyone would report, which is precisely
/// why it needs a test rather than a careful reading.
@Suite("Temperatures are shown the way the reference shows them")
struct TemperatureTests {
    @Test("The familiar points are right")
    func knownPoints() {
        #expect(Temperature.fahrenheit(fromCelsius: 0) == 32)
        #expect(Temperature.fahrenheit(fromCelsius: 100) == 212)
        #expect(Temperature.fahrenheit(fromCelsius: -40) == -40)
        #expect(Temperature.fahrenheit(fromCelsius: 20) == 68)
        #expect(Temperature.fahrenheit(fromCelsius: 37) == 99)
    }

    /// The whole reason this is not written inline next to the label.
    ///
    /// Each of these lands exactly on a half before rounding, and each is a value the simulation
    /// actually produces — ice, a chilled pond, the deep freeze.
    @Test("A negative half rounds upward, as JavaScript does and Swift does not")
    func negativeHalvesRoundUpward() {
        // −40.25°C is −40.45°F, not a half — so pick values that land on one exactly.
        // c × 9/5 + 32 = x.5  ⇒  c = (x.5 − 32) × 5/9
        for target in [-40.5, -1.5, -0.5, -100.5, -212.5] {
            let celsius = (target - 32) * 5 / 9
            let produced = Temperature.fahrenheit(fromCelsius: celsius)
            // JavaScript's answer: floor(x + 0.5), so −40.5 becomes −40.
            let expected = (target + 0.5).rounded(.down)
            #expect(
                produced == expected,
                "\(target) should round to \(expected), got \(produced)"
            )
            // And confirm this is genuinely the case Swift gets wrong, so the test is not vacuous.
            #expect(
                target.rounded() != expected,
                "\(target) was supposed to be a case where Swift's own rounding differs"
            )
        }
    }

    @Test("Celsius rounds the same way, so the two scales agree about halves")
    func celsiusRoundsAlike() {
        #expect(Temperature.celsius(-0.5) == 0)
        #expect(Temperature.celsius(-1.5) == -1)
        #expect(Temperature.celsius(1.5) == 2)
        #expect(Temperature.celsius(-200) == -200)
        // Swift would give −1 and −2 for the first two, which is the inconsistency being avoided.
        #expect((-0.5).rounded() == -1)
    }

    @Test("The temperatures the simulation actually produces convert sensibly")
    func realValues() {
        // The deep freeze.
        #expect(Temperature.fahrenheit(fromCelsius: -200) == -328)
        // Lava, as a meteor places it.
        #expect(Temperature.fahrenheit(fromCelsius: 2800) == 5072)
        // The threshold where lava sets.
        #expect(Temperature.fahrenheit(fromCelsius: 700) == 1292)
        // Water boiling.
        #expect(Temperature.fahrenheit(fromCelsius: 100) == 212)
    }

    /// A temperature that is not a number can exist in a damaged scene — the health report exists
    /// partly to find them. Converting it must not turn it into a plausible-looking number.
    @Test("An unusable temperature passes through rather than becoming a number")
    func unusableValues() {
        #expect(Temperature.fahrenheit(fromCelsius: .nan).isNaN)
        #expect(Temperature.celsius(.nan).isNaN)
        #expect(Temperature.fahrenheit(fromCelsius: .infinity).isInfinite)
    }

    /// Read from the grid, a temperature is single precision. The conversion should not introduce a
    /// disagreement of its own on the way through.
    @Test("A temperature read from the grid converts consistently")
    func fromTheGrid() {
        let engine = PowderEngine(width: 8, height: 8, seed: 1)
        engine.setElement(2, 2, Element.lava, temp: 1400)
        let stored = Double(engine.temperature[engine.index(2, 2)])
        #expect(Temperature.celsius(stored) == 1400)
        #expect(Temperature.fahrenheit(fromCelsius: stored) == 2552)
    }
}
