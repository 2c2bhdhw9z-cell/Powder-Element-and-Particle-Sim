import CrucibleCore
import Foundation
import UIKit

/// What the lasso does with what it lifted: moves it once, or puts copies of it down until told to stop.
enum LassoPlacing {
    case move
    case copy
}

/// The tools that are not painting: the lasso, the thermometer, the rewind, the tide, measurements as numbers, and
/// the two things to print — a poster and a drawing for a pen plotter.
///
/// What they remember is stored in `SimulationModel` itself, because an extension cannot hold anything; what they do
/// is here. The real work is the engine's, in `PowderLabTools.swift`, where it is tested. This is the part that knows
/// about touches, undo, the play button and files.
extension SimulationModel {
    // MARK: - Where a touch lands

    /// A touch, given in fractions of the view, as a place in the grid — not snapped to a cell, so a loop drawn
    /// through several touches inside one cell is still a smooth loop.
    private func gridPoint(fractionX fx: Double, fractionY fy: Double) -> (x: Double, y: Double) {
        (fx * Double(engine.width), fy * Double(engine.height))
    }

    /// A touch as the cell it landed in, kept inside the world: a finger that has slid off the edge still means the
    /// edge.
    private func gridCell(fractionX fx: Double, fractionY fy: Double) -> (x: Int, y: Int) {
        let point = gridPoint(fractionX: fx, fractionY: fy)
        let x = point.x.isFinite ? Int(max(0, min(Double(engine.width - 1), point.x.rounded(.down)))) : 0
        let y = point.y.isFinite ? Int(max(0, min(Double(engine.height - 1), point.y.rounded(.down)))) : 0
        return (x, y)
    }

    // MARK: - Choosing a tool

    /// Whether the next touch does something other than paint: the eyedropper, the lasso, or putting the thermometer
    /// in. The brush buttons show no shape as chosen while one of these is.
    var isUsingTool: Bool { isSampling || isLassoing || isPlacingThermometer || isHandlingPeople }

    /// Goes back to painting with a shape, putting down whichever tool was in hand.
    func chooseShape(_ shape: BrushShape) {
        brushShape = shape
        isSampling = false
        putToolsDownToPaint()
    }

    /// Puts the lasso and the thermometer down, so the next touch paints.
    func putToolsDownToPaint() {
        if isLassoing { isLassoing = false }
        if isPlacingThermometer { isPlacingThermometer = false }
        if isHandlingPeople {
            isHandlingPeople = false
            // Whoever was in hand is put down rather than left hanging in the air for good.
            engine.dropHeldPeople()
        }
    }

    // MARK: - The little people

    /// Picks up the hand that puts people in and moves them about, or puts it down.
    func togglePeople() {
        let wanted = !isHandlingPeople
        if wanted {
            putToolsDownToPaint()
            isSampling = false
        } else {
            engine.dropHeldPeople()
        }
        isHandlingPeople = wanted
    }

    /// How many people are in the world.
    var peopleCount: Int { engine.people.count }

    /// Whether there is room for anybody else.
    var canAddPerson: Bool { engine.people.count < PowderPeople.most }

    /// Takes everybody away.
    func clearPeople() {
        recordUndoPoint()
        engine.clearPeople()
    }

    /// A touch while the hand is in use: grabs whoever is near, or puts somebody new there.
    ///
    /// Grabbing first, because a tap near somebody almost always means that person — and a world where tapping next to
    /// a person made a second person standing on their head would be unusable within about four taps.
    private func peopleBeganStroke(atFractionX fx: Double, fractionY fy: Double) {
        let point = gridPoint(fractionX: fx, fractionY: fy)
        if let found = engine.person(nearX: point.x, y: point.y, within: Self.reachForAPerson) {
            _ = engine.holdPerson(found.id)
            engine.carryHeldPeople(toX: point.x, y: point.y)
            Haptics.selection()
            return
        }
        let cell = gridCell(fractionX: fx, fractionY: fy)
        guard engine.addPerson(atX: cell.x, y: cell.y) != nil else {
            peopleNote = "Twenty is as many people as a world can hold."
            return
        }
        peopleNote = nil
        recordUndoPoint()
        Haptics.firm()
    }

    /// How near a tap has to be to count as reaching for somebody, in cells.
    ///
    /// Generous, because a person is one cell wide and a fingertip is not. Too small and the tool feels broken; too
    /// large and a tap meant to add somebody keeps grabbing a person across the room instead.
    static let reachForAPerson = 6.0

    /// Picks up the eyedropper, or puts it down.
    func toggleSampling() {
        let wanted = !isSampling
        if wanted { putToolsDownToPaint() }
        isSampling = wanted
    }

    /// Picks up the lasso, or puts it down again — putting back anything it was holding.
    func toggleLasso() {
        if isLassoing {
            isLassoing = false
            return
        }
        // Somebody else's world arrives over this one every frame while following a room, so anything moved here
        // would jump straight back.
        guard !isFollowingRoom else { return }
        isSampling = false
        isPlacingThermometer = false
        lassoProblem = nil
        isLassoing = true
    }

    /// The next touch puts the thermometer in, or moves it if it is already in. Pressed again, it does not.
    func beginPlacingThermometer() {
        if isPlacingThermometer {
            isPlacingThermometer = false
            return
        }
        isSampling = false
        if isLassoing { isLassoing = false }
        isPlacingThermometer = true
    }

    // MARK: - Touches

    /// A touch has begun. Returns whether one of these tools took it, in which case nothing is painted.
    func toolBeganStroke(atFractionX fx: Double, fractionY fy: Double) -> Bool {
        if isHandlingPeople {
            toolOwnsStroke = true
            peopleBeganStroke(atFractionX: fx, fractionY: fy)
            return true
        }
        if isPlacingThermometer {
            toolOwnsStroke = true
            let cell = gridCell(fractionX: fx, fractionY: fy)
            placeThermometer(atX: cell.x, y: cell.y)
            return true
        }
        guard isLassoing, !isFollowingRoom else { return false }
        toolOwnsStroke = true
        if lassoPlacing != nil {
            // Holding a piece: it follows the finger, and goes down where the finger lifts.
            let cell = gridCell(fractionX: fx, fractionY: fy)
            heldAt = (cell.x, cell.y)
            return true
        }
        // A new loop, letting go of any earlier one.
        lassoSelection = []
        lassoProblem = nil
        lassoRecolourUndoTaken = false
        lassoLoop = [gridPoint(fractionX: fx, fractionY: fy)]
        isDrawingLasso = true
        return true
    }

    /// The longest a loop may be, in points along it. Far more than a finger can draw round a phone's screen; the
    /// limit is only there so a finger left circling for a minute cannot grow it without end.
    static let longestLoop = 6_000

    /// A touch has moved. Returns whether one of these tools had it.
    func toolContinuedStroke(atFractionX fx: Double, fractionY fy: Double) -> Bool {
        guard toolOwnsStroke else { return false }
        if isHandlingPeople {
            let point = gridPoint(fractionX: fx, fractionY: fy)
            engine.carryHeldPeople(toX: point.x, y: point.y)
            return true
        }
        if isPlacingThermometer {
            let cell = gridCell(fractionX: fx, fractionY: fy)
            if let thermometer, thermometer.x == cell.x, thermometer.y == cell.y { return true }
            placeThermometer(atX: cell.x, y: cell.y)
        } else if isDrawingLasso {
            let point = gridPoint(fractionX: fx, fractionY: fy)
            if let last = lassoLoop.last {
                let dx = point.x - last.x
                let dy = point.y - last.y
                // Half a cell apart is plenty to follow a finger by, and keeps a long loop cheap to draw and to fill.
                guard dx * dx + dy * dy >= 0.25 else { return true }
            }
            if lassoLoop.count < Self.longestLoop {
                lassoLoop.append(point)
            } else {
                // Full: the end of the loop still follows the finger, so it closes where the finger lifts.
                lassoLoop[lassoLoop.count - 1] = point
            }
        } else if lassoPlacing != nil {
            let cell = gridCell(fractionX: fx, fractionY: fy)
            if heldAt?.x != cell.x || heldAt?.y != cell.y { heldAt = (cell.x, cell.y) }
        }
        return true
    }

    /// A finger has lifted.
    func toolEndedStroke() {
        guard toolOwnsStroke else { return }
        toolOwnsStroke = false
        if isHandlingPeople {
            // Let go where the finger lifted. They fall from there, which is the whole point of being able to carry
            // somebody up a cliff.
            engine.dropHeldPeople()
            Haptics.tap()
            return
        }
        if isPlacingThermometer {
            // One placement per press of the button, like the eyedropper.
            isPlacingThermometer = false
            Haptics.selection()
        } else if isDrawingLasso {
            closeLasso()
        } else if lassoPlacing != nil, let place = heldAt {
            putDown(at: place)
        }
    }

    // MARK: - The lasso

    /// Whether a loop has been closed round something and is waiting to be told what to do with it.
    var hasLassoSelection: Bool { !lassoSelection.isEmpty && lassoPlacing == nil }

    /// Closes the loop that was just drawn, and takes what is inside it.
    private func closeLasso() {
        isDrawingLasso = false
        let inside = lassoLoop.count >= 3 ? engine.cells(insideLoop: lassoLoop) : []
        guard !inside.isEmpty else {
            lassoLoop = []
            lassoSelection = []
            lassoProblem = "That loop was too small to hold anything. Draw right round what you want."
            return
        }
        // A loop round nothing but air has nothing to move, heat or delete, and saying so is kinder than offering
        // five buttons that all do nothing.
        guard inside.contains(where: { engine.type[$0] != Element.empty }) else {
            lassoLoop = []
            lassoSelection = []
            lassoProblem = "There is only air inside that loop."
            return
        }
        lassoSelection = inside
        lassoProblem = nil
        lassoRecolourUndoTaken = false
        Haptics.selection()
    }

    /// Lifts what the loop holds, to move it — leaving a hole behind, with an undo point — or to put copies of it
    /// down, leaving it where it is.
    func liftLasso(copying: Bool) {
        guard hasLassoSelection else { return }
        let stamp = engine.stamp(of: lassoSelection)
        guard stamp.count > 0 else {
            clearLassoLoop()
            return
        }
        if !copying {
            recordUndoPoint()
            engine.clear(cells: lassoSelection)
            refreshCounts()
        }
        heldStamp = stamp
        lassoPlacing = copying ? .copy : .move
        heldOutline = lassoLoop.map { ($0.x - Double(stamp.originX), $0.y - Double(stamp.originY)) }
        heldAt = nil
        Haptics.selection()
    }

    /// Puts what is held down with its middle at a cell.
    private func putDown(at place: (x: Int, y: Int)) {
        guard let stamp = heldStamp, let placing = lassoPlacing else { return }
        // A copy is a change of its own, and each is its own undo — which is how a copy put in the wrong place is taken
        // back without losing the others. A move's undo point was taken when it was lifted, so lifting and putting
        // down come undone together.
        if placing == .copy { recordUndoPoint() }
        engine.place(stamp, atX: place.x, y: place.y)
        refreshCounts()
        heldAt = nil
        Haptics.firm()
        guard placing == .move else { return }
        // Moved: the loop goes with it, round the piece in its new place, so it can be moved again or heated there.
        let dx = Double(place.x - stamp.originX)
        let dy = Double(place.y - stamp.originY)
        lassoLoop = lassoLoop.map { ($0.x + dx, $0.y + dy) }
        heldStamp = nil
        lassoPlacing = nil
        heldOutline = []
        lassoRecolourUndoTaken = false
        lassoSelection = engine.cells(insideLoop: lassoLoop)
        if lassoSelection.isEmpty { lassoLoop = [] }
    }

    /// Puts a piece that was lifted to move back exactly where it came from.
    func putLassoBack() {
        guard lassoPlacing == .move else { return }
        settleHeldPiece()
        lassoSelection = engine.cells(insideLoop: lassoLoop)
        if lassoSelection.isEmpty { lassoLoop = [] }
        Haptics.selection()
    }

    /// Stops putting copies down. The loop stays round the original, to do something else with.
    func stopCopying() {
        guard lassoPlacing == .copy else { return }
        heldStamp = nil
        lassoPlacing = nil
        heldOutline = []
        heldAt = nil
    }

    /// Empties everything inside the loop.
    func deleteLasso() {
        guard hasLassoSelection else { return }
        recordUndoPoint()
        engine.clear(cells: lassoSelection)
        refreshCounts()
        Haptics.firm()
        clearLassoLoop()
    }

    /// Heats or cools everything inside the loop.
    func warmLasso(by degrees: Double) {
        guard hasLassoSelection else { return }
        recordUndoPoint()
        engine.warm(cells: lassoSelection, by: degrees)
        Haptics.selection()
    }

    /// How much one press of the lasso's heat or cool buttons changes what it holds, in degrees.
    static let lassoWarmth = 250.0

    /// Recolours everything inside the loop, or gives it its own colours back with nought.
    ///
    /// One undo point for however many colours are tried on the same selection, because the colour picker reports
    /// every shade a finger passes over.
    func recolourLasso(_ word: UInt32) {
        guard hasLassoSelection else { return }
        if !lassoRecolourUndoTaken {
            recordUndoPoint()
            lassoRecolourUndoTaken = true
        }
        engine.tint(cells: lassoSelection, with: word)
    }

    /// Finishes with the lasso altogether, and goes back to painting.
    func finishLasso() {
        isLassoing = false
    }

    /// Puts the lasso down: a piece still in the hand goes back where it came from, and the loop is let go.
    ///
    /// Called whenever the lasso stops being the tool in hand, however that happens.
    func cancelLasso() {
        settleHeldPiece()
        clearLassoLoop()
        lassoProblem = nil
    }

    /// A piece lifted to move is put back exactly where it came from; copies simply stop.
    private func settleHeldPiece() {
        if lassoPlacing == .move, let stamp = heldStamp {
            engine.place(stamp, atX: stamp.originX, y: stamp.originY)
            refreshCounts()
        }
        heldStamp = nil
        lassoPlacing = nil
        heldOutline = []
        heldAt = nil
    }

    private func clearLassoLoop() {
        lassoLoop = []
        lassoSelection = []
        isDrawingLasso = false
        lassoRecolourUndoTaken = false
    }

    // MARK: - When something else changes the world

    /// Before the whole world is replaced, cleared, turned over or resized.
    ///
    /// A piece held by the lasso goes back first, so it is part of the world the undo point records rather than lost
    /// with the hand that held it, and the loop is let go: it was round a place in a world that is going. The lasso
    /// itself stays in hand, for a loop in the new one.
    func toolsBeforeWorldReplaced() {
        if isRewinding { finishRewind(keeping: false) }
        guard heldStamp != nil || !lassoLoop.isEmpty || isDrawingLasso else { return }
        settleHeldPiece()
        clearLassoLoop()
    }

    /// Before undo or redo.
    ///
    /// Copies carry on — what is held is only a copy, and undoing the last one put down is exactly how a copy in the
    /// wrong place is taken back. A piece lifted to move is simply let go of, since undo puts it back itself: lifting
    /// it was the last thing done. The loop is let go either way, because what it was round has changed.
    func toolsBeforeUndo() {
        isDrawingLasso = false
        guard lassoPlacing != .copy else { return }
        heldStamp = nil
        lassoPlacing = nil
        heldOutline = []
        heldAt = nil
        lassoLoop = []
        lassoSelection = []
        lassoRecolourUndoTaken = false
    }

    /// After the grid has changed size, with everything in it either kept in place or stretched to fit.
    func toolsFollowResize(fromWidth oldWidth: Int, height oldHeight: Int, stretched: Bool) {
        // Moments of another size cannot be gone back to, and the memory they may use buys a different number now.
        rewind.clear()
        rewind.fit(budgetBytes: Self.rewindMemory, cellCount: engine.cellCount)
        if rewindCount != 0 { rewindCount = 0 }

        guard var probe = thermometer else { return }
        var x = probe.x
        var y = probe.y
        if stretched, oldWidth > 0, oldHeight > 0 {
            // Stretched with the world, to the same place in what is there.
            x = Int((Double(x) + 0.5) * Double(engine.width) / Double(oldWidth))
            y = Int((Double(y) + 0.5) * Double(engine.height) / Double(oldHeight))
        }
        // Kept inside rather than lost off the edge of a world that has shrunk.
        x = max(0, min(engine.width - 1, x))
        y = max(0, min(engine.height - 1, y))
        guard x != probe.x || y != probe.y || stretched else { return }
        probe.move(toX: x, y: y)
        probe.read(engine)
        thermometer = probe
    }

    /// Somebody else's world is about to be shown here, over this one, every frame.
    func putToolsAwayForRoom() {
        if isRewinding { finishRewind(keeping: false) }
        putToolsDownToPaint()
    }

    // MARK: - The thermometer

    /// Puts the thermometer in at a cell, or moves it there, and reads it straight away.
    func placeThermometer(atX x: Int, y: Int) {
        let cx = max(0, min(engine.width - 1, x))
        let cy = max(0, min(engine.height - 1, y))
        if thermometer == nil {
            thermometer = PowderThermometer(x: cx, y: cy)
        } else {
            thermometer?.move(toX: cx, y: cy)
        }
        thermometer?.read(engine)
        thermometerAge = 0
    }

    /// Takes the thermometer out.
    func removeThermometer() {
        thermometer = nil
        isPlacingThermometer = false
    }

    /// Reads the thermometer every thirty moments — four times a second at ordinary speed on most phones — by the
    /// world's moments rather than the clock's, so its little graph is of the world's time and holds still while
    /// the world is paused.
    func noteThermometer(after moments: Int) {
        guard thermometer != nil else { return }
        thermometerAge += moments
        guard thermometerAge >= 30 else { return }
        thermometerAge = 0
        thermometer?.read(engine)
    }

    // MARK: - Rewind

    /// Whether there is anything to go back to.
    var canRewind: Bool { rewindCount > 0 && !isFollowingRoom }

    /// Brings out the rewind: time stops, and the world can be scrubbed back through the last little while.
    func beginRewind() {
        endParallel(keepSecond: false)
        guard canRewind, !isRewinding else { return }
        cancelPendingEvent()
        // A piece in the lasso's hand goes back first, so it is in the present that scrubbing returns to.
        toolsBeforeWorldReplaced()
        putToolsDownToPaint()
        wasRunningBeforeRewind = isRunning
        rewind.beginScrub(engine, time: worldSeconds)
        rewindCount = rewind.count
        rewindStepsBack = 0
        isRewinding = true
        isRunning = false
        // So undo and redo grey out: they are not available while scrubbing.
        engineDidChange()
        Haptics.selection()
    }

    /// Shows the world as it was some kept moments ago. Nought is now.
    func scrubRewind(to stepsBack: Int) {
        guard isRewinding else { return }
        let wanted = max(0, min(rewind.count, stepsBack))
        guard wanted != rewindStepsBack else { return }
        guard rewind.show(engine, stepsBack: wanted) else { return }
        rewindStepsBack = wanted
        refreshCounts()
        Haptics.selection()
    }

    /// Puts the rewind away: either carrying on from the moment on screen, which lets go of everything after it, or
    /// going back to now exactly as it was.
    ///
    /// Carrying on from a past moment is recorded as a change like any other, so the present that was left is one
    /// undo away.
    func finishRewind(keeping: Bool) {
        guard isRewinding else { return }
        let steps = rewindStepsBack
        let present = rewind.presentSnapshot
        let then = rewind.time(stepsBack: steps)
        // Before anything that might ask whether a rewind is under way.
        isRewinding = false
        rewindStepsBack = 0
        if keeping, steps > 0, rewind.endScrub(engine, keepingStepsBack: steps) {
            if let present { history.push(present) }
            if let then { rewindClock(to: then) }
        } else {
            rewind.endScrub(engine, keepingStepsBack: nil)
        }
        rewindCount = rewind.count
        // Time carries on if it was running before — or if play is what ended this, in which case it already is.
        if !isRunning, wasRunningBeforeRewind { isRunning = true }
        afterWholeWorldChange()
    }

    /// The world's clock, put back to the moment the world has gone back to. Measurements taken after it describe
    /// a future that did not, in the end, happen, and the thermometer's graph with them.
    private func rewindClock(to then: Double) {
        worldSeconds = then
        if isMeasuring {
            measurements.forget(after: then - measuringSince)
            if then < measuringSince { measuringSince = then }
            measurementRows = measurements.rows.count
        }
        if let probe = thermometer {
            thermometer?.move(toX: probe.x, y: probe.y)
            thermometer?.read(engine)
        }
    }

    /// How long ago the moment on screen was, in seconds of the world running.
    var rewindSecondsBack: Double {
        _ = rewindStepsBack
        return rewind.timeBack(stepsBack: rewindStepsBack)
    }

    /// How long ago the oldest kept moment was, in seconds of the world running.
    var rewindReachSeconds: Double {
        _ = rewindCount
        return rewind.timeBack(stepsBack: rewind.count)
    }

    // MARK: - The tide

    /// Whether the sea along one side is rising and falling.
    var tideOn: Bool {
        get {
            observeEngine()
            return engine.tide != nil
        }
        set {
            guard newValue != (engine.tide != nil) else { return }
            engine.tide = newValue ? tideSettings : nil
            engineDidChange()
        }
    }

    /// Which edge the open sea is beyond.
    var tideSide: PowderTide.Side {
        get {
            observeEngine()
            return (engine.tide ?? tideSettings).side
        }
        set { changeTide(side: newValue) }
    }

    /// How long one rise and fall takes, in seconds at ordinary speed.
    var tidePeriodSeconds: Double {
        get {
            observeEngine()
            return (engine.tide ?? tideSettings).period / Self.momentsPerSecond
        }
        set { changeTide(period: newValue * Self.momentsPerSecond) }
    }

    /// How many grains of water arrive in a moment at the height of the flood.
    var tideStrength: Double {
        get {
            observeEngine()
            return (engine.tide ?? tideSettings).strength
        }
        set { changeTide(strength: newValue) }
    }

    /// Changes one of the tide's settings, through its own initialiser so the limits hold, and applies it at once if
    /// the tide is running.
    private func changeTide(side: PowderTide.Side? = nil, period: Double? = nil, strength: Double? = nil) {
        let current = engine.tide ?? tideSettings
        let changed = PowderTide(
            side: side ?? current.side,
            period: period ?? current.period,
            strength: strength ?? current.strength
        )
        tideSettings = changed
        // The water already in the world is left as it is: only how it comes and goes from now on changes.
        if engine.tide != nil, engine.tide != changed { engine.tide = changed }
        engineDidChange()
    }

    /// How many moments a second the world runs at ordinary speed on this phone: one a frame, at the display's rate.
    static var momentsPerSecond: Double {
        Double(max(30, min(120, UIScreen.main.maximumFramesPerSecond)))
    }

    // MARK: - Measurements, as numbers

    /// The measurements as a spreadsheet file, with temperatures in the reader's own scale, ready to be handed to
    /// something that reads spreadsheets. Nothing if nothing has been measured.
    func measurementsFile(unit: TemperatureUnit) -> URL? {
        guard !measurements.rows.isEmpty else { return nil }
        let convert: (Double) -> Double = unit == .fahrenheit ? { $0 * 9 / 5 + 32 } : { $0 }
        let text = measurements.csv(
            name: { engine.registry.element($0).name },
            temperature: convert,
            unit: unit.title
        )
        return LabSnapshot.write(text: text, named: LabSnapshot.fileName() + "-measurements", extension: "csv")
    }

    /// Forgets everything measured so far and starts a fresh sheet, carrying on measuring.
    func restartMeasurements() {
        measurements.clear()
        measuringSince = worldSeconds
        measurementRows = 0
    }

    // MARK: - Things to print

    /// How many pixels along its longer side a poster is: an A3 sheet at the resolution a printer prints photographs.
    static let posterPixels = 4_960

    /// The world as a picture big enough to print as a poster, written to a file to hand on.
    ///
    /// Every grain a crisp square, enlarged by whole numbers exactly as the ordinary picture is, only much further.
    /// Drawn here, since the engine is only ever touched from here; enlarged and compressed elsewhere, because at ten
    /// million pixels or so that takes long enough to be felt, and the world should not stop while it happens.
    func posterFile() async -> URL? {
        let width = engine.width
        let height = engine.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            engine.render(into: base, overlay: overlay)
        }
        let factor = PixelExport.enlargement(forWidth: max(width, height), targetWidth: Self.posterPixels)
        let name = LabSnapshot.fileName() + "-poster"
        let colours = pixels
        return await Task.detached(priority: .userInitiated) {
            LabSnapshot.writePNG(fromEngineColors: colours, width: width, height: height, scale: factor, named: name)
        }.value
    }

    /// The largest drawing that fits an A4 sheet with a centimetre to spare all round, in millimetres. A4 because that
    /// is what most pen plotters take; the drawing is lines, so it scales to any other size without losing anything.
    static let plotterPage = (width: 190.0, height: 277.0)

    /// The world as a line drawing for a pen plotter — every edge where one thing meets another, as long straight
    /// lines — written to a file to hand on.
    func plotterFile() async -> URL? {
        let width = engine.width
        let height = engine.height
        guard width > 0, height > 0 else { return nil }
        let types = Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))
        let cell = min(Self.plotterPage.width / Double(width), Self.plotterPage.height / Double(height))
        let name = LabSnapshot.fileName() + "-plotter"
        return await Task.detached(priority: .userInitiated) {
            let drawing = PowderEngine.outlineSVG(types: types, width: width, height: height, cellMillimetres: cell)
            return LabSnapshot.write(text: drawing, named: name, extension: "svg")
        }.value
    }
}
