import CoreMotion
import Foundation

/// Reads how the phone is tipped, for looking round the field in 3D by moving the phone.
///
/// ## What it does
///
/// With it on, the phone becomes a window into the box: lean it to the right and the view goes round to the
/// right side of what is in there; tip its top away and the view rises to look down into it. Only by a little —
/// a few tens of degrees at most — because it is for peering round something, not for turning it over, which
/// the Turn tool and the sliders are for. It settles smoothly rather than following every tremor of a hand.
///
/// ## Why the tilt rather than the phone's full attitude
///
/// The same reason as the Tilt button's (see `TiltSensor.orientationAngles`): which way down is, measured in the
/// phone's own directions, is the one reading whose meaning is not in doubt, and a mistake in converting a full
/// attitude looks like "the view turns the wrong way" rather than like an error. Turning on the spot — about the
/// upright — is the one movement this cannot see, and it is also the one a person holding a phone to look at it
/// does not make.
///
/// Its own motion manager, started only while it is wanted. The Tilt button's is started only while that is
/// on, so the two only run together when somebody has asked for both.
@MainActor
final class LookSensor {
    private let motion = CMMotionManager()
    /// How the phone was held when looking round began: the view it gives is the one already on the screen.
    private var reference: (beta: Double, gamma: Double)?

    /// How far round the box the phone has turned the view, in degrees.
    private(set) var yaw: Double = 0
    /// How far up or down it has tipped the view, in degrees.
    private(set) var pitch: Double = 0

    /// The furthest the phone turns the view either way.
    static let largestTurn = 28.0
    /// How much of the way toward where the phone points the view moves each reading. Small, so it glides.
    private static let easing = 0.18

    var isRunning: Bool { motion.isDeviceMotionActive }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        reference = nil
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, error in
            guard let self, error == nil, let data else { return }
            self.consume(data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        reference = nil
        yaw = 0
        pitch = 0
    }

    /// Takes however the phone is held now as looking straight at the view.
    func recentre() {
        reference = nil
    }

    private func consume(_ data: CMDeviceMotion) {
        let angles = TiltSensor.orientationAngles(
            gravityX: data.gravity.x,
            gravityY: data.gravity.y,
            gravityZ: data.gravity.z
        )
        guard let reference else {
            self.reference = angles
            return
        }
        var tip = angles.beta - reference.beta
        if tip > 180 { tip -= 360 }
        if tip < -180 { tip += 360 }
        let lean = angles.gamma - reference.gamma
        // Lean right to see round the right side; tip the top away to look down into the box.
        let wantedYaw = max(-Self.largestTurn, min(Self.largestTurn, -lean * 0.9))
        let wantedPitch = max(-Self.largestTurn, min(Self.largestTurn, -tip * 0.9))
        guard wantedYaw.isFinite, wantedPitch.isFinite else { return }
        yaw += (wantedYaw - yaw) * Self.easing
        pitch += (wantedPitch - pitch) * Self.easing
    }
}
