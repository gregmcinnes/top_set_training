import Foundation

/// Parses what a user typed into a decimal-pad field.
///
/// `Double("102,5")` returns nil, but the decimal pad types a comma in many
/// locales, so every numeric text field must parse through here. Accepts either
/// separator regardless of locale and rejects NaN/infinity, which `Double(_:)`
/// would otherwise accept from text such as "nan" or "1e999".
public func parseDecimalInput(_ text: String) -> Double? {
    let normalized = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: ".")
    guard let value = Double(normalized), value.isFinite else { return nil }
    return value
}

/// What a key on the weight pad does to the text so far. Input stays something
/// `parseDecimalInput` accepts: one separator, two decimals and four whole digits at most.
public enum WeightPadInput {
    public static func appending(digit: Int, to text: String) -> String {
        if text == "0" { return "\(digit)" }
        let parts = text.split(whereSeparator: isSeparator).map(String.init)
        if text.contains(where: isSeparator) {
            return (parts.count > 1 ? parts[1].count : 0) >= 2 ? text : text + "\(digit)"
        }
        return text.count >= 4 ? text : text + "\(digit)"
    }

    public static func appendingSeparator(_ separator: String, to text: String) -> String {
        if text.contains(where: isSeparator) { return text }
        return (text.isEmpty ? "0" : text) + separator
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == "." || character == ","
    }
}

private let poundsPerKilogram = 1.0 / 0.45359237

public extension Double {
    /// Text for a weight field: weights are stored in pounds but typed in the user's unit
    func weightInputText(useMetric: Bool) -> String {
        String(format: "%.1f", useMetric ? self / poundsPerKilogram : self)
    }

    /// The stored pounds for a value typed in the user's unit
    func poundsFromInput(useMetric: Bool) -> Double {
        useMetric ? self * poundsPerKilogram : self
    }
}
