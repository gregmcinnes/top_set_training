import SwiftUI

struct DayCard: View {
    let day: Int
    let title: String
    let lifts: [String]
    let logStatus: DayLogStatus
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SBSLayout.paddingMedium) {
                // Day number badge
                DayBadge(day: day, status: logStatus, isSelected: isSelected)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text(lifts.joined(separator: " • "))
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Status indicator
                LogStatusBadge(status: logStatus)
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
            .padding(SBSLayout.paddingMedium)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(isSelected ? SBSColors.surfaceElevatedFallback : SBSColors.surfaceFallback)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .strokeBorder(
                        isSelected ? SBSColors.accentFallback : .clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: .black.opacity(isSelected ? 0.15 : 0.08),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 4 : 2
            )
        }
        .buttonStyle(.plain)
    }
}

struct DayBadge: View {
    let day: Int
    let status: DayLogStatus
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 44, height: 44)
            
            Text("\(day)")
                .font(SBSFonts.title3())
                .foregroundStyle(foregroundColor)
        }
    }
    
    private var backgroundColor: Color {
        switch status {
        case .complete:
            return SBSColors.success.opacity(0.15)
        case .partial:
            return SBSColors.warning.opacity(0.15)
        case .notStarted:
            return isSelected ? SBSColors.accentFallback.opacity(0.15) : SBSColors.backgroundFallback
        }
    }
    
    private var foregroundColor: Color {
        switch status {
        case .complete:
            return SBSColors.success
        case .partial:
            return SBSColors.warning
        case .notStarted:
            return isSelected ? SBSColors.accentFallback : SBSColors.textSecondaryFallback
        }
    }
}

struct LogStatusBadge: View {
    let status: DayLogStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
            
            Text(statusText)
                .font(SBSFonts.caption())
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.12))
        )
    }
    
    private var iconName: String {
        switch status {
        case .complete: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .notStarted: return "circle"
        }
    }
    
    private var statusText: String {
        switch status {
        case .complete: return "Done"
        case .partial: return "Partial"
        case .notStarted: return "To Do"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .complete: return SBSColors.success
        case .partial: return SBSColors.warning
        case .notStarted: return SBSColors.textTertiaryFallback
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        DayCard(
            day: 1,
            title: "Squat Day",
            lifts: ["Squat", "Push Press"],
            logStatus: .complete,
            isSelected: false,
            onTap: {}
        )
        
        DayCard(
            day: 2,
            title: "Bench Day",
            lifts: ["Bench Press", "Front Squat"],
            logStatus: .partial,
            isSelected: true,
            onTap: {}
        )
        
        DayCard(
            day: 3,
            title: "Deadlift Day",
            lifts: ["Trap Bar Deadlift", "Incline Press"],
            logStatus: .notStarted,
            isSelected: false,
            onTap: {}
        )
    }
    .padding()
    .sbsBackground()
}

