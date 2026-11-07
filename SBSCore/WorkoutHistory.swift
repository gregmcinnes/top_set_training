import Foundation

// Grouping and display rules for the History screens. Everything here reads saved data
// and changes none of it, and none of it computes progression.

// MARK: - What a lift's progress number means

/// How a lift moves, which decides how its progress may be described
enum LiftProgressKind: Equatable {
    /// Linear programs: the working weight itself moves, session by session
    case workingWeight
    /// Manual-progression programs (5/3/1): the TM holds until the next cycle
    case fixedTrainingMax
    /// The TM adjusts from rep-out sets during the cycle
    case autoregulatedTrainingMax
    /// Not in the current program, so all we can say is what was logged
    case notInProgram

    /// `itemTypes` are the types of every day item for this lift in the current program
    static func resolve(itemTypes: [DayItem.ItemType], manualProgression: Bool) -> LiftProgressKind {
        let types = itemTypes.filter { $0 != .accessory }
        if types.isEmpty { return .notInProgram }
        if types.contains(.linear) { return .workingWeight }
        return manualProgression ? .fixedTrainingMax : .autoregulatedTrainingMax
    }

    var chartModeLabel: String {
        self == .workingWeight ? "Working Weight" : "Training Max"
    }

    var chartTitle: String {
        switch self {
        case .workingWeight: return "Working Weight Progress"
        case .fixedTrainingMax: return "Training Max"
        case .autoregulatedTrainingMax: return "Training Max Progress"
        case .notInProgram: return "Training Max History"
        }
    }

    var chartSubtitle: String {
        switch self {
        case .workingWeight: return "Weight lifted, week by week"
        case .fixedTrainingMax: return "Stays fixed through each cycle"
        case .autoregulatedTrainingMax: return "Adjusts from your rep-out sets"
        case .notInProgram: return "From your logged workouts"
        }
    }

    var chartStartLabel: String {
        self == .workingWeight ? "Start" : "Start TM"
    }

    var chartLatestLabel: String {
        self == .workingWeight ? "Latest" : "Current TM"
    }
}

/// One lift's movement across the current cycle
struct LiftCycleProgress: Identifiable, Equatable {
    let lift: String
    let kind: LiftProgressKind
    let start: Double
    /// Next session's working weight for linear lifts, otherwise the current training max
    let current: Double

    var id: String { lift }
    var gain: Double { current - start }

    var gainPercent: Double {
        guard start > 0 else { return 0 }
        return (current - start) / start * 100
    }

    /// False when nothing moved, so the UI can say so instead of showing "up 0"
    var hasChange: Bool { abs(gain) >= 0.01 }
}

/// The current cycle's lifts plus the wording that fits their program type
struct CycleProgressSummary: Equatable {
    let lifts: [LiftCycleProgress]

    private var allWorkingWeight: Bool { !lifts.isEmpty && lifts.allSatisfy { $0.kind == .workingWeight } }
    private var anyWorkingWeight: Bool { lifts.contains { $0.kind == .workingWeight } }

    /// Every lift holds its TM through the cycle, so there's no gain to report yet
    var isFixedThroughCycle: Bool { !lifts.isEmpty && lifts.allSatisfy { $0.kind == .fixedTrainingMax } }

    var cardTitle: String {
        if allWorkingWeight { return "Working Weight Progress" }
        if isFixedThroughCycle { return "Training Maxes" }
        return anyWorkingWeight ? "Lift Progress" : "Training Max Progress"
    }

    var detailTitle: String {
        if allWorkingWeight { return "Working Weights" }
        if isFixedThroughCycle { return "Training Maxes" }
        return anyWorkingWeight ? "Lift Progress" : "TM Progress"
    }

    var averageLabel: String {
        if allWorkingWeight { return "Avg Weight Change" }
        return anyWorkingWeight ? "Avg Change" : "Avg TM Change"
    }

    var totalLabel: String {
        if allWorkingWeight { return "Total Weight Added" }
        return anyWorkingWeight ? "Total Change" : "Total TM Gained"
    }

    /// What the numbers on the detail screen are
    var explanation: String {
        if isFixedThroughCycle {
            return "This program keeps training maxes fixed through the cycle. They go up when you complete it and start the next one."
        }
        if allWorkingWeight { return "Where each lift started this cycle, and its working weight next session." }
        if anyWorkingWeight { return "Linear lifts show next session's working weight. Other lifts show their training max." }
        return "Where each training max started this cycle, and where your rep-out sets have moved it."
    }

    var emptyMessage: String {
        if isFixedThroughCycle { return "Complete workouts to see your training maxes and records here" }
        if allWorkingWeight { return "Complete workouts to watch your working weights climb" }
        return "Complete workouts to track your training max changes"
    }

    var averagePercent: Double {
        let counted = lifts.filter { $0.start > 0 }
        guard !counted.isEmpty else { return 0 }
        return counted.map(\.gainPercent).reduce(0, +) / Double(counted.count)
    }

    var totalGain: Double { lifts.map(\.gain).reduce(0, +) }

    /// Only when something moved and the program allows it to move mid-cycle
    var showsAverageBadge: Bool {
        !isFixedThroughCycle && abs(averagePercent) >= 0.05
    }
}

// MARK: - Lift order

enum HistoryLiftOrder {
    private static let classicOrder = ["Squat", "Bench Press", "Deadlift", "Overhead Press"]

    /// Each main lift once, in the order the program first uses it
    static func programOrder(_ items: [(lift: String, type: DayItem.ItemType)]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { item in
            guard item.type != .accessory, seen.insert(item.lift).inserted else { return nil }
            return item.lift
        }
    }

    /// For archived cycles, which don't keep their program's order: the big four, then A–Z
    static func classicFirst(_ lifts: some Sequence<String>) -> [String] {
        func rank(_ lift: String) -> Int {
            classicOrder.firstIndex(of: ExerciseLibrary.canonicalLiftName(lift)) ?? classicOrder.count
        }
        return lifts.sorted { a, b in
            let (ra, rb) = (rank(a), rank(b))
            return ra != rb ? ra < rb : a < b
        }
    }
}

// MARK: - Archived cycles

extension CompletedCycle {
    /// Lifts with real start and end values. `startingMaxes` also holds every lift the
    /// user ever logged, and those have no end value: they'd read as a 100% drop.
    var progressedLifts: [String] {
        HistoryLiftOrder.classicFirst(endingMaxes.keys.filter { lift in
            (startingMaxes[lift] ?? 0) > 0 && (endingMaxes[lift] ?? 0) > 0
        })
    }

    /// Lifts to preview on a cycle's row: anything that has an end value
    var summaryLifts: [String] {
        HistoryLiftOrder.classicFirst(endingMaxes.keys.filter { (endingMaxes[$0] ?? 0) > 0 })
    }

    func usedLinearProgression(for lift: String) -> Bool {
        linearLogs.canonicalLiftValue(for: lift) != nil
    }
}

// MARK: - Sessions

/// A run of identical results within one exercise: "5 × 5 at 135 lb" is one line
struct HistorySetLine: Equatable, Identifiable {
    let id: Int
    let count: Int
    let weight: Double
    let reps: Int
    let targetReps: Int
    let isAMRAP: Bool
    /// A missed set's saved rep count is an assumption, so `reps` holds the target
    let missed: Bool

    static func lines(from sets: [WorkoutSetRecord]) -> [HistorySetLine] {
        var lines: [HistorySetLine] = []
        for set in sets.sorted(by: { $0.setNumber < $1.setNumber }) {
            let missed = !set.completed && !set.isAMRAP
            let reps = missed ? set.targetReps : (set.actualReps ?? set.targetReps)
            if let last = lines.last, !set.isAMRAP, !last.isAMRAP, last.missed == missed,
               last.weight == set.weight, last.reps == reps, last.targetReps == set.targetReps {
                lines[lines.count - 1] = HistorySetLine(
                    id: last.id, count: last.count + 1, weight: last.weight, reps: last.reps,
                    targetReps: last.targetReps, isAMRAP: false, missed: missed
                )
            } else {
                lines.append(HistorySetLine(
                    id: lines.count, count: 1, weight: set.weight, reps: reps,
                    targetReps: set.targetReps, isAMRAP: set.isAMRAP, missed: missed
                ))
            }
        }
        return lines
    }
}

struct HistorySessionExercise: Equatable, Identifiable {
    let id: UUID
    let name: String
    let type: WorkoutExerciseType
    let trainingMax: Double
    let lines: [HistorySetLine]
    let note: String?
}

struct HistorySessionAccessory: Equatable, Identifiable {
    let id: UUID
    let name: String
    let weight: Double
    let sets: Int
    let reps: Int
    let note: String?
}

/// One dated workout: its record's results plus the accessories logged alongside it
struct HistorySession: Equatable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let programName: String
    /// Nil for a day with accessories but no main-lift record
    let week: Int?
    let day: Int?
    let exercises: [HistorySessionExercise]
    let accessories: [HistorySessionAccessory]

    var positionLabel: String? {
        guard let week, let day else { return nil }
        return "Week \(week) · Day \(day)"
    }

    var exerciseNames: [String] { exercises.map(\.name) + accessories.map(\.name) }
}

/// A cycle's worth of sessions, newest first
struct HistorySessionSection: Equatable, Identifiable {
    let id: String
    let cycleNumber: Int
    let isCurrent: Bool
    let programName: String?
    let sessions: [HistorySession]
    /// An archived cycle from before per-session records existed: only its summary remains
    let cycleWithoutSessionRecords: CompletedCycle?
}

struct HistorySessionList: Equatable {
    let sections: [HistorySessionSection]
    /// Archived cycles left out for an account without full history
    let lockedCycleCount: Int

    var isEmpty: Bool { sections.isEmpty }
}

enum HistorySessionBuilder {

    /// `includeArchived` is the free-tier gate: without it, nothing from an archived cycle
    /// comes back, including accessories, which aren't archived with their cycle.
    static func list(
        records: [WorkoutRecord],
        accessoryHistory: [AccessoryRecord],
        currentCycleStart: Date,
        currentCycleNumber: Int,
        currentProgramName: String?,
        archivedCycles: [CompletedCycle],
        includeArchived: Bool,
        calendar: Calendar = .current
    ) -> HistorySessionList {
        var sections: [HistorySessionSection] = []

        let current = sessions(
            records: records.filter { $0.date >= currentCycleStart },
            accessories: accessoryHistory.filter { $0.date >= currentCycleStart },
            calendar: calendar
        )
        if !current.isEmpty {
            sections.append(HistorySessionSection(
                id: "current",
                cycleNumber: currentCycleNumber,
                isCurrent: true,
                programName: currentProgramName,
                sessions: current,
                cycleWithoutSessionRecords: nil
            ))
        }

        guard includeArchived else {
            return HistorySessionList(sections: sections, lockedCycleCount: archivedCycles.count)
        }

        for cycle in archivedCycles.sorted(by: { $0.startDate > $1.startDate }) {
            let cycleSessions = sessions(for: cycle, accessoryHistory: accessoryHistory, calendar: calendar)
            let hasRecords = cycleSessions.contains { !$0.exercises.isEmpty }
            sections.append(HistorySessionSection(
                id: cycle.id.uuidString,
                cycleNumber: cycle.cycleNumber,
                isCurrent: false,
                programName: cycle.programName ?? cycle.workoutRecords.first?.programName,
                sessions: cycleSessions,
                cycleWithoutSessionRecords: hasRecords ? nil : cycle
            ))
        }
        return HistorySessionList(sections: sections, lockedCycleCount: 0)
    }

    /// One archived cycle's sessions, newest first. The caller decides whether the user
    /// may see them.
    static func sessions(
        for cycle: CompletedCycle,
        accessoryHistory: [AccessoryRecord],
        calendar: Calendar = .current
    ) -> [HistorySession] {
        sessions(
            records: cycle.workoutRecords,
            accessories: accessoryHistory.filter { isInCycle($0.date, cycle: cycle) },
            calendar: calendar
        )
    }

    private static func isInCycle(_ date: Date, cycle: CompletedCycle) -> Bool {
        date >= cycle.startDate && date < cycle.endDate
    }

    /// Accessory records have no week or day, so they join by time. Each goes to the
    /// same-day workout already under way when it was logged, or that day's first workout
    /// if it came earlier. A day with no workout gets an accessory-only session.
    static func sessions(
        records: [WorkoutRecord],
        accessories: [AccessoryRecord],
        calendar: Calendar = .current
    ) -> [HistorySession] {
        // Older data can hold records or exercises with nothing left in them
        let usable: [(record: WorkoutRecord, exercises: [WorkoutExerciseRecord])] = records
            .map { record in (record, record.exercises.filter { !$0.sets.isEmpty }) }
            .filter { !$0.exercises.isEmpty }
            .sorted { $0.record.date < $1.record.date }

        var indicesByDay: [Date: [Int]] = [:]
        for (index, item) in usable.enumerated() {
            indicesByDay[calendar.startOfDay(for: item.record.date), default: []].append(index)
        }

        var attached: [Int: [AccessoryRecord]] = [:]
        var unattachedByDay: [Date: [AccessoryRecord]] = [:]
        for accessory in accessories.sorted(by: { $0.date < $1.date }) {
            let day = calendar.startOfDay(for: accessory.date)
            guard let sameDay = indicesByDay[day], let earliest = sameDay.first else {
                unattachedByDay[day, default: []].append(accessory)
                continue
            }
            let target = sameDay.last { usable[$0].record.date <= accessory.date } ?? earliest
            attached[target, default: []].append(accessory)
        }

        var result: [HistorySession] = usable.enumerated().map { index, item in
            let title = item.record.dayTitle?.trimmingCharacters(in: .whitespaces) ?? ""
            return HistorySession(
                id: item.record.id,
                date: item.record.date,
                title: title.isEmpty ? "Day \(item.record.day)" : title,
                programName: item.record.programName,
                week: item.record.week,
                day: item.record.day,
                exercises: item.exercises.map { exercise in
                    HistorySessionExercise(
                        id: exercise.id,
                        name: exercise.exerciseName.isEmpty ? exercise.lift : exercise.exerciseName,
                        type: exercise.exerciseType,
                        trainingMax: exercise.trainingMax,
                        lines: HistorySetLine.lines(from: exercise.sets),
                        note: nonEmpty(exercise.note)
                    )
                },
                accessories: latestPerName(attached[index] ?? [])
            )
        }

        for (_, dayAccessories) in unattachedByDay {
            guard let first = dayAccessories.first else { continue }
            result.append(HistorySession(
                id: first.id,
                date: first.date,
                title: "Accessories",
                programName: "",
                week: nil,
                day: nil,
                exercises: [],
                accessories: latestPerName(dayAccessories)
            ))
        }

        return result.sorted { $0.date > $1.date }
    }

    /// Each edit of an accessory's weight appends a record, so several in one session are
    /// usually one piece of work. Keep the last, in the order first logged.
    private static func latestPerName(_ accessories: [AccessoryRecord]) -> [HistorySessionAccessory] {
        var order: [String] = []
        var latest: [String: AccessoryRecord] = [:]
        for accessory in accessories.sorted(by: { $0.date < $1.date }) {
            if latest[accessory.name] == nil { order.append(accessory.name) }
            latest[accessory.name] = accessory
        }
        return order.compactMap { latest[$0] }.map { record in
            HistorySessionAccessory(
                id: record.id,
                name: record.name,
                weight: record.weight,
                sets: record.sets,
                reps: record.reps,
                note: nonEmpty(record.note)
            )
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Accessory history

/// One accessory's results over time, newest first
struct AccessoryHistoryGroup: Equatable, Identifiable {
    let name: String
    let entries: [AccessoryRecord]

    var id: String { name }
    var latest: AccessoryRecord? { entries.first }
}

enum AccessoryHistoryBuilder {

    /// Records from the current cycle and, with `includeArchived`, from archived cycles.
    /// Records outside any remaining cycle stay hidden: the user deleted that cycle, or
    /// reset their logs.
    static func groups(
        accessoryHistory: [AccessoryRecord],
        currentCycleStart: Date,
        archivedCycles: [CompletedCycle],
        includeArchived: Bool,
        calendar: Calendar = .current
    ) -> [AccessoryHistoryGroup] {
        let visible = accessoryHistory.filter { record in
            if record.date >= currentCycleStart { return true }
            guard includeArchived else { return false }
            return archivedCycles.contains { record.date >= $0.startDate && record.date < $0.endDate }
        }

        var byName: [String: [AccessoryRecord]] = [:]
        for record in visible { byName[record.name, default: []].append(record) }

        return byName.map { name, records in
            // One per day: repeat records are edits of the same work, and the last one stands
            var seenDays = Set<Date>()
            let entries = records
                .sorted { $0.date > $1.date }
                .filter { seenDays.insert(calendar.startOfDay(for: $0.date)).inserted }
            return AccessoryHistoryGroup(name: name, entries: entries)
        }
        .sorted { a, b in
            let (da, db) = (a.latest?.date ?? .distantPast, b.latest?.date ?? .distantPast)
            return da != db ? da > db : a.name < b.name
        }
    }
}

// MARK: - Best set per week

/// A lift's top result in one week, across all that week's days
struct WeeklyBestSet: Equatable {
    let week: Int
    let reps: Int
    let target: Int
    let weight: Double
    let e1rm: Double
    let note: String?
    /// The workout this set came from
    let date: Date
    /// A missed linear session. Its saved rep count is assumed, so `reps` holds the
    /// target and `e1rm` is only good for ranking.
    let missedTarget: Bool

    /// Highest estimated 1RM per week. Sets with a measured result beat a missed session,
    /// whose rep count is a guess.
    static func perWeek(records: [WorkoutRecord], lift: String) -> [WeeklyBestSet] {
        let canonical = ExerciseLibrary.canonicalLiftName(lift)
        var best: [Int: WeeklyBestSet] = [:]

        for workout in records {
            for exercise in workout.exercises where ExerciseLibrary.canonicalLiftName(exercise.lift) == canonical {
                for set in exercise.sets {
                    guard let actualReps = set.actualReps else { continue }
                    let missed = !set.completed && !set.isAMRAP
                    let candidate = WeeklyBestSet(
                        week: workout.week,
                        reps: missed ? set.targetReps : actualReps,
                        target: set.targetReps,
                        weight: set.weight,
                        e1rm: set.weight * (1.0 + Double(actualReps) / 30.0),
                        note: exercise.note,
                        date: workout.date,
                        missedTarget: missed
                    )
                    guard let existing = best[workout.week] else {
                        best[workout.week] = candidate
                        continue
                    }
                    if existing.missedTarget != candidate.missedTarget {
                        if existing.missedTarget { best[workout.week] = candidate }
                    } else if candidate.e1rm > existing.e1rm {
                        best[workout.week] = candidate
                    }
                }
            }
        }
        return best.values.sorted { $0.week < $1.week }
    }
}

// MARK: - Next linear weight

extension ProgramEngine {
    /// The working weight after every logged session, from the same replay the plan uses,
    /// so old logs stay anchored to the weight they recorded. Asks for a session later
    /// than anything logged. Excludes any manual override set on a session not yet logged.
    func nextLinearWorkingWeight(state: ProgramState, lift: String) -> Double {
        computeLinearWeightForSession(state: state, lift: lift, week: .max, day: .max).weight
    }
}
