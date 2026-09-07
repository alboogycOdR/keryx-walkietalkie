/// TASK-048 — Technical §10: "Keep a temporary legacy route or
/// compatibility harness reachable during the migration… this is not a
/// requirement to ship two interfaces."
///
/// The old single-screen face (`lib/features/face/face_screen.dart`) stays
/// reachable through this named route while Wave 4 fills in the real
/// Channels/Talk/Stations/Settings destinations, but only in debug builds
/// and only by name — no destination, button, menu item or deep link in
/// `lib/app_shell/**` ever navigates to it, so it is not present in any
/// normal user navigation path. TASK-061 deletes both this constant's only
/// registration (in `lib/app.dart`) and the legacy face itself.
const String legacyFaceRouteName = '/legacy-face';
