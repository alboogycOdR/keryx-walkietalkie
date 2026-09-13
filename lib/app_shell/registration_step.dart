import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keryx/core/theme/ux_tokens.dart' show KeryxUxSpacing;
import 'package:keryx/services/directory/directory.dart' show DirectoryErrorCode;

import 'directory_providers.dart';

/// v2 (Owner requirements 2026-09-13, Design §2.6): the onboarding
/// confirmation shown between choosing an ID and reaching the shell —
/// "make the onboarding sequence as explicit as possible, with
/// confirmations that it's been registered after they choose the ID."
///
/// Reads [registrationStatusProvider] (built on top of the same
/// [identityEnrolmentProvider] the host awaits at boot) and never blocks
/// reaching Talk beyond [_timeout]: an attempt that is still in flight after
/// that long is treated the same as "offline" — the ladder inside
/// `RegistrationStatusController` keeps retrying in the background either
/// way.
class RegistrationStep extends ConsumerStatefulWidget {
  const RegistrationStep({
    super.key,
    required this.onContinue,
    required this.onBackToCallsign,
  });

  /// Reach the shell (registered, offline, or a non-blocking failure).
  final VoidCallback onContinue;

  /// `callsign_taken`: the only failure that sends the user back a step
  /// instead of forward, since retrying the same callsign will just repeat.
  final VoidCallback onBackToCallsign;

  static const _timeout = Duration(seconds: 8);

  @override
  ConsumerState<RegistrationStep> createState() => _RegistrationStepState();
}

class _RegistrationStepState extends ConsumerState<RegistrationStep> {
  Timer? _timeoutTimer;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(RegistrationStep._timeout, () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(registrationStatusProvider);
    return Scaffold(
      key: const ValueKey('shell.registration-step'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(KeryxUxSpacing.pageMargin),
            child: _content(status),
          ),
        ),
      ),
    );
  }

  Widget _content(RegistrationStatus status) {
    if (status is RegistrationRegistered) {
      final label = (status.shortCode == null || status.shortCode!.isEmpty)
          ? status.callsign
          : '${status.callsign}·${status.shortCode}';
      return _Body(
        key: const ValueKey('shell.registration-step-registered'),
        message: '✓ Registered as $label',
        buttonKey: const ValueKey('shell.registration-step-continue'),
        buttonLabel: 'Continue',
        onPressed: widget.onContinue,
      );
    }

    if (status is RegistrationFailed &&
        status.code == DirectoryErrorCode.callsignTaken) {
      return _Body(
        key: const ValueKey('shell.registration-step-callsign-taken'),
        message: 'That KERYX ID is already registered — choose another.',
        buttonKey: const ValueKey('shell.registration-step-back'),
        buttonLabel: 'Back',
        onPressed: widget.onBackToCallsign,
      );
    }

    if (status is RegistrationUnregistered) {
      // No relay configured (or no key yet) — nothing to wait for.
      return _Body(
        key: const ValueKey('shell.registration-step-unregistered'),
        message: 'No relay configured yet.',
        buttonKey: const ValueKey('shell.registration-step-continue'),
        buttonLabel: 'Continue',
        onPressed: widget.onContinue,
      );
    }

    final isFailureLike = status is RegistrationOffline || status is RegistrationFailed;
    if (isFailureLike || _timedOut) {
      return _Body(
        key: const ValueKey('shell.registration-step-offline'),
        message: "Not online yet — KERYX will register automatically when "
            "you're connected.",
        buttonKey: const ValueKey('shell.registration-step-continue'),
        buttonLabel: 'Continue anyway',
        onPressed: widget.onContinue,
      );
    }

    // RegistrationInProgress, still within the timeout window.
    return const Column(
      key: ValueKey('shell.registration-step-in-progress'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CircularProgressIndicator(),
        SizedBox(height: KeryxUxSpacing.grid),
        Text('Registering with the relay…'),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    super.key,
    required this.message,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String message;
  final Key buttonKey;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: KeryxUxSpacing.grid),
        FilledButton(key: buttonKey, onPressed: onPressed, child: Text(buttonLabel)),
      ],
    );
  }
}
