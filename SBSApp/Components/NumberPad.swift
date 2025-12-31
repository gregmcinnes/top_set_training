import SwiftUI

struct NumberPad: View {
    @Binding var value: Int?
    let target: Int
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
                        TMImpactPreviewCompact(reps: v, target: target)
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
    
    private var diff: Int { reps - target }
    
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
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
            
            Text(impactText)
                .font(SBSFonts.caption())
        }
        .foregroundStyle(impactColor)
    }
    
    private var iconName: String {
        if deltaPercent > 0 {
            return "arrow.up"
        } else if deltaPercent < 0 {
            return "arrow.down"
        } else {
            return "equal"
        }
    }
    
    private var impactText: String {
        if deltaPercent > 0 {
            return "+\(String(format: "%.1f", deltaPercent))%"
        } else if deltaPercent < 0 {
            return "\(String(format: "%.1f", deltaPercent))%"
        } else {
            return "No Δ"
        }
    }
    
    private var impactColor: Color {
        if deltaPercent > 0 {
            return SBSColors.success
        } else if deltaPercent < 0 {
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
    
    private var diff: Int { reps - target }
    
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
    
    private var iconName: String {
        if deltaPercent > 0 {
            return "arrow.up.circle.fill"
        } else if deltaPercent < 0 {
            return "arrow.down.circle.fill"
        } else {
            return "equal.circle.fill"
        }
    }
    
    private var impactText: String {
        if deltaPercent > 0 {
            return "Next TM: +\(String(format: "%.1f", deltaPercent))%"
        } else if deltaPercent < 0 {
            return "Next TM: \(String(format: "%.1f", deltaPercent))%"
        } else {
            return "Next TM: No change"
        }
    }
    
    private var impactColor: Color {
        if deltaPercent > 0 {
            return SBSColors.success
        } else if deltaPercent < 0 {
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
        onConfirm: {},
        onCancel: {}
    )
    .sbsBackground()
}

