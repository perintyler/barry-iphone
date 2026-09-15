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

    /// Opens a real session's diff view from the chat toolbar and confirms
    /// the mode toggle, stats bar, and file list (or a clean-tree empty
    /// state) all render against the real live API -- screenshotted for
    /// visual review.
    func testOpensDiffViewFromChat() throws {
        let app = launch()
        let list = app.collectionViews["sessionsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let firstCell = list.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10))
        firstCell.tap()

        let diffButton = app.buttons["diffViewButton"]
        XCTAssertTrue(diffButton.waitForExistence(timeout: 10), "diff toolbar button should appear in chat")
        diffButton.tap()

        let uncommittedTab = app.buttons["diffModeUncommitted"]
        let found = uncommittedTab.waitForExistence(timeout: 10)
        if !found {
            attach(app, name: "diff-view-failure")
        }
        XCTAssertTrue(found, "diff view's mode toggle should appear")
        // Give the real fetch+parse a moment, then screenshot whatever
        // state resulted (file list or a clean/empty state -- both are
        // valid depending on this session's live repo state).
        sleep(2)
        attach(app, name: "diff-view")

        // Switch to branch mode and confirm the toggle actually changes
        // selection (branch tab becomes the active-styled one).
        let branchTab = app.buttons.matching(NSPredicate(format: "identifier == %@", "diffModeBranch")).firstMatch
        if branchTab.exists {
            branchTab.tap()
            sleep(2)
            attach(app, name: "diff-view-branch-mode")
        }
    }

    /// Opens a real session with a long run of consecutive same-tool calls
    /// sitting right at the tail of its message history
    /// (`1ISj9U_2gzA51sWM6497J`, "barry-ios-app-setup" -- a 20+ consecutive
    /// Bash run, the same shape of real data the approved mockup's cited
    /// 100-call example from `kPdNYibZbAuePBEEWtFEZ` shows, just picked so
    /// the run is visible without paging into older history: ChatStore
    /// only loads the most recent ~60 messages up front, and kPd's own big
    /// runs happen to sit earlier than that tail window) and exercises the
    /// actual grouped-tool-call card: it should render collapsed with a
    /// "Bash × N" label, tapping it should expand to reveal individual
    /// calls, and tapping "Show N more" should reveal the rest. Found by
    /// the session's real, stable name rather than list position, since
    /// ordering shifts as new sessions get created on this shared local
    /// instance.
    func testGroupedToolRunExpandsAndCollapses() throws {
        let app = launch()
        let list = app.collectionViews["sessionsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))

        // Matched across ANY element type (not just .staticTexts) --
        // SwiftUI's accessibility tree for List row text is inconsistent
        // about which trait it exposes, same lesson as the messageInput
        // and bookkeeping-entry lookups elsewhere in this file.
        let targetRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "barry-ios-app-setup"))
            .firstMatch
        var rowFound = targetRow.waitForExistence(timeout: 10)
        if !rowFound {
            for _ in 0..<4 where !rowFound {
                list.swipeUp()
                rowFound = targetRow.waitForExistence(timeout: 3)
            }
        }
        if !rowFound {
            attach(app, name: "grouped-tool-run-session-not-found")
        }
        XCTAssertTrue(rowFound, "expected to find the real long-Bash-run session in the list")
        targetRow.tap()

        let input = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "messageInput"))
            .firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15), "chat should open")
        // Let the initial page of history load and group.
        sleep(2)

        // This session's tail has more than one qualifying run (a real
        // consequence of real data -- see the messages fetched from the
        // live API), so more than one toolRunGroup card can be on screen.
        // The card IS the tap target: its own Button (not a separate
        // "header" identifier) carries "toolRunGroup", because collapsed
        // it's the only interactive content in its container and SwiftUI
        // coalesces the card into one accessibility element -- an
        // identifier on a non-interactive wrapper around it would be
        // unreachable. Pin to the first match and reuse that same element
        // reference throughout so expand/collapse taps land on one card.
        let group = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "toolRunGroup"))
            .firstMatch
        var groupFound = group.waitForExistence(timeout: 15)
        if !groupFound {
            // One retry: the live shared local API occasionally serves the
            // initial message page slowly under concurrent load from other
            // sessions/tests hitting it at once.
            sleep(2)
            groupFound = group.waitForExistence(timeout: 15)
        }
        if !groupFound {
            attach(app, name: "grouped-tool-run-missing")
        }
        XCTAssertTrue(groupFound, "this session's long tool run should render as a collapsed group, not one row per call")
        attach(app, name: "grouped-tool-run-collapsed")

        group.tap()

        let showMore = app.buttons["toolRunGroupShowMore"]
        let expandedFound = showMore.waitForExistence(timeout: 5)
        if !expandedFound {
            attach(app, name: "grouped-tool-run-expand-failure")
        }
        XCTAssertTrue(expandedFound, "expanding the group should reveal individual calls plus a \"Show N more\" control")
        attach(app, name: "grouped-tool-run-expanded")

        showMore.tap()
        sleep(1)
        attach(app, name: "grouped-tool-run-fully-expanded")

        // Collapsing again should hide the show-more control.
        group.tap()
        XCTAssertFalse(app.buttons["toolRunGroupShowMore"].waitForExistence(timeout: 3), "collapsing should hide the expanded call list again")
    }

    /// Opens a real session's bookkeeping timeline from the chat toolbar.
    /// Prefers a session likely to have real ledger entries (picks the cell
    /// whose row shows the most messages, a rough proxy for "has been
    /// running a while") but accepts either the timeline or the empty state
    /// as a valid render -- both are legitimate depending on which real
    /// session gets opened.
    func testOpensBookkeepingViewFromChat() throws {
        let app = launch()
        let list = app.collectionViews["sessionsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let firstCell = list.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10))
        firstCell.tap()

        let bookkeepingButton = app.buttons["bookkeepingViewButton"]
        XCTAssertTrue(bookkeepingButton.waitForExistence(timeout: 10), "bookkeeping toolbar button should appear in chat")
        bookkeepingButton.tap()

        let timeline = app.scrollViews["bookkeepingTimeline"]
        let emptyState = app.otherElements["bookkeepingEmptyState"]
        let found = timeline.waitForExistence(timeout: 10) || emptyState.waitForExistence(timeout: 10)
        if !found {
            attach(app, name: "bookkeeping-view-failure")
        }
        XCTAssertTrue(found, "bookkeeping view should show either a timeline or an explicit empty state")
        attach(app, name: "bookkeeping-view")

        // If a real entry rendered, tap into its expanded detail view too.
        // Matched across ANY element type, not just .buttons -- a custom
        // view used as a NavigationLink's label with .buttonStyle(.plain)
        // doesn't reliably expose its accessibilityIdentifier on a button
        // trait in the accessibility tree (same lesson as ChatView's
        // messageInput lookup above).
        let entryCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR identifier == %@", "bookkeepingEntry", "bookkeepingDriftEntry"))
            .firstMatch
        if entryCard.waitForExistence(timeout: 3) {
            entryCard.tap()
            let detail = app.scrollViews["bookkeepingEntryDetail"]
            XCTAssertTrue(detail.waitForExistence(timeout: 10), "tapping an entry should push its expanded detail view")
            attach(app, name: "bookkeeping-entry-detail")
        }
    }

    /// Assistant text renders real Markdown structure (code blocks, lists),
    /// not the old `Text(markdown:)` literal-character behavior. There's no
    /// reliable accessibility-tree way to assert "this rendered as a real
    /// `<pre>` block" from XCUITest, so this test's real assertion is the
    /// screenshot -- attached for visual review the same way the grouped-
    /// tool-run and bookkeeping tests already work. The one thing it DOES
    /// assert programmatically: the message list itself renders without
    /// crashing/hanging against a real session's real message history,
    /// which is the regression a broken theme or cache would actually
    /// produce (a hang or a blank screen), not a subtle mis-render.
    func testAssistantMarkdownRendersInChat() throws {
        let app = launch()
        let list = app.collectionViews["sessionsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))

        // Prefer the same known-real-content session the bookkeeping and
        // diff-viewer tests already cite (matches this session's own
        // mockup data), falling back to the first cell if it's scrolled
        // out of the current list snapshot.
        let known = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "trait-picker-mockup-comparison"))
            .firstMatch
        let target = known.waitForExistence(timeout: 5) ? known : list.cells.firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()

        let input = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "messageInput"))
            .firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15), "chat should open")
        sleep(2) // let the initial page load and render

        attach(app, name: "assistant-markdown-rendered")
    }

    /// Smoke test for the jump-to-bottom affordance: it can appear once
    /// scrolled away from the bottom, and tapping it is a real, harmless
    /// interaction. Deliberately loose on timing -- exactly when the arrow
    /// should appear/disappear relative to scroll position is covered
    /// precisely by `JumpNavigationTests`' unit tests against the pure
    /// `JumpNavigation` logic (every boundary: first/last message, nothing
    /// visible, near/far from bottom, including a verified negative
    /// control). This test's job is only to catch a REAL regression that
    /// unit tests can't see -- the arrow never appearing at all, or tapping
    /// it crashing/hanging -- not to re-verify exact SwiftUI scroll-geometry
    /// timing against a live API and simulator that both have real,
    /// variable latency on a shared machine.
    func testJumpToBottomCanAppearAndBeTapped() throws {
        let app = launch()
        let list = app.collectionViews["sessionsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))

        // A session with enough history to actually scroll. Not asserting
        // "idle" vs "running" here -- unlike the precise timing test this
        // replaced, a smoke test tolerates content that's still growing.
        let target = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "trait-picker-mockup-comparison"))
            .firstMatch
        var found = target.waitForExistence(timeout: 10)
        if !found {
            for _ in 0..<4 where !found {
                list.swipeUp()
                found = target.waitForExistence(timeout: 3)
            }
        }
        XCTAssertTrue(found, "expected to find a real long-history session in the list")
        target.tap()

        let input = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "messageInput"))
            .firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15), "chat should open")
        sleep(2) // let the initial page load and render

        let jumpDown = app.buttons["jumpToNextUserMessage"]
        let messagesList = app.scrollViews.firstMatch

        // Several rounds of scroll-and-check rather than one fixed swipe
        // count -- real content height varies, and this only needs the
        // arrow to appear AT SOME POINT, not on a specific swipe.
        var appeared = jumpDown.waitForExistence(timeout: 1)
        for _ in 0..<8 where !appeared {
            messagesList.swipeDown()
            appeared = jumpDown.waitForExistence(timeout: 2)
        }
        if !appeared {
            attach(app, name: "jump-arrow-did-not-appear")
        }
        XCTAssertTrue(appeared, "the jump-to-bottom arrow should be able to appear after scrolling up")
        attach(app, name: "jump-arrow-visible")

        // Tapping it must be a real, harmless interaction -- not asserting
        // it disappears by a specific moment, just that the app is still
        // alive and responsive afterward.
        jumpDown.tap()
        sleep(1)
        XCTAssertTrue(input.exists, "chat should still be functional after using the jump arrow")
        attach(app, name: "jump-arrow-after-tap")
    }

    /// Real long user messages exist in session `bksiuOq8kgSihiNmNEwwC`
    /// (`barry-bag-audit`, completed/idle -- confirmed via the live API:
    /// five real user messages over 2000 characters each, INSIDE the
    /// initial ~60-message tail `ChatStore` loads on open, not further
    /// back in history behind a "load older" boundary). That last point
    /// matters: an earlier version of this test used
    /// `kPdNYibZbAuePBEEWtFEZ`, whose tail-60 page turned out to have ZERO
    /// user messages of any kind (confirmed via the live API after this
    /// test failed twice against real screenshots showing only assistant
    /// text no matter how far it scrolled) -- its long messages exist but
    /// sit further back in history than a plain scroll-up ever reaches
    /// without also triggering `loadOlder()`. This session's long messages
    /// are guaranteed reachable by scrolling alone.
    func testLongUserMessageCollapsesAndExpands() throws {
        let app = launch()
        let list = app.collectionViews["sessionsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))

        let target = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "barry-bag-audit"))
            .firstMatch
        var found = target.waitForExistence(timeout: 10)
        if !found {
            for _ in 0..<4 where !found {
                list.swipeUp()
                found = target.waitForExistence(timeout: 3)
            }
        }
        XCTAssertTrue(found, "expected to find the known session with real long user messages")
        target.tap()

        let input = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "messageInput"))
            .firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15), "chat should open")
        sleep(2)

        // `ChatView` opens scrolled to the bottom, and this session's own
        // tail can legitimately be assistant text -- scroll up through
        // real history rather than assuming a collapsed message is already
        // on-screen at rest (this genuinely failed once: the first
        // screenshot showed only assistant text, no user message visible
        // at all, because it happened to open scrolled past every one).
        let messagesList = app.scrollViews.firstMatch
        let showMore = app.buttons["userMessageShowMore"]
        var showMoreFound = showMore.waitForExistence(timeout: 2)
        for _ in 0..<8 where !showMoreFound {
            messagesList.swipeDown()
            showMoreFound = showMore.waitForExistence(timeout: 2)
        }
        if !showMoreFound {
            attach(app, name: "message-collapse-not-found")
        }
        XCTAssertTrue(showMoreFound, "a real 2000+ character user message should render collapsed with a Show more control")
        attach(app, name: "message-style-collapsed")

        showMore.tap()
        sleep(1)

        let showLess = app.buttons["userMessageShowLess"]
        XCTAssertTrue(showLess.waitForExistence(timeout: 5), "expanding should reveal a Show less control")
        attach(app, name: "message-style-expanded")

        showLess.tap()
        sleep(1)
        XCTAssertTrue(app.buttons["userMessageShowMore"].waitForExistence(timeout: 5), "collapsing again should restore the Show more control")
    }
}
