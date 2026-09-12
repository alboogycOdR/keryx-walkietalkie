# Settings (KRX-004 successor, TASK-030 / TASK-094)

Local-only encrypted prefs. No server-side persistence of anything (TS §8.1).

## Read path is total

`SettingsRepository.load()` never throws. Non-object JSON, malformed JSON,
and empty/absent storage all yield `const KeryxSettings()`. Out-of-range
numeric fields are **clamped on read** (not constructor-asserted), so debug
and release agree. FR-023's 30–120 TOT bound holds on the load path. One
bad field defaults that field and keeps the rest. Unknown v1 keys
(`mode`, `region`, `channelMemory`) are ignored.

## Live provider

`settingsProvider` is an `AsyncNotifier`. It re-emits after `save()` via
the same `SettingsRepository` instance the provider watches.

## Squelch unit (ORCH ruling)

Persisted value stays `int` 0–10. `KeryxSettings.squelchNormalized` returns
`squelchLevel / 10.0` in `0.0..1.0` for `BedMixer.gainsFor`. No storage
migration; consumers must not re-derive the conversion.

## Persisted keys

| Key | Spec | Default |
|---|---|---|
| `dimMode` | DS FR-108 automatic/manual | `auto` |
| `voxSensitivity` | FR-024, persist now | `5` (0–10) |
| `voxHangTimeMs` | FR-024, persist now | `500` |
| `preferDirectOnWifi` | Technical §7 | `true` |
| `messageRetentionDays` | Technical §7 | `7` |

`forceLocalOnly` remains a stored bit; the host enforces it by skipping
the relay chain (Technical §6.4). v1 `mode` / `region` / numbered
`channelMemory` are deleted (Technical §6.2/§7).

`RogerBeepVariant` is unchanged (FR-062 vs §7.1 still unresolved).
