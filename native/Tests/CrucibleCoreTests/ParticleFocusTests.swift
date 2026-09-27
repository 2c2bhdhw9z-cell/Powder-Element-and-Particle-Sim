import Foundation
import Testing

@testable import CrucibleCore

/// Camera focus and flying into the box.
@Suite("Camera focus and flying in")
struct ParticleFocusTests {
    private let world = (width: 1_320.0, height: 2_868.0, depth: 1_320.0)

    private func project(_ camera: ParticleCamera, _ x: Double, _ y: Double, _ z: Double) -> ParticleDepthProjection {
        camera.projectInDepth(
            x: x, y: y, z: z,
            worldWidth: world.width, worldHeight: world.height, worldDepth: world.depth,
            viewWidth: world.width, viewHeight: world.height
        )
    }

    @Test("Not flying in, the eye is exactly where it always was")
    func notFlyingChangesNothing() {
        for perspective in [0.0, 0.0005, 0.01, 0.04, 0.05, 0.3, 0.7, 1.0] {
            var camera = ParticleCamera()
            camera.perspective = perspective
            let expected: Double? = perspective > 0.001 ? min(40, 2 / perspective) * world.height * 0.5 : nil
            #expect(camera.eyeDistance(worldHeight: world.height) == expected, "perspective \(perspective)")
        }
    }

    @Test("Flying in brings the eye steadily to the middle of the box, even with no perspective")
    func flyingInApproachesTheMiddle() {
        var camera = ParticleCamera()
        camera.perspective = 0.7
        var last = Double.infinity
        for step in 0 ... 20 {
            camera.flyIn = Double(step) / 20
            let eye = camera.eyeDistance(worldHeight: world.height) ?? .nan
            #expect(eye < last || step == 0, "the eye went backwards at \(step)")
            last = eye
        }
        #expect(abs(last - world.height * ParticleCamera.flyInClosest) < 1e-6)
        camera.perspective = 0
        camera.flyIn = 0.5
        #expect(camera.eyeDistance(worldHeight: world.height) != nil, "no perspective left no eye to fly")
    }

    @Test("From inside, what is behind the eye is not drawn and what is ahead surrounds it")
    func insideTheBox() {
        var camera = ParticleCamera()
        camera.look(yaw: 0, pitch: 0)
        camera.flyIn = 1
        let middle = (x: world.width / 2, y: world.height / 2)
        // Behind: toward the viewer, past the eye.
        #expect(!project(camera, middle.x, middle.y, -400).isInFront)
        // Ahead: into the box, and drawn larger the nearer it is.
        let near = project(camera, middle.x, middle.y, 60)
        let far = project(camera, middle.x, middle.y, 600)
        #expect(near.isInFront && far.isInFront)
        #expect(near.scale > far.scale)
        // Something a little to one side and a little ahead is thrown far out toward the edge, as it is from inside.
        let beside = project(camera, middle.x + 60, middle.y, 60)
        #expect(abs(beside.x) > 0.3)
    }

    @Test("Not flying in, the lens is the eye's own distance, so the picture is exactly what it was")
    func lensUnchangedOutside() {
        for perspective in [0.0, 0.01, 0.3, 0.7, 1.0] {
            var camera = ParticleCamera()
            camera.perspective = perspective
            #expect(camera.focalLength(worldHeight: world.height) == camera.eyeDistance(worldHeight: world.height))
        }
        var camera = ParticleCamera()
        camera.flyIn = 1
        let eye = camera.eyeDistance(worldHeight: world.height)!
        let lens = camera.focalLength(worldHeight: world.height)!
        #expect(abs(lens - world.height * ParticleCamera.flyInLens) < 1e-6)
        // Inside, the middle of the box is drawn many times larger: that is what being close to it looks like.
        #expect(lens / eye > 10)
    }

    @Test("Turning round somewhere else puts that place in the middle of the picture, and it can be flown to")
    func turningRoundAPlace() {
        var camera = ParticleCamera()
        camera.look(yaw: 35, pitch: 20)
        camera.centreX = 300
        camera.centreY = -500
        camera.centreZ = 200
        let place = (x: world.width / 2 + 300, y: world.height / 2 - 500, z: 200.0)
        let drawn = project(camera, place.x, place.y, place.z)
        #expect(abs(drawn.x) < 1e-9 && abs(drawn.y) < 1e-9, "the place turned round was not in the middle")
        // Flown right in, it is still there, right in front of the eye.
        camera.flyIn = 1
        let close = project(camera, place.x, place.y, place.z)
        #expect(abs(close.x) < 1e-9 && abs(close.y) < 1e-9 && close.isInFront)
        // And near and far still run from nought to one across the whole box, from wherever the view turns round.
        for corner in [(0.0, 0.0, -660.0), (world.width, world.height, 660.0), (0.0, world.height, 660.0)] {
            let depth = project(camera, corner.0, corner.1, corner.2).depth
            #expect(depth > 0 && depth < 1, "a corner of the box fell outside near and far")
        }
        var reset = camera
        reset.reset()
        #expect(!reset.isOffCentre && reset.flyIn == 0)
    }

    @Test("Flown in, the finger reaches what its ring covers, not far past it")
    func reachInside() {
        var camera = ParticleCamera()
        camera.look(yaw: 0, pitch: 0)
        let outside = camera.fingerRay(
            screenX: world.width / 2, screenY: world.height / 2,
            worldWidth: world.width, worldHeight: world.height, worldDepth: world.depth,
            viewWidth: world.width, viewHeight: world.height
        )
        #expect(outside.reachScale == 1)
        camera.flyIn = 1
        let inside = camera.fingerRay(
            screenX: world.width / 2, screenY: world.height / 2,
            worldWidth: world.width, worldHeight: world.height, worldDepth: world.depth,
            viewWidth: world.width, viewHeight: world.height
        )
        let eye = camera.eyeDistance(worldHeight: world.height)!
        let lens = camera.focalLength(worldHeight: world.height)!
        #expect(abs(inside.reachScale - eye / lens) < 1e-9)
        // A body at the middle of the box, a ring's width to the side as drawn, is at the edge of what it reaches.
        let ring = 100.0
        #expect(abs(inside.reach(ring, at: inside.focusDistance) - ring * eye / lens) < 1e-6)
    }

    @Test("Flown in or not, and turning round anywhere, a finger's line goes through what is drawn under it")
    func fingerLineWhenFlownIn() {
        var rng = Mulberry32(seed: 7)
        var checked = 0
        for _ in 0 ..< 300 {
            var camera = ParticleCamera(zoom: 0.6 + rng.next() * 2)
            camera.look(yaw: (rng.next() - 0.5) * 360, pitch: (rng.next() - 0.5) * 170)
            camera.perspective = rng.next() < 0.2 ? 0 : rng.next()
            camera.flyIn = rng.next()
            if rng.next() < 0.5 {
                camera.centreX = (rng.next() - 0.5) * world.width
                camera.centreY = (rng.next() - 0.5) * world.height
                camera.centreZ = (rng.next() - 0.5) * world.depth
            }
            let point = (x: rng.next() * world.width, y: rng.next() * world.height, z: (rng.next() - 0.5) * world.depth)
            let drawn = project(camera, point.x, point.y, point.z)
            guard drawn.isInFront, abs(drawn.x) < 4, abs(drawn.y) < 4 else { continue }
            let ray = camera.fingerRay(
                screenX: (drawn.x + 1) * 0.5 * world.width, screenY: (1 - drawn.y) * 0.5 * world.height,
                worldWidth: world.width, worldHeight: world.height, worldDepth: world.depth,
                viewWidth: world.width, viewHeight: world.height
            )
            let near = ray.nearest(toX: point.x, y: point.y, z: point.z)
            let gap = ((near.x - point.x) * (near.x - point.x) + (near.y - point.y) * (near.y - point.y)
                + (near.z - point.z) * (near.z - point.z)).squareRoot()
            #expect(gap < 1e-3 * world.height, "the line missed what was drawn under the finger by \(gap)")
            checked += 1
        }
        #expect(checked > 100)
    }

    @Test("Focus is sharp at its distance and soft either side, and off means sharp everywhere")
    func focusRule() {
        var camera = ParticleCamera()
        #expect(!camera.focuses)
        #expect(camera.outOfFocus(atDepth: 0.1) == 0)
        camera.focusBlur = 1
        camera.focusAt = 0.4
        #expect(camera.outOfFocus(atDepth: 0.4) == 0)
        #expect(camera.outOfFocus(atDepth: 0.45) > 0 && camera.outOfFocus(atDepth: 0.45) < 0.5)
        #expect(camera.outOfFocus(atDepth: 0.9) == 1)
        #expect(abs(camera.outOfFocus(atDepth: 0.3) - camera.outOfFocus(atDepth: 0.5)) < 1e-9)
        camera.focusBlur = 0.2
        #expect(camera.outOfFocus(atDepth: 0.5) < 0.2 * ParticleCamera.focusFalloff * 0.1 + 1e-9)
        #expect(camera.outOfFocus(atDepth: .nan) == 0)
    }

    @Test("Focus and flying in are saved with the view, and an older view opens without them")
    func savedWithTheView() throws {
        var camera = ParticleCamera()
        camera.focusBlur = 0.65
        camera.focusAt = 0.2
        camera.flyIn = 0.8
        let text = try JSONEncoder().encode(camera)
        let back = try JSONDecoder().decode(ParticleCamera.self, from: text)
        #expect(back.focusBlur == 0.65 && back.focusAt == 0.2 && back.flyIn == 0.8)

        let older = try JSONDecoder().decode(ParticleCamera.self, from: Data(#"{"zoom": 1.5, "orbitYaw": 10}"#.utf8))
        #expect(older.focusBlur == 0 && older.focusAt == 0.5 && older.flyIn == 0)
        #expect(older.zoom == 1.5)

        let silly = ParticleCamera(focusBlur: 9, focusAt: -4, flyIn: .nan, centreX: .infinity, centreY: 1e12)
        #expect(silly.focusBlur == 1 && silly.focusAt == 0 && silly.flyIn == 0)
        #expect(silly.centreX == 0 && silly.centreY == 100_000)

        var flown = ParticleCamera()
        flown.centreX = 12
        flown.centreZ = -40
        let reread = try JSONDecoder().decode(ParticleCamera.self, from: try JSONEncoder().encode(flown))
        #expect(reread.centreX == 12 && reread.centreZ == -40)
    }
}
