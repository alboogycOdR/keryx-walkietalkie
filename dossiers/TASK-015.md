# TASK-015 — PTT button, secondary key row, EMG side key (KRX-015)

## Brief
The transmit controls in `lib/features/ptt/`: the full-width thumb-native PTT with all visual states (idle/pressed/granted/denied/latched), TX edge-glow, the MON/SCAN/SAY AGAIN/settings key row with Pro-locked dimming, and the orange EMG side key. Presentation + intent events + haptic hooks only — grant/deny decisions arrive as inputs (floor engine is TASK-022's territory).

## Spec pointers
- TS §6.1: PTT "≥ 96 dp tall, bottom third, full-width, thumb-native"; secondary keys "[MON] [SCAN] [SAY AGN] [⚙] … Pro keys shown dimmed/locked when unowned"; "[ EMG ] (side key)".
- FR-020: press → TX request → grant; release → roger → floor released (event surface).
- FR-021: "Latch mode (double-tap to lock TX, tap to release) as a setting."
- FR-022: denied → "denied buzz + short haptic and the TX LED does not light."
- FR-025: "long-press dedicated orange key → pre-emption tone… pins an EMG indicator until the sender clears it."
- FR-026: "red TX LED skeuomorph, screen edge-glow while transmitting, distinct grant/deny/timeout haptic compositions (§6.4)" — grant QUICK_RISE, deny THUD ×2, TOT warning TICK ×3, plus fallback patterns.
- DS §2: "Red appears only while the floor is held by this device. If a screenshot shows red and nobody is transmitting, it is a bug."
- DS §4 key travel: pressed = 1 dp down, top highlight lost, inner shadow. PT `.ptt`/`.keys`/`.emgkey` markup and deny styling.

## Intended approach
1. `ptt_button.dart`: state enum input (idle/requesting/granted/denied/latched), gesture handling (hold, double-tap latch when setting enabled, tap-release), emits `pttPressed/pttReleased/latchToggled`; granted → red gradient + inset press per PT; deny flash 260 ms.
2. `edge_glow.dart`: overlay widget (inner red glow on housing bounds) driven by tx-active flag — exported for TASK-017 to mount at face level.
3. `key_row.dart`: MON (press-and-hold semantics exposed), SCAN, SAY AGAIN, settings; `locked` visual (dimmed + Pro marker) with intent still emitted so caller can play deny.
4. `emg_key.dart`: side-mounted orange key, 600 ms long-press arm (PT), emits `emergencyToggled`.
5. `haptics.dart`: composition map per TS §6.4 with `vibration` fallback patterns; injected interface for tests.
6. Widget tests: every state renders, red only when granted, latch gesture flow, locked keys, long-press EMG threshold.

## Work Log
