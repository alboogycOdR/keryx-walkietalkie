import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

void main() {
  group('RadioViewState.project — independent composite fields', () {
    test(
      'emergency during TX shows both phase==tx and emergency==true — '
      'neither field replaces the other (Technical §5.2; Design §4)',
      () {
        final view = RadioViewState.project(
          radioState: const RadioState(
            phase: RadioPhase.tx,
            isEmergency: true,
          ),
          hostSnapshot: const RadioHostSnapshot(),
          settings: const KeryxSettings(),
        );

        expect(view.phase, RadioPhase.tx);
        expect(view.emergency, isTrue);
        expect(view.phaseCue.label, 'Transmitting');
        expect(view.activeOverlayCues, contains(OverlayCues.emergency));
      },
    );

    test(
      'a denied flash does not override a currently granted TX '
      '— both are readable simultaneously',
      () {
        final view = RadioViewState.project(
          radioState: const RadioState(
            phase: RadioPhase.tx,
            isTransmitDenied: true,
          ),
          hostSnapshot: const RadioHostSnapshot(),
          settings: const KeryxSettings(),
        );

        expect(view.phase, RadioPhase.tx);
        expect(view.phaseCue.label, 'Transmitting');
        expect(view.deniedFlash, isTrue);
        expect(view.activeOverlayCues, contains(OverlayCues.deniedFlash));
      },
    );

    test(
      'a global connection error (linkDegraded) does not conceal an '
      'active floor state field — phase and connection are independent',
      () {
        // linkDegraded is itself a phase (the reducer only reaches it from
        // a non-off phase), so this asserts the connection fields are
        // still populated distinctly rather than collapsed into the phase
        // alone.
        final view = RadioViewState.project(
          radioState: const RadioState(
            phase: RadioPhase.linkDegraded,
            isNoLink: true,
            mode: RadioMode.linked,
          ),
          hostSnapshot: const RadioHostSnapshot(),
          settings: const KeryxSettings(mode: RadioMode.auto),
        );

        expect(view.phase, RadioPhase.linkDegraded);
        expect(view.connection.degraded, isTrue);
        expect(view.connection.configuredMode, RadioMode.auto);
        expect(view.connection.effectiveRoute, RadioMode.linked);
      },
    );

    test(
      'permission denied and service fault project independently of phase',
      () {
        final view = RadioViewState.project(
          radioState: const RadioState(phase: RadioPhase.boot),
          hostSnapshot: const RadioHostSnapshot(
            micPermissionDenied: true,
            serviceFaultMessage: 'SVC FAULT',
          ),
          settings: const KeryxSettings(),
        );

        expect(view.phase, RadioPhase.boot);
        expect(view.permissionDenied, isTrue);
        expect(view.serviceFaultMessage, 'SVC FAULT');
        expect(
          view.activeOverlayCues,
          containsAll([
            OverlayCues.permissionDenied,
            OverlayCues.serviceFault,
          ]),
        );
      },
    );

    test('latched is projected independently and does not alter phase', () {
      final view = RadioViewState.project(
        radioState: const RadioState(phase: RadioPhase.tx),
        hostSnapshot: const RadioHostSnapshot(),
        settings: const KeryxSettings(),
        latched: true,
      );

      expect(view.phase, RadioPhase.tx);
      expect(view.latched, isTrue);
      expect(view.activeOverlayCues, contains(OverlayCues.latched));
    });

    test(
      'TOT-warning during TX shows both phase==tx and totWarning==true — '
      'neither field replaces the other (FR-023; Design §4 independent fields)',
      () {
        final view = RadioViewState.project(
          radioState: const RadioState(
            phase: RadioPhase.tx,
            isTotWarning: true,
          ),
          hostSnapshot: const RadioHostSnapshot(),
          settings: const KeryxSettings(),
        );

        expect(view.phase, RadioPhase.tx);
        expect(view.totWarning, isTrue);
        expect(view.emergency, isFalse);
        expect(view.latched, isFalse);
        expect(view.phaseCue.label, 'Transmitting');
        expect(view.activeOverlayCues, contains(OverlayCues.totWarning));
        expect(OverlayCues.totWarning.label, isNotEmpty);
        expect(OverlayCues.totWarning.iconId, isNotEmpty);
      },
    );

    test(
      'totWarning is sourced from RadioState.isTotWarning, never '
      'fabricated from phase==tx alone',
      () {
        final view = RadioViewState.project(
          radioState: const RadioState(
            phase: RadioPhase.tx,
            isTotWarning: false,
          ),
          hostSnapshot: const RadioHostSnapshot(),
          settings: const KeryxSettings(),
        );

        expect(view.phase, RadioPhase.tx);
        expect(view.totWarning, isFalse);
        expect(view.activeOverlayCues, isNot(contains(OverlayCues.totWarning)));
      },
    );
  });

  group('UX-FR-002 / Technical §7 — configured mode vs effective route', () {
    test('configured AUTO does not imply the effective route is LINKED', () {
      final view = RadioViewState.project(
        radioState: const RadioState(
          phase: RadioPhase.idle,
          // Production code only ever dispatches a resolved local/linked
          // value into this field (see
          // `RadioSessionController._resolveEffectiveMode`) — never the
          // raw AUTO preference. Spelled out explicitly here so the test
          // does not rely on `RadioState`'s own default.
          mode: RadioMode.local,
        ),
        hostSnapshot: const RadioHostSnapshot(),
        settings: const KeryxSettings(mode: RadioMode.auto),
      );

      // Asserts the two fields are carried and compared independently —
      // a configured AUTO preference must not be read back as "effective
      // route is LINKED" (or any other specific route) just because it
      // was the configured value.
      expect(view.connection.configuredMode, RadioMode.auto);
      expect(view.connection.effectiveRoute, RadioMode.local);
      expect(view.connection.effectiveRoute, isNot(RadioMode.auto));
    });

    test('configured and effective can legitimately differ', () {
      final view = RadioViewState.project(
        radioState: const RadioState(
          phase: RadioPhase.idle,
          mode: RadioMode.local,
        ),
        hostSnapshot: const RadioHostSnapshot(),
        settings: const KeryxSettings(mode: RadioMode.linked),
      );

      expect(view.connection.configuredMode, RadioMode.linked);
      expect(view.connection.effectiveRoute, RadioMode.local);
    });
  });

  group('Design §4 — 13 catalogue rows', () {
    test('every RadioPhase carries a distinct cue', () {
      final cues = RadioPhase.values.map((p) => p.cue).toList();
      final labels = cues.map((c) => c.label).toSet();
      final iconIds = cues.map((c) => c.iconId).toSet();

      expect(RadioPhase.values.length, 8);
      expect(labels.length, 8, reason: 'every phase label must be distinct');
      expect(iconIds.length, 8, reason: 'every phase icon must be distinct');
    });

    test('the 5 overlay rows are each distinct from each other and from '
        'every phase row — 13 catalogue rows total, all distinct', () {
      final overlayCues = [
        OverlayCues.deniedFlash,
        OverlayCues.latched,
        OverlayCues.emergency,
        OverlayCues.permissionDenied,
        OverlayCues.serviceFault,
      ];
      final phaseCues = RadioPhase.values.map((p) => p.cue).toList();
      final allLabels = <String>{
        ...overlayCues.map((c) => c.label),
        ...phaseCues.map((c) => c.label),
      };

      expect(overlayCues.toSet().length, 5);
      expect(allLabels.length, 13);
    });

    test(
      'TOT-warning cue is text+icon and distinct from every Design §4 '
      'catalogue label (FR-023 overlay is not a 14th Design §4 row)',
      () {
        expect(OverlayCues.totWarning.label, 'Transmission ending soon');
        expect(OverlayCues.totWarning.iconId, 'timer');
        expect(OverlayCues.totWarning.label, isNotEmpty);
        expect(OverlayCues.totWarning.iconId, isNotEmpty);

        final designLabels = <String>{
          ...RadioPhase.values.map((p) => p.cue.label),
          OverlayCues.deniedFlash.label,
          OverlayCues.latched.label,
          OverlayCues.emergency.label,
          OverlayCues.permissionDenied.label,
          OverlayCues.serviceFault.label,
        };
        expect(designLabels.length, 13);
        expect(designLabels, isNot(contains(OverlayCues.totWarning.label)));
        expect(
          RadioPhase.values.map((p) => p.cue.iconId),
          isNot(contains(OverlayCues.totWarning.iconId)),
        );
      },
    );

    test(
      'a pending request never projects as granted TX — grant appears '
      'only after authoritative engine grant (VT-010/VT-011)',
      () {
        final view = RadioViewState.project(
          radioState: const RadioState(phase: RadioPhase.txRequest),
          hostSnapshot: const RadioHostSnapshot(),
          settings: const KeryxSettings(),
        );

        expect(view.phase, isNot(RadioPhase.tx));
        expect(view.phaseCue.label, 'Requesting channel');
        expect(view.phaseCue.label, isNot('Transmitting'));
      },
    );

    test('receivingLabel resolves a known callsign, never a raw peer id', () {
      final view = RadioViewState.project(
        radioState: const RadioState(
          phase: RadioPhase.rxActive,
          activeSpeaker: 'peer-1',
        ),
        hostSnapshot: const RadioHostSnapshot(
          stations: [StationInfo(peerId: 'peer-1', callsign: 'ALPHA')],
        ),
        settings: const KeryxSettings(),
      );

      expect(view.receivingLabel, 'ALPHA speaking');
      expect(view.receivingLabel, isNot(contains('peer-1')));
    });

    test(
      'receivingLabel falls back to a neutral phrase when the speaker is '
      'unresolved — never the raw peer id (UX-FR-026)',
      () {
        final view = RadioViewState.project(
          radioState: const RadioState(
            phase: RadioPhase.rxActive,
            activeSpeaker: 'peer-unknown',
          ),
          hostSnapshot: const RadioHostSnapshot(),
          settings: const KeryxSettings(),
        );

        expect(view.receivingLabel, 'Someone is speaking');
        expect(view.receivingLabel, isNot(contains('peer-unknown')));
      },
    );

    test('receivingLabel is null when nobody holds the floor', () {
      final view = RadioViewState.project(
        radioState: const RadioState(phase: RadioPhase.idle),
        hostSnapshot: const RadioHostSnapshot(),
        settings: const KeryxSettings(),
      );

      expect(view.receivingLabel, isNull);
    });
  });

  group('Telemetry honesty (Technical §1.1/§5.3; UX-FR-045/046/027; VT-024)', () {
    test(
      'placeholder StationInfo.signalQuality never projects as measured '
      'full strength',
      () {
        final view = RadioViewState.project(
          radioState: const RadioState(phase: RadioPhase.idle),
          hostSnapshot: const RadioHostSnapshot(
            stations: [
              StationInfo(
                peerId: 'peer-1',
                callsign: 'ALPHA',
                signalQuality: StationInfo.placeholderSignalQuality,
              ),
            ],
          ),
          settings: const KeryxSettings(),
        );

        expect(view.signalQuality, SignalQuality.unavailable);
        expect(view.signalQuality, isNot(isA<MeasuredSignalQuality>()));
      },
    );

    test(
      'an unknown/incomplete LINKED roster projects as unavailable, never '
      'as a verified zero count',
      () {
        final view = RadioViewState.project(
          radioState: const RadioState(
            phase: RadioPhase.idle,
            mode: RadioMode.linked,
          ),
          hostSnapshot: const RadioHostSnapshot(stations: []),
          settings: const KeryxSettings(mode: RadioMode.linked),
        );

        expect(view.rosterCount, isA<UnavailableRosterCount>());
        expect(view.rosterCount, isNot(const KnownRosterCount(0)));
      },
    );

    test('a verified LOCAL roster count is a known, not unavailable, count', () {
      final view = RadioViewState.project(
        radioState: const RadioState(
          phase: RadioPhase.idle,
          mode: RadioMode.local,
        ),
        hostSnapshot: const RadioHostSnapshot(
          stations: [
            StationInfo(peerId: 'peer-1', callsign: 'ALPHA'),
            StationInfo(peerId: 'peer-2', callsign: 'BRAVO'),
          ],
        ),
        settings: const KeryxSettings(mode: RadioMode.local),
      );

      expect(view.rosterCount, const KnownRosterCount(2));
    });

    test(
      'the meter/animation level is typed decorative-only, never a '
      'measured value, regardless of phase',
      () {
        for (final phase in RadioPhase.values) {
          final view = RadioViewState.project(
            radioState: RadioState(phase: phase),
            hostSnapshot: const RadioHostSnapshot(),
            settings: const KeryxSettings(),
          );
          expect(
            view.meterLevel,
            isA<DecorativeMeterLevel>(),
            reason: 'phase $phase must not yield a measured meter level',
          );
          expect(view.meterLevel, isNot(isA<MeasuredMeterLevel>()));
        }
      },
    );
  });

  group('Technical §5.1 — projection purity', () {
    test('project() never mutates its RadioState/RadioHostSnapshot inputs', () {
      const radioState = RadioState(phase: RadioPhase.idle);
      const hostSnapshot = RadioHostSnapshot(
        stations: [StationInfo(peerId: 'peer-1', callsign: 'ALPHA')],
      );

      RadioViewState.project(
        radioState: radioState,
        hostSnapshot: hostSnapshot,
        settings: const KeryxSettings(),
      );

      // Inputs are immutable value types; re-asserting equality to the
      // pre-call literal proves nothing was replaced/rebuilt via a
      // hidden side channel (there is no setter to call in the first
      // place — this is a belt-and-braces characterization, not a
      // meaningful mutation probe on its own).
      expect(radioState.phase, RadioPhase.idle);
      expect(hostSnapshot.stations.single.callsign, 'ALPHA');
    });
  });

  group(
    'Technical §1.1 — RadioState equality-gap assessment '
    '(written finding: see dossiers/TASK-046.md)',
    () {
      test(
        'every RadioState field currently participates in == — flipping '
        'any single field alone makes the instances unequal',
        () {
          const base = RadioState(
            phase: RadioPhase.idle,
            mode: RadioMode.local,
            channel: 5,
            privacyCode: 3,
            isNoLink: false,
            isEmergency: false,
            isPrivate: false,
            isReplay: false,
            isMonitorOpen: false,
            isScanning: false,
            isVoxArmed: false,
            isTotWarning: false,
            isTransmitDenied: false,
            stationCount: 1,
            activeSpeaker: 'peer-1',
            arbiterId: 'peer-1',
            signalQuality: 5,
          );

          final variants = <RadioState>[
            base.copyWith(phase: RadioPhase.tx),
            base.copyWith(mode: RadioMode.linked),
            base.copyWith(channel: 6),
            base.copyWith(privacyCode: 4),
            base.copyWith(isNoLink: true),
            base.copyWith(isEmergency: true),
            base.copyWith(isPrivate: true),
            base.copyWith(isReplay: true),
            base.copyWith(isMonitorOpen: true),
            base.copyWith(isScanning: true),
            base.copyWith(isVoxArmed: true),
            base.copyWith(isTotWarning: true),
            base.copyWith(isTransmitDenied: true),
            base.copyWith(stationCount: 2),
            base.copyWith(activeSpeaker: 'peer-2'),
            base.copyWith(arbiterId: 'peer-2'),
            base.copyWith(signalQuality: 6),
          ];

          for (final variant in variants) {
            expect(
              variant == base,
              isFalse,
              reason:
                  '$variant unexpectedly compared equal to $base — this '
                  'would reopen the Technical §1.1 equality gap the '
                  'dossier records as currently closed',
            );
            expect(variant.hashCode == base.hashCode, isFalse);
          }
        },
      );
    },
  );
}
