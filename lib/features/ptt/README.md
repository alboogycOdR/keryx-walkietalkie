# Hero PTT controls

`PttButton` is the Phase 2 hero disc: a 320 dp outer meter ring enclosing a
236 dp raised circular face. It remains presentation plus intent only;
callers provide `PttState`, floor callbacks, and an optional live
`ValueListenable<double>` level source.

## Contract

- `PttRingController` accepts a clamped `0..100` level. Inject it (or any
  `ValueListenable<double>`) from live TX/RX audio. A gentle owned preview
  ticker is used only when no source is supplied, so the standalone widget is
  visible in previews and tests.
- `PttState.granted`/`latched`, `receiving`, and `emergency` render TX red,
  RX green, and emergency orange respectively. Idle uses LCD amber. RX swaps
  the mic for a speaker and reads `BUSY`; emergency reads `CANCEL`.
- The disc keeps the existing hold-to-talk/latch callbacks and invokes the
  existing `PttHapticFeedback.grant`/`.denied` seams on the same transitions.
  `PttEdgeGlow` remains the assembly-level TX glow hook.
- `PttKeyRow` visually presents MON/SCAN/STN/EMG below the disc. Its legacy
  callback names are intentionally source-compatible until TASK-043 wires the
  roster and emergency actions at face-assembly level.
- `EmgKey` retains its unchanged 600 ms hold-to-arm interaction and already
  uses `KeryxTheme.emergency` for its pinned/armed orange treatment.

## Press treatment

The TX or actively touched face moves down `KeryxTheme.keyTravel` (1 dp),
loses raised material edges, and gains an inner shadow. All state colours are
read from `KeryxTheme`; no widget-level signal colour literals are used.
