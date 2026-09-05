# TASK-042 — Single hero PTT disc with a live amplitude-ring meter

## Brief

Replace the current compact key-style `PttButton` with the approved design's
large circular PTT disc, ringed by a 64-tick amplitude meter that fills
symmetrically from the top and swaps colour by state (amber idle / red TX /
green RX / orange emergency). This task builds the widget in isolation — no
coupling to `FaceScreen` or the session layer. TASK-043 wires it to real state.

## Spec pointers

- Approved canvas, `Main.dc.html`'s interactive prototype is normative for the
  press/release behaviour and the ring's live-meter feel; `Transmit.dc.html` /
  `Receive.dc.html` / `Emergency.dc.html` are the state references for colour
  and glyph per state.
- `specs/KERYX_UI_Design_Specification_v1.0.md` §4 (key travel: 1dp down, lose
  top highlight, gain inner shadow — the disc keeps this rule) and §2 (colour
  tokens: `tx` `#E23D2E`, `rx` `#7FD1A0`, `lcd` `#F2A93B`, `emergency` `#FF7A18`,
  all via `KeryxTheme`, never literal hex in widget code).
- `lib/features/ptt/ptt_state.dart` — check this before inventing a second
  state enum; the disc's idle/tx/rx/emergency states likely map onto whatever
  is already modelled here.
- `lib/features/ptt/ptt_haptics.dart`, `edge_glow.dart` — existing hook points
  to reuse, not duplicate.

## Intended approach

1. Read `ptt_state.dart`, `ptt_button.dart`, `key_row.dart`, `emg_key.dart`,
   `ptt_haptics.dart`, `edge_glow.dart` first — understand what's reusable
   before writing new widgets.
2. Build the disc as a new widget (naming builder's call — e.g.
   `PttDisc`/`PttHeroButton`) with:
   - a `level` input (0–100) driving the ring, injectable via a
     `ValueListenable<double>`/controller seam, defaulting to a simple
     internal ticker only for standalone preview/tests;
   - a `PttDiscState` enum (or reuse the existing one) for idle/tx/rx/emergency,
     driving ring colour, glyph (mic ↔ speaker), and centre legend
     (PTT/BUSY/CANCEL);
   - the existing pressed-key treatment (1dp down, drop top highlight, inner
     shadow) on press.
3. Keep `key_row.dart` as the row beneath the disc — confirm layout, don't
   make it a dependency of the disc.
4. Keep `emg_key.dart`'s hold-to-arm interaction logic untouched; only retint.
5. Widget-test each state, the level→lit-tick-count relationship, and that
   `key_row`/`emg_key` behaviour is unchanged.

## Work Log

(empty — fill in as work proceeds)
