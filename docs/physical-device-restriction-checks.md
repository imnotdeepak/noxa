# Physical-device restriction checks

Status: On October 20, 2026, the Safari- and rule-aware-shield build installed and launched on the paired iPhone “iphony 5x”; both extensions have the required App Group entitlement. An earlier physical-device screen-capture UI test passed and showed Noxa's Home screen with six saved distraction selections and an enabled schedule. A later read-only Blocklist inspection test timed out while enabling iPhone UI automation, before it could observe a shield. App launch and state rendering are verified; Screen Time enforcement, shield text, widget placement, Live Activity presentation, Safari extension permission and filtering, and release behavior remain unverified. iPhone Mirroring is unavailable on this Mac because iCloud is signed out. Simulator results do not prove Screen Time enforcement.

## Setup

- Install the `codex/product-roadmap` build on a physical iPhone with the Family Controls entitlement and an active Noxa subscription.
- Grant Screen Time access. Choose one test app, one category, and one website domain. Confirm other named stores or old test schedules are cleared before each scenario.
- Record actual device time, app version, selection, expected rule owners, observed shield, and any notification delivery. Check both while Noxa is open and after force-quitting it.

## Required transitions

| Scenario | Expected result |
| --- | --- |
| Manual shield plus normal focus on the same target; end focus early | Manual block remains; focus-only targets release. |
| Daily limit plus focus on the same target; focus reaches planned end | Daily-limit block remains until its own reset. |
| Schedule plus focus overlap; allowed window begins during focus | Focus block remains until focus ends. |
| Upgrade with an active daily allowed schedule | The new named “Allowed hours, every day” rule keeps the same block and release times; old segment stores clear after the new store is applied. |
| Two schedules select the same app, and one allowed window opens | The other active blocked-hours or outside-allowed-hours rule keeps the app blocked. |
| Blocked Monday 22:00–Tuesday 07:00, Tuesday unselected | The block starts Monday night, continues after midnight, and releases Tuesday at 07:00. |
| Allowed Monday 22:00–Tuesday 07:00, Tuesday unselected | Monday outside the window is blocked; the overnight allowed window opens; Tuesday after 07:00 has no schedule block. |
| Disable a schedule during an active focus session | Its store clears immediately, while the focus-owned store keeps the selected target blocked. |
| Change device timezone or cross a daylight-saving transition | The next local-time boundary is shown correctly and shields follow the currently selected local weekdays and times. |
| Upgrade with an active pre-migration focus session | Focus shield moves to `noxa.focus`, remains through the planned end, then releases without leaving a legacy shield. |
| Strict enabled, then start a session longer than four hours | Review shows a four-hour maximum; active session has no early-end control and ends at its planned time. |
| Toggle Strict during an already-running normal session | That session keeps its normal early-end flow; the next session uses the new setting. |
| Toggle Strict off during an already-running strict session | That session remains strict; later sessions are normal. |
| Start a 15/5 Pomodoro cycle, then close Noxa | Four work intervals block the selected targets, three intervening breaks release only the Pomodoro-owned block, and the fourth work interval ends the cycle. |
| Open Noxa during a break and stop the cycle | Future work monitors and pending cycle notifications are cancelled; independent rules remain active. |
| Leave the phone locked across a break and next work start, then unlock | The next work shield is applied when the system delivers its callback; Noxa recovers the correct round and end time on launch. |
| Receive a delayed work-end callback during the next work interval | The current interval remains blocked. |
| Deny notification permission | Pomodoro scheduling and enforcement still work; no notification-dependent transition fails. |
| Allow notifications | Each break has halfway and one-minute-left notices; round four asks whether to start another cycle. |
| Revoke Screen Time authorization mid-cycle | The cycle is stopped and Noxa reports the interruption without leaving an app-controlled stale shield. |
| Complete the first focus session after force-quitting Noxa, then reopen it | The one-time recurring-schedule offer appears with the completed session's targets after subscription and authorization recover. The editor lets the user choose name, days, hours, and mode before saving. |
| End the first focus session early | No recurring-schedule offer appears. A later first completed session uses its own targets. |
| Tap an idle Home or Lock Screen widget | Noxa opens a focus review with one hour selected; the user can change duration and sees the Strict warning and planned end before confirming. No block starts on the widget tap alone. |
| Start and end a focus session with widgets placed | Home and Lock Screen widgets show the correct countdown, then return to Start. The Live Activity appears when permitted and clears at the end or on recovery. |
| Tap the widget with no subscription, targets, or Screen Time access | Noxa shows the correct paywall or setup path and does not claim a session started. |
| Enable the Instagram Safari extension and allow instagram.com after subscribing | With the Noxa Safari toggle on, direct Reels and Explore routes show the return-to-feed screen. The feed, messages, search, and profiles stay usable. Confirm embedded Reels separately; the prototype may miss them. |
| Turn the Noxa Safari toggle off, sign out, or reach subscription expiry | The extension stops hiding Instagram content even if Safari still lists it as enabled. Reload a page and check again after a minute on an already-open page. |
| Revoke Safari's Instagram website permission | The app shows only the extension enabled state, and does not claim that filtering is working; Instagram remains unchanged until access is restored. |
| Start focus and watch its status with Noxa open, then with Noxa relaunched | The app first shows that blocks were requested. A matching monitor callback changes the status to “Screen Time monitor applied your block settings.” Verify the selected app and site actually show a shield separately; the status alone does not prove that. A stale receipt from an earlier session never changes the new session's status. |
| Open a shielded app or site with focus, schedule, manual, or daily-limit rules active | The shield names matching rules, shows the focus or schedule end when known, and never implies that one rule ending releases a target held by another rule. Unknown rule state uses the generic message. |

## Evidence to retain

- Screen recording or timestamped screenshots of each shield and release transition.
- Xcode device logs from the app and `NoxaMonitor` for any missed or delayed callback.
- The test result and app build identifier, with a short note for any callback that occurred only after device use.
