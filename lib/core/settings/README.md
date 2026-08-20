# Settings (KRX-004 successor, TASK-030)

Local-only encrypted prefs. No server-side persistence of anything (TS §8.1).

## Read path is total

`SettingsRepository.load()` never throws. Non-object JSON, malformed JSON,
and empty/absent storage all yield `const KeryxSettings()`. Out-of-range
numeric fields are **clamped on read** (not constructor-asserted), so debug
and release agree. FR-023's 30–120 TOT bound and FR-009's last-6 memory cap
hold on the load path. One bad field defaults that field and keeps the rest.

## Live provider

`settingsProvider` is an `AsyncNotifier`. It re-emits after `save()` and
`rememberChannel()` — either via `settingsProvider.notifier` or via the
same `SettingsRepository` instance the provider watches. A one-shot
`FutureProvider` is not sufficient for TASK-018.

## Squelch unit (ORCH ruling)

Persisted value stays `int` 0–10. `KeryxSettings.squelchNormalized` returns
`squelchLevel / 10.0` in `0.0..1.0` for `BedMixer.gainsFor`. No storage
migration; consumers must not re-derive the conversion.

## New persisted keys (TASK-008 finding 6)

| Key | Spec | Default |
|---|---|---|
| `dimMode` | DS FR-108 auto/manual | `auto` |
| `mode` | FR-040 LOCAL/AUTO/LINKED | `auto` (`RadioMode.auto`) |
| `voxSensitivity` | FR-024, persist now | `5` (0–10) |
| `voxHangTimeMs` | FR-024, persist now | `500` |

`forceLocalOnly` remains a stored bit only — enforcing it onto
`RadioMode.local` is host-wiring, out of this territory.

`RogerBeepVariant` is unchanged (FR-062 vs §7.1 still unresolved).
