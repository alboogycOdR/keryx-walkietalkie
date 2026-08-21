# TASK-036 — Settings relay configuration

## Implementation decisions

- The back panel uses `PanelPickerRow` for the functional LOCAL / AUTO /
  LINKED selector. FR-040's face-slider treatment remains face territory.
- `relay/Caddyfile` reserves `/token`; when TOKEN URL is blank, the model
  derives `https://<relay-host>/token` from a configured `wss://` relay.
- Invalid endpoint values are normalized to the compile-time default (or an
  empty value) rather than throwing during a settings save.

## Work log

- 2026-08-21: Added persisted relay/token URLs, build-time defaults, URL
  normalization, the network controls, and regression/widget tests.
