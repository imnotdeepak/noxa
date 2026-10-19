# Enforcement inventory and first implementation slice

Status: Initial code inventory and pure rule evaluation, October 19, 2026. This describes current write paths, not physical-device proof of enforcement. The approved behavior is in `NOXA_PRODUCT_ROADMAP.md` and `product-roadmap-decisions.md`.

## Current owners and stores

| Rule or action | Main app path | Extension path | Managed Settings store |
| --- | --- | --- | --- |
| Focus session | `FocusSessionService` applies, ends, and reconciles the session | `NoxaMonitorExtension` applies at start and clears at end | `noxa.validation` |
| Explicit app/category/website shield | `ScreenTimeRestrictionService` applies and clears selected tokens | Validation callback can apply the persisted selection | `noxa.validation` |
| Custom website domains | `WebsiteBlocklistService` applies and clears the domain filter | Focus callback applies the session's domain snapshot | `noxa.validation` |
| Daily usage limits | `DailyLimitService` starts/stops monitoring, applies reached shields, and resets at day boundaries | Threshold callback unions reached limits and applies shields | `noxa.daily-limits` |
| Daily allowed schedules | `RestrictionScheduleService` monitors the before/after segments and applies their current shields | Schedule callbacks apply and clear the segment | One named store per schedule segment |
| Account deletion cleanup | `LocalDataCleanupService` invokes each service's cleanup path | None directly | All Noxa-owned stores through services |

The focus, explicit-shield, and custom-domain services share `noxa.validation`. A `clearAllSettings()` there clears every setting in that store; overlapping uses therefore need an explicit ownership and reconciliation policy. Separate daily-limit and schedule stores already provide some isolation, but do not provide one explanation of all currently active blocking reasons.

The monitor extension also writes focus and validation shields into `noxa.validation`. The current persisted selection and domain list do not record whether an explicit shield was switched on. Moving owners to separate named stores without a persisted activation state could either drop an intentional block or leave an old shield behind after an app update. The next integration step must first define that state and a one-time legacy-store migration, then update the app and extension together.

## Current schedule constraints

- A schedule is an allowed window every day; selected apps are blocked before and after it.
- Creation requires at least one app, rejects overlapping selections, and requires a same-day window of at least 15 minutes.
- Disabling or removing an enabled schedule is delayed 24 hours.
- Each schedule uses before/after monitor names and named stores. This is a useful foundation for the approved migration, but is not yet the new weekday/overnight/blocked-hours model.

## First engineering slice

1. Keep the current app behavior intact while introducing a versioned, device-local rule model and a pure evaluator that returns required targets and contributing rule IDs. The pure `RestrictionRuleEvaluator` and source-specific rule IDs are now present; persistence and the versioned format remain to be added.
2. Test the approved **any active block wins** rule with focus, daily-limit, and allowed/blocked schedule combinations. The new tests cover overlapping focus and daily-limit blocks, an allowed schedule window, and repeated callbacks. A Pomodoro break remains a later rule source.
3. Add a reconciliation adapter that compares desired restrictions with each Noxa-owned store and updates only the owning store. Make repeated callbacks and cleanup safe.
4. Define and test migration of existing schedules, including pending 24-hour disable/remove records, before writing a new schedule format.
5. Validate each enforcement transition on physical iPhones. Simulator tests verify local logic and UI, not Screen Time behavior.

## Baseline test finding

- Environment: Xcode 27.0, iPhone 17 simulator on iOS 26.5. The active command-line developer directory points to Command Line Tools, so project commands use `/Applications/Xcode.app/Contents/Developer` explicitly.
- The first test attempt exposed stale subscription test calls. After that test was updated, the next run exposed an onboarding test that skipped the required value-overview milestone. Both test expectations were brought into line with the current services.
- All 34 unit tests passed after the evaluator was added. This confirms the app and unit-test targets build in the selected simulator environment.
- A full-suite rerun did not complete because the simulator UI-test runner timed out while loading Accessibility. An earlier full run executed UI tests, but failed on the onboarding test before that expectation was fixed. A clean UI-test result remains to be obtained; this is separate from physical-device Screen Time validation.
