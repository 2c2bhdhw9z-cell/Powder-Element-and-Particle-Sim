import CrucibleCore
import SwiftUI
import MetalKit

/// The particle field, as something SwiftUI can place in a layout.
///
/// The counterpart to `SimulationSurface`. The touch handling differs in kind: painting into the
/// powder grid places material at a point, while touching the particle field applies a force for
/// as long as the finger is down — so this reports when the touch ends, which the powder surface
/// has no need to.
/// The field, with any names hanging in it drawn on top.
///
/// Two views rather than one: the field itself is drawn by the graphics card as geometry, and text is the one thing
/// that does not belong there — a handful of words laid over the top costs nothing and can use the app's own
/// typefaces, where drawing them into the field would mean turning letters into particles.
struct FieldWithLabels: View {
    let model: ParticleFieldModel

    var body: some View {
        FieldSurface(model: model)
            .overlay(alignment: .topLeading) {
                if model.showsLabels {
                    ZStack(alignment: .topLeading) {
                        ForEach(model.placedLabels) { label in
                            Text(label.text)
                                .font(.labBody(11, .semiBold))
                                .foregroundStyle(Palette.foreground.opacity(label.opacity))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Palette.background.opacity(Palette.overWorld(0.55) * label.opacity))
                                )
                                // Centred on the place it names rather than starting there, so the words straddle
                                // it the way a caption should.
                                .fixedSize()
                                .offset(x: label.x, y: label.y)
                                .alignmentGuide(.leading) { $0.width * 0.5 }
                                .alignmentGuide(.top) { $0.height }
                        }
                    }
                    // Names are a statement about the field, not part of it: they must never swallow a touch.
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // How many rabbits and foxes there have been, while they are what the field is showing. In the
                // corner nothing else uses, and never in the way of a finger.
                if model.isHerd, model.herdHistory.count > 1 {
                    HerdGraph(history: model.herdHistory)
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if let read = model.lensReading {
                    LensReadout(reading: read)
                        .padding(10)
                        // Above or below the finger, whichever leaves it visible: a panel under your own thumb is
                        // a panel you cannot read.
                        .frame(maxWidth: .infinity, alignment: model.lensAtX > 0.5 ? .leading : .trailing)
                        .frame(maxHeight: .infinity, alignment: model.lensAtY > 0.5 ? .top : .bottom)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Rabbits and foxes over the last minute and a half: two lines chasing each other round.
///
/// Each drawn against its own top rather than one shared scale, because there are always many more rabbits than
/// foxes — on one scale the foxes are a flat line along the bottom, and the whole point is to see their rise come
/// after the rabbits'.
struct HerdGraph: View {
    let history: [ParticleHerdCount]

    private static let rabbitColour = Color(red: 0.93, green: 0.86, blue: 0.72)
    private static let foxColour = Color(red: 0.98, green: 0.45, blue: 0.18)

    var body: some View {
        let now = history.last ?? ParticleHerdCount(rabbits: 0, foxes: 0)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                key("Rabbits", now.rabbits, Self.rabbitColour)
                key("Foxes", now.foxes, Self.foxColour)
            }
            // Copied out first: the drawing runs away from the main thread, where this view's own properties cannot
            // be read.
            let readings = history
            let rabbitColour = Self.rabbitColour
            let foxColour = Self.foxColour
            Canvas { context, size in
                let rabbitsTop = Double(max(1, readings.map(\.rabbits).max() ?? 1))
                let foxesTop = Double(max(1, readings.map(\.foxes).max() ?? 1))
                func line(_ value: (ParticleHerdCount) -> Int, top: Double) -> Path {
                    var path = Path()
                    for (index, reading) in readings.enumerated() {
                        let x = size.width * Double(index) / Double(max(1, readings.count - 1))
                        let y = size.height * (1 - Double(value(reading)) / top)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    return path
                }
                context.stroke(line({ $0.rabbits }, top: rabbitsTop), with: .color(rabbitColour), lineWidth: 1.5)
                context.stroke(line({ $0.foxes }, top: foxesTop), with: .color(foxColour), lineWidth: 1.5)
            }
            .frame(width: 150, height: 56)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.background.opacity(Palette.overWorld(0.82)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(now.rabbits) rabbits and \(now.foxes) foxes")
    }

    private func key(_ name: String, _ count: Int, _ colour: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text("\(name) \(count)")
                .font(.labNumeric(10))
                .foregroundStyle(Palette.muted)
        }
    }
}

/// What the lens found, in words.
///
/// Deliberately plain: the name of each force and how hard it is pushing, biggest first, so the answer to "why did
/// that just move" is the first line rather than something to be worked out.
struct LensReadout: View {
    let reading: ParticleReading

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(reading.isCrowd ? "One of the crowd" : "A body of its own")
                .font(.labBody(11, .semiBold))
                .foregroundStyle(Palette.foreground)
            row("Speed", value: reading.speed, unit: " a moment")
            row("Weight", value: reading.mass, unit: "")
            Text("\(reading.neighbours) close by")
                .font(.labNumeric(10))
                .foregroundStyle(Palette.subtleForeground)
            if !reading.pushes.isEmpty {
                Divider().overlay(Palette.border).padding(.vertical, 2)
                ForEach(Array(reading.pushes.prefix(5).enumerated()), id: \.offset) { _, push in
                    HStack(spacing: 6) {
                        Text(push.name)
                            .font(.labBody(10))
                            .foregroundStyle(Palette.muted)
                        Spacer(minLength: 8)
                        Text(push.size.formatted(.number.precision(.significantDigits(2))))
                            .font(.labNumeric(10))
                            .foregroundStyle(Palette.subtleForeground)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: 190, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.background.opacity(Palette.overWorld(0.9)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
    }

    private func row(_ name: String, value: Double, unit: String) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.labBody(10))
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 8)
            Text(value.formatted(.number.precision(.fractionLength(2))) + unit)
                .font(.labNumeric(10))
                .foregroundStyle(Palette.subtleForeground)
        }
    }
}

struct FieldSurface: UIViewRepresentable {
    let model: ParticleFieldModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> MTKView {
        guard let view = FieldView(model: model) else {
            let placeholder = MTKView()
            placeholder.isPaused = true
            placeholder.enableSetNeedsDisplay = true
            return placeholder
        }
        context.coordinator.attachGestures(to: view)
        // Handed to the model so that anything wanting a picture of the field can ask for one
        // without having to reach through the view hierarchy to find this. The field is drawn as
        // geometry on the GPU, so the view is the only thing that can produce one.
        //
        // Captured weakly: the model outlives the view, and a strong reference here would keep a
        // discarded Metal view and its buffers alive for as long as the app runs.
        // Written out rather than as `view?.snapshot()`: optional chaining on a method that already
        // returns an optional gives an optional of an optional, which is not what the model wants.
        model.snapshotProvider = { [weak view] in
            guard let view else { return nil }
            return view.snapshot()
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        private let model: ParticleFieldModel

        init(model: ParticleFieldModel) {
            self.model = model
            super.init()
        }

        /// One finger works the field; two fingers move the camera.
        ///
        /// That division is the whole scheme, and it is the only one that works here. A tool has to
        /// be usable with one finger — the force ones are held down, not tapped — so a single finger
        /// cannot also mean "pan". And a camera gesture has to be available without first putting a
        /// tool away, or looking closely at something becomes a three-step chore.
        ///
        /// Worth noting what the reference implementation does here, because it is why this had to be
        /// designed rather than ported: it pans with a middle-click, a right-click or a held Alt key,
        /// and its turn and tilt are reachable only from sliders. None of those exist on a phone. Its
        /// pinch-to-zoom is the one gesture that carried over.
        func attachGestures(to view: UIView) {
            // A long-press recogniser with no delay, rather than a pan. A pan does not begin
            // until the finger has moved, and holding still in one place is a perfectly good
            // thing to do with a force tool — with a pan, nothing would happen until you
            // twitched.
            let press = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handlePress(_:))
            )
            press.minimumPressDuration = 0
            press.allowableMovement = .greatestFiniteMagnitude
            press.delegate = self
            view.addGestureRecognizer(press)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            // Exactly two. One belongs to the tool, and three or more is nothing in this app — and
            // leaving the maximum open would let a stray third finger during a pinch be read as a
            // pan and jerk the view sideways.
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let rotate = UIRotationGestureRecognizer(
                target: self,
                action: #selector(handleRotate(_:))
            )
            rotate.delegate = self
            view.addGestureRecognizer(rotate)

            // Every finger, for when the field is set to take more than one. It runs all the time and does nothing
            // unless that is switched on — asking it to be added and removed as the setting changes would mean
            // reaching back into the view from the model, and this costs a list of touch positions per frame.
            //
            // The view is told to accept several touches at all: without this the system hands over only the first,
            // and every extra finger would simply not exist.
            view.isMultipleTouchEnabled = true
            let many = ManyFingersRecognizer(target: nil, action: nil)
            many.delegate = self
            many.onChange = { [weak self] points in
                self?.handleManyFingers(points, in: view)
            }
            view.addGestureRecognizer(many)
        }

        /// Every finger on the glass, while the field is set to take more than one.
        ///
        /// The first finger down keeps working the tool through the ordinary path, so nothing about one-finger use
        /// changes. The rest are handed over as extra places for the same tool.
        private func handleManyFingers(_ points: [CGPoint], in view: UIView) {
            guard model.manyFingers else {
                model.clearExtraTouches()
                return
            }
            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0, points.count > 1 else {
                model.clearExtraTouches()
                return
            }
            model.setExtraTouches(
                points.dropFirst().map {
                    (fx: Double($0.x / bounds.width), fy: Double($0.y / bounds.height))
                }
            )
        }

        @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view else { return }
            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            // A second finger means the camera, not the field. The tool is let go the moment one
            // arrives, because otherwise pinching to zoom would also drag whatever was under the
            // first finger halfway across the world.
            //
            // Unless the field has been set to take many fingers, in which case a second finger is another tool
            // rather than a camera move, and letting go would be exactly wrong.
            if gesture.numberOfTouches > 1, !model.manyFingers {
                model.endTouch()
                return
            }

            let point = gesture.location(in: view)
            let fx = Double(point.x / bounds.width)
            let fy = Double(point.y / bounds.height)

            switch gesture.state {
            case .began:
                Haptics.touchDown()
                model.beginTouch(atFractionX: fx, fractionY: fy)
            case .changed:
                model.updateTouch(atFractionX: fx, fractionY: fy)
            default:
                // Ended, cancelled or failed all mean the finger is gone. Treated the same,
                // because a force left switched on by a cancelled gesture would go on pulling
                // the field around with nothing touching the screen.
                model.endTouch()
            }
        }

        /// How many of the three camera gestures are running.
        ///
        /// Counted rather than a single flag, because all three are deliberately allowed to run at once —
        /// see the delegate below. One finishing while another continues must not be read as the whole
        /// motion being over.
        private var cameraGesturesRunning = 0

        /// Tells the model when a camera motion starts and when the last of it finishes.
        ///
        /// What this buys: while a finger is moving the view, the dock's readouts hold still instead of
        /// several hundred controls being reassembled on every touch sample. They catch up once, at the
        /// end. UIKit guarantees a recogniser that begins also ends, cancels or fails, so the count
        /// cannot be left stranded.
        private func track(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
            case .began:
                cameraGesturesRunning += 1
                model.beginCameraGesture()
            case .ended, .cancelled, .failed:
                cameraGesturesRunning = max(0, cameraGesturesRunning - 1)
                if cameraGesturesRunning == 0 { model.endCameraGesture() }
            default:
                break
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            // The camera stands down while every finger is a tool; there is no spare finger to move the view with.
            guard !model.manyFingers else { return }
            track(gesture)
            // The scale is reported cumulatively from the start of the gesture, so it is reset to one
            // after each reading and what gets applied is the change since the last. Applying the
            // cumulative value directly would fight the clamp: once the zoom hit its limit, pinching
            // back would do nothing until the fingers had returned all the way to where they started.
            guard gesture.state == .changed || gesture.state == .began else { return }
            model.zoomCamera(by: Double(gesture.scale))
            gesture.scale = 1
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            // The camera stands down while every finger is a tool; there is no spare finger to move the view with.
            guard !model.manyFingers else { return }
            track(gesture)
            guard let view = gesture.view else { return }
            guard gesture.state == .changed || gesture.state == .began else { return }
            let movement = gesture.translation(in: view)
            model.panCamera(byPointsX: Double(movement.x), y: Double(movement.y))
            gesture.setTranslation(.zero, in: view)
        }

        @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
            // The camera stands down while every finger is a tool; there is no spare finger to move the view with.
            guard !model.manyFingers else { return }
            track(gesture)
            guard gesture.state == .changed || gesture.state == .began else { return }
            model.rotateCamera(byRadians: Double(gesture.rotation))
            gesture.rotation = 0
        }
    }
}

extension FieldSurface.Coordinator: UIGestureRecognizerDelegate {
    /// All four run together.
    ///
    /// Pinch, two-finger drag and twist are one continuous motion of the same two fingers, and a
    /// system that made you choose between them would feel broken — letting go to change from
    /// zooming to turning is not how a phone behaves. The press recogniser also has to keep running
    /// alongside them, because it is the thing that notices the second finger arriving and puts the
    /// tool down.
    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
