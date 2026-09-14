import XCTest

/// Launch-and-look tests. They drive the real app against the real local API
/// and save screenshots as attachments for design review.
final class BarryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(unreachableServer: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        if unreachableServer {
            // A port nothing listens on — deterministic, fast-failing "server down".
            app.launchArguments += ["-barryBaseURL", "http://127.0.0.1:1"]
        }
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSessionListLoads() throws {
        let app = launch()
        // Sessions come from the live API; give the first load a moment.
        let list = app.collectionViews["sessionsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), "session list should appear")
        let firstCell = list.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "expected at least one session row")
        attach(app, name: "sessions")
    }

    func testOpensChatAndShowsMessages() throws {
        let app = launch()
        let list = app.collectionViews["sessionsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let firstCell = list.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10))
        firstCell.tap()
        // SwiftUI can expose a multiline TextField (axis: .vertical) as
        // either a TextField or a TextView in the accessibility tree
        // depending on content/layout state, so match on the identifier
        // across any element type rather than assuming XCUIElementTypeTextField.
        let input = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "messageInput"))
            .firstMatch
        let found = input.waitForExistence(timeout: 15)
        if !found {
            attach(app, name: "chat-failure")
            XCTFail("chat input should appear. Hierarchy:\n\(app.debugDescription)")
        }
        // History should render something within a few seconds.
        sleep(2)
        attach(app, name: "chat")
    }

    /// Verifies the compose sheet wires up (repo picker populates from the
    /// real API, Start enables once a prompt is typed) WITHOUT submitting —
    /// this app talks to a live, shared Barry instance, and starting a real
    /// session as a side effect of an automated UI test would spawn a live
    /// agent run against a real repo. That's the wrong side effect for a test
    /// to have.
    func testNewSessionSheetPopulatesFromRealAPI() throws {
        let app = launch()
        app.buttons["newSessionButton"].tap()
        let prompt = app.textViews["newSessionPrompt"].firstMatch
        let promptExists = prompt.waitForExistence(timeout: 10)
        if !promptExists {
            attach(app, name: "new-session-failure")
        }
        XCTAssertTrue(promptExists, "new session form should appear")
        // Repo picker should have loaded the real repo list within a few seconds.
        let repoRow = app.staticTexts["Barry"]
        XCTAssertTrue(repoRow.waitForExistence(timeout: 10), "repo picker should list the real 'Barry' repo")
        prompt.tap()
        prompt.typeText("test prompt — not submitted")
        let start = app.buttons["startSessionButton"]
        XCTAssertTrue(start.exists)
        XCTAssertTrue(start.isEnabled, "Start should enable once repo + prompt are set")
        attach(app, name: "new-session")
        app.buttons["Cancel"].tap()
    }

    /// Confirms the app tells the user something useful when it can't reach
    /// Barry at all, instead of hanging or showing a blank list. This is the
    /// "what would I see if this were completely broken" check for the
    /// happy-path session list test above.
    func testShowsErrorStateWhenServerUnreachable() throws {
        let app = launch(unreachableServer: true)
        let retryButton = app.buttons["Retry"]
        let found = retryButton.waitForExistence(timeout: 10)
        if !found {
            attach(app, name: "unreachable-server-failure")
        }
        XCTAssertTrue(found, "should show a recoverable error state, not hang or show an empty list")
        XCTAssertFalse(app.collectionViews["sessionsList"].exists, "should not show the list UI while genuinely disconnected")
        attach(app, name: "unreachable-server")
    }

    func testSettingsOpensAndTestsConnection() throws {
        let app = launch()
        app.buttons["settingsButton"].tap()
        let field = app.textFields["serverURLField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["Test connection"].tap()
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.waitForExistence(timeout: 10), "health check should pass against local server")
        attach(app, name: "settings")
    }
}
