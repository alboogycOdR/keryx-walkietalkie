import 'package:keryx/core/radio_host/radio_host.dart';

/// Persistent (survives `TalkScreen` disposal/remount) deliberate-latch
/// flag, keyed by [RadioHost] identity.
///
/// `RadioHost.releaseLatch`'s own dartdoc and `RadioViewState.latched`'s
/// (Technical §4, `lib/core/presentation/radio_view_state.dart`) both say a
/// deliberate latch is "UI-owned" state that "survives navigation" — but
/// `RadioHost` exposes only a *release* operation, never an *acquire* one
/// (Technical §4's reasoning: the host has no reason to remember a
/// UI-presentation fact). Round-1 review (2026-09-08) found the first
/// implementation stored that flag on `_TalkScreenState` itself, which is
/// disposed on every route unmount — a latched transmission survived at the
/// engine level (correctly — `dispose()` never releases a latch) but became
/// *unreleasable from the UI* the moment the user navigated away and back,
/// because the remounted screen started with `_latched == false` and lost
/// the release affordance while the mic was still open.
///
/// This holder lives at module scope, not on any [State], so it survives
/// exactly as long as the [RadioHost] instance does — which is exactly as
/// long as Design/Technical require a deliberate latch to survive (the
/// persistent host itself outlives ordinary navigation; see TASK-045/046).
/// It never talks to a transport/floor/audio API itself — [engage] is a
/// pure bookkeeping call the caller makes only after a real grant, and
/// [release]/[of] never call `RadioHost.releaseLatch()` on their own; the
/// caller ([TalkScreen]) remains the one place that issues that intent, per
/// Technical §5.1.
///
/// Keyed by identity (an [Expando], not a value key) so a fresh
/// [RadioHost] — e.g. a new `FakeRadioHost()` per test, or a genuinely
/// replaced host — never inherits a stale latch flag from an unrelated
/// instance.
abstract final class TalkLatchState {
  static final Expando<bool> _latched = Expando<bool>('talk-latch');

  /// Whether [host] currently has a deliberate latch engaged, per this
  /// holder's bookkeeping. Defaults to `false` for a host never seen here.
  static bool of(RadioHost host) => _latched[host] ?? false;

  /// Records that [host]'s floor is now deliberately latched. Pure
  /// bookkeeping only — the caller is responsible for having already
  /// confirmed a real grant before calling this (Design §4/UX-FR-025: a
  /// latch may only be engaged once the floor is actually held).
  static void engage(RadioHost host) => _latched[host] = true;

  /// Clears [host]'s latch bookkeeping. Pure bookkeeping only — the caller
  /// is responsible for also issuing `RadioHost.releaseLatch()` so the
  /// engine actually releases the floor (Technical §4).
  static void release(RadioHost host) => _latched[host] = false;
}
