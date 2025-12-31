# Bug Report

These bugs have been identified in the app

## Overhead Press Terminology is inconsistent across programs

*Inconcistency*

Overhead presses are refererred to differently across programs which leads to variability in one-rep max and training max tracking when switching programs. Some programs refer to it as OHP, some Overhead Press, and some simply Press.

This should be unified to Overhead Press for all programs. 

## Text wrapping

*Bug*

In some places in the app we are using elements where text is expected to wrap if it runs over but swift does not permit wrapping if it will change the height of the element its in. We need to address this by either making the text shorter or properly handling these by putting it in an element that will let the text wrap.

e.g., CycleBuilerView.swift (415-425)

## Add option to hide PR celebrations

*Feature*

We should add an option to the Settings to hide PR celebrations. Some people may not like it.


## PR Celebration skips a set 

*Bug*

When the user presses "Continue" to dismiss the PR celebration it also skips the next set that the timer is currently running for. 

For example if the user achieves a PR for their last set of squats and records it the timer starts for the countdown to do the next exercise (Set 1 of Bench Press, for example). The PR Celebration screen shows. The user presses "Continue" to dismiss the Celebration screen. Then the timer skips to Set 2 of bench press. 

## Strength Scores are not showing even when the user has upgraded to premium

*Bug*

We have the ability to show commonly used strength scores (e.g., WILKS) both in the History view and in the calculator. These are premium features. They were previously working as expected. However, now even when the user upgrades to premium these are still being hidden behind the "premium" badge. Clicking on the premium badge brings up the purchase screen rather than showing the feature. This is incorrect. It needs to be fixed both in the Calculator section and in the History view.

## Hitting "Share" on any of the share buttons opens a blank screen

*Bug*

Clicking "Share" in any of the places we have the option to share something from the app opens a blank screen the first time the button is pressed. Upon clicking a second time it works as expected.

## Starting a new program should reset Workout State

*Bug*

When the user starts a new program the Workout view should be reset back to week 1. Currently if the user initiates a new cycle from the cycle builder and go back to the Workouts view it will be on whatever week they were on in their previous cycle, even if that week doesn't exist in their new program. 

## Use current training maxes for new cycle just showing zeros

*Bug*

When planning a new cycle with the cycle builder the user is supposed to have the option to use their current training maxes to start the new cycle. This is not working as intended. Even when the user has training maxes already loaded into the app this page just zeroes for all training maxes. 

It is unclear if this is related to the other issues with training maxes to be discussed later.

## Workout history and training maxes not being calculated or displayed properly for most programs

For most programs the Workout History and Training maxes are either not being saved or are not being displayed. The only program for which this is currently working as expected is SBS Hypertrophy Template - 5 day.

In any program (or at least all the ones I check - EXCEPT SBS Hypertrophy Template - 5 day), when the user completes a workout and navigates to the History view no training maxes are being displayed in the history max chart and no workouts are logged in the Workout History. Training Max progress also never changes. This continues throughout the course of the cycle. The user could compete the entire cycle and the Workout History never changes and neither do the training maxes. 

SBS Hypertrophy Template - 5 day is working as expected. It properly shows the current training max in the Training Max Progress card. It shows the Training Max progression in the chart. And it shows all the workout history for each lift in the Workout History view.

However then when a user starts a new cycle after running SBS Hypertrophy Template - 5 day, the workout history is cleared again. This is supposed to persist across cycles.

## Workout History should show program name

*Improvement*

We show the cycle number in the Workout History that a lift was from (e.g., Cycle 2). We should also show the program name  for the program that was run for that cycle. (e.g., Cycle 2, AMRAP Basics)

