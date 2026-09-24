import CoreMotion
import CrucibleCore
import Foundation
import Observation

/// Reads how the phone is being held, and hands it to ``TiltMapping``.
///
/// Only the hardware part is here. Every number that decides how tilting *feels* lives in
/// `TiltMapping` in the engine, where it can be tested on a machine with no accelerometer.
///
/// ## Three states, not two
///
/// Tapping the button cycles **off → on → locked → off**, matching the web version. Locked is
/// the one that needs explaining: it freezes gravity wherever the phone was pointing, so a
/// world can be tipped over and then brought back level to look at, without everything sliding
/// back. Jolts still register while locked — a lock holds *which way is down*, and shaking a
/// tilted world should still rattle it loose.
@MainActor
@Observable
final class TiltSensor {
    /// What the button should say, and what the app is allowed to do.
    enum Status: Equatable {
        /// Available, not running.
        case off
        /// Running and following the phone.
        case on
        /// Running, but gravity is held where it was.
        case locked
        /// The person said no. Only they can undo that, in Settings.
        case denied
        /// This device cannot do it at all.
        case unavailable
    }

    private(set) var status: Status = .off

    /// The gravity and shake the simulation should use.
    private(set) var mapping = TiltMapping()

    /// Whether the simulation should be reading ``mapping`` at all.
    var isSteering: Bool { status == .on || status == .locked }

    private let motion = CMMotionManager()

    /// Sixty readings a second, matching what a browser delivers.
    ///
    /// Not a performance knob. The shake decays by a fixed fraction per *reading*, so asking
    /// for readings faster would make an identical knock fade sooner — a behaviour change
    /// disguised as a settings value. See `TiltMapping.shakeDecay`.
    private static let updateInterval = 1.0 / 60

    // MARK: Control

    /// Advances the three-state cycle.
    func advance() {
        switch status {
        case .off: start()
        case .on: status = .locked
        case .locked: stop()
        // Nothing to cycle through. Tapping again should not silently retry a request the
        // system will now refuse without showing anything, which looks like a dead button.
        case .denied, .unavailable: break
        }
    }

    private func start() {
        guard motion.isDeviceMotionAvailable else {
            status = .unavailable
            return
        }

        motion.deviceMotionUpdateInterval = Self.updateInterval
        // The arbitrary-Z-vertical frame is the cheap one: it settles immediately and needs no
        // magnetometer. Which compass direction the world faces is not used — only how the
        // phone is tilted relative to vertical — so paying for a true-north reference would buy
        // nothing and can leave the reading drifting while it calibrates.
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, error in
            guard let self else { return }
            if error != nil {
                // The only realistic cause on a modern phone is motion access being refused,
                // and the request is not something to keep retrying silently.
                self.status = .denied
                self.motion.stopDeviceMotionUpdates()
                return
            }
            guard let data else { return }
            self.consume(data)
        }
        status = .on
    }

    private func stop() {
        motion.stopDeviceMotionUpdates()
        status = .off
        // Gravity goes back to straight down. Left tilted, switching the feature off would
        // appear to have done nothing.
        mapping.reset()
    }

    // MARK: Readings

    private func consume(_ data: CMDeviceMotion) {
        // Shake first, and unconditionally, because it keeps working while locked.
        //
        // CoreMotion reports both parts in multiples of gravity; a browser reports their sum in
        // metres per second squared. The threshold the mapping uses is in the browser's units,
        // so the conversion happens here rather than there.
        let combinedX = data.gravity.x + data.userAcceleration.x
        let combinedY = data.gravity.y + data.userAcceleration.y
        let combinedZ = data.gravity.z + data.userAcceleration.z
        mapping.apply(
            accelerationX: combinedX * Self.gravityInMetresPerSecondSquared,
            y: combinedY * Self.gravityInMetresPerSecondSquared,
            z: combinedZ * Self.gravityInMetresPerSecondSquared
        )

        guard status == .on else { return }
        let angles = Self.orientationAngles(
            gravityX: data.gravity.x,
            gravityY: data.gravity.y,
            gravityZ: data.gravity.z
        )
        mapping.apply(betaDegrees: angles.beta, gammaDegrees: angles.gamma)
    }

    /// Standard gravity, for converting CoreMotion's multiples-of-g into a browser's units.
    private static let gravityInMetresPerSecondSquared = 9.80665

    // MARK: Attitude

    /// The two angles a browser's orientation event reports, worked out from the gravity vector.
    ///
    /// ## Why gravity rather than the attitude quaternion
    ///
    /// CoreMotion also offers an attitude, and converting that to a browser's angles is the
    /// textbook route. It is also the one that quietly goes wrong: the two use different
    /// reference frames and different rotation orders, the conventions are easy to get
    /// backwards, and being wrong looks like "tilt is mirrored" rather than like an error —
    /// which is not something that can be caught without a device to hold.
    ///
    /// The gravity vector avoids all of it. Apple documents it plainly as which way down is, in
    /// the device's own axes, and that is exactly what the two angles describe. Three positions
    /// anyone can check by hand pin the whole thing down: flat and face up is (0, 0), upright is
    /// (90, 0), and rolled onto its right edge is (0, 90).
    ///
    /// ## How it is derived
    ///
    /// A browser's angles compose as a rotation about Z, then the new X, then the new Y. Taking
    /// that rotation as device-to-world, the world's up direction in the device's own axes is
    /// its third row — `(-cos β sin γ, sin β, cos β cos γ)` — and gravity is the negation of
    /// that. Inverting those three equations gives what is below.
    ///
    /// Verified numerically before it was written: composing gravity from every attitude at half
    /// a degree over the full declared range and running it back through this reproduces the
    /// original direction to within 2.4e-15. That check found two real errors in the first
    /// attempt — a sign, and the upright case being mistaken for the edge-on one.
    ///
    /// - Parameters are the components of `CMDeviceMotion.gravity`.
    /// - Returns: beta, the front-to-back tilt in −180..<180, and gamma, the left-to-right
    ///   roll in −90...90. Both in degrees.
    static func orientationAngles(
        gravityX: Double,
        gravityY: Double,
        gravityZ: Double
    ) -> (beta: Double, gamma: Double) {
        let toDegrees = 180 / Double.pi
        // The three matrix entries gravity determines, recovered from its negation.
        let m31 = -gravityX
        let m32 = -gravityY
        let m33 = -gravityZ
        // Clamped because a sensor reading slightly longer than one unit would otherwise make
        // the arcsine not a number, and that would reach gravity.
        let sinBeta = max(-1, min(1, m32))

        // Edge-on. The phone is upright or upside down, cos β is nought, and rolling about the
        // phone's own long axis no longer changes anything gravity can see — so the roll simply
        // is not recoverable. Zero is the conventional answer, and the alternative is an
        // arbitrary value that would make gravity jump as the phone passes vertical.
        if abs(sinBeta) >= 1 - 1e-12 {
            return (sinBeta > 0 ? 90 : -90, 0)
        }
        if m33 > 0 {
            // Screen facing upward: the tilt is within a quarter turn of flat.
            return (Foundation.asin(sinBeta) * toDegrees, Foundation.atan2(-m31, m33) * toDegrees)
        }
        if m33 < 0 {
            // Screen facing downward: the same sine describes a tilt past the quarter turn.
            var beta = 180 - Foundation.asin(sinBeta) * toDegrees
            // Brought into the declared range, which stops at 180 rather than including it.
            if beta >= 180 { beta -= 360 }
            return (beta, Foundation.atan2(m31, -m33) * toDegrees)
        }
        // Exactly side-on, with the tilt away from vertical: it is the roll that is at a
        // quarter turn.
        return (Foundation.asin(sinBeta) * toDegrees, -m31 > 0 ? 90 : -90)
    }
}
