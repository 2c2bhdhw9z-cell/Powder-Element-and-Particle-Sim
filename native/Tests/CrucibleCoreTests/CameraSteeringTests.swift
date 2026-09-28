@testable import CrucibleCore
import Testing

@Suite("Steering with the front camera")
struct CameraSteeringTests {
    @Test("A hand arriving is put where it is, and then followed smoothly")
    func handFollows() throws {
        var steering = HandSteering()
        let nothing = steering.sighted(nil, at: 0)
        #expect(nothing == nil)
        let firstSeen = steering.sighted(HandSighting(x: 0.2, y: 0.3, pinch: 0.2), at: 0.1)
        let first = try #require(firstSeen)
        #expect(first.x == 0.2 && first.y == 0.3)
        let nextSeen = steering.sighted(HandSighting(x: 0.8, y: 0.3, pinch: 0.2), at: 0.15)
        let next = try #require(nextSeen)
        #expect(next.x > 0.2 && next.x < 0.8, "it jumped straight to \(next.x)")
    }

    @Test("A pinch closes and opens again without flickering in between")
    func pinch() throws {
        var steering = HandSteering()
        func pinch(_ amount: Double, _ time: Double) throws -> Bool {
            let seen = steering.sighted(HandSighting(x: 0.5, y: 0.5, pinch: amount), at: time)
            return try #require(seen).grabbing
        }
        #expect(try !pinch(0.2, 0))
        #expect(try pinch(0.03, 0.05))
        // Half open: still closed.
        #expect(try pinch(0.07, 0.1))
        #expect(try !pinch(0.12, 0.15))
        #expect(try !pinch(0.07, 0.2), "half closed from open stays open")
    }

    @Test("A hand missing for a moment is still there; gone for longer, the touch lets go")
    func handPatience() {
        var steering = HandSteering()
        _ = steering.sighted(HandSighting(x: 0.5, y: 0.5, pinch: 0.02), at: 1)
        let briefly = steering.sighted(nil, at: 1.2)
        #expect(briefly != nil)
        let longer = steering.sighted(nil, at: 1.5)
        #expect(longer == nil)
        // And a hand coming back starts open, not still pinching from before.
        let back = steering.sighted(HandSighting(x: 0.4, y: 0.5, pinch: 0.07), at: 2)
        #expect(back?.grabbing == false)
    }

    @Test("A sighting off the picture is kept to its edge, and nonsense is no hand")
    func handEdges() {
        var steering = HandSteering()
        let touch = steering.sighted(HandSighting(x: 1.4, y: -0.2, pinch: 0.2), at: 0)
        #expect(touch?.x == 1 && touch?.y == 0)
        var other = HandSteering()
        let nonsense = other.sighted(HandSighting(x: .nan, y: 0.5, pinch: 0.2), at: 0)
        #expect(nonsense == nil)
    }

    @Test("Where the head starts is straight on; moving it turns the view, as far as it goes and no further")
    func headTurns() {
        var look = HeadLook()
        let start = look.sighted(faceX: 0.5, faceY: 0.5, at: 0)
        #expect(start.yaw == 0 && start.pitch == 0)
        var turned = (yaw: 0.0, pitch: 0.0)
        for step in 1 ... 60 { turned = look.sighted(faceX: 0.65, faceY: 0.5, at: Double(step) / 30) }
        #expect(abs(turned.yaw - HeadLook.largestTurn / 2) < 0.5, "turned \(turned.yaw)")
        for step in 61 ... 120 { turned = look.sighted(faceX: 1.5, faceY: 0.2, at: Double(step) / 30) }
        #expect(abs(turned.yaw - HeadLook.largestTurn) < 0.01)
        #expect(turned.pitch > 0, "lifting the head should look down into the box")
    }

    @Test("With no face for a while the view drifts back to straight on")
    func headDriftsBack() {
        var look = HeadLook()
        _ = look.sighted(faceX: 0.5, faceY: 0.5, at: 0)
        for step in 1 ... 60 { _ = look.sighted(faceX: 0.8, faceY: 0.5, at: Double(step) / 30) }
        var now = (yaw: 0.0, pitch: 0.0)
        for step in 0 ..< 120 { now = look.sighted(faceX: nil, faceY: nil, at: 3 + Double(step) / 30) }
        #expect(abs(now.yaw) < 1)
    }
}
