import SwiftUI

/// Crucible.
///
/// The app is a thin shell around `CrucibleCore`, which holds the entire simulation and can
/// be built and tested on any machine with no Apple frameworks involved. Everything in this
/// target is display, touch and platform plumbing.
@main
struct CrucibleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
