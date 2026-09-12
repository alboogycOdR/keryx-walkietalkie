import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/contacts_tab_screen.dart';
import 'package:keryx/core/presentation/talk_target.dart';
import 'package:keryx/features/contacts/contact_view_models.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart'
    show encodeUnpaddedBase64Url;

void main() {
  test(
    'talkTargetFromContact pins TalkTarget.id to ContactRowVm.pk '
    '(TASK-101: no extra peerPublicKey field — id already is the key)',
    () {
      final key = List<int>.generate(32, (i) => i + 11);
      final pk = encodeUnpaddedBase64Url(key);
      final contact = ContactRowVm(
        pk: pk,
        callsign: 'ADA-1',
        shortCode: '4R2M',
        visual: PresenceVisual.available,
      );

      final target = talkTargetFromContact(
        contact: contact,
        roomId: 'ABCDEFGHIJKLMNOP',
      );

      expect(target.kind, TalkTargetKind.contact);
      expect(target.id, same(contact.pk));
      expect(target.id, pk);
      expect(target.name, 'ADA-1');
      expect(target.roomId, 'ABCDEFGHIJKLMNOP');
      expect(target.memberPeerIds, [pk]);
    },
  );
}
