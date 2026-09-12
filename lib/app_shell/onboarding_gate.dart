import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/theme/ux_tokens.dart' show KeryxUxSpacing;
import 'package:keryx/features/onboarding/onboarding_screen.dart';
import 'package:keryx/features/restore/restore_screen.dart';

import 'mobile_app_shell.dart';

/// v2 (Design §2.6, Technical §8 "v1 install migration", V2-FR-001..004):
/// gates the shell behind first-run identity creation.
///
/// A **keyed install** — `IdentityRepository.privateKeySeedKey` already has
/// a value, whether from a real v2 first run or a v1 install already
/// migrated by an earlier `loadOrCreate()` call (Technical §8: "an existing
/// v1 install... gets a fresh key pair and keeps its callsign") — goes
/// straight to [MobileAppShell]. A **fresh install** (no stored key at all)
/// shows a chooser between creating a new identity (→ [OnboardingScreen])
/// and [RestoreScreen] (Design's "'Restore' entry" — surfaced here, at the
/// pre-shell gate, rather than inside `OnboardingScreen`'s callsign step:
/// that screen's `Owned_Paths` belongs to TASK-089, not this task, and its
/// constructor has no restore hook to attach to; disclosed compat decision,
/// same pattern as TASK-092's).
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, this.identityRepository, this.store});

  /// Test seam. Production constructs `IdentityRepository(SecureIdentityStore())`.
  final IdentityRepository? identityRepository;

  /// Test seam for the raw fresh-install check (reads the same key
  /// [IdentityRepository] itself would create/read). Production uses a
  /// second [SecureIdentityStore] instance — reading, never writing, ahead
  /// of `loadOrCreate()` so the check itself never creates the key it is
  /// testing for.
  final IdentityStore? store;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

enum _GateStage { loading, chooser, creating, restoring, done }

class _OnboardingGateState extends State<OnboardingGate> {
  late final IdentityRepository _identityRepo;
  late final IdentityStore _rawStore;
  _GateStage _stage = _GateStage.loading;
  RecoveryPhrase? _pendingPhrase;

  @override
  void initState() {
    super.initState();
    _identityRepo =
        widget.identityRepository ?? IdentityRepository(SecureIdentityStore());
    _rawStore = widget.store ?? SecureIdentityStore();
    unawaited(_checkFreshInstall());
  }

  Future<void> _checkFreshInstall() async {
    final existingKey = await _rawStore.read(
      IdentityRepository.privateKeySeedKey,
    );
    if (!mounted) return;
    setState(() {
      _stage = existingKey == null ? _GateStage.chooser : _GateStage.done;
    });
  }

  void _startCreate() {
    setState(() {
      _pendingPhrase = RecoveryPhrase.generate();
      _stage = _GateStage.creating;
    });
  }

  void _startRestore() => setState(() => _stage = _GateStage.restoring);

  Future<void> _finishCreate(String callsign) async {
    final phrase = _pendingPhrase;
    if (phrase == null) return;
    final keyPair = await phrase.deriveKeyPair();
    await _identityRepo.restoreKeyPair(keyPair);
    await _identityRepo.setCallsign(callsign);
    await _RecoveryPhraseVault(_rawStore).save(phrase.words);
    if (!mounted) return;
    setState(() => _stage = _GateStage.done);
  }

  Future<void> _finishRestore(DeviceIdentity identity) async {
    final keyPair = identity.keyPair;
    if (keyPair != null) {
      await _identityRepo.restoreKeyPair(keyPair);
      await _identityRepo.setCallsign(identity.callsign.value);
    }
    if (!mounted) return;
    setState(() => _stage = _GateStage.done);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _GateStage.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case _GateStage.chooser:
        return _OnboardingChooser(
          onCreate: _startCreate,
          onRestore: _startRestore,
        );
      case _GateStage.creating:
        return OnboardingScreen(
          key: const ValueKey('shell.onboarding'),
          words: _pendingPhrase!.words,
          onDone: (String callsign) => unawaited(_finishCreate(callsign)),
        );
      case _GateStage.restoring:
        return RestoreScreen(
          key: const ValueKey('shell.restore'),
          onRestored: (DeviceIdentity identity) =>
              unawaited(_finishRestore(identity)),
        );
      case _GateStage.done:
        return const MobileAppShell();
    }
  }
}

class _OnboardingChooser extends StatelessWidget {
  const _OnboardingChooser({required this.onCreate, required this.onRestore});

  final VoidCallback onCreate;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('shell.onboarding-chooser'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(KeryxUxSpacing.pageMargin),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Welcome to KERYX',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: KeryxUxSpacing.grid),
                FilledButton(
                  key: const ValueKey('shell.onboarding-create'),
                  onPressed: onCreate,
                  child: const Text('Create a new KERYX ID'),
                ),
                const SizedBox(height: KeryxUxSpacing.controlGap),
                OutlinedButton(
                  key: const ValueKey('shell.onboarding-restore-entry'),
                  onPressed: onRestore,
                  child: const Text('Restore from a recovery phrase'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Persists the 12-word recovery phrase behind its own dedicated secure
/// storage key so Settings' "Show recovery phrase" (Design §2.7) can
/// display it again later — `IdentityRepository` deliberately never stores
/// the phrase itself (only the HKDF-derived key seed, Technical §3.2, is
/// one-way), and that file is frozen territory this task cannot extend.
/// This is new state under this task's own composition code, using the
/// same storage plugin already a dependency, not a modification to any
/// frozen file.
class _RecoveryPhraseVault {
  const _RecoveryPhraseVault(this._store);

  static const key = 'keryx.v2.recovery_phrase_words';

  final IdentityStore _store;

  Future<void> save(List<String> words) =>
      _store.write(key, jsonEncode(words));
}

/// Reads back the phrase [_RecoveryPhraseVault] saved, for Settings' "Show
/// recovery phrase" control. `null` when nothing was ever saved (e.g. a
/// restored identity, which never went through [OnboardingScreen]).
class RecoveryPhraseVault {
  RecoveryPhraseVault([IdentityStore? store])
    : _store = store ?? SecureIdentityStore();

  final IdentityStore _store;

  Future<List<String>?> load() async {
    final raw = await _store.read(_RecoveryPhraseVault.key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList(growable: false);
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
