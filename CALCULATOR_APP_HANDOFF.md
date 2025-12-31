# Strength Calculator App - Handoff Documentation

This document provides all the details needed to build a standalone iOS app that replicates the Calculators functionality from the Top Set Training app.

---

## Table of Contents
1. [App Overview](#app-overview)
2. [Target Platform & Requirements](#target-platform--requirements)
3. [Feature List](#feature-list)
4. [Design System & Styling](#design-system--styling)
5. [Calculator Implementations](#calculator-implementations)
6. [Premium/Monetization](#premiummonetization)
7. [Data Files Required](#data-files-required)
8. [Sharing Functionality](#sharing-functionality)
9. [Complete Code Reference](#complete-code-reference)

---

## App Overview

A standalone iOS app containing five strength training calculators:
1. **One-Rep Max Calculator** - Estimate 1RM from submaximal lifts (FREE)
2. **RPE Calculator** - Find weights for target RPE levels (FREE)
3. **Plate Calculator** - Visual barbell plate loading display (FREE)
4. **Training Max Calculator** - Calculate TM and percentage charts (FREE)
5. **Strength Standards** - Compare lifts to gym population & competitive lifters (PREMIUM)

---

## Target Platform & Requirements

- **Platform**: iOS 17.0+
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Architecture**: Single-screen app with NavigationStack
- **Device Support**: iPhone (optimized for all sizes)
- **StoreKit 2**: For in-app purchase (premium feature)

---

## Feature List

### 1. One-Rep Max Calculator (FREE)
- **Input**: Weight lifted, number of reps
- **Output**: Estimated 1RM using 6 formulas:
  - Epley: `weight * (1 + reps / 30.0)`
  - Brzycki: `weight * (36.0 / (37.0 - reps))`
  - Lombardi: `weight * pow(reps, 0.10)`
  - Mayhew: `weight * (100.0 / (52.2 + 41.9 * exp(-0.055 * reps)))`
  - O'Conner: `weight * (1 + 0.025 * reps)`
  - Wathan: `weight * (100.0 / (48.8 + 53.8 * exp(-0.075 * reps)))`
- Shows average E1RM prominently
- Displays training percentages (95%, 90%, 85%, etc.)
- Supports metric (kg) and imperial (lb) units

### 2. RPE Calculator (FREE)
- **Input**: Estimated 1RM, target reps (1-12), target RPE (6.5-10)
- **Output**: Recommended weight for the given RPE
- Uses Mike Tuchscherer's RPE percentage table
- Shows RPE reference guide with descriptions
- RPE levels: 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0

### 3. Plate Calculator (FREE)
- **Input**: Total target weight, bar weight selection
- **Output**: Visual barbell with color-coded plates
- Features:
  - Competition-style plate colors
  - Interactive barbell visualization
  - Per-side breakdown
  - Plate legend
  - Quick weight selection
  - Supports both lb and kg plate sets
  - Adjustable bar weights (45/35/25/15 lb or 20/15/10 kg)

### 4. Training Max Calculator (FREE)
- **Input**: Actual 1RM, TM percentage (80-100%)
- **Output**: Training max and percentage chart
- Common presets: 85% (BBB), 90% (Standard 5/3/1), 92.5%, 95%
- Shows percentage chart from 50-100% of TM
- Common programming examples (5/3/1 weeks)

### 5. Strength Standards (PREMIUM)
- **Input**: Sex, bodyweight, lift maxes (Squat, Bench, Deadlift, OHP)
- **Output**: 
  - Overall percentile ranking
  - Classification (Beginner → World Class)
  - Per-lift percentile bars
  - Gym population comparison
  - Competitive lifter comparison (OpenPowerlifting data)
  - Bodyweight multipliers
- **Share feature**: Generate shareable card image

---

## Design System & Styling

The app uses a cohesive design system. Here's the complete theme:

### Color Palette

```swift
enum SBSColors {
    // Background colors (light/dark adaptive)
    static let backgroundFallback = Color(light: .init(white: 0.96), dark: .init(white: 0.08))
    static let surfaceFallback = Color(light: .white, dark: .init(white: 0.12))
    static let surfaceElevatedFallback = Color(light: .white, dark: .init(white: 0.16))
    
    // Accent colors (warm orange + blue)
    static let accentFallback = Color(light: .init(red: 0.95, green: 0.5, blue: 0.2), dark: .init(red: 1.0, green: 0.6, blue: 0.3))
    static let accentSecondaryFallback = Color(light: .init(red: 0.2, green: 0.4, blue: 0.8), dark: .init(red: 0.4, green: 0.6, blue: 1.0))
    
    // Text colors
    static let textPrimaryFallback = Color(light: .init(white: 0.1), dark: .init(white: 0.95))
    static let textSecondaryFallback = Color(light: .init(white: 0.4), dark: .init(white: 0.6))
    static let textTertiaryFallback = Color(light: .init(white: 0.6), dark: .init(white: 0.4))
    
    // Semantic colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
```

### Typography

```swift
enum SBSFonts {
    static func largeTitle() -> Font { .system(size: 34, weight: .bold, design: .rounded) }
    static func title() -> Font { .system(size: 22, weight: .bold, design: .rounded) }
    static func title2() -> Font { .system(size: 20, weight: .semibold, design: .rounded) }
    static func title3() -> Font { .system(size: 18, weight: .semibold, design: .rounded) }
    static func body() -> Font { .system(size: 17, weight: .regular, design: .default) }
    static func bodyBold() -> Font { .system(size: 17, weight: .semibold, design: .default) }
    static func weight() -> Font { .system(size: 24, weight: .bold, design: .monospaced) }
    static func weightLarge() -> Font { .system(size: 32, weight: .bold, design: .monospaced) }
    static func number() -> Font { .system(size: 20, weight: .semibold, design: .monospaced) }
    static func caption() -> Font { .system(size: 13, weight: .medium, design: .default) }
    static func captionBold() -> Font { .system(size: 13, weight: .semibold, design: .default) }
    static func button() -> Font { .system(size: 17, weight: .semibold, design: .rounded) }
}
```

### Layout Constants

```swift
enum SBSLayout {
    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 16
    static let paddingLarge: CGFloat = 24
    static let paddingXLarge: CGFloat = 32
    
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
    
    static let cardSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 24
    
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 4
}
```

### View Modifiers

```swift
extension View {
    func sbsCard() -> some View {
        self
            .background(SBSColors.surfaceFallback)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
            .shadow(color: .black.opacity(0.1), radius: SBSLayout.shadowRadius, x: 0, y: SBSLayout.shadowY)
    }
    
    func sbsBackground() -> some View {
        self.background(SBSColors.backgroundFallback.ignoresSafeArea())
    }
}
```

### Plate Colors (Competition Style)

**Imperial (lb):**
| Weight | Color |
|--------|-------|
| 45 lb | Blue `(0.2, 0.4, 0.8)` |
| 35 lb | Yellow `(0.9, 0.75, 0.1)` |
| 25 lb | Green `(0.2, 0.7, 0.3)` |
| 10 lb | White `(0.95, 0.95, 0.95)` |
| 5 lb | Red `(0.85, 0.2, 0.2)` |
| 2.5 lb | Silver `(0.6, 0.6, 0.65)` |

**Metric (kg):**
| Weight | Color |
|--------|-------|
| 25 kg (55 lb) | Red |
| 20 kg (44 lb) | Blue |
| 15 kg (33 lb) | Yellow |
| 10 kg (22 lb) | Green |
| 5 kg (11 lb) | White |
| 2.5 kg (5.5 lb) | Red small |
| 1.25 kg (2.75 lb) | Silver |

---

## Calculator Implementations

### One-Rep Max Formulas

```swift
private var results: [(name: String, value: Double, description: String)] {
    guard let w = weightValue, let r = repsValue, r > 0 else { return [] }
    
    let repsDouble = Double(r)
    
    return [
        ("Epley", w * (1 + repsDouble / 30.0), "Most common formula"),
        ("Brzycki", w * (36.0 / (37.0 - repsDouble)), "Popular for lower reps"),
        ("Lombardi", w * pow(repsDouble, 0.10), "Simple power formula"),
        ("Mayhew", w * (100.0 / (52.2 + 41.9 * exp(-0.055 * repsDouble))), "Research-based"),
        ("O'Conner", w * (1 + 0.025 * repsDouble), "Conservative estimate"),
        ("Wathan", w * (100.0 / (48.8 + 53.8 * exp(-0.075 * repsDouble))), "Football-based")
    ]
}
```

### RPE Table (Mike Tuchscherer)

```swift
// Rows: reps (1-12), Columns: RPE (6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10)
private let rpeTable: [[Double]] = [
    // 1 rep
    [0.88, 0.89, 0.91, 0.92, 0.94, 0.96, 0.98, 1.00],
    // 2 reps
    [0.85, 0.86, 0.88, 0.89, 0.91, 0.92, 0.94, 0.96],
    // 3 reps
    [0.82, 0.84, 0.85, 0.86, 0.88, 0.89, 0.91, 0.92],
    // 4 reps
    [0.79, 0.81, 0.82, 0.84, 0.85, 0.86, 0.88, 0.89],
    // 5 reps
    [0.77, 0.78, 0.79, 0.81, 0.82, 0.84, 0.85, 0.86],
    // 6 reps
    [0.74, 0.75, 0.77, 0.78, 0.79, 0.81, 0.82, 0.84],
    // 7 reps
    [0.71, 0.73, 0.74, 0.75, 0.77, 0.78, 0.79, 0.81],
    // 8 reps
    [0.68, 0.70, 0.71, 0.73, 0.74, 0.75, 0.77, 0.78],
    // 9 reps
    [0.65, 0.67, 0.68, 0.70, 0.71, 0.73, 0.74, 0.75],
    // 10 reps
    [0.63, 0.65, 0.66, 0.67, 0.68, 0.70, 0.71, 0.73],
    // 11 reps
    [0.60, 0.62, 0.63, 0.65, 0.66, 0.67, 0.68, 0.70],
    // 12 reps
    [0.58, 0.60, 0.61, 0.62, 0.63, 0.65, 0.66, 0.67]
]
```

### Plate Calculator Algorithm

```swift
func calculate(totalWeight: Double) -> PlateCalculatorResult {
    guard totalWeight > barWeight else {
        return PlateCalculatorResult(platesPerSide: [], totalWeight: barWeight, barWeight: barWeight, remainder: 0)
    }
    
    var weightPerSide = (totalWeight - barWeight) / 2.0
    var plates: [Plate] = []
    
    // Greedy algorithm: use largest plates first
    for plate in availablePlates.sorted(by: { $0.weight > $1.weight }) {
        while weightPerSide >= plate.weight {
            plates.append(plate)
            weightPerSide -= plate.weight
        }
    }
    
    // Round remainder to avoid floating point issues
    let remainder = (weightPerSide * 10).rounded() / 10
    
    return PlateCalculatorResult(platesPerSide: plates, totalWeight: totalWeight, barWeight: barWeight, remainder: remainder)
}
```

### Strength Standards (Bodyweight Multipliers)

**Male Standards:**
```swift
static let maleSquat = LiftStandard(percentileMultipliers: [
    (5, 0.50), (10, 0.70), (20, 0.90), (30, 1.10), (40, 1.30),
    (50, 1.50), (60, 1.70), (70, 1.90), (80, 2.10), (90, 2.40),
    (95, 2.70), (99, 3.00)
])

static let maleBench = LiftStandard(percentileMultipliers: [
    (5, 0.35), (10, 0.50), (20, 0.65), (30, 0.80), (40, 0.95),
    (50, 1.10), (60, 1.25), (70, 1.40), (80, 1.55), (90, 1.80),
    (95, 2.00), (99, 2.30)
])

static let maleDeadlift = LiftStandard(percentileMultipliers: [
    (5, 0.70), (10, 0.90), (20, 1.10), (30, 1.35), (40, 1.55),
    (50, 1.80), (60, 2.00), (70, 2.25), (80, 2.50), (90, 2.85),
    (95, 3.10), (99, 3.50)
])

static let maleOHP = LiftStandard(percentileMultipliers: [
    (5, 0.20), (10, 0.30), (20, 0.40), (30, 0.50), (40, 0.60),
    (50, 0.70), (60, 0.80), (70, 0.90), (80, 1.00), (90, 1.15),
    (95, 1.30), (99, 1.50)
])
```

**Female Standards:** (approximately 60-70% of male for upper body, 75-80% for lower body)
```swift
static let femaleSquat = LiftStandard(percentileMultipliers: [
    (5, 0.35), (10, 0.50), (20, 0.70), (30, 0.85), (40, 1.00),
    (50, 1.15), (60, 1.30), (70, 1.50), (80, 1.70), (90, 2.00),
    (95, 2.25), (99, 2.60)
])
// ... etc (see full code reference)
```

### Strength Classifications

```swift
static func classification(for percentile: Double) -> Classification {
    switch percentile {
    case 0..<20: return Classification(name: "Beginner", color: .gray)
    case 20..<40: return Classification(name: "Novice", color: .blue)
    case 40..<60: return Classification(name: "Intermediate", color: .green)
    case 60..<80: return Classification(name: "Advanced", color: .purple)
    case 80..<95: return Classification(name: "Elite", color: .orange)
    default: return Classification(name: "World Class", color: .red)
    }
}
```

---

## Premium/Monetization

### Premium Feature: Strength Standards

The Strength Standards calculator is gated behind a one-time premium purchase.

### StoreKit 2 Implementation

```swift
@Observable
public final class StoreManager {
    public static let shared = StoreManager()
    public static let premiumProductID = "com.strengthcalc.premium" // CHANGE THIS
    
    private(set) public var products: [Product] = []
    private(set) public var purchasedProductIDs: Set<String> = []
    private(set) public var isLoading = false
    
    public var isPremium: Bool {
        purchasedProductIDs.contains(Self.premiumProductID)
    }
    
    public var premiumProduct: Product? {
        products.first { $0.id == Self.premiumProductID }
    }
    
    public var premiumPriceString: String {
        premiumProduct?.displayPrice ?? "$4.99"
    }
    
    public func canAccess(_ feature: PremiumFeature) -> Bool {
        return isPremium
    }
    
    // See full implementation in code reference
}
```

### Premium Features Enum

```swift
public enum PremiumFeature: String, CaseIterable {
    case strengthStandards
    
    public var displayName: String {
        switch self {
        case .strengthStandards: return "Strength Standards"
        }
    }
    
    public var featureDescription: String {
        switch self {
        case .strengthStandards: return "See your percentile ranking vs 3.5M+ competitive powerlifters"
        }
    }
    
    public var iconName: String {
        switch self {
        case .strengthStandards: return "chart.bar.fill"
        }
    }
}
```

### Paywall UI

Show a full-screen paywall with:
- Crown icon header
- Feature list with checkmarks
- One-time purchase price
- "Upgrade Now" button with gradient
- "Restore Purchases" link

---

## Data Files Required

### 1. powerlifting_percentiles.json

This JSON file contains competitive powerlifting percentile data from OpenPowerlifting (3.5M+ lifters).

**Structure:**
```json
{
  "metadata": {
    "source": "OpenPowerlifting",
    "url": "https://www.openpowerlifting.org",
    "lifter_count": 3564985,
    "description": "Percentile data from competitive powerlifting meets",
    "units": "kg",
    "percentiles": [5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99]
  },
  "male": {
    "59": {  // weight class in kg
      "all_ages": {
        "squat": {
          "count": 118391,
          "percentiles": {
            "5": 62.5,
            "10": 77.1,
            // ... etc
          }
        },
        "bench": { ... },
        "deadlift": { ... }
      }
    },
    "66": { ... },
    "74": { ... },
    "83": { ... },
    "93": { ... },
    "105": { ... },
    "120": { ... },
    "140": { ... }
  },
  "female": {
    "47": { ... },
    "52": { ... },
    "57": { ... },
    "63": { ... },
    "69": { ... },
    "76": { ... },
    "84": { ... },
    "100": { ... }
  }
}
```

**Weight Classes:**
- Male: 59, 66, 74, 83, 93, 105, 120, 140 (kg)
- Female: 47, 52, 57, 63, 69, 76, 84, 100 (kg)

**Copy the full `powerlifting_percentiles.json` file from the original project.**

---

## Sharing Functionality

### Strength Standards Share Card

The Strength Standards calculator includes a "Share My Strength" button that generates a shareable image.

**StrengthSummary Model:**
```swift
struct StrengthSummary: Equatable {
    let overallPercentile: Double
    let lifts: [LiftStandard]
    let bodyweight: Double
    let isMale: Bool
    let useMetric: Bool
    
    struct LiftStandard: Equatable, Identifiable {
        let id = UUID()
        let name: String
        let weight: Double
        let percentile: Double
    }
}
```

**Image Snapshot Extension:**
```swift
extension View {
    @MainActor
    func snapshot() -> UIImage {
        let controller = UIHostingController(rootView: self)
        let view = controller.view
        
        let targetSize = controller.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear
        view?.layoutIfNeeded()
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}
```

**ShareSheet:**
```swift
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

---

## Complete Code Reference

### Files to Create

1. **App Entry Point**
   - `CalculatorApp.swift` - Main app entry

2. **Views**
   - `CalculatorsView.swift` - Main calculator list view (~2400 lines, contains all calculator views)
   
3. **Components**
   - `PlateCalculator.swift` - Plate calculator logic and barbell visualization (~870 lines)
   - `WorkoutShareCard.swift` - Sharing card components (~1800 lines, includes StrengthShareCard)

4. **Theme**
   - `Theme.swift` - Colors, fonts, layout constants, modifiers (~230 lines)

5. **Store**
   - `StoreManager.swift` - StoreKit 2 purchase management (~240 lines)
   - `FeatureAccess.swift` - Premium feature gating (~180 lines)

6. **Resources**
   - `powerlifting_percentiles.json` - Competitive lifter data (~6700 lines)

### Key Components to Extract

From the original codebase, copy and adapt:

1. **CalculatorsView.swift** (entire file)
   - `CalculatorsView` - Main view
   - `CalculatorCard` - Navigation card component
   - `PremiumCalculatorCard` - Locked card component  
   - `OneRepMaxCalculatorView`
   - `RPECalculatorView`
   - `StandalonePlateCalculatorView`
   - `TrainingMaxCalculatorView`
   - `StrengthStandardsView`
   - `StrengthStandards` enum with all standards data
   - `CompetitiveLiftingData` class

2. **PlateCalculator.swift** (entire file)
   - `Plate` struct
   - `StandardPlates` enum
   - `PlateCalculator` struct
   - `PlateCalculatorResult` struct
   - `BarbellView`
   - `PlateView`
   - `PlateLegendView`
   - `PlateListView`

3. **Theme.swift** (entire file)

4. **StoreManager.swift** (entire file, update product ID)

5. **FeatureAccess.swift** (simplify for single feature)

6. **WorkoutShareCard.swift** (partial - just the StrengthShareCard section)
   - `StrengthSummary` struct
   - `StrengthShareCard`
   - `ShareableStrengthCard`
   - `snapshot()` extension
   - `ShareSheet`

7. **PaywallView.swift** (entire file)

8. **UpgradePrompt.swift** (partial)
   - `PremiumBadge`

---

## App Structure Suggestion

```
StrengthCalculator/
├── StrengthCalculatorApp.swift
├── Views/
│   ├── CalculatorsView.swift
│   └── PaywallView.swift
├── Components/
│   ├── PlateCalculator.swift
│   └── ShareComponents.swift
├── Theme/
│   └── Theme.swift
├── Store/
│   ├── StoreManager.swift
│   └── FeatureAccess.swift
├── Resources/
│   └── powerlifting_percentiles.json
└── Info.plist
```

---

## Settings to Include

Add a simple settings section or sheet for:
- **Unit Toggle**: Metric (kg) / Imperial (lb)
- **Default Bar Weight**: 45 lb / 20 kg etc.

Store these in `@AppStorage` (UserDefaults).

```swift
@AppStorage("useMetric") private var useMetric = false
@AppStorage("barWeight") private var barWeight: Double = 45
```

---

## Testing Checklist

- [ ] All calculators work with both metric and imperial units
- [ ] Plate calculator shows correct plates for various weights
- [ ] RPE calculator matches expected percentages
- [ ] Strength standards classifications are correct
- [ ] Premium paywall appears for strength standards when not purchased
- [ ] In-app purchase completes successfully
- [ ] Restore purchases works
- [ ] Share card generates correctly
- [ ] Share sheet appears with correct image
- [ ] App handles edge cases (0 weight, invalid input, etc.)

---

## App Store Preparation

1. **App Name Ideas**: 
   - "Strength Calc"
   - "Lifter's Calculator"
   - "Gym Calc Pro"

2. **App Store Description Points**:
   - Six 1RM formulas with averaging
   - RPE-based weight recommendations
   - Visual plate calculator
   - Training max and percentage charts
   - Strength standards (compare to millions of lifters)
   - Beautiful, dark-mode-optimized design

3. **Screenshots Needed**:
   - Calculator list view
   - 1RM Calculator with results
   - Plate Calculator with barbell
   - Strength Standards results
   - Share card preview

4. **In-App Purchase**:
   - Product ID: `com.yourcompany.strengthcalc.premium` (configure in App Store Connect)
   - Type: Non-Consumable
   - Price: $4.99 suggested

---

## Notes

- The app should feel native and performant
- All animations should be smooth (use SwiftUI spring animations)
- Support both light and dark mode
- Keyboard should dismiss when scrolling
- Number inputs should use appropriate keyboard types (.decimalPad, .numberPad)
- Consider haptic feedback on button presses

