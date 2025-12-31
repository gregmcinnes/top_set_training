import SwiftUI

// MARK: - Training Max Card

struct TMCard: View {
    let name: String
    let trainingMax: Double
    let topSingleAt8: Double
    let useMetric: Bool
    var barWeight: Double = 45
    var showPlateCalculator: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            // Header
            HStack {
                Text(name)
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Spacer()
                
                Text("TM")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(SBSColors.backgroundFallback)
                    )
            }
            
            // Values
            HStack(spacing: SBSLayout.paddingLarge) {
                // Training Max
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training Max")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                    
                    Text(trainingMax.formattedWeight(useMetric: useMetric))
                        .font(SBSFonts.weight())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                }
                
                Divider()
                    .frame(height: 40)
                
                // Top Single @8
                VStack(alignment: .leading, spacing: 2) {
                    Text("Single @8")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                    
                    Text(topSingleAt8.formattedWeight(useMetric: useMetric))
                        .font(SBSFonts.weight())
                        .foregroundStyle(SBSColors.accentFallback)
                }
                
                Spacer()
            }
            
            // Plate calculator for single @8
            if showPlateCalculator && topSingleAt8 >= barWeight {
                PlateListView(weight: topSingleAt8, barWeight: barWeight, useMetric: useMetric)
            }
        }
        .padding(SBSLayout.paddingMedium)
        .sbsCard()
    }
}

// MARK: - Volume Card

struct VolumeCard: View {
    let name: String
    let weight: Double
    let sets: Int
    let repsPerSet: Int
    let repOutTarget: Int
    let loggedReps: Int?
    let tmDelta: Double?
    let useMetric: Bool
    var barWeight: Double = 45
    var showPlateCalculator: Bool = true
    var isWeightOverridden: Bool = false
    var calculatedWeight: Double? = nil
    var loggedNote: String? = nil
    var intensity: Double? = nil  // Percentage of training max (0.0-1.0)
    let onLogTap: () -> Void
    var onWeightTap: (() -> Void)? = nil
    
    private var hasNote: Bool {
        guard let note = loggedNote else { return false }
        return !note.isEmpty
    }
    
    private var intensityBadgeText: String {
        guard let intensity = intensity, intensity > 0 else {
            return "VOLUME"
        }
        let percentage = Int(round(intensity * 100))
        return "\(percentage)% TM"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            // Header
            HStack {
                Text(name)
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Spacer()
                
                Text(intensityBadgeText)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.accentFallback)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(SBSColors.accentFallback.opacity(0.15))
                    )
            }
            
            // Prescription
            HStack(alignment: .bottom, spacing: SBSLayout.paddingSmall) {
                // Sets x Reps
                Text("\(sets) × \(repsPerSet)")
                    .font(SBSFonts.weightLarge())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("@")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                // Weight (tappable)
                Button(action: { onWeightTap?() }) {
                    HStack(spacing: 4) {
                        Text(weight.formattedWeight(useMetric: useMetric))
                            .font(SBSFonts.weightLarge())
                            .foregroundStyle(isWeightOverridden ? SBSColors.warning : SBSColors.accentFallback)
                        
                        if isWeightOverridden {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(SBSColors.warning)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            
            // Show original weight if overridden
            if isWeightOverridden, let calculated = calculatedWeight {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.system(size: 10))
                    Text("Recommended: \(calculated.formattedWeight(useMetric: useMetric))")
                        .font(SBSFonts.caption())
                }
                .foregroundStyle(SBSColors.textTertiaryFallback)
            }
            
            // Plate Calculator (compact)
            if showPlateCalculator && weight >= barWeight {
                PlateListView(weight: weight, barWeight: barWeight, useMetric: useMetric)
            }
            
            // Note preview (if present)
            if hasNote, let note = loggedNote {
                NotePreview(note: note)
            }
            
            Divider()
            
            // Rep-out target and logging
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rep-out Target")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.system(size: 14))
                        Text("\(repOutTarget)+ reps")
                            .font(SBSFonts.bodyBold())
                        
                        // Note indicator
                        if hasNote {
                            Image(systemName: "note.text")
                                .font(.system(size: 12))
                                .foregroundStyle(SBSColors.accentSecondaryFallback)
                        }
                    }
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
                
                // Log button
                LogButton(
                    loggedReps: loggedReps,
                    tmDelta: tmDelta,
                    onTap: onLogTap
                )
            }
        }
        .padding(SBSLayout.paddingMedium)
        .sbsCard()
    }
}

// MARK: - Log Button

struct LogButton: View {
    let loggedReps: Int?
    let tmDelta: Double?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let reps = loggedReps {
                    // Logged state
                    Text("\(reps)")
                        .font(SBSFonts.weight())
                        .foregroundStyle(.white)
                    
                    if let delta = tmDelta {
                        Text(deltaText(delta))
                            .font(SBSFonts.caption())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                } else {
                    // Not logged state
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    Text("Log")
                        .font(SBSFonts.caption())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 72, height: 72)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(loggedReps != nil ? SBSColors.success : SBSColors.accentFallback)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func deltaText(_ delta: Double) -> String {
        let pct = delta * 100
        if pct >= 0 {
            return "+\(String(format: "%.1f", pct))%"
        } else {
            return "\(String(format: "%.1f", pct))%"
        }
    }
}

// MARK: - Note Preview

struct NotePreview: View {
    let note: String
    @State private var isExpanded: Bool = false
    
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: SBSLayout.paddingSmall) {
                Image(systemName: "note.text")
                    .font(.system(size: 12))
                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                
                Text(note)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                if note.count > 60 {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
            }
            .padding(SBSLayout.paddingSmall)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .fill(SBSColors.accentSecondaryFallback.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Structured Card

struct StructuredCard: View {
    let name: String
    let lift: String
    let trainingMax: Double
    let sets: [StructuredSetInfo]
    let logEntry: StructuredLogEntry?
    let useMetric: Bool
    var barWeight: Double = 45
    var showPlateCalculator: Bool = true
    let onSetTap: (Int) -> Void  // Called with set index for AMRAP sets
    
    /// Find the "1+" set (usually the heavy single) - this is the primary AMRAP
    private var primaryAMRAPIndex: Int? {
        sets.first { $0.isAMRAP && $0.targetReps == 1 }?.setIndex
    }
    
    /// Check if all AMRAP sets are logged
    private var isFullyLogged: Bool {
        let amrapSets = sets.filter { $0.isAMRAP }
        guard !amrapSets.isEmpty else { return false }
        return amrapSets.allSatisfy { $0.loggedReps != nil }
    }
    
    /// Get the 1+ set reps (for display)
    private var onePlusReps: Int? {
        guard let index = primaryAMRAPIndex else { return nil }
        return sets[index].loggedReps
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            // Header
            HStack {
                Text(name)
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Spacer()
                
                Text("TM: \(trainingMax.formattedWeight(useMetric: useMetric))")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(SBSColors.warning.opacity(0.15))
                    )
            }
            
            // Sets grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(sets, id: \.setIndex) { setInfo in
                    StructuredSetCell(
                        setInfo: setInfo,
                        useMetric: useMetric,
                        onTap: {
                            if setInfo.isAMRAP {
                                onSetTap(setInfo.setIndex)
                            }
                        }
                    )
                }
            }
            
            // Plate calculator for heaviest set (usually set index 2, the 1+ set)
            if showPlateCalculator, let heaviestSet = sets.max(by: { $0.weight < $1.weight }) {
                if heaviestSet.weight >= barWeight {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Heavy single plates:")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                        
                        PlateListView(weight: heaviestSet.weight, barWeight: barWeight, useMetric: useMetric)
                    }
                }
            }
            
            // Status indicator
            HStack {
                if isFullyLogged {
                    Label("All AMRAP sets logged", systemImage: "checkmark.circle.fill")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.success)
                } else if let reps = onePlusReps {
                    Label("1+ set: \(reps) reps", systemImage: "flame.fill")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.warning)
                } else {
                    Label("Tap AMRAP sets to log reps", systemImage: "hand.tap")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                
                Spacer()
            }
        }
        .padding(SBSLayout.paddingMedium)
        .sbsCard()
    }
}

// MARK: - Structured Set Cell

struct StructuredSetCell: View {
    let setInfo: StructuredSetInfo
    let useMetric: Bool
    let onTap: () -> Void
    
    private var intensityText: String {
        "\(Int(setInfo.intensity * 100))%"
    }
    
    private var repsText: String {
        if setInfo.isAMRAP {
            return "\(setInfo.targetReps)+"
        }
        return "\(setInfo.targetReps)"
    }
    
    private var isLogged: Bool {
        setInfo.isAMRAP && setInfo.loggedReps != nil
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Weight
                Text(setInfo.weight.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(isLogged ? .white : (setInfo.isAMRAP ? SBSColors.warning : SBSColors.textPrimaryFallback))
                
                // Reps (or logged reps for AMRAP)
                if let logged = setInfo.loggedReps {
                    Text("\(logged) reps")
                        .font(SBSFonts.caption())
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Text("× \(repsText)")
                        .font(SBSFonts.caption())
                        .foregroundStyle(setInfo.isAMRAP ? SBSColors.warning : SBSColors.textSecondaryFallback)
                }
                
                // Intensity indicator
                Text(intensityText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isLogged ? .white.opacity(0.7) : SBSColors.textTertiaryFallback)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .strokeBorder(borderColor, lineWidth: setInfo.isAMRAP ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(!setInfo.isAMRAP)
    }
    
    private var backgroundColor: Color {
        if isLogged {
            return SBSColors.success
        } else if setInfo.isAMRAP {
            return SBSColors.warning.opacity(0.1)
        } else {
            return SBSColors.surfaceFallback
        }
    }
    
    private var borderColor: Color {
        if isLogged {
            return .clear
        } else if setInfo.isAMRAP {
            return SBSColors.warning.opacity(0.5)
        } else {
            return .clear
        }
    }
}

// MARK: - Accessory Card

struct AccessoryCard: View {
    let name: String
    let sets: Int
    let reps: Int
    let lastLog: AccessoryLog?
    let useMetric: Bool
    let onLogTap: () -> Void
    
    private var hasNote: Bool {
        guard let note = lastLog?.note else { return false }
        return !note.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            // Header
            HStack {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                Text(name)
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                // Note indicator
                if hasNote {
                    Image(systemName: "note.text")
                        .font(.system(size: 12))
                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                }
                
                Spacer()
                
                Text("ACCESSORY")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(SBSColors.backgroundFallback)
                    )
            }
            
            // Prescription and weight log
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Sets x Reps
                    Text("\(sets) × \(reps)")
                        .font(SBSFonts.weight())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    // Last weight used
                    if let log = lastLog {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12))
                            Text("Last: \(log.weight.formattedWeightShort(useMetric: useMetric))")
                                .font(SBSFonts.caption())
                        }
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                    } else {
                        Text("No weight logged")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                }
                
                Spacer()
                
                // Log button
                AccessoryLogButton(
                    lastLog: lastLog,
                    useMetric: useMetric,
                    onTap: onLogTap
                )
            }
            
            // Note preview (if present)
            if hasNote, let note = lastLog?.note {
                NotePreview(note: note)
            }
        }
        .padding(SBSLayout.paddingMedium)
        .sbsCard()
    }
}

// MARK: - Accessory Log Button

struct AccessoryLogButton: View {
    let lastLog: AccessoryLog?
    let useMetric: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let log = lastLog {
                    // Logged state - show weight
                    Text(log.weight.formattedWeightShort(useMetric: useMetric))
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(.white)
                    
                    Text("Edit")
                        .font(SBSFonts.caption())
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    // Not logged state
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    Text("Log")
                        .font(SBSFonts.caption())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 64, height: 56)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(lastLog != nil ? SBSColors.accentSecondaryFallback : SBSColors.surfaceFallback)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Linear Card (StrongLifts-style)

struct LinearCard: View {
    let name: String
    let info: LinearExerciseInfo
    let useMetric: Bool
    var barWeight: Double = 45
    var showPlateCalculator: Bool = true
    let onLogTap: () -> Void
    
    private var isLogged: Bool {
        info.logEntry != nil
    }
    
    private var wasSuccessful: Bool {
        info.logEntry?.completed ?? false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            // Header
            HStack {
                Text(name)
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Spacer()
                
                Text("TM: \(info.weight.formattedWeight(useMetric: useMetric))")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.accentFallback)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(SBSColors.accentFallback.opacity(0.15))
                    )
            }
            
            // Prescription
            HStack(alignment: .bottom, spacing: SBSLayout.paddingSmall) {
                // Sets x Reps
                Text("\(info.sets) × \(info.reps)")
                    .font(SBSFonts.weightLarge())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("@")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                // Weight
                Text(info.weight.formattedWeight(useMetric: useMetric))
                    .font(SBSFonts.weightLarge())
                    .foregroundStyle(SBSColors.accentFallback)
                
                Spacer()
            }
            
            // Plate calculator
            if showPlateCalculator && info.weight >= barWeight {
                PlateListView(weight: info.weight, barWeight: barWeight, useMetric: useMetric)
            }
            
            // Failure warning if applicable
            if info.isDeloadPending && !isLogged {
                HStack(spacing: SBSLayout.paddingSmall) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    
                    Text("Deload pending (\(info.consecutiveFailures) failures)")
                        .font(SBSFonts.caption())
                }
                .foregroundStyle(SBSColors.warning)
                .padding(.horizontal, SBSLayout.paddingMedium)
                .padding(.vertical, SBSLayout.paddingSmall)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                        .fill(SBSColors.warning.opacity(0.1))
                )
            }
            
            Divider()
            
            // Progression info and log button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next Session")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("+\(info.increment.formattedWeight(useMetric: useMetric)) on success")
                            .font(SBSFonts.caption())
                    }
                    .foregroundStyle(SBSColors.success)
                }
                
                Spacer()
                
                // Log button
                LinearLogButton(
                    isLogged: isLogged,
                    wasSuccessful: wasSuccessful,
                    onTap: onLogTap
                )
            }
        }
        .padding(SBSLayout.paddingMedium)
        .sbsCard()
    }
}

// MARK: - Linear Log Button

struct LinearLogButton: View {
    let isLogged: Bool
    let wasSuccessful: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if isLogged {
                    // Logged state
                    Image(systemName: wasSuccessful ? "checkmark" : "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text(wasSuccessful ? "Done" : "Failed")
                        .font(SBSFonts.caption())
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    // Not logged state
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    Text("Log")
                        .font(SBSFonts.caption())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 72, height: 72)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(buttonColor)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var buttonColor: Color {
        if isLogged {
            return wasSuccessful ? SBSColors.success : SBSColors.error
        }
        return SBSColors.accentFallback
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            TMCard(
                name: "Squat TM",
                trainingMax: 172,
                topSingleAt8: 155,
                useMetric: false
            )
            
            VolumeCard(
                name: "Squat",
                weight: 130,
                sets: 4,
                repsPerSet: 8,
                repOutTarget: 10,
                loggedReps: nil,
                tmDelta: nil,
                useMetric: false,
                onLogTap: {},
                onWeightTap: {}
            )
            
            VolumeCard(
                name: "Push Press (Overridden)",
                weight: 90,
                sets: 4,
                repsPerSet: 12,
                repOutTarget: 15,
                loggedReps: 17,
                tmDelta: 0.01,
                useMetric: false,
                isWeightOverridden: true,
                calculatedWeight: 85,
                onLogTap: {},
                onWeightTap: {}
            )
            
            AccessoryCard(
                name: "Cable Rows",
                sets: 4,
                reps: 10,
                lastLog: AccessoryLog(weight: 120, sets: 4, reps: 10),
                useMetric: false,
                onLogTap: {}
            )
            AccessoryCard(
                name: "EZ Bar Curls",
                sets: 4,
                reps: 10,
                lastLog: nil,
                useMetric: false,
                onLogTap: {}
            )
        }
        .padding()
    }
    .sbsBackground()
}

