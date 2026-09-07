# KERYX — Mobile UX Redesign Technical & Migration Specification

> **Version:** 1.0 | **Status:** Proposed for DEVDepartment technical planning  
> **Baseline commit:** `55c51da237c89767806969a52b30cc30e44025c9`  
> **Changelog:** v1.0 — defines safe migration from the existing FaceScreen-owned session to a persistent application host and modern presentation layer.

## 0. Constraints and source of truth

The existing backend is not assumed fully production-proven. The latest baseline commit records a real-device LOCAL audio issue, an Android WebRTC routing fix, and a remaining remote-track handling concern; the fix was not hardware-verified. R1 must preserve and verify the backend rather than declaring it complete. Any confirmed transport defect is a separate, narrowly scoped corrective task, not an excuse to replace the engine during a UI sprint.

The existing `RadioReducer`, `FloorEngine`, session transports, discovery, signaling, LiveKit and token-service contracts remain authoritative. No speculative backend API may be introduced to make a mockup work. All work follows AGENTS.md, docs/COORDINATION_PROTOCOL.md and the actual current autopilot.json configuration. The observed integration branch is `master`, not `main`. Revalidate current state and active worktrees before planning.

## 1. Verified repository architecture

| Area | Existing implementation | Migration treatment |
|---|---|---|
| Entry shell | `lib/app.dart`, `lib/main.dart` | Replace navigation composition; retain a single ProviderScope. |
| Lifecycle host | `lib/features/face/face_screen.dart` | Extract boot/session/audio/service ownership from disposable presentation. |
| Session seam | `lib/features/face/session_host.dart` | Reuse or move with compatibility; preserve injection and fake testing. |
| State | `lib/core/state/radio_state.dart`, `radio_state_controller.dart` | Preserve reducer/event semantics. Add projections only when needed. |
| Floor | `lib/core/floor/**` | Preserve authoritative grant/release/arbitration/TOT behavior. |
| Session | `lib/services/session/radio_session_controller.dart` | Preserve composition and retune contracts; fix only separately approved defects. |
| PTT | `lib/features/ptt/**` | Reuse interaction contract or replace visual layer while retaining safe intents and tests. |
| Face | `lib/features/face/face_view.dart` | Retire the hardware presentation after successor tests pass. |
| Roster | `lib/features/face/roster_screen.dart`, `roster.dart` | Reuse live state; distinguish unavailable LINKED roster and unmeasured quality. |
| Settings | `lib/core/settings/**`, `lib/features/settings_panel/**` | Preserve storage and settings schema; reorganize presentation. |
| Event QR | `lib/features/event_qr/**` | Retain payload and validation contracts; add explicit route-transition UX. |
| Android | `android/**`, `lib/services/platform/**` | Preserve foreground service, notification actions, audio routing and permissions. |
| Tests | `test/**`, `tests/**` | Preserve historical tests; add successor tests rather than simply deleting failures. |

### 1.1 Important existing limitations

The current `FaceScreen` owns identity/bootstrap, permission gates, SFX engine, session factory, floor effect subscriptions, foreground service, station notifier and tuning callbacks. Its `dispose()` tears down the session and service. Therefore putting the existing FaceScreen beneath a disposable Talk route is incorrect: it would terminate communication on navigation. A persistent host must be introduced first.

The current `RadioSessionController` captures settings at construction. Meaningful mode, URL, LOCAL-only, TOT and busy-lockout changes require host-managed reconstruction. `retune` rebuilds channel-scoped resources. The new UI may not change a numeral without executing that operation.

The existing station stream is LOCAL signaling-backed; LINKED mode does not provide a complete roster through this interface. Existing `StationInfo.signalQuality` defaults to a placeholder maximum value. The new UI must not render this as actual measured signal. The existing ring uses a state-driven proxy and currently labels itself an amplitude meter. That misleading label must not migrate.

The current QR join requires an already-active LINKED session. A scan in LOCAL can currently result in a displayed error; it must become an explicit, safe route-transition workflow. Existing numeric QR export is implemented; keyed export requires additional wiring and must not be assumed complete.

The existing state machine has a known equality concern: its value equality does not include every state field. ORCH must assess whether any new selected/reduced projection depends on those fields and create a focused corrective successor task if needed, without changing reducer semantics opportunistically.

## 2. Target architecture

```text
KeryxApp / single ProviderScope
│
├── Persistent RadioHost
│   ├── Identity + settings bootstrap
│   ├── Permission coordinator
│   ├── SessionHost / RadioSessionController
│   ├── FloorEngine (authoritative)
│   ├── SfxProjection + AudioSink
│   ├── Android RadioServiceController
│   └── RadioState + host-derived presentation state
│
└── MobileAppShell
    ├── Channels
    ├── Talk
    ├── Stations / Radio controls / QR
    └── Settings
```

The host is created once at the application/session scope and survives tab and route changes. It owns exactly one active radio session, engine, audio pipeline and foreground-service controller. UI widgets subscribe to immutable state and invoke typed intents. No visual widget may start a transport, publish microphone media, construct a floor engine or own the foreground service.

The implementation may use a Riverpod Notifier/AsyncNotifier or a dedicated lifecycle service exposed through Riverpod. ORCH must choose based on existing repository conventions and testability. The design does not mandate a new state-management dependency or routing package.

## 3. Host contract

The implementation shall expose a testable, narrow interface equivalent to:

```dart
abstract interface class RadioHost {
  RadioViewState get current;
  Stream<RadioViewState> get changes;

  Future<void> start();
  Future<void> powerOff();
  Future<TuneResult> tune(int channel, int code);
  Future<void> applySettings(KeryxSettings settings);
  Future<JoinResult> joinEvent(EventLinkPayload payload);

  void pressPtt();
  void releasePtt();
  void releaseLatch();
  Future<void> dispose();
}
```

This is an illustrative contract, not a demand to introduce these exact names or return types. The implementation must preserve the existing `SessionHost` seam and injected fakes where practical. Typed results should distinguish successful operation, validation failure, cancellation, unavailable route and transport failure. The UI must not parse exception text to determine state.

The host exposes current channel/code, configured mode, effective route, phase, active speaker, station visibility, entitlement, permission/service condition and pending operations. The actual floor engine remains the source of truth for TX ownership. Never duplicate the reducer state into an independently mutable UI state machine.

## 4. Lifecycle invariants

- Exactly one application-scoped active session and one active floor engine per radio instance.
- Navigation alone never invokes start, dispose, retune, powerOff or applySettings.
- A single boot operation is in flight; concurrent boots share or serialize its result.
- Session reconstruction and retune are serialized. A stale completion must not adopt an obsolete session or overwrite the latest intended channel.
- Teardown of an old session is awaited or otherwise proven complete before conflicting channel-scoped resources are reused; any intentional overlap must be justified and tested.
- A route-level PTT gesture is released on cancellation/disposal. A deliberate latch is owned by the persistent host and survives ordinary navigation until explicit release, TOT or authoritative termination.
- Power-off, service-killed, permission loss and engine disposal cannot leave a locally transmitting microphone track active.
- Navigation away from Talk does not suppress incoming audio or notification actions.
- Session-affecting settings are applied through the host; presentation-only settings do not rebuild communication.
- State and subscriptions are disposed once, without retained listeners from replaced sessions.

## 5. PTT and state projection

### 5.1 Authoritative command path

```text
Pointer/hardware/notification intent
    → persistent host
    → FloorEngine.requestTransmit / releaseTransmit
    → existing floor effects and state bridge
    → RadioState
    → immutable RadioViewState
    → Talk UI
```

The UI must not dispatch `TransmitGranted`, `EndTransmit` or remote floor events to simulate a result. A request indicator may appear on the intent, but red TX appears only after authoritative grant. A hardware/notification action must continue to use the same engine and remain correct when no Talk route is mounted.

### 5.2 Composite presentation state

Model phase, emergency, latch, denied flash, connection condition and service/permission faults independently. Do not use a single priority switch that hides actual TX because emergency is active. `PttState` may be extended or replaced by a pure adapter, but the underlying `RadioPhase` remains unchanged unless a separately approved defect requires a reducer change.

The existing `PttButton` has pointer suppression and double-tap latch behavior. A new component must preserve or explicitly replace those semantics, with tests for cancellation, disposal, duplicate events, latch release and disabled transitions. No route disposal should accidentally cancel a deliberate persistent latch.

### 5.3 Telemetry honesty

Introduce a measured/unavailable quality model at the presentation boundary if needed. Do not use the existing placeholder value as proof of quality. Unknown LINKED roster count is not zero. Remove the simulated amplitude meter's measurement semantics or use a verified real audio tap in a separately scoped telemetry task. An animation driven by phase is decorative and must not be described as measured RMS.

## 6. Tuning and channel operations

The existing channel and code ranges remain 1–99 and 0–38. Direct entry and recall feed one host tune operation. Validate before submission. Keep a requested target separate from the authoritative current channel while tuning; do not optimistically claim connection to a new channel.

The current implementation dispatches TuneTo and launches asynchronous retune without waiting. ORCH must inspect and resolve the associated race/failure behavior as a dedicated migration task. The successor must serialize competing tune requests and define a deterministic policy: latest requested target wins, pending intermediate operations are canceled or completed safely, and the visible state represents the actual active chain. Failed retune must provide retry/recovery and cannot leave the UI claiming an unverified channel. Do not invent rollback support if the underlying operation has already torn down the previous chain; implement an explicit recovery policy and test it.

Existing channel-memory writes remain serialized and deduplicated. No schema expansion is required for R1. Keyed/private channels must use existing supported contracts; any missing identity or channel persistence capability is a separate scoped task.

## 7. Settings and connectivity

Retain `KeryxSettings`, SettingsRepository storage key, defaults and migration behavior. New appearance preferences may be added additively with safe defaults. Do not overwrite existing stored data with a reduced settings object. Preserve the existing LOCAL-only guard, relay configuration and actual AUTO policy.

The UI must distinguish configured preference from effective route. A configured AUTO value does not establish that the app is currently connected to both LAN and WAN. The existing controller chooses LINKED when a relay is configured, otherwise LOCAL, subject to force-LOCAL; actual route and fallback handling must be verified. Any change to mode policy requires a separate ADR.

A session-affecting settings change while transmitting must be deferred or safely serialized according to an explicit policy. No hot-mic window is permitted during teardown/recreation. Apply non-session settings without reconnecting unnecessarily.

## 8. Event QR and deep links

Retain current payload schema, expiry validation and token-service contracts. Add a host-level join coordinator that checks effective route and LOCAL-only policy before invoking the existing LINKED-only join. A required route change is user-approved, cancellable and safely serialized. Do not initiate WAN traffic when force-LOCAL is enabled. Failure must leave a known active session/selection or a clearly unavailable state with recovery.

The existing scanner and export components may be reused. Keyed export, persistence and server-side expiration behavior must be verified independently before being represented as complete. No unreviewed secret or passphrase may be logged or placed in analytics.

## 9. UI module migration

Proposed successor modules (names are illustrative; ORCH resolves exact paths):

```text
lib/app_shell/
lib/features/channels/
lib/features/talk/
lib/features/stations/
lib/features/radio_controls/
lib/features/settings/
lib/core/radio_host/
lib/core/presentation/
```

Do not create a parallel audio or session service beneath these modules. Preserve existing public APIs until consumers and tests migrate. Prefer adapters and additive changes over a broad rename. If moving `SessionHost` or permissions interfaces, retain compatibility exports during the transition. A separate integration task owns shared route registration, app.dart, shared providers and final wiring.

The existing frozen feature and core territories must not be modified by a builder without explicit successor ownership. ORCH must resolve all path overlaps and assign cross-cutting integration work serially. Do not delete the old face and its tests until the new host and new presentation are independently verified and the owner approves retirement.

## 10. Legacy compatibility and migration

Existing installation identity, callsign, settings, channel memory and network configuration survive the update. A migration test loads a real old-version settings fixture and verifies no data loss or reset. New theme preferences default safely. No mandatory account or network setup appears after upgrade.

Keep a temporary legacy route or compatibility harness on a development branch if it is useful for side-by-side validation; this is not a requirement to ship two interfaces. Retire the old route, assets and tests only through an explicit cleanup task after successor golden tests and real-device acceptance pass.

## 11. Planning dependencies (ORCH to assign task IDs)

| Sequence | Work package | Required evidence |
|---|---|---|
| A | Read-only baseline audit, current task reconciliation, ADR and design approval | Inventory, conflict matrix, baseline tests, owner decisions |
| B | Persistent host extraction and lifecycle tests | Fake-based ownership, boot/dispose/navigation tests |
| C | Pure presentation projections and state/telemetry honesty | State matrix and truthfulness tests |
| D | Design tokens and approved UI components | Prototype sign-off, accessibility/golden baselines |
| E | Channels, selector and tuning coordinator | Real retune and race/failure tests |
| F | Talk screen, PTT and radio controls | Floor, latch, emergency and cancellation tests |
| G | Stations, Settings and Event QR integration | Live streams, migration, connectivity tests |
| H | Final shell wiring and old-face retirement | Complete regression, hardware tests, release review |

These are work packages, not task allocations. ORCH determines actual task IDs, assignments, sizes and dependencies after inspecting live PLAN.md and ownership. Cross-cutting changes may require integration tasks before downstream feature work.

## 12. Existing technical debt and explicit blockers

The baseline commit records a still-unverified real-device audio routing correction and remote-track handling gap. Confirm bidirectional audio before declaring backend preservation successful. Review the parked FR-025 emergency-preemption issue in PLAN/REVIEW rather than claiming emergency behavior fully proven. Verify LINKED presence, telemetry, keyed channels, scan/replay/VOX entitlements and supported features individually. Unknown or incomplete functionality is disclosed as such; it is not automatically in scope to complete all existing backlog items.

## 13. Integration and release rules

No changes to PLAN.md, autopilot.json, AGENTS.md, the coordination protocol, shared branch settings or active worktrees are authorized by the spec importer. ORCH records approval, creates successor tasks and owns their integration. Builders work only in assigned Owned_Paths and their task branches. Use the current protocol's supported PLAN commit mechanism, not legacy raw ref-push shortcuts. No direct code commit to the integration branch. Every change requires scoped tests, independent review and an explicit verdict. No claimed test or hardware result may be treated as verified without evidence.
