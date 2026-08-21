# KERYX — UI & Visual Design Specification

**Companion to:** KERYX Product & Technical Specification v1.1
**Version:** 1.0 — *Design direction locked, tokens ratified*
**Owner:** Basileia Technologies
**Applies to:** Epic E2 (The Face), E3 (Sound), FR-101 (faceplates), FR-106 (accessibility)

---

## 0. Answering the question: how much design belongs in the spec?

**No — the product spec should not carry the full visual design, and v1.1 is correct to stop where it does.** But the gap it leaves must be closed by a different kind of artefact, not by leaving it to the build.

The split that works:

| Lives in the **product spec** (v1.1) | Lives in **this design spec** | Lives in the **prototype** |
|---|---|---|
| *What* the face must contain (FR-###), interaction contracts (knob detents, key-up budget), accessibility floor, principles P1/P4 | *Why it looks like this*: tokens, type, materials, spacing system, motion curves, states, copy voice | *How it feels*: the actual physics, timing, and sound in the hand |

The reason is simple: **a walkie-talkie's UI cannot be validated by reading.** Knob weight, detent tick timing, PTT travel, and how the static swell lands are felt, not specified. Writing more prose about them produces false confidence. So the design process is deliberately **prototype-led**, and this document exists to make sure the prototype is a *designed* thing rather than a developer's placeholder that quietly becomes the product.

### The design workflow (binding for E2)

1. **Tokens first** (§2–§4 below) — locked before any face code. Everything downstream derives from them.
2. **Interactive fidelity prototype** — the deliverable accompanying this document: a real, running face with working knob physics, LCD, PTT states, telltales, grille visualiser, and synthesised sound. It is a *decision instrument*, not a mockup.
3. **The hand test** (gate G1) — the prototype goes on a real phone, in a real hand, with real ambient noise. Three people who have used real radios operate it with no explanation. Pass = they change channel and transmit unaided (the FRS test).
4. **Only then** production Flutter widgets (KRX-010…018), built to match the ratified prototype pixel-for-pixel and millisecond-for-millisecond.
5. **Golden tests** (KRX-018) freeze every face state so the design cannot silently rot during networking work.

**Design gates.** G1 the hand test (above). **G2 the glance test**: channel, mode, and who's talking readable in under 400 ms at arm's length in daylight. **G3 the glove test**: every primary control operable with a thumb, one-handed, wearing a work glove. **G4 the dark test**: usable at night without the display becoming a torch — night dimming is a real radio behaviour, not a theme.

**Who does the design.** With a solo + AI execution model there is no separate designer to hand off to, which is exactly why the tokens must be ratified up front and the golden tests must exist: they are the substitute for a design reviewer. Budget the one external spend where taste cannot be synthesised — **sound (D6)** — and treat commissioned faceplate art (Phase 2) as the second candidate for outside help.

---

## 1. Design Thesis

> **An instrument, not an interface.**

The face is a piece of equipment: a moulded polymer housing photographed under a single hard light, with a small illuminated window and three real controls. It is restrained everywhere except the two places that carry the fantasy — **the knob** and **the display glass**.

Anti-references, explicitly: glossy 2009 skeuomorphism (leather, stitching, drop-shadowed chrome), toy-radio cartoon styling, and flat Material re-skinned with a dark theme. The reference is a *modern* handheld — Kenwood/Motorola industrial design, anodised finishes, matte injection-moulded texture, legends silk-screened onto the shell.

**The one deliberate risk:** the display is a real, ugly-beautiful **transflective LCD** — amber segments on a warm-black glass with visible pixel structure and a faint backlight bloom, including the classic "all segments on" flash at power-up. Screens that imitate cheap hardware are unfashionable. It is the single most convincing detail available, and it costs nothing to render well.

---

## 2. Colour Tokens

Six values. Every colour in the app derives from these; no ad-hoc hexes in widget code.

| Token | Hex | Role |
|---|---|---|
| `--shell-900` | `#15181B` | Deep housing shadow, screen letterbox |
| `--shell-700` | `#22262A` | Primary housing — gunmetal moulded polymer |
| `--shell-500` | `#31363B` | Raised surfaces: key caps, knob body, bezel highlight |
| `--glass` | `#0F1512` | LCD substrate — warm-black with a green cast |
| `--lcd` | `#F2A93B` | Illuminated segments — amber. Unlit segments = `--lcd` at 7% opacity (ghost segments, as on real LCDs) |
| `--legend` | `#CFCBC0` | Bone silk-screen legends and labels |

**Signal colours** (used *only* for state, never decoration):

| Token | Hex | Meaning |
|---|---|---|
| `--tx` | `#E23D2E` | Transmitting. The only red in the product. |
| `--rx` | `#7FD1A0` | Receiving / station active |
| `--emg` | `#FF7A18` | Emergency / priority |
| `--olive` | `#6B7052` | Faceplate accent (Field Black default: hardware trim, knob indicator line) |

Rules: amber appears **only** inside the glass. Red appears **only** while the floor is held by this device. If a screenshot shows red and nobody is transmitting, it is a bug.

---

## 3. Typography

Three roles, deliberately not one family.

| Role | Face | Use |
|---|---|---|
| **Display (glass)** | `Share Tech Mono` — with a real 7-segment face (`DSEG7 Classic`) for the channel numerals only | `CH 07 · 21`, telltales, dot-matrix status line |
| **Legend (housing)** | `Barlow Condensed`, 600, letter-spaced `0.14em`, uppercase | Silk-screened control labels: `MON`, `SCAN`, `PTT`, `CH` |
| **Interface (panels)** | `Inter`, 400/600 | Settings back-panel, first-run copy, store-facing text |

Scale: channel numerals `56/1.0`; secondary glass line `15/1.2`; telltales `11/1.0`; legends `11/1.0` at `0.14em`; panel body `15/1.5`.

The legend face doing double duty as the brand voice is intentional — condensed industrial caps are what equipment labelling actually looks like, and it keeps the store listing consistent with the product.

---

## 4. Material, Layout & Motion

**Material.** Housing = `--shell-700` with a 2–3% monochrome noise overlay (moulded texture) and a single top-left light source: 1 px `rgba(255,255,255,.06)` top inner edge, 1 px `rgba(0,0,0,.5)` bottom inner edge on every raised element. No gradients longer than 20% of an element's height. No blur-heavy glassmorphism anywhere.

**Layout grid.** 8 dp base. Vertical allocation of the face: status strip 6% · glass 18% · grille 26% · control cluster 22% · PTT 22% · safe area 6%. PTT owns the bottom fifth and full width because that is where a thumb lives. Controls never occupy the top third — hands cover the bottom, eyes read the top.

**Motion.** Two curves only: `snap` (140 ms, `cubic-bezier(.2,.9,.3,1)`) for anything mechanical — key presses, detent settle, telltale on/off; and `settle` (320 ms, `cubic-bezier(.16,1,.3,1)`) for the grille and meter, which have mass. Nothing eases in. Nothing bounces except the knob flywheel, which follows real friction decay, not a spring preset. `prefers-reduced-motion` removes the grille tremble and flywheel animation but **keeps every haptic and sound** — the feedback loop survives, only the visuals quiet down (P4).

**Key travel.** Pressed keys move 1 dp down, lose their top highlight, and gain an inner shadow — the same three changes on every control, so the whole face feels like one manufactured object.

---

## 5. Signature Elements

1. **The knob.** Knurled, 96 dp, with an olive indicator line. Drag along an arc; 1 detent = 1 channel; tick sound + `PRIMITIVE_CLICK` + LCD update land in the same frame. Fling gives friction-decayed flywheel, ticks capped at 12/s. This is the element the app is remembered by.
2. **The glass.** Amber segments with ghost segments visible behind them, faint backlight bloom, and the power-up all-segments flash. Night dimming per gate G4.
3. **The grille.** Amplitude-driven tremble of the grille slots during RX — the only ambient animation permitted (§4).

Everything else stays quiet. If a fourth "special" element appears in a build review, cut it.

---

## 6. State Catalogue (frozen by golden tests, KRX-018)

`OFF` · `BOOT` (segment flash + power-on sweep) · `IDLE local` · `IDLE linked` · `TUNING` (static swell, channel blinking) · `TX granted` · `TX denied/busy` · `TX time-out warning` · `RX active (callsign shown)` · `MONITOR open` · `SCAN cycling` · `NO LINK` · `LAN?` · `EMG active` · `REPLAY` · `VOX armed` · `PRV keyed channel` · `Station list flip` · `Pro-locked key`.

Each state defines: glass content, telltales lit, key states, sound, haptic. No state may use a dialog, toast, or snackbar (P1).

---

## 7. Copy Voice

Plain, mechanical, unapologetic — an equipment manual, not an app.

- Labels are nouns or verbs a radio user knows: `MONITOR`, `SCAN`, `CHANNEL`, not `Listen mode` or `Discover`.
- Failures state the condition and the fix, in the interface's voice: **"No stations found on this network. Check everyone is on the same Wi-Fi, or start a hotspot."** Never "Oops!", never an apology.
- Empty channel: **"Channel clear. Hold PTT to talk."** — an invitation, not a mood.
- Permission explainers stay in world: **"A radio needs a microphone."**
- The same word survives the whole flow: the key says `MONITOR`, the telltale says `MON`, the setting says *Monitor*.

---

## 8. Accessibility Floor (non-negotiable, FR-106)

Contrast ≥ 4.5:1 for all legends and glass content on every faceplate (validated per-plate in CI). Touch targets ≥ 48 dp — including each knob detent zone, which is why the steppers exist as the accessible tuning path. Full TalkBack labelling with live-region announcements for channel changes and floor events. A haptic-and-sound-only profile that remains fully operable with the screen off. Faceplates may change materials and hue but **never** layout, contrast ratios, or control positions.

---

## 9. Amendments to the Product Spec

Fold into KERYX v1.2:

- ~~**New FR-108:** Night dimming — display and legend luminance follow an auto/manual dim setting (gate G4).~~ **RATIFIED 2026-08-21** into `KERYX_Product_Technical_Spec_v1.1.md` FR-108 (Should, default auto) — no longer pending fold-in.
- **New FR-109:** Power-up sequence — all-segments flash + power-on sweep on radio power-on (BOOT state).
- **KRX-010 amended:** implement the token system of §2–§4 as a single theme source; no literal colour or duration values elsewhere in the widget tree.
- **KRX-018 amended:** golden tests must cover the full state catalogue in §6, on every shipped faceplate.
- **New KRX-019:** design gates G1–G4 as a documented pre-merge checklist for E2.
- **New KRX-096:** per-faceplate contrast validation in CI.

---

## 10. Clarification Log (ORCH, versioned)

Amendments made to resolve implementation-blocking ambiguity. Each entry names
the follow-up it closes, the conflict, and the ratified value.

- **2026-08-19 — closes follow-up (p). §4 `settle` easing pinned.**
  §4 specified `settle` as "320 ms, ease-out" while the prototype
  (`keryx-face-prototype.html` L16) specifies
  `--settle:320ms cubic-bezier(.16,1,.3,1)`. These are not in conflict: the
  durations agree, and the prototype's bezier *is* an ease-out — it is simply
  the precise instance of the spec's generic term. **RATIFIED: the prototype
  value is normative.** §4 now reads `cubic-bezier(.16,1,.3,1)` verbatim.
  This matches what the frozen theme (TASK-005, `lib/core/theme/**`) already
  implements and disclosed in dartdoc, so no merged code changes. Consumers
  (TASK-016 grille, and the meter) must take the curve from the theme token,
  never re-declare it.

---

*End — KERYX UI & Visual Design Specification v1.0.*
