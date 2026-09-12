# Field test — KERYX v2.0 (TASK-095)

Owner-run evidence record for Verification §6 rows A–I. Per Verification
§9 / R1 convention: a row is **PASS** only on direct owner observation;
anything not exercised is **NOT RUN** — never assumed to pass. Failures
are recorded as **FAIL** with what happened.

Do **not** install or ship an APK from this file. ORCH hands the hashed
release build to the owner.

## Build under test

| Field | Value |
|---|---|
| App | `za.co.basileia.keryx` |
| Artifact | `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (split-per-abi) |
| Commit | _fill after install_ |
| Size / SHA-256 | see `ops/REGRESSION_V2.md` §3 |
| Device A | Honor CRT-NX1, Android 15 (API 35) unless owner substitutes |
| Device B | Samsung Galaxy A05s, Android 14 unless owner substitutes |
| Extra devices (row C) | three more phones, two networks |

Fill the evidence slots as you go. Screenshot / screen-recording paths are
owner-local; paste a filename or "none".

---

## Row A — Meet and add by QR (V2-NFR-001)

**Pass when:** under 60 s from opening the scanner to hearing each other.

### Steps

1. Fresh install the arm64 release APK on Device A and Device B. Accept mic.
2. On each phone complete first-run: pick a callsign, write down the 12-word
   phrase, confirm "I've written it down". Land on Talk ("No one selected yet").
3. On A: Talk → **Add your first contact** → **Show my code** (or ⋮ → My code).
4. On B: Add contact → Scan. Scan A's QR.
5. On A: accept the incoming request (`Add <B-callsign>?`).
6. On either phone open the new contact on Talk, hold PTT, speak; the other
   hears. Release. Swap direction.

### Evidence

| Slot | Value |
|---|---|
| Result | NOT RUN / PASS / FAIL |
| Elapsed time (scanner open → first heard voice) | _ss_ |
| A's callsign · short code | |
| B's callsign · short code | |
| Direct or relay mark on Talk header | |
| Screenshot / clip | |
| Notes | |

---

## Row B — Add by link over WhatsApp (V2-FR-010)

**Pass when:** request arrives and accepts.

### Steps

1. On A: ⋮ → My code → copy / share the `https://keryx.app/c/…` link.
2. Send the link to B over WhatsApp (or any messenger).
3. On B: tap the link; KERYX opens; the request goes out.
4. On A: incoming request for B appears on Contacts; Accept.
5. Both Contacts lists show the other with presence.

### Evidence

| Slot | Value |
|---|---|
| Result | NOT RUN / PASS / FAIL |
| Link opened KERYX (not a browser-only dead end) | |
| Request visible on A within _s | |
| Accept created a symmetric contact | |
| Screenshot / clip | |
| Notes | |

---

## Row C — Group of 5 across two networks (V2-FR-043, PRD §5.2)

**Pass when:** one speaker at a time, correct callsign on every screen,
direct mark on LAN pairs, relay mark on remote.

### Steps

1. Five phones, two networks: two on Wi-Fi X, three on a different network
   (cellular or Wi-Fi Y). All five have the same release APK.
2. One admin creates group **Site crew**, shares the group QR / link.
3. The other four join. Member list reaches 5.
4. Each member in turn holds PTT for ~5 s. Confirm:
   - only one speaker at a time
   - every listener shows that speaker's callsign
   - LAN pair shows **direct**; remote members show **relay**
5. A second member tries to talk while the first is still holding — busy /
   "someone is already transmitting", no double voice.

### Evidence

| Slot | Value |
|---|---|
| Result | NOT RUN / PASS / FAIL |
| Networks | Wi-Fi X: _n_ phones; other: _n_ phones |
| Floor exclusivity (one speaker) | |
| Callsign correct on every listener | |
| Direct mark on LAN pairs | |
| Relay mark on remote members | |
| Screenshot / clip | |
| Notes | |

---

## Row D — Presence, DND, Alert (V2-FR-033, V2-FR-050)

**Pass when:** DND on one phone shows within 5 s on the other; talk is
refused with the reason; Alert breaks through once.

### Steps

1. A and B are contacts (from A or B). Both on Talk targeting each other.
2. On B: set status **Do Not Disturb**.
3. On A: within 5 s B shows DND (Contacts dot + Talk "B is on Do Not Disturb").
4. On A: hold PTT toward B — refused locally; ring returns to ready; no audio
   on B.
5. On A: tap **Alert**. B plays the alert (sound + vibrate) even under DND.
6. On A: tap Alert again within 10 minutes — refused (rate limit).
7. On B: set **Available**. A can talk again.

### Evidence

| Slot | Value |
|---|---|
| Result | NOT RUN / PASS / FAIL |
| DND visible on A within 5 s | |
| Talk refused with DND reason | |
| First Alert broke through | |
| Second Alert within 10 min refused | |
| Screenshot / clip | |
| Notes | |

---

## Row E — Rotation after removal (V2-FR-023)

**Pass when:** removed member cannot hear the group after removal.

### Steps

1. Group of at least 3 (admin A, members B and C), all on the group Talk target.
2. A removes C.
3. Remaining members keep talking; B hears A.
4. C's Talk to that group no longer receives audio. C cannot decrypt / join
   the live room.
5. Optional: A talks after removal; C hears silence.

### Evidence

| Slot | Value |
|---|---|
| Result | NOT RUN / PASS / FAIL |
| C removed from member list on A and B | |
| A↔B still hear each other | |
| C cannot hear post-removal | |
| Screenshot / clip | |
| Notes | |

---

## Row F — Restore (V2-FR-003)

**Pass when:** wiped phone + phrase → same ID, contacts, groups.

### Steps

1. On A, note callsign, short code, contact list, group list. Confirm the
   12-word phrase is written down (Settings → show recovery phrase, device lock).
2. Uninstall KERYX on A (or wipe app data).
3. Reinstall the same APK. Choose **Restore**, type the 12 words.
4. Confirm: same callsign and short code; contacts and groups reappear from
   the directory. Message history is **not** expected (never left the phone).

### Evidence

| Slot | Value |
|---|---|
| Result | NOT RUN / PASS / FAIL |
| Same callsign · short code | |
| Contacts restored | |
| Groups restored | |
| Phrase typos rejected (optional check) | |
| Screenshot / clip | |
| Notes | |

---

## Row G — Background and lock (Verification §6)

**Pass when:** talk continues with the screen locked; app switch and return
keep the target.

### Steps

1. A talking to B (contact or group). Hold PTT, lock A's screen — B still hears.
2. Unlock; target is still selected.
3. Switch to another app for 10 s, return — same target, PTT still works.
4. Optional: use the notification PTT action while the app is backgrounded.

### Evidence

| Slot | Value |
|---|---|
| Result | NOT RUN / PASS / FAIL |
| Locked-screen TX heard on B | |
| Target kept across app switch | |
| Notification PTT (if exercised) | |
| Screenshot / clip | |
| Notes | |

---

## Row H — No internet, same Wi-Fi (V2-FR-043 direct)

**Pass when:** two contacts on a router with no uplink still talk directly.

### Steps

1. A and B already contacts (directory reachability was needed to add).
2. Put both on a Wi-Fi that has **no uplink** (AP isolation off — phones must
   see each other). Disable mobile data.
3. Open the contact on Talk. Hold PTT. Direct mark. Voice both ways.
4. Confirm the app does not sit on "Connecting" forever; if the directory is
   unreachable, already-cached contacts still talk on LAN.

### Evidence

| Slot | Value |
|---|---|
| Result | NOT RUN / PASS / FAIL |
| Router / hotspot used | |
| Uplink confirmed down | |
| Direct mark | |
| Voice A→B and B→A | |
| Screenshot / clip | |
| Notes | |

---

## Row I — Upgrade from v1 (PRD §1 removed items)

**Pass when:** callsign kept, phrase shown, channel memory gone, no crash.

### Steps

1. Device with a v1 / R2 install that has a callsign and (if any) channel
   memory.
2. Install this v2 release over it (do not uninstall first).
3. Launch. App must not crash.
4. Confirm: same callsign; recovery phrase can be shown from Settings;
   no channel number, privacy code, Stations tab, or LOCAL/LINKED/AUTO
   mode control anywhere in the UI.
5. Talk / Contacts / Groups tabs present; ⋮ has My code, Radio controls,
   Settings.

### Evidence

| Slot | Value |
|---|---|
| Result | NOT RUN / PASS / FAIL |
| Crash on first launch after upgrade | |
| Callsign kept | |
| Phrase reachable from Settings | |
| Channel memory / picker absent | |
| Screenshot / clip | |
| Notes | |

---

## Outcome

_Fill after the run. Any FAIL becomes a successor task, not a silent skip._

| Rows PASS | |
| Rows FAIL | |
| Rows NOT RUN | A–I (initial) |
| Owner | |
| Date (local) | |
