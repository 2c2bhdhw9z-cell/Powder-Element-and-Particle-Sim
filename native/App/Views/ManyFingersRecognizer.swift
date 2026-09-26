import UIKit

/// Reports every finger on the field, from the moment each one lands.
///
/// ## Why this is not one of the system's own recognisers
///
/// None of them does this. A long press reports the first finger and treats the rest as a reason to cancel; a pan
/// reports a group of fingers as one average place and needs movement before it begins. What the field wants is
/// every finger separately and immediately, because each one is its own tool.
///
/// So this is the plainest possible recogniser: it never fails, never cancels, and simply says where every finger
/// currently is, each time that changes. Whoever owns it decides what to do with them.
final class ManyFingersRecognizer: UIGestureRecognizer {
    /// Called whenever a finger lands, moves or lifts, with where every finger now is, in the view's own points.
    ///
    /// An empty list means the last finger has gone.
    var onChange: (([CGPoint]) -> Void)?

    /// The fingers currently down, in the order they landed.
    ///
    /// In order on purpose: the first one down stays the first one reported for as long as it is held, so the tool
    /// it is working does not jump to another finger when a second lands or lifts.
    private var touches: [UITouch] = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        // Never gets in the way of anything else — the camera's pinch and twist can run alongside it, and it is up
        // to the view whether they are switched on at all.
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ began: Set<UITouch>, with event: UIEvent) {
        for touch in began where !touches.contains(touch) { touches.append(touch) }
        // Begun rather than recognised, so it keeps receiving moves for as long as a finger is down.
        if state == .possible { state = .began } else { state = .changed }
        report()
    }

    override func touchesMoved(_ moved: Set<UITouch>, with event: UIEvent) {
        state = .changed
        report()
    }

    override func touchesEnded(_ ended: Set<UITouch>, with event: UIEvent) {
        finish(ended)
    }

    override func touchesCancelled(_ cancelled: Set<UITouch>, with event: UIEvent) {
        finish(cancelled)
    }

    override func reset() {
        super.reset()
        touches.removeAll()
    }

    private func finish(_ gone: Set<UITouch>) {
        touches.removeAll { gone.contains($0) }
        report()
        if touches.isEmpty {
            // Ended rather than cancelled, so anything watching sees a clean finish.
            state = .ended
        } else {
            state = .changed
        }
    }

    private func report() {
        guard let view else { return }
        onChange?(touches.map { $0.location(in: view) })
    }
}
