/// EMG pin (FR-025). The indicator stays up until the *sender* clears it.
///
/// Pre-emption itself is the arbiter's `TX_REQ(prio=1)` path; this type
/// only tracks the pin so the host can project the EMG telltale.
class EmergencyPin {
  String? _peer;

  /// Peer that currently pins EMG, or `null` if clear.
  String? get peer => _peer;

  bool get isPinned => _peer != null;

  void pin(String peer) {
    if (peer.isEmpty) {
      throw ArgumentError.value(peer, 'peer', 'must not be empty');
    }
    _peer = peer;
  }

  /// Clear only when [peer] is the pin holder. A stray `EMG_CLR` from
  /// someone else is ignored.
  bool clear(String peer) {
    if (_peer == peer) {
      _peer = null;
      return true;
    }
    return false;
  }

  void reset() => _peer = null;
}
