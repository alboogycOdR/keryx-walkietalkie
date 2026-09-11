# ADR-002: Talk-first, Zello-aligned UI polish (UX R2)

**Status:** ACCEPTED (owner decisions recorded 2026-09-11 in an interactive ORCH session)
**Date:** 2026-09-11
**Author:** ORCH
**Amends:** `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §1 (information architecture), §2.1 (landing), §2.2 (Talk layout and PTT), §3.2 (`action/primary` value) and §4 (Ready/Requesting/Denied ring treatments). Only the clauses named in §3 below are amended.
**Does NOT amend:** anything in §4 below.

## 1. Context

UX R1 (TASK-045 to TASK-058, merged 2026-09-07/08) shipped a channel-first
Material shell. The owner used it on two real phones (TASK-059 run 1,
2026-09-11: bidirectional LOCAL voice confirmed) and judged the UI unpolished:

- the app opens on a Channels list, and Talk is one extra tap away;
- the PTT is a flat filled circle that repeats the status sentence inside itself;
- visible "Start transmitting" and "Lock transmission" buttons crowd the PTT;
- navigation uses a generic bottom `NavigationBar`.

The owner supplied Zello Android screenshots as the polish reference: a dark PTT
disc with one thick glowing ring and a faint mic glyph, a compact channel header
card, and a thin icon-only tab strip with an accent underline. Design §0 already
allows inspiration from established PTT apps. It forbids copying Zello assets,
and that rule stands.

## 2. Owner decisions (2026-09-11)

| # | Question | Decision |
|---|---|---|
| O1 | Launch destination | **Talk**, on every launch, including the first. No channel picker is forced on first run; the stored/default channel (01 · 00 on a fresh install) is used. |
| O2 | Tabs | **Talk · Channels · Stations**, icon-only, in a top tab strip. Settings (and Radio controls) move into the app-bar overflow menu. No Contacts/History tab (Design §1/§6 still apply). |
| O3 | Accent colour | **Amber / radio yellow** replaces blue as `action/primary`. |
| O4 | Process | Straight to tasks, no design canvas. The owner reviews the built debug APK at the end of the wave (TASK-078) instead of a mockup. |

## 3. Amendments

**A1. Information architecture (Design §1, §2.1).** "Channels (default)" becomes
"Talk (default)". The shell has a top app bar (KERYX wordmark, connection
indicator, overflow menu containing Radio controls and Settings) and, beneath it,
an icon-only tab strip: Talk (mic), Channels, Stations. Each tab has a semantic
label and a 48 dp target. The active tab shows an accent underline. The bottom
navigation bar is removed. Horizontal swipe between tabs is **disabled** so a
sliding finger on the PTT can never change tabs mid-hold. Settings, Radio
controls, channel selector and Event QR are pushed full-screen routes with a back
affordance. The Android back button on a non-Talk tab returns to Talk; on Talk it
leaves the app as normal. Recent channels stay on the Channels tab. The
"one-tap current-channel shortcut" requirement is met by Talk being the default.

**A2. Talk layout (Design §2.2).** Content order: channel card; overlay
banners (emergency, latched, permission, service fault); flexible space; PTT;
status text below the PTT; compact contextual control row. The channel card
replaces the back/channel header. It shows:

- a leading channel tile;
- `CH NN · CC`;
- the effective route, plus the configured preference only when it differs (Technical §7 still applies);
- a station-count affordance that opens the Stations tab;
- a channel-picker affordance.

A back button appears only when the route can pop.

**A3. PTT presentation (Design §2.2, §4).**
- A dark circular face (`ptt/face` token) with one thick outer ring whose colour carries floor state, and a centred mic glyph. **No sentence inside the disc.**
- Diameter = `clamp(0.78 × available width, 96, 300)` dp. On a 360×640 dp screen at text scale 1.0 the channel card, PTT and status text are all visible without scrolling. At text scale 2.0, scrolling is allowed (Verification §6 unchanged).
- Ring treatments:
  - Ready: accent, solid.
  - Requesting: accent with a rotating sweep segment.
  - TX granted: `state/tx` red.
  - Receiving: `state/rx` green.
  - Latched: red plus a lock badge.
  - Denied/busy: neutral ring flash plus a short horizontal shake.
  - Off/Boot/No link/Tuning: neutral, dimmed.
- Emergency remains an orange banner overlay and never recolours the ring (Design §4's "overlay, not replacement" stands).
- Press feedback: the face scales to ~0.97 and darkens within 120–200 ms, with a light haptic on press-down.
- **Level glow**: an outer glow whose intensity follows `MeasuredMeterLevel` only. With `DecorativeMeterLevel` the ring is static. No phase-driven pulse may be presented as audio (Design §3.4, Technical §5.3, VT-015 unchanged).
- Reduced motion replaces the sweep and shake with static treatments. The label, icon and haptic cues remain.

**A4. Non-drag alternative and latch (Design §2.2, §5).**
- The visible "Start transmitting" button is removed. The non-drag alternative becomes:
  - a semantics custom action on the PTT ("Start transmitting" / "Stop transmitting"), reachable by TalkBack and switch access;
  - `Enter`/`Space` toggling when the PTT has keyboard focus.

  The requirement itself is unchanged; only its placement moves.
- "Lock transmission" becomes a compact, labelled 48 dp lock control that is visible only while TX is granted, and a labelled "Release" control while latched.

**A5. Accent (Design §3.2, §4).**
- `action/primary` becomes an amber/radio-yellow in both themes. Exact hex values are chosen by TASK-072 and must pass the existing contrast verification.
- `state/warning` is no longer used for any PTT ring treatment. It may remain on banners and chips, which always carry an icon and text.
- `state/emergency` must stay visibly distinct from the new accent: at least 20° hue separation, verified in a test.
- Red stays reserved for granted local TX.

**A6. RX level telemetry (Technical §5.3).** Plumbing the existing inbound-rtp
`audioLevel` reader (TASK-065) into `RadioViewState.meterLevel` as
`MeasuredMeterLevel` during receive is authorised. Rules:

- Where no reader or value exists, the level stays unavailable/decorative.
- No level is synthesised from energy, jitter or media-source stats.
- Local TX mic metering is **not** authorised by this ADR.

**A7. On-device review amendments (owner, 2026-09-11 17:36, after installing the R2 review APK).**
- **PTT placement (supersedes the "bottom portion" placement in A2/A3 and Design §2.2):** the PTT ring and its status text are centred vertically in the space below the channel card and banners. They are no longer pinned to the bottom. At text scale 2.0 and in landscape, the scroll fallback stays and the PTT must still be reachable.
- **A refused press is transient:**
  - A denied flash (ring neutral + shake, "Channel busy" cue) lasts about 1.5 s. The ring then returns to its Ready treatment on its own, even when no further radio event arrives. The owner saw it stay grey indefinitely with no second phone connected.
  - The flash is presentation-only. It never overrides a granted TX (Design §4 precedence unchanged).
- **Honest deny copy:** when a press is refused and the roster is known to be empty (LOCAL, zero other stations), the cue reads "No other stations on this channel", not "Channel busy". "Channel busy" is kept for a real contention or lockout deny.

## 4. Not changed

- The floor, audio, session, security and emergency contracts (ADR-001 §5).
- Emergency hold duration and its separate control (in Radio controls).
- Every VT-0xx behaviour: hold/latch idempotency, route-unmount and background release, permission-loss release, no false TX.
- No Contacts/History destination, and no Zello logo, icon or asset copied.
- TASK-059/060 hardware gates and TASK-061/062 retirement and release sequencing.

## 5. Consequences

UX R2 is decomposed as TASK-072 to TASK-080 (plan v15.0). The R1 golden baseline
for Talk, Channels and Stations is intentionally replaced by the tasks that change
those surfaces. Each task regenerates only the golden files for its own surface,
so `master` stays green between merges.
