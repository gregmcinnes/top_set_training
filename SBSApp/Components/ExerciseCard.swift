import SwiftUI

// MARK: - Live Set Card

/// The one set the lifter is about to do, and the only card on a screen with the
/// signature treatment (2px rule, square corners, hard shadow). One per screen: the
/// current set while lifting, the next set while resting.
///
/// The card computes nothing: the caller hands it the labels, the weight and the scheme.
struct LiveSetCard: View {
    /// "Set 3 of 5 · last set", passed in sentence case
    let eyebrow: String
    /// Trailing tag on the eyebrow row: "85% TM", "Adjusted"
    var badge: String? = nil
    let weight: Double
    let useMetric: Bool
    /// "× 5", "× 5+"
    let scheme: String
    var showPlates: Bool = false
    var barWeight: Double = 45
    var onUnlockTap: (() -> Void)? = nil
    var onWeightTap: (() -> Void)? = nil
    /// A new value flashes the card orange once (a PR was just logged)
    var flashToken: UUID? = nil
    var onFlashDone: (() -> Void)? = nil

    @State private var flashOpacity: Double = 0

    private var weightText: String { weight.formattedWeightShort(useMetric: useMetric) }
    private var unit: String { useMetric ? "kg" : "lb" }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space1) {
            HStack(alignment: .center, spacing: SBSLayout.space2) {
                Text(eyebrow)
                    .eyebrowText()
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
                Spacer(minLength: SBSLayout.space2)
                if let badge {
                    SBSBadge(text: badge)
                }
            }

            weightRow

            Text(scheme)
                .font(SBSFonts.number())
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if showPlates {
                PremiumPlateLoadSummary(
                    weight: weight,
                    barWeight: barWeight,
                    useMetric: useMetric,
                    onUnlockTap: onUnlockTap
                )
            }
        }
        .padding(SBSLayout.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            // The PR flash: orange across the whole card, the word on it, then it settles
            ZStack {
                Color.orangeFill
                Text("PR")
                    .font(SBSFonts.titleLarge())
                    .foregroundStyle(Color.orangeInk)
            }
            .opacity(flashOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .signatureCard()
        .task(id: flashToken) {
            guard flashToken != nil else { return }
            // 600ms in all. Up and down in two steps: setting 1 then animating to 0 in
            // the same update would never draw the orange.
            withAnimation(.easeOut(duration: 0.1)) { flashOpacity = 1 }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.5)) { flashOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(500))
            onFlashDone?()
        }
    }

    @ViewBuilder
    private var weightRow: some View {
        let row = HStack(alignment: .firstTextBaseline, spacing: 6) {
            // The hero: may shrink at large text sizes, never wraps
            Text(weightText)
                .font(SBSFonts.workingWeight())
                .tracking(-0.68)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .layoutPriority(1)

            Text(unit)
                .font(SBSFonts.numberUnit())
                .foregroundStyle(Color.inkSecondary)
                .fixedSize()

            if onWeightTap != nil {
                Image(systemName: "pencil")
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.leading, SBSLayout.space1)
            }

            Spacer(minLength: 0)
        }

        if let onWeightTap {
            Button(action: onWeightTap) { row.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit weight, \(weightText) \(unit)")
        } else {
            row
                .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Card Pieces

/// A 1px hairline across a card
private struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: SBSLayout.strokeHairline)
    }
}

/// The square tile a card logs from. Unlogged it's a hairline surface with "+ Log";
/// logged it's raised and the content carries the result with a glyph. Orange stays
/// off these tiles: a list of cards would otherwise be a wall of orange.
private struct LogTile<Content: View>: View {
    let isLogged: Bool
    var width: CGFloat = 72
    var height: CGFloat = 72
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: SBSLayout.space1) {
            content()
        }
        .frame(minWidth: width, minHeight: height)
        .background(isLogged ? Color.surfaceRaised : Color.surface, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
        )
    }
}

/// "+ LOG", the unlogged face of a log tile
private struct LogPrompt: View {
    var body: some View {
        Image(systemName: "plus")
            .font(SBSFonts.bodyStrong())
            .foregroundStyle(Color.ink)
        Text("Log")
            .eyebrowText()
            .foregroundStyle(Color.ink)
    }
}

// MARK: - Training Max Card

struct TMCard: View {
    let name: String
    let trainingMax: Double
    let topSingleAt8: Double
    let useMetric: Bool
    var barWeight: Double = 45
    var showPlateCalculator: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(SBSFonts.heading())
                    .foregroundStyle(Color.ink)

                Spacer()

                SBSBadge(text: "TM")
            }

            HStack(alignment: .top, spacing: SBSLayout.space6) {
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    Text("Training max")
                        .eyebrowText()
                        .foregroundStyle(Color.inkSecondary)

                    Text(trainingMax.formattedWeight(useMetric: useMetric))
                        .font(SBSFonts.numberLarge())
                        .tracking(-0.84)
                        .foregroundStyle(Color.ink)
                }

                Rectangle()
                    .fill(Color.hairline)
                    .frame(width: SBSLayout.strokeHairline, height: 44)

                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    Text("Single @ 8")
                        .eyebrowText()
                        .foregroundStyle(Color.inkSecondary)

                    Text(topSingleAt8.formattedWeight(useMetric: useMetric))
                        .font(SBSFonts.numberLarge())
                        .tracking(-0.84)
                        .foregroundStyle(Color.ink)
                }

                Spacer()
            }

            if showPlateCalculator && topSingleAt8 >= barWeight {
                PlateListView(weight: topSingleAt8, barWeight: barWeight, useMetric: useMetric)
            }
        }
        .padding(SBSLayout.space4)
        .card()
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
            return "Volume"
        }
        let percentage = Int(round(intensity * 100))
        return "\(percentage)% TM"
    }

    private var volumeScheme: some View {
        Text("\(sets) × \(repsPerSet)")
            .font(SBSFonts.numberLarge())
            .tracking(-0.84)
            .foregroundStyle(Color.ink)
    }

    private var volumeWeight: some View {
        HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
            Text("@")
                .font(SBSFonts.number())
                .foregroundStyle(Color.inkSecondary)

            Button(action: { onWeightTap?() }) {
                HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space1) {
                    Text(weight.formattedWeight(useMetric: useMetric))
                        .font(SBSFonts.numberLarge())
                        .tracking(-0.84)
                        .foregroundStyle(isWeightOverridden ? Color.warning : Color.ink)

                    Image(systemName: isWeightOverridden ? "pencil" : "chevron.right")
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(isWeightOverridden ? Color.warning : Color.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit weight, \(weight.formattedWeight(useMetric: useMetric))\(isWeightOverridden ? ", adjusted" : "")")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(SBSFonts.heading())
                    .foregroundStyle(Color.ink)

                Spacer()

                SBSBadge(text: intensityBadgeText)
            }

            // Prescription: "4 × 8 @ 130 lb", the weight under the scheme when one line won't fit
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                    volumeScheme
                    volumeWeight
                }
                .lineLimit(1)

                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    volumeScheme
                    volumeWeight
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            if isWeightOverridden, let calculated = calculatedWeight {

                Label("Recommended: \(calculated.formattedWeight(useMetric: useMetric))", systemImage: "arrow.turn.up.right")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }

            if showPlateCalculator && weight >= barWeight {
                PlateListView(weight: weight, barWeight: barWeight, useMetric: useMetric)
            }

            if hasNote, let note = loggedNote {
                NotePreview(note: note)
            }

            HairlineDivider()

            HStack {
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    Text("Rep-out target")
                        .eyebrowText()
                        .foregroundStyle(Color.inkSecondary)

                    HStack(spacing: SBSLayout.space1) {
                        Text("\(repOutTarget)+ reps")
                            .font(SBSFonts.number())
                            .foregroundStyle(Color.ink)

                        if hasNote {
                            Image(systemName: "note.text")
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                                .accessibilityLabel("Has a note")
                        }
                    }
                }

                Spacer()

                LogButton(
                    loggedReps: loggedReps,
                    tmDelta: tmDelta,
                    onTap: onLogTap
                )
            }
        }
        .padding(SBSLayout.space4)
        .card()
    }
}

// MARK: - Log Button

struct LogButton: View {
    let loggedReps: Int?
    let tmDelta: Double?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            LogTile(isLogged: loggedReps != nil) {
                if let reps = loggedReps {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark")
                            .font(SBSFonts.caption().weight(.bold))
                            .foregroundStyle(Color.success)
                        Text("\(reps)")
                            .font(SBSFonts.number())
                            .foregroundStyle(Color.ink)
                    }

                    if let delta = tmDelta {
                        Text(deltaText(delta))
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(delta < 0 ? Color.danger : (delta > 0 ? Color.success : Color.inkSecondary))
                    }
                } else {
                    LogPrompt()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loggedReps.map { "Logged \($0) reps, edit" } ?? "Log reps")
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
            withAnimation(.easeOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: SBSLayout.space2) {
                Image(systemName: "note.text")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)

                Text(note)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.ink)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)

                Spacer()

                if note.count > 60 {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .padding(SBSLayout.space2)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Structured Card

/// A structured lift in the session list. Never the live set (that's LiveSetCard on
/// the workout screen), so it's an ordinary hairline card.
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
        VStack(alignment: .leading, spacing: SBSLayout.space3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(SBSFonts.heading())
                    .foregroundStyle(Color.ink)

                Spacer()

                Text("TM \(trainingMax.formattedWeight(useMetric: useMetric))")
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SBSLayout.space2), count: 3), spacing: SBSLayout.space2) {
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

            // Plates for the heaviest set (usually the 1+ set)
            if showPlateCalculator, let heaviestSet = sets.max(by: { $0.weight < $1.weight }),
               heaviestSet.weight >= barWeight {
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    Text("Heavy single")
                        .eyebrowText()
                        .foregroundStyle(Color.inkSecondary)

                    PlateListView(weight: heaviestSet.weight, barWeight: barWeight, useMetric: useMetric)
                }
            }

            Group {
                if isFullyLogged {
                    Label("All AMRAP sets logged", systemImage: "checkmark")
                        .foregroundStyle(Color.success)
                } else if let reps = onePlusReps {
                    Label("1+ set: \(reps) reps", systemImage: "flame")
                        .foregroundStyle(Color.ink)
                } else {
                    Label("Tap AMRAP sets to log reps", systemImage: "hand.tap")
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .font(SBSFonts.caption())
        }
        .padding(SBSLayout.space4)
        .card()
    }
}

// MARK: - Structured Set Cell

/// A set in the session list's grid. Unlogged AMRAPs are what to act on, so they
/// take the orange-soft cell; logged sets show their reps with a check.
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

    private var isOpenAMRAP: Bool {
        setInfo.isAMRAP && !isLogged
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(setInfo.weight.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let logged = setInfo.loggedReps {
                    (Text(Image(systemName: "checkmark")) + Text(" \(logged) reps"))
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.success)
                } else {
                    Text("× \(repsText)")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.ink)
                }

                Text(intensityText)
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SBSLayout.space2)
            .padding(.horizontal, SBSLayout.space1)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(isOpenAMRAP ? Color.orangeText : Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
        }
        .buttonStyle(.plain)
        .disabled(!setInfo.isAMRAP)
    }

    private var backgroundColor: Color {
        if isLogged {
            return .surfaceRaised
        } else if isOpenAMRAP {
            return .orangeSoft
        } else {
            return .surface
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
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            Text("Accessory")
                .eyebrowText()
                .foregroundStyle(Color.inkSecondary)

            HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                Text(name)
                    .font(SBSFonts.heading())
                    .foregroundStyle(Color.ink)

                if hasNote {
                    Image(systemName: "note.text")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .accessibilityLabel("Has a note")
                }

                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    Text("\(sets) × \(reps)")
                        .font(SBSFonts.number())
                        .foregroundStyle(Color.ink)

                    if let log = lastLog {
                        Label(log.weight > 0 ? "Last: \(log.weight.formattedWeightShort(useMetric: useMetric))" : "Last: no added weight",
                              systemImage: "clock.arrow.circlepath")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)

                        if log.wasEasy == true {
                            Label("Last time was easy, go heavier", systemImage: "hand.thumbsup")
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.success)
                        }
                    } else {
                        Text("No weight logged")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                }

                Spacer()

                AccessoryLogButton(
                    lastLog: lastLog,
                    useMetric: useMetric,
                    onTap: onLogTap
                )
            }

            if hasNote, let note = lastLog?.note {
                NotePreview(note: note)
            }
        }
        .padding(SBSLayout.space4)
        .card()
    }
}

// MARK: - Accessory Log Button

struct AccessoryLogButton: View {
    let lastLog: AccessoryLog?
    let useMetric: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            LogTile(isLogged: lastLog != nil, width: 64, height: 56) {
                if let log = lastLog {
                    Text(log.weight.formattedWeightShort(useMetric: useMetric))
                        .font(SBSFonts.number())
                        .foregroundStyle(Color.ink)

                    Text("Edit")
                        .eyebrowText()
                        .foregroundStyle(Color.inkSecondary)
                } else {
                    LogPrompt()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lastLog.map { "Logged \($0.weight.formattedWeightShort(useMetric: useMetric)), edit" } ?? "Log accessory")
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

    private var linearScheme: some View {
        Text("\(info.sets) × \(info.reps)")
            .font(SBSFonts.numberLarge())
            .tracking(-0.84)
            .foregroundStyle(Color.ink)
    }

    private var linearWeight: some View {
        HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
            Text("@")
                .font(SBSFonts.number())
                .foregroundStyle(Color.inkSecondary)

            Text(info.weight.formattedWeight(useMetric: useMetric))
                .font(SBSFonts.numberLarge())
                .tracking(-0.84)
                .foregroundStyle(Color.ink)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space3) {
            Text(name)
                .font(SBSFonts.heading())
                .foregroundStyle(Color.ink)

            // "5 × 5 @ 135 lb", the weight under the scheme when one line won't fit
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                    linearScheme
                    linearWeight
                    Spacer(minLength: 0)
                }
                .lineLimit(1)

                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    linearScheme
                    linearWeight
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            if showPlateCalculator && info.weight >= barWeight {
                PlateListView(weight: info.weight, barWeight: barWeight, useMetric: useMetric)
            }

            if info.isDeloadPending && !isLogged {
                Label("Deload pending (\(info.consecutiveFailures) failures)", systemImage: "exclamationmark.triangle")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.warning)
            }

            HairlineDivider()

            HStack {
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    Text("Next session")
                        .eyebrowText()
                        .foregroundStyle(Color.inkSecondary)

                    Label("+\(info.increment.formattedWeight(useMetric: useMetric)) on success", systemImage: "plus")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.success)
                }

                Spacer()

                LinearLogButton(
                    isLogged: isLogged,
                    wasSuccessful: wasSuccessful,
                    onTap: onLogTap
                )
            }
        }
        .padding(SBSLayout.space4)
        .card()
    }
}

// MARK: - Linear Log Button

struct LinearLogButton: View {
    let isLogged: Bool
    let wasSuccessful: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            LogTile(isLogged: isLogged) {
                if isLogged {
                    Image(systemName: wasSuccessful ? "checkmark" : "xmark")
                        .font(SBSFonts.bodyStrong().weight(.bold))
                        .foregroundStyle(wasSuccessful ? Color.success : Color.danger)

                    Text(wasSuccessful ? "Done" : "Failed")
                        .eyebrowText()
                        .foregroundStyle(wasSuccessful ? Color.success : Color.danger)
                } else {
                    LogPrompt()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLogged ? (wasSuccessful ? "Done, edit" : "Failed, edit") : "Log result")
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            LiveSetCard(
                eyebrow: "Set 3 of 5 · last set",
                badge: "85% TM",
                weight: 335,
                useMetric: false,
                scheme: "× 5",
                showPlates: true,
                onWeightTap: {}
            )

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
