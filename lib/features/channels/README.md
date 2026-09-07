# `lib/features/channels`

TASK-049 — Design §2.1 Channels landing, built fresh (ADR-001 §7 item 2).

`ChannelsLanding` is the default-landing body: brand + connection indicator,
current-channel card (two-digit channel/code, **configured** mode and
**effective** route as separate fields, concise actual status), primary Open
Talk, six-entry recent recall, Select channel. It reads TASK-046's
`RadioViewState` projection and dispatches only `RadioViewIntents.tune`.

Open Talk and Select channel are callbacks. Talk is TASK-051; the selector
flow is TASK-050. This screen only launches them. Persistent navigation stays
on the TASK-048 shell (`MobileAppShell`); pass `persistentNavigation` only in
tests that need the full content-order including the bottom bar.

`lib/app_shell/channels_screen.dart` is frozen TASK-048 territory and is not
edited here. A later wiring pass should compose `ChannelsLanding` into that
destination.

Hard prohibitions (Design §2.1 / UX-FR-008):

- No fake online/member/unread/contact/history affordance.
- No background subscription sweep across the 99-channel space. The optional
  `watchChannel` constructor argument is a test seam and is never invoked.
