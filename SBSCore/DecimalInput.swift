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
