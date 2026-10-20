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

## Current schedule implementation

- The live schedule service now reads a versioned `ScheduleRule` archive and converts old rules into named “Allowed hours, every day” rules with the same IDs, targets, times, enabled state, and pending changes. It saves the new archive before registering new monitors, applies the new store, then clears legacy monitors and stores after all new registrations succeed.
- Users can create and edit blocked or allowed hours, weekdays, overnight windows, names, and app/category/website targets. Multiple rules may select the same target. Each rule has its own named shield store; ending one rule does not clear another rule's shield.
- The app and extension reevaluate a rule at its start/end wake times and at midnight for allowed-hour rules. The extension also wakes at the effective time of a migrated pending 24-hour change. Both use the device's current local time and recalculate state when a callback arrives late.
- Disabling or removing schedules and daily limits takes effect immediately, including during focus. A legacy pending schedule change retains its original effective date until the user explicitly changes the schedule.
- Home shows each enabled schedule's name, current blocking status, next local-time change, and selected targets on tap.
- This code is unverified on a physical device. Repeating wake points, overlapping stores, migration with active shields, locked-device callbacks, DST, and timezone changes must pass the device matrix before release. Apple warns that too many or tightly scheduled activities can make registration fail; the service reports those failures and retains legacy monitors during an unsuccessful migration.

## First engineering slice

1. Keep the current app behavior intact while introducing a versioned, device-local rule model and a pure evaluator that returns required targets and contributing rule IDs. The pure `RestrictionRuleEvaluator` and source-specific rule IDs are present. A versioned archive is present for schedules, while a unified persisted rule format remains to be added.
2. Test the approved **any active block wins** rule with focus, daily-limit, and allowed/blocked schedule combinations. The new tests cover overlapping focus and daily-limit blocks, an allowed schedule window, and repeated callbacks. A Pomodoro break remains a later rule source.
3. Add a reconciliation adapter that compares desired restrictions with each Noxa-owned store and updates only the owning store. The first part is complete: focus/manual/website stores are isolated and reconciled from their own saved state. A unified adapter across schedules, daily limits, and Pomodoro remains to be built.
4. Define and test migration of existing schedules, including pending 24-hour disable/remove records, before writing a new schedule format. The format, migration reader, live service, and extension callbacks are present; physical-device migration tests remain.
5. Validate each enforcement transition on physical iPhones. Simulator tests verify local logic and UI, not Screen Time behavior.

## Baseline test finding

- Environment: Xcode 27.0, iPhone 17 simulator on iOS 26.5. The active command-line developer directory points to Command Line Tools, so project commands use `/Applications/Xcode.app/Contents/Developer` explicitly.
- The first test attempt exposed stale subscription test calls. After that test was updated, the next run exposed an onboarding test that skipped the required value-overview milestone. Both test expectations were brought into line with the current services.
- The current branch has 63 passing unit tests and 3 passing simulator UI tests. Simulator Managed Settings stores read back as empty even after accepting a write, so physical-device testing is required for actual enforcement and migration.
- A signed build was installed and launched on the paired iPhone. A launch-only device UI test passed, but a screen-query test was denied iPhone UI-automation permission. Actual Screen Time behavior remains unverified.

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

## Paid onboarding progress

- The existing payment gate still comes before distraction selection and use of blocking features.
- A notification education page now appears after payment and before target selection. It offers a clear enable or Not Now choice. Declining notifications does not stop focus or Pomodoro enforcement.
- Every normal focus start now opens a review of selected targets, duration, expected end time, and Strict status before the final Start action. After paid setup, Noxa opens that review once with a 30-minute default, after the one-time Strict offer. Existing completed users do not reenter it.
- The target picker now shows a suggestion based on the user's goal and distraction answer; the user still chooses the actual opaque Screen Time targets.
- A first completed focus session now offers a one-time recurring schedule using its saved device-local targets. The user chooses the schedule name, days, mode, and hours before saving; dismissing the offer clears the target copy. The target copy survives the extension clearing the active focus shield before the app records completion. This path still needs physical-device lifecycle validation.
- The app now displays a matching monitor-process receipt after a focus callback applies the saved settings. This confirms the callback path ran, not that iOS visibly blocked the selected targets; physical-device observation is still required.

## Widget and Lock Screen first slice

- A WidgetKit extension provides Home Screen and Lock Screen focus widgets. An idle widget opens the paid app's focus review with one hour selected; the user can change the duration before starting. An active widget reads the device-local App Group session snapshot and counts down to the planned end. Its timeline returns to idle at the planned end, and the app reloads it when session state changes.
- An ActivityKit Live Activity shows the same session countdown on the Lock Screen and Dynamic Island where available. The app requests it for an active session, ends it when session state changes, and reconciles it on app launch or foreground. If iOS suspends the app at the precise end time, the Live Activity may remain stale until reconciliation; this behavior needs physical-device measurement.
- The focus screen distinguishes a started session from a matching receipt written by the DeviceActivity monitor after it applies the saved block settings. The receipt is cleared with the focus restrictions and cannot confirm that iOS visibly shielded a selected target; that still requires physical-device observation.
- Widget taps still pass through the existing subscription, Screen Time authorization, target, Strict, and active-session checks in the app. An idle widget never starts blocking directly.
- The new widget extension builds in the simulator, and the signed app with the extension installed and launched on the paired iPhone. Widget placement, countdown behavior while the app is closed, and Live Activity permission still need direct device observation.

## Instagram Safari prototype

- `Experiments/InstagramSafari` now contains an isolated Safari Web Extension prototype. It covers direct Reels and Explore routes and hides links to those sections while leaving the feed and other paths available by route. Three script behavior tests pass, and Apple's Safari extension packager accepted the manifest for an iOS project (with icon warnings).
- The prototype is not embedded in the Noxa app, exposed as a product setting, or verified on signed-in Instagram in Safari. Instagram's dynamic markup, embedded feed Reels, permission state, and physical-device behavior must be checked before claiming selective filtering or moving it into the app.
