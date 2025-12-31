import SwiftUI

// MARK: - PR Celebration View

struct PRCelebrationView: View {
    let liftName: String
    let newE1RM: Double
    let previousE1RM: Double?
    let weight: Double
    let reps: Int
    let useMetric: Bool
    let onDismiss: () -> Void
    
    @State private var showContent = false
    @State private var showConfetti = false
    @State private var trophyScale: CGFloat = 0.3
    @State private var trophyRotation: Double = -30
    
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
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWithAnimation()
                }
            
            // Confetti particles
            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
            }
            
            // Main content card
            VStack(spacing: SBSLayout.paddingLarge) {
                // Trophy icon with animation
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.yellow.opacity(0.4), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .scaleEffect(showConfetti ? 1.2 : 0.8)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: showConfetti)
                    
                    // Trophy
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.yellow, Color.orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .orange.opacity(0.5), radius: 10, x: 0, y: 5)
                        .scaleEffect(trophyScale)
                        .rotationEffect(.degrees(trophyRotation))
                }
                
                // Title
                VStack(spacing: SBSLayout.paddingSmall) {
                    Text("🎉 NEW PR! 🎉")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.yellow, Color.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text(liftName)
                        .font(SBSFonts.title())
                        .foregroundStyle(.white)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                
                // Stats
                VStack(spacing: SBSLayout.paddingMedium) {
                    // The set that was performed
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Text(weight.formattedWeight(useMetric: useMetric))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("×")
                            .font(SBSFonts.title2())
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Text("\(reps) reps")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    
                    // New E1RM
                    VStack(spacing: 4) {
                        Text("Estimated 1RM")
                            .font(SBSFonts.caption())
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Text(newE1RM.formattedWeight(useMetric: useMetric))
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(Color.green)
                    }
                    
                    // Improvement (if not first PR)
                    if let improvement = improvement, let percent = improvementPercent {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(Color.green)
                            
                            Text("+\(improvement.formattedWeight(useMetric: useMetric))")
                                .font(SBSFonts.bodyBold())
                                .foregroundStyle(Color.green)
                            
                            Text("(+\(String(format: "%.1f", percent))%)")
                                .font(SBSFonts.body())
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, SBSLayout.paddingMedium)
                        .padding(.vertical, SBSLayout.paddingSmall)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.2))
                        )
                    } else {
                        Text("First recorded PR!")
                            .font(SBSFonts.caption())
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, SBSLayout.paddingMedium)
                            .padding(.vertical, SBSLayout.paddingSmall)
                            .background(
                                Capsule()
                                    .fill(Color.yellow.opacity(0.2))
                            )
                    }
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                
                Spacer().frame(height: SBSLayout.paddingMedium)
                
                // Continue button
                Button(action: dismissWithAnimation) {
                    Text("Continue")
                        .font(SBSFonts.button())
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.paddingMedium)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.yellow, Color.orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .opacity(showContent ? 1 : 0)
                .padding(.horizontal, SBSLayout.paddingLarge)
            }
            .padding(SBSLayout.paddingLarge)
            .frame(maxWidth: 340)
        }
        .onAppear {
            // Play haptics
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Animate in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                trophyScale = 1.0
                trophyRotation = 0
            }
            
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                showContent = true
            }
            
            withAnimation(.easeIn(duration: 0.3).delay(0.3)) {
                showConfetti = true
            }
            
            // Extra haptic bursts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let impact = UIImpactFeedbackGenerator(style: .heavy)
                impact.impactOccurred()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }
        }
    }
    
    private func dismissWithAnimation() {
        withAnimation(.easeIn(duration: 0.2)) {
            showContent = false
            showConfetti = false
            trophyScale = 0.5
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
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
                        color: [Color.yellow, Color.orange, Color.red, Color.green, Color.blue, Color.purple].randomElement()!,
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
        RoundedRectangle(cornerRadius: 2)
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

struct PRBadge: View {
    var small: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.system(size: small ? 10 : 12))
            
            if !small {
                Text("PR")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(
            LinearGradient(
                colors: [Color.yellow, Color.orange],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 3 : 4)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.15))
        )
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
    .background(Color.black)
}

