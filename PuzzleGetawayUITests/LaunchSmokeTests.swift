import XCTest

/// Shell flow tests and screenshots. Launch arguments (see AppModel): `-PGResetSave` starts clean,
/// `-PGDemoOnly` plays the demo mode regardless of which real modes are bundled, `-PGShowMoves` shows the
/// move counter, `-PGNoSplash` skips the brief launch splash.
final class LaunchSmokeTests: XCTestCase {
    private let freshArgs = ["-PGResetSave", "-PGDemoOnly", "-PGShowMoves", "-PGNoSplash"]
    private let resumeArgs = ["-PGDemoOnly", "-PGShowMoves", "-PGNoSplash"]

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

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += args
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func moveCounterValue(_ app: XCUIApplication) -> String? {
        element(app, "moveCounter").value as? String
    }

    private func dismissTipIfShown(_ app: XCUIApplication) {
        let tip = app.buttons["tipDismiss"]
        if tip.waitForExistence(timeout: 3) { tip.tap() }
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
    }

    // MARK: Tests

    /// Quick Play, one move, kill the app, relaunch, Continue restores the exact board, then Settings.
    func testQuickPlayContinueAndSettings() {
        var app = launch(freshArgs)

        let quickPlay = app.buttons["quickPlayButton"]
        XCTAssertTrue(quickPlay.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["continueButton"].exists)
        XCTAssertTrue(app.staticTexts["offlineNote"].exists || element(app, "offlineNote").exists)
        attach(app, name: "01-main-menu")

        quickPlay.tap()
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["restartButton"].exists)
        XCTAssertTrue(app.buttons["hintButton"].exists)
        XCTAssertTrue(app.buttons["pauseButton"].exists)
        attach(app, name: "02-game-with-tip")
        dismissTipIfShown(app)

        XCTAssertEqual(moveCounterValue(app), "0")
        let add3 = app.buttons["demoAdd3"]
        XCTAssertTrue(add3.waitForExistence(timeout: 5))
        add3.tap()
        XCTAssertEqual(moveCounterValue(app), "1")
        attach(app, name: "03-game-after-move")

        // Leave the foreground (autosave), then kill the app outright.
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.terminate()

        app = launch(resumeArgs)
        let continueButton = app.buttons["continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 20))
        continueButton.tap()
        XCTAssertTrue(app.buttons["undoButton"].waitForExistence(timeout: 10))
        XCTAssertEqual(moveCounterValue(app), "1", "Continue should restore the exact in-progress board")
        attach(app, name: "04-game-restored")

        // Pause menu -> Settings
        app.buttons["pauseButton"].tap()
        let pauseSettings = app.buttons["pauseSettings"]
        XCTAssertTrue(pauseSettings.waitForExistence(timeout: 5))
        attach(app, name: "05-pause")
        pauseSettings.tap()
        XCTAssertTrue(element(app, "toggleHaptics").waitForExistence(timeout: 5))
        attach(app, name: "06-settings")
    }

    /// Walks the map, intro card, level select, restoration, scrapbook, Relax, Daily and Backup screens.
    func testShellTourScreenshots() {
        let app = launch(freshArgs)
        let mapButton = app.buttons["mapButton"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 20))

        mapButton.tap()
        let stop = app.buttons["destination-d1"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        attach(app, name: "10-map")

        stop.tap()
        let intro = app.buttons["introContinue"]
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        attach(app, name: "11-destination-intro")
        intro.tap()

        let restoration = app.buttons["restorationLink"]
        XCTAssertTrue(restoration.waitForExistence(timeout: 10))
        attach(app, name: "12-level-select")

        restoration.tap()
        XCTAssertTrue(element(app, "restorationScene").waitForExistence(timeout: 10))
        attach(app, name: "13-restoration")

        goBack(app) // level select
        goBack(app) // map
        goBack(app) // main menu

        let scrapbook = app.buttons["scrapbookButton"]
        XCTAssertTrue(scrapbook.waitForExistence(timeout: 5))
        scrapbook.tap()
        XCTAssertTrue(element(app, "scrapbookCount").waitForExistence(timeout: 10))
        attach(app, name: "14-scrapbook")
        let firstPiece = app.buttons["scrap-d1-stage1"]
        if firstPiece.waitForExistence(timeout: 3) {
            firstPiece.tap()
            XCTAssertTrue(app.buttons["scrapbookDone"].waitForExistence(timeout: 5))
            attach(app, name: "15-scrapbook-detail")
            app.buttons["scrapbookDone"].tap()
        }
        goBack(app)

        app.buttons["relaxButton"].tap()
        XCTAssertTrue(app.navigationBars["Relax"].waitForExistence(timeout: 5))
        attach(app, name: "16-relax")
        goBack(app)

        app.buttons["dailyButton"].tap()
        XCTAssertTrue(element(app, "journeysTaken").waitForExistence(timeout: 5))
        attach(app, name: "17-daily")
        goBack(app)

        app.buttons["backupButton"].tap()
        XCTAssertTrue(element(app, "savedStatus").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["exportProgress"].exists)
        XCTAssertTrue(app.buttons["importProgress"].exists)
        attach(app, name: "18-backup")
    }

    /// Solves the demo level, checks the completion card and the restoration unlock, then plays the next level.
    func testLevelCompleteRestorationAndNextLevel() {
        let app = launch(freshArgs)
        let quickPlay = app.buttons["quickPlayButton"]
        XCTAssertTrue(quickPlay.waitForExistence(timeout: 20))
        quickPlay.tap()
        XCTAssertTrue(app.buttons["undoButton"].waitForExistence(timeout: 10))
        dismissTipIfShown(app)

        let add3 = app.buttons["demoAdd3"]
        XCTAssertTrue(add3.waitForExistence(timeout: 5))
        add3.tap()
        add3.tap()
        app.buttons["demoAdd1"].tap()

        XCTAssertTrue(element(app, "levelCompleteTitle").waitForExistence(timeout: 8), "Level Complete should appear about a second after solving")
        let next = app.buttons["nextLevelButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 3), "Next level button")
        XCTAssertTrue(app.buttons["replayButton"].exists)
        sleep(1)
        attach(app, name: "20-level-complete")

        // Three stars on the first level cross the first restoration threshold.
        let seeRestoration = app.buttons["seeRestoration"]
        XCTAssertTrue(seeRestoration.waitForExistence(timeout: 3), "Restoration unlocked banner expected")
        seeRestoration.tap()
        XCTAssertTrue(element(app, "restorationScene").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "stageUnlockedBanner").waitForExistence(timeout: 5))
        sleep(1)
        attach(app, name: "21-restoration-unlocked")

        // Back to the level list: level 2 is open now.
        goBack(app)
        let second = app.buttons["level-demo-demo-02"]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        second.tap()
        XCTAssertTrue(app.buttons["undoButton"].waitForExistence(timeout: 10))
        XCTAssertEqual(moveCounterValue(app), "0")
    }

    /// iPad landscape: board on the left, info panel on the right. Skipped on iPhone.
    func testIPadLandscapeScreenshots() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(freshArgs)
        let quickPlay = app.buttons["quickPlayButton"]
        XCTAssertTrue(quickPlay.waitForExistence(timeout: 20))
        attach(app, name: "30-ipad-landscape-menu")

        app.buttons["mapButton"].tap()
        XCTAssertTrue(app.buttons["destination-d1"].waitForExistence(timeout: 10))
        attach(app, name: "31-ipad-landscape-map")
        goBack(app)

        quickPlay.tap()
        XCTAssertTrue(app.buttons["undoButton"].waitForExistence(timeout: 10))
        dismissTipIfShown(app)
        attach(app, name: "32-ipad-landscape-game")
        XCUIDevice.shared.orientation = .portrait
    }
}
