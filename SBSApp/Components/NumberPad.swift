import SwiftUI

/// Context for structured progression (Greyskull, GZCLP, etc.)
/// When provided, shows weight changes instead of percentage changes
struct StructuredProgressionContext {
    let liftName: String
    let useMetric: Bool
    /// If true, AMRAP doesn't auto-adjust TMs (e.g., 5/3/1) - just show hit/miss
    let manualProgression: Bool
    
    init(liftName: String, useMetric: Bool, manualProgression: Bool = false) {
        self.liftName = liftName
        self.useMetric = useMetric
        self.manualProgression = manualProgression
    }
    
    /// Determine if the lift is upper body based on name
    var isUpperBody: Bool {
        let lowerBodyKeywords = ["squat", "deadlift", "leg", "lunge", "hip"]
        let lowercased = liftName.lowercased()
        return !lowerBodyKeywords.contains { lowercased.contains($0) }
    }
    
    /// The change the engine will apply, in the user's unit. Calls the engine so the
    /// preview can't drift from what progression actually does.
    func weightAdjustment(reps: Int, target: Int) -> Double {
        let pounds = ProgramEngine().structuredProgression(
            repsOnOnePlus: reps,
            targetReps: target,
            isUpperBody: isUpperBody
        )
        return useMetric ? pounds / 2.0 : pounds  // Metric: +5/+10/+15 lb becomes +2.5/+5/+7.5 kg
    }
}

struct NumberPad: View {
    @Binding var value: Int?
    let target: Int
    let structuredContext: StructuredProgressionContext?  // nil = use percentage display
    var prRepsNeeded: Int? = nil  // reps that would set a new E1RM PR; nil = no hint
    let onConfirm: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: SBSLayout.space2), count: 3)
    
    var body: some View {
        VStack(spacing: SBSLayout.space3) {
            // Readout: one big number, then what it does to the program
            VStack(spacing: SBSLayout.space1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value.map(String.init) ?? "—")
                        .font(SBSFonts.timer())
                        .foregroundStyle(value == nil ? Color.inkTertiary : Color.ink)
                        .lineLimit(1)
                    Text("reps")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reps")
                .accessibilityValue(value.map { "\($0)" } ?? "Empty")

                HStack(spacing: SBSLayout.space2) {
                    Text("Target \(target)")
                        .foregroundStyle(Color.inkSecondary)

                    if let v = value {
                        TMImpactPreviewCompact(reps: v, target: target, structuredContext: structuredContext)
                    }

                    if let needed = prRepsNeeded {
                        if let v = value, v >= needed {
                            Label("New 1RM", systemImage: "trophy")
                                .foregroundStyle(Color.success)
                        } else {
                            Text("\(needed) = new 1RM")
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }
                }
                .font(SBSFonts.caption())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)

            LazyVGrid(columns: columns, spacing: SBSLayout.space2) {
                ForEach(1...9, id: \.self) { num in
                    NumberPadKey(digit: num) {
                        appendDigit(num)
                    }
                }
                
                // Clear/backspace button
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        if let current = value, current >= 10 {
                            value = current / 10
                        } else {
                            value = nil
                        }
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "delete.left")
                        .font(SBSFonts.bodyStrong())
                }
                .buttonStyle(SBSNumberPadButtonStyle())
                .accessibilityLabel("Delete")

                NumberPadKey(digit: 0) {
                    appendDigit(0)
                }
                
                // Log: the one orange key, a primary button in miniature without the shadow
                Button {
                    if value != nil {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onConfirm()
                    }
                } label: {
                    NumberPadCommitLabel(title: "Log", accessibilityLabel: "Confirm reps")
                }
                .buttonStyle(SBSNumberPadButtonStyle(isHighlighted: true))
                .disabled(value == nil)
            }
        }
        .padding(SBSLayout.space4)
        .numberPadPanel()
        .padding(.horizontal, SBSLayout.space4)
        .padding(.vertical, SBSLayout.space3)
    }
    
    private func appendDigit(_ digit: Int) {
        withAnimation(.easeOut(duration: 0.15)) {
            if let current = value {
                let newValue = current * 10 + digit
                value = min(newValue, 99) // Cap at 99
            } else {
                value = digit
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Weight Pad

/// The number pad for weights: a decimal key where the reps pad has delete, and the
/// commit key in the same place. What counts as a valid weight is the caller's, because
/// 0 is a real value for some inputs and means unset for others.
struct WeightPad: View {
    @Binding var text: String
    let useMetric: Bool
    let canConfirm: Bool
    let onConfirm: () -> Void

    /// Text this pad last typed. Anything else was prefilled or set by a quick button, and
    /// the first key replaces it rather than adding digits to the end of "135.0".
    @State private var typedText: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: SBSLayout.space2), count: 3)

    private var editableText: String {
        text == typedText ? text : ""
    }

    var body: some View {
        VStack(spacing: SBSLayout.space3) {
            HStack(spacing: SBSLayout.space2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(text.isEmpty ? "—" : text)
                        .font(SBSFonts.timer())
                        .foregroundStyle(text.isEmpty ? Color.inkTertiary : Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(useMetric ? "kg" : "lb")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weight")
                .accessibilityValue(text.isEmpty ? "Empty" : "\(text) \(useMetric ? "kilograms" : "pounds")")

                Button {
                    type(String(text.dropLast()))
                } label: {
                    Image(systemName: "delete.left")
                        .font(SBSFonts.bodyStrong())
                }
                .buttonStyle(SBSNumberPadButtonStyle())
                .frame(width: 88)
                .accessibilityLabel("Delete")
            }

            LazyVGrid(columns: columns, spacing: SBSLayout.space2) {
                ForEach(1...9, id: \.self) { digit in
                    NumberPadKey(digit: digit) {
                        type(WeightPadInput.appending(digit: digit, to: editableText))
                    }
                }

                Button {
                    type(WeightPadInput.appendingSeparator(decimalSeparator, to: editableText))
                } label: {
                    Text(decimalSeparator)
                }
                .buttonStyle(SBSNumberPadButtonStyle())
                .accessibilityLabel("Decimal point")

                NumberPadKey(digit: 0) {
                    type(WeightPadInput.appending(digit: 0, to: editableText))
                }

                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onConfirm()
                } label: {
                    NumberPadCommitLabel(title: "Save", accessibilityLabel: "Save weight")
                }
                .buttonStyle(SBSNumberPadButtonStyle(isHighlighted: true))
                .disabled(!canConfirm)
            }
        }
        .padding(SBSLayout.space4)
        .numberPadPanel()
        .padding(.horizontal, SBSLayout.space4)
        .padding(.vertical, SBSLayout.space3)
    }

    private var decimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    private func type(_ newText: String) {
        text = newText
        typedText = newText
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Number Pad Key

struct NumberPadKey: View {
    let digit: Int
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text("\(digit)")
        }
        .buttonStyle(SBSNumberPadButtonStyle())
    }
}

/// The commit key's label: button type in capitals, the words as written for VoiceOver
private struct NumberPadCommitLabel: View {
    let title: String
    let accessibilityLabel: String

    var body: some View {
        SBSButtonTitle(title, accessibilityLabel: accessibilityLabel)
            .font(SBSFonts.button())
            .tracking(1.2)
    }
}

extension View {
    /// The pad's panel: surface-raised with the sheet radius and a hairline
    fileprivate func numberPadPanel() -> some View {
        background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: SBSLayout.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusMd)
                    .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
    }
}

// MARK: - Compact TM Impact Preview (for inline display)

struct TMImpactPreviewCompact: View {
    let reps: Int
    let target: Int
    let structuredContext: StructuredProgressionContext?  // nil = use percentage display
    
    private var diff: Int { reps - target }
    
    /// Percentage change for volume-based programs (SBS style)
    private var deltaPercent: Double {
        if diff <= -2 { return -5.0 }
        if diff == -1 { return -2.0 }
        if diff == 0 { return 0.0 }
        if diff == 1 { return 0.5 }
        if diff == 2 { return 1.0 }
        if diff == 3 { return 1.5 }
        if diff == 4 { return 2.0 }
        return 3.0 // 5+
    }
    
    /// Weight change for structured programs (Greyskull, GZCLP style)
    private var deltaWeight: Double {
        guard let context = structuredContext else { return 0 }
        return context.weightAdjustment(reps: reps, target: target)
    }
    
    /// The effective delta value for determining direction (positive/negative/zero)
    private var effectiveDelta: Double {
        if structuredContext != nil {
            return deltaWeight
        } else {
            return deltaPercent
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(SBSFonts.caption().weight(.semibold))
            
            Text(impactText)
                .font(SBSFonts.caption())
        }
        .foregroundStyle(impactColor)
    }
    
    /// For manual progression programs (like 5/3/1), just check if target was hit
    private var hitTarget: Bool {
        return reps >= target
    }
    
    private var iconName: String {
        // Manual progression - just show hit/miss
        if let context = structuredContext, context.manualProgression {
            return hitTarget ? "checkmark" : "xmark"
        }
        
        if effectiveDelta > 0 {
            return "arrow.up"
        } else if effectiveDelta < 0 {
            return "arrow.down"
        } else {
            return "equal"
        }
    }
    
    private var impactText: String {
        // Manual progression (5/3/1) - just show hit/miss status
        if let context = structuredContext, context.manualProgression {
            return hitTarget ? "Target hit" : "Missed"
        }
        
        if let context = structuredContext {
            // Structured progression - show weight change
            let unit = context.useMetric ? "kg" : "lb"
            if deltaWeight > 0 {
                return "+\(String(format: "%g", deltaWeight)) \(unit)"
            } else if deltaWeight < 0 {
                return "\(String(format: "%g", deltaWeight)) \(unit)"
            } else {
                return "No Δ"
            }
        } else {
            // Volume-based progression - show percentage
            if deltaPercent > 0 {
                return "+\(String(format: "%.1f", deltaPercent))%"
            } else if deltaPercent < 0 {
                return "\(String(format: "%.1f", deltaPercent))%"
            } else {
                return "No Δ"
            }
        }
    }
    
    private var impactColor: Color {
        // Manual progression - just show hit/miss colors
        if let context = structuredContext, context.manualProgression {
            return hitTarget ? Color.success : Color.warning
        }
        
        if effectiveDelta > 0 {
            return Color.success
        } else if effectiveDelta < 0 {
            return Color.warning
        } else {
            return Color.inkSecondary
        }
    }
}

// MARK: - Full TM Impact Preview

struct TMImpactPreview: View {
    let reps: Int
    let target: Int
    let structuredContext: StructuredProgressionContext?  // nil = use percentage display
    
    private var diff: Int { reps - target }
    
    /// Percentage change for volume-based programs (SBS style)
    private var deltaPercent: Double {
        if diff <= -2 { return -5.0 }
        if diff == -1 { return -2.0 }
        if diff == 0 { return 0.0 }
        if diff == 1 { return 0.5 }
        if diff == 2 { return 1.0 }
        if diff == 3 { return 1.5 }
        if diff == 4 { return 2.0 }
        return 3.0 // 5+
    }
    
    /// Weight change for structured programs (Greyskull, GZCLP style)
    private var deltaWeight: Double {
        guard let context = structuredContext else { return 0 }
        return context.weightAdjustment(reps: reps, target: target)
    }
    
    /// The effective delta value for determining direction (positive/negative/zero)
    private var effectiveDelta: Double {
        if structuredContext != nil {
            return deltaWeight
        } else {
            return deltaPercent
        }
    }
    
    var body: some View {
        HStack(spacing: SBSLayout.space2) {
            Image(systemName: iconName)
                .font(SBSFonts.caption().weight(.semibold))
            
            Text(impactText)
                .font(SBSFonts.caption())
        }
        .foregroundStyle(impactColor)
        .padding(.horizontal, SBSLayout.space3)
        .padding(.vertical, SBSLayout.space2)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
        )
    }
    
    /// For manual progression programs (like 5/3/1), just check if target was hit
    private var hitTarget: Bool {
        return reps >= target
    }
    
    private var iconName: String {
        // Manual progression - just show hit/miss
        if let context = structuredContext, context.manualProgression {
            return hitTarget ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
        
        if effectiveDelta > 0 {
            return "arrow.up.circle.fill"
        } else if effectiveDelta < 0 {
            return "arrow.down.circle.fill"
        } else {
            return "equal.circle.fill"
        }
    }
    
    private var impactText: String {
        // Manual progression (5/3/1) - just show hit/miss status
        if let context = structuredContext, context.manualProgression {
            return hitTarget ? "Target hit!" : "Missed target"
        }
        
        if let context = structuredContext {
            // Structured progression - show weight change
            let unit = context.useMetric ? "kg" : "lb"
            if deltaWeight > 0 {
                return "Next: +\(String(format: "%g", deltaWeight)) \(unit)"
            } else if deltaWeight < 0 {
                return "Next: \(String(format: "%g", deltaWeight)) \(unit)"
            } else {
                return "Next: No change"
            }
        } else {
            // Volume-based progression - show percentage
            if deltaPercent > 0 {
                return "Next TM: +\(String(format: "%.1f", deltaPercent))%"
            } else if deltaPercent < 0 {
                return "Next TM: \(String(format: "%.1f", deltaPercent))%"
            } else {
                return "Next TM: No change"
            }
        }
    }
    
    private var impactColor: Color {
        // Manual progression - just show hit/miss colors
        if let context = structuredContext, context.manualProgression {
            return hitTarget ? Color.success : Color.warning
        }
        
        if effectiveDelta > 0 {
            return Color.success
        } else if effectiveDelta < 0 {
            return Color.warning
        } else {
            return Color.inkSecondary
        }
    }
}

#Preview {
    NumberPad(
        value: .constant(12),
        target: 10,
        structuredContext: nil,  // nil = percentage display (SBS style)
        onConfirm: {}
    )
    .sbsBackground()
}

