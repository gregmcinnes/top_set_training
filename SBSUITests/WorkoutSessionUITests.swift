import XCTest

/// Walks the real app through a workout and writes a screenshot of each step.
///
/// This logs real sets, so run it on a spare simulator, never one whose data matters.
/// `scripts/ui_walkthrough.sh` does that, starting from a clean install, and is the way
/// to run this. It isn't part of the regular test command.
final class WorkoutSessionUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotNumber = 0

    /// Set by scripts/ui_walkthrough.sh through TEST_RUNNER_WALKTHROUGH_OUT
    private var outputDirectory: String {
        ProcessInfo.processInfo.environment["WALKTHROUGH_OUT"] ?? NSTemporaryDirectory()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        allowNotificationsWhenAsked()
        app.launch()
        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Helpers

    private func shot(_ name: String) {
        shotNumber += 1
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let test = testRun?.test.name.filter { $0.isLetter || $0.isNumber } ?? "test"
        let file = "\(test)-\(String(format: "%02d", shotNumber))-\(name).png"
        try? data.write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent(file))
    }

    private func allowNotificationsWhenAsked() {
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            return false
        }
    }

    /// The system alert only reaches the monitor once the app gets an interaction
    private func dismissSpringboardAlert() {
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
    }

    private func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }

    private func tap(_ label: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let element = button(label)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "No button \(label)", file: file, line: line)
        element.tap()
    }

    private func tapContinue() {
        let next = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Continue'")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 8), "No Continue button")
        next.tap()
    }

    /// Get to Home from whatever state the app launched in
    private func goHome() {
        dismissSpringboardAlert()
        if button("I Know What I Want").waitForExistence(timeout: 5) {
            shot("welcome")
            completeOnboarding()
        }
        discardWorkoutIfActive()
        let tab = app.otherElements["tabBar"].children(matching: .button)["Workout"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
    }

    private func completeOnboarding() {
        tap("I Know What I Want")
        for _ in 0..<8 {
            if button("Start Training").exists { break }
            if button("Skip for now").exists {
                button("Skip for now").tap()
            } else {
                let next = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Continue'")).firstMatch
                if next.waitForExistence(timeout: 3) {
                    next.tap()
                } else if let program = firstProgramCard() {
                    program.tap()
                }
            }
            sleep(1)
        }
        tap("Start Training")
    }

    private func firstProgramCard() -> XCUIElement? {
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] '5x5' OR label CONTAINS[c] 'StrongLifts'")).firstMatch
        return card.exists ? card : nil
    }

    private var resumeBar: XCUIElement { app.buttons["resumeWorkoutBar"] }

    private func discardWorkoutIfActive() {
        if resumeBar.waitForExistence(timeout: 2) {
            resumeBar.tap()
            exitWorkout()
        }
    }

    private func exitWorkout() {
        tap("Exit workout")
        let exit = app.alerts.buttons["Exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.tap()
    }

    private func openDay(_ number: Int) {
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Day \(number),")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8), "No card for day \(number)")
        card.tap()
    }

    private func startFirstDay() {
        goHome()
        openDay(firstUnfinishedDay())
        tap("Start Workout")
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 8))
    }

    /// Earlier tests may have finished some days
    private func firstUnfinishedDay() -> Int {
        let card = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'To Do'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8), "No day left to do")
        // "Day 3, Workout A, …"
        return Int(card.label.dropFirst("Day ".count).prefix { $0.isNumber }) ?? 1
    }

    /// "Set 2 of 5" on the workout screen
    private func setLabel() -> String {
        let label = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Set ' AND label CONTAINS ' of '")).firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        return label.label
    }

    private func completeSet() {
        tap("Complete Set")
        dismissSpringboardAlert()
        XCTAssertTrue(button("Skip rest timer").waitForExistence(timeout: 5))
    }

    private func skipRest() {
        tap("Skip rest timer")
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 5))
    }

    // MARK: - Item 0

    /// Tapping the highlighted tab used to pop the workout, losing every set
    func testTabBarCannotEndAWorkout() {
        startFirstDay()
        shot("workout-open")

        XCTAssertFalse(app.otherElements["tabBar"].firstMatch.isHittable, "The tab bar must be out of reach during a workout")

        completeSet()
        skipRest()
        completeSet()
        skipRest()
        XCTAssertEqual(setLabel(), "Set 3 of 5")

        // Nothing at the tab bar's position does anything
        let tabPosition = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.97))
        tabPosition.tap()
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 2))
        XCTAssertEqual(setLabel(), "Set 3 of 5")
        shot("after-tab-position-tap")

        exitWorkout()
    }

    // MARK: - Minimizing

    func testMinimizeBrowseAndResumeKeepsSetAndTimer() {
        startFirstDay()
        completeSet()
        skipRest()
        completeSet()
        let before = setLabel()
        shot("resting")

        tap("Minimize workout")
        XCTAssertTrue(resumeBar.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["tabBar"].firstMatch.isHittable)
        XCTAssertTrue(resumeBar.label.contains("Rest timer"), "Countdown while resting: \(resumeBar.label)")
        shot("minimized-home")

        app.otherElements["tabBar"].children(matching: .button)["History"].tap()
        XCTAssertTrue(resumeBar.waitForExistence(timeout: 5))
        shot("minimized-history")
        app.otherElements["tabBar"].children(matching: .button)["Settings"].tap()
        XCTAssertTrue(resumeBar.waitForExistence(timeout: 5))
        app.swipeUp()
        shot("minimized-settings-scrolled")

        // Tapping the active tab does nothing to the workout now
        app.otherElements["tabBar"].children(matching: .button)["Workout"].tap()
        app.otherElements["tabBar"].children(matching: .button)["Workout"].tap()
        XCTAssertTrue(resumeBar.waitForExistence(timeout: 5))

        resumeBar.tap()
        XCTAssertTrue(button("Skip rest timer").waitForExistence(timeout: 5))
        XCTAssertEqual(setLabel(), before)
        shot("resumed")

        exitWorkout()
        XCTAssertFalse(resumeBar.waitForExistence(timeout: 2), "Exiting clears the session")
    }

    func testStartingAnotherDayAsksFirst() {
        startFirstDay()
        completeSet()
        tap("Minimize workout")

        // The session screen for this day offers Resume rather than Start
        XCTAssertTrue(button("Resume Workout").waitForExistence(timeout: 5))
        shot("session-resume-button")

        let back = app.navigationBars.buttons.firstMatch
        back.tap()
        openDay(firstUnfinishedDayOtherThanActive())
        tap("Start Workout")

        let alert = app.alerts["Workout in Progress"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        shot("in-progress-prompt")
        alert.buttons["Resume Current Workout"].tap()
        XCTAssertTrue(button("Skip rest timer").waitForExistence(timeout: 5))

        tap("Minimize workout")
        tap("Start Workout")
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Discard and Start New"].tap()
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 8))
        XCTAssertEqual(setLabel(), "Set 1 of 5")
        exitWorkout()
    }

    private func firstUnfinishedDayOtherThanActive() -> Int {
        let cards = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'To Do'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 8))
        let index = cards.count > 1 ? 1 : 0
        return Int(cards.element(boundBy: index).label.prefix { $0.isNumber }) ?? 2
    }

    // MARK: - Kill And Relaunch

    func testKillMidWorkoutResumesAtTheSameSet() {
        startFirstDay()
        completeSet()
        skipRest()
        completeSet()
        skipRest()
        XCTAssertEqual(setLabel(), "Set 3 of 5")
        sleep(1)  // Saves land on the next main-actor turn

        app.terminate()
        app.launch()

        XCTAssertTrue(resumeBar.waitForExistence(timeout: 10), "A saved session shows the bar on launch")
        shot("relaunched")
        resumeBar.tap()
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 5))
        XCTAssertEqual(setLabel(), "Set 3 of 5")
        shot("relaunched-resumed")
        exitWorkout()
        XCTAssertFalse(resumeBar.waitForExistence(timeout: 2))

        app.terminate()
        app.launch()
        XCTAssertFalse(resumeBar.waitForExistence(timeout: 5), "Exiting cleared the saved session")
    }

    func testKillMidRestResumesTheCountdown() {
        startFirstDay()
        completeSet()
        sleep(1)

        app.terminate()
        app.launch()

        XCTAssertTrue(resumeBar.waitForExistence(timeout: 10))
        XCTAssertTrue(resumeBar.label.contains("Rest timer"), "Rest continues: \(resumeBar.label)")
        shot("relaunched-mid-rest")
        resumeBar.tap()
        XCTAssertTrue(button("Skip rest timer").waitForExistence(timeout: 5))
        shot("relaunched-mid-rest-resumed")
        skipRest()
        XCTAssertEqual(setLabel(), "Set 2 of 5")
        exitWorkout()
    }

    /// Bring the running rest down to its 15 second minimum
    private func shortenRest() {
        for _ in 0..<8 { button("Subtract 15 seconds").tap() }
    }

    func testRestEndsWhileMinimized() {
        startFirstDay()
        completeSet()
        shortenRest()
        tap("Minimize workout")
        XCTAssertTrue(resumeBar.waitForExistence(timeout: 5))
        app.otherElements["tabBar"].children(matching: .button)["Settings"].tap()

        let done = NSPredicate(format: "label CONTAINS 'Rest done'")
        expectation(for: done, evaluatedWith: resumeBar)
        waitForExpectations(timeout: 25)
        shot("rest-done-minimized")

        resumeBar.tap()
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 5), "Back on the next set, not a timer")
        XCTAssertEqual(setLabel(), "Set 2 of 5")
        exitWorkout()
    }

    func testRestThatExpiresDuringAKillIsClearedSilently() {
        startFirstDay()
        completeSet()
        shortenRest()
        sleep(1)

        app.terminate()
        sleep(17)
        app.launch()

        XCTAssertTrue(resumeBar.waitForExistence(timeout: 10))
        XCTAssertFalse(resumeBar.label.contains("Rest"), "Nothing left of the rest: \(resumeBar.label)")
        shot("relaunched-rest-expired")
        resumeBar.tap()
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 5))
        XCTAssertFalse(button("Skip rest timer").exists)
        XCTAssertEqual(setLabel(), "Set 2 of 5")
        exitWorkout()
    }

    func testCorruptSavedSessionDoesNotBlockLaunch() {
        goHome()
        app.terminate()

        // Launch arguments override defaults, so this replaces the saved session
        app.launchArguments = ["-sbs_active_workout_session", "<6e6f74206a736f6e>"]
        app.launch()

        XCTAssertTrue(app.otherElements["tabBar"].children(matching: .button)["Workout"].waitForExistence(timeout: 10))
        XCTAssertFalse(resumeBar.waitForExistence(timeout: 3))
        shot("launched-with-corrupt-session")
    }

    // MARK: - Finished Days

    /// Do every set until the summary shows
    private func finishWorkout() {
        for _ in 0..<60 {
            let celebration = button("Back to it")  // The PR cover, when confetti is on
            if celebration.exists && celebration.isHittable {
                celebration.tap()
                sleep(1)
                continue
            }
            if button("Done").exists && button("Done").isHittable { return }
            if button("Skip rest timer").exists && button("Skip rest timer").isHittable {
                button("Skip rest timer").tap()
            } else if button("Complete Set").exists && button("Complete Set").isHittable {
                button("Complete Set").tap()
                dismissSpringboardAlert()
            }
            usleep(400_000)
        }
        XCTFail("The workout never reached its summary")
    }

    private var doneState: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Workout Complete'")).firstMatch
    }

    private var finishedDayCard: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Done'")).firstMatch
    }

    /// Finish a whole workout, then check the finished day offers a quiet redo instead
    /// of Start Workout, and that a redo replaces the log rather than adding to it.
    func testFinishingShowsDoneStateWithRedo() {
        startFirstDay()
        finishWorkout()
        shot("summary")
        tap("Done")
        XCTAssertFalse(resumeBar.waitForExistence(timeout: 2), "Finishing clears the session")

        XCTAssertTrue(finishedDayCard.waitForExistence(timeout: 5), "Done lands on Home")
        shot("home-after-finish")
        finishedDayCard.tap()

        XCTAssertTrue(doneState.waitForExistence(timeout: 5))
        XCTAssertFalse(button("Start Workout").exists, "A finished day doesn't offer Start Workout")
        shot("session-done-state")

        tap("Redo Workout")
        let alert = app.alerts["Redo This Workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        shot("redo-confirm")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(doneState.waitForExistence(timeout: 5))

        // Backing out of a redo keeps the log
        tap("Redo Workout")
        alert.buttons["Redo Workout"].tap()
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 8))
        XCTAssertEqual(setLabel(), "Set 1 of 5")
        exitWorkout()
        XCTAssertTrue(doneState.waitForExistence(timeout: 5))

        // Going through with it leaves one finished day
        tap("Redo Workout")
        alert.buttons["Redo Workout"].tap()
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 8))
        finishWorkout()
        shot("redo-summary")
        tap("Done")

        XCTAssertTrue(finishedDayCard.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Done'")).count, 1)
        shot("home-after-redo")
        app.otherElements["tabBar"].children(matching: .button)["History"].tap()
        sleep(1)
        shot("history-after-redo")
    }
}
