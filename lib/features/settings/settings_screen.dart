import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'about_diagnostics.dart';
import 'appearance_preference.dart';
import 'session_settings.dart';
import 'settings_apply.dart';
import 'settings_copy.dart';
import 'settings_keys.dart';
import 'settings_rows.dart';

typedef SettingsConfirm =
    Future<bool> Function({required String title, required String body});

/// Design §2.6 Settings — six ordinary mobile sections over the
/// unchanged `KeryxSettings` model (ADR-001 §6). Widget tree is new.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.identityRepository,
    this.confirm,
    this.appVersion = SettingsCopy.appVersion,
  });

  /// Test seam. Production constructs `IdentityRepository(SecureIdentityStore())`.
  final IdentityRepository? identityRepository;

  /// Test seam. Production shows the reconnect confirmation dialog.
  final SettingsConfirm? confirm;

  final String appVersion;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final IdentityRepository _identityRepo;
  late final AppearanceStore _appearanceStore;
  late final SettingsApplyCoordinator _apply;
  StreamSubscription<RadioHostSnapshot>? _hostSub;

  RadioHostSnapshot _snapshot = const RadioHostSnapshot();
  DeviceIdentity? _identity;
  AppearancePreference _appearance = AppearancePreference.defaults;
  KeryxSettings? _pending;
  String? _regionError;
  String? _relayError;
  String? _tokenError;
  String? _callsignError;

  @override
  void initState() {
    super.initState();
    _identityRepo =
        widget.identityRepository ?? IdentityRepository(SecureIdentityStore());
    _appearanceStore = AppearanceStore(ref.read(settingsStoreProvider));
    final RadioHost host = ref.read(radioHostProvider);
    _snapshot = host.current;
    _apply = SettingsApplyCoordinator(
      host: host,
      save: (KeryxSettings next) =>
          ref.read(settingsProvider.notifier).save(next),
    );
    _hostSub = host.changes.listen((RadioHostSnapshot snapshot) {
      if (!mounted) {
        return;
      }
      setState(() => _snapshot = snapshot);
      unawaited(_flushDeferred());
    });
    unawaited(_loadIdentity());
    unawaited(_loadAppearance());
  }

  @override
  void dispose() {
    unawaited(_hostSub?.cancel());
    super.dispose();
  }

  Future<void> _loadIdentity() async {
    final DeviceIdentity identity = await _identityRepo.loadOrCreate();
    if (mounted) {
      setState(() => _identity = identity);
    }
  }

  Future<void> _loadAppearance() async {
    final AppearancePreference preference = await _appearanceStore.load();
    if (mounted) {
      setState(() => _appearance = preference);
    }
  }

  Future<bool> _confirm() {
    final SettingsConfirm? injected = widget.confirm;
    if (injected != null) {
      return injected(
        title: SettingsCopy.confirmTitle,
        body: SettingsCopy.confirmBody,
      );
    }
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          key: SettingsKeys.confirmDialog,
          title: const Text(SettingsCopy.confirmTitle),
          content: const Text(SettingsCopy.confirmBody),
          actions: <Widget>[
            TextButton(
              key: SettingsKeys.confirmCancel,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(SettingsCopy.confirmCancel),
            ),
            TextButton(
              key: SettingsKeys.confirmApply,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(SettingsCopy.confirmApply),
            ),
          ],
        );
      },
    ).then((bool? value) => value ?? false);
  }

  Future<void> _propose(KeryxSettings current, KeryxSettings next) async {
    final RadioState radio = ref.read(radioStateProvider);
    final SettingsApplyResult result = await _apply.propose(
      current: current,
      next: next,
      snapshot: _snapshot,
      radio: radio,
      confirmSession: _confirm,
    );
    if (!mounted) {
      return;
    }
    setState(() => _pending = result.pending);
  }

  Future<void> _flushDeferred() async {
    if (_apply.pending == null) {
      return;
    }
    final RadioState radio = ref.read(radioStateProvider);
    final SettingsApplyResult result = await _apply.flushDeferred(
      snapshot: _snapshot,
      radio: radio,
    );
    if (!mounted) {
      return;
    }
    setState(() => _pending = result.pending);
  }

  void _cancelDeferred() {
    _apply.cancelDeferred();
    setState(() => _pending = null);
  }

  Future<void> _setTheme(AppearanceTheme theme) async {
    final AppearancePreference next = _appearance.copyWith(theme: theme);
    await _appearanceStore.save(next);
    if (mounted) {
      setState(() => _appearance = next);
    }
  }

  Future<void> _setCallsign(String raw) async {
    try {
      final DeviceIdentity identity = await _identityRepo.setCallsign(raw);
      if (mounted) {
        setState(() {
          _identity = identity;
          _callsignError = null;
        });
      }
    } on FormatException {
      if (mounted) {
        setState(() => _callsignError = SettingsCopy.callsignInvalid);
      }
    }
  }

  Brightness _brightnessFor(BuildContext context) {
    switch (_appearance.theme) {
      case AppearanceTheme.light:
        return Brightness.light;
      case AppearanceTheme.dark:
        return Brightness.dark;
      case AppearanceTheme.system:
        return MediaQuery.platformBrightnessOf(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RadioState>(radioStateProvider, (RadioState? _, RadioState _) {
      unawaited(_flushDeferred());
    });

    final AsyncValue<KeryxSettings> settingsAsync = ref.watch(settingsProvider);
    final RadioState radio = ref.watch(radioStateProvider);
    final Brightness brightness = _brightnessFor(context);

    return Theme(
      data: keryxUxThemeData(brightness: brightness),
      child: settingsAsync.when(
        data: (KeryxSettings settings) {
          final RadioViewState view = RadioViewState.project(
            radioState: radio,
            hostSnapshot: _snapshot,
            settings: settings,
          );
          return _SettingsScaffold(
            settings: settings,
            view: view,
            identity: _identity,
            appearance: _appearance,
            pending: _pending,
            appVersion: widget.appVersion,
            regionError: _regionError,
            relayError: _relayError,
            tokenError: _tokenError,
            callsignError: _callsignError,
            onPropose: (KeryxSettings next) => unawaited(_propose(settings, next)),
            onTheme: (AppearanceTheme theme) => unawaited(_setTheme(theme)),
            onCallsign: (String raw) => unawaited(_setCallsign(raw)),
            onCancelDeferred: _cancelDeferred,
            onRegionError: (String? error) =>
                setState(() => _regionError = error),
            onRelayError: (String? error) => setState(() => _relayError = error),
            onTokenError: (String? error) => setState(() => _tokenError = error),
          );
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (Object _, StackTrace _) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(KeryxUxSpacing.pageMargin),
              child: Text(
                SettingsCopy.loadFailed,
                key: SettingsKeys.loadFailed,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({
    required this.settings,
    required this.view,
    required this.identity,
    required this.appearance,
    required this.pending,
    required this.appVersion,
    required this.regionError,
    required this.relayError,
    required this.tokenError,
    required this.callsignError,
    required this.onPropose,
    required this.onTheme,
    required this.onCallsign,
    required this.onCancelDeferred,
    required this.onRegionError,
    required this.onRelayError,
    required this.onTokenError,
  });

  final KeryxSettings settings;
  final RadioViewState view;
  final DeviceIdentity? identity;
  final AppearancePreference appearance;
  final KeryxSettings? pending;
  final String appVersion;
  final String? regionError;
  final String? relayError;
  final String? tokenError;
  final String? callsignError;
  final ValueChanged<KeryxSettings> onPropose;
  final ValueChanged<AppearanceTheme> onTheme;
  final ValueChanged<String> onCallsign;
  final VoidCallback onCancelDeferred;
  final ValueChanged<String?> onRegionError;
  final ValueChanged<String?> onRelayError;
  final ValueChanged<String?> onTokenError;

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    final AboutDiagnostics about = buildAboutDiagnostics(
      view: view,
      settings: settings,
      version: appVersion,
    );
    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: tokens.surfaceBase,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        title: Text(
          SettingsCopy.title,
          key: SettingsKeys.title,
          style: KeryxUxTypography.screenTitle.copyWith(
            color: tokens.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KeryxUxSpacing.pageMargin,
            KeryxUxSpacing.grid,
            KeryxUxSpacing.pageMargin,
            KeryxUxSpacing.pageMargin,
          ),
          children: <Widget>[
            if (pending != null) _DeferredBanner(onCancel: onCancelDeferred),
            SettingsSection(
              key: SettingsKeys.radioSection,
              title: SettingsCopy.radioSection,
              description: SettingsCopy.radioSectionDescription,
              children: <Widget>[
                SettingsStepperRow(
                  key: SettingsKeys.tot,
                  label: SettingsCopy.totLabel,
                  description: SettingsCopy.totDescription,
                  value: settings.totSeconds,
                  min: KeryxSettings.totSecondsMin,
                  max: KeryxSettings.totSecondsMax,
                  step: 5,
                  valueLabel: SettingsCopy.totValueLabel,
                  sessionAffecting: true,
                  onChanged: (int v) =>
                      onPropose(settings.copyWith(totSeconds: v)),
                ),
                SettingsToggleRow(
                  key: SettingsKeys.latch,
                  label: SettingsCopy.latchLabel,
                  description: SettingsCopy.latchDescription,
                  value: settings.latchMode,
                  onChanged: (bool v) =>
                      onPropose(settings.copyWith(latchMode: v)),
                ),
                SettingsToggleRow(
                  key: SettingsKeys.lockout,
                  label: SettingsCopy.lockoutLabel,
                  description: SettingsCopy.lockoutDescription,
                  value: settings.busyLockout,
                  sessionAffecting: true,
                  onChanged: (bool v) =>
                      onPropose(settings.copyWith(busyLockout: v)),
                ),
                SettingsTextRow(
                  key: SettingsKeys.region,
                  label: SettingsCopy.regionLabel,
                  description: SettingsCopy.regionDescription,
                  value: settings.region,
                  sessionAffecting: true,
                  error: regionError,
                  onSubmit: (String raw) {
                    if (raw.isEmpty) {
                      onRegionError(SettingsCopy.regionEmptyError);
                      return;
                    }
                    onRegionError(null);
                    onPropose(settings.copyWith(region: raw));
                  },
                ),
              ],
            ),
            SettingsSection(
              key: SettingsKeys.audioSection,
              title: SettingsCopy.audioSection,
              description: SettingsCopy.audioSectionDescription,
              children: <Widget>[
                SettingsStepperRow(
                  key: SettingsKeys.squelch,
                  label: SettingsCopy.squelchLabel,
                  description: SettingsCopy.squelchDescription,
                  value: settings.squelchLevel,
                  min: KeryxSettings.squelchLevelMin,
                  max: KeryxSettings.squelchLevelMax,
                  step: 1,
                  valueLabel: (int v) => '$v',
                  onChanged: (int v) =>
                      onPropose(settings.copyWith(squelchLevel: v)),
                ),
                SettingsPickerRow<RogerBeepVariant>(
                  key: SettingsKeys.roger,
                  label: SettingsCopy.rogerLabel,
                  description: SettingsCopy.rogerDescription,
                  value: settings.rogerBeep,
                  options: RogerBeepVariant.values,
                  optionLabel: (RogerBeepVariant v) =>
                      SettingsCopy.rogerOptionLabel(v.name),
                  onChanged: (RogerBeepVariant v) =>
                      onPropose(settings.copyWith(rogerBeep: v)),
                ),
                SettingsPickerRow<CharacterDspIntensity>(
                  key: SettingsKeys.dsp,
                  label: SettingsCopy.dspLabel,
                  description: SettingsCopy.dspDescription,
                  value: settings.characterDspIntensity,
                  options: CharacterDspIntensity.values,
                  optionLabel: (CharacterDspIntensity v) =>
                      SettingsCopy.dspOptionLabel(v.name),
                  onChanged: (CharacterDspIntensity v) =>
                      onPropose(settings.copyWith(characterDspIntensity: v)),
                ),
                const SettingsReadOnlyRow(
                  key: SettingsKeys.audioRouting,
                  label: SettingsCopy.audioRoutingLabel,
                  description: SettingsCopy.audioRoutingDescription,
                  value: SettingsCopy.audioRoutingValue,
                ),
              ],
            ),
            SettingsSection(
              key: SettingsKeys.connectivitySection,
              title: SettingsCopy.connectivitySection,
              description: SettingsCopy.connectivitySectionDescription,
              children: <Widget>[
                SettingsPickerRow<RadioMode>(
                  key: SettingsKeys.mode,
                  label: SettingsCopy.modeLabel,
                  description: SettingsCopy.modeDescription,
                  value: settings.mode,
                  options: RadioMode.values,
                  optionLabel: (RadioMode v) =>
                      SettingsCopy.modeOptionLabel(v.name),
                  sessionAffecting: true,
                  onChanged: (RadioMode v) =>
                      onPropose(settings.copyWith(mode: v)),
                ),
                SettingsReadOnlyRow(
                  key: SettingsKeys.effectiveRoute,
                  label: SettingsCopy.effectiveRouteLabel,
                  description: SettingsCopy.effectiveRouteDescription,
                  value: view.connection.routeLabel,
                ),
                SettingsToggleRow(
                  key: SettingsKeys.forceLocal,
                  label: SettingsCopy.forceLocalLabel,
                  description: SettingsCopy.forceLocalDescription,
                  value: settings.forceLocalOnly,
                  sessionAffecting: true,
                  onChanged: (bool v) =>
                      onPropose(settings.copyWith(forceLocalOnly: v)),
                ),
                if (settings.forceLocalOnly)
                  Padding(
                    key: SettingsKeys.forceLocalNote,
                    padding: const EdgeInsets.only(
                      bottom: KeryxUxSpacing.controlGap,
                    ),
                    child: Text(
                      SettingsCopy.forceLocalBlocksWan,
                      style: KeryxUxTypography.secondary.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                SettingsTextRow(
                  key: SettingsKeys.relayUrl,
                  label: SettingsCopy.relayUrlLabel,
                  description: SettingsCopy.relayUrlDescription,
                  value: settings.relayUrl,
                  sessionAffecting: true,
                  error: relayError,
                  onSubmit: (String raw) {
                    if (!isValidRelayUrl(raw)) {
                      onRelayError(SettingsCopy.relayUrlError);
                      return;
                    }
                    onRelayError(null);
                    onPropose(settings.copyWith(relayUrl: raw));
                  },
                ),
                SettingsTextRow(
                  key: SettingsKeys.tokenUrl,
                  label: SettingsCopy.tokenUrlLabel,
                  description: SettingsCopy.tokenUrlDescription,
                  value: settings.tokenServiceUrl,
                  sessionAffecting: true,
                  error: tokenError,
                  onSubmit: (String raw) {
                    if (!isValidTokenUrl(raw)) {
                      onTokenError(SettingsCopy.tokenUrlError);
                      return;
                    }
                    onTokenError(null);
                    onPropose(settings.copyWith(tokenServiceUrl: raw));
                  },
                ),
              ],
            ),
            SettingsSection(
              key: SettingsKeys.identitySection,
              title: SettingsCopy.identitySection,
              description: SettingsCopy.identitySectionDescription,
              children: <Widget>[
                SettingsTextRow(
                  key: SettingsKeys.callsign,
                  label: SettingsCopy.callsignLabel,
                  description: SettingsCopy.callsignDescription,
                  value: identity?.callsign.value ?? '',
                  error: callsignError,
                  onSubmit: onCallsign,
                ),
              ],
            ),
            SettingsSection(
              key: SettingsKeys.appearanceSection,
              title: SettingsCopy.appearanceSection,
              description: SettingsCopy.appearanceSectionDescription,
              children: <Widget>[
                SettingsPickerRow<AppearanceTheme>(
                  key: SettingsKeys.theme,
                  label: SettingsCopy.themeLabel,
                  description: SettingsCopy.themeDescription,
                  value: appearance.theme,
                  options: AppearanceTheme.values,
                  optionLabel: (AppearanceTheme v) =>
                      SettingsCopy.themeOptionLabel(v.name),
                  onChanged: onTheme,
                ),
                SettingsPickerRow<DimMode>(
                  key: SettingsKeys.dim,
                  label: SettingsCopy.dimLabel,
                  description: SettingsCopy.dimDescription,
                  value: settings.dimMode,
                  options: DimMode.values,
                  optionLabel: (DimMode v) =>
                      SettingsCopy.dimOptionLabel(v.name),
                  onChanged: (DimMode v) =>
                      onPropose(settings.copyWith(dimMode: v)),
                ),
              ],
            ),
            SettingsSection(
              key: SettingsKeys.aboutSection,
              title: SettingsCopy.aboutSection,
              description: SettingsCopy.aboutSectionDescription,
              children: <Widget>[
                SettingsReadOnlyRow(
                  key: SettingsKeys.version,
                  label: SettingsCopy.versionLabel,
                  description: SettingsCopy.aboutSectionDescription,
                  value: appVersion,
                ),
                SettingsReadOnlyRow(
                  key: SettingsKeys.diagnostics,
                  label: SettingsCopy.diagnosticsLabel,
                  description: SettingsCopy.aboutSectionDescription,
                  value: about.summaryLines.join('\n'),
                ),
                SettingsReadOnlyRow(
                  key: SettingsKeys.technicalDetails,
                  label: SettingsCopy.technicalDetailsLabel,
                  description: SettingsCopy.aboutSectionDescription,
                  value: about.detailLines.join('\n'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeferredBanner extends StatelessWidget {
  const _DeferredBanner({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: KeryxUxSpacing.cardSpacing),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.stateWarning),
        ),
        child: Padding(
          padding: const EdgeInsets.all(KeryxUxSpacing.controlGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.hourglass_top, color: tokens.stateWarning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      SettingsCopy.deferredBanner,
                      key: SettingsKeys.deferredBanner,
                      style: KeryxUxTypography.body.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: SettingsKeys.deferredCancel,
                  onPressed: onCancel,
                  child: const Text(SettingsCopy.deferredCancel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
