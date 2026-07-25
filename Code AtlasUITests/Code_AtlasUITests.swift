//
//  Code_AtlasUITests.swift
//  Code AtlasUITests
//
//  Created by Saketh Kammari on 7/23/26.
//

import XCTest

final class Code_AtlasUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAllDashboardCardsScrollAndDoNotCrash() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        enterMockSessionIfNeeded(app)

        openTab("Home", in: app)
        let homeScroll = app.scrollViews["homeScrollView"]
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["How It Works"].waitForExistence(timeout: 3))
        app.staticTexts["AI Code Review"].firstMatch.tap()
        let reviewScroll = app.scrollViews["reviewScrollView"]
        XCTAssertTrue(reviewScroll.waitForExistence(timeout: 3))
        app.buttons["Review Indexed Repo"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Add a public GitHub repository")).firstMatch.waitForExistence(timeout: 4))
        app.navigationBars.buttons["Home"].firstMatch.tap()

        openTab("Ask", in: app)
        let askScroll = app.scrollViews["askScrollView"]
        XCTAssertTrue(askScroll.waitForExistence(timeout: 3))
        app.buttons["askSendButton"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "JWT authentication")).firstMatch.waitForExistence(timeout: 5))
        askScroll.swipeUp()
        askScroll.swipeDown()

        openTab("Explore", in: app)
        let exploreScroll = app.scrollViews["exploreScrollView"]
        XCTAssertTrue(exploreScroll.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Project Tree"].waitForExistence(timeout: 4))
        let chatFile = app.buttons["architectureFileButton_Sources_Chat_ChatViewModel_swift"]
        if chatFile.waitForExistence(timeout: 2) {
            chatFile.tap()
            XCTAssertTrue(app.staticTexts["ChatViewModel.swift"].waitForExistence(timeout: 2))
            XCTAssertTrue(app.staticTexts["Selected File"].waitForExistence(timeout: 2))
        }
        exploreScroll.swipeUp()
        exploreScroll.swipeDown()

        openTab("Home", in: app)
        app.staticTexts["Refactoring Assistant"].firstMatch.tap()
        let refactorScroll = app.scrollViews["refactorScrollView"]
        XCTAssertTrue(refactorScroll.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Extract token refresh policy"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Problem"].exists)
        app.buttons["Mark Applied"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Applied"].firstMatch.waitForExistence(timeout: 2))
        app.navigationBars.buttons["Home"].firstMatch.tap()

        app.staticTexts["Pull Request Review"].firstMatch.tap()
        let prScroll = app.scrollViews["pullRequestScrollView"]
        XCTAssertTrue(prScroll.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["PR #128: Add repository chat streaming"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Sources/Chat/ChatService.swift"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Do not log raw streamed chunks because answers can contain private repository snippets."].waitForExistence(timeout: 2))
        app.buttons["approvePullRequestButton"].tap()
        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 2))
        app.buttons["requestPullRequestChangesButton"].tap()
        XCTAssertTrue(app.staticTexts["Changes requested"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testAccountSectionActionsAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        enterMockSessionIfNeeded(app)
        openTab("Account", in: app)

        let accountScroll = app.scrollViews["accountScrollView"]
        XCTAssertTrue(accountScroll.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["CodeAtlas Demo User"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["92/100"].waitForExistence(timeout: 2))
        app.buttons["connectGitHubButton"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 3))
        app.buttons["disconnectGitHubButton"].tap()
        XCTAssertTrue(app.staticTexts["Not Connected"].waitForExistence(timeout: 3))
        openAccountDetail("Manage Account", in: app)
        XCTAssertTrue(app.staticTexts["Full Name"].waitForExistence(timeout: 3))
        navigateBackToAccount(in: app)
        openAccountDetail("Privacy & Security", in: app)
        XCTAssertTrue(app.staticTexts["Repository Content"].waitForExistence(timeout: 3))
        navigateBackToAccount(in: app)
        openAccountDetail("About CodeAtlas", in: app)
        XCTAssertTrue(app.staticTexts["Project Health"].waitForExistence(timeout: 3))
        navigateBackToAccount(in: app)
        openAccountDetail("Send Feedback", in: app)
        app.buttons["sendFeedbackButton"].tap()
        XCTAssertTrue(app.buttons["Feedback Sent"].waitForExistence(timeout: 3))
        navigateBackToAccount(in: app)
        accountScroll.swipeUp()
        accountScroll.swipeDown()
        app.buttons["accountSignOutButton"].tap()
        app.buttons["Sign Out"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["CodeAtlas"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchesInLightAndDarkMode() throws {
        for style in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-AppleInterfaceStyle", style]
            app.launch()
            enterMockSessionIfNeeded(app)
            XCTAssertTrue(app.tabBars.buttons["Home"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func enterMockSessionIfNeeded(_ app: XCUIApplication) {
        let continueButton = app.buttons["continueMockSessionButton"]
        if continueButton.waitForExistence(timeout: 2) {
            continueButton.tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func openTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
            return
        }

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 3), "Missing tab or More menu for: \(title)")
        moreTab.tap()

        let moreCell = app.cells.staticTexts[title].firstMatch
        XCTAssertTrue(moreCell.waitForExistence(timeout: 3), "Missing More item: \(title)")
        moreCell.tap()
    }

    @MainActor
    private func openAccountDetail(_ title: String, in app: XCUIApplication) {
        let button = app.buttons[title].firstMatch
        if button.waitForExistence(timeout: 2) {
            button.tap()
            return
        }

        let text = app.staticTexts[title].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 3), "Missing account row: \(title)")
        text.tap()
    }

    @MainActor
    private func navigateBackToAccount(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons["Account"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()
    }
}
