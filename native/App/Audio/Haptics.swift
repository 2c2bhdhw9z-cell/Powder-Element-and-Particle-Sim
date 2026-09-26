import UIKit

/// Taps and thumps felt through the phone.
///
/// One place for all of them, so that the switch in Settings is honoured everywhere by construction: nothing
/// in the app makes the phone buzz except by coming through here, and everything here checks the switch
/// first.
///
/// Built on UIKit's feedback generators, which need no permission, no entitlement and nothing extra in the
/// app — so they cannot make signing the app on the phone any harder than it already is.
///
/// ## What is felt, and why each is the weight it is
///
/// - **A selection** — choosing a tool, a shape, a material, a colour. The lightest tick there is: these
///   happen constantly and should feel like a detent under the thumb, not like being nudged.
/// - **A light tap** — pressing an ordinary button: play, undo, add bodies.
/// - **A firm tap** — something that changes the whole world: laying out a scene, clearing it.
/// - **A heavy thump** — an explosion, a meteor landing. Sized by how big the event was.
/// - **A warning** — the one double buzz, for something refused: no room left, nothing to undo.
@MainActor
enum Haptics {
    /// Where the switch is kept. Read directly rather than handed around, so every screen agrees.
    nonisolated static let settingKey = "hapticsEnabled"

    /// Whether the phone should buzz at all. On unless somebody has switched it off.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let firmGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let noticeGenerator = UINotificationFeedbackGenerator()

    /// The last moment anything was felt, so a burst of events does not become one continuous rattle.
    private static var lastImpact: CFAbsoluteTime = 0

    /// A detent: something was chosen from a set.
    static func selection() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    /// An ordinary button.
    static func tap() {
        guard isEnabled else { return }
        lightGenerator.impactOccurred()
    }

    /// Something that changes the whole world.
    static func firm() {
        guard isEnabled else { return }
        firmGenerator.impactOccurred()
    }

    /// A finger coming down on the world to paint or push.
    static func touchDown() {
        guard isEnabled else { return }
        softGenerator.impactOccurred(intensity: 0.55)
    }

    /// An explosion or an impact, from nought to one.
    ///
    /// Spaced out to at most one every tenth of a second: a chain of twenty blasts in one moment is felt as a
    /// single hard thump rather than as a phone buzzing itself off the table.
    static func impact(strength: Double) {
        guard isEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastImpact > 0.1 else { return }
        lastImpact = now
        let amount = CGFloat(max(0.2, min(1, strength)))
        heavyGenerator.impactOccurred(intensity: amount)
    }

    /// Something was refused.
    static func refused() {
        guard isEnabled else { return }
        noticeGenerator.notificationOccurred(.warning)
    }

    /// Something finished well — a save, a share, a repair.
    static func success() {
        guard isEnabled else { return }
        noticeGenerator.notificationOccurred(.success)
    }
}
