import XCTest

/// Accessories inside the one workout session: starting at them, what gets logged and when,
/// supersets for premium users, and the logging sheets.
final class AccessorySessionUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotNumber = 0

    private var outputDirectory: String {
        ProcessInfo.processInfo.environment["WALKTHROUGH_OUT"] ?? NSTemporaryDirectory()
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

    private func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = button(label)
        XCTAssertTrue(element.waitForExistence(timeout: 8), "No button \(label)", file: file, line: line)
        element.tap()
    }

    private func any(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func containingText(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func hex(_ json: String) -> String {
        Data(json.utf8).map { String(format: "%02x", $0) }.joined()
    }

    private let lift = #"{"type":"linear","lift":"Squat","name":"Squat","sets":1,"reps":5}"#
    private let curl = #"{"type":"accessory","name":"Curl","defaultSets":2,"defaultReps":10}"#
    private let facePull = #"{"type":"accessory","name":"Face Pull","defaultSets":1,"defaultReps":12}"#

    private func launch(days: String, premium: Bool = false, supersets: Bool = false, extra: String = "") {
        continueAfterFailure = false
        let id = "11111111-2222-3333-4444-555555555555"
        let template = #"{"id":"\#(id)","name":"My Plan","created_at":0,"updated_at":0,"mode":"simple","days_per_week":2,"weeks":[1,2],"days":\#(days)}"#
        let user = #"{"hasCompletedOnboarding":true,"selectedProgram":"custom_\#(id)","customTemplates":[\#(template)],"customInitialMaxes":{"Squat":135}\#(extra)}"#
        app = XCUIApplication()
        app.launchArguments = ["-sbs_user_data", "<\(hex(user))>", "-sbs_active_workout_session", "<>"]
        // Every key: settings have no decoding defaults, so a partial copy would be ignored
        let adjustments = #"{"belowBy2Plus":-0.05,"belowBy1":-0.02,"hitTarget":0,"beatBy1":0.005,"beatBy2":0.01,"beatBy3":0.015,"beatBy4":0.02,"beatBy5Plus":0.03}"#
        let settings = #"{"useMetric":false,"roundingIncrement":5,"currentWeek":1,"currentDay":1,"restTimerDuration":120,"supersetAccessories":\#(supersets),"weightAdjustments":\#(adjustments),"barWeight":45,"showPlateCalculator":true,"playSoundNotifications":false,"appearanceMode":"system","isMale":true,"showPRCelebrations":true,"healthKitEnabled":false,"pushNotificationsEnabled":false}"#
        app.launchArguments += ["-sbs_settings", "<\(hex(settings))>"]
        if premium {
            app.launchArguments += ["-com.gregorymcinnes.topsettraining.reviewerUnlock", "YES"]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Workout"].waitForExistence(timeout: 15))
    }

    private func openDay(_ number: Int) {
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(number),")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8), "No card for day \(number)")
        card.tap()
    }

    private func startAccessoriesOnly() {
        let start = button("Start Accessories Only")
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(button("Exit workout").waitForExistence(timeout: 8))
    }

    private func completeSetAndSkipRest() {
        tap("Complete Set")
        let skip = button("Skip rest timer")
        if skip.waitForExistence(timeout: 3), skip.isHittable { skip.tap() }
    }

    private func doSets(_ count: Int) {
        for _ in 0..<count { completeSetAndSkipRest() }
    }

    private func finishEarly() {
        tap("Exercise list")
        tap("Finish Workout")
        let confirm = app.alerts.buttons["Finish Workout"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    /// The Session screen listing Squat stays in the tree behind the cover, so read the
    /// session's own exercise list.
    private func assertSquatNotInSession(file: StaticString = #filePath, line: UInt = #line) {
        tap("Exercise list")
        XCTAssertTrue(app.navigationBars["Workout Overview"].waitForExistence(timeout: 5), file: file, line: line)
        let squat = app.staticTexts["Squat"].firstMatch
        XCTAssertFalse(squat.exists && squat.isHittable, "Main lifts are left out", file: file, line: line)
        shot("exercise-list")
        app.navigationBars["Workout Overview"].buttons["Done"].tap()
        sleep(1)
    }

    private func openAccessoryHistory() {
        app.tabBars.buttons["History"].tap()
        let link = any("historyAccessoriesLink")
        for _ in 0..<4 where !(link.exists && link.isHittable) { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 8), "No accessories in History")
        link.tap()
    }

    // MARK: - Tests

    /// Replaces the separate accessory screen's test. Same promise: no tab bar to pop it.
    func testAccessoriesOnlySessionCannotBePoppedByTheTabBar() {
        launch(days: #"{"1":[\#(lift),\#(curl)],"2":[\#(lift)]}"#)
        openDay(1)
        sleep(1)
        shot("session-screen")
        startAccessoriesOnly()
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "The tab bar must be out of reach here too")
        XCTAssertTrue(app.staticTexts["Curl"].firstMatch.exists, "Opens on the accessory")
        assertSquatNotInSession()
        shot("accessory-session")
        tap("Exit workout")
        let exit = app.alerts.buttons["Exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.tap()
        XCTAssertTrue(button("Start Accessories Only").waitForExistence(timeout: 8))
    }

    /// Only what was done is logged, at the session's weight, once the session finishes
    func testFinishEarlyLogsPerformedAccessoriesOnly() {
        launch(days: #"{"1":[\#(curl),\#(facePull)],"2":[\#(lift)]}"#)
        openDay(1)
        tap("Start Workout")
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 8))

        // Set a weight through the pad
        let weightButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Edit weight'")).firstMatch
        XCTAssertTrue(weightButton.waitForExistence(timeout: 5))
        weightButton.tap()
        XCTAssertTrue(button("Save weight").waitForExistence(timeout: 5))
        shot("weight-sheet")
        tap("2")
        tap("7")
        tap("Decimal point")
        tap("5")
        shot("weight-entered")
        tap("Save weight")
        sleep(1)

        doSets(1)
        shot("after-one-set")
        finishEarly()
        XCTAssertTrue(button("Done").waitForExistence(timeout: 8))
        shot("summary")
        tap("Done")

        openAccessoryHistory()
        XCTAssertTrue(app.staticTexts["Curl"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Face Pull"].firstMatch.exists, "It was never done")
        shot("accessory-history")
    }

    /// Exit drops the session: accessory sets aren't logged, and the screen says so first
    func testExitLogsNoAccessories() {
        launch(days: #"{"1":[\#(curl)],"2":[\#(lift)]}"#)
        openDay(1)
        tap("Start Workout")
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 8))
        doSets(1)
        tap("Exit workout")
        XCTAssertTrue(app.alerts.buttons["Exit"].waitForExistence(timeout: 5))
        shot("exit-alert")
        app.alerts.buttons["Exit"].tap()
        XCTAssertTrue(button("Start Workout").waitForExistence(timeout: 8))
        app.tabBars.buttons["History"].tap()
        sleep(1)
        XCTAssertFalse(any("historyAccessoriesLink").exists, "Nothing should be logged")
        shot("history")
    }

    /// Lifts first, accessories later in their own session: one workout in History
    func testAccessoriesAfterTheLiftsAreOneWorkoutInHistory() {
        launch(days: #"{"1":[\#(lift),\#(facePull)],"2":[\#(lift)]}"#)
        openDay(1)
        tap("Start Workout")
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 8))
        completeSetAndSkipRest()
        finishEarly()
        XCTAssertTrue(button("Done").waitForExistence(timeout: 8))
        tap("Done")

        openDay(1)
        XCTAssertTrue(button("Redo Workout").waitForExistence(timeout: 8), "The lift is logged, so the day is done")
        startAccessoriesOnly()
        assertSquatNotInSession()
        tap("Complete Set")
        XCTAssertTrue(button("Done").waitForExistence(timeout: 8))
        XCTAssertFalse(containingText("Not finished").exists, "No lift is left open")
        XCTAssertTrue(app.staticTexts["Accessories"].firstMatch.exists, "The summary lists what gets logged")
        shot("accessories-summary")
        tap("Done")

        app.tabBars.buttons["History"].tap()
        let sessionsLink = any("historySessionsLink")
        for _ in 0..<4 where !(sessionsLink.exists && sessionsLink.isHittable) { app.swipeUp() }
        sessionsLink.tap()
        XCTAssertTrue(any("historySessionRow").waitForExistence(timeout: 8))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "historySessionRow").count, 1)
        shot("sessions")
        any("historySessionRow").tap()
        XCTAssertTrue(app.staticTexts["Face Pull"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Squat"].firstMatch.exists)
        shot("session-detail")
    }

    /// An accessory-only day reads Done once finished, without counting as next or progress
    func testAccessoryOnlyDayShowsDoneWithoutChangingProgress() {
        launch(days: #"{"1":[\#(facePull)],"2":[\#(facePull)]}"#)
        let day = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '1,'")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 8))
        XCTAssertTrue(day.label.hasSuffix("To Do"), day.label)
        day.tap()
        XCTAssertFalse(button("Start Accessories Only").waitForExistence(timeout: 2), "Start Workout is the same thing here")
        tap("Start Workout")
        tap("Complete Set")
        XCTAssertTrue(button("Done").waitForExistence(timeout: 8))
        tap("Done")

        XCTAssertTrue(day.waitForExistence(timeout: 8))
        XCTAssertFalse(day.label.hasSuffix("To Do"), day.label)
        XCTAssertFalse(app.otherElements["nextWorkoutCard"].exists)
        XCTAssertFalse(app.staticTexts["Program Progress"].exists)
        shot("home-after")
        day.tap()
        XCTAssertTrue(button("Redo Workout").waitForExistence(timeout: 8))
        shot("session-done")
    }

    /// Premium superset pairing: the accessory rides with its lift and logs at finish
    func testSupersetAccessoryLogsWithItsLift() {
        launch(days: #"{"1":[\#(lift),\#(curl),\#(facePull)],"2":[\#(lift)]}"#, premium: true, supersets: true)
        openDay(1)
        sleep(1)
        shot("session-screen")
        tap("Start Workout")
        XCTAssertTrue(button("Complete Set").waitForExistence(timeout: 8))
        tap("Complete Set")   // Squat's only set
        let skip = button("Skip rest timer")
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        let supersetTimer = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Superset timer'")).firstMatch
        XCTAssertTrue(supersetTimer.waitForExistence(timeout: 5), "The pair shows in the rest after the lift's last set")
        shot("rest-after-squat")
        skip.tap()
        XCTAssertTrue(app.staticTexts["Face Pull"].firstMatch.waitForExistence(timeout: 5), "The extra accessory stands alone")
        shot("extra-accessory")
        tap("Complete Set")
        XCTAssertTrue(button("Done").waitForExistence(timeout: 8))
        tap("Done")

        openAccessoryHistory()
        XCTAssertTrue(app.staticTexts["Curl"].firstMatch.waitForExistence(timeout: 8), "The paired accessory logged")
        XCTAssertTrue(app.staticTexts["Face Pull"].firstMatch.exists)
        shot("accessory-history")
    }

    /// The Session screen's sheets: same sides, the app's pad, ✓ commits
    func testSessionSheetsShareOnePattern() {
        launch(days: #"{"1":[\#(lift),\#(curl)],"2":[\#(lift)]}"#)
        openDay(1)
        sleep(1)
        // The accessory's comes last: the day's lifts have Log buttons too
        let logs = app.buttons.matching(identifier: "Log")
        XCTAssertTrue(logs.firstMatch.waitForExistence(timeout: 5))
        let log = logs.element(boundBy: logs.count - 1)
        for _ in 0..<3 where !(log.exists && log.isHittable) { app.swipeUp() }
        XCTAssertTrue(log.waitForExistence(timeout: 5), "No log button for the accessory")
        log.tap()
        XCTAssertTrue(button("Save weight").waitForExistence(timeout: 5))
        XCTAssertFalse(button("Save weight").isEnabled, "Nothing entered yet")
        shot("accessory-log-sheet")
        tap("0")
        XCTAssertTrue(button("Save weight").isEnabled, "0 is a real accessory weight")
        tap("Delete")
        tap("2")
        tap("5")
        shot("accessory-log-entered")
        tap("Save weight")
        XCTAssertTrue(containingText("Last: 25").waitForExistence(timeout: 5))

        tap("Edit accessories")
        XCTAssertTrue(app.navigationBars["Edit Accessories"].waitForExistence(timeout: 5))
        shot("accessory-editor")
        tap("Cancel")
    }
}
