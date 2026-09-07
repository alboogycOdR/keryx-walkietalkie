# TASK-049 — Channels landing screen

## Brief

The default landing screen, built fresh against the new Design spec's mockup:
connection indicator, current-channel card, Open Talk, recent-channel recall,
Select channel, persistent nav. Reads only TASK-046's projection and dispatches
only its typed intents. Two easy-to-violate prohibitions carry most of the risk:
no fake online count, and no background subscription sweep across the 99-channel
space to populate presence.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.1 (content order, card
  contents, recents, empty state, the two prohibitions), §1.
- PRD UX-D01, UX-D05 (recall is not history), UX-FR-002/004/005/008/010.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §6 — channel-memory writes
  stay serialized and deduplicated; no schema expansion for R1.
- Verification VT-020 (recall order/deduplication).

## Approach

New widgets per ADR-001 §7 item 2 — nothing from TASK-043 is wrapped. Configured
mode and actual status are separate fields on the card. Recent entries route
through the authoritative tune intent; the selector flow itself is TASK-050's,
this screen only launches it. Widget tests run against fake host/projection —
no sockets, no native plugins (Verification §2).

## Work Log

- [2026-09-07T20:47:00Z] [GB] Session start. Claimed TASK-049, branch `task/TASK-049-gb` off master `720b8eb`. Preflight: new territory `lib/features/channels/**` and `test/features/channels/**`; dossier exists. Plan: `ChannelsLanding` Consumer widget over `radioHostProvider` + `radioStateProvider` + `settingsProvider`, projecting `RadioViewState`; Open Talk / Select channel are callbacks (Talk is TASK-051, selector is TASK-050). Channel memory rendered from `RadioHostSnapshot.channelMemory` (newest-first, deduped, cap 6). No presence sweep, no online/member/unread affordances. Tokens via `KeryxUxTokens`. Tests use `FakeRadioHost` + seeded radio/settings — no sockets/plugins. Will not edit `lib/app_shell/**`.
- [2026-09-07T20:58:00Z] [GB] Implementation complete. `ChannelsLanding` ships in `lib/features/channels/**` with two-digit CH/code, Configured vs Effective as separate fields, Open Talk / Select channel callbacks, recent recall (deduped, cap 6, tune-only), empty-state copy, no presence sweep (`watchChannel` test seam never invoked), no online/member/unread/contact/history copy. Tokens only — no `Color(0x` / `Colors.` literals. Widget tests use `FakeRadioHost` + `InMemorySettingsStore` + seeded `radioStateProvider`. `lib/app_shell/channels_screen.dart` left untouched (TASK-048 frozen); a later wiring pass should compose `ChannelsLanding` into that destination. Revert-mutation-checked 3 tests (99-channel `watchChannel` sweep; recent tap also opening Talk; swapping Configured/Effective labels) — each flipped exactly its own case red; restored. `flutter analyze` on territory: no issues. Repo-wide: 8 pre-existing TASK-035 warnings only. Full suite 1163 passed / 0 failed / 40 skipped (18 new). → needs_review.
