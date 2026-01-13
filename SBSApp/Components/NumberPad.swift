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
    
    /// Calculate weight adjustment based on reps performed vs target
    /// Matches the structuredProgression function in ProgramEngine
    func weightAdjustment(reps: Int, target: Int) -> Double {
        // nSuns-style 1+ sets use different progression rules
        // Requires minimum 2 reps to progress, same for all lifts
        if target == 1 {
            if reps <= 1 { return 0.0 }    // 0-1 reps = stall
            if reps <= 4 { return 5.0 }    // 2-4 reps = +5 lbs
            return 10.0                     // 5+ reps = +10 lbs
        }
        
        // Standard structured progression (Greyskull, GZCLP)
        let diff = reps - target
        
        if isUpperBody {
            switch diff {
            case ...(-1): return -5.0  // Miss target = -5 lbs
            case 0: return 0.0         // Hit exact = no change
            case 1, 2: return 5.0      // 1-2 over = +5 lbs
            default: return 10.0       // 3+ over = +10 lbs
            }
        } else {
            // Lower body - more aggressive progression
            switch diff {
            case ...(-1): return 0.0   // Miss = stall (no reduction for lower)
            case 0: return 5.0         // Hit exact = +5 lbs
            case 1, 2: return 10.0     // 1-2 over = +10 lbs
            default: return 15.0       // 3+ over = +15 lbs
            }
        }
    }
}

struct NumberPad: View {
    @Binding var value: Int?
    let target: Int
    let structuredContext: StructuredProgressionContext?  // nil = use percentage display
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            // Display with target indicator - more compact
            HStack(spacing: SBSLayout.paddingMedium) {
                ZStack {
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .fill(SBSColors.surfaceFallback)
                        .frame(height: 64)
                    
                    if let v = value {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Text("\(v)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(displayColor)
                            
                            Text("reps")
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                }
                
                // TM Impact and Target in side column
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target: \(target)")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                    
                    if let v = value {
                        TMImpactPreviewCompact(reps: v, target: target, structuredContext: structuredContext)
                    }
                }
                .frame(minWidth: 100)
            }
            
            // Number pad (calculator style) - more compact
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...9, id: \.self) { num in
                    NumberPadKey(digit: num) {
                        appendDigit(num)
                    }
                }
                
                // Clear/backspace button
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if let current = value, current >= 10 {
                            value = current / 10
                        } else {
                            value = nil
                        }
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .buttonStyle(NumberPadKeyStyle())
                
                // Zero
                NumberPadKey(digit: 0) {
                    appendDigit(0)
                }
                
                // Confirm checkmark
                Button {
                    if value != nil {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onConfirm()
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(value != nil ? SBSColors.success : SBSColors.textTertiaryFallback)
                }
                .buttonStyle(NumberPadKeyStyle(isAccent: value != nil))
                .disabled(value == nil)
            }
        }
        .padding(.horizontal, SBSLayout.paddingLarge)
        .padding(.vertical, SBSLayout.paddingMedium)
    }
    
    private var displayColor: Color {
        guard let v = value else { return SBSColors.textPrimaryFallback }
        let diff = v - target
        if diff >= 0 {
            return SBSColors.success
        } else if diff == -1 {
            return SBSColors.warning
        } else {
            return SBSColors.error
        }
    }
    
    private func appendDigit(_ digit: Int) {
        withAnimation(.easeInOut(duration: 0.15)) {
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

// MARK: - Number Pad Key

struct NumberPadKey: View {
    let digit: Int
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text("\(digit)")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(SBSColors.textPrimaryFallback)
        }
        .buttonStyle(NumberPadKeyStyle())
    }
}

// MARK: - Number Pad Key Style

struct NumberPadKeyStyle: ButtonStyle {
    var isAccent: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(isAccent ? SBSColors.success.opacity(0.15) : SBSColors.surfaceFallback)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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
                .font(.system(size: 12, weight: .semibold))
            
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
                return "+\(Int(deltaWeight)) \(unit)"
            } else if deltaWeight < 0 {
                return "\(Int(deltaWeight)) \(unit)"
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
            return hitTarget ? SBSColors.success : SBSColors.error
        }
        
        if effectiveDelta > 0 {
            return SBSColors.success
        } else if effectiveDelta < 0 {
            return SBSColors.error
        } else {
            return SBSColors.textSecondaryFallback
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
        HStack(spacing: SBSLayout.paddingSmall) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
            
            Text(impactText)
                .font(SBSFonts.captionBold())
        }
        .foregroundStyle(impactColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(impactColor.opacity(0.12))
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
                return "Next: +\(Int(deltaWeight)) \(unit)"
            } else if deltaWeight < 0 {
                return "Next: \(Int(deltaWeight)) \(unit)"
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
            return hitTarget ? SBSColors.success : SBSColors.error
        }
        
        if effectiveDelta > 0 {
            return SBSColors.success
        } else if effectiveDelta < 0 {
            return SBSColors.error
        } else {
            return SBSColors.textSecondaryFallback
        }
    }
}

#Preview {
    NumberPad(
        value: .constant(12),
        target: 10,
        structuredContext: nil,  // nil = percentage display (SBS style)
        onConfirm: {},
        onCancel: {}
    )
    .sbsBackground()
}

