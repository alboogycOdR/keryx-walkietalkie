---
plan_version: 1.2
last_updated: 2026-08-18T09:55:09Z
overall_status: in_progress
orchestrator_notes: "Plan v1.0 — first real decomposition from 3 specs (KERYX_Product_Technical_Spec_v1.1.md, KERYX_UI_Design_Specification_v1.0.md, keryx-face-prototype.html). 26 tasks. Territory rules: pubspec.yaml/analysis_options.yaml/.github/**/.gitignore/README.md are FROZEN after TASK-001. android/** is a serialized chain (001 → 019 → 026). lib/core/audio/** is a serialized chain (010 → 011). Dossiers exist for every task in dossiers/TASK-NNN.md. S5/S5B are defined but INACTIVE for this project — never assign them. REVIEW (2026-08-18T09:55Z): TASK-002 (GB, relay/**) REVIEWED AND APPROVED first-pass — merged to master as e18e820 (`git merge --no-ff task/TASK-002-gb`), Status: done, branch task/TASK-002-gb deleted. GB's worktree (wt-grok-) was left in place, detached at master, so the next dispatch can reuse it. Verified independently, not from GB's summary: territory clean (13 files, all relay/**), c8b9872 preflight present, GB's three PLAN.md commits touched only its own block, 6/6 acceptance criteria checked against spec text quoted by a subagent, and the test suite re-run at GB's HEAD (16/16, exit 0, with a REAL `docker compose config` — Docker 29.6.1 is present and the test has no skip path). Two non-blocking follow-ups recorded in TASK-002 Review_Findings (coturn 5349 TLS listener has no cert=/pkey= while livekit.yaml advertises it; LIVEKIT_API_SECRET has two injection paths vs. a one-path rotation procedure) — fold these into a later relay task, do not reopen TASK-002. TASK-002 UNLOCKED NOTHING: no task in this plan lists TASK-002 in Depends_On (verified across all 26 Depends_On lines); TASK-024 depends on TASK-003+TASK-007, TASK-025 on TASK-007. SPEC DRIFT worth a human decision (found during spec verification, not GB's fault): the spec's §3 has no D8 section although its front matter cites "naming decision D8", and its closing line reads "End of specification — KERYX v1.0" while the header declares v1.1. Also note TASK-002's acceptance criteria 3 (.env.example / no secrets in-repo) and 6 (`docker compose config` validates) have NO backing spec text — they are ORCH-authored engineering criteria, which is fine, but the CLAUDE.md planning standard says each criterion maps to a spec sentence; label such criteria explicitly in future decompositions. TASK-001 (CX, Flutter scaffold) is in_progress after a re-dispatch — see incident below. GB is idle after TASK-002, next eligible is TASK-003 (token-svc/**, no deps) — not yet re-dispatched, needs a fresh GB launch. TWO INCIDENTS this wave, both resolved: (1) scripts/dispatch.ps1 and scripts/worktree.ps1 hardcoded branch name 'main' instead of reading autopilot.json git.base_branch ('master' here) — fixed commit 196218e. (2) scripts/plan_commit.ps1/.sh resolved repo root from the invoked script's own file path, so running the instructed relative path from inside a worktree resolved to the WORKTREE root instead of the main checkout, failing the integration-branch check — CX hit this on its first TASK-001 attempt, self-blocked and reverted cleanly (~52k tokens spent), re-dispatched after the fix (commit b8171fe) and succeeded. SEPARATELY, a genuine PLAN.md lost-update race occurred: GB wrote its TASK-002 needs_review update to the working tree, then CX's claim-TASK-001 write (from a stale in-memory read) clobbered it before GB could commit — same class of bug as the pack's documented 2026-08-02 TASK-011 incident, and plan_guard.py did not catch it because the clobbered content matched HEAD at commit time (nothing to flag from git's perspective). GB self-detected via its own briefing discipline ('PLAN.md went stale under me'), discarded its stale copy, re-read master, and re-applied only its own block (commit c66becf) — no ORCH intervention needed, no data actually lost in the end, but this confirms the race is still live and will recur under concurrent dispatch; worth a real fix (e.g. plan_commit re-diffing immediately before commit) rather than relying on every builder session happening to carry the same self-heal discipline GB's briefing does. Next: dispatch GB→TASK-003 (token-svc/**, no deps, GB now idle with a clean detached worktree); TASK-001 (CX) still in flight."
---

# Project Plan

Coordination blackboard for ORCH (Claude Code), GB (Grok Build), CX (Codex AI).
Rules: `AGENTS.md` (summary) and `docs/COORDINATION_PROTOCOL.md` (authoritative).
Status lifecycle: `pending → claimed → in_progress → needs_review → done`, `blocked` from claimed/in_progress. Builders never set `done`.

Spec shorthand used below: **TS** = `specs/KERYX_Product_Technical_Spec_v1.1.md`, **DS** = `specs/KERYX_UI_Design_Specification_v1.0.md`, **PT** = `specs/keryx-face-prototype.html`.

## Work Items

### TASK-001
**Title:** Repo scaffold: Flutter app + CI (KRX-001, app half)
**Status:** needs_review
**Assigned_To:** CX
**Priority:** critical
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.1, §11 E1 (KRX-001), §9 NFR-10; specs/KERYX_UI_Design_Specification_v1.0.md §3
**Owned_Paths:** pubspec.yaml, pubspec.lock, analysis_options.yaml, .metadata, .gitignore, README.md, lib/**, test/**, android/**, assets/**, .github/**
**Depends_On:** —
**Description:** Create the Flutter application skeleton per TS §8.1 (Flutter/Dart 3, Android-first, min SDK 26, target latest) via `flutter create --platforms android` (org `za.co.basileia`, project `keryx`), plus CI (GitHub Actions: `flutter analyze`, `flutter test`, debug APK build). Pre-declare ALL anticipated Phase-1 pub dependencies (flutter_riverpod, flutter_webrtc, livekit_client, flutter_secure_storage/shared_preferences, crypto, qr_flutter, mobile_scanner, vibration) and bundle/declare the four font families from DS §3 (DSEG7 Classic, Share Tech Mono, Barlow Condensed, Inter) plus empty `assets/sfx/v1/` pipeline dir, so downstream feature tasks never need to touch pubspec.yaml. Create empty directory skeleton `lib/core/`, `lib/features/`, `lib/services/` with placeholder barrel comments. Must NOT touch existing DEVDEPARTMENT files (docs/, scripts/, tests/, hooks/, briefings/, board/, deploy/, specs/, *.md coordination files) — append Flutter ignores to the existing .gitignore, don't replace it.
**Acceptance_Criteria:**
- [x] Flutter app targets Android with `minSdkVersion 26` per TS §8.1 ("Flutter (Dart 3), Android-first, min SDK 26, target latest")
- [x] Riverpod is the state-management dependency per TS §8.1 ("State mgmt: Riverpod (or Bloc — dev's standing convention wins)")
- [x] `flutter_webrtc` and `livekit_client` are declared per TS §8.1 ("WebRTC via flutter_webrtc (LOCAL) and livekit_client (LINKED)")
- [x] Font families DSEG7 Classic (7-segment channel numerals), Share Tech Mono, Barlow Condensed, Inter are bundled and declared per DS §3 typography table
- [x] `assets/sfx/v1/` exists as the versioned sound asset root per TS §7 ("Sound is a first-class, versioned asset set (/assets/sfx/v1/)")
- [x] CI workflow runs `flutter analyze`, `flutter test`, and builds a debug APK per TS §11 KRX-001 ("CI (analyze, test, build APK)")
- [x] `flutter analyze` and `flutter test` pass locally; no pre-existing repo file outside Owned_Paths modified
**Branch:** task/TASK-001-cx
**Started_At:** 2026-08-18T09:41:16Z
**Progress_Notes:**
- [2026-08-18T09:42:30Z] [CX] Preflight complete:
  [preflight] TASK-001 Owned_Paths inspected in C:\CLAUDECODE_TOOLSETS\wt-codex-walkietalkie-keryx
  [preflight] 11 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
    NEW    pubspec.yaml  -> does not exist; parent ./ exists
    NEW    pubspec.lock  -> does not exist; parent ./ exists
    NEW    analysis_options.yaml  -> does not exist; parent ./ exists
    NEW    .metadata  -> does not exist; parent ./ exists
    FILE   .gitignore  -> exists, 13 line(s), 340 bytes
    NEW    README.md  -> does not exist; parent ./ exists
    GLOB   lib/**  -> matches nothing yet (new territory)
    GLOB   test/**  -> matches nothing yet (new territory)
    GLOB   android/**  -> matches nothing yet (new territory)
    GLOB   assets/**  -> matches nothing yet (new territory)
    GLOB   .github/**  -> matches nothing yet (new territory)
  [preflight] Paste this output into your first Progress_Note as the c8b9872 filesystem check.
- [2026-08-18T09:59:47Z] [CX] Flutter Android scaffold, Phase-1 dependencies, bundled font assets, versioned SFX root, CI workflow, and minimal Riverpod boot shell committed as 789d30a; ready for review. Local debug APK build was attempted after setting compileSdk 37 for flutter_secure_storage, but the environment timed out during Gradle without a final result.
**Artifacts:**
- `.github/workflows/flutter.yml`, `.gitignore`, `.metadata`, `README.md`, `analysis_options.yaml`, `pubspec.yaml`, `pubspec.lock`
- `android/**`, `assets/fonts/**`, `assets/sfx/v1/.gitkeep`, `lib/main.dart`, `lib/core/core.dart`, `lib/features/features.dart`, `lib/services/services.dart`, `test/widget_test.dart`
**Test_Evidence:**
- [2026-08-18T09:58:00Z] [CX] `flutter analyze` — passed: No issues found.
- [2026-08-18T09:58:00Z] [CX] `flutter test` — passed: 1/1 widget tests.
- [2026-08-18T09:58:00Z] [CX] `flutter build apk --debug` — attempted twice; first exposed compileSdk 37 requirement from `flutter_secure_storage` and a shader output-write error, then retry timed out after 306 s in Gradle with no final artifact/result. CI independently runs this required command.
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** CX
**Updated_At:** 2026-08-18T09:59:47Z

### TASK-002
**Title:** Relay stack: LiveKit + Redis + Caddy + coturn Docker compose (KRX-050)
**Status:** done
**Assigned_To:** GB
**Priority:** critical
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.1 (Relay row), §8.4, §11 E6 (KRX-050), §9 NFR-05, NFR-09
**Owned_Paths:** relay/**
**Depends_On:** —
**Description:** Build the self-hosted relay deployment under `relay/`: a single Docker compose with LiveKit SFU, Redis, Caddy (TLS), and coturn (TURN), configured for a single-VPS deployment (clawsrv-class, 4 vCPU/8 GB) per TS §8.1. Include livekit.yaml, Caddyfile, turnserver.conf, an `.env.example` (domains, keys, secrets — no real secrets committed), a `relay/README.md` runbook (bring-up, ports, firewall), and a hardening checklist per KRX-050. Provide a compose config-validation script/test (`docker compose config`) runnable without a live VPS.
**Acceptance_Criteria:**
- [x] `relay/docker-compose.yml` defines LiveKit + Redis + Caddy TLS + coturn per TS §8.1 ("Self-hosted LiveKit (single Docker compose: LiveKit + Redis + Caddy TLS + coturn) on one VPS")
- [x] coturn is bundled and wired into LiveKit config per TS §8.4 ("TURN (coturn) bundled for hostile NATs; target ≥ 97% connection success")
- [x] No secrets in-repo: `.env.example` documents every required variable; compose interpolates from env
- [x] Hardening checklist delivered per TS §11 KRX-050 ("Relay deployment: LiveKit + Redis + coturn + Caddy compose; hardening checklist")
- [x] Scale-out path documented per TS §9 NFR-09 ("1 VPS serves ≥ 500 concurrent channel-joins; scale-out documented")
- [x] `docker compose config` validates cleanly (evidence pasted)
**Branch:** task/TASK-002-gb
**Started_At:** 2026-08-18T09:32:00Z
**Progress_Notes:**
- [2026-08-18T09:35:00Z] [GB] Claimed TASK-002. Preflight (c8b9872 filesystem check) output:
```
[preflight] TASK-002 Owned_Paths inspected in C:\CLAUDECODE_TOOLSETS\wt-grok-walkietalkie-keryx
[preflight] 1 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
  GLOB   relay/**  -> matches nothing yet (new territory)
[preflight] Paste this output into your first Progress_Note as the c8b9872 filesystem check.
```
New territory under relay/**. Implementing LiveKit+Redis+Caddy+coturn compose, env templates, runbook, hardening checklist, and `docker compose config` validator.
- [2026-08-18T09:40:37Z] [GB] Relay stack complete on `task/TASK-002-gb` (commit 1234447). Compose: livekit/livekit-server:v1.9.11 + redis:7.4.2-alpine + caddy:2.9.1-alpine + coturn/coturn:4.6.3-alpine, host network, no egress/ingress. coturn wired via livekit.yaml turn_servers (UDP/TCP 3478 + TLS 5349). Secrets only in .env.example placeholders. Ready for review.
**Artifacts:**
- relay/docker-compose.yml
- relay/.env.example
- relay/.gitignore
- relay/Caddyfile
- relay/livekit.yaml.tmpl
- relay/turnserver.conf.tmpl
- relay/redis.conf
- relay/README.md
- relay/HARDENING.md
- relay/scripts/render_config.py
- relay/scripts/validate.ps1
- relay/scripts/validate.sh
- relay/tests/test_relay_config.py
**Test_Evidence:**
- [2026-08-18T09:40:37Z] [GB] `python relay/tests/test_relay_config.py` — 16/16 OK (includes `docker compose --env-file .env.example config --format json`). Services: caddy, coturn, livekit, redis. Images: caddy:2.9.1-alpine, coturn/coturn:4.6.3-alpine, livekit/livekit-server:v1.9.11, redis:7.4.2-alpine. Also `powershell -File relay/scripts/validate.ps1` — render + compose config + unit checks green. No live VPS bring-up (not required).
- [2026-08-18T09:55:09Z] [ORCH] Independently re-run at HEAD 1234447 (worktree clean, tests ran against committed code): `python relay/tests/test_relay_config.py` → 16 run, 16 passed, 0 failed, 0 skipped, exit 0. `validate.ps1` → exit 0 (render + `docker compose --env-file .env.example config` + unit suite). Docker 29.6.1 / Compose v5.1.4 present, so the compose validation is real, not skipped — `test_docker_compose_config_validates` has no skip path (it `self.fail()`s if docker is off PATH) and asserts {livekit, redis, caddy, coturn} present with no egress/ingress service. GB's "16/16 OK" claim verified exactly, no discrepancy.
**Review_Findings:**
- [2026-08-18T09:55:09Z] [ORCH] **APPROVED, first-pass.** Territory clean (13 files, all `relay/**`). PLAN.md discipline clean (e6ed13f / d3b1a29 / c66becf each touch only the TASK-002 block — no frontmatter, no other task's block). c8b9872 preflight filesystem check present in the first Progress_Note. All 6 acceptance criteria verified against quoted spec text, not GB's summary. No blocking defects. Two non-blocking follow-ups, to be carried into a later relay task rather than reopening this one:
  1. **coturn TLS (5349) has no certificate.** `turnserver.conf.tmpl` sets `tls-listening-port=5349` but supplies no `cert=` / `pkey=`, and neither README nor HARDENING documents provisioning one. Caddy's ACME certs live in the `caddy_data` named volume, which is not shared with the coturn container. Meanwhile `livekit.yaml.tmpl` advertises a `protocol: tls` TURN server on 5349 and the README firewall table opens 5349/tcp — so that advertised candidate will not serve until a cert is wired. Not blocking: the TURN/UDP and TURN/TCP 3478 paths (the primary hostile-NAT route for NFR-05) are fully configured and correct.
  2. **LiveKit API secret has two sources of truth.** `docker-compose.yml` injects `LIVEKIT_KEYS: "${LIVEKIT_API_KEY}:${LIVEKIT_API_SECRET}"` while the rendered `livekit.yaml` also carries a `keys:` block. GB documents this as a deliberate second injection path, but it is a rotation hazard — the HARDENING key-rotation procedure only describes rotating the `keys:` block. Worth collapsing to one path, or extending the rotation step to cover both.
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T09:55:09Z

### TASK-003
**Title:** Token service: FastAPI LiveKit JWT mint + rate limiting (KRX-051)
**Status:** in_progress
**Assigned_To:** GB
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.1 (Signaling glue row), §8.4, §8.7, §11 E6 (KRX-051), FR-044
**Owned_Paths:** token-svc/**
**Depends_On:** —
**Description:** Implement the stateless FastAPI token service under `token-svc/`: accepts a room derivation (roomId per TS §8.7 — computed client-side; the service never sees passphrases) plus callsign, mints a short-lived LiveKit JWT (identity = callsign + random suffix), enforces IP-scoped rate limits, and refuses expired Event-QR tokens (FR-044). No user DB, no persistent user records. Include pytest suite covering mint, expiry refusal, rate limiting, and a logging-policy test asserting nothing beyond ephemeral rate-limit counters is logged. Dockerfile + README so it can join the relay compose later (compose wiring itself belongs to relay/** — do not edit relay/**).
**Acceptance_Criteria:**
- [ ] Service is a small stateless FastAPI app minting LiveKit JWTs from room derivations with no user DB per TS §8.1 ("Tiny stateless token service (FastAPI, ~200 LOC): mints LiveKit JWTs from room derivations; no user DB")
- [ ] JWT identity is callsign + random suffix and short-lived per TS §8.4 ("token service issues a short-lived LiveKit JWT (identity = callsign + random suffix)")
- [ ] Expired event tokens are refused per FR-044 ("Expired tokens are refused by the token service so temporary event channels do not linger on the relay")
- [ ] Rate limiting is IP-scoped, counters expire ≤ 1 h per TS §8.7 ("logs nothing beyond ephemeral, IP-scoped rate-limit counters (no callsigns, no room-join histories; counters expire ≤ 1 h)")
- [ ] Logging-policy test asserts no callsigns/room-join histories are ever logged per TS §8.7 ("asserted by a logging-policy test in KRX-051")
- [ ] Full pytest suite green (evidence pasted)
**Branch:** task/TASK-003-gb
**Started_At:** 2026-08-18T09:59:39Z
**Progress_Notes:**
- [2026-08-18T10:02:00Z] [GB] Claimed TASK-003. Preflight (c8b9872 filesystem check) output:
```
[preflight] TASK-003 Owned_Paths inspected in C:\CLAUDECODE_TOOLSETS\wt-grok-walkietalkie-keryx
[preflight] 1 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
  GLOB   token-svc/**  -> matches nothing yet (new territory)
[preflight] Paste this output into your first Progress_Note as the c8b9872 filesystem check.
```
New territory under token-svc/**. Implementing FastAPI JWT mint, event-token expiry, IP rate limits, logging-policy tests.
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** GB
**Updated_At:** 2026-08-18T10:02:00Z

### TASK-004
**Title:** Radio state machine reducer + 100%-branch test suite (KRX-003)
**Status:** pending
**Assigned_To:** CX
**Priority:** critical
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.2, §11 E1 (KRX-003), §9 NFR-10, FR-040, FR-045
**Owned_Paths:** lib/core/state/**, test/core/state/**
**Depends_On:** TASK-001
**Description:** Implement the authoritative radio state machine of TS §8.2 as a single pure reducer (Riverpod-hosted): states OFF/BOOT/IDLE(RX)/TUNING/TX_REQ/TX/RX_ACTIVE/LINK_DEGRADED with the transition graph exactly as specified, plus the mode dimension (LOCAL/AUTO/LINKED, FR-040) and channel/code tuning state (CH 1–99, code 00–38, FR-001/FR-002 ranges). Events in, state out — no IO, no widgets, no network. UI/audio/haptics/network consume it as projections. 100% branch coverage unit suite.
**Acceptance_Criteria:**
- [ ] Reducer implements `OFF → BOOT → IDLE(RX) ⇄ TUNING`, `IDLE → TX_REQ → TX (granted) → IDLE`, `IDLE → RX_ACTIVE (remote floor) → IDLE`, `any → LINK_DEGRADED → IDLE|LOCAL_FALLBACK` per TS §8.2 diagram
- [ ] Exactly one reducer owns the state per TS §8.2 ("One reducer owns this. UI, audio, haptics, and network are all projections of it")
- [ ] Channel domain is 1–99 and privacy code 00–38 with 00 = open per FR-001/FR-002
- [ ] Mode is a three-position LOCAL/AUTO/LINKED value, default AUTO, per FR-040
- [ ] LINK_DEGRADED path drops to LOCAL without any modal error per FR-045 ("never a modal error dialog")
- [ ] 100% branch coverage on the reducer per NFR-10 ("Reducer/state machine 100% branch"); coverage report pasted as evidence
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-005
**Title:** Theme system: design tokens, typography, materials (KRX-010 token half)
**Status:** pending
**Assigned_To:** CX
**Priority:** high
**Spec_References:** specs/KERYX_UI_Design_Specification_v1.0.md §2, §3, §4, §9 (KRX-010 amended); specs/keryx-face-prototype.html (:root CSS tokens); specs/KERYX_Product_Technical_Spec_v1.1.md FR-106
**Owned_Paths:** lib/core/theme/**, test/core/theme/**
**Depends_On:** TASK-001
**Description:** Implement DS §2–§4 as a single Dart theme source under `lib/core/theme/`: the six shell/glass/lcd/legend colour tokens, the four signal colours (tx/rx/emg/olive), typography roles and scale (DSEG7 for channel numerals, Share Tech Mono glass, Barlow Condensed legends, Inter panels), the two motion curves (`snap` 140 ms cubic-bezier(.2,.9,.3,1); `settle` 320 ms ease-out), 8 dp grid constants, face vertical-allocation ratios, and the lip/inner-edge material treatment. Values must match PT's `:root` exactly. Unit tests assert token values and that no other library file will need literal colours (export a lint-friendly single import surface).
**Acceptance_Criteria:**
- [ ] All six colour tokens match DS §2 hexes exactly (`--shell-900 #15181B` … `--legend #CFCBC0`) and signal colours `--tx #E23D2E`, `--rx #7FD1A0`, `--emg #FF7A18`, `--olive #6B7052`
- [ ] Unlit segments render as `--lcd` at 7% opacity per DS §2 ("Unlit segments = --lcd at 7% opacity (ghost segments)") — exposed as a token
- [ ] Typography scale per DS §3: channel numerals 56/1.0, secondary glass 15/1.2, telltales 11/1.0, legends 11/1.0 at 0.14em, panel body 15/1.5
- [ ] Motion: only `snap` (140 ms, cubic-bezier(.2,.9,.3,1)) and `settle` (320 ms, ease-out) exist per DS §4 ("Two curves only")
- [ ] Theme is the single source per DS §9 KRX-010 amendment ("implement the token system of §2–§4 as a single theme source; no literal colour or duration values elsewhere in the widget tree")
- [ ] Token/typography unit tests green
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-006
**Title:** Floor control protocol v1: message codec, versioning, timing constants (KRX-040)
**Status:** pending
**Assigned_To:** GB
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.6, §11 E5 (KRX-040), FR-025
**Owned_Paths:** lib/core/protocol/**, test/core/protocol/**
**Depends_On:** TASK-001
**Description:** Implement the floor-control protocol v1 wire layer under `lib/core/protocol/`: JSON codec for TX_REQ/TX_GRANT/TX_DENY/TX_START/TX_END/PRESENCE/RCHK/RCHK_ACK/EMG/EMG_CLR with the exact fields of TS §8.6, protocol-version tagging with unknown-version tolerance, and the locked timing constants table exported as a single constants module (heartbeat 5 s / 3 misses, lease TOT+2 s, re-election ≤ 500 ms, TX_REQ retry 150 ms ×3, floor-idle debounce 750 ms). Pure Dart, transport-agnostic (data-channel and LiveKit data-message transports plug in later). Round-trip and forward-compat tests.
**Acceptance_Criteria:**
- [ ] All ten message types with the exact fields of the TS §8.6 table (e.g. `TX_REQ {peer, prio, ts}`, `TX_GRANT {peer, lease_ms}`, `TX_DENY {peer, reason: BUSY|LOCKOUT}`, `PRESENCE {peer, cs, seq}`)
- [ ] Every message carries a protocol version and unknown versions are ignored per TS §8.6 ("All messages carry protocol version; unknown versions are ignored (forward compatibility)")
- [ ] `TX_REQ` prio supports 0 normal / 1 emergency per TS §8.6 ("prio: 0 normal, 1 emergency")
- [ ] Timing constants exactly match TS §8.6 locked table (5 s/3 missed, TOT+2 s default 62 s, ≤ 500 ms, 150 ms/3 attempts, 750 ms) and are asserted by tests
- [ ] Encoding is JSON per TS §8.6 ("JSON over data channels; protobuf reserved for v2")
- [ ] Codec round-trip + malformed-input tests green
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-007
**Title:** Room derivation library: numbered/keyed/scrypt + test vectors (KRX-053)
**Status:** pending
**Assigned_To:** GB
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.7, §11 E6 (KRX-053), FR-002, FR-007, FR-008
**Owned_Paths:** lib/core/rooms/**, test/core/rooms/**
**Depends_On:** TASK-001
**Description:** Pure-Dart room derivation under `lib/core/rooms/`: `numbered: roomId = b32(HMAC-SHA256("KERYX.v1", region | ch | code))[:16]` and `keyed: roomId = b32(HMAC-SHA256("KERYX.v1", "PRV" | scrypt(passphrase)))[:16]` per TS §8.7, with region-salt input (FR-008) and fixed scrypt parameters (document chosen N/r/p in code — spec leaves them open, ORCH ratifies at review). Deliver a frozen test-vector suite (known inputs → known roomIds) so client and any future server tooling can never drift.
**Acceptance_Criteria:**
- [ ] Numbered derivation implements `b32(HMAC-SHA256("KERYX.v1", region | ch | code))[:16]` per TS §8.7
- [ ] Keyed derivation implements `b32(HMAC-SHA256("KERYX.v1", "PRV" | scrypt(passphrase)))[:16]` per TS §8.7
- [ ] Region participates in numbered derivation per FR-008 ("Region setting (region salt) partitions the numbered-channel namespace on LINKED")
- [ ] Passphrase is scrypt-stretched and never leaves the client per TS §8.7 ("Keyed channels get real entropy from the passphrase (scrypt-stretched)"; "Server sees keyed-channel room hashes only, never passphrases")
- [ ] Privacy code participates in room derivation per FR-002 ("on LINKED, code participates in room derivation (§8.7)")
- [ ] Frozen test vectors committed and green
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-008
**Title:** Settings & persistence layer: encrypted prefs, channel memory (KRX-004)
**Status:** pending
**Assigned_To:** CX
**Priority:** medium
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.1 (Persistence row), §11 E1 (KRX-004), FR-009, FR-023, FR-046, FR-061, FR-062
**Owned_Paths:** lib/core/settings/**, test/core/settings/**
**Depends_On:** TASK-001
**Description:** Local-only persistence under `lib/core/settings/`: encrypted prefs store (flutter_secure_storage-backed with in-memory fake for tests) holding all Phase-1 settings — squelch level (FR-061), roger-beep variant (FR-062), TOT duration 30–120 s (FR-023), busy-lockout on/off (FR-022), latch mode (FR-021), character-DSP intensity (TS §7.2), force-LOCAL-only toggle (FR-046), region (FR-008), Pro flag placeholder — plus channel memory of the last 6 tuned channels (FR-009). Typed repository API with Riverpod providers; zero server-side persistence.
**Acceptance_Criteria:**
- [ ] Storage is "Local only: settings + channel memory in encrypted prefs. No server-side persistence of anything." per TS §8.1
- [ ] Channel memory keeps the last 6 tuned channels per FR-009 ("Channel memory: last 6 tuned channels accessible via quick-recall")
- [ ] TOT setting is configurable 30–120 s with 60 s default per FR-023 ("max continuous TX 60 s (configurable 30–120 s)")
- [ ] A force-LOCAL-only toggle is persisted per FR-046 ("A 'force LOCAL only' privacy toggle that hard-disables all WAN traffic")
- [ ] Character-DSP intensity persists Off/Light/Full with default Light per TS §7.2 ("Character DSP intensity: Off / Light / Full (default Light)")
- [ ] Repository unit tests green against the in-memory fake
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-009
**Title:** Identity: peerId derivation + NATO callsign generator (KRX-075 + §8.6 identity)
**Status:** pending
**Assigned_To:** GB
**Priority:** medium
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.6 (Peer identity), FR-068, §11 E8 (KRX-075)
**Owned_Paths:** lib/core/identity/**, test/core/identity/**
**Depends_On:** TASK-001
**Description:** Under `lib/core/identity/`: install-time UUID generation (persisted via its own tiny storage adapter, not TASK-008's territory), `peerId = base32(SHA-256(installUUID))[:10]`, NATO-phonetic callsign auto-generation (e.g. `BRAVO-7`, `SIERRA-19`), callsign editing with 2–12 char validation, and per-channel collision suffixing logic (`BRAVO-7 (2)` by join order) as a pure function over a peer list. Property tests on peerId distribution/stability and collision suffixing.
**Acceptance_Criteria:**
- [ ] `peerId = base32(SHA-256(installUUID))[:10]`, generated once at install, independent of callsign, per TS §8.6 ("Peer identity (normative)")
- [ ] Callsigns are auto-generated NATO-phonetic on first run, editable, 2–12 chars, per FR-068
- [ ] No uniqueness enforcement beyond per-channel collision suffixing per FR-068 ("No accounts, no uniqueness enforcement beyond per-channel collision suffixing")
- [ ] Collision rendering: later joiners get a numeric suffix by join order; peerIds never collide, per TS §8.6 ("later joiners render with a numeric suffix (BRAVO-7, BRAVO-7 (2)) derived from join order")
- [ ] Callsigns are display-only (not used in election) per TS §8.6 ("Callsigns are display-only")
- [ ] Unit/property tests green
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-010
**Title:** SFX engine: dual-bus mixer, ducking, loop beds, roger variants (KRX-021 + KRX-024 playback)
**Status:** pending
**Assigned_To:** GB
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §7.1, §7.2, §11 E3 (KRX-021, KRX-024), FR-006, FR-062; specs/keryx-face-prototype.html (audio engine section)
**Owned_Paths:** lib/core/audio/**, test/core/audio/**, assets/sfx/**
**Depends_On:** TASK-001
**Description:** The SFX half of the audio stack under `lib/core/audio/`: a dual-bus mixer (Voice bus / SFX bus), the §7.1 asset manifest as a typed registry loading from `assets/sfx/v1/`, seamless-loop static beds with squelch-level crossfade, ducking rules (SFX ducks voice −3 dB ≤ 150 ms; voice never ducks for cosmetics), and roger-beep variant playback (off/classic K/dual-tone). Commissioned audio (KRX-020) is out of scope — generate placeholder synthesized WAVs (48 kHz 16-bit, −16 LUFS target; emergency −12 LUFS) mirroring PT's synthesis so the manifest is exercised end-to-end. Tests via a fake audio sink asserting bus routing and ducking envelopes.
**Acceptance_Criteria:**
- [ ] Two buses exist and SFX never traverses the network per TS §7.2 ("Two buses: Voice bus (network audio) and SFX bus (local assets). SFX never traverses the network")
- [ ] All SFX play from local assets on a dedicated bus per P4 ("All SFX play from local assets on a dedicated bus — instant and identical regardless of network conditions")
- [ ] Every §7.1 manifest asset has a registry entry and a placeholder file (squelch_open/tail, static_bed_1/2/3, tune_burst, scan_tick, roger_k/dual/moto, deny_buzz, tot_warn/cut, link_lost/up, emg_alert, rchk_ok, key_click, knob_tick, slider_thunk, power_on/off)
- [ ] Ducking: "SFX ducks voice by −3 dB during overlap ≤ 150 ms; voice never ducks for cosmetics" per TS §7.2
- [ ] Static beds loop seamlessly and crossfade with the squelch knob per TS §7.1 ("Seamless loop points; squelch knob crossfades")
- [ ] Assets are 48 kHz 16-bit WAV normalised to −16 LUFS, emergency at −12 LUFS, per TS §7 preamble
- [ ] Mixer/ducking unit tests green
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-011
**Title:** Radio character DSP + squelch gate wiring (KRX-022, KRX-023)
**Status:** pending
**Assigned_To:** GB
**Priority:** medium
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §7.2 (RX chain), §11 E3 (KRX-022, KRX-023), FR-061
**Owned_Paths:** lib/core/audio/**, test/core/audio/**, assets/sfx/**
**Depends_On:** TASK-010
**Description:** Extend `lib/core/audio/` (same territory as TASK-010, sequenced after it) with the voice-bus RX chain: 300–3400 Hz band-pass, 3:1 soft-knee compression, +0…+6 dB makeup, optional hiss floor mixed at squelch-knob level, with Off/Light/Full intensity; plus squelch wiring — the squelch setting drives both the RX gate threshold and the resting hiss bed level. DSP as a pure sample-transform pipeline with golden-audio unit tests (process known buffers, assert spectra/envelope), independent of WebRTC plumbing.
**Acceptance_Criteria:**
- [ ] RX chain implements "radio character DSP (300–3400 Hz band-pass, 3:1 soft-knee compression, +0…+6 dB makeup, optional hiss floor mixed at squelch-knob level)" per TS §7.2
- [ ] Intensity setting Off/Light/Full with default Light per TS §7.2
- [ ] Squelch "sets RX gate threshold and the resting hiss level (from silent to faint bed)" per FR-061
- [ ] DSP is testable without network: pure buffer-in/buffer-out pipeline; unit tests green
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-012
**Title:** Segment LCD glass component: channel/code, telltales, dot-matrix line (KRX-012)
**Status:** pending
**Assigned_To:** CX
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §6.1, §6.3, §11 E2 (KRX-012), FR-001, FR-002, FR-007; specs/KERYX_UI_Design_Specification_v1.0.md §1, §5.2, §9 (FR-109); specs/keryx-face-prototype.html (.glass markup)
**Owned_Paths:** lib/features/display/**, test/features/display/**
**Depends_On:** TASK-005
**Description:** The glass: a self-contained widget under `lib/features/display/` rendering channel · code in DSEG7 amber segments with ghost segments behind (7% opacity), the mode label, the dot-matrix secondary line (active speaker/status), and the telltale row (TX, MON, PRV, VOX, EMG, NO LINK, replay) — driven entirely by an immutable display-model input (no state ownership). Includes backlight bloom, warm-black glass substrate, the BOOT all-segments flash (`88 · 88`, per DS FR-109/PT power-on), night-dimming input (DS FR-108), and `PRV` + label rendering for keyed channels. Widget tests for every telltale and content mode.
**Acceptance_Criteria:**
- [ ] Channels display as segment-style `CH 01`–`CH 99` per FR-001; code as `CH 07 · 21` per FR-002
- [ ] Keyed channels render as `PRV` + user label per FR-007 ("Rendered as PRV + user label on the display")
- [ ] Amber appears only inside the glass; ghost segments at 7% opacity per DS §2 rules
- [ ] Telltale icons only — "no toasts, no snackbars, no dialogs on the face" per TS §6.3
- [ ] Power-up shows the all-segments flash per DS §1 ("including the classic 'all segments on' flash at power-up") and DS §9 FR-109
- [ ] Display/legend luminance follows a dim input per DS §9 FR-108 ("Night dimming — display and legend luminance follow an auto/manual dim setting")
- [ ] Widget tests cover telltales TX/MON/PRV/VOX/EMG/NO LINK per TS §6.1 diagram; green
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-013
**Title:** Rotary knob widget: arc drag, detents, flywheel, haptic hooks (KRX-011)
**Status:** pending
**Assigned_To:** CX
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §3 D1, §6.2, §6.4, FR-003, §11 E2 (KRX-011); specs/KERYX_UI_Design_Specification_v1.0.md §5.1; specs/keryx-face-prototype.html (knob physics script)
**Owned_Paths:** lib/features/knob/**, test/features/knob/**
**Depends_On:** TASK-005
**Description:** The signature element: a 96 dp knurled knob widget under `lib/features/knob/` with arc-drag tuning (1 detent = 1 channel), detent snap at ±12° with critically-damped settle, fling → flywheel with exponential friction decay (per PT: decay factor, no spring), tick rate capped at 12 ch/s, and per-detent callback firing haptic `PRIMITIVE_CLICK` (scale 0.6) + tick-sound + LCD-update hooks in the same frame. Emits channel-delta events only — tuning state itself lives in TASK-004's reducer. Widget tests drive gestures and assert detent counts, cap, and settle.
**Acceptance_Criteria:**
- [ ] "Drag along an arc; 1 detent = 1 channel; detent snap at ±12° with critically-damped settle" per TS §6.2
- [ ] "Fling → flywheel with exponential decay, detent ticks (audio + haptic) firing per channel crossed, capped at 12 ch/s" per TS §6.2
- [ ] Every detent fires haptic PRIMITIVE_CLICK, 8 ms tick sample hook, LCD update "all in the same frame" per TS §6.2
- [ ] Knob is 96 dp, knurled, with olive indicator line per DS §5.1
- [ ] Flywheel "follows real friction decay, not a spring preset" per DS §4
- [ ] Widget tests green (drag N detents → N channel deltas; fling respects 12/s cap)
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-014
**Title:** CH steppers with auto-repeat + keypad direct-entry sheet (KRX-013)
**Status:** pending
**Assigned_To:** CX
**Priority:** medium
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §3 D1, FR-004, FR-005, FR-009, FR-106, §11 E2 (KRX-013); specs/keryx-face-prototype.html (stepper script)
**Owned_Paths:** lib/features/tuning/**, test/features/tuning/**
**Depends_On:** TASK-005
**Description:** Under `lib/features/tuning/`: CH▲/CH▼ stepper buttons with press-and-hold accelerating auto-repeat (PT: 420 ms initial, rate ×0.82 per repeat, floor 60 ms — treat as the ratified feel), long-press-channel-display keypad sheet for direct entry of channel 1–99 + privacy code 00–38 (rendered in-world, not a Material dialog), and quick-recall of the 6-slot channel memory on long-press CH▼ (FR-009). Emits tuning intents only; ≥ 48 dp targets, full TalkBack labels (steppers are the accessible tuning path).
**Acceptance_Criteria:**
- [ ] "CH▲/CH▼ steppers with press-and-hold auto-repeat (accelerating)" per FR-004
- [ ] "Long-press channel display → keypad direct entry of channel + code" per FR-005
- [ ] "Channel memory: last 6 tuned channels accessible via quick-recall (long-press CH▼)" per FR-009
- [ ] All three input paths "write to the same tuning state machine" per D1 — widget emits intents, owns no channel state
- [ ] Touch targets ≥ 48 dp and TalkBack labels present per FR-106 ("stepper-first tuning path, min 48 dp targets")
- [ ] Widget tests green (auto-repeat acceleration, keypad range validation 1–99 / 00–38)
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-015
**Title:** PTT button, secondary key row, EMG side key (KRX-015)
**Status:** pending
**Assigned_To:** CX
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §6.1, §6.4, FR-020, FR-021, FR-022, FR-025, FR-026, §11 E2 (KRX-015); specs/KERYX_UI_Design_Specification_v1.0.md §2 (signal colours), §4 (key travel); specs/keryx-face-prototype.html (.ptt/.keys markup)
**Owned_Paths:** lib/features/ptt/**, test/features/ptt/**
**Depends_On:** TASK-005
**Description:** Under `lib/features/ptt/`: the full-width ≥ 96 dp PTT button (pressed/granted/denied/latched visual states, red TX treatment, screen edge-glow while transmitting), latch-mode gesture (double-tap lock, tap release), the secondary key row (MON, SCAN, SAY AGAIN, settings key — with Pro-locked dimmed state), and the orange EMG side key with long-press activation. Haptic composition hooks per TS §6.4 (grant QUICK_RISE, deny THUD ×2, TOT TICK ×3) with fallback patterns. Pure presentation + intent events; floor logic stays in TASK-022's territory.
**Acceptance_Criteria:**
- [ ] PTT is "≥ 96 dp tall, bottom third, full-width, thumb-native" per TS §6.1 face diagram
- [ ] "red TX LED skeuomorph, screen edge-glow while transmitting, distinct grant/deny/timeout haptic compositions" per FR-026
- [ ] Denied state: "PTT press yields a denied buzz + short haptic and the TX LED does not light" per FR-022 (visual/haptic hooks; deny decision is an input)
- [ ] "Latch mode (double-tap to lock TX, tap to release)" per FR-021
- [ ] EMG: "long-press dedicated orange key" pins an EMG indicator until cleared per FR-025
- [ ] Red appears only while this device holds the floor per DS §2 ("Red appears only while the floor is held by this device")
- [ ] Pressed keys move 1 dp down, lose top highlight, gain inner shadow per DS §4 ("the same three changes on every control")
- [ ] Widget tests green for all states incl. Pro-locked keys ("Pro keys shown dimmed/locked when unowned", TS §6.1)
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-016
**Title:** Speaker-grille RX visualiser (KRX-014)
**Status:** pending
**Assigned_To:** TBD
**Priority:** medium
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §6.1, §11 E2 (KRX-014); specs/KERYX_UI_Design_Specification_v1.0.md §4 (motion), §5.3; specs/keryx-face-prototype.html (grille script)
**Owned_Paths:** lib/features/grille/**, test/features/grille/**
**Depends_On:** TASK-005
**Description:** Under `lib/features/grille/`: the speaker-grille widget whose bars tremble with incoming RX audio amplitude (amplitude stream input), using the `settle` curve (the grille "has mass"), with a live/idle tint state and `prefers-reduced-motion` handling that removes the tremble while keeping the widget inert-but-correct. The only ambient animation allowed in the product.
**Acceptance_Criteria:**
- [ ] "grille bars tremble with incoming audio amplitude" per TS §6.1 ("the only 'animation for its own sake' allowed")
- [ ] Grille motion uses the `settle` curve per DS §4 ("`settle` (320 ms, ease-out) for the grille and meter, which have mass")
- [ ] Reduced-motion "removes the grille tremble … but keeps every haptic and sound" per DS §4 — widget exposes a motion-off mode without dropping amplitude input plumbing
- [ ] Amplitude is an injected stream (no audio-engine import from grille code) so the widget is testable; widget tests green
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-017
**Title:** Face assembly: layout, status strip, station-list flip, app wiring (KRX-010 assembly)
**Status:** pending
**Assigned_To:** CX
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §6.1, FR-067, FR-069, §11 E2 (KRX-010); specs/KERYX_UI_Design_Specification_v1.0.md §4 (layout grid), §6 (state catalogue); specs/keryx-face-prototype.html (full page layout)
**Owned_Paths:** lib/features/face/**, test/features/face/**, lib/main.dart, lib/app.dart
**Depends_On:** TASK-004, TASK-012, TASK-013, TASK-014, TASK-015, TASK-016
**Description:** Compose the whole face under `lib/features/face/` + app entry (`lib/main.dart`, `lib/app.dart`): housing material (moulded texture, single top-left light), DS §4 vertical allocation (status strip 6% · glass 18% · grille 26% · controls 22% · PTT 22% · safe 6%), status strip (aggregate S-meter, STN count, battery, mode), the STN-tap station-list panel flip with per-station S-meters and 5 s auto-flip-back, portrait-primary with landscape "brick on its side", and wiring of every child widget to the TASK-004 reducer projections. This task is the sole owner of `lib/main.dart`/`lib/app.dart` — the app must boot to the face.
**Acceptance_Criteria:**
- [ ] Vertical allocation matches DS §4: "status strip 6% · glass 18% · grille 26% · control cluster 22% · PTT 22% · safe area 6%"
- [ ] "Controls never occupy the top third — hands cover the bottom, eyes read the top" per DS §4
- [ ] Presence: "STN n count on the display; tap to flip the display panel to the station list (callsigns + S-meter per station). Flip back automatically after 5 s" per FR-067
- [ ] Status-strip meter is aggregate (talking station's link while TX, worst active peer at idle); per-station meters live in the flip panel, per FR-069
- [ ] "Landscape supported (radio rotates to 'brick on its side' layout); portrait is primary" per TS §6.1
- [ ] UI is a projection of the single reducer per TS §8.2 — no widget owns radio state
- [ ] App boots to the face; widget tests for strip/flip green; `flutter analyze` clean
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-018
**Title:** Settings-as-back-panel screen (KRX-016)
**Status:** pending
**Assigned_To:** TBD
**Priority:** medium
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md FR-100, FR-061, FR-046, FR-023, §11 E2 (KRX-016); specs/KERYX_UI_Design_Specification_v1.0.md §3 (Interface role), §7 (copy voice)
**Owned_Paths:** lib/features/settings_panel/**, test/features/settings_panel/**
**Depends_On:** TASK-005, TASK-008
**Description:** Under `lib/features/settings_panel/`: the settings screen rendered as the radio's back panel / battery hatch (FR-100), exposing the TASK-008 settings repository — squelch knob control, roger-beep variant, TOT duration, latch mode, busy lockout, character-DSP intensity, force-LOCAL-only, region, dim mode — in equipment-manual copy voice (DS §7), Inter type for panel body, ≥ 48 dp targets, TalkBack labelled.
**Acceptance_Criteria:**
- [ ] "Settings rendered as the radio's back panel / battery-hatch screen — even configuration stays in-world (P1)" per FR-100
- [ ] Squelch control "sets RX gate threshold and the resting hiss level" per FR-061 (wired to the TASK-008 setting)
- [ ] Force-LOCAL-only toggle exposed per FR-046
- [ ] Copy follows DS §7 voice ("Labels are nouns or verbs a radio user knows"; the word survives the whole flow — key `MONITOR`, telltale `MON`, setting *Monitor*)
- [ ] Panel body uses Inter 15/1.5 per DS §3
- [ ] Widget tests green; all settings round-trip through the repository
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-019
**Title:** NSD discovery platform channel + MulticastLock lifecycle (KRX-030)
**Status:** pending
**Assigned_To:** GB
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.1 (Local discovery row), §8.3 step 1, FR-041, FR-042, §9 NFR-04, §11 E4 (KRX-030)
**Owned_Paths:** android/**, lib/services/discovery/**, test/services/discovery/**
**Depends_On:** TASK-001
**Description:** Native Android NSD (mDNS) via a platform channel (TS §8.1: "Native reliability > plugin roulette"): Kotlin-side register/browse of `_keryx._tcp` with TXT records `cs` (callsign), `ch` (channel-hash prefix), `v` (protocol version) — plus the signaling port for TASK-020's WebSocket — MulticastLock acquired only while the radio is on, and a Dart facade under `lib/services/discovery/` exposing peer-found/lost streams. Includes the UDP broadcast beacon fallback trigger surface (beacon implementation detail: 2 s intervals for 30 s after tuning, per §8.3 step 5) and a `LAN?` state output. Dart-side tests against a mocked channel; Kotlin unit-testable where feasible.
**Acceptance_Criteria:**
- [ ] "LOCAL discovery via mDNS/NSD, service type `_keryx._tcp`, TXT records: cs (callsign), ch (channel hash prefix), v (protocol version)" per FR-041
- [ ] "MulticastLock acquired while radio is on" per FR-041 — and released on power-off (TS §8.8: "MulticastLock only while LOCAL discovery active")
- [ ] TXT carries a channel-hash prefix, never plaintext channel/code, per TS §8.3 ("privacy: full channel/code never broadcast in plaintext")
- [ ] Fallback: "a UDP broadcast beacon fallback runs at 2 s intervals for 30 s after tuning; if both fail the display shows `LAN?`" per TS §8.3 step 5
- [ ] Implemented via Android NSD platform channel per TS §8.1 ("Android NSD (mDNS) via platform channel")
- [ ] Dart facade tests green with mocked platform channel
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-020
**Title:** LAN signaling WebSocket + peer session management (KRX-031)
**Status:** pending
**Assigned_To:** TBD
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.3 steps 2–3, FR-042, §11 E4 (KRX-031, KRX-034)
**Owned_Paths:** lib/services/signaling/**, test/services/signaling/**
**Depends_On:** TASK-006, TASK-009
**Description:** Under `lib/services/signaling/`: each device runs a LAN WebSocket server on a random high port (advertised via NSD TXT), peers with matching channel hash connect and exchange WebRTC offer/answer over it (LAN candidates only: host candidates, mDNS ICE). Peer session lifecycle (connect, churn, departure via PRESENCE misses using TASK-006 codec + TASK-009 peerIds), and the 16-peer soft-cap warning state (KRX-034). No media here — mesh audio is TASK-021. Tested with in-process socket pairs.
**Acceptance_Criteria:**
- [ ] "each device runs a loopback-free LAN WebSocket (random high port, advertised in NSD). Peers on a matching channel hash perform WebRTC offer/answer over it" per TS §8.3 step 2
- [ ] "LAN candidates only (host candidates; mDNS ICE)" per TS §8.3 step 2
- [ ] Fully serverless: "LAN-internal signaling (§8.3), no packets leave the network" per FR-042
- [ ] Departure detection: "5 s heartbeat; 3 misses = departed" per TS §8.6 PRESENCE row
- [ ] "N ≤ 16 peers per channel on LAN is the supported envelope (soft cap, warn beyond)" per TS §8.3 step 3 — cap state exposed
- [ ] Session-lifecycle tests green (join, churn, departure, cap)
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-021
**Title:** WebRTC mesh audio: pre-published muted track, enable-on-grant (KRX-032)
**Status:** pending
**Assigned_To:** TBD
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.3 step 3, §8.5, §8.1 (Codec row), FR-020, §9 NFR-01/NFR-03, §11 E4 (KRX-032)
**Owned_Paths:** lib/services/mesh/**, test/services/mesh/**
**Depends_On:** TASK-020
**Description:** Under `lib/services/mesh/`: full-mesh WebRTC audio over the TASK-020 sessions using flutter_webrtc — Opus mono 16–24 kbps, 20 ms frames, in-band FEC on, DTX off during TX; the audio track pre-published muted on channel join with PTT grant flipping `enabled=true` (the ≤ 50 ms TX attack); RX rendering gated by TX_START/TX_END floor messages. Data channels opened for the floor-control transport (consumed by TASK-022). Testable via abstraction over the WebRTC plugin; on-device latency measurement is a later bench task.
**Acceptance_Criteria:**
- [ ] "full-mesh WebRTC audio. Mesh is safe here because PTT means at most one publisher at a time" per TS §8.3 step 3
- [ ] "the audio track is pre-published muted on channel join; PTT grant flips enabled=true" per TS §8.5
- [ ] TX attack ≤ 50 ms from grant designed-for per FR-020 ("TX attack ≤ 50 ms from grant to live audio (pre-published muted track, §8.5)")
- [ ] Codec config: "Opus, mono, 16–24 kbps, 20 ms frames, in-band FEC on, DTX off during TX" per TS §8.1
- [ ] Floor-control data channel established per TS §8.3 step 4 ("Floor control: over WebRTC data channels using the protocol in §8.6")
- [ ] Unit tests green against the plugin abstraction (publish-muted on join, enable on grant, gate on TX_START/END)
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-022
**Title:** Floor control runtime: arbiter election, leases, lockout, TOT, emergency (KRX-041/042/043)
**Status:** pending
**Assigned_To:** TBD
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.3 step 4, §8.6, FR-022, FR-023, FR-025, §11 E5 (KRX-041, KRX-042, KRX-043)
**Owned_Paths:** lib/core/floor/**, test/core/floor/**
**Depends_On:** TASK-004, TASK-006
**Description:** Under `lib/core/floor/`: the floor-control engine consuming/emitting TASK-006 protocol messages over an injected transport — deterministic arbiter election (lexicographically lowest peerId, re-elected on churn, self-healing ≤ 500 ms), grant leases (TOT + 2 s, expiry frees a crashed speaker's floor), busy-channel lockout denials, TOT with T-5 s warning and hard cut, TX_REQ retry (150 ms ×3), and emergency pre-emption (prio=1 pre-empts an active lease, EMG pin until EMG_CLR). Drives the TASK-004 reducer via events. Deterministic (injected clock) unit tests.
**Acceptance_Criteria:**
- [ ] "Deterministic arbiter = lexicographically lowest peer ID currently in the channel (re-elected on churn); grants are idempotent and time-bounded, so arbiter loss self-heals within 500 ms" per TS §8.3 step 4
- [ ] "Grants expire; a crashed speaker frees the floor automatically at lease end" per TS §8.6; lease = TOT + 2 s
- [ ] Busy lockout: "if the floor is held, PTT press yields a denied buzz … Setting: on by default" per FR-022 (deny decision emitted; SFX/haptics are consumers)
- [ ] TOT: "max continuous TX 60 s (configurable 30–120 s). Warning chirp at T-5 s, hard cut + penalty tone at 0, floor released" per FR-023 (warn/cut events emitted)
- [ ] "emergency TX_REQ(prio=1) pre-empts an active lease" per TS §8.6; overrides busy lockout and pins EMG until cleared per FR-025
- [ ] TX_REQ retry 150 ms / 3 attempts per TS §8.6 timing table
- [ ] Deterministic unit tests green with injected clock/transport
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-023
**Title:** Floor-control simulation soak harness: 500-run churn/loss, zero double-grants (KRX-044)
**Status:** pending
**Assigned_To:** TBD
**Priority:** medium
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §11 E5 (KRX-044), §8.6, §9 NFR-10
**Owned_Paths:** test/simulation/**
**Depends_On:** TASK-022
**Description:** Under `test/simulation/`: a randomized simulation harness driving N virtual peers (TASK-022 engines over a simulated lossy/reordering transport with churn) for 500 seeded runs, asserting: never two simultaneous grants, arbiter re-election within the 500 ms settle bound, lease expiry frees a crashed speaker, and the §8.6 timing constants and peerId election properties hold. Seeds logged so failures reproduce.
**Acceptance_Criteria:**
- [ ] "Simulation test harness: 500-run randomized churn/loss soak, zero double-grants" per KRX-044
- [ ] Harness "asserts the locked timing constants and peerId election properties of §8.6" per KRX-044
- [ ] Failures are reproducible (seed printed per run)
- [ ] Suite runs green in CI ("floor protocol simulation suite" per NFR-10)
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-024
**Title:** LINKED integration: livekit_client join/publish/subscribe mirroring PTT (KRX-052 + KRX-055)
**Status:** pending
**Assigned_To:** TBD
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.4, §8.5, FR-043, FR-045, §11 E6 (KRX-052, KRX-055)
**Owned_Paths:** lib/services/linked/**, test/services/linked/**
**Depends_On:** TASK-003, TASK-007
**Description:** Under `lib/services/linked/`: LINKED-path client — derive roomId (TASK-007), fetch JWT from the token service (TASK-003 contract), join the LiveKit room, pre-publish the muted audio track, mirror PTT state on it, ride floor-control messages over LiveKit data messages (same §8.6 schema), and implement link-loss/regain behaviour: `NO LINK` flag, link_lost/link_up chirp events, auto-fallback to LOCAL, never a modal. Tested against a LiveKit client abstraction; live-relay smoke test documented for review.
**Acceptance_Criteria:**
- [ ] "Channel → deterministic roomId (§8.7) → token service issues a short-lived LiveKit JWT … → join room" per TS §8.4
- [ ] "One LiveKit room per channel; audio publish/subscribe mirrors PTT state; floor control messages ride LiveKit data messages (same schema as LOCAL)" per TS §8.4
- [ ] Muted pre-publish on join per TS §8.5 (same ≤ 50 ms attack design as LOCAL)
- [ ] "relay unreachable → radio drops to LOCAL with an audible 'link lost' double-chirp and NO LINK display flag; never a modal error dialog" per FR-045
- [ ] Join methods supported at the API level: numbered channel + code, keyed passphrase per FR-043
- [ ] Unit tests green against the client abstraction
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-025
**Title:** Event QR generate/scan + keryx:// deep links (KRX-054)
**Status:** pending
**Assigned_To:** TBD
**Priority:** medium
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md FR-043, FR-044, §11 E6 (KRX-054)
**Owned_Paths:** lib/features/event_qr/**, test/features/event_qr/**
**Depends_On:** TASK-007
**Description:** Under `lib/features/event_qr/`: export any channel as a QR + `keryx://` deep link encoding region, channel, code (or keyed-channel token) and expiry, with expiry presets 4 h / 24 h (default) / 7 d / no-expiry (extra explicit tap); scanner flow that tunes the radio instantly on scan; deep-link intent handling payload parser (Android manifest registration itself lands with the android-chain tasks — parser and UI here). Token format versioned; unit tests for encode/decode/expiry.
**Acceptance_Criteria:**
- [ ] "any channel can be exported as a QR code + keryx:// deep link encoding region, channel, code (or keyed-channel token), and expiry" per FR-044
- [ ] "Default expiry: 24 h, with presets (4 h 'session', 24 h, 7 d, no expiry — the last requiring an explicit extra tap)" per FR-044
- [ ] "Scanning tunes the radio instantly" per FR-044 — scan result emits a tuning intent
- [ ] Event QR is a first-class LINKED join method per FR-043
- [ ] Encode/decode/expiry unit tests green
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z

### TASK-026
**Title:** Foreground service + radio notification (KRX-080)
**Status:** pending
**Assigned_To:** TBD
**Priority:** medium
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md FR-102, FR-103, §8.8, §9 NFR-06, §11 E9 (KRX-080)
**Owned_Paths:** android/**, lib/services/platform/**, test/services/platform/**
**Depends_On:** TASK-019
**Description:** Android foreground service (`mediaPlayback` + `microphone` types) with the persistent radio-styled notification (channel shown, PTT action on Android 14+ where permitted, power-off action), partial wake lock held during RX/TX only, audio-focus handling (transient-may-duck for RX, abandon on power-off), and service-death detection hook (feeds FR-105 OEM guidance later). Shares the android/** chain after TASK-019 — never concurrent with it.
**Acceptance_Criteria:**
- [ ] "Foreground service with a persistent radio-styled notification (channel, PTT action button on Android 14+ where permitted, power-off action)" per FR-103
- [ ] Service types are `mediaPlayback` + `microphone`, "partial wake lock during RX/TX only" per TS §8.8
- [ ] Audio focus "transient-may-duck for RX; abandon on power-off" per TS §8.8
- [ ] Standby design honours FR-102 ("with nobody transmitting, no media flows (PTT model) — only presence keepalives") — no polling loops added by the service
- [ ] OEM-kill detection heuristic ("service death without user power-off") emits an event per TS §8.8
- [ ] Dart facade tests green; manual on-device checklist documented in dossier work log
**Branch:** —
**Started_At:** —
**Progress_Notes:** —
**Artifacts:** —
**Test_Evidence:** —
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T14:10:00Z
