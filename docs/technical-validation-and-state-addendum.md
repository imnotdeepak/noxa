# Noxa MVP — Technical Validation and State Addendum

Status: working implementation plan derived from `app-spec-v2.2.md`.

This document converts the product specification into testable engineering work. It is intentionally conservative: Apple Screen Time behavior observed on physical devices is authoritative over assumptions in the product spec.

## 0. Project prerequisites

Complete and record these items before running the validation spikes:

- confirm the shipping bundle identifier; the current project uses `LycheeCorp.Noxa`
- align the Xcode deployment target with the product requirement; the project currently targets iOS 26.5 while the product specification says iOS 16+
- create the main app, `DeviceActivityMonitor`, and shield-extension targets required by the spike being tested
- enable Family Controls on every applicable target and record whether the build uses development or distribution authorization
- do not add the separate Family Controls App and Website Usage capability for this MVP unless the product explicitly chooses to access non-tokenized activity data; the MVP should continue using opaque tokens
- create one App Group shared by the main app and extensions; proposed identifier: `group.LycheeCorp.Noxa`
- confirm every target uses the same signing team and compatible capabilities
- define unified logging categories for authorization, selection persistence, monitoring, shielding, session lifecycle, and recovery
- ensure logs contain opaque local IDs only and never serialize Screen Time tokens for analytics or remote diagnostics

### Minimum test matrix

Test the oldest supported iOS version and the current shipping iOS version on physical devices. Add an intermediate version when behavior differs or a relevant API changed. For each version, cover:

- clean install and upgrade install
- foreground, device lock, normal backgrounding, and operating-system termination
- user force-quit from the app switcher
- debugger/Xcode process stop, recorded separately from force-quit
- deliberate test crash, recorded separately from termination
- online, airplane mode, and network restoration
- authorization granted, denied, and later revoked

Do not treat Simulator results as proof of Screen Time enforcement behavior.

## 1. Release gate

Do not finalize onboarding copy, App Store claims, or the public blocking promise until all six spikes below have a written result on supported physical iPhones.

Each spike must record:

- device model, iOS version, build number, and entitlement status
- exact steps and timestamps
- expected result versus observed result
- screenshots/video or logs where useful
- whether the result is reliable after repeating the test at least three times
- product decision required if the behavior is unsupported or inconsistent

Use this result template for every device/OS combination:

```text
Spike:
Date:
Tester:
Build/commit:
Device model:
iOS version:
Signing and entitlement mode:
Installation state: clean / upgraded
Preconditions:
Procedure:
Expected result:
Observed result:
Observed timing/tolerance:
Relevant local logs:
Repetitions passed / attempted:
Result: pass / conditional pass / fail
Product or engineering decision:
Follow-up owner:
```

The release gate is passed only when the team can answer, with evidence:

1. Which restrictions survive main-app termination and device lock?
2. How are restrictions removed if the app crashes, loses network, or is force-quit?
3. Which callbacks and schedules survive a reboot?
4. Can a daily limit be paused during a focus session without counting focus time?
5. What website restrictions are enforceable, and what is the tested domain capacity?

## 2. Physical-device validation spikes

### Spike A — Family Controls authorization

**Objective:** establish the permission lifecycle and user-facing recovery path.

**Steps:**

1. Request individual authorization from a clean install.
2. Test grant, deny, and later revocation in Settings.
3. Relaunch after each result; also test app termination before relaunch.
4. Confirm the main app reports the correct authorization state.
5. Confirm each extension can perform only the operations it needs under each authorization condition; do not assume every target exposes the same status interface.

**Pass criteria:** the app never presents a false “enabled” state; denial and revocation produce a retry/Settings path; all dependent actions are disabled with an explanatory message.

If the SDK exposes `approvedWithDataAccess`, treat it as authorized for shielding purposes but do not infer that Noxa may use non-tokenized activity data. Access to that data requires the separate App and Website Usage capability and is outside this MVP.

### Spike B — App shielding

**Objective:** prove that a selected app can be shielded and unshielded without the SwiftUI process remaining alive.

**Steps:**

1. Select one app with `FamilyActivityPicker`.
2. Persist the selection in the App Group.
3. Apply and verify a `ManagedSettings` shield.
4. Test normal backgrounding, device lock, operating-system termination, user force-quit, debugger stop, and a deliberate crash as distinct cases.
5. Relaunch after each condition.
6. Remove the shield and verify normal access.
7. Repeat with an application category and with multiple selected applications after the single-application case passes.

**Pass criteria:** the selected app is blocked while the restriction is active; removal is reliable; a stale shield can be identified and recovered; no bundle identifier is required for the product data model.

### Spike C — DeviceActivity threshold

**Objective:** prove that the monitor extension receives a threshold callback and can apply a shield.

**Steps:**

1. Configure a short threshold for one selected app.
2. Start monitoring through the intended production path.
3. Use the app until the threshold is reached.
4. Confirm the `DeviceActivityMonitor` callback, shield application, and local event persistence.
5. Repeat with the main app terminated.

**Pass criteria:** the callback arrives within a documented tolerance; the extension can enforce the shield independently; duplicate callbacks are safe; a warning threshold can be distinguished from the final threshold if supported.

### Spike D — Timed focus session

**Objective:** prove the end-to-end focus lifecycle while the app is not active.

**Steps:**

1. Start a short session with one app restriction only.
2. Persist a start intent before applying restrictions; mark the session active only after every intended restriction succeeds.
3. Lock the device and test each termination condition from the minimum test matrix.
4. Wait for the planned end time.
5. Confirm the app restriction is removed and the session is reconciled.
6. Repeat the test with one website restriction only.
7. Repeat with app and website restrictions together.
8. Test ending early and extending the duration while foregrounded and backgrounded.
9. Repeat the applicable cases without a network connection, then restore the network and confirm synchronization converges.

**Pass criteria:** session start is atomic; enforcement does not depend on a live SwiftUI process where the tested platform supports that behavior; end-of-session cleanup is reliable or produces a recoverable stale state; a network outage does not leave an otherwise authorized user unable to manage local restrictions.

### Spike E — Website blocking

**Objective:** define exactly what domain restrictions mean on target iOS versions.

**Steps:**

1. Add a normalized domain such as `reddit.com`.
2. Test the root domain, common subdomains, redirects, paths, and Safari private browsing behavior.
3. Test duplicate entries, invalid domains, internationalized domains, and bundle-plus-custom overlap.
4. Increase the active list until the platform limit is reached.

**Pass criteria:** normalization and validation are deterministic; the UI prevents unsupported configurations; user-facing copy describes tested behavior without promising private-browsing behavior that is not verified.

### Spike F — Device restart and recovery

**Objective:** establish behavior after reboot and define safe reconciliation.

**Steps:**

1. Start a session and reboot during the session.
2. Repeat with the main app terminated before reboot.
3. Inspect restrictions, schedules, extension callbacks, and App Group metadata.
4. Relaunch the app before and after the planned end time.
5. Repeat with permission revoked and with an expired entitlement.
6. Record separately what is known from persisted intent, what the system reports, and what is observed by attempting to access the restricted app or website.

**Pass criteria:** observed behavior is documented per iOS version; stale local state is reconciled; the app never claims a session is active when it cannot safely determine enforcement state.

## 3. Authoritative state and invariants

### Authority rules

- **Apple's local Screen Time configuration** is authoritative for restrictions the app has asked the system to enforce, within the observability Apple provides.
- **Persisted App Group state** records desired configuration, session intent, and the last known application/cleanup result. It may become stale and is not proof that a restriction is currently enforced.
- **StoreKit 2** is authoritative for current iOS entitlement access.
- **Supabase** stores synchronized product data and history; it is not authoritative for active enforcement or entitlement access.
- Cloud writes are asynchronous, retryable, and idempotent. A failed cloud write must not undo a successful local restriction.
- The UI must distinguish confirmed state, pending state, and state that requires reconciliation rather than presenting last-known metadata as certainty.

### Focus-session engine state

The local engine describes whether the device is currently managing a session:

```text
idle
starting
active
ending
reconciling
```

### Persisted session outcome

A created session record has a lifecycle/outcome separate from the engine state:

```text
start_pending
active
completed
ended_early
failed_to_start
interrupted
recovered_stale
```

Required invariants:

- At most one local session may have an outcome of `start_pending` or `active`.
- A `start_pending` record is persisted before restrictions are applied or the UI reports a successful start.
- A session is not `active` until every intended restriction has been applied.
- If any restriction fails during start, roll back every restriction already applied and mark the session `failed_to_start`. Partial sessions are not supported in the MVP.
- Session end is idempotent: repeating cleanup must be safe.
- Cloud history may lag local state but must converge through retry and reconciliation.
- `recovered_stale` is a terminal outcome used when persisted state required recovery and the original completion outcome cannot be established confidently.

### Entitlement state

Represent at least:

```text
unknown
checking
active
grace_period
billing_retry
expired
revoked
verification_failed
```

Product rules to implement and test:

- Never grant new premium access solely because a Supabase row says `active`.
- A temporary network failure must not immediately erase a locally verified entitlement.
- An expired user must retain a safe path to end or remove locally active restrictions.
- Restore purchases must be idempotent and must not silently attach a transaction to the wrong account.

### Onboarding progress and routing

Persist completed milestones and draft answers rather than treating the last visible screen as authoritative:

```text
has_seen_welcome
has_completed_goals
has_completed_distractions
has_seen_capabilities_explainer
has_completed_initial_setup
has_seen_first_session_prompt
draft_personalization_answers
draft_setup_configuration
```

Derive the current route at launch from live facts plus persisted milestones. Routing precedence is:

1. reconcile an active, ending, or stale focus session
2. show a Screen Time recovery path when required permission has been revoked
3. complete required authentication when the selected account policy requires it
4. check or restore StoreKit entitlement
5. show the paywall when entitlement is inactive
6. resume incomplete post-purchase setup
7. show the main product

A previously saved onboarding milestone must never bypass a newly revoked permission, expired entitlement, signed-out account, or incomplete setup.

## 4. Failure and recovery matrix

| Failure | Local behavior | User experience | Cloud behavior |
|---|---|---|---|
| Any intended restriction fails during start | Roll back restrictions already applied and mark `failed_to_start` | Explain that the session could not start; offer retry | Record diagnostic event without Screen Time tokens |
| Shield removal fails | Keep/reconcile local ending state | Show a clear recovery action; never claim normal access | Retry session completion |
| Network unavailable at start | Continue only if a locally verified entitlement, valid authorization, and local enforcement configuration are available | State that history sync will happen later | Queue idempotent session create |
| Network unavailable at end | Remove local restrictions | Show completion locally | Queue session update |
| Main app leaves foreground | Extension/schedule remains responsible only for behavior proven by the corresponding termination test | No special message unless recovery is needed | Reconcile on next launch |
| Permission revoked | Disable dependent configuration and reconcile shields | Explain and provide retry/Settings path | Mark device capability state if needed |
| Entitlement expires mid-session | Apply the chosen product policy; always preserve safe cleanup | Make renewal available without trapping the user | Mirror verified status asynchronously |
| App/device reboot | Inspect persisted metadata and actual restrictions | Reconcile stale state before showing Home | Repair session record after local reconciliation |

## 5. Product decisions required before UI lock

The following decisions should be recorded after the spikes, with the proposed default shown for planning:

1. **Account before purchase:** recommended default is to keep the current flow only if restore/account-linking is tested; otherwise allow purchase and link it idempotently afterward.
2. **Offline start:** allow when StoreKit has a valid locally verified entitlement, Family Controls authorization is valid, and all restrictions can be configured locally; queue cloud synchronization.
3. **Subscription expiration during an active session:** recommended default is to finish the already-started session, then prevent new sessions while preserving safe shield removal.
4. **Editing during a session:** defer changes to the next session and display that explicitly.
5. **Daily reset:** use the device’s current calendar/timezone, document behavior when the timezone changes, and test daylight-saving transitions.
6. **Focus time and daily allowance:** do not promise exclusion until Spike C/D proves a supported implementation.
7. **Completion definition:** count a session as completed only when its planned end is reached and cleanup succeeds or is safely reconciled.
8. **Streak definition:** define timezone, minimum duration, and whether ended-early sessions count before implementing Stats.

## 6. Initial acceptance criteria

- A new user can grant or deny Family Controls and always reach a valid recovery path.
- A configured app remains shielded after each supported termination condition documented by the physical-device matrix.
- A focus session can end without requiring the main app to remain open on every device/iOS combination the release claims to support.
- Starting a session with no effective restriction is impossible and clearly explained.
- When a valid locally verified entitlement and Family Controls authorization are available, a network outage cannot prevent local enforcement or safe restriction removal.
- A stale session is detected on every launch and reconciled before the Home screen reports an active/inactive state.
- StoreKit entitlement truth controls premium access; Supabase status is only a synchronized mirror.
- Website input is normalized, deduplicated, validated, and bounded by the tested platform capacity.
- Account deletion removes cloud account data through an approved server-side flow and clears local Screen Time configuration.
- Every completed, ended-early, failed, interrupted, or recovered session is represented unambiguously in local state and cloud history.
- Repeating start rollback, session cleanup, or cloud synchronization does not duplicate records or leave additional restrictions applied.

## 7. Implementation order after validation

1. Add shared App Group storage and typed local state models.
2. Implement the blocking/reconciliation engine and extensions.
3. Add automated unit tests for state transitions and idempotent cleanup.
4. Add Supabase schema, RLS, and retryable synchronization.
5. Add StoreKit entitlement and restore-purchase handling.
6. Build onboarding and routing against the tested state model.
7. Run the full physical-device matrix before TestFlight claims or App Store copy are finalized.
