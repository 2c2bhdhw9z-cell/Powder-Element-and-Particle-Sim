import Foundation
import Testing

@testable import CrucibleCore

/// Holds the four set-piece events to the exact grid the web engine produces.
///
/// A meteor, a blast, a surge and a deep freeze. These were the last part of the simulation still
/// living inside the web version's canvas component, mixed in with sound and screen-shake, where
/// nothing could reach them — which is why they are the last to be checked.
///
/// They deserve it. Between them they contain a disc of radius ten dropped at a depth of fourteen,
/// an explosion placed at 0.65 of the world's height, a water band running from 0.28 down to two
/// from the bottom at a fixed sideways momentum, and four element substitutions at −200°C. Every
/// one of those is a number that can be transposed while the result still looks like an explosion.
///
/// Checked at four sizes, and the cramped one matters most: a 30×24 world is smaller than the
/// meteor's own disc and well below the surge's band, so almost every line has to clip or decline
/// to run. Translating the surge's loops directly is a crash at that size rather than a
/// difference, because a Swift range whose end is below its start traps where a JavaScript loop
/// simply does not execute.
@Suite("Set-piece events match the web engine")
struct EventGoldenTests {
    struct Blast: Decodable, Equatable {
        var x: Int
        var y: Int
        var radius: Int
        var force: Double
        var heat: Double
    }

    struct FollowUp: Decodable, Equatable {
        var delayMs: Double
        var blasts: [Blast]
        var shake: Double
        var sound: String?
        var soundIntensity: Double
    }

    struct Start: Decodable, Equatable {
        var shake: Double
        var sound: String?
        var soundIntensity: Double
        var followUp: FollowUp?
    }

    struct Event: Decodable, CustomTestStringConvertible {
        var event: String
        var width: Int
        var height: Int
        var seed: UInt32
        var typeRows: [String]
        var temperatures: [String]
        var lifetimes: [String]
        /// Non-zero momentum, as `index:vx,vy`.
        var momentum: [String]
        var activeCount: Int
        var randomDraws: Int
        var start: Start

        var testDescription: String { "\(event) at \(width)x\(height)" }
    }

    struct Fixture: Decodable {
        var note: String
        var events: [Event]
    }

    static let fixture: Fixture = {
        guard let url = Bundle.module.url(
            forResource: "web-events-golden",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "web-events-golden", withExtension: "json") else {
            fatalError("Fixture web-events-golden.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
        } catch {
            fatalError("Could not decode the golden event fixture: \(error)")
        }
    }()

    /// Builds the same world the generator did, then runs both halves of the event.
    private func run(_ event: Event) -> (engine: PowderEngine, draws: Int, start: PowderEventStart) {
        guard let id = PowderEventID(rawValue: event.event) else {
            fatalError("No event named \(event.event)")
        }
        let engine = PowderEngine(width: event.width, height: event.height, seed: event.seed)

        // The same deterministic floor and scattering of material the generator lays down, so a
        // freeze has something to convert and a blast has something to throw.
        for x in 0 ..< engine.width { engine.setElement(x, engine.height - 1, Element.bedrock) }
        var x = 0
        while x < engine.width {
            let y = engine.height - 2
            if engine.isValid(x, y) { engine.setElement(x, y, Element.water) }
            if engine.isValid(x + 1, y) { engine.setElement(x + 1, y, Element.lava) }
            if engine.isValid(x + 2, y) { engine.setElement(x + 2, y, Element.sand) }
            x += 3
        }

        // The generator resets its count here, after the world is built, so the fixture records
        // only what the event itself consumed.
        let stateBeforeEvent = engine.rng.state

        let start = engine.start(id)
        // Both halves. The delay is presentation; the second half is as much part of the event as
        // the first, and the delay itself is checked separately as data.
        if let followUp = start.followUp { engine.finish(followUp) }

        // Recovered by replaying the stream rather than by adding a counter to the engine.
        var replay = Mulberry32(seed: 0)
        replay.state = stateBeforeEvent
        var draws = 0
        while replay.state != engine.rng.state, draws < 500_000 {
            _ = replay.nextBits()
            draws += 1
        }
        return (engine, draws, start)
    }

    private func typeRows(_ engine: PowderEngine) -> [String] {
        (0 ..< engine.height).map { y in
            (0 ..< engine.width)
                .map { String(engine.type[y * engine.width + $0]) }
                .joined(separator: ",")
        }
    }

    private func lifetimes(_ engine: PowderEngine) -> [String] {
        var out: [String] = []
        for i in 0 ..< engine.cellCount where engine.life[i] != 0 {
            out.append("\(i):\(engine.life[i])")
        }
        return out
    }

    private func momentum(_ engine: PowderEngine) -> [String] {
        var out: [String] = []
        for i in 0 ..< engine.cellCount where engine.velocityX[i] != 0 || engine.velocityY[i] != 0 {
            out.append("\(i):\(engine.velocityX[i]),\(engine.velocityY[i])")
        }
        return out
    }

    /// Two decimal places, formatted the way JavaScript's `toFixed(2)` does.
    private func twoDecimals(_ value: Double) -> String {
        let scaled = JS.round(value * 100) / 100
        let negative = scaled < 0
        let magnitude = negative ? -scaled : scaled
        let integral = Int(magnitude.rounded(.down))
        var hundredths = Int(JS.round((magnitude - Double(integral)) * 100))
        var whole = integral
        if hundredths == 100 {
            hundredths = 0
            whole += 1
        }
        let fraction = hundredths < 10 ? "0\(hundredths)" : "\(hundredths)"
        return "\(negative ? "-" : "")\(whole).\(fraction)"
    }

    private func temperatures(_ engine: PowderEngine) -> [String] {
        let ambientText = twoDecimals(engine.ambientTemp)
        var out: [String] = []
        for i in 0 ..< engine.cellCount {
            let text = twoDecimals(Double(engine.temperature[i]))
            if text != ambientText { out.append("\(i):\(text)") }
        }
        return out
    }

    @Test("Every cell matches", arguments: fixture.events)
    func cellsMatch(event: Event) {
        let result = run(event)
        let actual = typeRows(result.engine)
        #expect(actual.count == event.typeRows.count, "\(event.testDescription): row count differs")

        var reported = 0
        for y in 0 ..< min(actual.count, event.typeRows.count) where actual[y] != event.typeRows[y] {
            if reported < 3 {
                Issue.record(
                    """
                    \(event.testDescription), row \(y) differs
                      native: \(actual[y])
                      web:    \(event.typeRows[y])
                    """
                )
            }
            reported += 1
        }
        if reported > 3 {
            Issue.record("\(event.testDescription): \(reported) rows differ in total")
        }
    }

    @Test("Temperatures match", arguments: fixture.events)
    func temperaturesMatch(event: Event) {
        // The whole point of a freeze is the temperature, and a meteor's 2800° is what makes it
        // set fire to what it lands on. Neither shows up in the grid of element ids.
        let result = run(event)
        let actual = temperatures(result.engine)
        #expect(
            actual.count == event.temperatures.count,
            "\(event.testDescription): \(actual.count) cells away from ambient, web engine had \(event.temperatures.count)"
        )
        for i in 0 ..< min(actual.count, event.temperatures.count) where actual[i] != event.temperatures[i] {
            Issue.record(
                """
                \(event.testDescription), temperature \(i) differs
                  native: \(actual[i])
                  web:    \(event.temperatures[i])
                """
            )
            break
        }
    }

    @Test("Lifetimes match", arguments: fixture.events)
    func lifetimesMatch(event: Event) {
        let result = run(event)
        let actual = lifetimes(result.engine)
        #expect(
            actual.count == event.lifetimes.count,
            "\(event.testDescription): \(actual.count) cells counting down, web engine had \(event.lifetimes.count)"
        )
        for i in 0 ..< min(actual.count, event.lifetimes.count) where actual[i] != event.lifetimes[i] {
            Issue.record(
                """
                \(event.testDescription), lifetime \(i) differs
                  native: \(actual[i])
                  web:    \(event.lifetimes[i])
                """
            )
            break
        }
    }

    @Test("Momentum matches", arguments: fixture.events)
    func momentumMatches(event: Event) {
        // The surge and the meteor both write momentum directly, and it is the only reason the
        // water travels sideways instead of just appearing. A grid comparison would not see it.
        let result = run(event)
        let actual = momentum(result.engine)
        #expect(
            actual.count == event.momentum.count,
            "\(event.testDescription): \(actual.count) cells carrying momentum, web engine had \(event.momentum.count)"
        )
        for i in 0 ..< min(actual.count, event.momentum.count) where actual[i] != event.momentum[i] {
            Issue.record(
                """
                \(event.testDescription), momentum \(i) differs
                  native: \(actual[i])
                  web:    \(event.momentum[i])
                """
            )
            break
        }
    }

    @Test("The random source is consumed identically", arguments: fixture.events)
    func drawsMatch(event: Event) {
        let result = run(event)
        #expect(
            result.draws == event.randomDraws,
            "\(event.testDescription): drew \(result.draws) numbers, the web engine drew \(event.randomDraws)"
        )
    }

    @Test("The occupied count matches", arguments: fixture.events)
    func activeCountMatches(event: Event) {
        let result = run(event)
        #expect(
            result.engine.activeParticleCount == event.activeCount,
            "\(event.testDescription): \(result.engine.activeParticleCount) cells filled, web engine had \(event.activeCount)"
        )
    }

    /// The shake, the sound and the delay are returned rather than performed, so they are data —
    /// and data can be wrong without any picture of the grid revealing it. A meteor that quietly
    /// stopped asking for its sound would be a real regression that looked like nothing.
    @Test("What the event asks the app to do matches", arguments: fixture.events)
    func accompanimentMatches(event: Event) {
        let result = run(event)
        let start = result.start
        let label = event.testDescription

        #expect(start.shake == event.start.shake, "\(label): shake")
        #expect(start.sound?.rawValue == event.start.sound, "\(label): sound")
        #expect(start.soundIntensity == event.start.soundIntensity, "\(label): sound intensity")

        guard let expected = event.start.followUp else {
            #expect(start.followUp == nil, "\(label): expected no delayed half")
            return
        }
        guard let actual = start.followUp else {
            Issue.record("\(label): expected a delayed half and there was none")
            return
        }
        // Recorded in milliseconds on the web and in seconds here, because a Swift duration is
        // conventionally seconds and a millisecond figure in a Double invites being passed to the
        // wrong kind of timer.
        #expect(actual.delaySeconds * 1000 == expected.delayMs, "\(label): delay")
        #expect(actual.shake == expected.shake, "\(label): follow-up shake")
        #expect(actual.sound?.rawValue == expected.sound, "\(label): follow-up sound")
        #expect(
            actual.soundIntensity == expected.soundIntensity,
            "\(label): follow-up sound intensity"
        )
        #expect(actual.blasts.count == expected.blasts.count, "\(label): number of explosions")
        for i in 0 ..< min(actual.blasts.count, expected.blasts.count) {
            let a = actual.blasts[i]
            let b = expected.blasts[i]
            #expect(a.x == b.x && a.y == b.y, "\(label): explosion \(i) position")
            #expect(a.radius == b.radius, "\(label): explosion \(i) radius")
            #expect(a.force == b.force, "\(label): explosion \(i) force")
            #expect(a.heat == b.heat, "\(label): explosion \(i) heat")
        }
    }

    /// The cramped case, called out on its own because it is a crash rather than a difference if
    /// the surge's loops are translated directly from the original.
    @Test("An event in a world too small for it does nothing, rather than trapping")
    func tinyWorldsSurvive() {
        for id in PowderEventID.allCases {
            for (width, height) in [(8, 8), (1, 1), (40, 6), (6, 40)] {
                let engine = PowderEngine(width: width, height: height, seed: 7)
                let start = engine.start(id)
                if let followUp = start.followUp { engine.finish(followUp) }
                // Reaching here at all is the assertion. Nothing about the result is claimed —
                // only that a world smaller than the event does not bring the app down.
                #expect(engine.cellCount == width * height)
            }
        }
    }
}
