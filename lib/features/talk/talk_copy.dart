/// Design §5's literal copy strings, kept in one place so this screen has
/// exactly one source for each — never inlined ad hoc at each call site.
///
/// Quoted from spec verbatim: "Channel clear. Hold to talk.", "Requesting
/// channel…", "Channel busy", "Connection lost", "Microphone permission
/// required", "No other stations are currently visible".
abstract final class TalkCopy {
  static const String channelClear = 'Channel clear.';
  static const String holdToTalk = 'Hold to talk';
  static const String requestingChannel = 'Requesting channel…';
  static const String channelBusy = 'Channel busy';
  static const String connectionLost = 'Connection lost';
  static const String microphonePermissionRequired =
      'Microphone permission required';
  static const String noOtherStationsVisible =
      'No other stations are currently visible';
  static const String someoneIsSpeaking = 'Someone is speaking';
  static const String transmissionLocked = 'Transmission locked';
  static const String transmitting = 'Transmitting';
  static const String lockTransmission = 'Lock transmission';
  static const String releaseTransmission = 'Release transmission';
  static const String startTransmitting = 'Start transmitting';
  static const String stopTransmitting = 'Stop transmitting';
  static const String openStations = 'Stations';
  static const String openChannelPicker = 'Change channel';
  static const String emergencyActive = 'Emergency active';
  static const String rosterUnavailable = 'Member list unavailable';
}
