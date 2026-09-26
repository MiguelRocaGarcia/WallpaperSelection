import XCTest

/// End-to-end run against the simulator's Photos library, seeded with WallpaperSelectionTests/Fixtures
/// by scripts/seed-simulator.sh. Swipes through every candidate, then checks undo and the album grid.
final class SwipeFlowUITests: XCTestCase {
    /// Photos the simulator should offer. Food and receipts caught only by image classification also
    /// appear here, because classification can't run in the simulator (see VisionFilter). The simulator's
    /// other built-in sample photos are all horizontal.
    private let expectedInSimulator: Set<String> = [
        "basilica_tiny_people.jpg", "beach_path.jpg", "glass_building.jpg", "skyline_night.jpg",
        "storm_sunset.jpg", "towers.jpg", "trail.jpg", "waterfall_distant_people.jpg", "waterfall_forest.jpg",
        "dinner.jpg", "pizza.jpg", "receipt_crumpled.jpg",
        "IMG_0004.JPG", // the simulator's built-in portrait waterfall sample photo
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    func testSwipeThroughLibrary() throws {
        try runSwipeFlow(order: "newestFirst")
    }

    /// Random order must offer exactly the same photos, just shuffled.
    func testRandomOrderShowsSamePhotos() throws {
        let app = launch(order: "random")
        XCTAssertEqual(try swipeAll(app), expectedInSimulator)
    }

    /// Each launch reshuffles, so the first photo shouldn't be the same every time.
    /// With 13 candidates, four identical first cards by chance is ~0.05%.
    func testRandomOrderReshufflesOnLaunch() throws {
        var firstCards: [String] = []
        for _ in 0..<4 {
            let app = launch(order: "random")
            let card = app.descendants(matching: .any)["photoCard"]
            XCTAssertTrue(card.waitForExistence(timeout: 30))
            firstCards.append(try waitForFilename(of: card))
            app.terminate()
        }
        print("FIRST CARDS: \(firstCards)")
        XCTAssertGreaterThan(Set(firstCards).count, 1, "Same first photo on every launch: \(firstCards)")
    }

    private func launch(order: String) -> XCUIApplication {
        let app = XCUIApplication()
        // Arguments land in UserDefaults' argument domain, overriding the stored setting.
        // A fresh store each run keeps earlier swipes from hiding photos.
        app.launchArguments += ["-filter.order", order, "-uiTestResetStore", "YES"]
        app.launch()
        allowPhotoAccessIfAsked()
        return app
    }

    private func swipeAll(_ app: XCUIApplication) throws -> Set<String> {
        let card = app.descendants(matching: .any)["photoCard"]
        var seen: Set<String> = []
        while card.waitForExistence(timeout: 30), seen.count < 40 {
            let name = try waitForFilename(of: card)
            seen.insert(name)
            app.buttons["rejectButton"].tap()
            waitUntil { !card.exists || (card.value as? String) != name }
        }
        XCTAssertTrue(app.staticTexts["You've seen them all"].waitForExistence(timeout: 30))
        return seen
    }

    private func runSwipeFlow(order: String) throws {
        let app = launch(order: order)

        let card = app.descendants(matching: .any)["photoCard"]
        var seen: [String] = []

        while card.waitForExistence(timeout: 30), seen.count < 40 {
            let name = try waitForFilename(of: card)
            seen.append(name)
            if seen.count <= 2 { attach(app, "card-\(seen.count)-\(name)") }

            // Exercise both the gestures and the buttons.
            switch seen.count {
            case 1: card.swipeRight()
            case 2: app.buttons["acceptButton"].tap()
            case 3: card.swipeLeft()
            default: app.buttons["rejectButton"].tap()
            }
            waitUntil { !card.exists || (card.value as? String) != name }
        }

        print("SEEN (\(seen.count)): \(seen.joined(separator: ", "))")
        XCTAssertTrue(app.staticTexts["You've seen them all"].waitForExistence(timeout: 30))
        attach(app, "all-done")
        XCTAssertEqual(Set(seen), expectedInSimulator)
        XCTAssertEqual(seen.count, expectedInSimulator.count, "A photo was shown twice")

        // Undo brings back the last skipped photo; skip it again.
        app.buttons["undoButton"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(try waitForFilename(of: card), seen.last)
        app.buttons["rejectButton"].tap()
        XCTAssertTrue(app.staticTexts["You've seen them all"].waitForExistence(timeout: 10))

        let stats = app.descendants(matching: .any)["stats"]
        XCTAssertTrue(stats.label.hasPrefix("2 added, \(seen.count - 2) skipped"), stats.label)

        // The album grid shows the two accepted photos.
        app.buttons["gridButton"].tap()
        XCTAssertTrue(app.navigationBars["Wallpapers (2)"].waitForExistence(timeout: 10))
        waitUntil(timeout: 3) { false }
        attach(app, "album-grid")

        // Remove one photo from the album via its full-screen preview.
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'thumbnail'")).firstMatch.tap()
        app.buttons["removeFromAlbumButton"].tap()
        app.buttons["Remove"].tap()
        XCTAssertTrue(app.navigationBars["Wallpapers (1)"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        // Settings opens and shows the same totals.
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        attach(app, "settings")
        app.buttons["Done"].tap()

        // Decisions survive a relaunch: nothing is offered again.
        app.terminate()
        app.launchArguments = ["-filter.order", order] // keep the store this time
        app.launch()
        XCTAssertTrue(app.staticTexts["You've seen them all"].waitForExistence(timeout: 30))
        XCTAssertFalse(card.exists)
        XCTAssertTrue(stats.label.hasPrefix("1 added, \(seen.count - 1) skipped"), stats.label)
    }

    // MARK: Helpers

    private func allowPhotoAccessIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow Full Access"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    private func waitForFilename(of card: XCUIElement) throws -> String {
        waitUntil { !((card.value as? String) ?? "").isEmpty }
        return try XCTUnwrap(card.value as? String)
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTWaiter().wait(for: [expectation], timeout: timeout)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
