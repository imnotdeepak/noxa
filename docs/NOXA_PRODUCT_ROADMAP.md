# Noxa — Product Roadmap & Next-Feature Specification

**Document type:** Product strategy and implementation roadmap

**Status:** Product decisions approved; implementation and platform validation pending

**Last updated:** October 18, 2026

**Repository:** https://github.com/imnotdeepak/noxa

---

## 1. Executive Summary

Noxa should become a simple, reliable system for controlling when people can access digital distractions. The product promise remains:

> **Take back your attention.**

Noxa should help people block distractions, set repeatable boundaries, and retain access to useful parts of websites when the platform can support that reliably.

The approved development order is:

1. Strengthen restriction ownership, reconciliation, automated tests, and physical-device validation.
2. Keep the existing subscription-before-use flow, then guide paid users into a first active focus session.
3. Expand today's allowed-window schedules into user-named schedules with both allowed and blocked hours, selected weekdays, overnight windows, and immediate changes.
4. Prototype and release **Distraction-Free Safari**, beginning with Instagram Reels and Explore. Validate Instagram before expanding to YouTube.
5. Add an opt-in Strict focus-session toggle, automatic four-round Pomodoro cycles, weekly schedule adherence, and a start-and-timer widget experience as their dependencies are proven.

Strict mode has one job: prevent a focus session from being ended early inside Noxa. It is off by default, applies only to future sessions, permits no breaks, and limits Strict sessions to four hours. Normal sessions retain their current early-end flow and eight-hour maximum.

Noxa should not become an AI coach, social network, general habit tracker, or gamified productivity platform. Its advantage should be effective controls with low complexity and affordable pricing. All features in this roadmap belong in the current subscription; no separate tier is planned.

---

## 2. Current Product Baseline

The repository contains initial implementations of the following capabilities. This is a code-review baseline, **not proof of a successful build or physical-device enforcement**.

| Area | Current implementation observed |
| --- | --- |
| Focus sessions | Configurable duration, active-session recovery, and an early-end ritual |
| App/category blocking | Apple's Screen Time APIs using opaque selection tokens |
| Website blocking | Domain-level restrictions |
| Daily app limits | Usage thresholds and enforcement |
| Schedules | Up to eight daily **allowed windows**; selected apps are blocked before and after the window; disabling an active schedule is delayed 24 hours |
| Pomodoro | One work interval, an automatically timed break, and a notification inviting a manual next start |
| Notifications | Session, Pomodoro, and completion notifications where permitted |
| Statistics | Focus minutes, history, completion rate, and streaks |
| Accounts/subscriptions | Supabase and StoreKit integration; payment precedes use |
| Sync | Focus history and website domains |
| Automated testing | Core state tests, a schedule persistence test, and limited UI coverage |

**Gaps relative to the approved direction:** named weekly and overnight schedules; both allowed and blocked windows; schedule overlap and migration; an onboarding path that reaches an active first rule after payment; automatic Pomodoro cycles; the Strict toggle; feature-level Instagram filtering in Safari; and stronger proof of real-world enforcement.

Some implementation details may change. Audit the relevant files, build the app, and validate on physical devices before turning this roadmap into release claims.

---

## 3. Product Principles

1. **Protection without friction:** Setup should be clear and routine execution automatic.
2. **Simple before smart:** Prefer explicit schedules and user-defined rules over opaque recommendations.
3. **Respect user choice:** Users choose their targets, schedule names, and whether to enable Strict; the app explains each restriction before it starts.
4. **Never silently weaken blocking:** An allowed window or expired rule cannot override another active block. Any active block wins.
5. **Privacy by default:** Keep opaque Screen Time tokens and sensitive enforcement state on-device where required; sync only suitable settings and history.
6. **Platform honesty:** Do not promise an impossible-to-bypass Strict mode, native-app feature filtering, or guaranteed Safari selectors.
7. **Measure meaningful outcomes:** Track successful paid activation, dependable enforcement, and repeat usefulness rather than time spent in Noxa.
8. **Safe recovery:** A failed restriction or stale shield needs a clear technical recovery path, even though Strict offers no routine early-end control.

---

## 4. Prioritized Feature Backlog

Effort ratings are relative estimates, not delivery timelines. The order below follows dependencies rather than simply grouping features by appeal.

| Priority | Feature | Expected impact | Relative effort |
| --- | --- | --- | --- |
| P0 | Rule ownership, effective restrictions, reconciliation, and device validation | Foundational | High |
| P0 | Paid onboarding to a first active focus session, including notification education | High | Medium |
| P0 | Expanded named schedules and migration of existing allowed windows | Very high | High |
| P0 | Instagram Distraction-Free Safari prototype, then supported release | Very high | High |
| P1 | Opt-in Strict focus sessions | High | Medium |
| P1 | Automatic four-round Pomodoro cycles | High | High |
| P1 | Rule-aware shields and weekly schedule adherence | Medium–high | Medium |
| P2 | Daily-limit warnings and refinements | Medium | Low–medium |
| P2 | Home and Lock Screen widgets, an active-session Live Activity, and shortcuts | Medium–high | Medium–high |

Temporary unlocks, timed breaks, schedule templates, and a separate subscription tier are **not planned for this cycle**.

---

## 5. Feature Specifications

### 5.1 Expanded Recurring Schedules

**Objective:** Build on the existing allowed-schedule feature so users can set repeatable boundaries once.

Users create and name their own schedules. Noxa does not ship Study, Sleep, or Work schedule templates in the initial release. Example user-created schedules include blocking selected distractions on weekdays from 9:00 AM to noon, or allowing selected apps only from 9:00 PM to 10:00 PM. Names help explain which rule is active.

**Core functionality**

- Create, name, edit, enable, disable, and delete schedules.
- Choose **Blocked hours** or **Allowed hours** for each schedule.
- Select apps, app categories, websites, or any combination; website-only schedules are valid.
- Select repeating weekdays and local start/end times, including overnight windows.
- Follow the device's current local time; validate travel, daylight-saving, and clock changes.
- Apply edits and disabling immediately. A separate active rule may still require the target to remain blocked.
- Permit overlapping target selections. An allowed window never releases a target blocked by a different active schedule, focus session, or reached daily limit.
- Show the active schedule's name, current effect, and next change time on the home screen. Tapping reveals its targets.
- Offer optional schedule start/end notifications, off by default.
- Restore expected state after app termination, reboot, or delayed callbacks within observed iOS behavior.

**Migration of existing schedules**

Convert each existing schedule to a named **Allowed hours, every day** schedule with the same selected apps and times. Preserve its effective blocking behavior across upgrade. Users may then edit or disable it immediately. Test migration with active, disabled, and pending-24-hour-change records; define how a pending change is resolved without unexpectedly weakening or extending a block.

**Suggested data concepts**

- `RestrictionSchedule`: stable ID, user name, allowed/blocked mode, selected targets, weekdays, local times, enabled state.
- `ActiveRuleInstance`: stable source and timing information.
- `EffectiveRestrictions`: targets required by all active rules, with contributing reasons.

**Acceptance criteria**

- Weekly and overnight schedules activate and end at the intended local times.
- Two overlapping schedules do not release each other's restrictions.
- Ending a focus session does not clear a block still required by a schedule or daily limit.
- Existing schedules retain their effective behavior after migration.
- An immediate edit updates only that schedule's contribution.
- Users can see why a target is blocked and when the relevant schedule next changes.

### 5.2 Distraction-Free Safari

**Objective:** Keep useful parts of supported websites available in Safari while suppressing selected distractions.

For each supported website, users choose:

- **Full Block:** Restrict the whole site using suitable platform controls.
- **Distraction-Free:** Keep the site available in Safari while suppressing documented sections.

**First site: Instagram web in Safari**

- Suppress Reels and Explore in navigation and at direct links, if the extension prototype proves reliable.
- Keep the main feed available.
- Preserve messages, search, profiles, and other useful navigation where verified.
- Make clear that selective filtering does not change the native Instagram app. The native app can be blocked as a whole through Screen Time.

Instagram is the first prototype and release candidate. Validate it before beginning YouTube filters. Candidate YouTube controls for a later release include Shorts and recommendation sections.

**Core functionality**

- Plain-language per-site filter descriptions and a visible enabled/permission state.
- Guidance for Safari extension permission.
- A simple in-app **Report a problem** action.
- If a filter is known to be unavailable or broken, warn the user and offer Full Block; do not silently switch modes or imply successful enforcement.
- Document unsupported sign-in states, localization, browser surfaces, and site changes honestly.

**Acceptance criteria**

- Reels and Explore are suppressed on documented Instagram test states, including direct links.
- The main feed and verified useful functions remain usable.
- Permission loss and known filter failures are visible to the user.
- The team can update or disable a broken filter without a misleading “protected” status.

### 5.3 Paid Onboarding to First Activation

**Objective:** Help a paying user reach a first successfully activated restriction without unrelated navigation.

**Approved flow**

1. Choose goals and distraction types.
2. Explain the app's blocking capability and the existing subscription requirement.
3. Complete subscription before using Noxa's blocking features.
4. Explain why notifications matter and offer permission; declined notifications must not prevent local enforcement.
5. Grant Screen Time authorization with a useful denial/retry path.
6. Use earlier answers to suggest relevant targets, then let the user choose actual apps, categories, or websites. At least one target is required before a session starts.
7. Offer a first focus session with **30 minutes selected by default**, while allowing duration changes.
8. Show a short review of targets, duration, and exact end time. Once Strict is available, also show whether it is on. Then the user taps **Start Focus**.
9. Distinguish rule configuration, application requested, and confirmed enforcement. Show an honest result and recovery guidance if activation fails.
10. After the first completed session, offer a one-time optional prompt to make its targets into a recurring schedule.

Once Strict ships, keep it off by default. Offer it once when a new user first lands on the home screen, with a clear decline option; keep the toggle available in Settings without repeated prompting.

**Primary metric:** Share of new paying users who configure and activate a first meaningful blocking rule. Purchase and onboarding-screen completion do not count as activation.

### 5.4 Strict Focus Sessions

**Objective:** Offer an optional commitment that prevents ending a focus session early inside Noxa.

- Put a **Strict focus sessions** toggle in Settings. It is off by default for new and existing users.
- Changing the toggle affects **future sessions only**. Persist each session's mode at start; turning the setting off during a Strict session does not cancel that session.
- With Strict off, retain the current early-end ritual and eight-hour maximum.
- With Strict on, remove routine in-app early end and timed breaks; cap the session at four hours.
- Before starting, clearly warn that the session cannot be ended early in Noxa and show its exact end time.
- Apply the same rule to Pomodoro **work intervals**. The user may stop the Pomodoro cycle during a scheduled break.
- Do not describe Strict as impossible to bypass through device settings or authorization changes.
- Preserve technical recovery for failed start, stale shield, revoked permission, or cleanup failure. Recovery is not a routine break.

**Acceptance criteria**

- A session keeps the mode selected at its start even if the Settings toggle later changes.
- No early-end action appears for an active Strict work interval.
- Normal sessions retain the existing early-end flow.
- Strict sessions cannot be set beyond four hours, and users see the correct planned end time.
- A session reaching its planned end releases only restrictions no other rule still requires.

### 5.5 Automatic Pomodoro Cycles

**Objective:** Turn the current single work-and-break pair into an automatic, bounded cycle.

- Run four work intervals per cycle by default, with a scheduled break between them; no round-count setting in the initial release.
- Automatically begin the next work interval when its break ends. Do not depend on notification permission for this transition.
- During each break, notify halfway through and one minute before the break ends when notifications are authorized.
- Allow the user to stop the cycle during a break. Under Strict, do not allow stopping during a work interval.
- After the fourth work interval, stop and notify that the cycle is complete. Tapping the notification opens Noxa to offer **Start another cycle**; a direct background start action requires separate validation.
- Persist the current phase, round count, planned transitions, and stop intent so the cycle reconciles after app termination or reboot.

**Acceptance criteria**

- Each work interval blocks its selected targets and each break releases only the Pomodoro rule's contribution. Other active rules remain enforced.
- The next work interval starts at the intended time on tested physical devices, including when Noxa is closed.
- Stop requests during breaks prevent the next interval.
- Notification denial does not halt or change the cycle.
- Delayed callbacks and relaunch do not skip, duplicate, or indefinitely extend a round.

### 5.6 Rule-Aware Shield Screens

**Objective:** Explain a block without adding an unintended escape path.

Where supported, show the active blocking rule's name and end time, plus the user's focus intention when one was entered. If multiple rules apply, avoid implying that the earliest ending rule will release the target. Keep the permitted action clear and accessible. Validate what data can be shared with the shield extension and what the platform allows it to display.

### 5.7 Usage and Focus Insights

**Objective:** Show whether boundaries are working without turning Noxa into a dashboard-heavy analytics product.

Prioritize **weekly schedule adherence**. Then improve completed versus early-ended session history and progress toward personal focus goals. Explore privacy-preserving Screen Time reports only where Apple's APIs and entitlements permit them. Do not present focus minutes as measured screen time saved.

### 5.8 Home and Lock Screen Widgets, Live Activity, and Shortcuts

**Objective:** Let users begin a focus session from a widget and see the remaining time without opening Noxa.

- Add a Home Screen widget with a **Start Focus** action when idle and remaining time when a focus session is active.
- Add a compact Lock Screen widget that opens the focus-start path when idle and shows session status when active, within the layout and interaction limits of the supported iOS versions.
- Start a Live Activity with each active focus session so the Lock Screen can show a current countdown. Where supported, also show it in the Dynamic Island. End or reconcile the Live Activity when the session completes, ends early, or is recovered.
- Tapping **Start Focus** opens a compact, prefilled start screen in Noxa. It uses the saved target selection, offers a duration choice with **one hour selected by default**, shows the exact end time, and requires the user to tap Start. This widget default does not change the 30-minute default in first-use onboarding.
- Before starting, validate subscription, Screen Time authorization, target selection, current session state, and the selected Strict policy. A Strict session must show its no-early-end warning and exact end time on this screen.
- If the widget cannot start a valid session, take the user to the relevant setup or recovery screen instead of displaying a false active state.
- Keep the widget and Live Activity synchronized with the same on-device session record used by enforcement. Treat the app's persisted record as desired/last-known state, not proof of currently enforced blocking.
- Add shortcuts after the shared start path is reliable. Optional direct widget actions and Control Center controls require separate device validation.
- Do not add Study, Sleep, or Work schedule templates in the initial release; users create their own schedules.

**Acceptance criteria**

- An idle widget opens the prefilled duration-and-review screen with one hour selected; an active widget displays the correct planned end or remaining time.
- The Lock Screen shows a readable countdown during a session through the Live Activity on supported devices, including while Noxa is closed.
- Widget state returns to idle after completion, early end, or recovery; it never offers a second concurrent session.
- Strict sessions cannot be started from a widget without the required warning and end-time review.
- Permission loss, expired subscription, missing targets, and stale session state lead to clear recovery rather than a false success.

### 5.9 Daily-Limit Warnings and Refinements

- Warn shortly before an allowance runs out where physical-device threshold tests confirm reliable timing.
- Explain clearly when a limit has been reached and which rule is blocking a target.
- Allow immediate editing or disabling of daily limits. Other active rules continue to apply.
- Validate reset behavior, timezone changes, and overlap with focus sessions and schedules.

---

## 6. Required Architecture: Unified Rule Evaluation

Sessions, schedules, daily limits, and Pomodoro intervals currently have separate paths for applying and clearing blocking state. Some restrictions already use separate named settings stores, which helps preserve overlaps. The next step is to make ownership and the **effective required restrictions** explicit across all paths; do not replace working behavior wholesale without tests.

### 6.1 Proposed Logical Flow

```text
User-defined rules
  ├── Manual focus sessions, including per-session Strict state
  ├── Named allowed/blocked schedules
  ├── Daily usage limits
  └── Pomodoro work intervals and break transitions
                   │
                   ▼
             Noxa rule evaluation
  - Normalize active rules and targets
  - Resolve allowed-window timing
  - Union all independently required blocks
  - Record contributing reasons
  - Reconcile requested and applied state
                   │
          ┌────────┴─────────┐
          ▼                  ▼
  iOS Screen Time      Safari extension
  App/category/domain  Supported web-section
  restrictions         filtering
```

### 6.2 Non-Negotiable Invariants

1. Every active restriction has one or more contributing rules.
2. **Any active block wins.** An allowed schedule window never cancels a different active block.
3. Ending a session, Pomodoro interval, schedule, or daily limit removes only its own contribution.
4. A Pomodoro break releases only the Pomodoro work rule. A separate schedule or reached daily limit stays enforced.
5. A Strict session's no-early-end policy is captured at start and is independent of later Settings changes.
6. Reconciliation recomputes desired state after callbacks, launches, permission changes, time changes, and recovery.
7. The UI can explain which active rules require a block and distinguish known enforcement from pending or uncertain state.
8. Opaque selection tokens and necessary enforcement state remain in appropriately protected on-device storage.
9. A technical cleanup path remains available when the app detects a failed or stale restriction.

### 6.3 Example Edge Cases

- A Study schedule's allowed window opens, but Instagram's daily limit has been reached: Instagram remains blocked.
- A focus session ends while a schedule blocks the same app: the app remains blocked.
- A Pomodoro break starts while a daily limit blocks YouTube: YouTube remains blocked.
- A Strict toggle is turned off during an active Strict session: the active session retains its no-early-end policy; later sessions use the new setting.
- A user immediately disables one schedule while another schedule blocks the same website: only the disabled schedule's contribution ends.

### 6.4 Engineering Work Before New UI

- Inventory every code path that applies, changes, or clears `ManagedSettings` restrictions.
- Define versioned rule and schedule models, including migration of the current allowed-window data.
- Centralize effective-restriction computation and rule-reason reporting.
- Make state updates idempotent across app and extension boundaries.
- Persist only the state needed for reconciliation and recovery.
- Add deterministic tests for overlap, migration, expiry, Pomodoro transitions, Strict persistence, and restart scenarios.
- Preserve existing single-session behavior while migrating incrementally.

---

## 7. Release Roadmap

### Phase 1 — Foundation and Paid First-Use Reliability

**Deliverables:** Baseline build/test record; restriction-path inventory; shared rule ownership and evaluator; overlap/recovery tests; paid onboarding that guides users to a first active session; notification education; physical-device test matrix.

**Exit criteria:** A paying new user can activate a real restriction, declined notifications do not prevent enforcement, and one rule ending does not defeat another.

### Phase 2 — Expanded Automation

**Deliverables:** Migration of existing schedules; user names; allowed and blocked hours; weekdays and overnight windows; combined app/category/website targets; immediate edits; active schedule status; optional reminders.

**Exit criteria:** Migrated users retain their effective blocks, and new schedules operate while the app is closed within tested platform constraints. Overlap and time-change tests pass on physical devices.

### Phase 3 — Instagram Safari Differentiation

**Deliverables:** Safari extension setup and permission education; Instagram Reels and Explore filtering; direct-link handling; Full Block choice; honest filter status; broken-filter reports.

**Exit criteria:** Documented Instagram states suppress Reels and Explore while the main feed and verified useful functions remain available. Unsupported or failing states are communicated accurately. Begin YouTube only after this gate.

### Phase 4 — Strict, Pomodoro, and Rule-Aware Shields

**Deliverables:** Off-by-default future-session Strict toggle and one-time home-screen offer; four-hour Strict cap and end-time warning; automatic four-round Pomodoro; break notifications; stop-during-break behavior; shields showing rule reasons and end times where supported.

**Exit criteria:** Strict does not alter normal sessions, Pomodoro transitions reconcile when the app is closed, and breaks never release restrictions owned by other rules.

### Phase 5 — Insights and Convenience

**Deliverables:** Weekly schedule adherence; improved focus history; daily-limit warnings; Home Screen start/status widget; Lock Screen start/status widget; active-session Lock Screen Live Activity countdown; shortcuts after the shared start path is validated.

**Exit criteria:** Noxa communicates meaningful progress and requires fewer interactions without weakening enforcement or overstating measured results.

---

## 8. Quality, Privacy, and Release Gates

**Real-device behavior is a release requirement.** Test at least these scenarios on supported physical iOS versions:

| Scenario | Expected result |
| --- | --- |
| Focus session starts and ends | Correct targets block and release according to all remaining rules |
| Two overlapping schedules or a schedule plus session | Ending one leaves the other's block in place |
| Allowed window opens after a daily limit is reached | The daily-limit block remains |
| Existing schedule upgrades | Same effective allowed window and targets remain before the user edits it |
| Immediate schedule or daily-limit edit | Only the edited rule's contribution changes |
| Overnight schedule and travel/time changes | Start/end behavior follows the documented local-time rule |
| App force-quit, termination, and reboot | State reconciles and UI reports only what is known |
| Screen Time permission revoked | UI shows the real authorization state and recovery guidance |
| Strict toggle changes during a session | Active mode remains fixed; future sessions follow the new setting |
| Strict session reaches planned end | Its restrictions release unless another rule still requires them |
| Pomodoro break and automatic restart | Four rounds proceed without duplicate or missed transitions; user can stop during breaks |
| Notifications declined | Focus, schedules, and Pomodoro enforcement remain functional |
| Widget starts or opens a focus session | Subscription, authorization, targets, Strict policy, and concurrency are validated before success is shown |
| Active session on Lock Screen | Live Activity countdown matches the planned end and clears after completion or recovery |
| Instagram site or permission changes | Known filter failure is surfaced; Full Block is offered |
| Subscription expires during a session | Existing session finishes and releases safely; new sessions require renewal |

**Testing approach**

- Unit-test rule evaluation, migration, Strict mode persistence, and Pomodoro phase transitions with synthetic scenarios.
- Integration-test adapter boundaries, persistence, and recovery.
- Maintain a physical-device test record for Screen Time, Safari, notifications, upgrade migration, and background callbacks.
- Add UI tests for paid onboarding activation, permission recovery, schedule creation, Strict warnings, and active-rule status.
- Test accessibility for onboarding, schedules, shields, Strict warnings, and recovery actions.
- Do not claim a restriction is enforced based only on saved intent or last-known metadata.

**Privacy:** Limit collection, keep Screen Time selection data appropriately on-device, describe what syncs through Supabase, and avoid sending detailed third-party app usage to a server unless needed and permitted.

---

## 9. Success Metrics

| Goal | Suggested measure |
| --- | --- |
| First-use success | Share of new paying users who configure and activate a first blocking rule |
| Reliability | Share of tested rule transitions with correct effective restrictions |
| Schedule usefulness | Share of active users with at least one enabled recurring schedule |
| Pomodoro reliability | Share of planned round transitions that occur correctly, including with the app closed |
| Widget usefulness | Widget start-path completion and accurate active-session countdown state |
| Retention | Week-1 and week-4 retention by successful activation status |
| Safari utility | Instagram filter usage, repeat use, and known failure reports |
| Support burden | Reports of incorrect unblocking, lingering blocks, permission confusion, or broken filters |

Do not treat focus-session duration as a precise estimate of screen time saved.

---

## 10. Explicitly Out of Scope for This Cycle

- Timed breaks, temporary unlock allowances, or an early-end option in Strict sessions.
- Separate Flexible/Intentional/Strict modes on each profile; Strict is one global toggle for future focus sessions, while non-Strict retains today's early-end flow.
- Study, Sleep, and Work schedule templates in the initial release.
- A separate subscription tier for these features.
- An AI accountability coach, social network, leaderboards, RPG, virtual pet, generalized habit tracker, or complex productivity score.
- Claims that Noxa removes Reels or Explore inside the native Instagram app.
- Android or macOS expansion before core iOS reliability and retention are demonstrated.

---

## 11. Immediate Engineering Backlog

- [ ] Record a passing build and test baseline on the current codebase.
- [ ] Map every app and extension path that sets or clears blocking state.
- [ ] Document the rule ownership and any-active-block-wins policy.
- [ ] Implement effective-restriction computation with overlap and recovery tests.
- [ ] Add versioned schedule migration tests before changing persisted schedules.
- [ ] Update paid onboarding: notification education, target suggestions and selection, first-session review, activation state, and one-time post-session schedule prompt.
- [ ] Extend schedules with names, allowed/blocked mode, weekdays, overnight timing, mixed targets, immediate changes, reminders, and active status.
- [ ] Test schedules and migration on physical devices, including overlap, overnight, restart, and permission changes.
- [ ] Prototype Instagram Safari filtering for Reels and Explore, including direct links; test useful functionality and failure states.
- [ ] Add per-site Full Block choice, filter status, and in-app broken-filter reporting.
- [ ] Implement the off-by-default Strict toggle with per-session persistence, four-hour cap, warning, and no routine early end.
- [ ] Implement four-round automatic Pomodoro state and notification timing; validate background transitions.
- [ ] Add rule-aware shields, weekly adherence insights, and daily-limit warnings.
- [ ] Add Home and Lock Screen widget start/status surfaces and a focus-session Live Activity countdown; verify lifecycle and Strict-policy behavior.
- [ ] Add shortcuts and optional direct controls after the shared start path is validated.
- [ ] Run the release quality, accessibility, privacy, and physical-device matrix before public claims.

### Recommended First Milestone

Ship a **paid first-use flow and a reliable user-created schedule**: after payment, a new user chooses real targets and starts a 30-minute-default focus session; then they can create a named schedule. The schedule supports blocked or allowed hours, overlaps safely with a reached daily limit, and survives tested app lifecycle events. Existing schedules migrate without changing their effective behavior.

Instagram Distraction-Free Safari is the next differentiated release after that foundation is dependable.

---

## 12. Platform References to Validate During Implementation

These are documentation entry points, not guarantees that every proposed interaction is supported in every iOS configuration:

- Apple Developer — [FamilyControls](https://developer.apple.com/documentation/familycontrols)
- Apple Developer — [DeviceActivity](https://developer.apple.com/documentation/deviceactivity)
- Apple Developer — [ManagedSettings](https://developer.apple.com/documentation/managedsettings)
- Apple Developer — [DeviceActivityReport](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport)
- Apple Developer — [Safari Web Extensions](https://developer.apple.com/documentation/safariservices/safari_web_extensions)
- Apple Developer — [UserNotifications](https://developer.apple.com/documentation/usernotifications)
- Apple Developer — [WidgetKit](https://developer.apple.com/documentation/widgetkit)
- Apple Developer — [ActivityKit](https://developer.apple.com/documentation/activitykit)
- Apple Developer — [App Intents](https://developer.apple.com/documentation/appintents)

Reconfirm API contracts, entitlement requirements, review policies, supported OS versions, and device behavior when implementing each feature.

---

## 13. Final Product Direction

Noxa should help users set effective boundaries once, reliably enforce them, and keep useful digital tools available where selective filtering is feasible.

The near-term product bets are:

1. **Expanded recurring schedules** — the feature that makes Noxa useful every day.
2. **Instagram Distraction-Free Safari** — the first selective-access feature that differentiates Noxa from whole-site blockers.
3. **Simple optional commitment** — Strict focus sessions and automatic Pomodoro cycles that follow the user's chosen policy without silently weakening other rules.

Reliability, clear onboarding after payment, and honest platform behavior support all three bets.
