import 'package:keryx/core/radio_host/radio_host.dart'
    show RadioHost, TuneResult;
import 'package:keryx/core/settings/settings_repository.dart' show KeryxSettings;

/// The typed intents every Wave 4 screen dispatches (Technical §5.1/§9's
/// "define the typed intents the UI dispatches
/// (press/release/latch-release/tune/apply-settings/join-event), all of
/// which delegate to the host").
///
/// Every method here forwards, unchanged, straight to the injected
/// [RadioHost] — this class holds no state of its own, performs no
/// transport/floor/audio/platform call itself, and never synthesizes a
/// result (Technical §5.1: "The UI must not dispatch `TransmitGranted`,
/// `EndTransmit` or remote floor events to simulate a result"). It exists
/// so screens depend on a narrow, presentation-scoped surface rather than
/// the full `RadioHost` contract directly — the same reason
/// `RadioViewState` exists on the read side.
class RadioViewIntents {
  const RadioViewIntents(this._host);

  final RadioHost _host;

  /// Authoritative command path entry point (Technical §5.1) — forwards
  /// straight to `RadioHost.pressPtt`, which itself forwards straight to
  /// `FloorEngine.requestTransmit`. Never grants locally.
  void press() => _host.pressPtt();

  /// Ordinary PTT release — forwards to `RadioHost.releasePtt`.
  void release() => _host.releasePtt();

  /// A deliberate latch release, exposed separately from [release] because
  /// a latch is UI-owned while the release action itself is always the
  /// host's job (Technical §4; `RadioHost.releaseLatch`'s own dartdoc).
  void releaseLatch() => _host.releaseLatch();

  /// Serialized channel/code change — forwards to `RadioHost.tune`.
  Future<TuneResult> tune(int channel, int privacyCode) =>
      _host.tune(channel, privacyCode);

  /// Applies a settings snapshot — forwards to `RadioHost.applySettings`.
  Future<void> applySettings(KeryxSettings settings) =>
      _host.applySettings(settings);
}
