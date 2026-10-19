# Enforcement inventory and first implementation slice

Status: Pure rule evaluation and first store isolation slice, October 19, 2026. This describes current write paths, not physical-device proof of enforcement. The approved behavior is in `NOXA_PRODUCT_ROADMAP.md` and `product-roadmap-decisions.md`.

## Current owners and stores

| Rule or action | Main app path | Extension path | Managed Settings store |
| --- | --- | --- | --- |
| Focus session | `FocusSessionService` applies, ends, and reconciles the session | `NoxaMonitorExtension` applies at start and clears at end | `noxa.focus` |
| Explicit app/category/website shield | `ScreenTimeRestrictionService` applies and clears a saved manual-shield snapshot | None | `noxa.manual` |
| Custom website domains | `WebsiteBlocklistService` applies and clears the domain filter, with saved active state | Focus callback applies the session's domain snapshot to the focus store | `noxa.websites` |
| Validation usage monitor | `DeviceActivityMonitoringService` starts and stops the validation monitor | Threshold callback applies the persisted selection | `noxa.validation` |
| Daily usage limits | `DailyLimitService` starts/stops monitoring, applies reached shields, and resets at day boundaries | Threshold callback unions reached limits and applies shields | `noxa.daily-limits` |
| Daily allowed schedules | `RestrictionScheduleService` monitors the before/after segments and applies their current shields | Schedule callbacks apply and clear the segment | One named store per schedule segment |
| Account deletion cleanup | `LocalDataCleanupService` invokes each service's cleanup path | None directly | All Noxa-owned stores through services |

The main app now gives focus, manual, website, daily-limit, schedule, and validation-monitor rules separate named stores. The explicit shield has a saved activation snapshot; the website blocklist has a saved active flag. `RestrictionStoreMigration` moves a pre-update shield from `noxa.validation` at app launch. If an old validation monitor is still running, it retains that store until its stop path clears it. The extension clears the old store when a pre-migration focus session ends. Existing app and extension paths were updated together, but the actual Managed Settings transfer and overlapping blocks still need physical-device verification.

The migration cannot always infer whether an old web-content filter came from a manual shield or a separately applied website blocklist. It preserves an otherwise unowned old filter as a removable manual shield. A filter from a running validation monitor remains temporary. This avoids turning a monitor threshold into a permanent manual block.

## Current schedule constraints

- A schedule is an allowed window every day; selected apps are blocked before and after it.
- Creation requires at least one app, rejects overlapping selections, and requires a same-day window of at least 15 minutes.
- Disabling or removing an enabled schedule is delayed 24 hours.
- Each schedule uses before/after monitor names and named stores. This is a useful foundation for the approved migration, but is not yet the new weekday/overnight/blocked-hours model.
- A versioned `ScheduleRule` archive and migration reader now convert legacy rules into named, every-day allowed-hour rules while retaining IDs, targets, enabled state, and pending 24-hour changes. The pure local-time evaluator covers weekdays and overnight windows. The live schedule service and monitor still use the legacy format; the new rule model is not yet enforced or shown in the app.
- Daily limits can now be edited, disabled, removed, or stopped immediately, including during focus. Their independent Managed Settings store keeps a focus block in force when a daily limit changes.

## First engineering slice

1. Keep the current app behavior intact while introducing a versioned, device-local rule model and a pure evaluator that returns required targets and contributing rule IDs. The pure `RestrictionRuleEvaluator` and source-specific rule IDs are present. A versioned archive is present for schedules, while a unified persisted rule format remains to be added.
2. Test the approved **any active block wins** rule with focus, daily-limit, and allowed/blocked schedule combinations. The new tests cover overlapping focus and daily-limit blocks, an allowed schedule window, and repeated callbacks. A Pomodoro break remains a later rule source.
3. Add a reconciliation adapter that compares desired restrictions with each Noxa-owned store and updates only the owning store. The first part is complete: focus/manual/website stores are isolated and reconciled from their own saved state. A unified adapter across schedules, daily limits, and Pomodoro remains to be built.
4. Define and test migration of existing schedules, including pending 24-hour disable/remove records, before writing a new schedule format. The migration reader and tests are present; switching live scheduling and extension callbacks to that format remains.
5. Validate each enforcement transition on physical iPhones. Simulator tests verify local logic and UI, not Screen Time behavior.

## Baseline test finding

- Environment: Xcode 27.0, iPhone 17 simulator on iOS 26.5. The active command-line developer directory points to Command Line Tools, so project commands use `/Applications/Xcode.app/Contents/Developer` explicitly.
- The first test attempt exposed stale subscription test calls. After that test was updated, the next run exposed an onboarding test that skipped the required value-overview milestone. Both test expectations were brought into line with the current services.
- The four-round integration has 49 passing unit tests and 3 passing UI tests. Simulator Managed Settings stores read back as empty even after accepting a write, so physical-device testing is required for actual enforcement and migration.
- A full-suite rerun did not complete because the simulator UI-test runner timed out while loading Accessibility. An earlier full run executed UI tests, but failed on the onboarding test before that expectation was fixed. A clean UI-test result remains to be obtained; this is separate from physical-device Screen Time validation.

## Strict Mode first slice

- A device-local Settings toggle defaults off and is offered once on first entry to the paid app. Its value is copied into each new session record; changing the toggle does not rewrite an active session.
- Strict starts show the expected end time and an in-app no-early-end warning. The service enforces a four-hour cap and rejects early-end calls for strict records; normal sessions retain the existing early-end flow and eight-hour cap.
- Account sign-out and deletion controls remain unavailable during any active focus session. Strict sessions show their scheduled end instead of an early-end action, including in the subscription recovery view.
- Pomodoro work intervals use the same strict policy. The four-round schedule is implemented below and awaits physical-device enforcement checks.

## Pomodoro timing slice

- `PomodoroCyclePlan` describes four work intervals and three breaks using elapsed time. It identifies the current phase after a process restart.
- `PomodoroCycleRecord` persists the targets, strict policy, and stable session IDs. Rounds two through four are scheduled as one-time Device Activity intervals; the monitor extension applies the saved targets while each work interval is current. The app rebuilds the current phase and completed history on launch or foreground.
- Every callback recalculates the current phase before touching the focus store. A late callback from an earlier interval therefore cannot release a newer work interval. Completed work is recorded in focus history only when a shield-application stamp exists for that round.
- `FocusNotificationService` schedules halfway and one-minute-left break reminders, work-end notices, next-round notices, and a four-round completion prompt. The cycle runs without notification permission.
- During a break, the user can stop the cycle; future monitors and pending cycle notifications are cancelled. Strict work intervals retain the no-early-end rule. The full transition matrix is in `physical-device-restriction-checks.md`.
