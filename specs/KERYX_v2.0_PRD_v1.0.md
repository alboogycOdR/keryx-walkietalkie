# KERYX v2.0 — Product Requirements (Contacts & Groups)

> **Version:** 1.0 | **Date:** 2026-09-11 | **Status:** Approved model (`KERYX_v2_Product_Model_v0.2.md`), requirements for build
> **Companions:** `KERYX_v2.0_Design_v1.0.md`, `KERYX_v2.0_Technical_v1.0.md`, `KERYX_v2.0_Verification_v1.0.md`, `docs/adr/ADR-003-v2-people-first.md`
> **Requirement IDs:** `V2-FR-nnn` (functional), `V2-NFR-nnn` (quality). Every acceptance criterion in PLAN.md must cite one.

## 0. Authority

ADR-003 records that v2 supersedes the numbered-channel model of `KERYX_Product_Technical_Spec_v1.1.md` and the channel-first information architecture of the R1 pack. Everything the ADR lists as kept (floor engine, voice path, audio-session fix, R2 Talk surface, privacy commitments) remains authoritative. Where this document is silent, the Product Model v0.2 decides.

## 1. Release boundary

**v2.0 ships:** KERYX ID with a recovery phrase, contact requests by QR and link, groups with keys and member lists, presence, 1:1 and group live talk, the Talk-first UI with Contacts and Groups tabs, and the directory service on the VPS.

**v2.0 does not ship:** store-and-forward voice messages, push notifications, captions or any AI feature, phone-number discovery, teams/admin. Each has a placeholder in the design so v2.1+ slot in without a redesign. A lone press in v2.0 records nothing; it shows "Nobody is listening" and the ring returns to ready (the v2.1 behaviour replaces this with "Sent as a message").

**Removed in v2.0:** channels 01–99, privacy codes, the channel picker and recall list, the Stations screen, the LOCAL/LINKED/AUTO mode setting and its labels, the Event QR numbered-channel path.

## 2. Users and journeys

**Personas (unchanged in spirit from v1):** the family (parents, teenagers, grandparents on one group), the site crew (5–25 people, some on Wi‑Fi together, some remote), the event team (temporary group that dissolves after the weekend).

### 2.1 First launch
Pick a callsign → the app creates the ID → shows the 12-word recovery phrase with a "I've written it down" gate → lands on Talk with "Add your first contact".

### 2.2 Meet and add
Alister taps *Add contact* → *Show my code*. Ben scans it. Ben's phone sends a request; Alister's shows *Add BEN·4R2M?* → Accept. Both now see each other in Contacts with presence. Under a minute, no typing beyond the callsign.

### 2.3 Add remotely
Alister shares his link over WhatsApp. Ben taps it, KERYX opens, the request goes out, Alister accepts.

### 2.4 Make a group
Alister creates *Site crew*, shares the group QR at the morning briefing. Twelve people scan. The member list fills in as each joins. Anyone can press and talk to everyone; one speaker at a time.

### 2.5 Talk
Open a contact or group → the ring shows whether anyone can hear → hold → talk → release. Same Wi‑Fi peers hear it directly; remote members through the relay. The speaker's callsign shows on every listener's screen.

### 2.6 Status
Ben sets *Do Not Disturb* before a meeting. Alister's Contacts list shows Ben's grey dot; pressing on Ben's tile says "Ben is on Do Not Disturb". An *Alert* still reaches Ben once.

### 2.7 Leave, remove, block
Leaving a group is one tap. An admin removes a member; the app rotates the key and re-invites the rest silently. Blocking a contact removes the link and refuses future requests.

### 2.8 Recover
New phone → *Restore* → type the 12 words → same ID, contacts and groups come back from the directory. (Message history does not; it never left the old phone.)

## 3. Functional requirements

### 3.1 Identity
- **V2-FR-001** On first run the app generates an Ed25519 key pair. The KERYX ID is the callsign plus a 4-character short code derived from the public key. The callsign is 2–12 letters, digits or hyphens. Callsigns are not unique (D9).
- **V2-FR-002** The app shows a 12-word BIP-39 recovery phrase once at first run, requires an explicit "I've written it down" confirmation, and can show it again from Settings behind the device lock. No copy of the private key ever leaves the phone (D10).
- **V2-FR-003** Restore from the phrase reproduces the same key pair and ID, and re-fetches contacts and groups from the directory.
- **V2-FR-004** The ID is presented as a QR code and as a link `https://keryx.app/c/<callsign>-<code>`. Both encode the public key, so a scan needs no server round-trip to verify identity.

### 3.2 Contacts
- **V2-FR-010** A contact request is created by scanning an ID QR, opening an ID link, or pasting an ID. The request is signed by the sender and delivered through the directory.
- **V2-FR-011** The recipient sees the sender's callsign and code and chooses Accept, Decline or Block. Only Accept creates a link, and it creates it for both sides.
- **V2-FR-012** Requests expire after 7 days. A blocked ID cannot send another request. There is a per-sender limit of 20 outstanding requests.
- **V2-FR-013** Either contact may remove the link at any time; removal is not announced to the other side.
- **V2-FR-014** The Contacts tab lists contacts alphabetically with presence, and lists pending incoming requests above them.

### 3.3 Groups
- **V2-FR-020** Any user can create a group with a name (1–40 characters). The app generates a 256-bit group secret; the creator is the first admin.
- **V2-FR-021** An invite is a QR or link carrying the group ID and the secret, optionally with an expiry (4 h, 24 h, 7 d, none). Joining registers membership with the directory; the member list updates for all members within 5 seconds while online.
- **V2-FR-022** Group size is capped at 25 members (D7). A 26th join is refused with a clear message.
- **V2-FR-023** Admins can name other admins, remove members, rename the group, and rotate the key. Removing a member rotates the key and redistributes it to remaining members automatically.
- **V2-FR-024** Any member can leave. When the last admin leaves, the oldest remaining member becomes admin.
- **V2-FR-025** The Groups tab lists groups with member count and how many are currently online.

### 3.4 Presence
- **V2-FR-030** Statuses: Available, Busy, Do Not Disturb, Offline. The user sets Available/Busy/DND from the Talk screen's status control; Offline is automatic after 5 minutes without a heartbeat and can be chosen manually ("appear offline").
- **V2-FR-031** Derived states shown alongside the status: Talking (holds a floor right now) and Nearby (reachable on the same Wi‑Fi).
- **V2-FR-032** Presence is visible only to contacts and fellow group members.
- **V2-FR-033** DND suppresses incoming live audio and notifications; Available and Busy do not change audio behaviour. An Alert breaks through DND once per sender per 10 minutes.

### 3.5 Talk
- **V2-FR-040** Talk targets are a contact (1:1) or a group. There is no channel number anywhere in the UI.
- **V2-FR-041** The PTT ring shows, before pressing, whether anyone can hear: accent when at least one target member is online and not in DND; neutral with the reason ("Nobody is listening", "Ben is on Do Not Disturb") otherwise.
- **V2-FR-042** Floor rules are unchanged from v1: one speaker at a time, TOT cut-off, emergency pre-emption, latch with explicit release.
- **V2-FR-043** Transport is chosen automatically per listener: direct WebRTC when the listener is discovered on the same LAN, otherwise the relay. The talk header shows a small "direct" or "relay" mark; nothing is configurable.
- **V2-FR-044** A press when nobody can hear is refused locally within 100 ms with the reason; the ring returns to ready within 1.5 s (v2.1 turns this into a voice message).
- **V2-FR-045** Emergency pre-empts the floor in every group the user shares and sets a pinned emergency marker on every contact's Talk screen until cleared.

### 3.6 Alerts
- **V2-FR-050** From a contact tile or the group member list, *Alert* sends a one-shot high-priority ping that plays a sound and vibrates even under Busy and DND. Rate-limited to one per sender per target per 10 minutes.

### 3.7 Settings
- **V2-FR-060** Settings retain the v1 audio, appearance and about sections. The connectivity section is replaced by: relay server address, "prefer direct on Wi‑Fi" (on by default), and the identity section: callsign edit, show recovery phrase, restore.
- **V2-FR-061** Message retention (default 7 days) appears in Settings from v2.0 so the preference exists before v2.1 uses it (D6).

## 4. Quality requirements

- **V2-NFR-001** Two strangers with the app installed can meet, exchange IDs, and hear each other within 60 seconds, measured on the real-device matrix.
- **V2-NFR-002** Directory API p95 latency under 300 ms for contact and presence calls from South Africa to the VPS.
- **V2-NFR-003** Presence changes propagate to online contacts within 5 seconds.
- **V2-NFR-004** All directory traffic is TLS; all talk audio is end-to-end encrypted; the server never holds a private key or a plaintext group secret (secrets are stored encrypted to each member's public key).
- **V2-NFR-005** No address-book access, no phone number, no analytics SDK. The Android manifest requests no contacts permission (carried from Verification §8).
- **V2-NFR-006** Cold start to Talk under 2 s on a 2022 mid-range phone; APK under 60 MB per ABI.
- **V2-NFR-007** The server stores under 4 KB per user for identity, contacts and presence, and under 2 KB per group membership. No audio is stored in v2.0.
- **V2-NFR-008** Accessibility carries from R1: 48 dp targets, TalkBack labels on every control, text scale 2.0 without loss of function.

## 5. Product acceptance for v2.0

1. Journeys 2.1–2.8 each pass on two real phones of different makes.
2. A 5-member group talks across two networks (two phones on one Wi‑Fi, three remote) with one speaker at a time and correct callsigns on every screen.
3. DND, Busy and Alert behave as V2-FR-033 and V2-FR-050 on real phones.
4. Restore from the phrase on a wiped phone brings back the same ID, contacts and groups.
5. The removed items in §1 are absent from the UI, and no v1 channel/tuning string remains in `lib/`.
6. Full suite green; analyzer clean; the Verification §7 device matrix rows for v2.0 recorded with evidence.

## 6. DEVDepartment intake

Spec-silent areas resolved here so builders do not guess: short-code derivation (Technical §3.1), invite link format (Technical §5), presence protocol (Technical §6), directory schema (Technical §4). Anything else spec-silent is a `SPEC_AMBIGUITY` block, not an invention.
