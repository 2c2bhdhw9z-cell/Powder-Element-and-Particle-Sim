import CoreMotion
import CrucibleCore
import Foundation
import SwiftUI
import UIKit

/// The phone's other senses: the air pressure, the day's walking, the time of day, and how bright the room is.
///
/// Every conversion is `WorldSenses` in the engine, where each one is tested. This is the part that needs a phone: which
/// frameworks to ask, which permissions are involved, and what to do when a sense is not there at all.
///
/// ## What each one does to the worlds
///
/// - **The weather** sets the powder world's room temperature and its wind. Falling pressure is weather coming in, so
///   the world gets colder and windier; a settled high is warm and still.
/// - **The day's walking** sets how strong the sea's tide is, when a tide is running. Both are slow things.
/// - **The time of day** blows the wind the way the sun drags weather across the sky, east to west.
/// - **How bright the room is** dims the picture to match it, and in a dark room holds the glow back.
///
/// ## What is asked of anybody
///
/// The barometer and the step count are Motion & Fitness, which iOS asks about once, and which needs a line in the app's
/// own description of itself. Everything else needs nothing. Nothing here is on until it is switched on, and each sense
/// says plainly whether the phone has it: a phone with no barometer says so rather than reading nought for ever.
@MainActor
@Observable
final class RoomSenses {
    /// Whether the phone's other senses are being used at all.
    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            if isOn { start() } else { stop() }
        }
    }

    /// The air pressure, in hectopascals, as the phone last read it. Nothing before the first reading.
    private(set) var pressure: Double?
    /// The pressure when this was switched on, so what is used is how much it has *moved* — see `WorldSenses.weather`.
    private(set) var firstPressure: Double?
    /// How many steps today.
    private(set) var steps: Int?
    /// Whether this phone has a barometer at all.
    let hasBarometer = CMAltimeter.isRelativeAltitudeAvailable()
    /// Whether this phone counts steps.
    let hasStepCounter = CMPedometer.isStepCountingAvailable()
    /// Why a sense could not be used, if the phone refused.
    private(set) var problem: String?

    /// How bright the screen is, which follows the room when the phone is set to do that — as it is by default.
    private(set) var screenBrightness = Double(UIScreen.main.brightness)

    private let altimeter = CMAltimeter()
    private let pedometer = CMPedometer()
    /// What has to be let go of, in something that is nobody's actor — a `deinit` may not touch the main actor's things.
    private let watching = SenseWatchers()

    // MARK: - What the worlds should do about it

    /// How settled the weather is, from the pressure — nothing until there is a reading.
    var weather: Double? {
        pressure.map { WorldSenses.weather(pressure: $0) }
    }

    /// How much the weather has turned since this was switched on.
    var weatherDrift: Double? {
        guard let firstPressure, let pressure else { return nil }
        return WorldSenses.weatherDrift(from: firstPressure, to: pressure)
    }

    /// Where the sun is, from the clock in this phone's own time.
    var sun: Double? {
        let minutes = Calendar.current.component(.hour, from: Date()) * 60
            + Calendar.current.component(.minute, from: Date())
        return WorldSenses.sun(hour: Double(minutes) / 60)
    }

    /// How bright the picture should be.
    var pictureBrightness: Double { WorldSenses.pictureBrightness(screen: screenBrightness) }

    /// Whether the room is dark enough to hold the glow back.
    var isDarkRoom: Bool { WorldSenses.isDarkRoom(screen: screenBrightness) }

    /// The room's temperature and the wind the weather calls for, or nothing when there is no reading yet.
    var weatherSettings: (roomTemperature: Double, wind: Double)? {
        guard let weather else { return nil }
        let fromWeather = WorldSenses.wind(weatherDrift: weatherDrift ?? 0)
        let fromSun = WorldSenses.wind(sun: sun)
        // Both blow: the front does most of it, the sun leans it one way.
        return (WorldSenses.roomTemperature(weather: weather), max(-5, min(5, fromWeather + fromSun * 0.5)))
    }

    /// How strong the sea's tide should be from today's walking, or nothing when the phone does not count steps.
    var tideStrength: Double? {
        steps.map { WorldSenses.tideStrength(steps: $0) }
    }

    // MARK: - Reading them

    init() {
        watchScreen()
    }

    // No `deinit`: everything that has to be let go of belongs to `watching`, which lets go of it in its own. The two
    // readers stop of their own accord once nothing holds them.

    private func watchScreen() {
        let watcher = NotificationCenter.default.addObserver(
            forName: UIScreen.brightnessDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.readScreen() }
        }
        watching.observers.append(watcher)
    }

    private func readScreen() {
        let now = Double(UIScreen.main.brightness)
        if abs(now - screenBrightness) > 0.01 { screenBrightness = now }
    }

    private func start() {
        problem = nil
        readScreen()

        if hasBarometer {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] reading, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        // Refused, almost always because Motion & Fitness was declined. Said once, and the switch is
                        // left on so nothing else silently stops.
                        self.problem = "The phone would not share its barometer: \(error.localizedDescription)"
                        return
                    }
                    guard let reading else { return }
                    // Kilopascals from the phone, hectopascals for everybody who reads a forecast.
                    let hectopascals = reading.pressure.doubleValue * 10
                    guard hectopascals.isFinite, hectopascals > 0 else { return }
                    self.pressure = hectopascals
                    if self.firstPressure == nil { self.firstPressure = hectopascals }
                }
            }
        }

        if hasStepCounter {
            readSteps()
            // The pedometer will push updates, but only while the app is on screen, and the count that matters is the
            // whole day's. Once a minute, and again whenever the app comes back.
            watching.clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.readSteps() }
            }
        }
    }

    private func readSteps() {
        let dayStart = Calendar.current.startOfDay(for: Date())
        pedometer.queryPedometerData(from: dayStart, to: Date()) { [weak self] data, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.problem = "The phone would not share the day's steps: \(error.localizedDescription)"
                    return
                }
                guard let data else { return }
                self.steps = data.numberOfSteps.intValue
            }
        }
    }

    private func stop() {
        altimeter.stopRelativeAltitudeUpdates()
        pedometer.stopUpdates()
        watching.clock?.invalidate()
        watching.clock = nil
        pressure = nil
        firstPressure = nil
        steps = nil
        problem = nil
    }

    /// The app has come back on screen: the day's steps will have moved on.
    func cameBack() {
        guard isOn, hasStepCounter else { return }
        readSteps()
    }

    // MARK: - Saying it

    /// What each sense is reading, in words, for the panel.
    var summary: [(name: String, value: String)] {
        var said: [(String, String)] = []
        if !hasBarometer {
            said.append(("Air pressure", "this phone has no barometer"))
        } else if let pressure {
            let turning = weatherDrift ?? 0
            let word = turning < -0.2 ? ", falling" : (turning > 0.2 ? ", rising" : ", steady")
            said.append(("Air pressure", "\(Int(pressure.rounded())) hPa\(word)"))
        } else {
            said.append(("Air pressure", isOn ? "reading…" : "off"))
        }
        if !hasStepCounter {
            said.append(("Steps today", "this phone does not count them"))
        } else if let steps {
            said.append(("Steps today", steps.formatted()))
        } else {
            said.append(("Steps today", isOn ? "reading…" : "off"))
        }
        said.append(("The sun", sun.map { $0 < -0.3 ? "low in the east" : ($0 > 0.3 ? "low in the west" : "high") } ?? "down"))
        said.append(("The room", isDarkRoom ? "dark" : "bright enough"))
        return said.map { (name: $0.0, value: $0.1) }
    }
}

/// Holds the things `RoomSenses` has to let go of, and lets go of them.
///
/// Its own object, isolated to nothing, for the same reason as `PowerWatchers`: a `deinit` may not touch anything that
/// belongs to an actor, and these are exactly what has to be cancelled.
private final class SenseWatchers {
    var observers: [NSObjectProtocol] = []
    var clock: Timer?

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        clock?.invalidate()
    }
}
