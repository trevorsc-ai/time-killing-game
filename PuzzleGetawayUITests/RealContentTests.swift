import XCTest

/// UI tests against the REAL bundled content (no -PGDemoOnly). They rely on DEBUG-only launch hooks:
/// `-PGUITestHooks` (an almost invisible "Solve step" button that plays the next stored-solution move) and
/// `-PGOpenLevel <id>` (open a level directly). Screenshots are kept as attachments for the CI artifact.
final class RealContentTests: XCTestCase {
    private let base = ["-PGResetSave", "-PGNoSplash", "-PGShowMoves", "-PGUITestHooks"]

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += base + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func dismissTips(_ app: XCUIApplication) {
        for _ in 0..<3 {
            let tip = app.buttons["tipDismiss"]
            if tip.waitForExistence(timeout: 2) { tip.tap() } else { break }
        }
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
    }

    /// Plays stored-solution moves until the Level Complete card shows.
    private func solve(_ app: XCUIApplication, maxMoves: Int = 120) {
        let step = app.buttons["solveStep"]
        XCTAssertTrue(step.waitForExistence(timeout: 10), "Solve step hook missing (Debug build with -PGUITestHooks)")
        let complete = element(app, "levelCompleteTitle")
        for _ in 0..<maxMoves {
            if complete.exists { break }
            step.tap()
            usleep(150_000)
        }
        XCTAssertTrue(complete.waitForExistence(timeout: 10), "Level Complete should appear after the stored solution is played")
    }

    // MARK: Tests

    /// Main menu, map, level select, then plays d1 level 1 (Liquid) with the stored solution to Level Complete.
    func testPlayFirstRealLevelToCompletion() {
        let app = launch()
        let mapButton = app.buttons["mapButton"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 20))
        attach(app, name: "r01-main-menu")

        mapButton.tap()
        let stop = app.buttons["destination-d1"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        attach(app, name: "r02-map")
        stop.tap()
        let intro = app.buttons["introContinue"]
        if intro.waitForExistence(timeout: 5) { intro.tap() }

        let first = app.buttons["level-d1-liquid-01"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        attach(app, name: "r03-level-select-d1")
        first.tap()

        XCTAssertTrue(app.buttons["undoButton"].waitForExistence(timeout: 10))
        dismissTips(app)
        XCTAssertEqual(element(app, "moveCounter").value as? String, "0")
        solve(app)
        sleep(1)
        attach(app, name: "r04-level-complete")

        let seeRestoration = app.buttons["seeRestoration"]
        if seeRestoration.waitForExistence(timeout: 3) {
            seeRestoration.tap()
            XCTAssertTrue(element(app, "restorationScene").waitForExistence(timeout: 10))
            sleep(1)
            attach(app, name: "r05-restoration")
        }
    }

    /// One screenshot of each mode's board, opened directly. One test per board keeps each well inside the per-test
    /// time allowance on the slower iPad simulator.
    private func checkBoard(_ id: String) {
        let app = launch(["-PGOpenLevel", id])
        XCTAssertTrue(app.buttons["undoButton"].waitForExistence(timeout: 20), "\(id) should open")
        attach(app, name: "b-\(id)-with-tip")
        dismissTips(app)
        sleep(1)
        attach(app, name: "b-\(id)")
    }

    func testBoardLiquid() { checkBoard("d1-liquid-01") }
    func testBoardPixel() { checkBoard("d1-pixel-02") }
    func testBoardBolt() { checkBoard("d1-bolt-16") }
    func testBoardParking() { checkBoard("d3-parking-01") }
    func testBoardPipe() { checkBoard("d4-pipe-01") }

    /// A first real move in a Pixel level shows progress in the HUD and the move counter ticks.
    func testPixelStepUpdatesProgress() {
        let app = launch(["-PGOpenLevel", "d1-pixel-02"])
        XCTAssertTrue(app.buttons["undoButton"].waitForExistence(timeout: 20))
        dismissTips(app)
        let bar = element(app, "progressBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertEqual(bar.value as? String, "0 percent")
        app.buttons["solveStep"].tap()
        sleep(2)
        XCTAssertEqual(element(app, "moveCounter").value as? String, "1")
        XCTAssertNotEqual(bar.value as? String, "0 percent")
    }

    /// Relax, Daily, Settings, Backup and Scrapbook with real content.
    func testRealContentTour() {
        let app = launch()
        XCTAssertTrue(app.buttons["relaxButton"].waitForExistence(timeout: 20))

        app.buttons["scrapbookButton"].tap()
        XCTAssertTrue(element(app, "scrapbookCount").waitForExistence(timeout: 10))
        attach(app, name: "r10-scrapbook")
        goBack(app)

        app.buttons["relaxButton"].tap()
        XCTAssertTrue(app.navigationBars["Relax"].waitForExistence(timeout: 5))
        attach(app, name: "r11-relax")
        goBack(app)

        app.buttons["dailyButton"].tap()
        XCTAssertTrue(element(app, "journeysTaken").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["startDaily"].exists, "Daily pool should have a playable puzzle for today")
        attach(app, name: "r12-daily")
        app.buttons["startDaily"].tap()
        XCTAssertTrue(app.buttons["undoButton"].waitForExistence(timeout: 15))
        dismissTips(app)
        attach(app, name: "r13-daily-board")
        app.buttons["backButton"].tap() // no moves made, so it leaves without a prompt
        XCTAssertTrue(element(app, "journeysTaken").waitForExistence(timeout: 5))
        goBack(app)

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(element(app, "toggleHaptics").waitForExistence(timeout: 5))
        attach(app, name: "r14-settings")
        goBack(app)

        app.buttons["backupButton"].tap()
        XCTAssertTrue(element(app, "savedStatus").waitForExistence(timeout: 5))
        attach(app, name: "r15-backup")
    }

    /// iPad landscape: map and a board with the side panel.
    func testIPadLandscapeRealContent() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        var app = launch()
        XCTAssertTrue(app.buttons["mapButton"].waitForExistence(timeout: 20))
        app.buttons["mapButton"].tap()
        XCTAssertTrue(app.buttons["destination-d1"].waitForExistence(timeout: 10))
        attach(app, name: "i01-ipad-landscape-map")
        app.terminate()

        app = launch(["-PGOpenLevel", "d1-pixel-02"])
        XCTAssertTrue(app.buttons["undoButton"].waitForExistence(timeout: 20))
        dismissTips(app)
        sleep(1)
        attach(app, name: "i02-ipad-landscape-board-pixel")
        app.terminate()

        app = launch(["-PGOpenLevel", "d1-liquid-01"])
        XCTAssertTrue(app.buttons["undoButton"].waitForExistence(timeout: 20))
        dismissTips(app)
        sleep(1)
        attach(app, name: "i03-ipad-landscape-board-liquid")
    }
}
