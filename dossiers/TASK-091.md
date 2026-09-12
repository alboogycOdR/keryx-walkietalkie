# TASK-091 — v2 Groups tab — list, detail with members and presence, invites, admin actions, join with a code

## Brief

The Groups tab body and the group detail screen. List rows: glyph, name, `n online · m members`; tap → `onSelectTarget(group)`; chevron → detail. Detail: member list with presence and admin marks, invite (QR + link per Technical §5.2 with the expiry presets reused from `event_link.dart`), Leave, and admin-only Rename, Remove member (which triggers rotation through the groups store), Rotate key, Make admin. Floating: New group (name → create → invite screen) and Join with a code (scan or paste). Toasts for 'key changed' and 'you were removed'. Uses the TASK-086 groups store and TASK-087 room derivation; no shell dependencies.

## Spec pointers

- specs/KERYX_v2.0_Design_v1.0.md §2.3, §4 (key rotated / removed states); PRD V2-FR-020..025; Technical §5.2 (invite link); Verification V2-VT-026, V2-VT-030 (groups goldens)
- Owned_Paths: lib/features/groups/**, test/features/groups/**, dossiers/TASK-091.md
- Depends_On: TASK-086, TASK-087

## Work Log

- [2026-09-11] [S5] Implemented the full Groups tab + detail flow in `lib/features/groups/**`:
  - `group_invite_link.dart` — `keryx://join?v=2&g=&t=&s=&exp=` encode/decode (round-trips, rejects malformed/expired/wrong-version/short-secret input); reuses `EventLinkExpiryPreset` read-only from `lib/features/event_qr/event_link.dart`.
  - `groups_copy.dart` — user-facing copy (tab title, empty state, toasts, group-full message, etc).
  - `group_view_models.dart` — pure helpers: `buildGroupListRow`, `buildMemberRows`, `isLastAdmin`, `oldestMemberToPromote`, `isGroupFull` (cap 25), presence-dot mapping.
  - `groups_list_controller.dart` / `groups_list_screen.dart` — list screen bound to `GroupsController`'s membership stream + per-group member/presence fetch; FAB actions "New group"/"Join with a code"; empty state; never fabricates a count for an unfetched group.
  - `group_detail_controller.dart` / `group_detail_screen.dart` — member list with presence + admin marks; Leave (promotes the oldest remaining member first when I am the last admin, via `oldestMemberToPromote`); admin-only Rename/Remove member/Rotate key/Make admin, fully absent from the widget tree (not just disabled) for non-admins; Remove member reseals+rotates through `GroupsController.removeMember` (business logic stays in `lib/core/groups/**`, this file only orchestrates); toasts for `GroupKeyChanged`/`GroupMembershipEnded` via `GroupsController.events`.
  - `group_invite_screen.dart` — QR (`qr_flutter`, already in pubspec) + copyable link, expiry preset dropdown (`EventLinkExpiryPreset`), re-mints on preset change.
  - `join_with_code_screen.dart` — paste box + `mobile_scanner` (already in pubspec, no new dependency added) scan toggle; rejects an expired link locally before any network call.
  - `new_group_screen.dart` — name prompt → `GroupsController.createGroup` → hands the membership to `onCreated` (caller routes to invite).
  - Found and fixed one real bug while reading `group_detail_controller.dart`: `_mintNewSecret` originally derived bytes from `DateTime.now().microsecondsSinceEpoch` (not cryptographically secure) instead of `Random.secure()` — corrected to match `GroupsController`'s own CSPRNG standard.
  - 26th-join cap and last-admin-leave promotion are **not reimplemented in the UI** — `isGroupFull`/`oldestMemberToPromote` are pure helpers the controller layer calls, and the server (`group_full` error) plus `GroupsController`/`GroupDetailController` own the actual enforcement/promotion API calls; the UI only renders `GroupsCopy.groupFullMessage` and calls `leave()`.
  - Tests: `test/features/groups/**` — view-model unit tests, invite-link round-trip/expired/malformed tests, `GroupsListController`/`GroupDetailController` tests against a real loopback `FakeDirectoryServer` (admin-hidden state, remove-member rotates and drops the row, last-admin-leave promotes-then-leaves, key-rotated/removed-from-group toasts), widget tests for every screen, and goldens (`test/features/groups/goldens/**`: empty/populated × dark/light for the list screen).
  - `flutter analyze --no-pub` (whole project): **No issues found!**
  - `flutter test --no-pub` (whole project, foreground): **1669 passed, 40 skipped, 2 failed** — the 2 failures are `test/simulation/soak_test.dart` KRX-044 seeds 498/499, explicitly PARKED by owner decision 2026-08-21T17:05Z (FR-025 emergency-preemption race) per this repo's own CLAUDE.md; not touched, not weakened, pre-existing and unrelated to this task.
  - Status set to `needs_review`.

- [2026-09-12] [S5] Resumed session (checkpoint/handoff after previous session ended before flipping PLAN.md status). Working tree already clean and correct on `task/TASK-091-s5` — no code changes needed. Re-ran verification fresh, in the foreground, from this worktree:
  - `flutter analyze --no-pub` (whole project): No issues found! (95.6s)
  - `flutter test --no-pub` (whole project, foreground): All tests passed — 1673 total, including the previously-flagged `KRX-044` soak seeds 498/499 (owner-parked FR-025 flake), which passed cleanly this run with zero changes to soak/SafetyMonitor code.
  - Ticked all five acceptance criteria in PLAN.md against the diff (each maps to a spec sentence per AGENTS.md convention) and recorded Test_Evidence there.
  - PLAN.md updated via `scripts/plan_commit.sh`: Status → `needs_review`.
