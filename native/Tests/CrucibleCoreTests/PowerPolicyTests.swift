import Testing

@testable import CrucibleCore

/// What the app does about a hot phone, a tired one, and what it costs the battery.
@Suite("A hot phone, a tired one, and what the battery pays")
struct PowerPolicyTests {
    @Test("A cool phone with charge in it gives nothing up")
    func fullSpeedWhenWell() {
        let advice = PowerPolicy.advice(for: PowerPolicy.Readings(heat: .nominal, lowPower: false, charge: 0.8))
        #expect(advice.framesPerSecond == 120)
        #expect(advice.keepsTheLuxuries)
        #expect(advice.shareOfTheWork == 1)
        #expect(!advice.isHoldingBack)
        #expect(advice.reason == nil)
    }

    @Test("The hotter it gets, the more is given up, and the reason is said in plain words")
    func easesOffAsItWarms() {
        let warm = PowerPolicy.advice(for: PowerPolicy.Readings(heat: .fair, charge: 0.8))
        #expect(warm.framesPerSecond == 120, "a merely warm phone should not lose frames")
        #expect(!warm.keepsTheLuxuries)
        #expect(warm.shareOfTheWork == 1)
        #expect(warm.reason?.contains("warming up") == true)

        let hot = PowerPolicy.advice(for: PowerPolicy.Readings(heat: .serious, charge: 0.8))
        #expect(hot.framesPerSecond == 60)
        #expect(!hot.keepsTheLuxuries)
        #expect(hot.shareOfTheWork == 0.75)
        #expect(hot.reason?.contains("hot") == true)

        let veryHot = PowerPolicy.advice(for: PowerPolicy.Readings(heat: .critical, charge: 0.8))
        #expect(veryHot.framesPerSecond == 30)
        #expect(veryHot.shareOfTheWork == 0.5)
        #expect(veryHot.reason?.contains("very hot") == true)

        // Each step gives up at least as much as the one before it: nothing is recovered by getting hotter.
        let steps = PowerPolicy.Heat.allCases.map { PowerPolicy.advice(for: PowerPolicy.Readings(heat: $0, charge: 0.8)) }
        for (cooler, hotter) in zip(steps, steps.dropFirst()) {
            #expect(hotter.framesPerSecond <= cooler.framesPerSecond)
            #expect(hotter.shareOfTheWork <= cooler.shareOfTheWork)
        }
    }

    @Test("Being plugged in excuses a warm phone but not a hot one")
    func chargingChangesWhatMatters() {
        let warmAndPlugged = PowerPolicy.advice(for: PowerPolicy.Readings(heat: .fair, charge: 0.4, isCharging: true))
        #expect(!warmAndPlugged.isHoldingBack, "a phone being filled was held back for merely being warm")

        let hotAndPlugged = PowerPolicy.advice(for: PowerPolicy.Readings(heat: .serious, charge: 0.4, isCharging: true))
        #expect(hotAndPlugged.isHoldingBack, "a hot phone was left at full speed because it was plugged in")

        let emptyAndPlugged = PowerPolicy.advice(for: PowerPolicy.Readings(charge: 0.02, isCharging: true))
        #expect(!emptyAndPlugged.isHoldingBack, "a phone on charge was saved from a battery that is filling up")
    }

    @Test("Low Power Mode and a low battery each halve the drawing")
    func honoursLowPowerAndLowBattery() {
        let lowPower = PowerPolicy.advice(for: PowerPolicy.Readings(lowPower: true, charge: 0.9))
        #expect(lowPower.framesPerSecond == 60)
        #expect(lowPower.shareOfTheWork == 1, "Low Power Mode should not change what the worlds do")
        #expect(lowPower.reason?.contains("Low Power Mode") == true)

        let low = PowerPolicy.advice(for: PowerPolicy.Readings(charge: PowerPolicy.lowCharge))
        #expect(low.framesPerSecond == 60)
        #expect(low.reason?.contains("battery is low") == true)

        let nearlyEmpty = PowerPolicy.advice(for: PowerPolicy.Readings(charge: PowerPolicy.veryLowCharge))
        #expect(nearlyEmpty.framesPerSecond == 30)
        #expect(nearlyEmpty.reason?.contains("nearly empty") == true)

        // A phone that will not say how much charge is left is left alone rather than assumed to be empty.
        #expect(!PowerPolicy.advice(for: PowerPolicy.Readings(charge: nil)).isHoldingBack)
        #expect(!PowerPolicy.advice(for: PowerPolicy.Readings(charge: .nan)).isHoldingBack)
    }

    @Test("What the battery pays is measured from the charge falling, and not guessed before then")
    func measuresTheBattery() {
        var cost = BatteryCost()
        cost.note(charge: 0.80, isCharging: false, seconds: 0)
        #expect(cost.shareAnHour == nil, "a figure was offered before any charge had gone")
        // Half a percent in a minute: still not a whole percent, so still nothing to say.
        cost.note(charge: 0.795, isCharging: false, seconds: 60)
        #expect(cost.shareAnHour == nil)
        // Two percent in six minutes is twenty percent an hour.
        cost.note(charge: 0.78, isCharging: false, seconds: 360)
        let rate = try! #require(cost.shareAnHour)
        #expect(abs(rate - 0.2) < 1e-9, "\(rate)")
        #expect(cost.seconds == 360)
        let hours = try! #require(cost.hoursLeft(charge: 0.78))
        #expect(abs(hours - 3.9) < 1e-9, "\(hours)")

        // Plugged in: what was measured is thrown away rather than averaged with a battery that is filling.
        cost.note(charge: 0.79, isCharging: true, seconds: 400)
        #expect(cost.shareAnHour == nil)
        #expect(cost.seconds == 0)

        // Unplugged again, it starts afresh from the charge it finds.
        cost.note(charge: 0.85, isCharging: false, seconds: 500)
        cost.note(charge: 0.83, isCharging: false, seconds: 860)
        #expect(abs((cost.shareAnHour ?? 0) - 0.2) < 1e-9)
        // And a charge that has gone *up* also starts it afresh: the phone was filled while the app was away.
        cost.note(charge: 0.99, isCharging: false, seconds: 1_000)
        #expect(cost.shareAnHour == nil)

        // Nothing the phone refuses to say can produce a figure.
        var quiet = BatteryCost()
        quiet.note(charge: nil, isCharging: false, seconds: 0)
        quiet.note(charge: nil, isCharging: false, seconds: 600)
        #expect(quiet.shareAnHour == nil)
        #expect(quiet.hoursLeft(charge: 0.5) == nil)
    }
}
