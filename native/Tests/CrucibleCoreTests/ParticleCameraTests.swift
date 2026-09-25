import Foundation
import Testing

@testable import CrucibleCore

/// The camera over the particle field.
///
/// Tested harder than most of this project, for two reasons. The first is that a camera fault is
/// invisible in the numbers and obvious on the screen — the brush lands in the wrong place, or the
/// picture drifts as it turns — and this project's whole record of interface faults is things a test
/// would have caught if one had existed. The second is that going backwards from the screen to the
/// world is a separate piece of arithmetic from going forwards, and the only thing keeping the two
/// honest is a test that round-trips them.
struct ParticleCameraTests {
    private let world = (width: 400.0, height: 700.0)
    private let view = (width: 400.0, height: 700.0)

    private func project(
        _ camera: ParticleCamera,
        x: Double,
        y: Double
    ) -> ParticleCamera.Projected {
        camera.project(
            x: x,
            y: y,
            worldWidth: world.width,
            worldHeight: world.height,
            viewWidth: view.width,
            viewHeight: view.height
        )
    }

    private func unproject(
        _ camera: ParticleCamera,
        x: Double,
        y: Double
    ) -> (x: Double, y: Double) {
        camera.unproject(
            screenX: x,
            screenY: y,
            worldWidth: world.width,
            worldHeight: world.height,
            viewWidth: view.width,
            viewHeight: view.height
        )
    }

    // MARK: - Doing nothing

    @Test("An untouched camera changes nothing at all")
    func identityIsExact() {
        // Not approximately. A field with the camera left alone must draw bit for bit as it did
        // before the camera existed, or every recorded comparison in this project becomes a
        // comparison against a slightly different picture.
        let camera = ParticleCamera.identity
        #expect(camera.isIdentity)
        #expect(!camera.isRotated)

        for point in [(0.0, 0.0), (400.0, 700.0), (200.0, 350.0), (17.0, 613.0)] {
            let projected = project(camera, x: point.0, y: point.1)
            #expect(projected.x == (point.0 / 400) * 2 - 1)
            #expect(projected.y == 1 - (point.1 / 700) * 2)
            #expect(projected.depthScale == 1, "no turn means no change of size")
        }
    }

    @Test("The corners of the world land on the corners of the screen")
    func cornersMapToCorners() {
        let camera = ParticleCamera.identity
        let topLeft = project(camera, x: 0, y: 0)
        #expect(topLeft.x == -1)
        #expect(topLeft.y == 1, "the top of the world is the top of the screen")

        let bottomRight = project(camera, x: 400, y: 700)
        #expect(bottomRight.x == 1)
        #expect(bottomRight.y == -1)

        let middle = project(camera, x: 200, y: 350)
        #expect(abs(middle.x) < 1e-12)
        #expect(abs(middle.y) < 1e-12)
    }

    @Test("A rotation too small to see is treated as none")
    func tinyRotationsAreIdentity() {
        // The early exit is a guarantee rather than a speed trick, so it has to trigger on the
        // values that reach it in practice — a slider returning to zero rarely returns exactly.
        var camera = ParticleCamera.identity
        camera.yaw = 1e-12
        camera.pitch = -1e-12
        #expect(!camera.isRotated)
        let projected = project(camera, x: 123, y: 456)
        #expect(projected.depthScale == 1)
    }

    // MARK: - Limits

    @Test("Zoom cannot go past its limits, however it is reached")
    func zoomIsClamped() {
        #expect(ParticleCamera(zoom: 0).zoom == ParticleCamera.minimumZoom)
        #expect(ParticleCamera(zoom: -4).zoom == ParticleCamera.minimumZoom)
        #expect(ParticleCamera(zoom: 1000).zoom == ParticleCamera.maximumZoom)
        #expect(ParticleCamera(zoom: .nan).zoom == 1, "an unusable zoom means no zoom")

        var camera = ParticleCamera.identity
        for _ in 0 ..< 200 { camera.zoom(by: 1.2) }
        #expect(camera.zoom == ParticleCamera.maximumZoom)
        for _ in 0 ..< 400 { camera.zoom(by: 0.8) }
        #expect(camera.zoom == ParticleCamera.minimumZoom)
    }

    @Test("A pinch that reports nonsense leaves the zoom where it was")
    func nonsensePinchesAreIgnored() {
        var camera = ParticleCamera(zoom: 3)
        camera.zoom(by: .nan)
        camera.zoom(by: 0)
        camera.zoom(by: -2)
        camera.zoom(by: .infinity)
        #expect(camera.zoom == 3)
    }

    @Test("The plane never tips far enough to vanish")
    func pitchIsClamped() {
        // At ninety degrees the plane is edge-on: every body collapses onto one line and the field
        // disappears. Seventy-two reads as nearly edge-on and never reaches that.
        #expect(ParticleCamera(pitch: 90).pitch == ParticleCamera.maximumPitch)
        #expect(ParticleCamera(pitch: 1000).pitch == ParticleCamera.maximumPitch)
        #expect(ParticleCamera(pitch: -30).pitch == 0)
        #expect(ParticleCamera(pitch: .nan).pitch == 0)

        var camera = ParticleCamera.identity
        for _ in 0 ..< 100 { camera.rotate(byYaw: 0, pitch: 5) }
        #expect(camera.pitch == ParticleCamera.maximumPitch)
    }

    @Test("Turning wraps round instead of jamming")
    func yawWraps() {
        // Clamping here would give a camera that stops after half a revolution, which is not what a
        // turn is.
        #expect(ParticleCamera(yaw: 190).yaw == -170)
        #expect(ParticleCamera(yaw: -190).yaw == 170)
        #expect(ParticleCamera(yaw: 540).yaw == -180)

        var camera = ParticleCamera.identity
        for _ in 0 ..< 100 { camera.rotate(byYaw: 17, pitch: 0) }
        #expect(camera.yaw >= -180 && camera.yaw < 180)
    }

    @Test("Depth never makes a body vanish or fill the screen")
    func depthScaleIsClamped() {
        var camera = ParticleCamera(pitch: ParticleCamera.maximumPitch)
        camera.zoom = 1
        for y in stride(from: 0.0, through: 700.0, by: 25) {
            let scale = camera.drawScale(depthScale: project(camera, x: 200, y: y).depthScale)
            #expect(scale >= ParticleCamera.minimumDepthScale)
            #expect(scale <= ParticleCamera.maximumDepthScale)
        }
        #expect(camera.drawScale(depthScale: .nan) == camera.zoom)
    }

    // MARK: - What a tilt actually does

    @Test("Tipping the plane makes near bodies bigger and far ones smaller")
    func tiltChangesSizeWithDepth() {
        // This is the difference between a real perspective and a squash. A squash would leave every
        // body the same size.
        var camera = ParticleCamera.identity
        camera.pitch = 55

        let near = project(camera, x: 200, y: 700)
        let far = project(camera, x: 200, y: 0)
        let middle = project(camera, x: 200, y: 350)

        #expect(middle.depthScale > 0.999 && middle.depthScale < 1.001, "the centre is unchanged")
        #expect(near.depthScale != far.depthScale, "a squash would leave these equal")
        #expect(
            max(near.depthScale, far.depthScale) > 1,
            "one side of the plane must come toward the viewer"
        )
        #expect(min(near.depthScale, far.depthScale) < 1, "and the other must go away")
    }

    @Test("Tipping the plane squeezes it vertically")
    func tiltCompressesTheView() {
        var camera = ParticleCamera.identity
        let flatSpan = project(camera, x: 200, y: 0).y - project(camera, x: 200, y: 700).y
        camera.pitch = 60
        let tiltedSpan = project(camera, x: 200, y: 0).y - project(camera, x: 200, y: 700).y
        #expect(tiltedSpan < flatSpan, "a tipped plane covers less height")
    }

    @Test("The middle of the plane stays put however it is turned")
    func centreIsTheAnchor() {
        // The turn happens about the middle of the world. If it did not, adjusting the tilt slider
        // would also slide the whole scene across the screen.
        for yaw in stride(from: -170.0, through: 170.0, by: 40) {
            for pitch in stride(from: 0.0, through: 70.0, by: 10) {
                var camera = ParticleCamera.identity
                camera.yaw = yaw
                camera.pitch = pitch
                let middle = project(camera, x: 200, y: 350)
                #expect(abs(middle.x) < 1e-9, "yaw \(yaw), pitch \(pitch)")
                #expect(abs(middle.y) < 1e-9, "yaw \(yaw), pitch \(pitch)")
                #expect(
                    abs(middle.depthScale - 1) < 1e-9,
                    "the centre is neither nearer nor further, at any angle"
                )
            }
        }
    }

    @Test("Turning a quarter of the way round flattens the plane sideways")
    func yawCompressesHorizontally() {
        var camera = ParticleCamera.identity
        let flat = project(camera, x: 400, y: 350).x - project(camera, x: 0, y: 350).x
        camera.yaw = 60
        let turned = project(camera, x: 400, y: 350).x - project(camera, x: 0, y: 350).x
        #expect(abs(turned) < abs(flat), "a turned plane covers less width")
    }

    // MARK: - Zoom and pan

    @Test("Zooming in spreads the world out from the centre")
    func zoomScalesAboutTheCentre() {
        var camera = ParticleCamera.identity
        camera.zoom = 2
        #expect(abs(project(camera, x: 200, y: 350).x) < 1e-12, "the centre does not move")
        #expect(project(camera, x: 400, y: 350).x == 2, "the right edge goes off screen")
        #expect(project(camera, x: 300, y: 350).x == 1, "and what was halfway is now the edge")
    }

    @Test("Panning moves the picture the same way the finger went")
    func panFollowsTheFinger() {
        // Dragging right must move the picture right, and dragging down must move it down. Getting
        // the vertical the wrong way round is the classic mistake here, because the drawing
        // coordinates run upward while the screen runs downward.
        var camera = ParticleCamera.identity
        let before = project(camera, x: 200, y: 350)

        camera.pan(byX: 100, y: 0)
        let right = project(camera, x: 200, y: 350)
        #expect(right.x > before.x, "dragging right moved the picture left")

        camera = ParticleCamera.identity
        camera.pan(byX: 0, y: 100)
        let down = project(camera, x: 200, y: 350)
        #expect(down.y < before.y, "dragging down moved the picture up")
    }

    @Test("Panning by half the view moves the picture by half the screen")
    func panIsMeasuredInScreenPoints() {
        var camera = ParticleCamera.identity
        camera.pan(byX: 200, y: 0)
        // Two hundred points across a four-hundred-point view is half the width, and the drawing
        // coordinates are two units wide, so that is one unit.
        #expect(abs(project(camera, x: 200, y: 350).x - 1) < 1e-12)
    }

    @Test("A pan that reports nonsense is ignored")
    func nonsensePansAreIgnored() {
        var camera = ParticleCamera(panX: 30, panY: 40)
        camera.pan(byX: .nan, y: 5)
        camera.pan(byX: 5, y: .infinity)
        #expect(camera.panX == 30)
        #expect(camera.panY == 40)
    }

    // MARK: - Going back from the screen to the world

    @Test("A place on screen maps back to the place in the world, untilted")
    func unprojectIsExactWhenFlat() {
        for zoom in [0.25, 0.7, 1.0, 2.5, 12.0] {
            for pan in [(0.0, 0.0), (80.0, -140.0), (-33.0, 210.0)] {
                var camera = ParticleCamera(zoom: zoom, panX: pan.0, panY: pan.1)
                camera.zoom = zoom
                for point in [(0.0, 0.0), (400.0, 700.0), (200.0, 350.0), (91.0, 605.0)] {
                    let projected = project(camera, x: point.0, y: point.1)
                    let screenX = (projected.x + 1) * 0.5 * view.width
                    let screenY = (1 - projected.y) * 0.5 * view.height
                    let back = unproject(camera, x: screenX, y: screenY)
                    #expect(abs(back.x - point.0) < 1e-9, "zoom \(zoom), pan \(pan)")
                    #expect(abs(back.y - point.1) < 1e-9, "zoom \(zoom), pan \(pan)")
                }
            }
        }
    }

    @Test("A place on screen maps back closely enough to touch, tilted")
    func unprojectIsCloseWhenTilted() {
        // Not exact, and the file says why: undoing the turn needs a term the forward direction folds
        // away. What matters is that the error is far below what a fingertip resolves — a tenth of a
        // point on a four-hundred-point-wide view is a fortieth of a percent.
        var worstError = 0.0
        for yaw in stride(from: -150.0, through: 150.0, by: 50) {
            for pitch in stride(from: 0.0, through: 70.0, by: 10) {
                for zoom in [0.5, 1.0, 3.0] {
                    var camera = ParticleCamera(yaw: yaw, pitch: pitch)
                    camera.zoom = zoom
                    for point in [(50.0, 80.0), (200.0, 350.0), (370.0, 640.0), (120.0, 500.0)] {
                        let projected = project(camera, x: point.0, y: point.1)
                        let screenX = (projected.x + 1) * 0.5 * view.width
                        let screenY = (1 - projected.y) * 0.5 * view.height
                        let back = unproject(camera, x: screenX, y: screenY)
                        worstError = max(worstError, abs(back.x - point.0))
                        worstError = max(worstError, abs(back.y - point.1))
                    }
                }
            }
        }
        #expect(worstError < 0.1, "worst round-trip error was \(worstError) points")
    }

    @Test("A touch off the edge of the view still gives a position")
    func unprojectOutsideTheViewIsSafe() {
        // A drag can leave the view, and the answer has to be a number rather than a crash or a
        // not-a-number that then poisons a body's position.
        for camera in [
            ParticleCamera.identity,
            ParticleCamera(zoom: 6, panX: 300, panY: -200),
            ParticleCamera(yaw: 140, pitch: 70),
        ] {
            for point in [(-900.0, -900.0), (5000.0, 5000.0), (.nan, 10.0), (10.0, .infinity)] {
                let back = unproject(camera, x: point.0, y: point.1)
                #expect(back.x.isFinite, "\(point)")
                #expect(back.y.isFinite, "\(point)")
            }
        }
    }

    @Test("A view or world of no size does not divide by nothing")
    func degenerateSizesAreSafe() {
        let camera = ParticleCamera(zoom: 2, yaw: 30, pitch: 40)
        for size in [0.0, -5.0, Double.nan] {
            let projected = camera.project(
                x: 10, y: 10, worldWidth: size, worldHeight: size, viewWidth: size, viewHeight: size
            )
            #expect(projected.x.isFinite)
            #expect(projected.y.isFinite)
            #expect(projected.depthScale.isFinite)

            let back = camera.unproject(
                screenX: 10, screenY: 10,
                worldWidth: size, worldHeight: size, viewWidth: size, viewHeight: size
            )
            #expect(back.x.isFinite)
            #expect(back.y.isFinite)
        }
    }

    // MARK: - The automatic spin

    @Test("The spin turns at the rate it says and does not fight the slider")
    func autoOrbitLeavesTheSliderAlone() {
        // The reference implementation wrote the spin into the same field the slider used, so turning
        // the spin on made the slider jump and then dragging it did nothing, because the next frame
        // overwrote it. Held apart, both work.
        var camera = ParticleCamera.identity
        camera.yaw = 45
        camera.autoOrbit = true

        for _ in 0 ..< 60 { camera.advance(bySeconds: 1.0 / 60) }
        #expect(camera.yaw == 45, "the spin must not touch what the slider set")
        #expect(
            abs(camera.autoOrbitAngle - ParticleCamera.autoOrbitDegreesPerSecond) < 1e-9,
            "one second of spin is one second's worth of degrees"
        )
        #expect(abs(camera.effectiveYaw - (45 + 18)) < 1e-9, "and the two add up")
    }

    @Test("The spin does nothing when it is switched off")
    func autoOrbitRespectsItsSwitch() {
        var camera = ParticleCamera.identity
        camera.autoOrbit = false
        for _ in 0 ..< 100 { camera.advance(bySeconds: 1.0 / 60) }
        #expect(camera.autoOrbitAngle == 0)
    }

    @Test("A long gap between frames does not jump the view round")
    func autoOrbitClampsLongFrames() {
        // Coming back from the background can report a gap of seconds. Turning the view a third of a
        // revolution in one frame reads as a glitch, not as a spin.
        var camera = ParticleCamera.identity
        camera.autoOrbit = true
        camera.advance(bySeconds: 9)
        #expect(
            abs(camera.autoOrbitAngle - 0.1 * ParticleCamera.autoOrbitDegreesPerSecond) < 1e-9,
            "a nine-second gap must count as a tenth of a second"
        )
    }

    @Test("A frame of no time, or of nonsense, advances nothing")
    func autoOrbitIgnoresBadFrames() {
        var camera = ParticleCamera.identity
        camera.autoOrbit = true
        camera.advance(bySeconds: 0)
        camera.advance(bySeconds: -1)
        camera.advance(bySeconds: .nan)
        #expect(camera.autoOrbitAngle == 0)
    }

    @Test("The spin keeps turning past a full revolution")
    func autoOrbitWrapsCleanly() {
        var camera = ParticleCamera.identity
        camera.autoOrbit = true
        for _ in 0 ..< 3600 { camera.advance(bySeconds: 1.0 / 60) }
        #expect(camera.autoOrbitAngle >= -180 && camera.autoOrbitAngle < 180)
    }

    @Test("Resetting clears the spin's progress but not the spin itself")
    func resetClearsTheAccumulatedAngle() {
        // Otherwise "reset the view" leaves the field at whatever angle the spin had reached, which
        // is not a reset.
        var camera = ParticleCamera(zoom: 5, panX: 90, panY: -30, yaw: 100, pitch: 50)
        camera.autoOrbit = true
        camera.advance(bySeconds: 2)
        camera.reset()
        #expect(camera.isIdentity)
        #expect(camera.autoOrbitAngle == 0)
        #expect(camera.autoOrbit, "the spin stays switched on")
    }

    // MARK: - Framing what is there

    private func framing(_ points: [(Double, Double)], trim: Double = ParticleCamera.framingTrimFraction)
        -> ParticleFraming
    {
        var flat: [Float] = []
        for point in points {
            flat.append(Float(point.0))
            flat.append(Float(point.1))
        }
        return flat.withUnsafeBufferPointer { buffer in
            ParticleCamera.framing(
                positions: buffer.baseAddress!,
                count: points.count,
                worldWidth: world.width,
                worldHeight: world.height,
                trim: trim
            )
        }
    }

    @Test("Nothing in the field frames to nothing")
    func emptyFieldFramesEmpty() {
        #expect(framing([]).isEmpty)
        #expect(framing([]).bodyCount == 0)
    }

    @Test("A cluster frames around itself, not around the world")
    func framingFindsTheCluster() {
        var points: [(Double, Double)] = []
        for index in 0 ..< 400 {
            let angle = Double(index) * 0.1
            points.append((100 + jsCos(angle) * 20, 200 + jsSin(angle) * 20))
        }
        let frame = framing(points)
        #expect(frame.bodyCount == 400)
        #expect(frame.minX > 70 && frame.minX < 85, "found \(frame.minX)")
        #expect(frame.maxX > 115 && frame.maxX < 130, "found \(frame.maxX)")
        #expect(abs(frame.centreX - 100) < 4)
        #expect(abs(frame.centreY - 200) < 4)
    }

    @Test("One body flung far away does not frame the whole scene around itself")
    func framingRejectsOutliers() {
        // This is the reason the fitting is a histogram and not a bounding box. A supernova throws a
        // handful of bodies to the edges; framing around them would make everything else a dot.
        var points: [(Double, Double)] = []
        for index in 0 ..< 1000 {
            let angle = Double(index) * 0.05
            points.append((200 + jsCos(angle) * 10, 350 + jsSin(angle) * 10))
        }
        points.append((2, 4))
        points.append((398, 696))

        let frame = framing(points)
        #expect(frame.width < 60, "the frame stretched to \(frame.width) to include two strays")
        #expect(frame.height < 60, "the frame stretched to \(frame.height)")
        #expect(abs(frame.centreX - 200) < 10)
    }

    @Test("With no trimming the frame does reach the strays")
    func framingWithoutTrimmingIncludesEverything() {
        // The counterpart to the test above: the rejection is a choice, and asking for none gives the
        // plain bounding box.
        var points: [(Double, Double)] = []
        for index in 0 ..< 100 { points.append((200, 350 + Double(index) * 0.01)) }
        points.append((5, 5))
        points.append((395, 695))

        let frame = framing(points, trim: 0)
        #expect(frame.minX < 10)
        #expect(frame.maxX > 390)
    }

    @Test("Bodies with unusable positions are left out of the count")
    func framingSkipsCorruptBodies() {
        // Counting a corrupt body at zero would drag the frame to the corner of the world, and the
        // picture would appear to be nowhere.
        var points: [(Double, Double)] = []
        for _ in 0 ..< 50 { points.append((300, 500)) }
        points.append((.nan, .nan))
        points.append((.infinity, 3))

        let frame = framing(points)
        #expect(frame.bodyCount == 50)
        #expect(frame.minX > 250, "the frame was dragged to \(frame.minX)")
    }

    @Test("Every body in one place frames to one small box, not to nothing")
    func framingASinglePointIsNotEmpty() {
        // Trimming from both ends of a small crowd can cross the two over. A zero-width frame would
        // then ask the fit to divide by nothing.
        let frame = framing(Array(repeating: (200.0, 350.0), count: 30))
        #expect(!frame.isEmpty)
        #expect(frame.width > 0)
        #expect(frame.height > 0)
    }

    // MARK: - Fitting the view to what is there

    @Test("Fitting puts the content in the middle of the screen")
    func fitCentresTheContent() {
        let frame = ParticleFraming(minX: 40, minY: 80, maxX: 120, maxY: 160, bodyCount: 500)
        var camera = ParticleCamera.identity
        camera.fit(
            to: frame,
            worldWidth: world.width,
            worldHeight: world.height,
            viewWidth: view.width,
            viewHeight: view.height
        )

        let middle = project(camera, x: frame.centreX, y: frame.centreY)
        #expect(abs(middle.x) < 1e-9, "the content's middle landed at \(middle.x)")
        #expect(abs(middle.y) < 1e-9, "the content's middle landed at \(middle.y)")
    }

    @Test("Fitting brings the whole content on screen, with a margin")
    func fitBringsEverythingIntoView() {
        for frame in [
            ParticleFraming(minX: 40, minY: 80, maxX: 120, maxY: 160, bodyCount: 500),
            ParticleFraming(minX: 0, minY: 0, maxX: 400, maxY: 700, bodyCount: 500),
            ParticleFraming(minX: 190, minY: 340, maxX: 210, maxY: 360, bodyCount: 500),
            ParticleFraming(minX: 10, minY: 300, maxX: 390, maxY: 340, bodyCount: 500),
        ] {
            var camera = ParticleCamera.identity
            camera.fit(
                to: frame,
                worldWidth: world.width,
                worldHeight: world.height,
                viewWidth: view.width,
                viewHeight: view.height
            )

            for corner in [
                (frame.minX, frame.minY), (frame.maxX, frame.minY),
                (frame.minX, frame.maxY), (frame.maxX, frame.maxY),
            ] {
                let projected = project(camera, x: corner.0, y: corner.1)
                #expect(abs(projected.x) <= 1.0001, "corner \(corner) at x \(projected.x)")
                #expect(abs(projected.y) <= 1.0001, "corner \(corner) at y \(projected.y)")
            }
        }
    }

    @Test("Fitting a small cluster actually zooms in")
    func fitZoomsInOnSmallContent() {
        let frame = ParticleFraming(minX: 190, minY: 340, maxX: 210, maxY: 360, bodyCount: 500)
        var camera = ParticleCamera.identity
        camera.fit(
            to: frame,
            worldWidth: world.width,
            worldHeight: world.height,
            viewWidth: view.width,
            viewHeight: view.height
        )
        #expect(camera.zoom > 4, "a twenty-point cluster in a seven-hundred-point world should fill it")
    }

    @Test("Fitting keeps a tilt rather than quietly undoing it")
    func fitPreservesTheAngles() {
        // Resetting the angles would be easier and would mean "fit" destroyed a view somebody had set
        // up. The fit is computed through the tilt instead.
        let frame = ParticleFraming(minX: 60, minY: 100, maxX: 180, maxY: 300, bodyCount: 500)
        var camera = ParticleCamera(yaw: 35, pitch: 45)
        camera.fit(
            to: frame,
            worldWidth: world.width,
            worldHeight: world.height,
            viewWidth: view.width,
            viewHeight: view.height
        )
        #expect(camera.yaw == 35)
        #expect(camera.pitch == 45)

        for corner in [
            (frame.minX, frame.minY), (frame.maxX, frame.minY),
            (frame.minX, frame.maxY), (frame.maxX, frame.maxY),
        ] {
            let projected = project(camera, x: corner.0, y: corner.1)
            #expect(abs(projected.x) <= 1.0001, "tilted corner \(corner) at x \(projected.x)")
            #expect(abs(projected.y) <= 1.0001, "tilted corner \(corner) at y \(projected.y)")
        }
    }

    @Test("Fitting nothing leaves the view alone")
    func fitOnAnEmptyFieldDoesNothing() {
        let before = ParticleCamera(zoom: 3, panX: 50, panY: 60, yaw: 20, pitch: 30)
        var camera = before
        camera.fit(
            to: ParticleFraming(minX: 0, minY: 0, maxX: 0, maxY: 0, bodyCount: 0),
            worldWidth: world.width,
            worldHeight: world.height,
            viewWidth: view.width,
            viewHeight: view.height
        )
        #expect(camera == before)
    }

    @Test("Fitting never produces a zoom outside the limits")
    func fitRespectsTheZoomLimits() {
        // A single body frames to one bin, which is a very small box. Without the clamp the fit would
        // ask for a zoom of hundreds and the field would be one enormous blur.
        var camera = ParticleCamera.identity
        camera.fit(
            to: ParticleFraming(minX: 200, minY: 350, maxX: 200.01, maxY: 350.01, bodyCount: 1),
            worldWidth: world.width,
            worldHeight: world.height,
            viewWidth: view.width,
            viewHeight: view.height
        )
        #expect(camera.zoom <= ParticleCamera.maximumZoom)
        #expect(camera.zoom >= ParticleCamera.minimumZoom)
        #expect(camera.panX.isFinite)
        #expect(camera.panY.isFinite)
    }

    // MARK: - Saving

    @Test("A camera survives being written down and read back")
    func cameraRoundTrips() throws {
        let camera = ParticleCamera(
            zoom: 3.5, panX: -80, panY: 120, yaw: 95, pitch: 44, autoOrbit: true, autoOrbitAngle: 70
        )
        let bytes = try JSONEncoder().encode(camera)
        #expect(try JSONDecoder().decode(ParticleCamera.self, from: bytes) == camera)
    }
}
