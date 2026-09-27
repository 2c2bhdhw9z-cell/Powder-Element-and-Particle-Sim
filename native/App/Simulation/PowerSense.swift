import CrucibleCore
import Foundation
import SwiftUI
import UIKit

/// Reads how warm the phone is, whether it has been asked to save power, and what the lab is costing the battery — and
/// hands the readings to `PowerPolicy`, which decides what to do about them.
///
/// Every decision is in the engine, where it is tested. This is the reading and the plumbing: the notifications iOS
/// sends, the one switch that has to be turned on before the battery can be read at all, and the timer that watches the
/// charge fall.
@MainActor
@Observable
final class PowerSense {
    /// What the phone currently says.
    private(set) var readings = PowerPolicy.Readings()
    /// What to do about it.
    private(set) var advice = PowerPolicy.advice(for: PowerPolicy.Readings())
    /// What the lab is costing the battery, measured from the charge falling.
    private(set) var cost = BatteryCost()

    /// Whether to obey any of this. Somebody who would rather the app simply ran flat out can say so.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            refresh()
        }
    }

    /// What to do, or nothing to do when this has been switched off.
    var inEffect: PowerPolicy.Advice {
        isEnabled ? advice : PowerPolicy.advice(for: PowerPolicy.Readings())
    }

    /// What has to be let go of, in something that is nobody's actor — see `PowerWatchers`.
    private let watching = PowerWatchers()
    private let startedAt = CFAbsoluteTimeGetCurrent()

    init() {
        // Without this the charge reads as minus one for ever. It is a device-wide switch that costs nothing and tells
        // nobody anything: it only lets this app read its own phone's battery.
        UIDevice.current.isBatteryMonitoringEnabled = true
        watch(ProcessInfo.thermalStateDidChangeNotification)
        watch(.NSProcessInfoPowerStateDidChange)
        watch(UIDevice.batteryLevelDidChangeNotification)
        watch(UIDevice.batteryStateDidChangeNotification)
        // A phone reports its charge in whole percents, so there is nothing to gain from reading it often. Once a
        // minute is enough to divide by, and the notifications above catch every real change anyway.
        watching.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    private func watch(_ name: Notification.Name) {
        let watcher = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            // Hopped onto the main actor rather than assumed to be on it: the queue is right, the compiler cannot know it.
            Task { @MainActor in self?.refresh() }
        }
        watching.observers.append(watcher)
    }

    /// Takes every reading again and works out what to do.
    func refresh() {
        let device = UIDevice.current
        let charge = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        let plugged = device.batteryState == .charging || device.batteryState == .full
        readings = PowerPolicy.Readings(
            heat: Self.heat(ProcessInfo.processInfo.thermalState),
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            charge: charge,
            isCharging: plugged
        )
        advice = PowerPolicy.advice(for: readings)
        cost.note(charge: charge, isCharging: plugged, seconds: CFAbsoluteTimeGetCurrent() - startedAt)
    }

    /// The app has been put away or brought back. Time spent away is not time the lab was costing anything, so what was
    /// being measured is thrown away rather than averaged with it.
    func sceneChanged(active: Bool) {
        if !active { cost.forget() }
        refresh()
    }

    private static func heat(_ state: ProcessInfo.ThermalState) -> PowerPolicy.Heat {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }

    // MARK: - Saying it

    /// How much charge the lab uses an hour, in words, or why there is no figure yet.
    var costInWords: String {
        if readings.isCharging { return "On charge, so there is nothing to measure." }
        guard let share = cost.shareAnHour else {
            return "Measuring — a figure appears once a percent of charge has gone."
        }
        var said = "About \(Int((share * 100).rounded()))% of the battery an hour"
        if let hours = cost.hoursLeft(charge: readings.charge) {
            let minutes = Int((hours * 60).rounded())
            said += minutes >= 60
                ? ", so about \(minutes / 60)h \(minutes % 60)m left at this rate"
                : ", so about \(minutes) minutes left at this rate"
        }
        return said + "."
    }

    /// How warm the phone says it is, in words.
    var heatInWords: String {
        switch readings.heat {
        case .nominal: "Cool"
        case .fair: "Warming up"
        case .serious: "Hot"
        case .critical: "Very hot"
        }
    }
}

/// Holds the things `PowerSense` has to let go of, and lets go of them.
///
/// Its own object, and deliberately isolated to nothing, because a `deinit` may not touch anything that belongs to an
/// actor — and `PowerSense` belongs to the main one. These are not state anybody reads; they are a bag of things to
/// cancel, which is exactly what can live out here.
private final class PowerWatchers {
    var observers: [NSObjectProtocol] = []
    var timer: Timer?

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        timer?.invalidate()
    }
}
