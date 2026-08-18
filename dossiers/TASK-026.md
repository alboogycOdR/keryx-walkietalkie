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
