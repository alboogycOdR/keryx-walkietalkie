# Sound projection

`SfxProjection` is the host-agnostic §8.2 projection from reducer and floor
effects to `SfxEngine`. It has no Riverpod or widget dependency.

## Pinned decisions

| Decision | Rationale |
| --- | --- |
| `GrantTone` → `keyClick` | TS §7.1 has no grant-tone manifest entry (the TASK-010 finding). `keyClick` is an existing cosmetic, non-ducking mechanical acknowledgement. No frozen asset or `SfxId` is invented here. |
| `customPack` roger → `moto` | FR-062 exposes a custom-pack preference, but the Phase-1 manifest has no custom-pack asset. The existing `roger_moto` entry is the compatible temporary audible variant. |
