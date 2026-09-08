# `lib/features/stations`

TASK-053 — Design §2.4 Stations screen, built fresh (ADR-001 §7 item 2).

`StationsScreen` is a full-screen live roster over the **existing** host
station stream (`RadioHost.changes` → `RadioHostSnapshot.stations`, the same
feed TASK-043's `RosterScreen` consumed via `FaceScreen._stationsNotifier`).
No new data source is introduced. The widget tree is new.

Honesty (the substance of this task):

- Placeholder `StationInfo.signalQuality` is omitted from every row and
  marked **Quality unavailable** at screen level — never rendered as
  measured bars (Technical §1.1, UX-FR-045, VT-024).
- LINKED roster incompleteness is an explicit **Complete member list
  unavailable** statement on a dedicated LINKED-members field, never a
  verified zero (Design §2.4, UX-FR-046). Local station count is a separate
  field (`Local stations: N`).
- Unknown identity uses **Unknown station**; a peer ID is never shown as a
  verified human name (UX-FR-026).

Event QR **Scan** / **Export** are launch callbacks. The QR screens
themselves are TASK-056's. `lib/app_shell/**` is not edited here; a later
wiring pass (TASK-052) mounts this screen.
