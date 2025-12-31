# Program Review Checklist

Tracking review status for all workout programs in the app.

## Programs to Review

| Program | Status | Reviewer Notes |
|---------|--------|----------------|
| StrongLifts 5×5 | ✅ Complete | True linear progression implemented |
| Starting Strength | ⬜ Pending | |
| GZCLP | ⬜ Pending | |
| Greyskull LP | ⬜ Pending | |
| nSuns 4-Day | ⬜ Pending | |
| nSuns 5-Day | ⬜ Pending | |
| Reddit PPL | ⬜ Pending | |
| 5/3/1 BBB | ⬜ Pending | |
| 5/3/1 Triumvirate | ⬜ Pending | |
| SBS Program Bundle | ⬜ Pending | |

---

## StrongLifts 5×5

**File:** `Resources/stronglifts_5x5_12week.json`

### Original Program Specification

StrongLifts 5×5 is a linear progression program for beginners:

- **Frequency:** 3 days per week (e.g., Mon/Wed/Fri)
- **Alternating Workouts:**
  - **Workout A:** Squat, Bench Press, Barbell Row (all 5×5)
  - **Workout B:** Squat, Overhead Press, Deadlift (Squat & OHP 5×5, Deadlift 1×5)
- **Pattern:** Week 1: A-B-A, Week 2: B-A-B, alternating each week
- **Progression:** Add 5 lbs per session (2.5 lbs for OHP after stalls)
- **Exercises:** 5 compound movements (Squat, Bench, Deadlift, OHP, Barbell Row)

### Implementation Analysis

#### ✅ Correct
- [ ] 5 main exercises (Squat, Bench, Deadlift, OHP, Barbell Row)
- [ ] 5×5 for most exercises
- [ ] Deadlift is 1×5 (1 set of 5 reps)
- [ ] 3 workout days per cycle
- [ ] Weight rounding to 5 lbs

#### ⚠️ Deviations from Original
- [ ] **Static A-B-A Pattern:** Our implementation uses fixed Day 1/3 = Workout A, Day 2 = Workout B every week. Original program alternates A-B-A / B-A-B each week.
- [ ] **AMRAP on Final Set:** Added AMRAP (As Many Reps As Possible) on the last set of each exercise. Original program does not have AMRAP sets.
- [ ] **12-Week Cycle:** Original StrongLifts is open-ended (run until stalls). Our implementation caps at 12 weeks.
- [ ] **Intensity at 100%:** All sets use `intensity: 1.0` (100% of TM). This is correct if TM = working weight.

#### ❓ Questions/Concerns
- [ ] Is the A-B-A static pattern intentional, or should we alternate weeks?
- [ ] Is AMRAP on final set a desired enhancement or a deviation?

#### 🔍 Progression System (IMPORTANT)

**Original StrongLifts Progression:**
- Add +5 lbs to every lift after every successful session (2.5 lbs for OHP after stalls)
- Simple linear progression regardless of rep performance

**Our Implementation (nSuns-style AMRAP-based):**

The program uses `type: "nsuns"` which triggers AMRAP-based progression via `nsunsProgression()`:

| AMRAP Reps | Upper Body Δ | Lower Body Δ |
|------------|--------------|--------------|
| 0 reps | -5 lbs | 0 lbs (stall) |
| 1 rep | 0 lbs | +5 lbs |
| 2-3 reps | +5 lbs | +10 lbs |
| 4+ reps | +10 lbs | +15 lbs |

**⚠️ This is fundamentally different from StrongLifts progression.** Classic SL adds weight every session regardless of rep performance. Our version uses performance-based progression.

- [ ] **Decision:** Keep AMRAP-based progression (more flexible) or implement true SL linear progression?

### Current Structure

**Day 1 (Workout A):**
| Exercise | Sets × Reps | Intensity | Notes |
|----------|-------------|-----------|-------|
| Squat | 5×5 | 100% TM | Last set AMRAP |
| Bench Press | 5×5 | 100% TM | Last set AMRAP |
| Barbell Row | 5×5 | 100% TM | Last set AMRAP |

**Day 2 (Workout B):**
| Exercise | Sets × Reps | Intensity | Notes |
|----------|-------------|-----------|-------|
| Squat | 5×5 | 100% TM | Last set AMRAP |
| OHP | 5×5 | 100% TM | Last set AMRAP |
| Deadlift | 1×5 | 100% TM | AMRAP |

**Day 3 (Workout A - identical to Day 1):**
| Exercise | Sets × Reps | Intensity | Notes |
|----------|-------------|-----------|-------|
| Squat | 5×5 | 100% TM | Last set AMRAP |
| Bench Press | 5×5 | 100% TM | Last set AMRAP |
| Barbell Row | 5×5 | 100% TM | Last set AMRAP |

### Default Training Maxes
| Lift | Initial TM |
|------|------------|
| Squat | 135 lbs |
| Bench Press | 95 lbs |
| Deadlift | 135 lbs |
| OHP | 65 lbs |
| Barbell Row | 95 lbs |

### Decision Required
- [x] ~~Accept as-is (modified StrongLifts with AMRAP tracking)~~
- [ ] Modify to true alternating A/B pattern
- [ ] ~~Remove AMRAP and use strict 5×5~~
- [x] **Implement true linear progression** ✅ DONE

### ✅ Implementation Complete

True linear progression has been implemented with:
- **+5 lbs per session** on success (for all lifts except Deadlift)
- **+10 lbs per session** for Deadlift
- **Failure tracking** - consecutive failures per lift
- **10% deload** after 3 consecutive failures on a lift
- **UI support** - success/failure dialog after each exercise

---

## 📋 StrongLifts True Linear Progression - Feasibility Analysis

### Original StrongLifts Progression Rules

1. **On Success (all 5×5 completed):**
   - Add +5 lbs to all lifts
   - Add +10 lbs to Deadlift

2. **On Failure (missed any reps):**
   - Track the failure
   - After 3 consecutive failures on same lift → **Deload 10%**

3. **Deload:** Reduce weight by 10%, work back up

### Current System Limitations

| Aspect | Current State | Needed for StrongLifts |
|--------|---------------|------------------------|
| **Set Tracking** | Only tracks "completed" (checkbox) | Need "completed" vs "failed" |
| **Rep Logging** | Only on AMRAP sets | Need to know if all reps hit |
| **Failure Counter** | ❌ Not tracked | ✅ Track consecutive failures per lift |
| **Deload Logic** | ❌ None | ✅ Auto-deload after 3 failures |
| **Per-Lift Increment** | ❌ Same for all | ✅ +5 for most, +10 for deadlift |

### Changes Required to Support True Linear Progression

#### 1. Data Model Changes (`ProgramModels.swift`)

```swift
// NEW: Linear progression log entry
public struct LinearLogEntry: Codable, Equatable {
    public var completed: Bool           // Did they complete all sets/reps?
    public var consecutiveFailures: Int  // Running count of failures
    public var deloadApplied: Bool       // Was a deload triggered this session?
    public var note: String
}

// NEW: Add to DayItem.ItemType
case linear  // Linear progression exercise (StrongLifts style)
```

#### 2. Program Config Changes (`stronglifts_5x5_12week.json`)

```json
{
  "progression_type": "linear",
  "progression_config": {
    "default_increment": 5.0,
    "lift_increments": {
      "Deadlift": 10.0
    },
    "failures_before_deload": 3,
    "deload_percentage": 0.10
  }
}
```

#### 3. Engine Changes (`ProgramEngine.swift`)

```swift
// NEW: Linear progression calculation
public func linearProgression(
    previousTM: Double,
    completed: Bool,
    consecutiveFailures: Int,
    increment: Double,
    deloadPercent: Double,
    failuresBeforeDeload: Int
) -> (newTM: Double, newFailureCount: Int, deloaded: Bool)
```

#### 4. UI Changes (`WorkoutView.swift`)

- Add "Failed Set" button (or toggle per set)
- Track which sets were completed vs failed
- Show failure count badge on exercises
- Display deload notification when triggered

### Implementation Effort Estimate

| Component | Effort | Notes |
|-----------|--------|-------|
| Data Models | Small | Add `LinearLogEntry`, new enum case |
| JSON Config | Small | Add progression config fields |
| Engine Logic | Medium | New progression function, TM calculation |
| Persistence | Small | Add `linearLogs` to `UserData` |
| UI - Workout | Medium | Add fail tracking, buttons |
| UI - Summary | Small | Show deload notifications |
| **Total** | **Medium** | ~4-6 hours of focused work |

### Alternative: Keep Current "Hybrid" Approach

The current implementation with AMRAP on the last set could be seen as an **"Enhanced StrongLifts"**:

**Pros:**
- AMRAP provides progression data even when all sets complete
- More flexible - handles "just barely" vs "crushed it"
- Similar to popular 5×5+ variants

**Cons:**
- Not "pure" StrongLifts
- No automatic deload system
- Users expecting classic SL behavior may be confused

### Recommendation

Two options:

**Option A: Implement True Linear Progression**
- More work, but supports StrongLifts as designed
- This system would also benefit Starting Strength and other LP programs

**Option B: Rename/Rebrand as "StrongLifts 5×5+"**
- Document it as an enhanced variant with AMRAP-based progression
- Keep simpler implementation
- Add note in app explaining the deviation

---

*Last Updated: December 14, 2025*

