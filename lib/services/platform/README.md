# Radio foreground service (KRX-080)

Android-only always-on backbone. Dart pushes power/phase/notification; native
owns the FGS, the persistent radio notification, the partial wake lock, audio
focus, and the OEM-kill heuristic. Host wiring into `FaceScreen` is **out of
this territory**.

## Spec

- FR-103: persistent radio-styled notification (channel, PTT on Android 14+
  where permitted, power-off action).
- TS §8.8: FGS types `mediaPlayback` + `microphone`; partial wake lock during
  RX/TX only; audio focus `transient-may-duck` for RX, abandon on power-off;
  service death without user power-off → event (feeds FR-105 later).
- FR-102 / NFR-06: nobody transmitting → no media, no polling loops. Presence
  keepalives stay in the mesh/linked tasks.

## Platform channel

- Method: `za.co.basileia.keryx/radio_service` — `start` / `stop` /
  `setPhase` / `updateNotification`
- Event: `za.co.basileia.keryx/radio_service_events` — `serviceKilled`,
  `pttAction`, `powerOffAction`, `error`

`start` args: `channelLabel`, optional `subtitle`. Returns
`{pttActionEnabled: bool}` (true only on API 34+).
`setPhase` args: `phase` = `idle` | `rx` | `tx`. No timers.

## Wake lock and audio focus (pinned)

| Phase | `PARTIAL_WAKE_LOCK` | `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` |
|---|---|---|
| idle | released | abandoned |
| rx | held | requested |
| tx | held | **kept if already held** (does not request its own) |
| power-off | released | abandoned |

Idle-end abandon is FR-102 (do not duck other apps in standby). Power-off
abandon is the TS §8.8 named trigger. TX does not request focus of its own
because the spec names RX only.

## Kill heuristic

Prefs `keryx.radio.service`: `powered_on`, `killed_dirty`, last channel label.
`onDestroy` without user `stop` sets `killed_dirty` and emits `serviceKilled`.
Sticky restart and the next Dart `start` / event-channel listen also emit if
the dirty flag is set. FR-105 OEM-whitelist UI is a later task; this only
emits the event.

## Notification

Channel `keryx.radio`, `IMPORTANCE_LOW` (silent — FR-102). Ongoing, colorized
olive (`#6B7052`, DS §2). Title = `channelLabel`. Power-off action on all
APIs. PTT action only when `SDK_INT >= 34`. Tapping the body brings
`MainActivity` to front.

## Permissions (minSdk 26)

| Permission | Why |
|---|---|
| `FOREGROUND_SERVICE` | FGS |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | type `mediaPlayback` (API 34+) |
| `FOREGROUND_SERVICE_MICROPHONE` | type `microphone` (API 34+) |
| `WAKE_LOCK` | partial wake lock |
| `POST_NOTIFICATIONS` | persistent notification (API 33+) |
| `RECORD_AUDIO` | required to actually start a microphone-type FGS |

Runtime grants for `RECORD_AUDIO` and `POST_NOTIFICATIONS` are the host's job
(FR-104). If the mic permission is missing on API 34+, native falls back to
`mediaPlayback` only rather than crashing; the type pair is still declared.

MulticastLock remains in `NsdPlugin` (TASK-019). This service does not
acquire it. BT SCO is KRX-081, out of scope.

## Decisions (spec-silent, pinned here)

- No `Timer.periodic` / `Handler.postDelayed` loop in the service. The plugin
  has a single 5 s start watchdog so a failed `startForeground` cannot hang
  the MethodChannel result.
- `android:stopWithTask="false"` — swiping recents does not power off; the
  notification power-off action does.
- `START_STICKY` while powered on so a recoverable OEM kill can come back.
- Notification PTT is a click (toggle intent to Dart), not a hold — a shade
  button cannot be a mechanical PTT hold.
- `lib/services/services.dart` is out of territory; import
  `package:keryx/services/platform/platform.dart`.
