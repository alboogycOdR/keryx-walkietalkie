# TASK-093 — v2 shell and settings — Talk/Contacts/Groups tabs, My code in overflow, onboarding and restore routes, v2 settings sections

## Brief

Rewire the shell for v2: tabs Talk (mic) / Contacts (person) / Groups (groups); ⋮ gains My code above Radio controls and Settings; first launch routes to onboarding before the shell; a 'Restore' entry on the callsign screen. Target selection from Contacts/Groups switches to Talk via `switchTarget`. Settings: replace the Connectivity section with relay address + prefer-direct; add Identity (callsign, Show recovery phrase behind device lock, Restore) and Messages (retention, marked 'used from v2.1'); remove the mode/region rows. Keep the TASK-077 back-button rules and add the new tabs to the real-back tests. Delete the debug legacy-face route registration from `app.dart`. Do not delete feature directories (TASK-094).

## Spec pointers

- specs/KERYX_v2.0_Design_v1.0.md §1, §2.7; Technical §6.4 (host start), §8 (v1 install migration); PRD V2-FR-060/061; Verification V2-VT-027 (shell half), V2-VT-029, V2-VT-030 (shell frame goldens)
- Owned_Paths: lib/app_shell/**, lib/app.dart, lib/main.dart, lib/features/settings/**, test/app_shell/**, test/features/settings/**, test/regression/real_composition_test.dart, test/regression/goldens/goldens/shell_frame_*.png, test/regression/goldens/goldens/settings_*.png, test/regression/goldens/shell_frame_golden_test.dart, test/regression/goldens/settings_golden_test.dart, dossiers/TASK-093.md
- Depends_On: TASK-089, TASK-090, TASK-091, TASK-092

## Work Log
