# Noxa product roadmap decisions

Status: Approved product direction, October 18, 2026. This document records decisions made after review of `NOXA_PRODUCT_ROADMAP.md`. Platform behavior and implementation details still require build and physical-device validation.

## Product direction and release order

1. Establish reliable enforcement, state reconciliation, and tests.
2. Improve paid onboarding through the first active focus session.
3. Extend the existing schedule feature.
4. Prototype and release Distraction-Free Safari, starting with Instagram.
5. Add insights and convenience controls after the core flows are reliable.

All planned features remain in the current subscription. Users cannot use the app's blocking features before subscribing; preserve the existing payment-before-setup flow.

## Restriction rules

- Schedules support both blocked hours and allowed hours. An allowed window never overrides an independently active focus session, schedule, or reached daily limit: any active block wins.
- A rule ending or being disabled removes only its own contribution. Other active rules continue to block their targets.
- Schedule and daily-limit changes take effect immediately. If another rule still requires a block, that block remains.
- Persist enough rule ownership and status to explain why a target is blocked and reconcile after lifecycle events.
- Screen Time authorization and observed enforcement must not be inferred solely from saved local state.

## Strict focus sessions

- Add a Settings toggle for Strict focus sessions. It is off by default for new and existing users, and is offered once when a new user first lands on the home screen. Keep the toggle available in Settings.
- A toggle change affects future focus sessions only. The mode of an active session is fixed at its start.
- With Strict off, keep the current early-end flow. With Strict on, an active focus session has no in-app early end and no timed breaks. Strict changes only this cancellation behavior; it does not add other enforcement rules.
- Strict sessions have a four-hour maximum. Regular sessions retain their current eight-hour maximum.
- Before starting a Strict session, show a clear warning and its exact end time alongside the start action.
- Describe Strict as preventing early cancellation in Noxa, without claiming the restriction is impossible to bypass through iOS.
- Preserve a technical recovery path for failed or stale enforcement; it is not a routine break or early-end control.

## Pomodoro

- Strict applies during each Pomodoro work interval. The user cannot stop during a Strict work interval, but can stop the Pomodoro cycle during a scheduled break.
- Begin the next work interval automatically when its break ends, including when Noxa is not foregrounded if the platform behavior validates on physical devices.
- Default to four work intervals per cycle, then stop. Notify the user that the cycle is complete and offer to open Noxa to start another cycle. Do not expose a round-count setting in the initial release.
- During each break, notify halfway through and one minute before the break ends. The cycle must continue correctly when notification permission is unavailable.
- Persist cycle phase, planned transition times, and stop intent so the work/break sequence can reconcile after interruption.

## Paid onboarding and first activation

- Keep the existing subscription requirement before the user can use Noxa's blocking features.
- After payment, guide the user to a first focus session. Require at least one chosen app, app category, or website before that session can start.
- Use the user's goal and distraction answers to suggest targets, while leaving the final selection to the user.
- Default the first session to 30 minutes; allow the user to customize its duration.
- Show a brief review of selected targets, duration, end time, and Strict status before Start Focus.
- Distinguish configured, requested, and confirmed enforcement states. Do not count purchase or setup-screen completion as first-rule activation.
- After the first session completes, offer a one-time optional prompt to make the same targets into a recurring schedule.
- Add an onboarding page explaining why notifications matter. Request permission with a clear choice and keep enforcement functional if notifications are declined.

## Schedules and daily limits

- Extend the existing allowed-schedule feature rather than introduce a separate competing scheduling feature.
- Users choose and edit schedule names. Schedules can target apps, app categories, websites, or any combination, including website-only schedules.
- Support selected weekdays and overnight windows.
- Convert existing schedules automatically to named "Allowed hours, every day" schedules with the same selected apps and times. Preserve their effective blocking behavior across the update; enable immediate editing and disabling afterward.
- Show an active schedule's name, whether it is blocking or allowing access, and its next change time on the home screen. Show selected targets on tap.
- Schedules follow the device's current local time. Validate daylight-saving and time-zone changes on physical devices.
- Offer optional schedule start/end reminders, off by default.
- Warn before daily allowances run out when physical-device testing confirms reliable timing.
- Allow daily limits to be edited or disabled immediately, without weakening independent active rules.

## Distraction-Free Safari

- Prototype Instagram first. In Safari, suppress Reels and Explore, including direct links to those sections. Keep the main feed available. Preserve messages, search, profiles, and other useful functions where the prototype verifies them.
- Offer a per-site choice between Distraction-Free and Full Block.
- Label selective filtering as Safari-only. The native Instagram app remains an all-or-nothing Screen Time block.
- If a filter is known to be broken or unavailable, warn the user and offer Full Block; do not switch modes without their choice or claim the filter is working.
- Provide a simple in-app broken-filter report action.
- Validate Instagram filtering before expanding to YouTube. Website changes and unsupported states require honest status and maintenance.

## Insights, shields, and convenience

- Prioritize weekly schedule adherence as the next insight. Keep focus-session duration separate from claims about screen time saved.
- Show the blocking rule's name and end time on a shield, and show the user's focus intention when available and supported.
- Let users create their own schedules; do not add Study, Sleep, or Work schedule templates in the initial release.
- Add a Home Screen widget with a Start Focus path when idle and remaining session time when active. Add a compact Lock Screen widget for start/status and an active-session Live Activity for a Lock Screen countdown; show the Dynamic Island presentation where supported.
- Tapping Start Focus on either widget opens a compact, prefilled start screen in Noxa. It uses the saved targets, lets the user choose a duration with one hour selected by default, shows the exact end time, and requires a final Start tap. This widget default does not change the 30-minute first-onboarding default.
- A widget start must validate subscription, Screen Time authorization, selected targets, current session state, and Strict policy. Strict requires its no-early-end warning and exact end time on the start screen.
- Keep widget and Live Activity state synchronized with the on-device session record and reconcile after completion, early end, or interruption. Add shortcuts and direct controls after the shared start path is validated.

## Subscription and quality behavior

- If a subscription expires during an already-started focus session, let that session finish and release its restrictions normally. Require renewal before starting another session.
- Verify overlap, expiry, authorization changes, timezone changes, app termination, reboot, and stale-state recovery with automated tests and a physical-device test record.
- Verify accessibility for onboarding, schedule setup, Strict warnings, shields, and recovery paths.
- Preserve opaque Screen Time selections and necessary enforcement state in appropriate on-device storage. Review what syncs through Supabase before release.

## Engineering preparation

- Establish and record a passing build and test baseline before changing enforcement.
- Document all current paths that apply or clear Managed Settings restrictions, then centralize rule evaluation and reconciliation incrementally.
- Add tests for overlapping rules and migration before changing schedule persistence.
- Implement in small, buildable releases with device validation at each enforcement milestone.
