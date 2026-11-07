import XCTest

/// The screens around a workout: first launch to a second workout, Home's next-workout and
/// end-of-cycle cards, and History with real data.
final class FirstRunAndHomeUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotNumber = 0

    private var outputDirectory: String {
        ProcessInfo.processInfo.environment["WALKTHROUGH_OUT"] ?? NSTemporaryDirectory()
    }

    private var springboardAllow: XCUIElement {
        XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
    }

    private func shot(_ name: String) {
        shotNumber += 1
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let test = testRun?.test.name.filter { $0.isLetter || $0.isNumber } ?? "test"
        let file = "\(test)-\(String(format: "%02d", shotNumber))-\(name).png"
        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent(file))
    }

    private func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }

    private func containingText(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = button(label)
        XCTAssertTrue(element.waitForExistence(timeout: 8), "No button \(label)", file: file, line: line)
        element.tap()
    }

    private func tapContinue(file: StaticString = #filePath, line: UInt = #line) {
        let next = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Continue'")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 8), "No Continue button", file: file, line: line)
        next.tap()
        sleep(1)
    }

    private var nextCard: XCUIElement { app.otherElements["nextWorkoutCard"].firstMatch }
    private var completionCard: XCUIElement { app.otherElements["cycleCompletionCard"].firstMatch }

    /// Launch with seeded user data and no saved session
    private func launch(json: String, premium: Bool = false) {
        continueAfterFailure = false
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined()
        app = XCUIApplication()
        app.launchArguments = ["-sbs_user_data", "<\(hex)>", "-sbs_active_workout_session", "<>"]
        if premium {
            // Repeating or customizing a Pro program checks access, as it should
            app.launchArguments += ["-com.gregorymcinnes.topsettraining.reviewerUnlock", "YES"]
        }
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            return false
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Workout"].waitForExistence(timeout: 15))
    }

    private let liftMaxes = #""customInitialMaxes":{"Squat":225,"Bench Press":155,"Deadlift":275,"Overhead Press":95,"Barbell Row":135}"#

    /// Linear logs for a set of weeks and days, every lift
    private func linearLogs(weeks: [Int], days: [Int]) -> String {
        let entry = #"{"completed":true,"consecutiveFailures":0,"deloadApplied":false,"weight":135,"note":""}"#
        let dayMap = days.map { #""\#($0)":\#(entry)"# }.joined(separator: ",")
        let weekMap = weeks.map { #""\#($0)":{\#(dayMap)}"# }.joined(separator: ",")
        let lifts = ["Squat", "Bench Press", "Barbell Row", "Overhead Press", "Deadlift"]
        return "{" + lifts.map { #""\#($0)":{\#(weekMap)}"# }.joined(separator: ",") + "}"
    }

    private func finishWorkout() {
        for _ in 0..<200 {
            if button("Done").exists && button("Done").isHittable { return }
            if button("Continue").exists && button("Continue").isHittable {
                button("Continue").tap()
            } else if button("Skip rest timer").exists && button("Skip rest timer").isHittable {
                button("Skip rest timer").tap()
            } else if button("Complete Set").exists && button("Complete Set").isHittable {
                button("Complete Set").tap()
            }
            usleep(300_000)
        }
        XCTFail("The workout never reached its summary")
    }

    // MARK: - First launch through a second workout

    /// Needs a true first launch: run it through scripts/ui_walkthrough.sh, which uninstalls
    func testFirstLaunchThroughSecondWorkout() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        // No permission prompt until there's a reason for it
        XCTAssertTrue(button("I Know What I Want").waitForExistence(timeout: 15), "Needs a fresh install")
        XCTAssertFalse(springboardAllow.waitForExistence(timeout: 3), "Nothing prompts on Welcome")
        shot("welcome")

        tap("I Know What I Want")
        sleep(1)
        shot("program")
        tapContinue()
        shot("exercises")
        tapContinue()
        shot("weights")
        XCTAssertTrue(containingText("Starting Weights").exists, "Linear programs ask for working weights")
        XCTAssertLessThan(
            app.staticTexts["Squat"].firstMatch.frame.minY,
            app.staticTexts["Bench Press"].firstMatch.frame.minY,
            "Program order, Squat first"
        )
        tapContinue()
        shot("review")
        tap("Start Training")

        // Home names the next workout and its lifts
        XCTAssertTrue(nextCard.waitForExistence(timeout: 10), "Home has a next-workout card")
        XCTAssertFalse(springboardAllow.exists, "Still no prompt on Home")
        shot("home-first")
        XCTAssertTrue(nextCard.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Squat'")).firstMatch.exists)

        // History before any workout offers a way forward
        app.tabBars.buttons["History"].tap()
        sleep(1)
        shot("history-empty")
        tap("Go to Workout")
        XCTAssertTrue(nextCard.waitForExistence(timeout: 8), "The empty state leads to Home")

        // One tap from Home starts the workout. The first rest asks for permission.
        nextCard.buttons["Start Workout"].tap()
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 8))
        XCTAssertFalse(springboardAllow.exists, "No prompt until a rest starts")
        button("Complete Set").tap()
        XCTAssertTrue(springboardAllow.waitForExistence(timeout: 6), "The first rest asks")
        shot("first-rest-prompt")
        springboardAllow.tap()
        XCTAssertTrue(button("Skip rest timer").waitForExistence(timeout: 5))
        shot("first-rest-after-prompt")

        // Minimized, the card becomes Resume
        tap("Minimize workout")
        XCTAssertTrue(nextCard.buttons["Resume Workout"].waitForExistence(timeout: 8))
        shot("home-resume-card")
        nextCard.buttons["Resume Workout"].tap()

        finishWorkout()
        shot("summary-1")
        tap("Done")

        // Home moves on to the next day, and the first day's card lists its lifts
        XCTAssertTrue(nextCard.waitForExistence(timeout: 8))
        XCTAssertTrue(nextCard.staticTexts["Next: Workout B"].waitForExistence(timeout: 3), "Done moves on")
        shot("home-after-first")

        // History has the session and everything in it
        app.tabBars.buttons["History"].tap()
        sleep(1)
        shot("history-with-data")
        let sessions = app.descendants(matching: .any)["historySessionsLink"].firstMatch
        XCTAssertTrue(sessions.waitForExistence(timeout: 8))
        sessions.tap()
        let row = app.descendants(matching: .any)["historySessionRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        shot("history-sessions")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["historySessionDetail"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(containingText("Squat").exists)
        shot("history-session-detail")
        app.tabBars.buttons["Workout"].tap()

        // The second workout
        nextCard.buttons["Start Workout"].tap()
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 8))
        shot("second-first-set")
        finishWorkout()
        shot("summary-2")
        tap("Done")
        XCTAssertTrue(nextCard.staticTexts["Next: Workout A"].waitForExistence(timeout: 8))
        shot("home-after-second")
    }

    // MARK: - Home

    /// The card names the same workout whichever week is being browsed, and progress
    /// counts finished days rather than the selected week.
    func testNextCardAndProgressIgnoreTheSelectedWeek() {
        let logs = linearLogs(weeks: [1], days: [1])
        launch(json: #"{"hasCompletedOnboarding":true,"selectedProgram":"stronglifts_5x5_12week",\#(liftMaxes),"linearLogs":\#(logs)}"#)
        XCTAssertTrue(nextCard.waitForExistence(timeout: 8))
        XCTAssertTrue(nextCard.staticTexts["WEEK 1, DAY 2"].exists)
        let percent = containingText("%").label
        shot("week-1")

        let week = app.staticTexts["5"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 5), "No week 5 in the strip")
        week.tap()
        XCTAssertTrue(app.staticTexts["WEEK 5 OF 12"].waitForExistence(timeout: 3), "Week 5 is selected")
        XCTAssertTrue(nextCard.staticTexts["WEEK 1, DAY 2"].exists, "Browsing doesn't change what's next")
        XCTAssertEqual(containingText("%").label, percent, "Browsing doesn't change progress")
        shot("week-5")
    }

    // MARK: - End of cycle

    /// A linear cycle finished with an earlier week selected: the card still shows, Customize
    /// skips Welcome, and cancelling leaves it as it was.
    func testCompletionCardShowsWhicheverWeekIsSelected() {
        let logs = linearLogs(weeks: Array(1...12), days: Array(1...6))
        launch(json: #"{"hasCompletedOnboarding":true,"selectedProgram":"stronglifts_5x5_12week",\#(liftMaxes),"linearLogs":\#(logs)}"#)
        XCTAssertTrue(completionCard.waitForExistence(timeout: 8))
        XCTAssertFalse(nextCard.exists, "Nothing is next")
        shot("card")

        completionCard.buttons["Customize"].tap()
        sleep(1)
        XCTAssertFalse(button("Get Started").exists, "Customize skips Welcome")
        shot("customize-first-step")
        tap("Cancel new cycle")
        XCTAssertTrue(completionCard.waitForExistence(timeout: 8), "Cancelling changes nothing")

        tap("More options")
        tap("Start New Cycle")
        sleep(1)
        shot("menu-dialog")
        XCTAssertEqual(app.alerts.count, 0, "One dialog, not an alert then a dialog")
        XCTAssertFalse(containingText("in progress").exists, "The cycle is finished")
        tap("Quick Repeat")

        XCTAssertTrue(nextCard.waitForExistence(timeout: 8), "A new cycle has a next workout")
        XCTAssertFalse(completionCard.exists)
        XCTAssertTrue(nextCard.staticTexts["WEEK 1, DAY 1"].exists)
        shot("new-cycle")
    }

    /// 5/3/1: the increase on a finished cycle reaches Customize's prefill, and applies once
    func test531IncreaseIsTheSameThroughEveryPath() {
        let entry = #"{"amrapReps":{},"note":""}"#
        let weeks = (1...4).map { week in
            #""\#(week)":{"# + (1...4).map { #""\#($0)":\#(entry)"# }.joined(separator: ",") + "}"
        }.joined(separator: ",")
        let tmEntry = #"{"repsLastSet":8,"note":""}"#
        let tmWeeks = (1...4).map { week in
            #""\#(week)":{"# + (1...4).map { #""\#($0)":\#(tmEntry)"# }.joined(separator: ",") + "}"
        }.joined(separator: ",")
        let lifts = ["Squat", "Bench Press", "Deadlift", "Overhead Press"]
        let structured = "{" + lifts.map { #""\#($0)":{\#(weeks)}"# }.joined(separator: ",") + "}"
        let volume = "{" + lifts.map { #""\#($0)":{\#(tmWeeks)}"# }.joined(separator: ",") + "}"
        launch(json: #"{"hasCompletedOnboarding":true,"selectedProgram":"531_bbb_12week",\#(liftMaxes),"structuredLogs":\#(structured),"logs":\#(volume)}"#, premium: true)

        XCTAssertTrue(completionCard.waitForExistence(timeout: 8), "The final week is done")
        shot("card")

        // Customize prefills the increase
        completionCard.buttons["Customize"].tap()
        sleep(1)
        tapContinue() // Program
        tapContinue() // Exercises
        let squat = app.textFields["Squat weight"].firstMatch
        XCTAssertTrue(squat.waitForExistence(timeout: 8))
        shot("customize-weights")
        XCTAssertEqual(squat.value as? String, "235", "225 + 10")
        tap("Cancel new cycle")

        // Quick Repeat gives the same, and doesn't add it twice
        XCTAssertTrue(completionCard.waitForExistence(timeout: 8))
        completionCard.buttons["Quick Repeat"].tap()
        XCTAssertTrue(nextCard.waitForExistence(timeout: 8))
        tap("More options")
        tap("Start New Cycle")
        sleep(1)
        shot("menu-unstarted-dialog")
        tap("Customize New Cycle")
        sleep(1)
        tapContinue()
        tapContinue()
        XCTAssertTrue(squat.waitForExistence(timeout: 8))
        XCTAssertEqual(squat.value as? String, "235", "Nothing added on top")
        shot("after-repeat-weights")
    }

    // MARK: - Setup details

    /// The quiz's "Browse All Programs" goes to the list, not back to Welcome
    func testQuizBrowseAllGoesToTheProgramList() {
        continueAfterFailure = false
        app = XCUIApplication()
        let hex = Data(#"{"hasCompletedOnboarding":false}"#.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-sbs_user_data", "<\(hex)>", "-sbs_active_workout_session", "<>", "-onboarding.draft.v1", "<>"]
        app.launch()
        tap("Help Me Choose a Program")
        sleep(1)
        let browse = button("Browse All Programs")
        for _ in 0..<12 where !browse.exists {
            let options = app.buttons.allElementsBoundByIndex.filter {
                $0.isHittable && !["Skip", "Close", "Back", ""].contains($0.label)
            }
            options.first { $0.frame.minY > 200 }?.tap()
            sleep(1)
        }
        shot("quiz-results")
        XCTAssertTrue(browse.exists, "Answering every question reaches the results")
        browse.tap()
        XCTAssertTrue(app.staticTexts["Select Program"].waitForExistence(timeout: 5), "Goes to the list")
        shot("after-browse-all")
    }

    /// A cleared field is called out and blocks Continue
    func testClearedWeightBlocksContinue() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Empty data means onboarding, even on a simulator that's already been through it
        let hex = Data(#"{"hasCompletedOnboarding":false}"#.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-sbs_user_data", "<\(hex)>", "-sbs_active_workout_session", "<>", "-onboarding.draft.v1", "<>"]
        app.launch()

        tap("I Know What I Want")
        sleep(1)
        tapContinue()
        tapContinue()
        let squat = app.textFields["Squat weight"].firstMatch
        XCTAssertTrue(squat.waitForExistence(timeout: 8))
        squat.tap()
        sleep(1)
        shot("keyboard")
        XCTAssertTrue(app.buttons["Done"].firstMatch.exists, "The keyboard has a Done key")
        let bar = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Continue'")).firstMatch
        XCTAssertLessThanOrEqual(squat.frame.maxY, bar.frame.minY, "The field isn't behind the buttons")
        if let current = squat.value as? String {
            squat.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        sleep(1)
        shot("cleared")
        let next = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Continue'")).firstMatch
        XCTAssertFalse(next.isEnabled, "A cleared field can't be carried forward")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(next.isEnabled)
        shot("cleared-after-done")

        tap("Not sure about Squat?")
        sleep(1)
        shot("not-sure")
    }
}
