/// Old → new mapping of every control the legacy back panel exposed.
///
/// This list is the UX-FR-061 inventory. A test asserts it covers every
/// legacy field; the dossier copies the same table.
class SettingsInventoryEntry {
  const SettingsInventoryEntry({
    required this.legacyLabel,
    required this.legacySection,
    required this.newLabel,
    required this.newSection,
    required this.field,
    required this.sessionAffecting,
  });

  final String legacyLabel;
  final String legacySection;
  final String newLabel;
  final String newSection;

  /// `KeryxSettings` field name, or `callsign` / `theme` / `effectiveRoute`
  /// / `audioRouting` / `version` for successor-only rows.
  final String field;
  final bool sessionAffecting;
}

/// Every legacy back-panel control, plus the successor-only rows Design
/// §2.6 adds (effective route, callsign, theme, audio routing, about).
const List<SettingsInventoryEntry> settingsInventory =
    <SettingsInventoryEntry>[
      SettingsInventoryEntry(
        legacyLabel: 'SQUELCH',
        legacySection: 'AUDIO',
        newLabel: 'Squelch',
        newSection: 'Audio',
        field: 'squelchLevel',
        sessionAffecting: false,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'ROGER BEEP',
        legacySection: 'AUDIO',
        newLabel: 'Roger beep',
        newSection: 'Audio',
        field: 'rogerBeep',
        sessionAffecting: false,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'TIME-OUT TIMER',
        legacySection: 'TRANSMIT',
        newLabel: 'Time-out timer',
        newSection: 'Radio',
        field: 'totSeconds',
        sessionAffecting: true,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'LATCH',
        legacySection: 'TRANSMIT',
        newLabel: 'Latch',
        newSection: 'Radio',
        field: 'latchMode',
        sessionAffecting: false,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'BUSY LOCKOUT',
        legacySection: 'TRANSMIT',
        newLabel: 'Busy lockout',
        newSection: 'Radio',
        field: 'busyLockout',
        sessionAffecting: true,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'CHARACTER DSP',
        legacySection: 'CHARACTER',
        newLabel: 'Character DSP',
        newSection: 'Audio',
        field: 'characterDspIntensity',
        sessionAffecting: false,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'DIM',
        legacySection: 'CHARACTER',
        newLabel: 'Dim',
        newSection: 'Appearance',
        field: 'dimMode',
        sessionAffecting: false,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'RADIO MODE',
        legacySection: 'NETWORK',
        newLabel: 'Radio mode',
        newSection: 'Connectivity',
        field: 'mode',
        sessionAffecting: true,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'LOCAL ONLY',
        legacySection: 'NETWORK',
        newLabel: 'Local only',
        newSection: 'Connectivity',
        field: 'forceLocalOnly',
        sessionAffecting: true,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'REGION',
        legacySection: 'NETWORK',
        newLabel: 'Region',
        newSection: 'Radio',
        field: 'region',
        sessionAffecting: true,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'RELAY URL',
        legacySection: 'NETWORK',
        newLabel: 'Relay URL',
        newSection: 'Connectivity',
        field: 'relayUrl',
        sessionAffecting: true,
      ),
      SettingsInventoryEntry(
        legacyLabel: 'TOKEN URL',
        legacySection: 'NETWORK',
        newLabel: 'Token URL',
        newSection: 'Connectivity',
        field: 'tokenServiceUrl',
        sessionAffecting: true,
      ),
      SettingsInventoryEntry(
        legacyLabel: '—',
        legacySection: '—',
        newLabel: 'Effective route',
        newSection: 'Connectivity',
        field: 'effectiveRoute',
        sessionAffecting: false,
      ),
      SettingsInventoryEntry(
        legacyLabel: '—',
        legacySection: '—',
        newLabel: 'Callsign',
        newSection: 'Identity',
        field: 'callsign',
        sessionAffecting: false,
      ),
      SettingsInventoryEntry(
        legacyLabel: '—',
        legacySection: '—',
        newLabel: 'Theme',
        newSection: 'Appearance',
        field: 'theme',
        sessionAffecting: false,
      ),
      SettingsInventoryEntry(
        legacyLabel: '—',
        legacySection: '—',
        newLabel: 'Audio routing',
        newSection: 'Audio',
        field: 'audioRouting',
        sessionAffecting: false,
      ),
      SettingsInventoryEntry(
        legacyLabel: '—',
        legacySection: '—',
        newLabel: 'Version',
        newSection: 'About',
        field: 'version',
        sessionAffecting: false,
      ),
    ];

/// Legacy back-panel field names that must survive in the successor.
const Set<String> legacySettingsFields = <String>{
  'squelchLevel',
  'rogerBeep',
  'totSeconds',
  'latchMode',
  'busyLockout',
  'characterDspIntensity',
  'dimMode',
  'mode',
  'forceLocalOnly',
  'region',
  'relayUrl',
  'tokenServiceUrl',
};
