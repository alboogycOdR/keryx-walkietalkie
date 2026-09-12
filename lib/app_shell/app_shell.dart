/// TASK-048 — mobile app shell: persistent host mounting, tab navigation,
/// route registration. Owns `lib/app.dart`/`lib/main.dart` (Technical §9's
/// "A separate integration task owns shared route registration, app.dart,
/// shared providers and final wiring").
///
/// TASK-093 (v2): the Channels/Stations tabs are gone — replaced by
/// Contacts/Groups (`contacts_tab_screen.dart`/`groups_tab_screen.dart`) —
/// and the shell gains the onboarding gate (`onboarding_gate.dart`) and the
/// directory/contacts/groups composition root (`directory_providers.dart`).
library;

export 'contacts_tab_screen.dart';
export 'directory_providers.dart';
export 'groups_tab_screen.dart';
export 'mobile_app_shell.dart';
export 'onboarding_gate.dart';
export 'radio_host_provider.dart';
export 'shell_keys.dart';
export 'shell_routes.dart';
export 'talk_screen.dart';
