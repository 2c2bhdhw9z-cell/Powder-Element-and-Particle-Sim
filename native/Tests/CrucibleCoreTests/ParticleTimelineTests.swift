import Foundation
import Testing

@testable import CrucibleCore

/// Recording how the field should change over time.
struct ParticleTimelineTests {
    private func timeline(_ frames: [(Double, ParticleKeyframe.Curve, [ParticleTimeline.Setting: Double])])
        -> ParticleTimeline
    {
        ParticleTimeline(
            keyframes: frames.map { ParticleKeyframe(at: $0.0, curve: $0.1, values: $0.2) }
        )
    }

    // MARK: - Curves

    @Test("Every curve leaves nought at nought and one at one")
    func curvesPreserveTheirEnds() {
        // The property that keeps a keyframe's own value exact whichever curve leads to it. A curve without
        // it would mean the field never quite reached the value somebody set.
        for curve in ParticleKeyframe.Curve.allCases {
            #expect(curve.shape(0) == 0, "\(curve.rawValue) does not start at nought")
            #expect(curve.shape(1) == 1, "\(curve.rawValue) does not end at one")
        }
    }

    @Test("Every curve stays between its ends, and never goes backwards")
    func curvesAreWellBehaved() {
        for curve in ParticleKeyframe.Curve.allCases {
            var previous = 0.0
            for step in 0 ... 100 {
                let shaped = curve.shape(Double(step) / 100)
                #expect(shaped >= 0 && shaped <= 1, "\(curve.rawValue) reached \(shaped)")
                #expect(shaped >= previous - 1e-12, "\(curve.rawValue) went backwards")
                previous = shaped
            }
        }
    }

    @Test("Each curve has its own shape")
    func curvesAreDistinct() {
        var seen: [String: String] = [:]
        for curve in ParticleKeyframe.Curve.allCases {
            let signature = (0 ... 10)
                .map { "\(Int(curve.shape(Double($0) / 10) * 1000))" }
                .joined(separator: ",")
            if let twin = seen[signature] {
                Issue.record("\(curve.rawValue) is the same shape as \(twin)")
            }
            seen[signature] = curve.rawValue
        }
    }

    @Test("Smooth is slow at both ends and easing is slow at one")
    func curvesHaveTheRightShapes() {
        // The whole reason for having them. A straight blend reads as machinery; something slow to leave and
        // slow to arrive reads as deliberate.
        let straight = ParticleKeyframe.Curve.straight
        let smooth = ParticleKeyframe.Curve.smooth
        #expect(smooth.shape(0.1) < straight.shape(0.1), "smooth should leave slowly")
        #expect(smooth.shape(0.9) > straight.shape(0.9), "and arrive slowly")
        #expect(abs(smooth.shape(0.5) - 0.5) < 1e-12, "and be halfway at halfway")

        #expect(ParticleKeyframe.Curve.easeIn.shape(0.5) < 0.5, "easing in starts slowly")
        #expect(ParticleKeyframe.Curve.easeOut.shape(0.5) > 0.5, "easing out ends slowly")
    }

    @Test("A jump does not blend at all")
    func holdDoesNotBlend() {
        let hold = ParticleKeyframe.Curve.hold
        #expect(hold.shape(0.01) == 0)
        #expect(hold.shape(0.99) == 0, "everything before the keyframe keeps the old value")
        #expect(hold.shape(1) == 1)
    }

    @Test("A fraction that is not a number does not break a curve")
    func curvesSurviveUnusableInput() {
        for curve in ParticleKeyframe.Curve.allCases {
            // Anything that is not a usable number counts as no progress at all, which holds the previous
            // value. That is the safe direction: the alternative — treating it as fully arrived — makes a
            // single bad number jump the whole field to the next keyframe.
            #expect(curve.shape(.nan) == 0)
            #expect(curve.shape(.infinity) == 0)
            #expect(curve.shape(-.infinity) == 0)
            // A usable number outside the range is simply pulled into it.
            #expect(curve.shape(-5) == 0)
            #expect(curve.shape(9) == 1)
        }
    }

    // MARK: - Keeping a timeline in order

    @Test("Keyframes come back in order of time")
    func keyframesAreSorted() {
        let out = timeline([
            (4, .smooth, [.gravityY: 1]),
            (1, .smooth, [.gravityY: 0]),
            (9, .smooth, [.gravityY: 0.5]),
        ])
        #expect(out.keyframes.map(\.at) == [1, 4, 9])
        #expect(out.duration == 9)
    }

    @Test("Keyframes at the same moment keep the order they were given in")
    func sortingIsStable() {
        // Swift's own sort makes no promise about ties, and a timeline that reordered itself between
        // launches would be baffling.
        let out = ParticleTimeline(keyframes: (0 ..< 8).map {
            ParticleKeyframe(at: 2, curve: .smooth, values: [.glow: Double($0) * 0.1])
        })
        #expect(out.keyframes.map { $0.values[.glow] ?? -1 } == [0, 0.1, 0.2, 0.30000000000000004, 0.4, 0.5, 0.6000000000000001, 0.7000000000000001])
    }

    @Test("What cannot be used is dropped, and what is out of range is pulled in")
    func keyframesAreTidied() {
        let out = ParticleTimeline(keyframes: [
            ParticleKeyframe(at: .nan, curve: .smooth, values: [.glow: 1]),
            ParticleKeyframe(at: 1, curve: .smooth, values: [:]),
            ParticleKeyframe(at: -4, curve: .smooth, values: [.glow: 99]),
            ParticleKeyframe(at: 3, curve: .smooth, values: [.gravityY: .nan, .glow: 2]),
        ])
        #expect(out.keyframes.count == 2, "an unusable time and an empty keyframe should both go")
        #expect(out.keyframes[0].at == 0, "a negative time is pulled to the start")
        #expect(out.keyframes[0].values[.glow] == 4, "a glow of ninety-nine is pulled to its limit")
        #expect(out.keyframes[1].values[.gravityY] == nil, "an unusable value is dropped, not stored")
    }

    @Test("Recording over the playhead replaces what is there")
    func recordingReplaces() {
        // Rather than leaving two keyframes a millionth of a second apart, which would blend between them in
        // no time at all and read as a jump.
        var out = timeline([(2, .smooth, [.glow: 1])])
        out.record(ParticleKeyframe(at: 2.00001, curve: .straight, values: [.glow: 3]))
        #expect(out.keyframes.count == 1)
        #expect(out.keyframes[0].values[.glow] == 3)

        out.record(ParticleKeyframe(at: 5, curve: .smooth, values: [.glow: 0]))
        #expect(out.keyframes.count == 2)
    }

    @Test("Keyframes can be removed, and removing one that is not there does nothing")
    func removingWorks() {
        var out = timeline([(1, .smooth, [.glow: 1]), (2, .smooth, [.glow: 2])])
        out.remove(at: 0)
        #expect(out.keyframes.count == 1)
        #expect(out.keyframes[0].at == 2)
        out.remove(at: 9)
        out.remove(at: -1)
        #expect(out.keyframes.count == 1)
        out.clear()
        #expect(out.isEmpty)
        #expect(out.duration == 0)
    }

    // MARK: - Working out the values in between

    @Test("A value holds before the first keyframe and after the last")
    func endsHold() {
        // Not carried on past the end, which would run a setting off into its limit and read as a fault
        // rather than as a choice.
        let out = timeline([(2, .straight, [.glow: 1]), (6, .straight, [.glow: 3])])
        #expect(out.value(of: .glow, at: 0) == 1)
        #expect(out.value(of: .glow, at: 2) == 1)
        #expect(out.value(of: .glow, at: 6) == 3)
        #expect(out.value(of: .glow, at: 99) == 3)
    }

    @Test("A value blends between the keyframes that mention it")
    func valuesBlend() {
        let out = timeline([(0, .straight, [.glow: 0]), (4, .straight, [.glow: 4])])
        #expect(out.value(of: .glow, at: 1) == 1)
        #expect(out.value(of: .glow, at: 2) == 2)
        #expect(out.value(of: .glow, at: 3) == 3)
    }

    @Test("A setting only some keyframes mention skips the ones that do not")
    func settingsAreIndependent() {
        // This is what makes it possible to animate the gravity over eight seconds and flash the glow twice
        // in the middle, without the two having to share keyframes.
        let out = timeline([
            (0, .straight, [.gravityY: 0, .glow: 0]),
            (2, .straight, [.glow: 4]),
            (4, .straight, [.glow: 0]),
            (8, .straight, [.gravityY: 1]),
        ])
        // The gravity ignores the two glow-only keyframes and runs straight across the whole eight seconds.
        #expect(abs((out.value(of: .gravityY, at: 4) ?? 0) - 0.5) < 1e-12)
        // And the glow does its own thing in the middle.
        #expect(out.value(of: .glow, at: 2) == 4)
        #expect(out.value(of: .glow, at: 4) == 0)
    }

    @Test("The curve of the keyframe being approached is the one used")
    func theArrivingCurveWins() throws {
        // Taking it from the keyframe being left would mean a keyframe's curve affected what came before it
        // rather than what came after, which is not how anybody reads a timeline.
        let straightArrival = timeline([
            (0, .smooth, [.glow: 0]),
            (4, .straight, [.glow: 4]),
        ])
        #expect(straightArrival.value(of: .glow, at: 1) == 1, "a straight arrival blends straight")

        let easedArrival = timeline([
            (0, .straight, [.glow: 0]),
            (4, .easeIn, [.glow: 4]),
        ])
        let quarter = try #require(easedArrival.value(of: .glow, at: 1))
        #expect(quarter < 1, "an eased arrival should be behind a straight one early on")
    }

    @Test("Two keyframes at the same moment do not divide by nothing")
    func coincidentKeyframesAreSafe() {
        let out = ParticleTimeline(keyframes: [
            ParticleKeyframe(at: 0, curve: .straight, values: [.glow: 0]),
            ParticleKeyframe(at: 2, curve: .straight, values: [.glow: 2]),
            ParticleKeyframe(at: 2, curve: .straight, values: [.glow: 4]),
        ])
        for moment in [0.0, 1.0, 2.0, 3.0] {
            let value = out.value(of: .glow, at: moment)
            #expect((value ?? .nan).isFinite, "at \(moment) the value was \(value ?? .nan)")
        }
    }

    @Test("Asking about a setting no keyframe mentions gives nothing, not a guess")
    func unmentionedSettingsAreAbsent() {
        let out = timeline([(0, .smooth, [.glow: 1])])
        #expect(out.value(of: .gravityY, at: 0) == nil)
        #expect(out.values(at: 0)[.gravityY] == nil)
        #expect(out.values(at: 0)[.glow] == 1)
    }

    @Test("An empty timeline says nothing about anything")
    func emptyTimelineIsSilent() {
        let out = ParticleTimeline()
        #expect(out.values(at: 0).isEmpty)
        #expect(out.value(of: .glow, at: 5) == nil)
        #expect(out.duration == 0)
    }

    @Test("A moment that is not a number is treated as the start")
    func unusableMomentsAreSafe() {
        let out = timeline([(0, .straight, [.glow: 0]), (4, .straight, [.glow: 4])])
        #expect(out.value(of: .glow, at: .nan) == 0)
        #expect(out.value(of: .glow, at: -9) == 0)
    }

    // MARK: - Playing it

    @Test("A stopped playhead does not move")
    func stoppedMeansStopped() {
        let out = timeline([(0, .smooth, [.glow: 0]), (4, .smooth, [.glow: 4])])
        let head = ParticlePlayhead(isPlaying: false, at: 1)
        #expect(head.advanced(by: 2, through: out) == head)
    }

    @Test("A playing playhead moves forward")
    func playingMovesForward() {
        let out = timeline([(0, .smooth, [.glow: 0]), (4, .smooth, [.glow: 4])])
        let head = ParticlePlayhead(isPlaying: true, at: 1).advanced(by: 0.5, through: out)
        #expect(head.at == 1.5)
        #expect(head.isPlaying)
    }

    @Test("A looping timeline keeps its overshoot rather than throwing it away")
    func loopingKeepsTheOvershoot() {
        // Otherwise a slow frame gradually shifts the loop earlier and earlier relative to everything else.
        let out = ParticleTimeline(
            keyframes: [
                ParticleKeyframe(at: 0, curve: .smooth, values: [.glow: 0]),
                ParticleKeyframe(at: 4, curve: .smooth, values: [.glow: 4]),
            ],
            loops: true
        )
        let head = ParticlePlayhead(isPlaying: true, at: 3.5).advanced(by: 1, through: out)
        #expect(abs(head.at - 0.5) < 1e-12, "landed at \(head.at)")
        #expect(head.isPlaying)
    }

    @Test("A timeline that does not loop stops at the end, showing the last keyframe")
    func notLoopingStopsAtTheEnd() {
        let out = ParticleTimeline(
            keyframes: [
                ParticleKeyframe(at: 0, curve: .smooth, values: [.glow: 0]),
                ParticleKeyframe(at: 4, curve: .smooth, values: [.glow: 4]),
            ],
            loops: false
        )
        let head = ParticlePlayhead(isPlaying: true, at: 3.9).advanced(by: 1, through: out)
        #expect(head.at == 4, "stopped at \(head.at), which should be the end exactly")
        #expect(!head.isPlaying)
        #expect(out.value(of: .glow, at: head.at) == 4, "the last keyframe's value is what is left showing")
    }

    @Test("A timeline with no length parks at the start rather than running forever")
    func lengthlessTimelineParks() {
        // Everything at one moment, so there is nothing to play through. A single keyframe part-way along is
        // a different thing — that is a timeline of that length whose value happens to be constant, and it
        // plays normally.
        let instant = timeline([(0, .smooth, [.glow: 1])])
        #expect(ParticlePlayhead(isPlaying: true, at: 0).advanced(by: 1, through: instant).at == 0)

        let later = timeline([(2, .smooth, [.glow: 1])])
        #expect(
            ParticlePlayhead(isPlaying: true, at: 0).advanced(by: 1, through: later).at == 1,
            "a keyframe two seconds in makes a two-second timeline"
        )
    }

    /// Past the end by a fixed margin, so there is somewhere to move to and record the next keyframe. Held to
    /// the end exactly, a timeline of one keyframe had no length and the playhead could not move at all.
    @Test("Scrubbing reaches a little past the end, and does not start or stop the timeline")
    func scrubbingIsBounded() {
        let out = timeline([(0, .smooth, [.glow: 0]), (4, .smooth, [.glow: 4])])
        let playing = ParticlePlayhead(isPlaying: true, at: 1)
        #expect(playing.scrubbed(to: 99, through: out).at == 4 + ParticleTimeline.roomToRecord)
        let single = timeline([(0, .smooth, [.glow: 1])])
        #expect(ParticlePlayhead().scrubbed(to: 3, through: single).at == 3, "one keyframe left nowhere to go")
        #expect(playing.scrubbed(to: -9, through: out).at == 0)
        #expect(playing.scrubbed(to: 2, through: out).isPlaying, "scrubbing should not stop playback")
        #expect(playing.scrubbed(to: .nan, through: out).at == 0)
    }

    @Test("A frame of nonsense does not move the playhead")
    func unusableFramesDoNotAdvance() {
        let out = timeline([(0, .smooth, [.glow: 0]), (4, .smooth, [.glow: 4])])
        let head = ParticlePlayhead(isPlaying: true, at: 1)
        #expect(head.advanced(by: .nan, through: out).at == 1)
        #expect(head.advanced(by: -5, through: out).at == 1)
    }

    // MARK: - Joined up with the field

    @Test("Every setting a timeline can hold can be read and written")
    func everySettingIsWired() {
        // The reference implementation keeps three separate lists of what can be animated, so a setting can
        // be added to two of them and silently never animate. This is the test that there is one list.
        let field = ParticleEngine(width: 400, height: 700, seed: 1)
        let resting = field.currentTimelineValues()
        for setting in ParticleTimeline.Setting.allCases {
            #expect(resting[setting] != nil, "\(setting.rawValue) cannot be read")

            // Written, and then read back to prove it arrived somewhere real.
            let range = setting.range
            let target = range.low + (range.high - range.low) * 0.37
            field.applyTimelineValues([setting: target])
            let after = field.currentTimelineValues()[setting]
            #expect(
                abs((after ?? .nan) - target) < 1e-9,
                "\(setting.rawValue) was set to \(target) and reads back as \(after ?? .nan)"
            )
        }
    }

    @Test("Every setting has a name and a sensible range")
    func settingsAreDescribed() {
        for setting in ParticleTimeline.Setting.allCases {
            #expect(!setting.displayName.isEmpty)
            let range = setting.range
            #expect(range.low < range.high, "\(setting.rawValue) has an empty range")
        }
        #expect(
            Set(ParticleTimeline.Setting.allCases.map(\.displayName)).count
                == ParticleTimeline.Setting.allCases.count
        )
    }

    @Test("The timeline plays as the field ticks")
    func timelinePlaysWithTheField() {
        // Advanced from the tick rather than from a clock, so a recorded piece plays back the same whatever
        // the field is doing to the frame rate.
        let field = ParticleEngine(width: 400, height: 700, seed: 1)
        field.timeline = ParticleTimeline(
            keyframes: [
                ParticleKeyframe(at: 0, curve: .straight, values: [.gravityY: 0]),
                ParticleKeyframe(at: 1, curve: .straight, values: [.gravityY: 1]),
            ],
            loops: false
        )
        field.playhead = ParticlePlayhead(isPlaying: true, at: 0)

        for _ in 0 ..< 30 { field.step() }
        #expect(abs(field.gravityY - 0.5) < 0.05, "halfway through, gravity is \(field.gravityY)")

        for _ in 0 ..< 60 { field.step() }
        #expect(abs(field.gravityY - 1) < 1e-9, "at the end it should be exactly the last value")
        #expect(!field.playhead.isPlaying, "and playback should have stopped")
    }

    @Test("An empty timeline leaves the field alone")
    func emptyTimelineDoesNotInterfere() {
        let field = ParticleEngine(width: 400, height: 700, seed: 1)
        field.gravityY = 0.42
        field.playhead = ParticlePlayhead(isPlaying: true, at: 0)
        for _ in 0 ..< 30 { field.step() }
        #expect(field.gravityY == 0.42)
    }

    // MARK: - Saving

    @Test("A timeline comes back with a saved scene")
    func timelineSurvivesASave() throws {
        let source = ParticleEngine(width: 400, height: 700, seed: 3)
        source.timeline = ParticleTimeline(
            keyframes: [
                ParticleKeyframe(at: 0, curve: .easeOut, values: [.gravityY: -0.4, .glow: 0]),
                ParticleKeyframe(at: 3.5, curve: .hold, values: [.glow: 2.5]),
                ParticleKeyframe(at: 7, curve: .smooth, values: [.gravityY: 1, .swirl: 4]),
            ],
            loops: false
        )
        source.addParticle(x: 10, y: 20, velocityX: 0, velocityY: 0, radius: 2, charge: 0)

        let bytes = try JSONEncoder().encode(source.captureState())
        let state = try JSONDecoder().decode(ParticleState.self, from: bytes)
        let loaded = ParticleEngine(width: 100, height: 100, seed: 9)
        #expect(loaded.apply(state))

        #expect(loaded.timeline.keyframes.count == 3)
        #expect(!loaded.timeline.loops)
        #expect(loaded.timeline.keyframes[1].curve == .hold)
        #expect(loaded.timeline.keyframes[2].values[.swirl] == 4)
        #expect(!loaded.playhead.isPlaying, "a loaded scene should not start playing on its own")
    }

    /// A saved scene with no timeline is a scene with no timeline. This used to keep whatever the field had
    /// before, so a recording made for one scene went on overwriting the gravity and the glow of the next.
    @Test("A scene with no timeline has none once loaded")
    func olderScenesHaveNoTimeline() throws {
        let source = ParticleEngine(width: 400, height: 700, seed: 3)
        source.addParticle(x: 10, y: 20, velocityX: 0, velocityY: 0, radius: 2, charge: 0)
        let state = source.captureState()
        #expect(state.timeline == nil, "an empty timeline should not be written at all")

        let loaded = ParticleEngine(width: 100, height: 100, seed: 9)
        loaded.timeline = ParticleTimeline(keyframes: [
            ParticleKeyframe(at: 1, curve: .smooth, values: [.glow: 1])
        ])
        #expect(loaded.apply(state))
        #expect(loaded.timeline.keyframes.isEmpty, "the previous field's recording was carried into this one")
    }

    @Test("A hand-edited timeline is put in order on the way in")
    func loadedTimelineIsTidied() {
        let source = ParticleEngine(width: 400, height: 700, seed: 3)
        source.addParticle(x: 10, y: 20, velocityX: 0, velocityY: 0, radius: 2, charge: 0)
        var state = source.captureState()
        state.timeline = ParticleTimeline(keyframes: [
            ParticleKeyframe(at: 9, curve: .smooth, values: [.glow: 99]),
            ParticleKeyframe(at: 1, curve: .smooth, values: [.glow: -5]),
        ])

        let loaded = ParticleEngine(width: 100, height: 100, seed: 9)
        #expect(loaded.apply(state))
        #expect(loaded.timeline.keyframes.map(\.at) == [1, 9])
        #expect(loaded.timeline.keyframes[0].values[.glow] == 0, "a negative glow is pulled to nothing")
        #expect(loaded.timeline.keyframes[1].values[.glow] == 4, "and ninety-nine to its limit")
    }

    @Test("A timeline survives being written down on its own")
    func typesRoundTrip() throws {
        let out = ParticleTimeline(
            keyframes: [ParticleKeyframe(at: 2, curve: .easeIn, values: [.drag: 0.95])],
            loops: false
        )
        let bytes = try JSONEncoder().encode(out)
        #expect(try JSONDecoder().decode(ParticleTimeline.self, from: bytes) == out)

        let head = ParticlePlayhead(isPlaying: true, at: 1.25)
        let headBytes = try JSONEncoder().encode(head)
        #expect(try JSONDecoder().decode(ParticlePlayhead.self, from: headBytes) == head)
    }

    @Test("A stopped timeline does not pin the settings it records")
    func stoppedTimelineLeavesSettingsAlone() {
        let engine = ParticleEngine(width: 400, height: 700, seed: 1)
        engine.timeline = timeline([(0, .smooth, [.gravityY: 0.3])])
        engine.gravityY = 0.9
        engine.step()
        #expect(engine.gravityY == 0.9, "a slider moved while the timeline was stopped snapped back")
    }
}
