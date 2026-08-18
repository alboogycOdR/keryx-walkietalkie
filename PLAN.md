---
plan_version: 1.6
last_updated: 2026-08-18T13:12:13Z
overall_status: in_progress
orchestrator_notes: "Plan v1.0 — 26 tasks from 3 specs. Territory: pubspec.yaml/analysis_options.yaml/.github/**/.gitignore/README.md FROZEN since 2c40de2. android/** serialized 001→019→026. lib/core/audio/** serialized 010→011. Dossiers in dossiers/TASK-NNN.md. S5/S5B INACTIVE — never assign. Full review/incident history in git log / REVIEW.md, not repeated here. Known unresolved risk: plan_commit doesn't re-diff before commit — real lost-update race hit twice, both self-healed by builder discipline, not mechanically fixed. SPEC/PLAN FOLLOW-UPS OWED (full detail in each task's Review_Findings + REVIEW.md — index only): (a) font OFL/LICENSE missing; (b)+(c) .github/** CI pin+coverage task (after TASK-004 lands); (d) BLOCKS TASK-007 — roomId base32 alphabet undefined in spec, token-svc pinned RFC 4648 by implementation; (e) token-svc trusts X-Forwarded-For unconditionally; (f) R4 per-room caps unbuilt; (g) keryx-evt.v1 contract vs FR-044 prose; (h) tune_burst ducking direction contradicts itself §7.1/FR-006 vs §7.2; (i) KRX-024 60ms end-of-TX marker unspecified/uncoded; (j) SFX ducking release has no driver wired; (k) BLOCKS TASK-012/013/014 — channel/code wrap-vs-clamp undefined, decide before those three dispatch; (l) LINK_DEGRADED/LOCAL_FALLBACK undefined in §8.2; (m) BLOCKS TASK-017+TASK-022 (neither eligible yet anyway) — RadioState still lacks the flags/STN-count/active-speaker DS §6 requires; CX's rework correctly left this alone (not a rework cause) — NOW MANDATORY, NOT OPTIONAL: TASK-004 merged at 6994a11 so lib/core/state/** is FROZEN with no owner, and the other unfixed non-blocking items from that review live in the same file (tuneDelta + wrap-vs-clamp, Riverpod-import purity split, legacy StateNotifierProvider vs NotifierProvider, LinkRecovered naming, LinkDegraded accepted from off, SetMode accepted mid-TX). ORCH must create a successor task owning lib/core/state/** before TASK-017/TASK-022 dispatch, on the 010→011 pattern; full item list in TASK-004 Review_Findings. No git remote — CI has never run. NEW SPEC uncommitted in specs/: KERYX_World_Band_Radio_Spec_v1.0.md (Phase 2, not now). STATUS SCAN (2026-08-18T13:00Z): TASK-004 (CX) rework complete and back to needs_review — fixed exactly criterion 6 (exhaustive 8-phase×14-event transition matrix, explicit negative tests for the 3 previously-unguarded transitions, dropped the unsupportable coverage percentage per the review's instruction), left the non-blocking items alone as instructed. Territory still clean (2 files), 2 commits (9731221, d05013b) both tagged. TASK-006 (GB, floor-control protocol codec) also landed at needs_review — territory clean (7 files, all lib/core/protocol+test/core/protocol), commit ccfbb01 tagged [TASK-006]. Both builders now idle. No blocked tasks, no critical findings, no drift. REVIEW 2026-08-18T13:12:13Z: TASK-004 APPROVED on re-review and merged as 6994a11 — the mutation test that condemned round 1 now goes red, all three guards independently caught; post-merge integrated suite on master 36/36 green, analyze clean; branch task/TASK-004-cx deleted and CX's worktree detached at d05013b. Nothing unlocked — TASK-017 still needs 012/013/014/015/016 (all pending), TASK-022 still needs TASK-006 (still at needs_review). Next: /devteam-review TASK-006 (queued, separate pass); then dispatch whichever builder(s) go idle against remaining eligible work — GB: {007 still blocked by (d), 009, 019}; CX: {005, 008} — and create the lib/core/state/** successor task per follow-up (m) before TASK-017/TASK-022 can ever dispatch."
---

# Project Plan

Coordination blackboard for ORCH (Claude Code), GB (Grok Build), CX (Codex AI).
Rules: `AGENTS.md` (summary) and `docs/COORDINATION_PROTOCOL.md` (authoritative).
Status lifecycle: `pending → claimed → in_progress → needs_review → done`, `blocked` from claimed/in_progress. Builders never set `done`.

Spec shorthand used below: **TS** = `specs/KERYX_Product_Technical_Spec_v1.1.md`, **DS** = `specs/KERYX_UI_Design_Specification_v1.0.md`, **PT** = `specs/keryx-face-prototype.html`.

## Work Items

### TASK-001
**Title:** Repo scaffold: Flutter app + CI (KRX-001, app half)
**Status:** done
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
**Review_Findings:** APPROVED first-pass, merged as 2c40de2. Territory clean — 37 files, 1314 insertions / 0 deletions, single commit 789d30a tagged [TASK-001], every path inside Owned_Paths (verified by pathspec-exclusion diff returning empty). `.gitignore` is a pure 12-line append; all 13 pre-existing lines survive. No DEVDEPARTMENT file touched. c8b9872 preflight present in Progress_Notes. CX's 3 PLAN.md commits (7a07c8c/44d3c7a/01d1fc4) touched only this block — no frontmatter, no other task's block. All 7 acceptance criteria verified against independently quoted spec text (TS §7 L238, §8.1 L272/273/278, §11 KRX-001 L418; DS §3 L80-82). Test_Evidence reproduced exactly at CX's HEAD: `flutter analyze` → "No issues found!" exit 0; `flutter test` → 1/1 pass exit 0 (Flutter 3.41.6 stable / Dart 3.11.4 present locally; `flutter doctor` all-green incl. Android SDK 37, so the toolchain claim is real). `compileSdk = 37` verified truthful against flutter_secure_storage-11.0.0's own build.gradle; minSdk stays 26. No secrets; zero dependency bloat (lockfile has exactly 10 direct-main entries = flutter + the 9 specified). NON-BLOCKING FOLLOW-UPS (do NOT reopen this task — they need ORCH-created tasks since this territory is now frozen): (1) LICENCE COMPLIANCE — the 5 bundled TTFs ship with no OFL/LICENSE file despite the dossier's explicit "with their licence files"; SIL OFL requires the licence to travel with redistribution, and these are embedded in the APK. Must land before any release build. `assets/fonts/**` is NOT in the frozen set, so a small follow-up task can own it. (2) CI pins `channel: stable` but no `flutter-version`, so CI floats away from the locally-pinned 3.41.6 — needs a `.github/**` integration task. (3) CI has no `--coverage`/threshold, so §9 NFR-10 ("≥ 80% overall") is unenforced — correctly deferred until TASK-004's reducer exists, but `.github/**` is frozen so it needs the same integration task. (4) Inter is declared as a single variable TTF with no `weight:`/`FontVariation` entries, so a `FontWeight.w600` request synthesises bold rather than using the real 600 axis — carry into TASK-005 theming (DS §3 asks Inter 400/600). Barlow Condensed 600 IS correctly declared. (5) No git remote configured, so the CI workflow has never actually executed — criterion 6 is verified by static inspection only.
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T10:16:44Z

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
**Status:** done
**Assigned_To:** GB
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.1 (Signaling glue row), §8.4, §8.7, §11 E6 (KRX-051), FR-044
**Owned_Paths:** token-svc/**
**Depends_On:** —
**Description:** Implement the stateless FastAPI token service under `token-svc/`: accepts a room derivation (roomId per TS §8.7 — computed client-side; the service never sees passphrases) plus callsign, mints a short-lived LiveKit JWT (identity = callsign + random suffix), enforces IP-scoped rate limits, and refuses expired Event-QR tokens (FR-044). No user DB, no persistent user records. Include pytest suite covering mint, expiry refusal, rate limiting, and a logging-policy test asserting nothing beyond ephemeral rate-limit counters is logged. Dockerfile + README so it can join the relay compose later (compose wiring itself belongs to relay/** — do not edit relay/**).
**Acceptance_Criteria:**
- [x] Service is a small stateless FastAPI app minting LiveKit JWTs from room derivations with no user DB per TS §8.1 ("Tiny stateless token service (FastAPI, ~200 LOC): mints LiveKit JWTs from room derivations; no user DB")
- [x] JWT identity is callsign + random suffix and short-lived per TS §8.4 ("token service issues a short-lived LiveKit JWT (identity = callsign + random suffix)")
- [x] Expired event tokens are refused per FR-044 ("Expired tokens are refused by the token service so temporary event channels do not linger on the relay")
- [x] Rate limiting is IP-scoped, counters expire ≤ 1 h per TS §8.7 ("logs nothing beyond ephemeral, IP-scoped rate-limit counters (no callsigns, no room-join histories; counters expire ≤ 1 h)")
- [x] Logging-policy test asserts no callsigns/room-join histories are ever logged per TS §8.7 ("asserted by a logging-policy test in KRX-051")
- [x] Full pytest suite green (evidence pasted)
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
- [2026-08-18T10:09:43Z] [GB] Token service complete on `task/TASK-003-gb` (commit f22a26c). FastAPI POST /token mints HS256 LiveKit JWTs (identity=`callsign#<8 hex>`), refuses expired/forged Event-QR tokens (keryx-evt.v1 contract in README), IP rate limiter with ≤1h counter TTL, logging policy + suite. Dockerfile included; did not touch relay/**.
**Artifacts:**
- token-svc/app/main.py
- token-svc/app/config.py
- token-svc/app/models.py
- token-svc/app/jwt_mint.py
- token-svc/app/event_token.py
- token-svc/app/rate_limit.py
- token-svc/app/logging_policy.py
- token-svc/Dockerfile
- token-svc/README.md
- token-svc/.env.example
- token-svc/requirements.txt
- token-svc/tests/test_mint.py
- token-svc/tests/test_event_token.py
- token-svc/tests/test_rate_limit.py
- token-svc/tests/test_logging_policy.py
- token-svc/tests/test_validation.py
**Test_Evidence:**
- [2026-08-18T10:09:43Z] [GB] `Set-Location token-svc; .\.venv\Scripts\python.exe -m pytest -v` — 23 passed, 0 failed, 0.94s. Suites: test_event_token 7, test_logging_policy 2, test_mint 5, test_rate_limit 5, test_validation 4.
- [2026-08-18T10:53:36Z] [ORCH] Independently re-run at GB's HEAD f22a26c. Note: the shared GB worktree had already been repurposed to `task/TASK-010-gb` (HEAD a0cc2c5), so `token-svc/` was no longer on disk there; rather than mutate another unit's worktree, the committed tree was extracted read-only (`git archive f22a26c token-svc`) into a scratchpad, a fresh venv built, and `pip install -r requirements.txt -r requirements-dev.txt` run against the pinned versions. `python -m pytest -v -rA` (no `-k`, no path filter) → `23 passed in 0.42s`, exit 0, 0 failed / 0 skipped / 0 errors / 0 warnings, Python 3.11.9, pytest 8.4.1. Per-file: test_event_token 7, test_logging_policy 2, test_mint 5, test_rate_limit 5, test_validation 4 — matches GB's claim exactly, both in total and in per-suite breakdown. All pinned deps resolved exactly (fastapi 0.116.1 / pydantic 2.11.7 / PyJWT 2.10.1 / uvicorn 0.35.0 / httpx 0.28.1).
**Review_Findings:**
- [2026-08-18T10:53:36Z] [ORCH] **APPROVED, first-pass.** Territory clean: 22 files, 1015 insertions / 0 deletions, all under `token-svc/**`; a pathspec-exclusion diff (`--name-only -- . ':(exclude)token-svc/**'`) returns empty, and `relay/**` is provably untouched — the task's one explicit "do not edit" boundary is respected. Single commit `f22a26c` correctly tagged `[TASK-003]`. c8b9872 preflight filesystem check present verbatim in the first Progress_Note (new territory, glob matched nothing). PLAN.md discipline clean: 8e0d38e / 465ed9c / 840ce0c each touch only the TASK-003 block — no frontmatter, no other unit's block, no protected path. All 6 acceptance criteria verified against independently quoted spec text (TS §8.1 L277, §8.4 L303, §8.7 L352-361, FR-044 L136, FR-068 L152, §11 E6 L456-463, R4 L511), not GB's summary:
  1. **Stateless, no user DB** — FastAPI app, in-memory only; `test_no_user_database_or_state_files` actively greps `app/` for sqlite3/sqlalchemy/psycopg/pymongo and walks the tree for `.db`/`.sqlite` files. Satisfies TS L279 "No server-side persistence of anything."
  2. **Identity = callsign + random suffix, short-lived** — `new_identity()` = `{callsign}#{secrets.token_hex(4)}`, TTL default 300 s; test decodes the JWT and asserts `exp - nbf == 300`, `sub == identity`, suffix is 8 hex chars, and uniqueness across two mints. Callsign regex `[A-Za-z0-9-]{2,12}` matches FR-068's "2–12 chars" exactly.
  3. **Expired event tokens refused** — HMAC-SHA256 `keryx-evt.v1` tokens; `now >= exp` → 403 `expired_event_token`. Boundary (exact-expiry), forged-secret, wrong-room, and malformed cases all covered and all refused. `hmac.compare_digest` used for signature comparison (no timing leak).
  4. **IP-scoped rate limiting, counters expire ≤ 1 h** — TTL ceiling enforced twice, defensively: `IpRateLimiter.__init__` raises on `ttl_seconds > 3600` and `Settings.from_env` re-checks with an explicit "(TS §8.7)" message. Tests pin the boundary at 3599 s (retained) / 3600 s (purged) and assert distinct IPs get independent counters.
  5. **Logging-policy test** — genuinely strong, and value-based rather than keyword-based: it attaches a capture handler to root + `uvicorn` / `uvicorn.access` / `uvicorn.error` / `fastapi` / both keryx loggers, drives a full 200 request cycle with sentinel values, then asserts the sentinel callsign, sentinel room, and the returned identity are all absent from the captured stream, that "joined" never appears, and that `rate_limit` IS present (counters being the only permitted surface). This is exactly what TS L361 mandates.
  6. **Full suite green** — reproduced independently, 23/23, exit 0 (detail in Test_Evidence).
  No hardcoded secrets: `config.py` has no defaults for the three secrets (`_require` raises at startup), `.env.example` ships `REPLACE_ME_*` placeholders only, and the sole secret-shaped literals in the tree are obvious dev fixtures in `tests/conftest.py`. Error handling and input validation are sound — `RequestValidationError` is remapped to a flat `{"detail": "invalid_request"}` so no request values are echoed back, and FastAPI's `docs_url`/`redoc_url`/`openapi_url` are all disabled. Dockerfile runs as a non-root uid 10001 and passes `--no-access-log` (with an inline comment explaining that uvicorn's default access line can carry query strings). No blocking defects. Seven non-blocking follow-ups, to be carried into later tasks rather than reopening this one:
  1. **`X-Forwarded-For` is trusted unconditionally.** `_client_ip()` in `main.py` takes the first XFF hop with no trusted-proxy allowlist, so any client that can reach the service directly can rotate that header and bypass IP rate limiting entirely — defeating R4's "Token-svc rate limits". Safe as designed *only* because Caddy is meant to front it, but the README never states that as a deployment requirement. The relay-compose task that wires this service in should both restrict ingress to the proxy and document the trusted-hop assumption.
  2. **Per-room caps (R4) are not implemented.** TS L511 pairs "Token-svc rate limits" with "per-room caps"; only the former is delivered. GB explicitly defers this in README's Scale path, and it is genuinely relay-side work, but R4's mitigation is currently half-built — it needs its own task, not silence.
  3. **Base32 alphabet is spec-silent and has now been pinned by implementation.** TS §8.7 L355-356 says only `b32(...)[:16]`; it never fixes RFC 4648 vs Crockford, case, or padding. GB chose RFC 4648 uppercase unpadded (`^[A-Z2-7]{16}$`, with lowercase input normalized up) and documented it. This is a reasonable choice, but the client-side room-derivation work (KRX-053) must match it byte-for-byte or **every single mint request will 422**. Recommend ORCH write the alphabet into TS §8.7 as a versioned clarification rather than leave two tasks to converge by luck.
  4. **The Event-QR token contract is likewise normative-by-implementation.** FR-044 L136 says the QR encodes "region, channel, code (or keyed-channel token), and expiry"; GB's `keryx-evt.v1` payload carries only `{v, room_id, exp}`. That is self-consistent (roomId already folds region|ch|code via HMAC) and the README declares itself normative for TASK-025, but the spec and the implementation now describe different payloads. TASK-025/KRX-054 must be built against the README contract, and the discrepancy should be reconciled in the spec.
  5. **No coverage tooling.** `requirements-dev.txt` has no `pytest-cov`, so NFR-10 (TS L389, "≥ 80% overall") is unmeasured for this service. Same class as TASK-001 review follow-up (c); worth folding into the same CI/coverage integration task.
  6. **The logging-policy test cannot exercise the real uvicorn access-log path**, because `TestClient` bypasses uvicorn entirely. That path is instead closed by `--no-access-log` in both the Dockerfile CMD and the README run command — adequate, but enforced by convention rather than by test. A deployment smoke check should assert it.
  7. **`app/` is ~415 lines against TS §8.1's indicative "~200 LOC".** Not a defect — docstrings, type annotations and the split into seven small modules account for the difference, and the service is still unambiguously "tiny" — noted only because the spec quantifies it.
  Verified as intentional, not gaps: event tokens with no `exp` never expire (correct — FR-044 L136 lists "no expiry" as a real preset "requiring an explicit extra tap", and the README mirrors that wording); and the rate-limit check runs *before* event-token verification, so unauthenticated HMAC work cannot be used as an amplification vector. Merged as faaa657.
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T10:53:36Z

### TASK-004
**Title:** Radio state machine reducer + 100%-branch test suite (KRX-003)
**Status:** done
**Assigned_To:** CX
**Priority:** critical
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.2, §11 E1 (KRX-003), §9 NFR-10, FR-040, FR-045
**Owned_Paths:** lib/core/state/**, test/core/state/**
**Depends_On:** TASK-001
**Description:** Implement the authoritative radio state machine of TS §8.2 as a single pure reducer (Riverpod-hosted): states OFF/BOOT/IDLE(RX)/TUNING/TX_REQ/TX/RX_ACTIVE/LINK_DEGRADED with the transition graph exactly as specified, plus the mode dimension (LOCAL/AUTO/LINKED, FR-040) and channel/code tuning state (CH 1–99, code 00–38, FR-001/FR-002 ranges). Events in, state out — no IO, no widgets, no network. UI/audio/haptics/network consume it as projections. 100% branch coverage unit suite.
**Acceptance_Criteria:**
- [x] Reducer implements `OFF → BOOT → IDLE(RX) ⇄ TUNING`, `IDLE → TX_REQ → TX (granted) → IDLE`, `IDLE → RX_ACTIVE (remote floor) → IDLE`, `any → LINK_DEGRADED → IDLE|LOCAL_FALLBACK` per TS §8.2 diagram
- [x] Exactly one reducer owns the state per TS §8.2 ("One reducer owns this. UI, audio, haptics, and network are all projections of it")
- [x] Channel domain is 1–99 and privacy code 00–38 with 00 = open per FR-001/FR-002
- [x] Mode is a three-position LOCAL/AUTO/LINKED value, default AUTO, per FR-040
- [x] LINK_DEGRADED path drops to LOCAL without any modal error per FR-045 ("never a modal error dialog")
- [x] 100% branch coverage on the reducer per NFR-10 ("Reducer/state machine 100% branch"); coverage report pasted as evidence
**Branch:** task/TASK-004-cx
**Started_At:** 2026-08-18T10:25:15Z
**Progress_Notes:**
- [2026-08-18T10:25:15Z] [CX] Preflight complete:
  [preflight] TASK-004 Owned_Paths inspected in C:\CLAUDECODE_TOOLSETS\wt-codex-walkietalkie-keryx
  [preflight] 2 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
    GLOB   lib/core/state/**  -> matches nothing yet (new territory)
    GLOB   test/core/state/**  -> matches nothing yet (new territory)
  [preflight] Paste this output into your first Progress_Note as the c8b9872 filesystem check.
- [2026-08-18T10:28:28Z] [CX] Implemented and committed authoritative pure reducer plus Riverpod controller/providers on `task/TASK-004-cx` at `9731221`; all transitions, domains, AUTO default, and local fallback are covered.
- [2026-08-18T11:12:00Z] [ORCH] Reconciling: CX's own `needs_review` handoff was blocked at the time because the main checkout had a concurrent uncommitted TASK-010 edit in flight, and CX correctly refused to overwrite it rather than risk the lost-update race documented earlier this session — it left `Status: in_progress` and exited cleanly instead. The branch (single commit `9731221`, territory-clean) and the evidence below are exactly what CX recorded in its own transcript; this is only now applying the handoff CX had already completed the work for, once the board was quiescent.
- [2026-08-18T12:54:16Z] [CX] Rework complete in `d05013b`: added an exhaustive 8-phase × 14-event transition matrix and converted reducer dispatch to an exhaustive sealed-event switch, removing the unreachable fall-through.
**Artifacts:**
- `lib/core/state/radio_state.dart`
- `test/core/state/radio_state_test.dart`
**Test_Evidence:**
- [2026-08-18T10:28:28Z] [CX] `flutter test test/core/state/radio_state_test.dart --branch-coverage --coverage-path %TEMP%\keryx-task-004-lcov.info` — passed 12/12; LCOV branch records: 44/44 hit (100%).
- [2026-08-18T10:28:28Z] [CX] `flutter analyze` — passed: No issues found.
- [2026-08-18T10:28:28Z] [CX] `flutter test` — passed: 13/13 tests.
- [2026-08-18T12:54:16Z] [CX] `flutter test test/core/state/radio_state_test.dart --branch-coverage --coverage-path %TEMP%\keryx-task-004-lcov-rework.info` — passed 13/13. The matrix asserts 35 legal outcomes and 77 invalid-pair no-ops across all 112 phase/event pairs; LCOV reports `LF/LH 92/92` and 44/44 single-sided `BRDA` entries, but no `BRF/BRH` decision denominator (tool limitation; no percentage claimed).
- [2026-08-18T12:54:16Z] [CX] `flutter analyze` — passed: No issues found.
- [2026-08-18T12:54:16Z] [CX] `flutter test` — passed: 14/14 tests.
- [2026-08-18T13:12:13Z] [ORCH] Independent re-run at `d05013b` in a clean `git archive` extraction (Flutter 3.41.6 stable / Dart 3.11.4): `flutter analyze` → "No issues found!" exit 0; full `flutter test` → 14 passed / 0 failed / 0 skipped, exit 0. CX's claim reproduced exactly.
- [2026-08-18T13:12:13Z] [ORCH] Mutation re-test (the same experiment that failed this task last round), phase guards deleted from `BeginTuning` / `RequestTransmit` / `RemoteFloorStarted`: **exit 1, 13 passed / 1 failed** — `RadioPhase.off + Instance of 'BeginTuning'` at `radio_state_test.dart:45`. Each guard mutated individually from a clean tree is also caught (exit 1, `+13 -1` each). Previously this same mutation left the suite 13/13 green.
- [2026-08-18T13:12:13Z] [ORCH] Post-merge integrated suite on `master` at `6994a11`: `flutter analyze` → "No issues found!" exit 0; full `flutter test` → **36 passed / 0 failed / 0 skipped**, exit 0 (bed_mixer 6 + manifest_and_assets 5 + sfx_engine 11 + radio_state 13 + widget_test 1). No cross-package regression against TASK-010's audio suite — the branch predated that merge, so a branch-only run could not have detected one.
**Review_Findings:**
- [2026-08-18T12:08:40Z] [ORCH] **REWORK — one criterion only (criterion 6). Everything else passed; do not redo it.** The reducer implementation is good and the process was clean — this is a test-suite gap, not a rewrite.
- **CLEAN / ALREADY VERIFIED (leave alone):** territory is exactly the 2 owned files (`lib/core/state/radio_state.dart` +249, `test/core/state/radio_state_test.dart` +204), single commit `9731221` tagged `[TASK-004]`; the pathspec-exclusion diff for everything outside Owned_Paths is empty. c8b9872 preflight present. CX's 2 PLAN.md commits (`f4f10a0` claim, `f838b67` in_progress) touched only the TASK-004 block; ORCH's reconciliation commit `4230ac7` touched only frontmatter + the TASK-004 block, nothing else. Every number CX reported reproduced exactly at `9731221` on a clean tree: `flutter analyze` exit 0 "No issues found!" (Flutter 3.41.6 / Dart 3.11.4), full suite 13/13 exit 0 (12 state + 1 widget), targeted run 12/12, LCOV `LF/LH 94/94`, 44 `BRDA` records with zero unhit. CX did not overclaim its numbers — the problem is what the numbers mean (below).
- **CRITERIA 1–5 VERIFIED** against spec text quoted independently, not CX's summary (TS L283-289 §8.2, L106/107 FR-001/FR-002, L132 FR-040, L137 FR-045, L389 NFR-10, L56 D1, L305 §8.4): all four §8.2 graph lines are implemented edge-for-edge — `OFF→BOOT` (PowerOn), `BOOT→IDLE` (BootCompleted), `IDLE⇄TUNING` (Begin/FinishTuning), `IDLE→TX_REQ→TX→IDLE` (Request/Granted/EndTransmit), `IDLE→RX_ACTIVE→IDLE` (RemoteFloorStarted/Ended), `any→LINK_DEGRADED` (unconditional, and the test loops it over all 8 `RadioPhase.values`), `LINK_DEGRADED→IDLE|LOCAL_FALLBACK` (LinkRecovered, with `fallbackToLocal` selecting the second exit). The `TX_REQ→IDLE` deny edge is absent from the §8.2 graph but required by FR-022/`TX_DENY` (§8.6 L332) — adding it was the right call. One reducer genuinely owns the state: `RadioStateController.dispatch` is a one-liner delegating to `RadioReducer.reduce`, no logic is duplicated in the provider. Channel 1–99 / code 0–38 constants match FR-001/FR-002 and both ends of both domains are asserted. `RadioMode` has exactly three values and `auto` is the default in both constructors. The degradation path drops to LOCAL and, being a pure reducer, cannot raise a modal.
- **CRITERION 6 FAILS — the suite does not achieve 100% branch coverage, and the pasted evidence does not measure branch coverage at all.** Two independent proofs:
  1. **The LCOV artifact does not say what the evidence line claims.** The `--branch-coverage` output contains **no `BRF:` or `BRH:` line anywhere** — so "44/44 hit (100%)" has no denominator in the file; the ratio was inferred, not read. All 44 `BRDA` records are single-sided block-entry markers of the form `BRDA:<line>,0,0,<n>` on 44 *distinct* lines. Real decision coverage emits at least two entries per conditional so an untaken outcome shows as `0`; with one entry per line the format **structurally cannot report an untaken branch**, so "all hit" is guaranteed the moment each line is reached once. 30 of the 44 lines contain no conditional at all (constructors, `==`/`hashCode`/`toString`, the event classes, the two provider declarations). Every actual decision point is *absent* from the report: all 12 guard ternaries (155/160/165/170/175/186/191/196/201/206/211/216), the LOCAL-fallback ternary at **219**, the `&&` short-circuits in `_isValidTuning` (227-230) and `operator ==` (61-65), the `??` chain in `copyWith` (53-56), and both range asserts (26-28). Separately, line **223** (`return state;`, the `reduce` fall-through) has neither a `DA:` nor a `BRDA:` record, so `LF/LH 94/94` *excludes* it rather than proving it exercised — and this toolchain does emit zeros for genuinely uncovered code (a control full-suite run shows `lib/main.dart` with `DA:4,0` / `BRDA:4,0,0,0`), so the omission is real.
  2. **Mutation test — decisive.** ORCH deleted the phase guard from three transitions, leaving each as an unconditional `state.copyWith(...)`: `BeginTuning`, `RequestTransmit`, `RemoteFloorStarted`. That makes a powered-off radio enter TUNING, lets a PTT press re-enter TX_REQ from the middle of TX, and flips the device out of its own TX into RX_ACTIVE on a remote floor start. **The full suite stayed 13/13 green, exit 0.** Three of the reducer's 14 guards therefore have their illegal-transition branch entirely unexercised — `BeginTuning` is only ever driven from IDLE (test L25), `RequestTransmit` only from IDLE (L36, L51), `RemoteFloorStarted` only from IDLE (L64). (Worktree restored to `9731221` immediately after; `git status` empty, `git diff HEAD` empty, HEAD unchanged.) Credit where due: the other 11 guards *do* have explicit negative tests, and all four falsy paths of `_isValidTuning` are covered by distinct out-of-range cases (ch 0, ch 100, code -1, code 39) — that part was deliberate and correct.
- **TO FIX (this is the whole rework):** (i) add negative cases asserting `BeginTuning`, `RequestTransmit` and `RemoteFloorStarted` return the state **unchanged** from non-IDLE phases; (ii) then do what the dossier's step 5 actually asked and make the suite **table-driven over the full `RadioPhase.values` × event matrix**, so every legal edge is asserted to move and every illegal pair is asserted to be a no-op — that makes the coverage claim structural instead of incidental, and it is the only form of evidence that survives this toolchain; (iii) account for `radio_state.dart:223` explicitly — given `sealed class RadioEvent` and all 14 subclasses handled, it is unreachable, so either delete it or cover it; (iv) **do not quote a "100% branch" percentage from `--branch-coverage` again** — Dart/LCOV emits no decision records for ternaries or `&&` here, so that number cannot support NFR-10. State the evidence as the explicit phase×event matrix (count of legal edges asserted + count of illegal pairs asserted no-op) plus `LF/LH`, and note the tool's limitation honestly. An accurate, smaller claim is worth more than a large one the artifact does not back.
- **NON-BLOCKING — fix opportunistically while the territory is live (it freezes on merge; `lib/core/state/**` has no other owner in the plan):**
  1. **No `PowerOff` event** — there is no edge back to OFF. §8.2's graph does not draw one either, so this is not a criterion failure, but DS §6 lists `OFF` as a golden-test state, TASK-010 already ships a `power_off` SFX, and FR-065 requires the replay buffer cleared "on channel change or radio-off". Cheapest to add now.
  2. **No `tuneDelta`** — only absolute `TuneTo` exists. D1 (TS L56) is explicit that knob, CH▲/▼ steppers and keypad "all write to the same tuning state machine" (FR-003/004/005). With only absolute tuning, TASK-012/-013/-014 will each compute the next channel themselves — and **wrap-vs-clamp at 99/1 and 38/00 is spec-silent** (grep-confirmed absent from both specs; it is an implementer's choice, not a violation), so three widgets would each decide it independently. Own the decision in the reducer and write it down.
  3. **`RadioState` carries no flags, no station count, no active speaker** — FR-045 `NO LINK`, FR-025 `EMG`, FR-007 `PRV`, FR-065 replay, FR-060 `MON`, FR-063 scan, FR-024 `VOX`, FR-067 `STN n`, §6.1's active-speaker line, FR-069's S-meter. DS §6's "State Catalogue (frozen by golden tests, KRX-018)" names all of them and TS L289 makes them projections of *this* reducer. Not in TASK-004's Description or criteria, so **not a rework cause** — but TASK-017 owns only `lib/features/face/**`+main/app and TASK-022 only `lib/core/floor/**`, so neither can extend `RadioState` later. Adding them in this rework window is far cheaper than the successor task ORCH must otherwise create (the 010→011 pattern) before TASK-017/TASK-022 can dispatch.
  4. **Purity is structurally unprovable as written** — `radio_state.dart` imports `package:flutter_riverpod/flutter_riverpod.dart`, which transitively pulls in Flutter's widget layer, so the file holding the "no IO, no widgets, no network" reducer cannot be imported widget-free and its tests must run under `flutter test` rather than `dart test`. The reducer function itself is genuinely pure (no IO, no network, no clock, no randomness — verified by reading). Split the Riverpod host into its own file (the dossier's step 1-4 layout: `radio_state.dart` / `radio_event.dart` / `radio_reducer.dart` + provider) so a purity test can assert zero framework imports on the reducer — the same proof-by-absence pattern TASK-010 used for the audio bus.
  5. **`StateNotifier`/`StateNotifierProvider` is Riverpod's legacy API** (riverpod 2.6.1 still exports it, hence the clean analyze; it moves to `legacy.dart` and is slated for removal in 3.x). Dossier step 4 asked for `NotifierProvider`. TASK-017 and TASK-022 both build on this surface — switch it before it spreads.
  6. **`LinkRecovered(fallbackToLocal: true)` is misnamed** — it is the LOCAL_FALLBACK exit, which is *structurally correct* per the graph (`LINK_DEGRADED → IDLE|LOCAL_FALLBACK` puts both exits on the leave-degradation edge), but "recovered" is the wrong word for the branch that gives up. Rename (e.g. `LinkResolved`, or split out a `LocalFallback` event). Note for ORCH: `LINK_DEGRADED` and `LOCAL_FALLBACK` each appear exactly once in the entire spec — inside the §8.2 graph — and are never defined; CX's mapping LOCAL_FALLBACK ≡ (phase idle, mode local) is therefore normative-by-implementation and needs writing into the spec.
  7. **`LinkDegraded` is accepted from `off`**, so `OFF → LINK_DEGRADED → IDLE` reaches IDLE without ever passing BOOT. Literally spec-compliant ("any → LINK_DEGRADED"), but almost certainly unintended — gate it to powered-on phases.
  8. **`SetMode` is accepted in every phase, including mid-TX.** TS L305 says the AUTO path switch happens "at floor-idle only", with a 750 ms floor-idle debounce (§8.6 L350). Outside this task's criteria, but the reducer is where that guard belongs.
  9. FR-002's "`00` = open" is representable (min code 0, and the default) but carries no named semantic — a `bool get isOpenCode` would make the projection sites read correctly.
  10. The `RadioState` range `assert`s are stripped in release builds, so `copyWith` is unvalidated outside debug. Nothing currently reaches it (the reducer validates first), but consider clamping rather than asserting.
  11. LCOV `SF:` paths are emitted with Windows backslashes (`lib\core\state\radio_state.dart`) — `genhtml` and most coverage uploaders will not resolve those on a POSIX CI runner. Matters for the pending `.github/**` coverage-gate follow-up (c), not for this task.
  12. Cosmetic: the claim commit set `Started_At: 2026-08-18T14:32:00Z` (local time, not UTC) and the in_progress commit then moved `Updated_At` *backwards* to 10:25:15Z. Use UTC for both.
- [2026-08-18T13:12:13Z] [ORCH] **APPROVED on re-review (rework resubmission — NOT first-pass). Merged as `6994a11`.** Scoped to criterion 6; criteria 1–5 were verified in depth last round and were deliberately not re-litigated.
- **THE FIX IS REAL — the same mutation test that condemned the first submission now goes red.** ORCH re-ran the exact prior experiment in a throwaway `git archive` extraction (the live worktree was never touched): deleting the phase guards from `BeginTuning`, `RequestTransmit` and `RemoteFloorStarted` — leaving each an unconditional `copyWith` — now **fails, exit 1, 13 passed / 1 failed**, first mismatch reported as `RadioPhase.off + Instance of 'BeginTuning'` at `radio_state_test.dart:45`. Each guard was then mutated **individually** from a clean tree and **all three are independently caught** (exit 1, `+13 -1` each). Last round this identical mutation left the suite 13/13 green; the gap is closed.
- **The matrix claim holds up on reading, not just on the runner.** `test/core/state/radio_state_test.dart:14-56` iterates `RadioPhase.values` (8) × a 14-element `RadioEvent` list = 112 pairs, and asserts **both** directions on every pair: `expect(actual, expected)` against an oracle, then classifies via `identical(expected, state)` and pins the split with `expect(legalTransitions, 35)` / `expect(illegalNoOps, 77)`. ORCH recomputed those counts by hand from the reducer's own semantics — LinkDegraded 8 + SetMode 8 + TuneTo 8 (all phase-independent) + 11 single-source-phase edges = 35, and 112 − 35 = 77 — so the hard-coded constants are correct, not curve-fitted. The oracle `_expectedMatrixResult` (L250-290) is a genuine parallel reimplementation using `when` guards, **not** a delegation back into `RadioReducer`, so it cannot trivially agree with a broken reducer. Caveat recorded honestly: it is still a hand-written second copy of the same spec, so a misconception made consistently in both places would survive; and the matrix fails fast, so a multi-guard regression surfaces as one failing test naming only the first bad cell.
- **Worth knowing for future assignment:** under every mutation the **13 hand-written scenario tests stayed green** — all of the killing power lives in the single matrix test. That vindicates instruction (ii) of the last review: the table-driven form is what made the coverage structural rather than incidental.
- **Line 223 resolved by deletion, and better than asked.** `reduce` was converted from an `is`-chain to an exhaustive `switch (event)` expression over the `sealed class RadioEvent` hierarchy with all 14 arms present, so the unreachable `return state;` fall-through is gone. Semantics are byte-for-byte unchanged (diff read arm by arm) and exhaustiveness is now **compiler-enforced** — a future 15th event subclass becomes a compile error instead of a silent no-op. That is a stronger outcome than "delete or cover".
- **Evidence wording is now honest.** The rework Test_Evidence line states the matrix counts (35 legal / 77 no-op / 112 pairs) plus `LF/LH 92/92`, and explicitly says "44/44 single-sided `BRDA` entries, but no `BRF/BRH` decision denominator (tool limitation; no percentage claimed)". No "100% branch" percentage is asserted anywhere in the rework evidence. Instruction (iv) complied with precisely. (The criterion checkbox text still reads "100% branch coverage … coverage report pasted as evidence" — that is ORCH's own wording from decomposition, not a CX claim; NFR-10 is satisfied here by the exhaustive phase×event matrix, which is the strongest evidence this toolchain can produce.)
- **Process re-verified for the rework round only:** territory still exactly 2 files (`lib/core/state/radio_state.dart` 232 lines, `test/core/state/radio_state_test.dart` 290 lines); pathspec-exclusion diff for everything outside `Owned_Paths` empty; both commits tagged (`9731221`, `d05013b`). CX's single rework PLAN.md commit `918b796` touched **only** PLAN.md and **only** the TASK-004 block (8 insertions / 4 deletions: Status, criterion-6 checkbox, one Progress_Note, three Test_Evidence lines, Updated_By/At) — no frontmatter, no other unit's block. No `skip:`/`solo:` markers in the suite.
- **Independent runs reproduced CX's numbers exactly** (Flutter 3.41.6 stable / Dart 3.11.4, clean `git archive` extraction, live worktree untouched): `flutter analyze` → "No issues found!" exit 0; full `flutter test` → **14/14 passed, 0 failed, 0 skipped, exit 0**. Post-merge the full integrated suite was re-run on `master` at `6994a11` (see Test_Evidence) to prove no cross-package regression against TASK-010's audio tests — the branch predated that merge, so a branch-only run could not have seen one.
- **TERRITORY NOW FROZEN — the 12 non-blocking items above are NOT fixed and no longer have an owner.** CX correctly left them alone as instructed. `lib/core/state/**` has no other owner anywhere in the plan, so items 2 (`tuneDelta` + the spec-silent wrap-vs-clamp decision), 3 (`RadioState` lacks every DS §6 flag, STN count and active speaker), 4 (Riverpod import defeats a proof-by-absence purity test), 5 (legacy `StateNotifierProvider` instead of `NotifierProvider`), 6 (`LinkRecovered` misnaming + `LOCAL_FALLBACK` undefined in spec), 7 (`LinkDegraded` accepted from `off`) and 8 (`SetMode` accepted mid-TX) now **require an ORCH-created successor task owning `lib/core/state/**`**, on the 010→011 pattern. Items 3 and 5 are hard prerequisites for TASK-017 and TASK-022 (neither owns this path), and item 2 must be settled before TASK-012/013/014 dispatch. Tracked in frontmatter follow-ups (k) and (m).
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T13:12:13Z

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
**Status:** needs_review
**Assigned_To:** GB
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §8.6, §11 E5 (KRX-040), FR-025
**Owned_Paths:** lib/core/protocol/**, test/core/protocol/**
**Depends_On:** TASK-001
**Description:** Implement the floor-control protocol v1 wire layer under `lib/core/protocol/`: JSON codec for TX_REQ/TX_GRANT/TX_DENY/TX_START/TX_END/PRESENCE/RCHK/RCHK_ACK/EMG/EMG_CLR with the exact fields of TS §8.6, protocol-version tagging with unknown-version tolerance, and the locked timing constants table exported as a single constants module (heartbeat 5 s / 3 misses, lease TOT+2 s, re-election ≤ 500 ms, TX_REQ retry 150 ms ×3, floor-idle debounce 750 ms). Pure Dart, transport-agnostic (data-channel and LiveKit data-message transports plug in later). Round-trip and forward-compat tests.
**Acceptance_Criteria:**
- [x] All ten message types with the exact fields of the TS §8.6 table (e.g. `TX_REQ {peer, prio, ts}`, `TX_GRANT {peer, lease_ms}`, `TX_DENY {peer, reason: BUSY|LOCKOUT}`, `PRESENCE {peer, cs, seq}`)
- [x] Every message carries a protocol version and unknown versions are ignored per TS §8.6 ("All messages carry protocol version; unknown versions are ignored (forward compatibility)")
- [x] `TX_REQ` prio supports 0 normal / 1 emergency per TS §8.6 ("prio: 0 normal, 1 emergency")
- [x] Timing constants exactly match TS §8.6 locked table (5 s/3 missed, TOT+2 s default 62 s, ≤ 500 ms, 150 ms/3 attempts, 750 ms) and are asserted by tests
- [x] Encoding is JSON per TS §8.6 ("JSON over data channels; protobuf reserved for v2")
- [x] Codec round-trip + malformed-input tests green
**Branch:** task/TASK-006-gb
**Started_At:** 2026-08-18T12:16:00Z
**Progress_Notes:**
- [2026-08-18T12:16:00Z] [GB] Claimed TASK-006. Preflight (c8b9872 filesystem check) output:
```
[preflight] TASK-006 Owned_Paths inspected in C:\CLAUDECODE_TOOLSETS\wt-grok-walkietalkie-keryx
[preflight] 2 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
  GLOB   lib/core/protocol/**  -> matches nothing yet (new territory)
  GLOB   test/core/protocol/**  -> matches nothing yet (new territory)
[preflight] Paste this output into your first Progress_Note as the c8b9872 filesystem check.
```
New territory under lib/core/protocol/** and test/core/protocol/**. Implementing §8.6 codec, versioned envelope, FloorTiming constants.
- [2026-08-18T12:19:13Z] [GB] Protocol v1 complete on `task/TASK-006-gb` (commit ccfbb01). Sealed FloorMessage × 10 types, FloorCodec envelope `{v:1,t,...}` (unknown v/t and malformed → null, never throws), FloorTiming locked table. Implementation pins (spec-silent types): `ts` = Unix epoch ms; `quality` = S-meter int (FR-066 / §8.9). Ready for review.
**Artifacts:**
- `lib/core/protocol/protocol.dart`
- `lib/core/protocol/messages.dart`
- `lib/core/protocol/codec.dart`
- `lib/core/protocol/timing.dart`
- `lib/core/protocol/README.md`
- `test/core/protocol/codec_test.dart`
- `test/core/protocol/timing_test.dart`
**Test_Evidence:**
- [2026-08-18T12:18:30Z] [GB] `flutter analyze` — passed: No issues found! (ran in 4.6s).
- [2026-08-18T12:18:30Z] [GB] `flutter test --reporter expanded` — 40/40 passed, exit 0. New: codec 12 + timing 5; existing audio 22 + widget 1 unchanged.
**Review_Findings:** —
**Blocked_Reason:** —
**Updated_By:** GB
**Updated_At:** 2026-08-18T12:19:13Z

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
**Status:** done
**Assigned_To:** GB
**Priority:** high
**Spec_References:** specs/KERYX_Product_Technical_Spec_v1.1.md §7.1, §7.2, §11 E3 (KRX-021, KRX-024), FR-006, FR-062; specs/keryx-face-prototype.html (audio engine section)
**Owned_Paths:** lib/core/audio/**, test/core/audio/**, assets/sfx/**
**Depends_On:** TASK-001
**Description:** The SFX half of the audio stack under `lib/core/audio/`: a dual-bus mixer (Voice bus / SFX bus), the §7.1 asset manifest as a typed registry loading from `assets/sfx/v1/`, seamless-loop static beds with squelch-level crossfade, ducking rules (SFX ducks voice −3 dB ≤ 150 ms; voice never ducks for cosmetics), and roger-beep variant playback (off/classic K/dual-tone). Commissioned audio (KRX-020) is out of scope — generate placeholder synthesized WAVs (48 kHz 16-bit, −16 LUFS target; emergency −12 LUFS) mirroring PT's synthesis so the manifest is exercised end-to-end. Tests via a fake audio sink asserting bus routing and ducking envelopes.
**Acceptance_Criteria:**
- [x] Two buses exist and SFX never traverses the network per TS §7.2 ("Two buses: Voice bus (network audio) and SFX bus (local assets). SFX never traverses the network")
- [x] All SFX play from local assets on a dedicated bus per P4 ("All SFX play from local assets on a dedicated bus — instant and identical regardless of network conditions")
- [x] Every §7.1 manifest asset has a registry entry and a placeholder file (squelch_open/tail, static_bed_1/2/3, tune_burst, scan_tick, roger_k/dual/moto, deny_buzz, tot_warn/cut, link_lost/up, emg_alert, rchk_ok, key_click, knob_tick, slider_thunk, power_on/off)
- [x] Ducking: "SFX ducks voice by −3 dB during overlap ≤ 150 ms; voice never ducks for cosmetics" per TS §7.2
- [x] Static beds loop seamlessly and crossfade with the squelch knob per TS §7.1 ("Seamless loop points; squelch knob crossfades")
- [x] Assets are 48 kHz 16-bit WAV normalised to −16 LUFS, emergency at −12 LUFS, per TS §7 preamble
- [x] Mixer/ducking unit tests green
**Branch:** task/TASK-010-gb
**Started_At:** 2026-08-18T10:25:46Z
**Progress_Notes:**
- [2026-08-18T10:26:30Z] [GB] Claimed TASK-010. Preflight (c8b9872 filesystem check) output:
```
[preflight] TASK-010 Owned_Paths inspected in C:\CLAUDECODE_TOOLSETS\wt-grok-walkietalkie-keryx
[preflight] 3 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
  GLOB   lib/core/audio/**  -> matches nothing yet (new territory)
  GLOB   test/core/audio/**  -> matches nothing yet (new territory)
  GLOB   assets/sfx/**  -> matches nothing yet (new territory)
[preflight] Paste this output into your first Progress_Note as the c8b9872 filesystem check.
```
New territory. `assets/sfx/v1/.gitkeep` exists from TASK-001 (empty glob because only .gitkeep). Implementing dual-bus mixer, §7.1 manifest, placeholder WAVs, ducking, bed crossfade. pubspec is frozen with no playback package — engine will use an injectable AudioSink; real device playback is the host's job, not flutter_webrtc.
- [2026-08-18T10:34:04Z] [GB] SFX engine complete on `task/TASK-010-gb` (commit a0cc2c5). Dual-bus mixer + DuckController (−3 dB / ≤150 ms; cosmetics/beds do not duck), §7.1 typed manifest, seeded placeholder WAV generator, roger off/K/dual/moto. No pubspec change; host injects AudioSink.
**Artifacts:**
- `lib/core/audio/audio.dart`
- `lib/core/audio/audio_bus.dart`
- `lib/core/audio/audio_mix.dart`
- `lib/core/audio/audio_sink.dart`
- `lib/core/audio/bed_mixer.dart`
- `lib/core/audio/ducking.dart`
- `lib/core/audio/roger.dart`
- `lib/core/audio/sfx_engine.dart`
- `lib/core/audio/sfx_id.dart`
- `lib/core/audio/sfx_manifest.dart`
- `assets/sfx/README.md`
- `assets/sfx/tools/generate_placeholders.py`
- `assets/sfx/v1/*.wav` (22 placeholders)
- `test/core/audio/sfx_engine_test.dart`
- `test/core/audio/bed_mixer_test.dart`
- `test/core/audio/manifest_and_assets_test.dart`
- `test/core/audio/wav_lufs.dart`
**Test_Evidence:**
- [2026-08-18T10:33:20Z] [GB] `flutter test --reporter expanded` — 23/23 passed (22 audio + 1 existing widget). Suites: bed_mixer 6, manifest_and_assets 5, sfx_engine 11, widget_test 1.
- [2026-08-18T10:33:50Z] [GB] `flutter analyze` — passed: No issues found! (ran in 3.3s).
- [2026-08-18T11:00:47Z] [ORCH] Reproduced independently at a0cc2c5 via `git archive` into a scratchpad (GB's worktree left untouched — it carried an uncommitted `dossiers/TASK-010.md` edit): full Dart suite 23 passed / 0 failed / 0 skipped, exit 0; breakdown bed_mixer 6 + manifest_and_assets 5 + sfx_engine 11 + widget_test 1 — matches GB's claim exactly. `flutter analyze` → "No issues found!" exit 0. Flutter 3.41.6 stable / Dart 3.11.4.
**Review_Findings:** APPROVED first-pass, merged as 1a3eadf. Territory clean — 38 files, 1356 insertions / 0 deletions, single commit `a0cc2c5` tagged `[TASK-010]`; pathspec-exclusion diff (`-- . ':(exclude)lib/core/audio' ':(exclude)test/core/audio' ':(exclude)assets/sfx'`) returns empty. `pubspec.yaml` correctly untouched (frozen) — TASK-001's existing `assets: - assets/sfx/v1/` already bundles the 22 WAVs while correctly NOT shipping `assets/sfx/tools/*.py` or the README into the APK. c8b9872 preflight present verbatim in the first Progress_Note (3 globs, new territory). PLAN.md discipline clean: f746f3c / 6f9cd2e touch only the TASK-010 block — no frontmatter, no other unit's block. All 7 acceptance criteria verified against independently quoted spec text (TS §7 L238, §7.1 L240-255, §7.2 L257-262, P4 L44, §11 E3 L434-439, FR-006 L111, FR-062 L146), not GB's summary:
  1. **Two buses / SFX never on the network** — `AudioBus` has exactly two members; every `SfxEngine` code path passes `AudioBus.sfx`; `busFor()` is constant-`sfx`; `lib/core/audio/**` imports no WebRTC/LiveKit/network symbol and performs no I/O other than through the injected `AudioSink`. Tests assert `everyElement(AudioBus.sfx)` across both one-shots and loops.
  2. **All SFX from local assets (P4 L44)** — `assetPath` is derived from `AudioMix.assetRoot` (`assets/sfx/v1/`) and `play()` hard-guards `entry.isLocalAsset` before dispatch.
  3. **Manifest completeness** — §7.1's table (L244–255) enumerates exactly 22 distinct asset ids; `SfxId` has exactly 22 members whose stems are byte-identical to the spec's, `SfxManifest.entries` covers all 22 with no extras (test asserts set equality both ways), and all 22 `.wav` files exist. §7.1's stated duration bounds independently checked against the real WAV headers, not the manifest: `squelch_open` 60.0 ms / `squelch_tail` 70.0 ms both inside L244's 40–80 ms; `scan_tick` 25.0 ms ≤ L247's 30 ms.
  4. **Ducking (§7.2 L261)** — −3 dB and 150 ms are named `AudioMix` constants, not literals; duck window = min(asset duration, 150 ms); `SfxId.ducksVoice` excludes beds and cosmetics; `setBusGainDb` is only ever called with `AudioBus.voice`, and the test pins `sink.busGainsDb[AudioBus.sfx] == 0` so the reverse direction is proven absent.
  5. **Seamless beds + squelch crossfade (§7.1 L245)** — `seamless_loop()` wraps by crossfading the head against a 20 ms overrun tail so the file wraps continuously; measured |first−last| is 0.038 / 0.025 / 0.026 full-scale for beds 1/2/3 (test bound 0.08). `BedMixer.gainsFor()` maps 0..1 across silence→bed1→bed2→bed3 with NaN and out-of-range rejection.
  6. **48 kHz / 16-bit / −16 LUFS, emergency −12 LUFS (§7 L238)** — all 22 WAVs independently header-parsed in Python: 48000 Hz, 1 channel, 16-bit, durations matching the manifest to the sample, peaks 0.155–0.492 (no clipping; the generator's 0.99 peak ceiling never engaged, so no sound had its LUFS pulled off target). LUFS is genuinely implemented, not asserted in a comment: the generator carries the correct BS.1770-4 K-weighting biquads (48 kHz pre-filter 1.53512485958697/−2.69169618940638/1.19839281085285 over 1/−1.69065929318241/0.73248077421585, RLB 1/−2/1 over 1/−1.99004745483398/0.99007225036621, −0.691 offset), and `test/core/audio/wav_lufs.dart` re-implements the same measurement in Dart and re-measures every file from its bytes with a 1.25 dB tolerance. Re-running the committed generator produced −16.00 LUFS for all 21 SFX and −12.00 for `emg_alert`.
  7. **Tests green** — reproduced independently (see Test_Evidence above).
  **Bit-stability + provenance verified:** re-ran `assets/sfx/tools/generate_placeholders.py` from the committed tree into a scratch dir and compared `git hash-object` against all 22 committed blobs — 0 mismatches. The shipped assets provably come from the shipped generator.
  **Prototype mirroring verified sound-by-sound against `specs/keryx-face-prototype.html` L184-229, not taken on trust:** `roger_k` = PT's `tone(1180,.09,'square')` with PT's exact 6 ms attack / 20 ms release; `deny_buzz` = PT's saw 180 Hz + 150 Hz at +110 ms, 90 ms each; `power_on` = PT's 520/780/1040 sine at 0/70/140 ms (70/70/110 ms); `power_off` = PT's 780@0 + 430@+70; `tot_warn` = PT's 1400 Hz square ×2 at 0 and +120 ms; `emg_alert` = PT's 4× (1600/1100 Hz square, 100 ms) at 220 ms spacing; `tune_burst` = PT's `noiseBurst(.30,.45,2200)` at PT's Q 0.6; `scan_tick`/`knob_tick` at PT's 4200 Hz; and `static_bed_2` is PT's hiss bed exactly (2 s noise, bandpass 1800 Hz Q 0.7), with beds 1 (2500/0.8) and 3 (1200/0.5) as the brighter/darker intensity variants PT lacks. This is a faithful mirror, not arbitrary synthesis.
  **Resource cleanup is correct** (the Flutter bug class this task was most exposed to): `SfxEngine` owns no `Timer`, `Stream`, or subscription — all device lifetime belongs to the injected sink — and `dispose()` is idempotent, calls `stopAll()`, restores voice gain to 0 dB, and makes every subsequent call throw `StateError` (tested). Input validation present throughout (`gainsFor` rejects NaN/out-of-range; `play()` rejects loop beds and non-local paths; `lookup()` throws on a missing manifest entry).
  NON-BLOCKING FOLLOW-UPS (do NOT reopen this task — territory passes to TASK-011, which should absorb 1–5): (1) **Duck release needs an external driver.** `DuckController` expires on its injected clock and the `voiceGainDb`/`isVoiceDucked` getters self-expire correctly, but `SfxEngine` only emits the restoring `setBusGainDb(voice, 0)` inside `tick()`, and nothing schedules `tick()` — no timer, no stream. A host that polls the getters is safe; a host that reacts to sink events will leave the voice bus at −3 dB indefinitely after any programme SFX. Highest-priority item. (2) **`tune_burst` ducking direction is a genuine spec self-contradiction.** §7.1 L246 says tune_burst "Ducks under incoming audio" and FR-006 L111 says the swell "ducks into the new channel's live audio or settles to the ambient hiss floor" — both describe the *burst* being attenuated by voice. §7.2 L261 (which criterion 4 quotes) says the opposite. GB implemented §7.2 only; nothing attenuates tune_burst when voice arrives. ORCH should settle this in the spec text before TASK-011 dispatches, since TASK-011 owns the hiss-floor half of FR-006. (3) **KRX-024's 60 ms in-band end-of-TX marker has no representation** — FR-062 L146 requires it and the dossier asked for a playback-side hook; there is no constant, no `SfxId`, and no hook in `lib/core/audio/`. §7.1 also has no asset id for it, so this is a spec gap as well as a code gap; the TX/voice-path task must own it. (4) **FR-062 names the fourth roger variant "custom pack" while §7.1 L248 ships `roger_moto`.** GB reconciled to the real assets (`RogerVariant.moto`), which is the right call, but user-supplied packs are unimplemented and the spec now carries two names for the same slot — pick one. (5) **README and the generator docstring both claim "equal-power" crossfades; the code is linear.** `seamless_loop()` is `head[i]*(i/n) + tail[i]*(1−i/n)` and `BedMixer.gainsFor()` is likewise linear-amplitude. For uncorrelated noise beds that yields a ~3 dB power dip mid-crossfade, so the squelch knob will audibly sag between beds. Wrap continuity still measures fine, so this is a quality/doc defect, not a break — switch to a sqrt law and fix both docs in TASK-011. (6) **The prototype's `grant()` tone has no §7.1 asset id.** PT L223 `tone(900,.045,'sine',.12)` fires on the critical ≤80 ms key-up path (PT L349, comment "grant tone+haptic = the ≤80ms perceived key-up") but the manifest enumerates nothing for it, so `SfxId` has nothing either; `rchk_ok` (880 Hz sine, 120 ms) is acoustically close but is the radio-check confirmation, a different event. Whoever builds PTT will need this added to §7.1 and to the manifest. (7) **LUFS is ungated.** The K-weighting is correct but neither implementation applies BS.1770 gating or 400 ms block integration, so for an 8 ms `knob_tick` the number is a proxy rather than a standards-conformant measurement. README says "ungated" honestly and KRX-020 replaces the pack anyway — fold a real gated-measurement requirement into the commissioning brief. (8) **Nothing in the repo can actually make a sound yet.** `AudioSink` has no concrete implementation and pubspec carries no player package; GB correctly flagged this rather than unfreezing pubspec, but the host-side sink needs its own task with a pubspec change. (9) Cosmetic: `SfxEngine.busFor()` contains `final _ = id;` purely to silence an unused-parameter lint.
**Blocked_Reason:** —
**Updated_By:** ORCH
**Updated_At:** 2026-08-18T11:00:47Z

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
