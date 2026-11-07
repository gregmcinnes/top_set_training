import SwiftUI

// MARK: - PR Celebration View

struct PRCelebrationView: View {
    let liftName: String
    let newE1RM: Double
    let previousE1RM: Double?
    let weight: Double
    let reps: Int
    let useMetric: Bool
    // Optional workout context used to build a richer PR share card.
    var week: Int = 0
    var day: Int = 0
    var programName: String? = nil
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var showConfetti = false
    @State private var showingShareSheet = false

    /// A single-PR workout summary for the share card (reuses WorkoutShareCard's
    /// existing PR styling).
    private var prShareSummary: WorkoutSummary {
        WorkoutSummary(
            date: Date(),
            dayTitle: "\(liftName) PR",
            week: week,
            day: day,
            programName: programName,
            exercises: [
                WorkoutSummary.ExerciseSummary(
                    name: liftName,
                    weight: weight,
                    sets: 1,
                    reps: "\(reps)",
                    isAMRAP: true,
                    estimatedOneRM: newE1RM,
                    isAccessory: false
                )
            ],
            totalSets: 1,
            duration: nil,
            prs: [
                WorkoutSummary.PRSummary(
                    liftName: liftName,
                    weight: weight,
                    reps: reps,
                    newE1RM: newE1RM,
                    previousE1RM: previousE1RM
                )
            ]
        )
    }
    
    private var improvement: Double? {
        guard let previous = previousE1RM, previous > 0 else { return nil }
        return newE1RM - previous
    }
    
    private var improvementPercent: Double? {
        guard let previous = previousE1RM, previous > 0 else { return nil }
        return ((newE1RM - previous) / previous) * 100
    }
    
    var body: some View {
        ZStack {
            // Solid, so nothing behind it can collide with this text
            Color.bg
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWithAnimation()
                }
            
            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            
            VStack(alignment: .leading, spacing: SBSLayout.space6) {
                // The word does the celebrating: PR on an orange block
                VStack(alignment: .leading, spacing: SBSLayout.space3) {
                    Text("PR")
                        .font(SBSFonts.titleLarge())
                        .foregroundStyle(Color.orangeInk)
                        .padding(.horizontal, SBSLayout.space4)
                        .padding(.vertical, SBSLayout.space2)
                        .background(Color.orangeFill)
                        .accessibilityLabel("New PR")

                    Text(liftName)
                        .titleLargeText()
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 12)
                
                VStack(alignment: .leading, spacing: SBSLayout.space4) {
                    // The set that was performed
                    Text("\(weight.formattedWeight(useMetric: useMetric)) × \(reps)")
                        .font(SBSFonts.number())
                        .foregroundStyle(Color.ink)
                    
                    VStack(alignment: .leading, spacing: SBSLayout.space1) {
                        Text("Estimated 1RM")
                            .eyebrowText()
                            .foregroundStyle(Color.inkSecondary)
                        
                        Text(newE1RM.formattedWeight(useMetric: useMetric))
                            .font(SBSFonts.numberLarge())
                            .tracking(-0.84)
                            .foregroundStyle(Color.ink)
                    }
                    
                    if let improvement = improvement, let percent = improvementPercent {
                        Label {
                            Text("+\(improvement.formattedWeight(useMetric: useMetric)) (+\(String(format: "%.1f", percent))%)")
                        } icon: {
                            Image(systemName: "arrow.up")
                        }
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.success)
                    } else {
                        Text("First recorded PR")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 12)
                
                VStack(spacing: SBSLayout.space3) {
                    Button(action: dismissWithAnimation) {
                        SBSButtonTitle("Back to it")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SBSPrimaryButtonStyle())

                    // Renders the PR as a share card
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        showingShareSheet = true
                    } label: {
                        Label {
                            SBSButtonTitle("Share this PR")
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SBSSecondaryButtonStyle())
                }
                // Room for the primary button's hard shadow
                .padding(.trailing, SBSLayout.hardShadowOffset)
                .opacity(showContent ? 1 : 0)
            }
            .padding(SBSLayout.space6)
            .frame(maxWidth: 420)
        }
        .sheet(isPresented: $showingShareSheet) {
            WorkoutShareSheet(
                summary: prShareSummary,
                useMetric: useMetric,
                onDismiss: { showingShareSheet = false }
            )
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            // Fast and physical: ease out, nothing bounces or loops
            withAnimation(.easeOut(duration: 0.25)) {
                showContent = true
            }
            withAnimation(.easeOut(duration: 0.25).delay(0.15)) {
                showConfetti = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }
    
    private func dismissWithAnimation() {
        withAnimation(.easeIn(duration: 0.2)) {
            showContent = false
            showConfetti = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    /// The brand's own objects: orange and the plate colours, which are the same in
    /// both themes
    private static let colors: [Color] = [.orangeFill, .plateRed, .plateBlue, .plateYellow, .plateGreen, .plateSilver]

    @State private var confettiPieces: [ConfettiPiece] = []
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(confettiPieces) { piece in
                    ConfettiPieceView(piece: piece)
                }
            }
            .onAppear {
                // Generate confetti pieces
                for _ in 0..<60 {
                    confettiPieces.append(ConfettiPiece(
                        x: CGFloat.random(in: 0...geo.size.width),
                        y: -20,
                        targetY: geo.size.height + 50,
                        color: Self.colors.randomElement()!,
                        size: CGFloat.random(in: 6...12),
                        rotation: Double.random(in: 0...360),
                        delay: Double.random(in: 0...0.5)
                    ))
                }
            }
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let targetY: CGFloat
    let color: Color
    let size: CGFloat
    let rotation: Double
    let delay: Double
}

struct ConfettiPieceView: View {
    let piece: ConfettiPiece
    
    @State private var currentY: CGFloat = -20
    @State private var currentRotation: Double = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        Rectangle()
            .fill(piece.color)
            .frame(width: piece.size, height: piece.size * 1.5)
            .rotationEffect(.degrees(currentRotation))
            .position(x: piece.x + horizontalOffset, y: currentY)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeIn(duration: Double.random(in: 2...3))
                    .delay(piece.delay)
                ) {
                    currentY = piece.targetY
                    currentRotation = piece.rotation + Double.random(in: 360...720)
                    horizontalOffset = CGFloat.random(in: -50...50)
                }
                
                withAnimation(
                    .easeIn(duration: 0.5)
                    .delay(piece.delay + 2)
                ) {
                    opacity = 0
                }
            }
    }
}

// MARK: - PR Badge (for showing in history/cards)

/// The one filled badge: "PR" on orange with orange-ink
struct PRBadge: View {
    var small: Bool = false
    
    var body: some View {
        SBSBadge(text: "PR", variant: .pr)
            .scaleEffect(small ? 0.9 : 1)
    }
}

// MARK: - Previews

#Preview("PR Celebration") {
    PRCelebrationView(
        liftName: "Squat",
        newE1RM: 315,
        previousE1RM: 295,
        weight: 275,
        reps: 8,
        useMetric: false,
        onDismiss: {}
    )
}

#Preview("First PR") {
    PRCelebrationView(
        liftName: "Bench Press",
        newE1RM: 225,
        previousE1RM: nil,
        weight: 185,
        reps: 10,
        useMetric: false,
        onDismiss: {}
    )
}

#Preview("PR Badge") {
    VStack(spacing: 20) {
        PRBadge()
        PRBadge(small: true)
    }
    .padding()
    .sbsBackground()
}



