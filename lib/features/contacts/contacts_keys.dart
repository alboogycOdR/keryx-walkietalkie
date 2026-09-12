import 'package:flutter/foundation.dart';

/// Widget keys for the Contacts tab (V2-VT-025).
abstract final class ContactsKeys {
  static const Key empty = Key('keryx-contacts-empty');
  static const Key list = Key('keryx-contacts-list');
  static const Key requestsSection = Key('keryx-contacts-requests');
  static const Key contactsSection = Key('keryx-contacts-section');
  static const Key addFab = Key('keryx-contacts-add');
  static const Key addSheet = Key('keryx-contacts-add-sheet');
  static const Key addScan = Key('keryx-contacts-add-scan');
  static const Key addShowMyCode = Key('keryx-contacts-add-show-my-code');
  static const Key addPasteField = Key('keryx-contacts-add-paste');
  static const Key addPasteSubmit = Key('keryx-contacts-add-paste-submit');
  static const Key addError = Key('keryx-contacts-add-error');
  static const Key scanScreen = Key('keryx-contacts-scan');
  static const Key scanView = Key('keryx-contacts-scan-view');
  static const Key incomingSheet = Key('keryx-contacts-incoming-sheet');
  static const Key incomingAccept = Key('keryx-contacts-incoming-accept');
  static const Key incomingDecline = Key('keryx-contacts-incoming-decline');
  static const Key incomingBlock = Key('keryx-contacts-incoming-block');
  static const Key actionsSheet = Key('keryx-contacts-actions-sheet');
  static const Key actionsAlert = Key('keryx-contacts-actions-alert');
  static const Key actionsRemove = Key('keryx-contacts-actions-remove');
  static const Key actionsBlock = Key('keryx-contacts-actions-block');

  static Key requestRow(String pk) => Key('keryx-contacts-request-$pk');
  static Key requestAccept(String pk) => Key('keryx-contacts-request-accept-$pk');
  static Key requestDecline(String pk) => Key('keryx-contacts-request-decline-$pk');
  static Key requestBlock(String pk) => Key('keryx-contacts-request-block-$pk');
  static Key contactRow(String pk) => Key('keryx-contacts-row-$pk');
  static Key presenceDot(String pk) => Key('keryx-contacts-presence-$pk');
}
