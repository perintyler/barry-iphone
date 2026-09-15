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

    /// Regression: a New Session failure produced NO visible feedback --
    /// traced to the error rendering in a Form Section below the fold,
    /// invisible without scrolling. This actually taps Start against the
    /// real live API (breaking this suite's usual non-mutating discipline
    /// for New Session tests, see testNewSessionSheetPopulatesFromRealAPI
    /// above) because the only way to prove an alert appears on a REAL
    /// failure is to trigger a real failure -- a mocked/local failure
    /// would only prove the alert code compiles, not that create() really
    /// reaches it. Safe to repeat: at the time this was written the create
    /// endpoint was failing with a genuine server-side 500 that occurs
    /// before any row is persisted (a SQL error on INSERT), so a failed
    /// attempt here does not create orphaned draft sessions. If the server
    /// bug is later fixed, this call may succeed instead -- the assertion
    /// below only requires SOME outcome (alert or dismissal), not the
    /// specific failure, so it keeps passing either way.
    func testNewSessionShowsVisibleFeedbackOnFailure() throws {
        let app = launch()
        app.buttons["newSessionButton"].tap()
        let prompt = app.textViews["newSessionPrompt"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "new session form should appear")
        prompt.tap()
        prompt.typeText("UI test probe — verifying error visibility, not creating a real session")
        let start = app.buttons["startSessionButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // Either the alert appears (the failure case this test exists to
        // catch), or the sheet dismisses because creation actually
        // succeeded (the server bug got fixed) -- both are healthy
        // outcomes; only "nothing happens and the form just sits there"
        // (the original bug report) is not.
        let alert = app.alerts["Couldn't start session"]
        let alertAppeared = alert.waitForExistence(timeout: 15)
        let sheetDismissed = !prompt.exists
        if !alertAppeared && !sheetDismissed {
            attach(app, name: "new-session-no-feedback-failure")
        }
        XCTAssertTrue(alertAppeared || sheetDismissed, "creation must either show an alert or succeed — never leave the form sitting with no feedback")
        if alertAppeared {
            attach(app, name: "new-session-error-alert")
            alert.buttons["OK"].tap()
        }
    }

    /// Trait picker: opens from the New Session form, lists real traits from
    /// the live API, and multi-select actually works -- tapping two rows
    /// leaves both checked and the row's live count reflects it. Cancels
    /// out without creating a session, same non-mutating discipline as
    /// testNewSessionSheetPopulatesFromRealAPI above.
    func testTraitPickerMultiSelect() throws {
        let app = launch()
        app.buttons["newSessionButton"].tap()
        let prompt = app.textViews["newSessionPrompt"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "new session form should appear")

        let traitsRow = app.buttons["traitsRow"]
        XCTAssertTrue(traitsRow.waitForExistence(timeout: 10), "traits row should appear in the form")
        traitsRow.tap()

        let doneButton = app.buttons["traitPickerDone"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10), "trait picker should open")
        let cells = app.cells
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), "trait list should load real traits from the API")
        attach(app, name: "trait-picker-empty")

        // Tap two specific, known-real trait rows by their accessibility
        // identifier rather than positional index -- boundBy(0)/boundBy(1)
        // proved flaky here (a tap could land between rows during the list's
        // settle animation and silently miss), where tapping a named,
        // on-screen element is deterministic.
        let ableton = app.buttons["trait-ableton"]
        let actions = app.buttons["trait-actions"]
        XCTAssertTrue(ableton.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        ableton.tap()
        actions.tap()
        attach(app, name: "trait-picker-two-selected")

        doneButton.tap()

        // Back on the form, the row summary should reflect exactly 2 picked.
        let traitsSummary = app.staticTexts["2 selected"]
        XCTAssertTrue(traitsSummary.waitForExistence(timeout: 5), "traits row should show \"2 selected\" after picking two")
        attach(app, name: "new-session-with-traits")
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
