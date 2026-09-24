import SwiftUI

#if canImport(Darwin)
    import Darwin
#endif

/// Crucible.
///
/// The app is a thin shell around `CrucibleCore`, which holds the entire simulation and can be
/// built and tested on any machine with no Apple frameworks involved. Everything in this target
/// is display, touch and platform plumbing.
@main
struct CrucibleApp: App {
    init() {
        DebugSettings.applyGraphicsOverlayPreference()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Switches Apple's own graphics overlay on and off.
///
/// ## Why this needs the app reopened
///
/// The overlay in the screenshots — device name, memory, GPU timings, the vertex and fragment
/// bars — is built into Metal itself, not into this app. Metal decides whether to draw it by
/// reading an environment variable *once*, when the graphics device is first created, and there
/// is no supported way to turn it on or off after that. Apple's own guidance says as much.
///
/// So the switch sets the variable as early as the app can possibly run — before any graphics
/// object exists — and takes effect the next time the app is opened. That is the whole trick:
/// the preference is remembered here, and applied before Metal has had a chance to look.
///
/// It also means the overlay no longer depends on the toggle buried in iOS's own developer
/// settings. Leave that one alone; this one is enough.
enum DebugSettings {
    /// Where the preference is stored. Read here and written by the settings tray.
    static let graphicsOverlayKey = "appleGraphicsOverlayEnabled"

    /// Tells Metal whether to draw its overlay, before Metal is first used.
    ///
    /// Must be called from the app's initialiser and nowhere else. By the time any view exists
    /// the graphics device has been created and the variable will be ignored.
    static func applyGraphicsOverlayPreference() {
        #if canImport(Darwin)
            let enabled = UserDefaults.standard.bool(forKey: graphicsOverlayKey)
            // Overwrites any existing value, so turning the switch off really does turn the
            // overlay off rather than leaving whatever was set before.
            setenv("MTL_HUD_ENABLED", enabled ? "1" : "0", 1)
        #endif
    }

    /// Whether the overlay is currently being drawn.
    ///
    /// Read from the environment rather than from the preference, because the two disagree
    /// exactly when it matters: after the switch has been changed and before the app has been
    /// reopened. That difference is what the settings tray uses to say so.
    static var graphicsOverlayIsActive: Bool {
        #if canImport(Darwin)
            guard let value = getenv("MTL_HUD_ENABLED") else { return false }
            return String(cString: value) == "1"
        #else
            return false
        #endif
    }
}
