# TASK-008 — Settings & persistence layer: encrypted prefs, channel memory (KRX-004)

## Brief
Local-only typed settings repository in `lib/core/settings/` backed by encrypted prefs, plus the 6-slot channel memory. Feeds the settings back-panel (TASK-018) and every behaviour flag consumer (TOT, squelch, lockout, DSP intensity, force-LOCAL). Nothing ever persists server-side.

## Spec pointers
- TS §8.1 Persistence row: "Local only: settings + channel memory in encrypted prefs. **No server-side persistence of anything.**"
- FR-009: "Channel memory: last 6 tuned channels accessible via quick-recall (long-press CH▼)."
- FR-023: TOT "max continuous TX 60 s (configurable 30–120 s)". FR-022: busy lockout "Setting: on by default". FR-021 latch mode. FR-024 VOX sensitivity/hang-time (persist keys now, feature later).
- FR-046: "A 'force LOCAL only' privacy toggle that hard-disables all WAN traffic."
- FR-061 squelch level; FR-062 roger variant (off/K/dual/custom); TS §7.2 DSP intensity "Off / Light / Full (default Light)"; FR-008 region; DS FR-108 dim mode (auto/manual).

## Intended approach
1. `settings_model.dart`: immutable `KrxSettings` with spec defaults (TOT 60 s, lockout on, DSP light, mode AUTO default per FR-040, roger classic-K, force-local off).
2. `settings_store.dart`: abstract store; `SecureSettingsStore` (flutter_secure_storage, JSON blob) + `InMemorySettingsStore` fake for tests.
3. `settings_repository.dart`: typed getters/setters, validation (TOT clamp 30–120, code 0–38), Riverpod provider exposing a settings stream.
4. `channel_memory.dart`: most-recent-first unique list capped at 6 (FR-009), persisted alongside.
5. Tests against the in-memory fake: defaults, round-trips, clamping, memory eviction order.

## Work Log
