# Physical-device restriction checks

Status: The latest signed app build, including focus monitor status and widgets, was installed and launched on the paired iPhone “iphony 5x” on October 19, 2026. A launch-only device UI test passed. A UI test that queried the screen failed with “Not authorized for performing UI testing actions,” so no on-device interaction was automated. Screen Time permission, subscription access, target selection, actual shield behavior, widget placement, Live Activity presentation, and release behavior remain unverified. iPhone Mirroring is unavailable on this Mac because iCloud is signed out; device-side setup or another observation path is needed. Simulator results do not prove Screen Time enforcement.

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
| Start focus and watch its status with Noxa open, then with Noxa relaunched | The app first shows that blocks were requested. A matching monitor callback changes the status to “Screen Time monitor applied your block settings.” Verify the selected app and site actually show a shield separately; the status alone does not prove that. A stale receipt from an earlier session never changes the new session's status. |

## Evidence to retain

- Screen recording or timestamped screenshots of each shield and release transition.
- Xcode device logs from the app and `NoxaMonitor` for any missed or delayed callback.
- The test result and app build identifier, with a short note for any callback that occurred only after device use.
