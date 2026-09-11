# TASK-085 — v2 directory service II — groups, invites, rotation, alerts, membership-gated /token

## Brief

Second half of the directory. Groups: create (creator's sealed secret copy stored), invites with expiry (token hash stored, secret never seen by the server), join (cap 25, refuse the 26th), member list with roles and presence, admin actions (make admin, rename, remove — server requires the sealed secrets for every remaining member in the same call, then bumps `key_version`), leave with last-admin succession. Presence fan-out extended to co-members; rotation notice pushed over the presence socket. Alerts: `POST /v2/alerts` delivered over the target's presence socket, rate-limited 1 per sender per target per 10 min. `/token`: verify the signed caller is a current member of `room_id` (room IDs are derived client-side; the server stores the expected room ID per group at create/rotate time and per 1:1 pair on demand). Update `openapi-v2.yaml`.

## Spec pointers

- specs/KERYX_v2.0_Technical_v1.0.md §4.2 (groups/alerts/token rows), §5.2 (invite), §5.3 (rotation); PRD V2-FR-020..025, V2-FR-050; Verification V2-VT-011, 012, 014, 015
- Owned_Paths: token-svc/**, dossiers/TASK-085.md
- Depends_On: TASK-084

## Work Log
