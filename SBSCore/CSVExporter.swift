import Foundation

public enum CSVExporter {
    // Simple CSV generation matching Python export_week_csv fields
    public static func exportWeekCSV(plan: [Int: [PlanItem]], week: Int) -> String {
        // Collect rows as dictionaries
        var rows: [[String: String]] = []
        let sortedDays = plan.keys.sorted()
        for day in sortedDays {
            for item in plan[day] ?? [] {
                var row: [String: String] = [
                    "Week": String(week),
                    "Day": String(day)
                ]
                switch item {
                case let .tm(name, _, tm, top):
                    row["Name"] = name
                    row["Type"] = "tm"
                    row["TM"] = String(format: "%.2f", tm)
                    row["Top single @8"] = String(format: "%.2f", top)
                case let .volume(name, _, weight, _, _, repsPerSet, repOutTarget, _, _, _, _):
                    row["Name"] = name
                    row["Type"] = "volume"
                    row["Sets"] = "4" // Program is 4 sets across, printed value matches Python default
                    row["Reps per set"] = String(repsPerSet)
                    row["Weight"] = String(format: "%.2f", weight)
                    row["Rep out target"] = String(repOutTarget)
                case let .structured(name, _, tm, sets, _):
                    row["Name"] = name
                    row["Type"] = "structured"
                    row["TM"] = String(format: "%.2f", tm)
                    row["Sets"] = String(sets.count)
                    // Export the heaviest weight (1+ set)
                    if let heaviestSet = sets.max(by: { $0.weight < $1.weight }) {
                        row["Weight"] = String(format: "%.2f", heaviestSet.weight)
                    }
                case let .accessory(name, sets, reps, lastLog):
                    row["Name"] = name
                    row["Type"] = "accessory"
                    row["Sets"] = String(sets)
                    row["Reps per set"] = String(reps)
                    if let log = lastLog {
                        row["Weight"] = String(format: "%.2f", log.weight)
                    }
                case let .linear(name, info):
                    row["Name"] = name
                    row["Type"] = "linear"
                    row["Sets"] = String(info.sets)
                    row["Reps per set"] = String(info.reps)
                    row["Weight"] = String(format: "%.2f", info.weight)
                    row["Increment"] = String(format: "%.2f", info.increment)
                    row["Consecutive Failures"] = String(info.consecutiveFailures)
                }
                rows.append(row)
            }
        }
        // Determine all fieldnames
        let fieldnames: [String] = Array(Set(rows.flatMap { $0.keys })).sorted()
        // Build CSV text
        var lines: [String] = []
        lines.append(fieldnames.joined(separator: ","))
        for r in rows {
            let vals = fieldnames.map { key -> String in
                if let v = r[key] {
                    return escapeCSV(v)
                } else {
                    return ""
                }
            }
            lines.append(vals.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\n") || value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}



