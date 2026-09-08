# `lib/features/settings`

TASK-055 — Design §2.6 Settings, built fresh (ADR-001 §6). The
`KeryxSettings` model and `SettingsRepository` are reused unchanged;
`lib/core/settings/**` is not edited. The legacy hatch UI in
`lib/features/settings_panel/**` is left in place for TASK-061.

## Sections

Radio, Audio, Connectivity, Identity, Appearance, About. Every legacy
back-panel control is present (see `settings_inventory.dart` and the
dossier). Successor-only rows: effective route, callsign, theme, audio
routing, version / sanitized diagnostics.

## Session-apply policy

Mirrored from `KeryxRadioHost._sessionAffectingFieldsChanged`:

`mode`, `forceLocalOnly`, `relayUrl`, `tokenServiceUrl`, `totSeconds`,
`busyLockout`, `region`.

1. Presentation-only writes persist immediately and call
   `RadioHost.applySettings` (host no-rebuild). Zero reconstruction.
2. Session-affecting writes show an explanatory confirmation
   ("Reconnects radio" badge + dialog) then persist + `applySettings`.
3. **Defer-until-idle:** if `FloorEngine.isTransmitting` is true (fallback
   `RadioPhase.tx` when the snapshot has no engine), `applySettings` is
   **not** invoked. The confirmed snapshot waits until the engine is
   idle. Teardown never starts during TX — no hot-mic window (PTS §8.5).
4. Proposes are FIFO-serialized so two session-affecting writes cannot
   interleave reconstructions.
5. Settings never calls `joinEvent` or any other WAN path. Force-LOCAL
   therefore cannot initiate WAN from this screen.

Callsign is identity-store only (no host identity-apply API). The on-air
name updates at the next session reconstruction / boot.

Theme is stored additively under `keryx.appearance.v1` so a legacy
settings blob is never rewritten as a reduced object. Night-dimming is
the existing `dimMode` field.

## Honesty

- Configured mode, effective route, and Local only are three separate
  rows. Auto is never presented as dual LAN+WAN.
- About shows version and sanitized status only — no exception text,
  type names, or internal service identifiers.
- Audio routing is device-default; roger / DSP remain radio SFX.
