import CrucibleCore
import SwiftUI
import UIKit

/// The field on a television, with the phone left holding the controls.
///
/// ## Why this needs no extension, and why that matters
///
/// A second screen is a second window on the same app: the phone notices a screen has been connected and puts a window
/// on it. Nothing is installed, nothing is signed separately, and no capability is asked for — which matters more here
/// than it would in most apps, because this one is signed on the device it is installed on, and an app extension is
/// exactly the thing that makes that fail.
///
/// ## What goes on which screen
///
/// The television gets the field and nothing else: no tray, no tools, no readouts. The phone keeps all of it. That is
/// the arrangement worth having — somebody watching sees the world, and whoever is holding the phone is working the
/// controls without their hands in the picture.
///
/// The powder world is not offered on the television, and the reason is worth stating: it is drawn at one cell per
/// screen pixel, so a television would mean a grid four or five times the size, which is four or five times the cost of
/// every moment. The field costs the same whatever it is drawn on, because the bodies are the cost and not the pixels.
@MainActor
@Observable
final class BigScreen {
    /// The field being shown, handed over by the app.
    private weak var field: ParticleFieldModel?

    /// Whether a second screen currently has the field on it.
    private(set) var isShowing = false
    /// What the screen is called, roughly — its size in pixels, since a television does not tell an app its name.
    private(set) var describes: String?
    /// Whether anything is connected at all.
    private(set) var isAvailable = false

    private var window: UIWindow?
    private let watching = BigScreenWatchers()

    init() {
        watch()
        isAvailable = Self.otherScene() != nil
    }

    // MARK: - Noticing a screen

    private func watch() {
        for name in [UIScene.didActivateNotification, UIScene.didDisconnectNotification] {
            let watcher = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screensChanged() }
            }
            watching.observers.append(watcher)
        }
    }

    private func screensChanged() {
        let other = Self.otherScene()
        isAvailable = other != nil
        // Unplugged while showing: the window goes with the screen, so this only has to notice.
        if other == nil, isShowing { stop() }
    }

    /// A scene that is not the phone's own, if one is connected.
    ///
    /// Asked of the scenes rather than of `UIScreen.screens`, which Apple has retired: a connected screen shows up as a
    /// window scene of its own, and that is the thing a window can be put on.
    private static func otherScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // The phone's own is the one holding the app's windows already.
        return scenes.first { scene in
            scene.windows.allSatisfy { !$0.isKeyWindow } && scene.session.role == .windowExternalDisplayNonInteractive
        } ?? scenes.first { $0.session.role == .windowExternalDisplayNonInteractive }
    }

    // MARK: - Showing it

    /// Whichever field to show. Held weakly: the app owns it, and this must not keep it alive.
    func use(_ field: ParticleFieldModel) {
        self.field = field
    }

    /// Puts the field on the connected screen. Does nothing if there is none.
    func start() {
        guard !isShowing, let scene = Self.otherScene(), let field else { return }
        let made = UIWindow(windowScene: scene)
        made.rootViewController = UIHostingController(
            rootView: BigScreenView(model: field)
        )
        made.rootViewController?.view.backgroundColor = .black
        made.isHidden = false
        made.makeKeyAndVisible()
        window = made
        isShowing = true
        // Its size in pixels, which is the only thing a television tells an app about itself.
        let size = scene.screen.bounds.size
        let scale = scene.screen.scale
        describes = "\(Int(size.width * scale)) × \(Int(size.height * scale))"
    }

    /// Takes the field off the screen again.
    func stop() {
        window?.isHidden = true
        window = nil
        isShowing = false
        describes = nil
    }

    /// One line for the panel: what is on the television, or what could be.
    var summary: String {
        if isShowing { return "On the second screen\(describes.map { ", \($0)" } ?? "")" }
        if isAvailable { return "A second screen is connected" }
        return "Connect a screen, or mirror to one, and the field can fill it"
    }
}

/// The field alone, for a screen nobody is touching.
///
/// No tray, no tools, no readouts, and no gestures: it is a picture. The phone keeps every control, which is the whole
/// point of the arrangement.
private struct BigScreenView: View {
    let model: ParticleFieldModel

    var body: some View {
        GeometryReader { geometry in
            let aspect = CGFloat(max(0.000_001, model.engine.width / max(0.000_001, model.engine.height)))
            let available = geometry.size.width / max(1, geometry.size.height)
            let size = available > aspect
                ? CGSize(width: geometry.size.height * aspect, height: geometry.size.height)
                : CGSize(width: geometry.size.width, height: geometry.size.width / aspect)
            FieldSurface(model: model)
                .frame(width: size.width, height: size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        // A second renderer is only another view of the same world. It must never resize that world or compete with
        // the phone's touch/pan measurements; differing screen shapes are handled by the fitted frame above.
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
        .statusBarHidden()
    }
}

/// Holds what has to be let go of when `BigScreen` is thrown away. Isolated to nothing, because a `deinit` may not
/// touch the main actor's things — the same reason `PowerWatchers` exists.
private final class BigScreenWatchers {
    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
