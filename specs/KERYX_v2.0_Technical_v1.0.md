# KERYX v2.0 — Technical & Migration Specification

> **Version:** 1.0 | **Date:** 2026-09-11 | **Companions:** PRD, Design, Verification v1.0; ADR-003
> **Verified against the repository at `master` b863181 (2026-09-11).**

## 0. Source of truth and constraints

- Requirement IDs come from the PRD. Owner decisions D1–D11 from the Product Model v0.2 bind this document.
- The floor engine (`lib/core/floor/**`), the reducer (`lib/core/state/**`), the WebRTC mesh (`lib/services/mesh/**`), the LiveKit path (`lib/services/linked/**`), and the audio pipeline (`lib/core/audio/**`) are **kept**. Changes to them are limited to what §7 lists.
- The relay stack (`relay/`: LiveKit 1.9.11, Redis, coturn, Caddy) is kept unchanged. The token service (`token-svc/`) is **grown** into the directory service, not replaced.

## 1. Verified current architecture (what v2 builds on)

| Area | Today | v2 use |
|---|---|---|
| Identity | `install_uuid` → `derivePeerId` = base32(sha256(uuid))[:10] (`lib/core/identity/peer_id.dart`); callsign stored via `IdentityRepository`; no key pair | Replaced by an Ed25519 key pair; the peer ID becomes base32(sha256(publicKey))[:10] so every existing consumer of `PeerId` keeps working |
| Rooms | `deriveNumbered(region, channel, code)` and `deriveKeyed(passphrase)` → 16-char base32 room IDs via HMAC-SHA256 with `keryxContext`; scrypt-stretched passphrases (`lib/core/rooms/`) | `deriveNumbered` is deleted; `deriveKeyed` is reused: a group's room ID is `deriveKeyed(groupSecret)`; a 1:1 room ID is `deriveKeyed(sorted(pubA, pubB))` |
| LAN discovery | NSD `_keryx._tcp` with an 8-char channel-hash prefix in the service name (`lib/services/discovery/`) | Kept; the prefix becomes the first 8 chars of the room ID the app is currently listening on. A phone advertises one service per active room (max 3: current target + 2 most recent) |
| Relay join | `POST /token {room_id, callsign, event_token?}` → LiveKit JWT (`token-svc/app/main.py`) | Kept, with authentication: the request is signed by the caller's key and the directory checks membership before minting |
| Event QR | `keryx://join?...` numbered or keyed links (`lib/features/event_qr/event_link.dart`) | Numbered path deleted; the keyed path becomes the group invite |
| Floor | `FloorEngine`, `Arbiter`, `RadioStateBridge`, TOT, emergency | Kept as-is; roster comes from the directory's member list instead of channel discovery |
| Presentation | `RadioViewState.project`, `ConnectionCondition`, Talk shell (TASK-077) | `ConnectionCondition` loses configured/effective mode; gains `transport: direct|relay|none`; `RadioViewState` gains `target` and `audience` (§6.3) |

### 1.1 Existing limitations that v2 must respect
- `MeshController` supports one mesh at a time. Switching target tears down and rebuilds, as `retune` does today (`RadioSessionController.retune`). Target switch latency must stay under 1 s on LAN.
- The floor engine's join-guard denies a solo press until a roster is known (TASK-082 dossier). In v2 the roster is known immediately from the directory, so `updateRoster` is called at session start with the full member list; a solo station is then denied with the honest "Nobody is listening" reason at the presentation layer *before* the engine is asked.
- LiveKit participant audio levels are not exposed (TASK-079); RX metering stays LOCAL-only.

## 2. Target architecture

```text
Phone                                             VPS
──────────────────────────────────────            ───────────────────────────────
Identity (keys, phrase)  ──signed requests──►     Directory API (FastAPI + Postgres)
Contacts / Groups store  ◄──REST + WS push──      ├─ /v2/identity, /contacts, /groups
Presence client          ◄──WS presence───►       ├─ /v2/presence (WebSocket)
RadioHost                                         ├─ /token (existing, now authenticated)
 ├─ FloorEngine                                   └─ Redis (presence fan-out, already present)
 ├─ MeshController ──direct WebRTC──► other phones on the LAN
 └─ LinkedController ──LiveKit──► relay ◄── remote phones
```

## 3. Identity

### 3.1 Keys and ID
- Ed25519 via `package:cryptography` (add dependency; pure Dart, no native build). Private key in `flutter_secure_storage` (already a dependency).
- `peerId = base32(sha256(publicKey))[:10]` (reuses `derivePeerId`'s shape; the only change is the input).
- `shortCode = base32(sha256(publicKey))[10:14]` shown with a middle dot: `BEN·4R2M`. Alphabet excludes 0/1/8 lookalikes by construction (RFC 4648).
- Display ID string: `<CALLSIGN>·<CODE>`; link: `https://keryx.app/c/<callsign>-<code>?k=<base64url(publicKey)>`; QR payload: `keryx://id?v=1&c=<callsign>&k=<base64url(publicKey)>`. Both carry the key, so verification is local (V2-FR-004).

### 3.2 Recovery phrase
- 128-bit entropy → 12 BIP-39 English words (`package:bip39` or an inlined word list; either is acceptable, pin the list in the repo). Seed → Ed25519 via HKDF-SHA256 with info `keryx-id-v1`.
- Restore: words → seed → same key → `GET /v2/identity/me` (signed) returns contacts and groups; group secrets are re-fetched from the member-encrypted store (§5.3).

### 3.3 Signing
- Every mutating directory call carries `X-Keryx-Sig: base64(ed25519(sha256(method|path|body|timestamp)))` and `X-Keryx-Key`, `X-Keryx-Ts`. The server rejects timestamps more than 120 s old and replays within that window (Redis nonce set).

## 4. Directory service

Grown from `token-svc`. Same container, same Caddy vhost, path prefix `/v2/`. Postgres 16 added to `relay/docker-compose.yml` with a named volume; migrations via Alembic.

### 4.1 Schema (minimal by D2/V2-NFR-007)
```
identities(pubkey PK bytea, callsign text, created_at, last_seen_at, status smallint)
contact_requests(from_pk, to_pk, sig, created_at, expires_at, state)   PK(from_pk,to_pk)
contacts(a_pk, b_pk, created_at)                                       PK(a_pk,b_pk), a<b
blocks(blocker_pk, blocked_pk, created_at)
groups(id PK uuid, name text, created_by, created_at, key_version int)
group_members(group_id, pk, role smallint, joined_at, secret_enc bytea)  PK(group_id,pk)
invites(group_id, token_hash, expires_at, created_by)
```
No audio, no message tables in v2.0. `secret_enc` is the group secret sealed to the member's public key (X25519 from the Ed25519 key, libsodium sealed box); the server cannot read it.

### 4.2 Endpoints
| Method | Path | Purpose | Auth |
|---|---|---|---|
| POST | `/v2/identity` | Register pubkey + callsign | Signed |
| GET | `/v2/identity/me` | Contacts, groups, pending requests | Signed |
| PATCH | `/v2/identity/callsign` | Rename | Signed |
| POST | `/v2/contacts/requests` | Send request `{to_pk}` | Signed |
| POST | `/v2/contacts/requests/{from_pk}:accept|decline|block` | Resolve | Signed |
| DELETE | `/v2/contacts/{pk}` | Remove | Signed |
| POST | `/v2/groups` | Create `{name, my_secret_enc}` | Signed |
| POST | `/v2/groups/{id}/invites` | Mint invite `{expires_in}` → `{token}` | Signed, member |
| POST | `/v2/groups/join` | `{token, my_secret_enc}` | Signed |
| GET | `/v2/groups/{id}` | Members + roles + presence | Signed, member |
| POST | `/v2/groups/{id}/rotate` | `{secrets_enc: {pk: bytes}}` for all remaining members | Signed, admin |
| DELETE | `/v2/groups/{id}/members/{pk}` | Remove (server requires a rotate in the same call) | Signed, admin |
| DELETE | `/v2/groups/{id}/members/me` | Leave | Signed |
| POST | `/v2/alerts` | `{to_pk}` → push through presence WS | Signed, contact; rate-limited |
| WS | `/v2/presence` | Heartbeat every 60 s; server fans out status changes to contacts/co-members | Signed handshake |
| POST | `/token` | Existing; now checks the signed caller is a member of `room_id` | Signed |

Errors: JSON `{error: code}` only; codes are enumerated in the Verification plan. Rate limits: existing `IpRateLimiter` plus per-key limits (requests 20 outstanding, alerts 1/10 min/target).

### 4.3 Presence protocol
Client opens the WS after boot with a signed hello; sends `{status}` on change and a heartbeat every 60 s. Server marks Offline after 5 minutes without a heartbeat. Fan-out via Redis pub/sub to every online contact and co-member. Message: `{pk, status, talking?, since}`. "Nearby" is computed on the phone from LAN discovery, never by the server.

## 5. Groups and keys

### 5.1 Secret and room
`groupSecret` is 32 random bytes made by the creator. `roomId = deriveKeyed(base64(groupSecret))` (existing function). The relay room and the LAN service prefix both derive from it, so a phone with the secret can reach the group on either transport with no server help beyond the JWT.

### 5.2 Invite
`keryx://join?v=2&g=<groupId>&t=<inviteToken>&s=<base64url(groupSecret)>` and the `https://keryx.app/j/...` equivalent. The token proves the invite was minted by a member and carries the expiry; the secret rides in the link so the server never sees it. Anyone who has the link has the secret: that is the same trust model as a WhatsApp invite link, and rotation is the remedy.

### 5.3 Rotation
Admin generates a new secret, seals it to each remaining member's public key, and posts all sealed copies in one `rotate` call; the server bumps `key_version`. Members receive a presence-WS notice, fetch their sealed copy, and switch rooms on their next talk. A removed member's copy is not written, so they cannot derive the new room.

### 5.4 1:1 rooms
`roomId = deriveKeyed(base64(x25519(myPriv, theirPub)))`, the shared secret from the two keys. No server state.

### 5.5 E2E audio
Direct WebRTC is already DTLS-SRTP. For the relay, LiveKit's end-to-end encryption (`E2EEOptions` with a per-room `BaseKeyProvider`) is enabled with a key derived from the room secret via HKDF. The relay then forwards ciphertext (V2-NFR-004).

## 6. Client changes

### 6.1 New modules (all `lib/**`)
- `lib/core/identity/keys.dart`, `recovery_phrase.dart`; `peer_id.dart` re-pointed at the public key.
- `lib/services/directory/` — REST client, signing, presence WS client, models.
- `lib/core/contacts/` — contacts store (local SQLite via `sqflite`, or `shared_preferences` JSON if under 500 entries; choose SQLite), request state machine.
- `lib/core/groups/` — group store, secret sealing, rotation handling.
- `lib/features/contacts/`, `lib/features/groups/`, `lib/features/my_code/`, `lib/features/onboarding/` (callsign + phrase), `lib/features/restore/`.
- `lib/features/talk/` — header card becomes `TalkTargetCard`; audience-aware ready state.

### 6.2 Removed modules
`lib/features/channels/**`, `lib/features/channel_selector/**`, `lib/features/stations/**`, numbered paths in `lib/features/event_qr*/**`, `lib/core/rooms/derivation.dart::deriveNumbered`, `lib/services/discovery/channel_hash_prefix.dart` (replaced by a room-prefix helper), the mode setting in `lib/core/settings/`. Their tests go with them; behavioural tests that still apply (retune serialisation, QR decoding) are migrated, not deleted (Verification §0 rule carried).

### 6.3 Presentation
- `RadioViewState` adds `target: TalkTarget?` (contact or group with name, presence summary) and `audience: AudienceState { canHear: int, reason: String? }`. `ConnectionCondition` becomes `{transport: none|direct|relay, degraded}`.
- Ready ring rule (V2-FR-041): `audience.canHear > 0 && !degraded` → accent; else neutral with `audience.reason` as the status line.
- Lone press: the Talk screen refuses locally (V2-FR-044) and never calls `press()`; the TASK-082 flash timer is reused.

### 6.4 Host and session
- `KeryxRadioHost.start` now: load identity → open directory session → fetch me → open presence WS → pick current target → start `RadioSessionController` for that room.
- `RadioSessionController` gains `switchTarget(roomId, members)`; it calls the existing teardown/rebuild path and `FloorEngine.updateRoster(members)` immediately (fixes the solo join-guard, §1.1).
- Transport selection per listener: direct if the listener's peer ID is currently discovered on the LAN, else relay. Both may be active in one session (LAN mesh + relay room) — this already exists as the AUTO bridge in `_resolveEffectiveMode`; it becomes always-on.

## 7. Changes inside kept modules (explicit, nothing else)
- `lib/core/identity/peer_id.dart`: input becomes the public key.
- `lib/core/rooms/derivation.dart`: delete `deriveNumbered`.
- `lib/core/settings/settings_model.dart`: remove `mode`, `region`, `channel`, `privacyCode`; add `preferDirectOnWifi`, `messageRetention`, `relayBaseUrl` (exists as token URL).
- `lib/core/state/radio_state.dart`: remove `channel`, `privacyCode`, `mode`; add `roomId`, `transport`. `SetMode` becomes `SetTransport`.
- `lib/services/session/radio_session_controller.dart`: `retune` → `switchTarget`; `_resolveEffectiveMode` → always both, with the LAN mesh optional when no LAN peer is discovered.
- `lib/services/linked/token_client.dart`: signed request.
- `lib/core/floor/**`: **no change**.

## 8. Migration from v1 installs
On first launch of v2.0 an existing install has a callsign and an install UUID but no key pair. Generate the key pair, keep the callsign, show the recovery phrase, and discard channel memory. There is nothing else to migrate: v1 had no contacts, groups or messages. The v1 `FaceScreen` and the debug legacy route are deleted in the same wave (TASK-061's scope folds in).

## 9. Server deployment
- `relay/docker-compose.yml`: add `postgres:16-alpine` with a volume and healthcheck; the token-svc container gets `DATABASE_URL`, `REDIS_URL` (already present), and `KERYX_SIGNING_WINDOW_S=120`.
- Backups: nightly `pg_dump` to the VPS disk, 7 copies. The database is small by design (V2-NFR-007).
- The `keryx.app` domain (or whatever the owner registers) serves `/c/` and `/j/` links as an app-link page with the store link as fallback; Android App Links verification file in `relay/` Caddy config.

## 10. Planning dependencies (for ORCH decompose)
1. **Identity core** (keys, phrase, peer ID re-point) — no deps.
2. **Directory service** (schema, identity/contacts/groups endpoints, presence WS, signed `/token`) — no deps; testable with a Dart client stub.
3. **Directory client + stores** — depends on 1, 2's contract (can start against the OpenAPI stub).
4. **Room derivation and E2E** (1:1 and group rooms, LiveKit E2EE, LAN prefix) — depends on 1.
5. **Session/host changes** (`switchTarget`, roster-at-start, transport) — depends on 4.
6. **Onboarding + My code + Restore UI** — depends on 1, 3.
7. **Contacts UI** — depends on 3.
8. **Groups UI** — depends on 3, 4.
9. **Talk changes** (target card, audience ready state, lone-press refusal, Alert banner) — depends on 5, 7, 8.
10. **Shell rewiring** (tabs, ⋮ My code, removals) — depends on 6–9.
11. **Deletions** (channels, selector, stations, numbered QR, legacy face) — after 10.
12. **Regression + device matrix + release build** — last.

## 11. Debt carried in
TASK-079 (e) snapshot throttle; TASK-077 (a) mounted guard; TASK-082 (a) remount timer seed. Fold into the tasks that touch those files.
