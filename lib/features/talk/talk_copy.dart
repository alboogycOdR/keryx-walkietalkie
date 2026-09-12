/// Design §5's literal copy strings, kept in one place so this screen has
/// exactly one source for each — never inlined ad hoc at each call site.
///
/// v2 (Design §2.1/§5): every v1 channel/route string is gone from this
/// file — Design §5's closing rule ("Never 'channel', 'tune', 'station',
/// 'LOCAL', 'LINKED' or 'AUTO' anywhere in the user-facing copy") is a hard
/// acceptance criterion for TASK-092, and `TalkCopy` is the single place the
/// Talk screen draws its strings from.
abstract final class TalkCopy {
  static const String readyToTalk = 'Ready.';
  static const String holdToTalk = 'Hold to talk';
  static const String requestingChannel = 'Requesting…';
  static const String connectionLost = 'Connection lost';

  /// v1's "Channel busy" renamed off channel vocabulary — the host reducer's
  /// own contention deny (as opposed to this task's new local
  /// audience-refusal flash) still needs a copy string.
  static const String someoneAlreadyTransmitting =
      'Someone is already transmitting';
  static const String microphonePermissionRequired =
      'Microphone permission required';
  static const String someoneIsSpeaking = 'Someone is speaking';
  static const String transmissionLocked = 'Transmission locked';
  static const String transmitting = 'Transmitting';
  static const String lockTransmission = 'Lock transmission';
  static const String releaseTransmission = 'Release transmission';
  static const String startTransmitting = 'Start transmitting';
  static const String stopTransmitting = 'Stop transmitting';

  /// Design §4: the "Nobody listening" state's label, reused verbatim as
  /// the [AudienceState.nobodyListening] default reason.
  static const String nobodyIsListening = 'Nobody is listening';

  /// Design §2.1's no-target state.
  static const String noTargetHeadline = 'No one selected yet';
  static const String addFirstContact = 'Add your first contact';
  static const String createAGroup = 'Create a group';

  /// Design §2.1's own-status control and chevron.
  static const String ownStatus = 'Your status';
  static const String openTargetDetail = 'Open details';

  /// Design §4's "Target on DND" row.
  static const String alert = 'Alert';

  /// Design §4's "Alert received" banner.
  static const String reply = 'Reply';
}
