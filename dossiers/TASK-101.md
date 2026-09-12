# TASK-101 — 1:1 relay rooms: send `peer_pk` on `/token`

## Problem

The v2 token service only creates a `DirectRoom` when `POST /token` carries
`peer_pk` (`token-svc/app/main.py:176-180` → `ensure_direct_room`). The
client minted tokens with `room_id` / `callsign` / `event_token` only, so
every contact call over relay was 403 `not_member`. Groups were unaffected
(`Group` + `GroupMember` rows already exist).

## What `TalkTarget.id` holds for a contact

Verified at source, not assumed: `lib/app_shell/contacts_tab_screen.dart`
builds the target as `id: contact.pk` (now via `talkTargetFromContact`).
`ContactRowVm.pk` is the directory's unpadded-base64url Ed25519 public key.
**No extra field was added.** `RadioSessionController.switchTarget` decodes
that id (32 bytes) and passes it to `LinkedController.joinRoomId` →
`TokenClient.requestToken(peerPublicKey:)`, which encodes with the existing
`encodeUnpaddedBase64Url` (`lib/features/my_code/keryx_id_link.dart`).
Groups and the idle session send none.

## Fix

1. `TokenClient.requestToken` — optional `List<int>? peerPublicKey`. When
   non-null, body gains `peer_pk` (unpadded base64url). When null, the JSON
   body is byte-identical to today (`room_id`/`callsign`/`event_token` only).
2. `LinkedController.joinRoomId` threads it through `_join` /
   `_connectAndPublish` / `_reconnectRoom` so a LiveKit JWT re-mint still
   provisions the DirectRoom.
3. `RadioSessionController.switchTarget` passes the decoded contact key for
   `TalkTargetKind.contact` only. Malformed / wrong-length ids send none
   (existing 403 `not_member` path).
4. 403 `not_contacts` / 409 `room_conflict` already parse via
   `TokenRequestException.detail` (`error` or `detail` key) and wrap in
   `SessionEstablishmentFailure` from `_startLinked`. No new UI/copy.

## Work Log

- [2026-09-12T21:42:00Z] [GB] Claimed + preflight. `TalkTarget.id` is already
  `contact.pk`. Implementing threading; no new TalkTarget field.
- [2026-09-12T22:10:00Z] [GB] Implementation + tests. Ready for suite run.
- [2026-09-12T22:20:00Z] [GB] Mutation: omitting `peer_pk` from TokenClient turned the encoding test red (`Expected: 'AQID…' Actual: <null>`), then restored. Full suite +1458 ~40 -0, analyze clean. → needs_review.
