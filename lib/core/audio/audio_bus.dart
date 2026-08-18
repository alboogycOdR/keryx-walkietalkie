/// Dual-bus mix destinations (TS §7.2).
enum AudioBus {
  /// Network / WebRTC voice. SFX never routes here.
  voice,

  /// Local assets only. Instant and identical regardless of network (P4).
  sfx,
}
