import XCTest

/// The in-workout flow from Home back to Home. Each test launches with its own user data,
/// so a lift's first log really is its first and programs can be tested past the free tier
/// (gating is at selection, so an in-progress cycle runs on any tier).
final class WorkoutFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotNumber = 0

    private var outputDirectory: String {
        ProcessInfo.processInfo.environment["WALKTHROUGH_OUT"] ?? NSTemporaryDirectory()
    }

    /// `confetti` turns on "Celebrate PRs with confetti", the PR cover. It's off by
    /// default; the flash on the live set card always runs.
    private func launch(program: String, confetti: Bool = false) {
        continueAfterFailure = false
        let maxes = #"{"Squat":225,"Bench Press":155,"Deadlift":275,"Overhead Press":95,"Barbell Row":135,"Sumo Deadlift":245,"Front Squat":185}"#
        let json = #"{"hasCompletedOnboarding":true,"selectedProgram":"\#(program)","customInitialMaxes":\#(maxes)}"#
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined()
        app = XCUIApplication()
        // Launch arguments override defaults, and the saved session has to go with the data
        app.launchArguments = ["-sbs_user_data", "<\(hex)>", "-sbs_active_workout_session", "<>"]
        if confetti {
            // Every key: settings have no decoding defaults, so a partial copy would be ignored
            let adjustments = #"{"belowBy2Plus":-0.05,"belowBy1":-0.02,"hitTarget":0,"beatBy1":0.005,"beatBy2":0.01,"beatBy3":0.015,"beatBy4":0.02,"beatBy5Plus":0.03}"#
            let settings = #"{"useMetric":false,"roundingIncrement":5,"currentWeek":1,"currentDay":1,"restTimerDuration":120,"supersetAccessories":false,"weightAdjustments":\#(adjustments),"barWeight":45,"showPlateCalculator":true,"playSoundNotifications":false,"appearanceMode":"system","isMale":true,"showPRCelebrations":true,"celebratePRsWithConfetti":true,"healthKitEnabled":false,"pushNotificationsEnabled":true}"#
            let settingsHex = Data(settings.utf8).map { String(format: "%02x", $0) }.joined()
            app.launchArguments += ["-sbs_settings", "<\(settingsHex)>"]
        }
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            return false
        }
        app.launch()
        allowNotifications()
        XCTAssertTrue(app.otherElements["tabBar"].children(matching: .button)["Workout"].waitForExistence(timeout: 15))
        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
    }

    private func allowNotifications() {
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
    }

    private func shot(_ name: String) {
        shotNumber += 1
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let test = testRun?.test.name.filter { $0.isLetter || $0.isNumber } ?? "test"
        let file = "\(test)-\(String(format: "%02d", shotNumber))-\(name).png"
        try? data.write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent(file))
    }

    private func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }

    private func text(_ label: String) -> XCUIElement { app.staticTexts[label].firstMatch }

    private func containingText(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = button(label)
        XCTAssertTrue(element.waitForExistence(timeout: 8), "No button \(label)", file: file, line: line)
        element.tap()
    }

    private func start(day: Int) {
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Day \(day),")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8), "No card for day \(day)")
        card.tap()
        tap("Start Workout")
        XCTAssertTrue(app.buttons["Exercise list"].waitForExistence(timeout: 8))
    }

    private func setLabel() -> String {
        let label = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Set ' AND label CONTAINS ' of '")).firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        return label.label
    }

    private func enterReps(_ reps: Int) {
        for digit in String(reps) { tap(String(digit)) }
        tap("Confirm reps")
    }

    /// Complete every set until the summary, counting PR overlays along the way
    @discardableResult
    private func finishWorkout(amrapReps: Int = 8) -> Int {
        var celebrations = 0
        for _ in 0..<200 {
            if button("Done").exists && button("Done").isHittable { return celebrations }
            if button("Back to it").exists && button("Back to it").isHittable {
                celebrations += 1
                dismissCelebration()
            } else if button("Skip rest timer").exists && button("Skip rest timer").isHittable {
                button("Skip rest timer").tap()
            } else if button("Complete Set").exists && button("Complete Set").isHittable {
                button("Complete Set").tap()
            } else if button("Log Reps").exists && button("Log Reps").isHittable {
                button("Log Reps").tap()
                enterReps(amrapReps)
            }
            usleep(300_000)
        }
        XCTFail("The workout never reached its summary")
        return celebrations
    }

    /// Wait it out: a button on a cover that's animating away can't report hittability
    private func dismissCelebration() {
        button("Back to it").tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: button("Back to it"))
        wait(for: [gone], timeout: 5)
    }

    private func completeSets(_ count: Int) {
        for _ in 0..<count {
            tap("Complete Set")
            allowNotifications()
            tap("Skip rest timer")
        }
    }

    // MARK: - Item 3, 6, 10

    /// The normal path: no question sheet, no PR overlay for first-ever logs, a summary
    /// with what happens next, and Done landing on Home with the next day selected.
    func testFullWorkoutGoesHomeToHomeWithNoQuestions() {
        launch(program: "stronglifts_5x5_12week")
        shot("home")
        start(day: 1)
        shot("first-set")
        tap("Complete Set")
        allowNotifications()
        XCTAssertTrue(button("Skip rest timer").waitForExistence(timeout: 5))
        shot("rest")
        tap("Skip rest timer")

        let celebrations = finishWorkout()
        XCTAssertEqual(celebrations, 0, "First-ever logs are baselines, not PRs")
        XCTAssertFalse(containingText("PR").exists, "No PR claims on a first workout")
        XCTAssertTrue(text("Next Time").exists)
        XCTAssertFalse(app.buttons["Exit workout"].exists, "The summary has no way to abandon")
        XCTAssertFalse(app.buttons["Exercise list"].exists)
        shot("summary")

        tap("Done")
        let finishedDay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Day 1,' AND label ENDSWITH 'Done'")).firstMatch
        XCTAssertTrue(finishedDay.waitForExistence(timeout: 8), "Done lands on Home")
        XCTAssertFalse(button("Redo Workout").exists, "Not on the Session screen")
        XCTAssertFalse(app.buttons["resumeWorkoutBar"].exists)
        shot("home-after-done")
    }

    /// Done lands on Home's root even if the workout was minimized on another tab
    func testDoneFromAnotherTabLandsOnHomeRoot() {
        launch(program: "stronglifts_5x5_12week")
        start(day: 1)
        tap("Minimize workout")
        app.otherElements["tabBar"].children(matching: .button)["History"].tap()
        let bar = app.buttons["resumeWorkoutBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.tap()
        finishWorkout()
        tap("Done")
        let finishedDay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Day 1,' AND label ENDSWITH 'Done'")).firstMatch
        XCTAssertTrue(finishedDay.waitForExistence(timeout: 8), "On Home, not History or the Session screen")
    }

    /// A real PR mid-workout gets one overlay with nothing readable behind it. A real PR
    /// on the last lift goes straight to the summary, once.
    func testRealPRsAppearOnce() {
        launch(program: "stronglifts_5x5_12week", confetti: true)
        start(day: 1)
        XCTAssertEqual(finishWorkout(), 0)
        tap("Done")

        // Day 2 repeats Squat at a higher weight, then adds first-ever lifts
        start(day: 2)
        XCTAssertTrue(containingText("Last time:").waitForExistence(timeout: 5), "Main lifts show the last session")
        shot("last-time")
        var sawOverlay = false
        for _ in 0..<60 where !sawOverlay {
            if button("Back to it").exists && button("Back to it").isHittable {
                sawOverlay = true
            } else if button("Skip rest timer").exists && button("Skip rest timer").isHittable {
                button("Skip rest timer").tap()
            } else if button("Complete Set").exists && button("Complete Set").isHittable {
                button("Complete Set").tap()
            }
            usleep(300_000)
        }
        XCTAssertTrue(sawOverlay, "Squat at a new weight is a PR")
        shot("pr-overlay")
        dismissCelebration()
        XCTAssertEqual(finishWorkout(), 0, "Only Squat beat a previous best")
        XCTAssertTrue(containingText("New PR").exists)
        shot("summary-one-pr")
        tap("Done")

        // Day 3 repeats day 1, so its last lift is a PR: the summary celebrates it alone
        start(day: 3)
        let overlays = finishWorkout()
        XCTAssertEqual(overlays, 2, "Squat and Bench celebrate; the last lift doesn't stack on the summary")
        XCTAssertTrue(containingText("3 New PRs").exists)
        shot("summary-last-lift-pr")
    }

    // MARK: - Item 7

    /// A missed set makes the lift a failure with no question, and holds its weight
    func testMissedRepsFailTheLiftWithNoQuestion() {
        launch(program: "stronglifts_5x5_12week")
        start(day: 1)
        completeSets(2)
        shot("before-missing")
        tap("Missed Reps")
        allowNotifications()
        tap("Skip rest timer")
        shot("missed-indicator")
        completeSets(2)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        XCTAssertEqual(setLabel(), "Set 1 of 5", "On to the next lift")
        finishWorkout()
        XCTAssertTrue(containingText("Missed reps, weight stays").exists)
        shot("summary-after-miss")
    }

    func testUndoFromRestAndFromIndicator() {
        launch(program: "stronglifts_5x5_12week")
        start(day: 1)

        // From the rest screen: the rest goes with the set
        tap("Complete Set")
        allowNotifications()
        XCTAssertTrue(button("Skip rest timer").waitForExistence(timeout: 5))
        shot("rest-with-undo")
        tap("Undo Last Set")
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 5))
        XCTAssertEqual(setLabel(), "Set 1 of 5")

        // From a completed indicator
        completeSets(2)
        XCTAssertEqual(setLabel(), "Set 3 of 5")
        tap("Undo set 2")
        shot("undo-indicator-confirm")
        app.alerts.buttons["Undo Set"].tap()
        XCTAssertEqual(setLabel(), "Set 2 of 5")

        // The last set of a lift logged a result: undoing it comes back and reopens the lift
        completeSets(3)
        XCTAssertEqual(setLabel(), "Set 5 of 5")
        tap("Complete Set")
        XCTAssertEqual(setLabel(), "Set 1 of 5", "Resting before the next lift")
        tap("Undo Last Set")
        XCTAssertEqual(setLabel(), "Set 5 of 5")
        XCTAssertTrue(text("Squat").exists)
        tap("Exercise list")
        shot("list-after-undo")
        app.buttons["Done"].firstMatch.tap()
        completeSets(1)
        XCTAssertEqual(setLabel(), "Set 1 of 5")
    }

    /// Item 7: undo on the last set of the workout, reached through the summary, then
    /// the lift logs again with no double result
    func testUndoFromTheSummary() {
        launch(program: "stronglifts_5x5_12week")
        start(day: 1)
        finishWorkout()
        shot("summary-with-undo")
        tap("Undo Last Set")
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 5))
        XCTAssertEqual(setLabel(), "Set 5 of 5")
        finishWorkout()
        tap("Done")
        // Counting while the summary was still closing could read 5, so wait until it's gone
        XCTAssertTrue(app.otherElements["nextWorkoutCard"].firstMatch.waitForExistence(timeout: 8))
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Undo Last Set"].firstMatch)
        wait(for: [closed], timeout: 8)
        let finishedDays = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Done'"))
        XCTAssertEqual(finishedDays.count, 1, finishedDays.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
    }

    // MARK: - Item 8

    /// A ±15s change carries to the exercise's next rest but no further
    func testRestAdjustmentLastsForTheExercise() {
        launch(program: "stronglifts_5x5_12week")
        start(day: 1)
        tap("Complete Set")
        allowNotifications()
        XCTAssertTrue(text("of 2:00").waitForExistence(timeout: 5))
        tap("Add 15 seconds")
        XCTAssertTrue(text("of 2:15").waitForExistence(timeout: 3))
        tap("Skip rest timer")

        tap("Complete Set")
        XCTAssertTrue(text("of 2:15").waitForExistence(timeout: 5), "Kept for this exercise")
        tap("Skip rest timer")

        completeSets(3)
        tap("Complete Set")
        XCTAssertTrue(text("of 2:00").waitForExistence(timeout: 5), "The next lift starts from the default")
    }

    // MARK: - Item 9

    func testFinishEarlyHoldsUnfinishedLifts() {
        launch(program: "stronglifts_5x5_12week")
        start(day: 1)
        completeSets(2)
        tap("Exercise list")
        shot("list-with-finish")
        tap("Finish Workout")
        shot("finish-confirm")
        app.alerts.buttons["Finish Workout"].tap()

        XCTAssertTrue(text("Workout Finished").waitForExistence(timeout: 5))
        XCTAssertTrue(containingText("Not finished, weight stays").exists)
        XCTAssertFalse(app.buttons["Exit workout"].exists)
        shot("summary-early")

        tap("Done")
        // Nothing finished means nothing logged, so the day is still to do
        let day1 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Day 1,'")).firstMatch
        XCTAssertTrue(day1.waitForExistence(timeout: 8))
        XCTAssertTrue(day1.label.hasSuffix("To Do"), day1.label)
        shot("home-after-early-finish-nothing-logged")
    }

    /// With a lift finished the day is partly logged, and Done moves on to the next day
    func testFinishEarlyWithALiftLoggedMovesOn() {
        launch(program: "stronglifts_5x5_12week")
        start(day: 1)
        completeSets(6)
        XCTAssertEqual(setLabel(), "Set 2 of 5")
        tap("Exercise list")
        tap("Finish Workout")
        app.alerts.buttons["Finish Workout"].tap()
        XCTAssertTrue(text("Workout Finished").waitForExistence(timeout: 5))
        shot("summary-one-lift-logged")
        tap("Done")

        let day1 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Day 1,'")).firstMatch
        XCTAssertTrue(day1.waitForExistence(timeout: 8))
        XCTAssertFalse(day1.label.hasSuffix("To Do"), day1.label)
        XCTAssertFalse(day1.label.hasSuffix("Done"), day1.label)
        shot("home-partial-next-day-selected")
    }

    /// Finishing the last exercise with earlier ones open used to end the workout
    func testFinishingLastExerciseWithOthersOpenAsks() {
        launch(program: "stronglifts_5x5_12week")
        start(day: 1)
        tap("Exercise list")
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS '0/5 sets'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        rows.element(boundBy: rows.count - 1).tap()

        completeSets(4)
        tap("Complete Set")
        let alert = app.alerts["Lifts Still Open"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Not the summary")
        XCTAssertFalse(text("Workout Complete").exists)
        shot("lifts-still-open")

        alert.buttons["Go Back"].tap()
        XCTAssertEqual(setLabel(), "Set 1 of 5")
        shot("went-back")
    }

    func testExitNoLongerAsksAboutFitness() {
        launch(program: "stronglifts_5x5_12week")
        start(day: 1)
        completeSets(1)
        tap("Exit workout")
        let alert = app.alerts["Exit Workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Save to Apple Fitness?"].exists)
        shot("exit-alert")
        alert.buttons["Keep Going"].tap()
    }

    // MARK: - AMRAP programs

    /// 5/3/1: a volume-of-sets-plus-AMRAP day, undoing an AMRAP already logged
    func test531AMRAPUndoAndFinish() {
        launch(program: "531_bbb_12week")
        start(day: 1)
        shot("531-first-set")
        for _ in 0..<40 where !button("Log Reps").exists {
            if button("Skip rest timer").exists && button("Skip rest timer").isHittable {
                button("Skip rest timer").tap()
            } else if button("Complete Set").exists && button("Complete Set").isHittable {
                button("Complete Set").tap()
                allowNotifications()
            }
            usleep(300_000)
        }
        shot("531-amrap-set")
        XCTAssertFalse(button("Missed Reps").exists, "Only linear lifts have this")
        let setBeforeLog = setLabel()
        tap("Log Reps")
        XCTAssertTrue(button("Confirm reps").waitForExistence(timeout: 5))
        shot("531-rep-sheet")
        enterReps(8)
        XCTAssertTrue(button("Undo Last Set").waitForExistence(timeout: 5))
        shot("531-rest-after-amrap")
        tap("Undo Last Set")
        XCTAssertEqual(setLabel(), setBeforeLog)
        XCTAssertTrue(button("Log Reps").waitForExistence(timeout: 5), "The AMRAP asks again")

        finishWorkout()
        shot("531-summary")
        tap("Done")
        let finished = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Day 1,' AND label ENDSWITH 'Done'")).firstMatch
        XCTAssertTrue(finished.waitForExistence(timeout: 8))
    }

    /// nSuns: per-set weights, several AMRAPs
    func testNSunsFullWorkout() {
        launch(program: "nsuns_4day_12week")
        start(day: 1)
        shot("nsuns-first-set")
        finishWorkout()
        XCTAssertTrue(text("Next Time").exists)
        shot("nsuns-summary")
        tap("Done")
        let finished = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Day 1,' AND label ENDSWITH 'Done'")).firstMatch
        XCTAssertTrue(finished.waitForExistence(timeout: 8))
        shot("nsuns-home")
    }

}
