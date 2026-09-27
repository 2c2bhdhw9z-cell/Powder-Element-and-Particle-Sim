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
    private func trayArea(_ app: XCUIApplication) -> (from: CGVector, to: CGVector) {
        (CGVector(dx: 0.5, dy: 0.86), CGVector(dx: 0.5, dy: 0.72))
    }

    /// The scrolling part of whichever panel is open, found by the panel's own title.
    ///
    /// Not a place on the screen: on a tablet a panel is a small card in the middle of it, so dragging at a fraction of
    /// the screen's height scrolled the tray underneath instead and the panel never moved. This finds the panel itself.
    private func panelScroll(in app: XCUIApplication) -> XCUIElement? {
        let title = element("sheet.title", in: app)
        guard title.waitForExistence(timeout: 10) else { return nil }
        let inside = CGPoint(x: title.frame.midX, y: title.frame.maxY + 20)
        let scrolls = app.scrollViews
        for index in 0 ..< scrolls.count {
            let scroll = scrolls.element(boundBy: index)
            guard scroll.exists, scroll.frame.contains(inside) else { continue }
            return scroll
        }
        return nil
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
        for _ in 0 ..< 12 {
            if target.exists, target.isHittable { return target }
            guard let scroll, scroll.exists else { break }
            scroll.swipeUp()
            guard isRunning(app) else { return nil }
        }
        return target.exists && target.isHittable ? target : nil
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
