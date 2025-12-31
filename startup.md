Here is a clear, hand-off ready spec you can give a builder. I also extracted the program into a single JSON config so they can plug it in directly.

[Download the program config (JSON)](sandbox:/mnt/data/sbs_program_config.json)

# Product goals

* Replicate your 20-week, 5-day hypertrophy program, including the exact week-to-week intensity, sets, reps, and rep-out targets for each lift and variation.
* Keep the same auto-regulation logic: adjust next week’s training max (TM) up or down based on how many reps you hit on the last set vs the target.
* Present a simple, workout-first UI similar to the nSuns iOS app: week overview, day session view, quick logging, and frictionless navigation.

# Core concepts

**Program length and split**

* 20 weeks.
* 5 training days per week.

**Exercise types**

* Primary lifts and close variations. Each has:

  * A “TM” header line that shows the current training max and a recommended single at about RPE 8.
  * A volume prescription for the day: sets x reps at a percentage of TM with a rep-out target on the last set.
* Accessories. Listed for the right day, but loads are not auto-calculated.

**Training max (TM)**

* Each lift has a starting TM (from Quick Setup).
* The app stores a TM per lift per week. Week 1 uses the starting TM. Weeks 2 to 20 adjust from the prior week based on logged performance.

**Top single @8**

* A recommended single weight for that lift: `rounded(TM * single_at_8_percent)`.
* `single_at_8_percent` is 0.90 for all lifts in your sheet.

**Rounding**

* Round all working weights and top singles to the nearest increment. Default is 5 lb (can be user configurable).

# Auto-regulation model

On each volume prescription, the last set has a rep-out target. After the session, the user logs the actual reps for that last set. The difference from the target maps to a percentage change for next week’s TM.

**Mapping (constant across all weeks and all lifts in your template):**

* 2+ below target: −5 percent
* 1 below target: −2 percent
* Hit target: 0 percent
* 1 over: +0.5 percent
* 2 over: +1.0 percent
* 3 over: +1.5 percent
* 4 over: +2.0 percent
* 5+ over: +3.0 percent

**Update rule**

```
TM_next = TM_current * (1 + delta)
```

If no log is entered for the week, treat as “hit target” (0 percent).

# Programming details from your template

* The program defines every lift’s weekly intensity, sets, normal reps, and rep-out target for all 20 weeks.
* Primary lift families use a 3-week wave of rep ranges and intensities, with high-rep deload style weeks at weeks 7 and 14. Example for Squat:

  * Reps per set by week: 10, 9, 8, then repeat patterns that trend down over blocks, with week 7 and 14 high-rep days (14 reps) as a lighter week.
  * Intensity (% of TM) rises across the block: for Squat and Bench the range goes roughly from 0.70 up to 0.825 by week 20. Close variations run about 0.05 lower in the same pattern (for example Front Squat 0.65 up to about 0.775).
  * Sets are 4 across weeks for the primary and variation lifts in this template.
  * Rep-out targets trail normal reps by about 2 on most weeks, with larger targets on high-rep deload weeks.
* The day layout is fixed for the entire cycle. For example:

  * Day 1: Squat TM, Squat volume, Push Press TM, Push Press volume, plus accessories
  * Day 2: Bench Press TM, Bench volume, Front Squat TM, Front Squat volume, plus accessories
  * Day 3: Trap Bar Deadlift TM, Trap Bar DL volume, Incline Press TM, Incline volume, plus accessories
  * Day 4: OHP TM, OHP volume, Paused Squat TM, Paused Squat volume, plus accessories
  * Day 5: Spoto Press TM, Spoto volume, Rack Pull TM, Rack Pull volume, plus accessories
* All of the exact numbers are encoded in the JSON linked above: weeks 1 to 20, per lift, with the intensity, sets, reps, rep-out, and the universal auto-reg deltas.

# Data model

You can use the JSON as the canonical program source. Minimal schema:

```json
{
  "name": "SBS Hypertrophy Template - 5 day",
  "rounding": 5,
  "initial_maxes": { "Squat": 170, "Bench Press": 235, "Trap Bar Deadlift": 270, "OHP": 135, "Front Squat": 100, "Paused Squat": 175, "Incline Press": 175, "Spoto Press": 175, "Rack Pull": 205, "Push Press": 125 },
  "single_at_8_percent": { "Squat": 0.9, "...": 0.9 },
  "weeks": [1, ..., 20],
  "days": {
    "1": [ {"type":"tm","name":"Squat TM","lift":"Squat"}, {"type":"volume","name":"Squat","lift":"Squat"}, {"type":"tm","name":"Push Press TM","lift":"Push Press"}, {"type":"volume","name":"Push Press","lift":"Push Press"}, {"type":"accessory","name":"Cable rows"}, {"type":"accessory","name":"EZ Bar Curls"} ],
    "2": [ ... ],
    "3": [ ... ],
    "4": [ ... ],
    "5": [ ... ]
  },
  "lifts": {
    "Squat": {
      "1": {"Intensity":0.70,"Reps per normal set":10,"Rep out target":12,"Sets":4, "Below rep target by 2+ reps":-0.05,"Below rep target by 1 rep":-0.02,"Hit rep target":0.0,"Beat by 1 rep":0.005,"Beat by 2 reps":0.01,"Beat by 3 reps":0.015,"Beat by 4 reps":0.02,"Beat by 5+ reps":0.03},
      "2": {"Intensity":0.725,"Reps per normal set":9,  "Rep out target":11,"Sets":4, "...":0.03},
      "...": {}
    },
    "Bench Press": { "1": {...}, "...": {} },
    "...": {}
  }
}
```

# Workout engine

**Inputs**

* Program config (above).
* Training maxes by lift for week 1.
* Rounding increment (default 5).
* Logs: per lift, per week, reps on last set, optional note.

**Outputs**

* For a given week and day:

  * For each “TM” entry: show the current TM and the rounded top single at 8 (TM * 0.90).
  * For each “volume” entry: sets x reps, the rounded working weight `round(TM * Intensity)`, and the rep-out target.
  * Accessories appear as labels.

**Algorithm**

```
for week in 1..20:
  if week == 1:
     TM_week[1] = user.initial_maxes
  else:
     TM_week[week] = {}
     for lift in lifts:
       prior = TM_week[week-1][lift]
       logged = logs.get(lift, {}).get(week-1)
       target = config.lifts[lift][week-1]["Rep out target"]
       diff = (logged.reps if logged else target) - target
       delta = map_diff_to_delta(diff)  # table above
       TM_week[week][lift] = prior * (1 + delta)
```

**Rounding**

```
rounded_weight = nearest(weight, rounding_increment)
```

# Representative test cases

Use these to verify the engine matches the program.

**Given rounding = 5 lb and initial TMs from the JSON:**

* Week 1 Day 1

  * Squat TM: 170, top single @8 -> round(170 * 0.90) = 155
  * Squat volume: 4 x 10 @ round(170 * 0.70) = 120, rep-out target 12
  * Push Press TM: 125, top single @8 -> 110
  * Push Press volume: 4 x 12 @ round(125 * 0.65) = 80, rep-out target 15
* If user logs Squat last-set reps = 14 in Week 1 (target 12), diff = +2 -> delta = +1.0 percent

  * Squat TM for Week 2 becomes 170 * 1.01 = 171.7
  * Week 2 Squat volume weight = round(171.7 * 0.725) = 125

# Suggested UI (patterned after nSuns)

**Home**

* Current macrocycle card (Weeks 1 to 20).
* Week selector with a 5 card strip for Day 1 to Day 5.
* Tap a day to open the session.

**Session view**

* Header: Week X, Day Y. Quick action to switch days.
* For each “TM” row: lift name, TM number, suggested single @8.
* For each “volume” row: lift name, sets x reps, prescribed rounded load, rep-out target, a field to log last-set reps and a small Notes area.
* Accessories listed after main work.
* CTA at bottom: Save Session.

**Logging**

* A compact number pad for last-set reps.
* Notes field.
* If no log is entered, TM carries forward unchanged.

**History**

* Simple graph per lift of TM by week.
* A list of saved sessions with last-set reps inline.

**Settings**

* Units and rounding increment.
* Edit week 1 TMs.
* Export data (CSV or JSON), import from JSON.

# Tech outline

* Data source: the provided JSON config.
* Core module exposes:

  * `get_week_plan(week, day)` -> fully resolved session with rounded loads.
  * `apply_logs_and_update_tms(logs)` -> returns TM table for weeks 1..N.
  * `round_to(weight, increment)`.
* Persistence: local storage or SQLite for user TMs and logs. Keep the immutable program config separate.
* Optional backend if you want sync or multiple devices: simple REST endpoints for user profile, logs, and TM snapshots.

# Edge cases and rules

* If a lift has no log for a week, treat as “hit target”.
* Never update the current week’s TM based on that same week’s log. Changes start next week.
* Clamp negative TMs if user deletes data incorrectly (should never go below a safe floor).
* Round only at the last step when converting a weight to the bar.
* If a lift is removed from a day, do not delete its TM history.

# What the builder needs from you

* Confirm units and rounding default (5 lb is current).
* Confirm you want the 20-week block to end and then either repeat or hold at Week 20.
* Confirm accessory list editing is allowed or fixed.

If you want, I can also provide a tiny reference library in Python or TypeScript that consumes the JSON and outputs a week or day plan.
