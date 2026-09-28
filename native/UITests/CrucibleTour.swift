import Foundation
import UIKit
import XCTest

/// A walk through the app the way somebody would use it, on a simulated phone on the checks' Mac.
///
/// It fails if the app closes by itself, stops answering, or shows a blank world — the faults no test of the engine
/// can see, because each is a fault of the app around it. On the way it takes a picture of every screen it reaches,
/// kept with the run, so what the app looks like can be seen without a phone.
///
/// Each part starts the app afresh, as if it had just been installed (see `CrucibleApp.freshStart`), so a fault in one
/// part cannot hide what the others would have found.
///
/// Buttons are found by names given to them for this (`accessibilityIdentifier`), not by what they say, so rewording a
/// button does not break the walk. Nobody using the app sees or hears those names.
@MainActor
final class CrucibleTour: XCTestCase {
    // MARK: - The parts of the walk

    /// The powder world: the tray, a material, a stroke, play and pause, the Lab panel and a slider in it, and the
    /// tools that are not painting.
    func testPowderWorld() {
        let app = launch()
        let world = element("world.powder", in: app)
        picture(app, "01 Powder world")
        expectDrawn(world, "the powder world", in: app)

        tap("tray.arrow", "the powder tray's arrow", in: app)
        picture(app, "02 Powder tray open")
        if let sand = find("material.Sand", in: app, scrollingWithin: trayArea(app)) {
            sand.tap()
            stillRunning(app, after: "choosing sand")
        } else {
            XCTFail("sand was not in the tray")
            report(app, "Sand was not in the tray")
        }
        tap("tray.arrow", "the powder tray's arrow, to close it", in: app)
        guard isRunning(app) else { return }

        drag(across: world, from: CGVector(dx: 0.2, dy: 0.35), to: CGVector(dx: 0.8, dy: 0.4))
        stillRunning(app, after: "drawing a line of sand")
        picture(app, "03 After drawing sand")

        tap("header.play", "pause", in: app)
        tap("header.play", "play", in: app)
        guard isRunning(app) else { return }

        tap("header.menu", "the menu", in: app)
        picture(app, "04 Lab panel")
        if let wind = find("slider.Wind", in: app, kind: .slider, scrollingIn: panelScroll(in: app)) {
            wind.adjust(toNormalizedSliderPosition: 0.8)
            stillRunning(app, after: "moving the wind slider")
            picture(app, "05 Lab panel, wind moved")
        } else {
            XCTFail("the wind slider was not in the Lab panel")
            report(app, "The wind slider was not in the Lab panel")
        }
        tap("sheet.close", "the Lab panel's close button", in: app)
        guard isRunning(app) else { return }

        // The tools that are not painting.
        tap("tray.arrow", "the powder tray's arrow", in: app)
        if let lasso = find("tool.lasso", in: app, scrollingWithin: trayArea(app)) {
            lasso.tap()
            stillRunning(app, after: "picking up the lasso")
            picture(app, "06 Lasso")
            tap("lasso.done", "the lasso's Done", in: app)
        } else {
            XCTFail("the lasso was not in the tray")
            report(app, "The lasso was not in the tray")
        }
        guard isRunning(app) else { return }

        // Rewind waits for a moment to go back to: the first is kept once the world has run for a second or so, which
        // on a simulated phone takes longer than on a real one.
        if waitUntilEnabled("tray.rewind", "rewind", in: app, seconds: 60) {
            tap("tray.rewind", "rewind", in: app)
            picture(app, "07 Rewind")
            tap("rewind.now", "rewind's Back to now", in: app)
            picture(app, "08 Back to now")
        }
    }

    /// Both chambers: switching between them, the split view, and the phone turned on its side.
    func testChambersSplitAndSideways() {
        let app = launch()
        tap("header.chamber.field", "the Field chamber", in: app)
        let field = element("world.field", in: app)
        picture(app, "10 Particle field")
        expectDrawn(field, "the particle field", in: app)

        tap("header.split", "show both chambers", in: app)
        picture(app, "11 Both chambers")
        tap("header.split", "show one chamber", in: app)
        guard isRunning(app) else { return }

        tap("header.chamber.powder", "the Powder chamber", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        stillRunning(app, after: "turning the phone on its side")
        picture(app, "12 Sideways, powder")
        tap("header.chamber.field", "the Field chamber, sideways", in: app)
        picture(app, "13 Sideways, field")
        XCUIDevice.shared.orientation = .portrait
        stillRunning(app, after: "turning the phone upright again")
    }

    /// The particle field's tray, opened by its handle and then by its arrow. The arrow is last, because it is the
    /// one reported to close the app — and the whole point of the walk is to catch that.
    func testZFieldTray() {
        let app = launch()
        tap("header.chamber.field", "the Field chamber", in: app)
        guard isRunning(app) else { return }

        tap("fieldTray.handle", "the Field tray's handle", in: app)
        picture(app, "20 Field tray, opened by its handle")
        tap("fieldTray.handle", "the Field tray's handle, to close it", in: app)
        guard isRunning(app) else { return }

        tap("fieldTray.arrow", "the Field tray's arrow", in: app)
        picture(app, "21 Field tray, opened by its arrow")
        tap("fieldTray.arrow", "the Field tray's arrow, to close it", in: app)
    }

    /// A shape described by a formula, made, and then reshaped by its own slider.
    ///
    /// The part worth walking is the slider. A recipe's knobs are built from what the recipe declares rather than
    /// written out in the interface, so a recipe whose knob is mis-declared — a range that does not contain its own
    /// starting value, a letter no formula uses — is a crash or a dead control that nothing else would notice.
    func testShapeFromAFormula() {
        let app = launch()
        tap("header.chamber.field", "the Field chamber", in: app)
        guard isRunning(app) else { return }
        let field = element("world.field", in: app)

        tap("fieldTray.handle", "the Field tray's handle", in: app)
        guard isRunning(app) else { return }

        guard let make = find("recipe.make", in: app, scrollingWithin: trayArea(app)) else {
            XCTFail("the Make button for a shape from a formula was not in the tray")
            report(app, "Make, for a shape from a formula, was not in the tray")
            return
        }
        make.tap()
        stillRunning(app, after: "making a shape from a formula")
        picture(app, "22 A shape from a formula")

        // Its own slider, while it is still known which recipe is loaded: the first of the ready-made ones, whose
        // knobs are how big it is and how many petals it has. Checked here rather than after the loop below, because
        // which recipe the loop ends on depends on which menu items this screen size can reach — and a check whose
        // subject depends on the screen is a check that fails for the wrong reason.
        if let petals = find("slider.Petals", in: app, kind: .slider, scrollingIn: trayScroll(in: app)) {
            petals.adjust(toNormalizedSliderPosition: 0.9)
            stillRunning(app, after: "turning a shape's own knob")
            petals.adjust(toNormalizedSliderPosition: 0.1)
            stillRunning(app, after: "turning it back")
            picture(app, "23 A shape reshaped by its own knob")
        } else {
            XCTFail("a recipe's own slider was not in the tray")
            report(app, "A recipe's own slider was not in the tray")
        }

        // Every ready-made recipe, each made in turn. Any one of them that cannot lay out takes the app down here
        // rather than on somebody's phone.
        for name in ["Lissajous", "Spirograph", "Heart", "Ripples", "Star", "Knot", "Grid that bends"] {
            guard isRunning(app) else { return }
            guard let picker = find("recipe.pick", in: app, scrollingWithin: trayArea(app)) else { break }
            picker.tap()
            let choice = app.buttons["recipe.choice.\(name)"]
            // Hittable as well as present. A menu of ten on a small screen puts some of its items where there is no
            // usable point to press, and asking anyway is an error rather than a miss — so the ones out of reach are
            // left for another screen size rather than failing the walk. That every recipe lays out is settled by the
            // engine's own checks; what is being walked here is the interface.
            if choice.waitForExistence(timeout: 3), canReallyTap(choice, in: app) {
                choice.tap()
                stillRunning(app, after: "choosing \(name)")
                if let again = find("recipe.make", in: app, scrollingWithin: trayArea(app)) {
                    again.tap()
                    stillRunning(app, after: "making \(name)")
                }
            } else {
                // The menu did not open, or the item is out of reach on this screen. Closed again rather than left
                // covering the tray for everything that follows.
                app.tap()
                stillRunning(app, after: "closing a menu that could not be used")
            }
        }
        picture(app, "24 The last shape from a formula")

        guard isRunning(app) else { return }
        tap("fieldTray.handle", "the Field tray's handle, to close it", in: app)
        guard isRunning(app) else { return }
        // And it is still a field that can be pushed about, which is the whole point of the shape having physics.
        drag(across: field, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.45))
        stillRunning(app, after: "shoving a shape made from a formula")
        picture(app, "25 The shape, shoved")
    }

    /// Layers: added, chosen, hidden, locked, and taken away again.
    ///
    /// Every one of these rearranges what is drawn or what a finger may touch, and the list of layers is a list of rows
    /// that appear and disappear — which is where a list-shaped interface usually comes apart. Deleting the one being
    /// looked at is the specific case: the row goes, and anything still pointing at it is pointing at nothing.
    func testZLayers() {
        let app = launch()
        tap("header.chamber.field", "the Field chamber", in: app)
        guard isRunning(app) else { return }
        let field = element("world.field", in: app)

        tap("fieldTray.handle", "the Field tray's handle", in: app)
        guard isRunning(app) else { return }

        guard let add = find("layer.add", in: app, scrollingWithin: trayArea(app)) else {
            XCTFail("the button that adds a layer was not in the tray")
            report(app, "Add, for layers, was not in the tray")
            return
        }
        add.tap()
        stillRunning(app, after: "adding a layer")
        picture(app, "26 Two layers")

        // Something on the new layer, so hiding it has something to hide.
        guard isRunning(app) else { return }
        tap("fieldTray.handle", "the Field tray's handle, to close it", in: app)
        guard isRunning(app) else { return }
        drag(across: field, from: CGVector(dx: 0.25, dy: 0.3), to: CGVector(dx: 0.75, dy: 0.7))
        stillRunning(app, after: "drawing on the second layer")
        tap("fieldTray.handle", "the Field tray's handle again", in: app)
        guard isRunning(app) else { return }

        for (id, what) in [
            ("layer.show.1", "hiding the second layer"),
            ("layer.show.1", "showing it again"),
            ("layer.lock.1", "locking the second layer"),
            ("layer.choose.0", "choosing the first layer"),
            ("layer.choose.1", "choosing the second layer"),
        ] {
            guard isRunning(app) else { return }
            guard let control = find(id, in: app, scrollingWithin: trayArea(app)) else {
                XCTFail("\(id) was not in the tray")
                report(app, "\(id) was not in the tray")
                continue
            }
            control.tap()
            stillRunning(app, after: what)
        }
        picture(app, "27 Layers, hidden and locked")

        // Its own two sliders, which only appear for the layer being worked on.
        guard isRunning(app) else { return }
        if let weight = find("slider.Weight", in: app, kind: .slider, scrollingIn: trayScroll(in: app)) {
            weight.adjust(toNormalizedSliderPosition: 0.2)
            stillRunning(app, after: "making a layer lighter")
            picture(app, "28 A layer with its own weight")
        } else {
            XCTFail("a layer's weight slider was not in the tray")
            report(app, "A layer's weight slider was not in the tray")
        }

        // Copying, and then deleting the very layer being looked at — the case that breaks a list.
        guard isRunning(app) else { return }
        if let more = find("layer.more.1", in: app, scrollingWithin: trayArea(app)) {
            more.tap()
            let copy = app.buttons["layer.copy.1"]
            if copy.waitForExistence(timeout: 3), canReallyTap(copy, in: app) {
                copy.tap()
                stillRunning(app, after: "copying a layer")
            } else {
                app.tap()
                stillRunning(app, after: "closing a menu that could not be used")
            }
        }
        guard isRunning(app) else { return }
        if let more = find("layer.more.1", in: app, scrollingWithin: trayArea(app)) {
            more.tap()
            let remove = app.buttons["layer.delete.1"]
            if remove.waitForExistence(timeout: 3), canReallyTap(remove, in: app) {
                remove.tap()
                stillRunning(app, after: "deleting the layer being looked at")
            } else {
                app.tap()
                stillRunning(app, after: "closing a menu that could not be used")
            }
        }
        picture(app, "29 After deleting a layer")
        guard isRunning(app) else { return }
        tap("fieldTray.handle", "the Field tray's handle, to close it", in: app)
        stillRunning(app, after: "closing the tray after working with layers")
    }

    /// The notebook: opened, read, and emptied.
    ///
    /// The list of things still to find is built from the notebook itself, so a discovery that names something the
    /// build no longer has, or two that answer to the same name, shows up here as an empty or duplicated row rather
    /// than anywhere it could be reasoned about.
    func testNotebook() {
        let app = launch()
        tap("tray.arrow", "the powder tray's arrow", in: app)
        guard isRunning(app) else { return }

        guard let entry = find("dock.notebook", in: app, scrollingWithin: trayArea(app)) else {
            XCTFail("the notebook was not in the tray")
            report(app, "The notebook was not in the tray")
            return
        }
        entry.tap()
        stillRunning(app, after: "opening the notebook")
        picture(app, "30 The notebook")

        // How many have been found, which on a fresh run is none of them — and the list of what to look for.
        let count = element("notebook.count", in: app)
        if !count.waitForExistence(timeout: 5) {
            XCTFail("the notebook did not say how many had been found")
            report(app, "The notebook had no count in it")
        }
        if let scroll = panelScroll(in: app) {
            scroll.swipeUp()
            stillRunning(app, after: "scrolling the notebook")
            picture(app, "31 The notebook, scrolled")
        }
        tap("sheet.close", "the notebook's close button", in: app)
        stillRunning(app, after: "closing the notebook")
    }

    /// Little people: put in, carried about, and taken away.
    ///
    /// Carrying is a drag that begins on a person and ends somewhere else, which is the same gesture as painting — so
    /// the thing worth walking is that the tool takes the touch instead of the brush, and that letting go somewhere
    /// impossible does not take the app down with it.
    func testLittlePeople() {
        let app = launch()
        let world = element("world.powder", in: app)

        tap("tray.arrow", "the powder tray's arrow", in: app)
        guard isRunning(app) else { return }
        guard let people = find("tool.people", in: app, scrollingWithin: trayArea(app)) else {
            XCTFail("the little people were not in the tray")
            report(app, "The little people were not in the tray")
            return
        }
        people.tap()
        stillRunning(app, after: "picking up the people tool")

        // Somebody put in, then a second one well away from the first.
        world.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4)).tap()
        stillRunning(app, after: "putting somebody in the world")
        world.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.4)).tap()
        stillRunning(app, after: "putting a second person in")
        picture(app, "32 Two little people")

        // Carried: a drag that starts on one of them.
        drag(across: world, from: CGVector(dx: 0.7, dy: 0.4), to: CGVector(dx: 0.5, dy: 0.15))
        stillRunning(app, after: "carrying somebody across the world")
        picture(app, "33 Somebody carried")

        // And let go at the very edge, which is where a coordinate can go wrong.
        drag(across: world, from: CGVector(dx: 0.5, dy: 0.2), to: CGVector(dx: 0.99, dy: 0.02))
        stillRunning(app, after: "letting somebody go at the edge of the world")

        guard isRunning(app) else { return }
        tap("tray.arrow", "the powder tray's arrow, to look at the tray again", in: app)
        guard isRunning(app) else { return }
        if let nobody = find("tool.nobody", in: app, scrollingWithin: trayArea(app)) {
            nobody.tap()
            stillRunning(app, after: "taking everybody away")
            picture(app, "34 Nobody left")
        } else {
            XCTFail("the button that takes everybody away was not in the tray")
            report(app, "The button that clears the people was not in the tray")
        }
    }

    /// The lab book: an experiment chosen, a guess made, the world asked to show how, and the answer explained.
    ///
    /// The card on the world changes shape three times — question, task, answer — and the answer arrives from the
    /// middle of a running world rather than from a tap, which is the part nothing but a walk can see: a card whose
    /// explanation lays out badly, or an answer that lands while the tray or a panel is in the way.
    func testLabBook() {
        let app = launch()
        tap("tray.arrow", "the powder tray's arrow", in: app)
        guard isRunning(app) else { return }
        guard let entry = find("dock.labbook", in: app, scrollingWithin: trayArea(app)) else {
            XCTFail("the lab book was not in the tray")
            report(app, "The lab book was not in the tray")
            return
        }
        entry.tap()
        stillRunning(app, after: "opening the lab book")
        picture(app, "35 The lab book")

        guard let floating = find("labbook.floating", in: app, scrollingIn: panelScroll(in: app)) else {
            XCTFail("the first experiment was not in the lab book")
            report(app, "The first experiment was not in the lab book")
            return
        }
        floating.tap()
        stillRunning(app, after: "choosing an experiment")
        guard element("labbook.card", in: app).waitForExistence(timeout: 10) else {
            XCTFail("choosing an experiment put no card on the world")
            report(app, "No lab book card")
            return
        }
        picture(app, "36 A question, waiting for a guess")

        tap("labbook.guess.0", "the first guess", in: app)
        picture(app, "37 The task")

        // Help is offered once the world has run for a fair while without an answer, which on a simulated phone is
        // slower than on a real one.
        if waitUntilEnabled("labbook.showme", "Show me", in: app, seconds: 150) {
            tap("labbook.showme", "Show me", in: app)
            picture(app, "38 Shown how")
            if element("labbook.verdict", in: app).waitForExistence(timeout: 150) {
                picture(app, "39 The world's answer")
            } else {
                XCTFail("the world never answered the experiment")
                report(app, "The experiment was never answered")
            }
        }
        guard isRunning(app) else { return }
        if element("labbook.next", in: app).waitForExistence(timeout: 5) {
            tap("labbook.next", "the next experiment", in: app)
            picture(app, "40 The next experiment")
        }
        tap("labbook.stop", "putting the lab book away", in: app)
        stillRunning(app, after: "putting the lab book away")
    }

    /// The movie studio: two stops, a caption, played, and then recorded into a clip that is offered to be sent.
    ///
    /// The clip is written by the field's own drawing, a frame at a time, into a video file — which is the part only a
    /// real graphics chip and a real video encoder can check. A clip that cannot be started, or never finishes, is
    /// found here: the walk waits for the finished clip to be offered.
    func testMovieStudio() {
        let app = launch()
        tap("header.chamber.field", "the Field chamber", in: app)
        guard isRunning(app) else { return }
        let field = element("world.field", in: app)

        tap("fieldTray.handle", "the Field tray's handle", in: app)
        guard let add = find("movie.add", in: app, kind: .any, scrollingIn: trayScroll(in: app)) else {
            XCTFail("the movie studio was not in the tray")
            report(app, "The movie studio was not in the tray")
            return
        }
        add.tap()
        stillRunning(app, after: "adding the first stop")

        // Somewhere else to look from: closer in.
        tap("fieldTray.handle", "the Field tray's handle, to close it", in: app)
        guard isRunning(app) else { return }
        field.pinch(withScale: 2.2, velocity: 1.5)
        stillRunning(app, after: "zooming in for the second stop")
        tap("fieldTray.handle", "the Field tray's handle again", in: app)
        guard let again = find("movie.add", in: app, kind: .any, scrollingIn: trayScroll(in: app)) else {
            XCTFail("the movie studio's add button went away")
            report(app, "No second add")
            return
        }
        again.tap()
        stillRunning(app, after: "adding the second stop")

        if let caption = find("movie.caption.1", in: app, kind: .textField, scrollingIn: trayScroll(in: app)) {
            caption.tap()
            caption.typeText("Closer\n")
            stillRunning(app, after: "writing a caption")
        } else {
            XCTFail("a stop had no caption to write")
            report(app, "No caption field")
        }
        picture(app, "41 A movie of two stops")

        guard let play = find("movie.play", in: app, kind: .any, scrollingIn: trayScroll(in: app)) else {
            XCTFail("the movie could not be played")
            report(app, "No play button for the movie")
            return
        }
        play.tap()
        stillRunning(app, after: "playing the movie")
        Thread.sleep(forTimeInterval: 3)
        picture(app, "42 The movie playing")
        // Stopped early, then recorded from the start.
        if element("movie.stop", in: app).waitForExistence(timeout: 5) {
            tap("movie.stop", "stopping the movie", in: app)
        }
        guard let record = find("movie.record", in: app, kind: .any, scrollingIn: trayScroll(in: app)) else {
            XCTFail("the movie could not be recorded")
            report(app, "No record button for the movie")
            return
        }
        record.tap()
        stillRunning(app, after: "recording the movie")
        // Two seconds at the first stop, three to fly, two at the second: seven, and time for the file to finish.
        let offered = app.buttons["Share the clip"]
        if offered.waitForExistence(timeout: 60) {
            picture(app, "43 The clip, offered to be sent")
            app.swipeDown()
        } else {
            XCTFail("the recorded clip was never offered")
            report(app, "The clip was never offered")
        }
        stillRunning(app, after: "recording a clip of the movie")
    }

    /// The world's own sound: water poured and lava dropped with the soundscape on, then the switch off and on again.
    ///
    /// Nothing here can hear, but it can see the app survive. The soundscape is made on the phone's audio thread, which
    /// is where a fault closes the app with nothing on screen to say why — so pouring things while it plays, and
    /// switching it while it plays, is the walk.
    func testSoundscape() {
        let app = launch()
        let world = element("world.powder", in: app)
        tap("tray.arrow", "the powder tray's arrow", in: app)
        if let water = find("material.Water", in: app, scrollingWithin: trayArea(app)) {
            water.tap()
        }
        tap("tray.arrow", "the powder tray's arrow, to close it", in: app)
        guard isRunning(app) else { return }
        drag(across: world, from: CGVector(dx: 0.3, dy: 0.2), to: CGVector(dx: 0.7, dy: 0.25))
        stillRunning(app, after: "pouring water with the world's sound on")
        Thread.sleep(forTimeInterval: 3)
        stillRunning(app, after: "listening to water")

        tap("header.menu", "the menu", in: app)
        guard let toggle = find("switch.The world's own sound", in: app, kind: .switch, scrollingIn: panelScroll(in: app))
        else {
            XCTFail("the switch for the world's own sound was not in the Lab panel")
            report(app, "No soundscape switch")
            return
        }
        picture(app, "44 The world's own sound")
        toggle.tap()
        stillRunning(app, after: "switching the world's sound off")
        toggle.tap()
        stillRunning(app, after: "switching the world's sound on again")
        tap("sheet.close", "the Lab panel's close button", in: app)
        guard isRunning(app) else { return }
        drag(across: world, from: CGVector(dx: 0.2, dy: 0.3), to: CGVector(dx: 0.8, dy: 0.3))
        Thread.sleep(forTimeInterval: 3)
        stillRunning(app, after: "listening to the world again")
    }

    // MARK: - Starting

    private func launch() -> XCUIApplication {
        // Carries on after a failure, so one missing button does not cost every picture after it. A crash stops it
        // anyway: every step after one checks the app is still there.
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--fresh-start"]
        app.launch()
        // Every run starts as if the app were newly installed, so the introduction is the first thing on screen.
        let skip = app.descendants(matching: .any)["welcome.skip"].firstMatch
        if skip.waitForExistence(timeout: 60) {
            picture(app, "00 The introduction")
            skip.tap()
        }
        XCTAssertTrue(
            app.buttons["header.play"].waitForExistence(timeout: 30),
            "the app did not open, or opened to something without a play button"
        )
        return app
    }

    // MARK: - Checking it is still there

    private func isRunning(_ app: XCUIApplication) -> Bool {
        app.state == .runningForeground
    }

    private func stillRunning(_ app: XCUIApplication, after what: String) {
        XCTAssertTrue(isRunning(app), "the app closed by itself after \(what)")
    }

    // MARK: - Finding things and touching them

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Taps the thing with a name, having waited for it, and checks the app survived.
    private func tap(_ id: String, _ what: String, in app: XCUIApplication) {
        guard isRunning(app) else { return }
        let target = element(id, in: app)
        guard target.waitForExistence(timeout: 10) else {
            XCTFail("could not find \(what)")
            report(app, "Could not find \(what)")
            return
        }
        target.tap()
        stillRunning(app, after: "tapping \(what)")
    }

    /// Waits for something to exist and become available to press, for anything the app only offers once it has been
    /// running a while.
    ///
    /// - Returns: whether it became available. Fails the walk, having said what state it was in, if it did not.
    private func waitUntilEnabled(_ id: String, _ what: String, in app: XCUIApplication, seconds: Int) -> Bool {
        guard isRunning(app) else { return false }
        let target = element(id, in: app)
        for _ in 0 ..< seconds * 2 {
            if target.exists, target.isEnabled, target.isHittable { return true }
            Thread.sleep(forTimeInterval: 0.5)
            guard isRunning(app) else { return false }
        }
        XCTFail(
            "\(what) never became available: "
                + "exists \(target.exists), can be pressed \(target.exists ? target.isEnabled : false)"
        )
        report(app, "\(what) never became available")
        return false
    }

    /// Finds something that may be scrolled out of sight, dragging upwards within an area until it can be touched.
    private func find(
        _ id: String,
        in app: XCUIApplication,
        kind: XCUIElement.ElementType = .any,
        scrollingWithin area: (from: CGVector, to: CGVector)
    ) -> XCUIElement? {
        guard isRunning(app) else { return nil }
        let target = app.descendants(matching: kind)[id].firstMatch
        for _ in 0 ..< 10 {
            if target.exists, target.isHittable { return target }
            let from = app.coordinate(withNormalizedOffset: area.from)
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: area.to))
            guard isRunning(app) else { return nil }
        }
        return target.exists && target.isHittable ? target : nil
    }

    /// Where to drag to scroll the open tray: near the bottom of the screen, upwards a little.
    ///
    /// Still a place rather than an element, because a tray holds several scrolling strips — the materials run
    /// sideways, the tools run down — and a drag at the bottom of the screen reaches whichever is under it. Good enough
    /// for the buttons, which sit in the part that is always on screen. Not good enough for a slider further down: see
    /// `trayScroll`.
    private func trayArea(_ app: XCUIApplication) -> (from: CGVector, to: CGVector) {
        (CGVector(dx: 0.5, dy: 0.86), CGVector(dx: 0.5, dy: 0.72))
    }

    /// The scrolling part of an open tray.
    ///
    /// The tallest scrolling area in the lower half of the screen. The same reasoning as `panelScroll`, and it exists
    /// for the same reason that one had to be rewritten: dragging at a fixed fraction of the screen catches whatever
    /// happens to be under that fraction, which for the field tray was a strip of chips rather than the tray's own
    /// contents — so a slider a few hundred pixels down was reported missing when it was merely below the fold.
    private func trayScroll(in app: XCUIApplication) -> XCUIElement? {
        let window = app.windows.element(boundBy: 0)
        guard window.exists else { return nil }
        let middle = window.frame.midY
        var best: XCUIElement?
        var tallest: CGFloat = 0
        let scrolls = app.scrollViews
        for index in 0 ..< scrolls.count {
            let scroll = scrolls.element(boundBy: index)
            guard scroll.exists else { continue }
            let frame = scroll.frame
            guard frame.midY > middle, frame.height > tallest else { continue }
            tallest = frame.height
            best = scroll
        }
        return best
    }

    /// Whether an element can really be pressed.
    ///
    /// `isHittable` is not enough on its own, which cost two failures: a menu item hanging off the right-hand edge of a
    /// phone reports itself hittable and then has no usable point to press, and asking anyway is an error rather than a
    /// miss. So the frame has to sit inside the window as well.
    ///
    /// ## Why the question is asked inside an expected failure
    ///
    /// Because for a menu item a tablet has laid out behind the rest of its menu, asking whether it can be pressed does
    /// not answer "no" — it fails the walk outright, "activation point invalid", which is the testing framework's own
    /// fault and not the app's. Both the recipe menu and a layer's menu cost a failed walk that way. Asked inside a
    /// non-strict expected failure, that outburst is kept to itself and the answer is simply no.
    private func canReallyTap(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.element(boundBy: 0)
        guard window.exists else { return false }
        let frame = element.frame
        guard frame.width > 1, frame.height > 1, window.frame.insetBy(dx: -1, dy: -1).contains(frame) else {
            return false
        }
        var hittable = false
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("asking whether a menu item can be pressed sometimes fails instead of answering", options: options) {
            hittable = element.isHittable
        }
        return hittable
    }

    /// The scrolling part of whichever panel is open, found by the panel's own title.
    ///
    /// Not a place on the screen: on a tablet a panel is a small card in the middle of it, so dragging at a fraction of
    /// the screen's height scrolled the tray underneath instead and the panel never moved. This finds the panel itself.
    ///
    /// ## Why it is not a point any more
    ///
    /// It used to take the point twenty pixels below the title and look for the scrolling area containing it. That
    /// point landed in the gap between the panel's heading and the top of its contents — three pixels above, as it
    /// happens — so nothing contained it, nothing scrolled, and every check that needed to reach further down the
    /// panel reported that the control "was not in the panel" when it was simply below the fold. On a phone the wind
    /// slider was fifteen hundred pixels down a nine-hundred-pixel screen.
    ///
    /// So: the tallest scrolling area that begins at or below the heading. A panel's contents are the tallest thing on
    /// screen by a wide margin — four hundred pixels against the tray's thirty — and "below the heading" is what
    /// distinguishes it from the world's own scrolling parts above.
    private func panelScroll(in app: XCUIApplication) -> XCUIElement? {
        let title = element("sheet.title", in: app)
        guard title.waitForExistence(timeout: 10) else { return nil }
        let top = title.frame.minY
        var best: XCUIElement?
        var tallest: CGFloat = 0
        let scrolls = app.scrollViews
        for index in 0 ..< scrolls.count {
            let scroll = scrolls.element(boundBy: index)
            guard scroll.exists else { continue }
            let frame = scroll.frame
            guard frame.minY >= top - 1, frame.height > tallest else { continue }
            tallest = frame.height
            best = scroll
        }
        return best
    }

    /// Finds something inside a scrolling area, swiping up within that area until it can be touched.
    private func find(
        _ id: String,
        in app: XCUIApplication,
        kind: XCUIElement.ElementType = .any,
        scrollingIn scroll: XCUIElement?
    ) -> XCUIElement? {
        guard isRunning(app) else { return nil }
        let target = app.descendants(matching: kind)[id].firstMatch
        // Said out loud, because a nil here used to look exactly like "the control does not exist" — and the control
        // did exist, a thousand pixels below the fold, with nothing scrolling to reach it.
        if scroll == nil {
            report(app, "Could not find anything to scroll, so nothing could be scrolled to reach \(id)")
        }
        for _ in 0 ..< 40 {
            if target.exists, target.isHittable { return target }
            guard let scroll, scroll.exists else { break }
            step(scroll, down: true)
            guard isRunning(app) else { return nil }
        }
        // And back the other way, in case it went past. A panel can be scrolled further than the thing being looked
        // for, and then it is above the fold rather than below it — equally invisible, for the opposite reason.
        for _ in 0 ..< 40 {
            if target.exists, target.isHittable { return target }
            guard let scroll, scroll.exists else { break }
            step(scroll, down: false)
            guard isRunning(app) else { return nil }
        }
        return target.exists && target.isHittable ? target : nil
    }

    /// Moves a scrolling area on by about half of itself, and no further.
    ///
    /// ## Why not a swipe
    ///
    /// A swipe is a flick, and a flick carries on after the finger has gone. In the field tray — three hundred points
    /// tall showing a list three and a half thousand points long — each flick threw the list about a thousand points,
    /// so the slider being looked for went from below the window to above it between two looks and was never seen in
    /// it. The walk then reported that the slider "was not in the tray" when it had flown straight past. A slow drag
    /// that holds still at the end stops dead where the finger stops, so every part of the list passes through the
    /// window at least once.
    private func step(_ scroll: XCUIElement, down: Bool) {
        // In the right-hand margin, where there are no sliders: a drag that begins on a slider moves the slider.
        let low = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.8))
        let high = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.3))
        let (from, to) = down ? (low, high) : (high, low)
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 400, thenHoldForDuration: 0.3)
    }

    private func drag(across element: XCUIElement, from start: CGVector, to end: CGVector) {
        let from = element.coordinate(withNormalizedOffset: start)
        from.press(forDuration: 0.1, thenDragTo: element.coordinate(withNormalizedOffset: end))
    }

    // MARK: - Pictures

    /// A picture, and everything on screen written out, for when something could not be found.
    ///
    /// The written-out version matters more than the picture: it lands in the check's own log, which can be read from
    /// anywhere, while the pictures can only be fetched by whoever can reach the run's files.
    private func report(_ app: XCUIApplication, _ name: String) {
        picture(app, name)
        guard isRunning(app) else { return }
        let tree = app.debugDescription
        print("--- What was on screen when \(name) ---\n\(tree)\n--- end ---")
        let written = XCTAttachment(string: tree)
        written.name = name
        written.lifetime = .keepAlways
        add(written)
    }

    private func picture(_ app: XCUIApplication, _ name: String) {
        guard isRunning(app) else { return }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Fails if a world is blank: all one colour where it should be drawn. A Metal view that has stopped drawing, or
    /// never started, looks exactly like this — and nothing else in the checks can see it.
    private func expectDrawn(_ world: XCUIElement, _ what: String, in app: XCUIApplication) {
        guard isRunning(app) else { return }
        XCTAssertTrue(world.waitForExistence(timeout: 10), "could not find \(what)")
        // A moment for the first frames.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "a moment")], timeout: 1.5)
        let colours = distinctColours(in: world.frame, of: app.screenshot().image)
        XCTAssertGreaterThan(colours, 2, "\(what) is blank: only \(colours) colour(s) where it should be drawn")
    }

    /// How many clearly different colours a grid of points across an area of a picture lands on.
    private func distinctColours(in frame: CGRect, of image: UIImage) -> Int {
        guard let picture = image.cgImage, image.size.width > 0, frame.width > 0, frame.height > 0 else { return 0 }
        let width = picture.width
        let height = picture.height
        let scale = CGFloat(width) / image.size.width
        var seen = Set<UInt32>()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            let steps = 32
            for i in 0 ..< steps {
                for j in 0 ..< steps {
                    let x = Int((frame.minX + frame.width * (CGFloat(i) + 0.5) / CGFloat(steps)) * scale)
                    let y = Int((frame.minY + frame.height * (CGFloat(j) + 0.5) / CGFloat(steps)) * scale)
                    guard x >= 0, x < width, y >= 0, y < height else { continue }
                    let at = (y * width + x) * 4
                    // Rounded to sixteen levels a channel, so a grain's speckle is not counted as many colours.
                    let key = UInt32(raw[at] >> 4) << 8 | UInt32(raw[at + 1] >> 4) << 4 | UInt32(raw[at + 2] >> 4)
                    seen.insert(key)
                }
            }
        }
        return seen.count
    }
}
