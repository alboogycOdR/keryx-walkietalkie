# `lib/features/stations`

TASK-053 — Design §2.4 Stations screen, built fresh (ADR-001 §7 item 2).

`StationsScreen` owns a `RadioHost.changes` subscription (live join/depart
without a parent rebuild) and projects `RadioViewState`. `StationsView`
renders that projection. The data source is the **existing** host station
stream (`RadioHostSnapshot.stations`, the same feed TASK-043's
`RosterScreen` consumed). No new data source is introduced.

Honesty (the substance of this task):

- Count UI switches on sealed `RosterCount`: `KnownRosterCount` →
  `Local stations: N` from `.count` (not `stations.length`);
  `UnavailableRosterCount` → route-labelled "Complete member list
  unavailable" (label follows `view.connection.effectiveRoute`, so AUTO
  is not called LINKED). Design §5 empty copy and a verified zero appear
  only on a known empty roster.
- Quality switches on sealed `SignalQuality`: `Unavailable` → "Quality
  unavailable"; `Measured` → `Quality: S<n>` text. Never bars. Rows do
  not read `StationInfo.signalQuality`.
- A host-stream error clears the snapshot and shows "Station list
  unavailable" rather than a stale list or a verified-empty room.
- Unknown identity uses **Unknown station**; a peer ID is never shown as a
  verified human name (UX-FR-026).

Event QR **Scan** / **Export** are launch callbacks. The QR screens
themselves are TASK-056's. `lib/app_shell/**` is not edited here; TASK-052
mounts this screen.
