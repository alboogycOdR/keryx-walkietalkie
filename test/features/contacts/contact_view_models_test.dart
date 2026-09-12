import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/contacts/contact_models.dart';
import 'package:keryx/features/contacts/contact_view_models.dart';
import 'package:keryx/features/contacts/contacts_copy.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart';

Uint8List _key() => Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

void main() {
  group('presenceVisualFor', () {
    test('maps the four wire statuses and falls back to offline', () {
      expect(presenceVisualFor('available'), PresenceVisual.available);
      expect(presenceVisualFor('busy'), PresenceVisual.busy);
      expect(presenceVisualFor('dnd'), PresenceVisual.dnd);
      expect(presenceVisualFor('offline'), PresenceVisual.offline);
      expect(presenceVisualFor(null), PresenceVisual.offline);
      expect(presenceVisualFor('nope'), PresenceVisual.offline);
    });
  });

  group('presenceWord', () {
    test('every visual has a word so colour is never the only cue', () {
      expect(presenceWord(PresenceVisual.available), ContactsCopy.availableLabel);
      expect(presenceWord(PresenceVisual.busy), ContactsCopy.busyLabel);
      expect(presenceWord(PresenceVisual.dnd), ContactsCopy.dndLabel);
      expect(presenceWord(PresenceVisual.offline), ContactsCopy.offlineLabel);
    });
  });

  group('offlinePresenceLabel', () {
    test('Design §3 relative-time form', () {
      expect(offlinePresenceLabel(nowUnixSeconds: 100, lastSeenAt: null), 'Offline');
      expect(offlinePresenceLabel(nowUnixSeconds: 100, lastSeenAt: 90), 'Offline');
      expect(offlinePresenceLabel(nowUnixSeconds: 1000, lastSeenAt: 1000 - 120), 'Offline · 2 min ago');
      expect(offlinePresenceLabel(nowUnixSeconds: 10_000, lastSeenAt: 10_000 - 7200), 'Offline · 2 h ago');
      expect(offlinePresenceLabel(nowUnixSeconds: 200_000, lastSeenAt: 200_000 - 86400), 'Offline · 1 d ago');
    });
  });

  group('parseContactId', () {
    test('accepts a well-formed QR payload', () {
      final link = KeryxIdLink(callsign: 'BEN', publicKey: _key());
      final parsed = parseContactId(link.qrPayload);
      expect(parsed, isA<ContactIdParsed>());
      expect((parsed as ContactIdParsed).link.callsign, 'BEN');
    });

    test('refuses a tampered key locally (V2-VT-003)', () {
      final parsed = parseContactId('keryx://id?v=1&c=BEN&k=not-valid-key');
      expect(parsed, isA<ContactIdInvalid>());
      expect((parsed as ContactIdInvalid).reason, ContactsCopy.tamperedId);
    });

    test('refuses a wrong-length key locally', () {
      final parsed = parseContactId('keryx://id?v=1&c=BEN&k=YWJjZA');
      expect(parsed, isA<ContactIdInvalid>());
    });
  });

  group('buildContactsViewState', () {
    test('incoming requests sit above alphabetical contacts; outgoing wait', () {
      final state = buildContactsViewState(
        pending: const [
          PendingContactRequest(
            pk: 'in1',
            callsign: 'Zed',
            direction: ContactRequestDirection.incoming,
            createdAt: 2,
            expiresAt: 99,
          ),
          PendingContactRequest(
            pk: 'out1',
            callsign: 'Waiter',
            direction: ContactRequestDirection.outgoing,
            createdAt: 1,
            expiresAt: 99,
          ),
        ],
        contacts: const [
          Contact(pk: 'c2', callsign: 'Mira', status: 'busy'),
          Contact(pk: 'c1', callsign: 'Ada', status: 'available'),
        ],
        talkingPks: {'c2'},
        nearbyPks: {'c1'},
        alertDisabledPks: {'c1'},
        nowUnixSeconds: 10,
      );

      expect(state.requests.single.callsign, 'Zed');
      expect(state.contacts.map((c) => c.callsign).toList(), ['Ada', 'Mira', 'Waiter']);
      expect(state.contacts[0].isNearby, isTrue);
      expect(state.contacts[1].isTalking, isTrue);
      expect(state.contacts[2].isOutgoingPending, isTrue);
      expect(state.isAlertDisabled('c1'), isTrue);
    });
  });

  group('alertIsOnCooldown', () {
    test('10-minute window (V2-FR-050)', () {
      expect(
        alertIsOnCooldown(lastAlertAtUnixSeconds: 0, nowUnixSeconds: 599),
        isTrue,
      );
      expect(
        alertIsOnCooldown(lastAlertAtUnixSeconds: 0, nowUnixSeconds: 600),
        isFalse,
      );
    });
  });

  test('user-facing copy never names channel/tune/station/LOCAL/LINKED/AUTO', () {
    const forbidden = ['channel', 'tune', 'station', 'LOCAL', 'LINKED', 'AUTO'];
    const corpus = [
      ContactsCopy.emptyStateTitle,
      ContactsCopy.emptyStateBody,
      ContactsCopy.addContactAction,
      ContactsCopy.scanACode,
      ContactsCopy.showMyCode,
      ContactsCopy.pasteAnId,
      ContactsCopy.requestsSection,
      ContactsCopy.contactsSection,
      ContactsCopy.acceptAction,
      ContactsCopy.declineAction,
      ContactsCopy.blockAction,
      ContactsCopy.blockConfirmAction,
      ContactsCopy.alertAction,
      ContactsCopy.removeAction,
      ContactsCopy.invalidId,
      ContactsCopy.tamperedId,
      ContactsCopy.alertCooldown,
    ];
    for (final text in corpus) {
      for (final word in forbidden) {
        expect(text.contains(word), isFalse, reason: '"$text" contains $word');
      }
    }
  });
}
