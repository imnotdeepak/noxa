# Physical-device restriction checks

Status: On October 20, 2026, the current roadmap build installed and launched on the paired iPhone “iphony 5x.” UI automation observed a real Screen Time shield for Dazz Cam that named the active schedule and its 9:00 PM end time; a duplicate rule description was fixed and rechecked. Selecting Instagram Full Block produced Safari's “Website Not Allowed” page at `instagram.com/explore/`, and returning the setting to Off let that URL load again. Opening the widget's `noxa://focus/start` route displayed a one-hour review with selected targets, an end time, and the Strict warning before any session started. These are narrow physical observations; the full transition matrix, actual widget placement, Live Activity, and selective Safari filtering remain unverified. Simulator results do not prove Screen Time enforcement.

October 21: The owner authorized a four-round 15/5 Pomodoro check. Its first automated start attempt did not launch a cycle because iOS asked for the iPhone passcode to enable XCTest UI automation and the runner timed out waiting. The cycle must not be recorded as started or validated from that attempt.

After XCTest automation was enabled, a second attempt started a Strict 15/5 Pomodoro cycle at about 4:16 PM. During work round 1, DoorDash opened and Noxa reported that the Screen Time monitor had not yet applied the block settings. A device-local App Group inspection found the active cycle and active session, but no `noxa.focusSessionRestrictions` snapshot. Dazz Cam still displayed its independent schedule shield without Focus. This is a real failed enforcement interval, so the cycle cannot pass the full acceptance check. The monitor's Pomodoro reconciliation only recognized rounds 2–4 and could clear the first round's focus store and snapshot if a focus-end callback arrived while round 1 was still active. The app and monitor were changed to restore round 1 from the persisted cycle. A signed build installed during the ongoing round, after which Noxa showed a monitor receipt, DoorDash displayed a Focus shield ending at 4:31 PM, and Dazz Cam displayed both Focus and its independent schedule. The intervening app upgrade means this check proves recovery and overlap on this device, not uninterrupted first-round enforcement.

At 4:32 PM and again at 4:34 PM, after the planned 4:31:51 PM work end, DoorDash still displayed the expired Focus shield while Noxa remained closed. The saved first-round session and focus restriction snapshot were still present. Opening Noxa at 4:35 PM reconciled to the break and released DoorDash. At 4:37 PM, after round 2's scheduled start, DoorDash opened normally; there was no round-2 enforcement marker or focus snapshot. Reopening Noxa at 4:39 PM restored round 2 and displayed a monitor receipt. This establishes that background break and next-round transitions failed in the observed cycle. The signed build was installed mid-cycle, so it remains to determine whether app upgrade invalidated scheduled callbacks or whether a fresh cycle also fails.

The app and monitor now use one shared writer for app, category, and website selections. A short iPhone check on this build still displayed the existing Dazz Cam schedule shield with the correct schedule name; it did not test a transition or release. Its “until 9:00 PM” wording was ambiguous late at night, so schedule shield messages now include the release date. A second iPhone check showed “until Oct 21, 2026 at 9:00 PM” on October 20. Repeat focus, schedule boundary, daily-limit, and overlap shield/release checks on this build before treating the refactor as physically validated.

## Observed scheduled-app check

- Three active schedules shared the display name “Allowed hours, every day.” Two selected Dazz Cam and one selected Letterboxd. At the observed time they displayed “Blocking selected targets” and a 9:00 PM change.
- Launching Dazz Cam showed the iOS shield with that schedule name and end time. The revised build showed the reason once and kept the warning that other rules may still apply.
- DoorDash was saved in the general Blocklist but was absent from these schedules, so it launched normally. That is expected for this test and does not establish a schedule enforcement failure.
- The checks only opened existing rules and apps; they did not change the user's saved selections or start a new focus session. Screen captures are retained in the local Xcode test result bundles and excluded from the repository because other captures include personal account details.

## Observed Instagram and start-review checks

- A temporary UI test selected Instagram Full Block, opened `instagram.com/explore/` in Safari, and captured the iOS “Website Not Allowed” page. A cleanup test returned the choice to Off. Safari then loaded Instagram at the same URL. Temporary UI tests were removed after the checks.
- A temporary UI test opened the widget's focus-start URL on the paired iPhone. The review showed one hour selected, the existing targets, the expected end time, and a Strict warning. It was dismissed without starting a session. The actual Home and Lock Screen widget tap and countdown remain to be checked.
- A temporary UI test changed the existing Letterboxd daily limit from 15 to 10 minutes, started daily-limit monitoring, kept Letterboxd foregrounded with interactions for 6.5 minutes, then stopped monitoring and restored 15 minutes. A second test used its original 15-minute limit for 5.5 minutes. The monitor's interval-start callback was observed, but no warning or reached callback. The first build also lacked the daily monitor's `warningTime`, which is now fixed. Letterboxd is selected by an existing schedule, so these tests do not establish that its use counted toward the limit. Both tests left daily limits off and restored the 15-minute choice. An unblocked target is needed for a valid warning check.
- A follow-up temporary UI test used Fantasy, which the observed schedules did not select. It changed the existing limit from 30 to 10 minutes, started daily monitoring, kept Fantasy foregrounded with repeated interactions, then stopped monitoring and restored 30 minutes. The App Group callback trace recorded `eventWillReachThresholdWarning` at 18:09:12 and `eventDidReachThreshold` at 18:14:12, five minutes apart. Both callbacks had Fantasy's event ID. This verifies the monitor callbacks for that target. Visible notification delivery was not observed. The test passed, and daily limits were off after cleanup.

## Observed Strict recovery check

- On October 20 at approximately 23:45 local time, a temporary UI test started a 15-minute Strict focus session from the saved selection. Its active screen had no early-end control, and the test terminated Noxa.
- On relaunch, the session initially ended with “could not be restored.” Recovery had attempted a new interval from the current time to the saved end, leaving less than DeviceActivity's minimum 15 minutes. Noxa now registers the original session interval instead.
- A second iPhone run relaunched Noxa during the active session and confirmed the Strict screen and matching Screen Time monitor receipt. A stronger run deliberately removed the focus monitor at launch and confirmed that Noxa restored the session without offering an early end. The temporary monitor-removal hook and UI tests were removed from the source afterward.
- During that session, Safari showed “Website Not Allowed” for the selected reddit.com domain. Dazz Cam showed a shield naming both Focus and its independent schedule. A first DoorDash launch immediately after another test build install opened normally despite its saved selection; after bringing Noxa to the foreground, DoorDash displayed the Focus shield. The test build installation and short observation gap prevent a firm cause assignment. The period before foreground reconciliation must be investigated with a realistic app upgrade before claiming continuous enforcement across updates.
- The Dynamic Island displayed the active focus countdown while Safari and shielded apps were foregrounded. The Lock Screen presentation and its end-of-session removal have not been observed.
- With Noxa closed at the planned end, a screenshot taken 12 seconds before expiry still showed DoorDash's Focus shield. A later launch opened DoorDash, and Safari loaded reddit.com. Dazz Cam remained shielded, now naming only its independent schedule. This directly verifies release of this session's app and website selections while an overlapping schedule continues. Other target combinations and app-upgrade continuity remain unchecked.

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
| Enable the Instagram Safari extension and allow instagram.com after subscribing | With Distraction-Free selected, direct Reels and Explore routes show the return-to-feed screen. The feed, messages, search, and profiles stay usable. Confirm embedded Reels separately; the prototype may miss them. |
| Turn the Instagram website choice Off, sign out, or reach subscription expiry | The extension stops hiding Instagram content even if Safari still lists it as enabled. Reload a page and check again after a minute on an already-open page. |
| Revoke Safari's Instagram website permission | The app shows no recent Instagram connection and offers Full Block; it does not claim that filtering is working. Instagram remains unchanged until access is restored. |
| Select Instagram Full Block, then Off | Safari shows “Website Not Allowed” for instagram.com while Full Block is selected and loads the page again after Off. **Observed on the paired iPhone.** |
| Start focus and watch its status with Noxa open, then with Noxa relaunched | The app first shows that blocks were requested. A matching monitor callback changes the status to “Screen Time monitor applied your block settings.” Verify the selected app and site actually show a shield separately; the status alone does not prove that. A stale receipt from an earlier session never changes the new session's status. |
| Open a shielded app or site with focus, schedule, manual, or daily-limit rules active | The shield names matching rules, shows the focus or schedule end when known, and never implies that one rule ending releases a target held by another rule. Unknown rule state uses the generic message. |

## Evidence to retain

- Screen recording or timestamped screenshots of each shield and release transition.
- Xcode device logs from the app and `NoxaMonitor` for any missed or delayed callback.
- The test result and app build identifier, with a short note for any callback that occurred only after device use.
