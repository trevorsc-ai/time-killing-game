import XCTest

final class LaunchSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testQuickPlayLaunchSmoke() {
        let app = XCUIApplication()
        app.launchArguments += ["-PGResetSave"]
        app.launch()

        let quickPlay = app.buttons["quickPlayButton"]
        XCTAssertTrue(quickPlay.waitForExistence(timeout: 15))
        attach(app, name: "01-main-menu")

        quickPlay.tap()
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["restartButton"].exists)
        XCTAssertTrue(app.buttons["hintButton"].exists)
        attach(app, name: "02-game-screen")
    }
}
