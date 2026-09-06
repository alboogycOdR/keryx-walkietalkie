# TASK-042 — Hero PTT disc

## Implementation

`PttButton` is now a 320 dp circular hero control with a 236 dp raised face
and 64 radial meter ticks. `PttRingController` is an injectable,
`ValueListenable<double>` seam accepting `0..100`; a bounded internal preview
ticker exists only for standalone rendering when no controller is supplied.

The existing PTT gesture callbacks, `PttHapticFeedback` grant/deny seams, and
`PttEdgeGlow` assembly hook are preserved rather than duplicated. `PttState`
now includes `receiving` and `emergency` for parent-owned RX/emergency visual
states. The disc maps idle/TX/RX/emergency to LCD/TX/RX/emergency theme tokens,
and maps the centre to PTT/PTT/BUSY/CANCEL with mic/mic/speaker/mic glyphs.

The rail labels now match the Phase 2 canvas (MON/SCAN/STN/EMG) while retaining
the pre-existing callback names for compatibility with the frozen face
assembly; TASK-043 owns the final action wiring.

## Emergency hold behaviour

`EmgKey` was not behaviourally changed. Before and after this task, its
pointer-down starts the same 600 ms timer, crossing the threshold invokes
`onEmergencyToggled` once, and pointer-up cancels the timer without a second
callback. Its already-tokenized pinned/armed orange treatment uses the same
`KeryxTheme.emergency` value as the hero disc.
