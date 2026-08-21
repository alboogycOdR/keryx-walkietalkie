# TASK-026 — Foreground service + radio notification (KRX-080)

## Brief
The always-on backbone: an Android foreground service (`mediaPlayback` + `microphone`) with the persistent radio-styled notification, wake-lock discipline, audio-focus handling, and an OEM-kill detection hook. Second link in the android/** chain — depends on TASK-019 so the two never touch android/ concurrently.

## Spec pointers
- FR-103: "Foreground service with a persistent radio-styled notification (channel, PTT action button on Android 14+ where permitted, power-off action)."
- TS §8.8: "Foreground service (`mediaPlayback` + `microphone` types), partial wake lock during RX/TX only, MulticastLock only while LOCAL discovery active… Audio focus: transient-may-duck for RX; abandon on power-off… OEM killers: detection heuristic (service death without user power-off) triggers FR-105 guidance."
- FR-102: "with nobody transmitting, no media flows (PTT model) — only presence keepalives. Screen-off monitor target ≤ 2%/hr battery."
- NFR-06 standby ≤ 2%/hr (measured later by the battery bench, KRX-086 — design for it now: no polling, no periodic wakeups beyond the 5 s presence heartbeat).

## Intended approach
1. Kotlin `RadioForegroundService`: started/stopped from Dart on power-on/off; `foregroundServiceType="mediaPlayback|microphone"` (manifest + runtime); notification channel with segment-style small icon, channel text, power-off action PendingIntent, PTT action where Android 14+ permits.
2. Wake lock: `PARTIAL_WAKE_LOCK` acquired on RX_ACTIVE/TX enter, released on exit (driven by Dart state events over the channel).
3. Audio focus: `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` requested on RX start, abandoned on power-off.
4. Kill detection: persist a "powered-on" flag; `onDestroy` without user power-off, or start-up seeing the stale flag → emit `serviceKilled` event to Dart (consumer: FR-105 guidance task, later).
5. Dart `lib/services/platform/`: `RadioServiceController` facade (start/stop, state pushes, killed-event stream), mocked-channel tests.
6. Manual on-device checklist (screen-off soak, notification actions) appended to this dossier's work log as evidence alongside unit tests.

## Work Log
- [2026-08-21T04:52:00Z] [GB] Claimed on `task/TASK-026-gb`. Preflight: android/** populated (21 files, TASK-019 predecessor), `lib/services/platform/**` and `test/services/platform/**` NEW, this dossier exists. Will not edit `NsdPlugin.kt`. Implementing Kotlin FGS (`mediaPlayback|microphone`), radio notification (channel + power-off + PTT on API 34+), partial wake lock on RX/TX only, `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` on RX / abandon on power-off, OEM-kill dirty flag, Dart `RadioServiceController` facade with mocked-channel tests. No polling loops. Host wiring into FaceScreen is out of territory.
- [2026-08-21T05:15:00Z] [GB] Implementation complete on `task/TASK-026-gb`. `RadioForegroundService` is `mediaPlayback|microphone`, silent ongoing notification (channel title, Power off always, PTT only `SDK_INT >= 34`), `PARTIAL_WAKE_LOCK` on rx/tx only, `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` on rx / keep through tx if already held / abandon on idle and power-off, OEM-kill dirty flag + `serviceKilled` event. Dart facade `ChannelRadioServiceController` over Method/Event channel. `NsdPlugin.kt` untouched. FaceScreen wiring out of territory.
- [2026-08-21T05:15:00Z] [GB] Tests: `flutter test test/services/platform/` 22/22; `flutter analyze` clean; full `flutter test` 449/449 (prior 427 + 22). Mutation: replacing `PARTIAL_WAKE_LOCK` with `SCREEN_BRIGHT_WAKE_LOCK` turned native-contract 7 → 6 passed / 1 FAILED; restored, 7/7 green. `flutter build apk --debug` succeeded after fixing an Intent.apply `flags` val-reassign compile error (`'val' cannot be reassigned` at buildNotification).
- [2026-08-21T05:15:00Z] [GB] Manual on-device checklist (documented; not executed this session — no device attached). Host must grant `RECORD_AUDIO` + `POST_NOTIFICATIONS` first (FR-104).
  1. Power on via `RadioServiceController.start(channelLabel: 'CH 01')` → persistent notification titled `CH 01`, ongoing, silent, olive colorized. Service types in `adb dumpsys activity services` include `mediaPlayback` and `microphone` (or mediaPlayback-only if mic permission missing).
  2. `updateNotification(channelLabel: 'CH 07')` rewrites the shade title without a second notification.
  3. Android 14+: PTT action is present; tap emits `pttAction` to Dart. Android 13 and below: PTT action absent, Power off still present.
  4. Power-off action removes the notification, stops the service, emits `powerOffAction`, abandons audio focus, releases wake lock. Dart `stop()` does the same without emitting `powerOffAction`.
  5. Screen-off idle: wake lock not held (`adb shell dumpsys power | findstr keryx`). `setPhase(rx)` holds it; `setPhase(idle)` releases it. Other media ducks during RX only.
  6. Force-stop the app from Settings while radio is on → reopen → `serviceKilled` event (dirty flag). User power-off then reopen must NOT emit `serviceKilled`.
  7. Idle with nobody transmitting: no `Handler.postDelayed` loop, no extra CPU wakeups from this service. NFR-06 2%/hr soak is KRX-086, not this task.
