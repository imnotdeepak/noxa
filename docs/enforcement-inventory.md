# Enforcement inventory and implementation status

Status: Roadmap implementation and selected iPhone checks, October 20, 2026. The approved behavior is in `NOXA_PRODUCT_ROADMAP.md` and `product-roadmap-decisions.md`. Each physical claim below names its observed target and state; the remaining release matrix is recorded in `physical-device-restriction-checks.md`.

## Current owners and stores

| Rule or action | Main app path | Extension path | Managed Settings store |
| --- | --- | --- | --- |
| Focus session | `FocusSessionService` applies, ends, and reconciles the session | `NoxaMonitorExtension` applies at start and clears at end | `noxa.focus` |
| Explicit app/category/website shield | `ScreenTimeRestrictionService` applies and clears a saved manual-shield snapshot | None | `noxa.manual` |
| Custom website domains | `WebsiteBlocklistService` applies and clears the domain filter, with saved active state | Focus callback applies the session's domain snapshot to the focus store | `noxa.websites` |
| Validation usage monitor | `DeviceActivityMonitoringService` starts and stops the validation monitor | Threshold callback applies the persisted selection | `noxa.validation` |
| Daily usage limits | `DailyLimitService` starts/stops monitoring, applies reached shields, and resets at day boundaries | Threshold callback unions reached limits and applies shields | `noxa.daily-limits` |
| Named allowed/blocked schedules | `RestrictionScheduleService` registers local-time wake points and applies each rule's current shield | Schedule callbacks reevaluate the rule and apply or clear its contribution | One named store per schedule rule |
| Account deletion cleanup | `LocalDataCleanupService` invokes each service's cleanup path | None directly | All Noxa-owned stores through services |

The main app now gives focus, manual, website, daily-limit, schedule, and validation-monitor rules separate named stores. The explicit shield has a saved activation snapshot; the website blocklist has a saved active flag. `RestrictionStoreMigration` moves a pre-update shield from `noxa.validation` at app launch. If an old validation monitor is still running, it retains that store until its stop path clears it. The extension clears the old store when a pre-migration focus session ends. Store migration and release of overlapping blocks still need physical-device verification.

The daily-limit service rereads the system's registered activity on launch and foreground. If the daily-limit activity is absent, it clears only the daily-limit store and its reached-state markers. This recovers an interrupted stop without touching focus, schedules, or manual shields. Its stale-store recovery still needs a physical interruption test.

Settings now offers **Refresh Blocking** for a wrong or lingering shield. It reruns each rule owner's normal reconciliation path, preserving active Strict sessions and other active rules. The screen asks the user to check the affected app or site afterward because a successful refresh does not prove iOS displayed the shield.

The migration cannot always infer whether an old web-content filter came from a manual shield or a separately applied website blocklist. It preserves an otherwise unowned old filter as a removable manual shield. A filter from a running validation monitor remains temporary. This avoids turning a monitor threshold into a permanent manual block.

## Current schedule implementation

- The live schedule service now reads a versioned `ScheduleRule` archive and converts old rules into named “Allowed hours, every day” rules with the same IDs, targets, times, enabled state, and pending changes. It saves the new archive before registering new monitors, applies the new store, then clears legacy monitors and stores after all new registrations succeed.
- Users can create and edit blocked or allowed hours, weekdays, overnight windows, names, and app/category/website targets. Multiple rules may select the same target. Each rule has its own named shield store; ending one rule does not clear another rule's shield.
- The app and extension reevaluate a rule at its start/end wake times and at midnight for allowed-hour rules. The extension also wakes at the effective time of a migrated pending 24-hour change. Both use the device's current local time and recalculate state when a callback arrives late.
- While the app is running, significant clock changes and timezone changes trigger schedule reconciliation; significant changes also refresh focus and daily-limit state. Foreground entry already reconciles after suspension. Real travel, daylight-saving, and background callback timing remain physical-device checks.
- The app, Device Activity monitor, and shield extension now call the same `Shared/ScheduleWindow.swift` evaluator for local-time blocking decisions. This keeps overnight, weekday, and pending-relaxation behavior aligned across the three processes. The 69 unit tests pass, and the signed build with all extensions installed and launched on the paired iPhone. Background transition timing still needs direct physical observation.
- Disabling or removing schedules and daily limits takes effect immediately, including during focus. A legacy pending schedule change retains its original effective date until the user explicitly changes the schedule.
- The app records which schedule IDs own named shield stores. On launch and schedule reconciliation it clears an orphaned schedule store and stale wake monitors if that rule no longer exists in the saved archive. It also recovers owner IDs from registered wake activities when a crash preceded owner-list persistence. The owner list is device-local and clears with account data.
- Home shows each enabled schedule's name, current blocking status, next local-time change, and selected targets on tap.
- One current scheduled app block and its named shield text were observed on the paired iPhone. Repeating wake points, release of overlapping stores, migration with active shields, locked-device callbacks, DST, and timezone changes still need physical checks before release. The service reports registration failures and retains legacy monitors during an unsuccessful migration.

## First engineering slice

1. Keep the current app behavior intact while introducing a versioned, device-local rule model and a pure evaluator that returns required targets and contributing rule IDs. The `RestrictionOwnershipPlan` now normalizes saved focus/Pomodoro, schedule, reached daily-limit, manual shield, website-list, and Instagram Full Block requests into the pure evaluator. Home shows the number of active requesting rules and selected items, explicitly without claiming iOS displayed a shield. Daily-limit ownership ignores a previous day's reached markers. A versioned archive is present for schedules, while a unified persisted rule format remains to be added.
2. Test the approved **any active block wins** rule with focus, daily-limit, and allowed/blocked schedule combinations. The new tests cover overlapping focus and daily-limit blocks, an allowed schedule window, and repeated callbacks. A Pomodoro break remains a later rule source.
3. Add a reconciliation adapter that compares desired restrictions with each Noxa-owned store and updates only the owning store. Focus/manual/website stores are isolated and reconciled from their own saved state, and the new planner computes cross-source requested ownership for UI status and overlap tests. The app and monitor extension now share `RestrictionStoreWriter` for focus, manual, schedule, and daily-limit selection writes. Each source still decides when its own store should apply or clear. The write refactor needs physical overlap and release checks before being considered validated.
4. Define and test migration of existing schedules, including pending 24-hour disable/remove records, before writing a new schedule format. The format, migration reader, live service, and extension callbacks are present; physical-device migration tests remain.
5. Validate each enforcement transition on physical iPhones. Simulator tests verify local logic and UI, not Screen Time behavior.

## Baseline test finding

- Environment: Xcode 27.0, iPhone 17 simulator on iOS 26.5. The active command-line developer directory points to Command Line Tools, so project commands use `/Applications/Xcode.app/Contents/Developer` explicitly.
- The first test attempt exposed stale subscription test calls. After that test was updated, the next run exposed an onboarding test that skipped the required value-overview milestone. Both test expectations were brought into line with the current services.
- The current branch has 81 passing unit tests and 3 passing simulator UI tests. The simulator build also passes after the time-change reconciliation addition. Simulator Managed Settings stores read back as empty even after accepting a write, so physical-device testing is required for actual enforcement and migration.
- Signed builds were installed and launched on the paired iPhone. Device UI automation observed a named app shield and Instagram's full-site web block and release. Those checks do not establish the rest of the release matrix.

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
- A paired-iPhone test started a 15-minute Strict session, closed Noxa, and reopened it while active. A separate recovery run deliberately removed its focus monitor before reconciliation; the app restored the session and kept the no-early-end UI. The first run had exposed a bug: it tried to register a new interval using only the remaining time, which falls below DeviceActivity's 15-minute minimum. Recovery now registers the original start-to-end window. During the session, reddit.com showed Safari's block screen and Dazz Cam showed both Focus and schedule reasons. DoorDash was briefly available immediately after a test-build install, then showed the Focus shield after Noxa reopened and reconciled. This gap needs realistic upgrade testing. At the planned end with Noxa closed, DoorDash and reddit.com became available while Dazz Cam remained blocked by its separate schedule. This verifies one physical app-and-website release with an overlapping schedule intact.
- Widget taps still pass through the existing subscription, Screen Time authorization, target, Strict, and active-session checks in the app. An idle widget never starts blocking directly.
- The new widget extension builds in the simulator, and the signed app with the extension installed and launched on the paired iPhone. A 15-minute Strict session displayed a countdown in the Dynamic Island while other apps were foregrounded. Widget placement, widget countdown behavior while the app is closed, Lock Screen Live Activity presentation, and its planned-end removal still need direct device observation.

## Rule-aware shield first slice

- The shield extension now reads the App Group's device-local focus, schedule, manual shield, website blocklist, and reached daily-limit records and matches the shielded app, category, or website against saved targets. A matching active focus session shows its planned end and entered intention; a matching schedule shows its name and next transition out of blocking when one is found. Other rules show a reason without a promised end time.
- The message says other rules may still apply, including when one displayed rule ends. Identical descriptions from separate matching schedules are shown once. Unknown or stale rule state falls back to the generic shield. Five unit tests cover matching domains, expired focus state, overlapping focus and schedule rules, manual and website lists, stale daily-limit events, and repeated schedule descriptions; the simulator build succeeds.
- A physical iPhone displayed the correct named schedule and 9:00 PM end time when opening Dazz Cam, which two saved schedules selected. The duplicate description found in the first screenshot was fixed and a second iPhone screenshot showed it once. Actual release at the boundary, other rule types, and overlapping stores still need physical observation. Validation monitor blocks use the generic shield.
- A later check after consolidating store writes again showed the Dazz Cam schedule shield on the paired iPhone. It revealed that a time-only end label was ambiguous after that day's allowed window had passed. The updated shield was then observed on the phone showing “until Oct 21, 2026 at 9:00 PM” on October 20. The date wording also has a unit test. The actual release at that boundary remains unverified.

## Instagram Safari prototype

- `Experiments/InstagramSafari` contains a Safari Web Extension prototype, now embedded in the Noxa app with an off-by-default Instagram website choice. Distraction-Free covers direct Reels and Explore routes and hides links to those sections while leaving the feed and other paths available by route. The extension asks the app-side native handler for permission before changing the page; the handler requires Distraction-Free mode and an unexpired paid entitlement. Its mutation observer now restores the route overlay and hidden-link style if Instagram replaces those nodes. Seven script behavior tests pass.
- Settings now offers Off, Distraction-Free, and Full Block for Instagram. Full Block uses its own Managed Settings website store, separate from schedules and the user's website list. It applies only while the saved entitlement expiry is in the future, clears on sign-out, account deletion, or entitlement refresh, and reconciles at app launch and foreground. An old on/off Safari preference migrates into Distraction-Free. On the paired iPhone, selecting Full Block produced Safari's “Website Not Allowed” screen at `instagram.com/explore/`; after returning to Off, that URL loaded Instagram again. The temporary test restored Off and was removed from the repo.
- Apple notes that enabling a web-content filter can disable Safari Private Browsing. Settings explains this. The Instagram app remains a separate all-or-nothing selection.
- The extension is not verified on signed-in Instagram in Safari. Instagram's dynamic markup, embedded feed Reels, permission state, and physical-device behavior must be checked before claiming selective filtering. Safari extension enablement is not proof that website access was granted or the script changed the page.
- The Safari manifest now declares the two supported Instagram hosts explicitly. A selective-filter content script that reaches an Instagram page sends its host to the native handler, which records only a last-contact timestamp after checking site, mode, and entitlement. Settings distinguishes a recent connection from extension enablement and offers Full Block when no connection is seen. This remains a diagnostic, not proof that all page elements were suppressed. Seven script tests and the signed iPhone build pass.

## Schedule reminders and shortcuts

- Start and end schedule reminders are independently optional and off by default. The schedule monitor posts a reminder only when its corresponding configured boundary actually changes the rule's blocking state, and skips callbacks over three minutes late. Older saved schedules decode with both reminders off. Notification denial does not affect schedule enforcement. Apple documents that Device Activity callbacks can wait until device use, so Settings warns that reminders may be late; delivery timing still needs a real-device boundary test.
- The Start Focus App Shortcut opens the existing one-hour duration and policy review through the same launch router as the widget. It does not start a session in the background. On the paired iPhone, the `noxa://focus/start` route opened a review with one hour selected, the selected targets, an end time, and the Strict warning before Start. The temporary UI test dismissed it without starting a session. Shortcuts discovery and the actual widget tap still need device validation.

## Daily limit warning candidate

- Daily-limit monitoring requests a warning callback about five minutes before each usage threshold. The monitor checks that the limit is still enabled and not already reached, deduplicates by limit and local day, and posts a local notification if notifications are allowed. The first signed build accidentally set `warningTime` on the validation monitor rather than the daily-limit monitor; this is corrected. On the paired iPhone, a temporary test used Fantasy outside the known schedule blocks, changed its 30-minute limit to 10 minutes, and recorded the warning and reached callbacks five minutes apart. It then stopped monitoring and restored 30 minutes. This verifies the callback path for that target, but the phone's displayed notification and other device states still need checks.
- The daily-limit screen now explains that alerts need notification permission and may arrive late. Its permission status refreshes when Noxa returns to the foreground. Limit enforcement does not depend on notification permission.

## Weekly schedule follow-through

- The Stats screen now shows the share of tracked schedule windows that stayed enabled through their planned end in the last seven local days. Creating, editing, enabling, disabling, or deleting a schedule records a small device-local configuration event without target tokens or usage data. Existing schedules begin tracking when this version opens, so old windows are not backfilled. Edits to reminder preferences alone do not interrupt a window. The UI explicitly says this is not measured app use or proof of blocking. The device UI layout was checked, and 75 unit tests pass, including daylight-saving boundary coverage.
