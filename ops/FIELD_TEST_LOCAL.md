# Field test — LOCAL mode (TASK-059)

Evidence record for the Verification §7 LOCAL rows. Per Verification §9, a row is
marked **PASS** only on direct owner observation; anything not exercised is
**NOT RUN** — never assumed to pass.

## Run 1 — 2026-09-11 (reported by project owner)

### Setup

| Field | Value |
|---|---|
| Device A | Honor CRT-NX1, Android 15 (API 35) — read via adb |
| Device B | Samsung Galaxy A05s — Android version not recorded (owner-reported model) |
| App build | `za.co.basileia.keryx` 1.0.0 (versionCode 2001, arm64-v8a split), installed on A 2026-09-08 20:45 local. Built on the owner's second machine; exact commit unrecorded — install time places it after `4f79a3a` (TASK-058 merge, 20:09) and before `2dd09f1` (TASK-070 merge, 21:56). TASK-070/071 are test/analyzer-only, so behaviour equals `f412dbd`. Contains TASK-044's `setSpeakerphoneOn` (confirmed by string search of the pulled APK's `libapp.so`). |
| Signing | Android Debug cert, SHA-256 `c5aed1ce110a054dbe48958b747a296d28bd9e89b184360f02d6d9cd86dca8b3` |
| Network | Home Wi-Fi **with** internet access (same LAN) |

### Results

| # | Verification §7 row | Result | Evidence / note |
|---|---|---|---|
| 1 | LOCAL discovery on a LAN **without** internet | **PARTIAL** | Discovery succeeded, but on a LAN *with* internet. The no-internet condition was not exercised — re-run on an offline router or hotspot. |
| 2 | Voice A→B and B→A, intended output route, grant/release, no stuck mic | **PASS** | Owner heard clear voice in both directions through the loudspeaker; mic released correctly. This is the first real-device confirmation of TASK-044's audio-session/routing fix — the 2026-08-23 "PTT responds but no voice" failure no longer reproduces. |
| 3 | Busy / contention — single floor owner | NOT RUN | |
| 4 | Channel change on both devices, old channel inactive | NOT RUN | |
| 5 | Network failure → documented reconnect / fallback / no-link | NOT RUN | |
| 6 | Audio routing: speakerphone / wired / Bluetooth, no earpiece-only regression | **PARTIAL** | Speakerphone PASS (row 2). Wired and Bluetooth not exercised. |
| 7 | Background: lock screen, notification action, app switch, return | NOT RUN | |
| 8 | Long-running TOT / battery / foreground service | NOT RUN | |

### Outcome

The critical audio blocker is resolved on real hardware. TASK-059 stays open:
rows 3, 4, 5, 7 and 8 need a run, rows 1 and 6 need their missing conditions and
Device B's Android version still needs recording. No failures were observed, so no successor
task is raised.
