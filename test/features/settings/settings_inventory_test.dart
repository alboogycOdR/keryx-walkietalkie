import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/settings/settings.dart';

void main() {
  test('inventory covers every legacy back-panel field', () {
    final Set<String> mapped = settingsInventory
        .map((SettingsInventoryEntry e) => e.field)
        .toSet();
    expect(mapped, containsAll(legacySettingsFields));
    for (final String field in legacySettingsFields) {
      expect(
        settingsInventory.where((SettingsInventoryEntry e) => e.field == field),
        hasLength(1),
      );
    }
  });

  test('six Design §2.6 sections are represented', () {
    final Set<String> sections = settingsInventory
        .map((SettingsInventoryEntry e) => e.newSection)
        .toSet();
    expect(
      sections,
      containsAll(<String>[
        'Radio',
        'Audio',
        'Connectivity',
        'Identity',
        'Appearance',
        'About',
      ]),
    );
  });

  test('session-affecting flags match the host field set', () {
    for (final SettingsInventoryEntry entry in settingsInventory) {
      if (legacySettingsFields.contains(entry.field)) {
        expect(
          entry.sessionAffecting,
          sessionAffectingFieldNames.contains(entry.field),
          reason: entry.field,
        );
      }
    }
  });
}
