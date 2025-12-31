import SwiftUI

struct WeekStrip: View {
    @Binding var selectedWeek: Int
    let totalWeeks: Int
    /// Returns fraction of workouts completed for a given week (0.0 to 1.0)
    var weekCompletionFraction: ((Int) -> Double)?
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            // Week label
            Text("WEEK \(selectedWeek) OF \(totalWeeks)")
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)
                .tracking(1)
            
            // Week selector
            HStack(spacing: SBSLayout.paddingMedium) {
                // Previous button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedWeek = max(1, selectedWeek - 1)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selectedWeek > 1 ? SBSColors.accentFallback : SBSColors.textTertiaryFallback)
                        .frame(width: 44, height: 44)
                }
                .disabled(selectedWeek <= 1)
                
                // Week pills - show 5 at a time centered on selection
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(1...totalWeeks, id: \.self) { week in
                                WeekPill(
                                    week: week,
                                    isSelected: week == selectedWeek,
                                    completionFraction: weekCompletionFraction?(week) ?? 0.0
                                )
                                .id(week)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedWeek = week
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, SBSLayout.paddingSmall)
                    }
                    .onChange(of: selectedWeek) { _, newValue in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                    .onAppear {
                        proxy.scrollTo(selectedWeek, anchor: .center)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Next button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedWeek = min(totalWeeks, selectedWeek + 1)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selectedWeek < totalWeeks ? SBSColors.accentFallback : SBSColors.textTertiaryFallback)
                        .frame(width: 44, height: 44)
                }
                .disabled(selectedWeek >= totalWeeks)
            }
        }
        .padding(.vertical, SBSLayout.paddingSmall)
    }
}

struct WeekPill: View {
    let week: Int
    let isSelected: Bool
    /// Fraction of workouts completed for this week (0.0 to 1.0)
    let completionFraction: Double
    
    var body: some View {
        Text("\(week)")
            .font(SBSFonts.captionBold())
            .foregroundStyle(foregroundColor)
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(backgroundColor)
            )
            .overlay(
                Circle()
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 0)
            )
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if completionFraction >= 1.0 {
            // Fully completed week - white text for contrast with full orange
            return .white
        } else if completionFraction > 0 {
            // Partially completed - adjust based on completion (darker text as background gets lighter)
            return completionFraction > 0.5 ? .white : SBSColors.textPrimaryFallback
        } else {
            return SBSColors.textPrimaryFallback
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            // Selected week always gets full accent color
            return SBSColors.accentFallback
        } else if completionFraction >= 1.0 {
            // Fully completed - slightly muted orange to distinguish from selected
            return SBSColors.accentFallback.opacity(0.85)
        } else if completionFraction > 0 {
            // Partially completed - gradient of orange based on completion
            // Minimum opacity 0.2, max 0.7 (saving full for completed/selected)
            let opacity = 0.2 + (completionFraction * 0.5)
            return SBSColors.accentFallback.opacity(opacity)
        } else {
            // Not started - default surface color
            return SBSColors.surfaceFallback
        }
    }
    
    private var borderColor: Color {
        isSelected ? SBSColors.accentFallback.opacity(0.5) : .clear
    }
}

#Preview {
    VStack {
        WeekStrip(
            selectedWeek: .constant(5),
            totalWeeks: 20,
            weekCompletionFraction: { week in
                // Demo: show varying completion levels
                switch week {
                case 1: return 1.0      // Fully complete
                case 2: return 1.0      // Fully complete
                case 3: return 0.8      // 80% complete
                case 4: return 0.6      // 60% complete
                case 5: return 0.4      // 40% complete (selected)
                case 6: return 0.2      // 20% complete
                default: return 0.0     // Not started
                }
            }
        )
    }
    .padding()
    .sbsBackground()
}

