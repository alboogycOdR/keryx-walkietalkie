# Two-phone field test — Keryx

Relay-side operator runbook (bring-up, health, triage) plus a reserved
slot for the app-side script.

**Relay-side sections (this file through the failure-triage table): TASK-040
(GB).** Do not rewrite them in later tasks; append.

**App-side operator script (LOCAL / LINKED / Event QR on two phones): TASK-039.**
Append after the HTML comment marker at the bottom. Do not edit headings
above that marker.

This file lives in `ops/` because builders cannot write `docs/**`.

---

## 0. Scope split

| Section | Owner | Needs the Flutter app? |
|---|---|---|
| §1 Env / secret checklist | TASK-040 | no |
| §2 VPS bring-up | TASK-040 | no |
| §3 Local bring-up (dev machine) | TASK-040 | no |
| §4 Health checks before any phone | TASK-040 | no |
| §5 Failure-triage table | TASK-040 | no |
| App-side field script | TASK-039 | yes (`Depends_On: TASK-040`) |

LINKED (TS §8.4) is: derive `roomId` → `POST https://DOMAIN/token` → join
LiveKit with the minted JWT. LOCAL stays serverless (D2) and does not need
this stack.

---

## 1. Env / secret checklist

Copy, do not commit. `relay/.env` and `token-svc/.env` are gitignored.

### `relay/.env` (from `relay/.env.example`)

| Variable | Required | Notes |
|---|---|---|
| `DOMAIN` | yes | Public hostname. ACME will not issue for `localhost`. |
| `TURN_DOMAIN` | yes | A/AAAA on the same VPS as `DOMAIN`. |
| `ACME_EMAIL` | yes | Mailbox someone reads (cert expiry). |
| `EXTERNAL_IP` | yes | Public IPv4. Not `127.0.0.1` on a VPS — coturn advertises this. |
| `LIVEKIT_API_KEY` | yes | `openssl rand -hex 16` |
| `LIVEKIT_API_SECRET` | yes | `openssl rand -hex 32` — must match token-svc |
| `TURN_SHARED_SECRET` | yes | `openssl rand -hex 32` |
| `TURN_REALM` | yes | Usually `TURN_DOMAIN` |
| `TOKEN_SVC_UPSTREAM` | yes | Default `127.0.0.1:8080` |

### `token-svc/.env` (from `token-svc/.env.example`)

| Variable | Required | Notes |
|---|---|---|
| `LIVEKIT_API_KEY` | yes | **Identical** to relay |
| `LIVEKIT_API_SECRET` | yes | **Identical** to relay |
| `EVENT_TOKEN_SECRET` | yes | HMAC for Event-QR tokens; shared with the app, **not** with LiveKit |
| `TOKEN_TTL_SECONDS` | no | default `300` |
| `RATE_LIMIT_MAX` | no | default `30` per IP per window |
| `RATE_LIMIT_WINDOW_SECONDS` | no | default `60` |
| `RATE_LIMIT_TTL_SECONDS` | no | default `3600`, must be ≤ 3600 (TS §8.7) |

Generate a matching local pair (never a VPS pair — those come from the
operator's secret store):

```powershell
python relay\scripts\gen_local_env.py
```

Work `relay/HARDENING.md` on every VPS. Tick a box only when the control is
actually in place.

---

## 2. VPS bring-up

Target: one Linux VPS (clawsrv-class, 4 vCPU / 8 GB is enough), Ubuntu
22.04/24.04, Docker Engine + Compose v2. This is the D2 / KRX-050 topology.

### DNS / TLS prerequisites localhost cannot prove

1. `A` (and `AAAA` if used) for `DOMAIN` and `TURN_DOMAIN` pointing at the
   VPS **public** IP. Caddy ACME HTTP-01 needs `DOMAIN` to resolve from the
   public internet to this box, with **:80 and :443 reachable from WAN**.
2. Let's Encrypt will **not** issue a certificate for `localhost`,
   `127.0.0.1`, or an `.example.com` placeholder. A laptop `compose up` of
   the `caddy` service with `DOMAIN=localhost` is expected to fail ACME;
   that is not a compose bug.
3. `EXTERNAL_IP` must be the VPS public IPv4. `127.0.0.1` makes coturn
   advertise a blackhole; NFR-05 (LINKED connect ≥ 97% with TURN) is a VPS
   measurement, not a localhost one.
4. Firewall: follow `relay/README.md` port table. **Do not** allow WAN to
   `:7880` (LiveKit), `:6379` (Redis), or `:8080` (token-svc). Caddy on
   `:443` is the only public signaling/mint path (`wss://DOMAIN`,
   `https://DOMAIN/token`).
5. TLS 1.3 only is in `relay/Caddyfile` (`protocols tls1.3`). Confirm on the
   VPS with `nmap --script ssl-enum-ciphers -p 443 $DOMAIN` after ACME
   succeeds — not confirmable on localhost.

### Command sequence (VPS)

```bash
# 1. tree on disk
sudo mkdir -p /opt/keryx && sudo chown "$USER:$USER" /opt/keryx
# copy relay/ and token-svc/ onto the box (git clone or rsync)

# 2. secrets
cd /opt/keryx/relay
cp .env.example .env
# fill DOMAIN, TURN_DOMAIN, ACME_EMAIL, EXTERNAL_IP, keys, TOKEN_SVC_UPSTREAM
cd /opt/keryx/token-svc
cp .env.example .env
# copy LIVEKIT_API_KEY / LIVEKIT_API_SECRET from relay/.env
# EVENT_TOKEN_SECRET=$(openssl rand -hex 32)

# 3. render + validate (no live traffic)
cd /opt/keryx/relay
python3 scripts/render_config.py --env .env
docker compose --env-file .env config
./scripts/validate.sh          # or: python3 tests/test_relay_config.py

# 4. firewall, then stack
# (ufw commands: relay/README.md)
docker compose --env-file .env up -d
docker compose ps

# 5. token-svc on loopback only — not a compose service
cd /opt/keryx/token-svc
docker build -t keryx-token-svc .
docker run -d --name keryx-token-svc --restart unless-stopped \
  -p 127.0.0.1:8080:8080 --env-file .env keryx-token-svc

# 6. health (see §4)
```

Clients: relay URL `wss://DOMAIN`, token URL `https://DOMAIN/token`
(TASK-036 derivation). `--dart-define=KERYX_RELAY_URL=...` is TASK-039.

Note for TASK-039 / session wiring: the public mint URL is `POST
https://DOMAIN/token`. Dart `TokenClient` appends `/token` to its `baseUrl`.
Pass the origin (`https://DOMAIN`) into `TokenClient`, not
`resolvedTokenServiceUrl` (which already includes `/token`), or the app
will POST `/token/token`.

---

## 3. Local bring-up (dev machine)

Docker is enough to prove LiveKit accepts a token-svc JWT. It is **not**
enough to prove ACME, TURN-vs-NAT, or `https://DOMAIN/token`.

Host networking (`network_mode: host` in compose) is required for WebRTC UDP
on a Linux VPS. On Docker Desktop for Windows/Mac, host-network is the
**Linux VM namespace**, not Windows localhost — `curl http://127.0.0.1:7880`
from PowerShell is expected to fail even when the stack is healthy. Prove
from `docker run --rm --network host …` instead. Treat a failed `caddy`
container on localhost as expected (ACME); do not "fix" production compose
to make ACME optional.

```powershell
cd relay
python scripts\gen_local_env.py
python scripts\render_config.py --env .env
powershell -ExecutionPolicy Bypass -File scripts\validate.ps1
# validate.ps1 renders .env.example into a temp dir (does not clobber generated/).
# Re-render from .env before `up` if you ran validate after gen_local_env:
python scripts\render_config.py --env .env

# skip caddy — ACME cannot issue for DOMAIN=localhost
docker compose --env-file .env up -d redis livekit coturn
docker compose ps

cd ..\token-svc
docker build -t keryx-token-svc .
docker run -d --name keryx-token-svc --network host --env-file .env keryx-token-svc
# VPS (Linux): prefer -p 127.0.0.1:8080:8080 so WAN cannot hit :8080.
# Docker Desktop: --network host shares the VM loopback with LiveKit.

cd ..\relay
docker run --rm --network host --env-file ..\token-svc\.env `
  -v ${PWD}\scripts\e2e_linked_proof.py:/e2e.py:ro `
  keryx-token-svc python /e2e.py --rate-limit
```

Optional HTTP stand-in for the Caddy `/token` matcher (same path, no TLS):

```powershell
docker run --rm --name keryx-token-edge --network host `
  -e TOKEN_SVC_UPSTREAM=127.0.0.1:8080 `
  -e LIVEKIT_UPSTREAM=127.0.0.1:7880 `
  -v ${PWD}/Caddyfile.local:/etc/caddy/Caddyfile:ro `
  caddy:2.9.1-alpine

docker run --rm --network host --env-file ..\token-svc\.env `
  -v ${PWD}\scripts\e2e_linked_proof.py:/e2e.py:ro `
  keryx-token-svc python /e2e.py --edge-url http://127.0.0.1:8880/token
```

Stop:

```powershell
docker stop keryx-token-svc keryx-token-edge
docker compose --env-file .env down
```

---

## 4. Health checks before any phone

Run these until they are green. A phone that shows `NO LINK` before this
list is green is not a phone bug.

| Check | Command | Expect |
|---|---|---|
| Compose config | `docker compose --env-file .env config` | exit 0, services `{livekit,redis,caddy,coturn}` |
| Relay unit tests | `python tests/test_relay_config.py` | all pass |
| token-svc unit tests | `python -m pytest` in `token-svc/` | all pass |
| Redis | `docker compose exec redis redis-cli ping` | `PONG` (host-network: `redis-cli -h 127.0.0.1 ping`) |
| LiveKit HTTP | `curl -sS -D- http://127.0.0.1:7880/` | LiveKit speaks (200/404, not connection refused) |
| token-svc health | `curl -fsS http://127.0.0.1:8080/healthz` | `{"ok": true}` |
| Direct mint | `POST http://127.0.0.1:8080/token` JSON `{room_id, callsign}` | 200 `{token, identity, ttl_seconds}` |
| Caddy `/token` (VPS) | `POST https://DOMAIN/token` same JSON | 200, **not** `503 token-svc not wired` |
| Caddy `/token` (local) | `POST http://127.0.0.1:8880/token` via `Caddyfile.local` | 200 |
| JWT join | `python relay/scripts/e2e_linked_proof.py` | minted JWT → LiveKit `/rtc` 101 **and** identity in `ListParticipants` |
| Rate limit | `python relay/scripts/e2e_linked_proof.py --rate-limit` | HTTP 429 `rate_limited` after `RATE_LIMIT_MAX` |
| TLS (VPS only) | `curl -fsSI https://DOMAIN/` | TLS 1.3, Caddy, not a browser MITM warning |
| TURN (VPS only) | coturn logs + a phone on mobile data | ICE `relay` candidate; NFR-05 is a field number, not a curl |

`e2e_linked_proof.py` is the TASK-040 join evidence: it mints through
token-svc, proves a garbage JWT is refused, holds a websocket upgrade with
the minted JWT, and checks LiveKit RoomService `ListParticipants` for that
identity. That is a real join, not "the mint endpoint returned 200".

---

## 5. Failure-triage table

Phone symptoms below are what TASK-039 will see. Match the log column
before changing compose.

| Symptom | Likely cause | What to pull |
|---|---|---|
| `NO LINK` immediately, never a token HTTP status | Relay URL wrong / DNS / :443 closed / Caddy down | `docker compose ps`; `docker compose logs caddy`; `curl -vI https://DOMAIN/` |
| Token HTTP **503** body `token-svc not wired` | Old Caddyfile (pre-TASK-040) still deployed | `relay/Caddyfile` must `reverse_proxy {$TOKEN_SVC_UPSTREAM}`; recreate caddy |
| Token HTTP **connection refused** on `:8080` | token-svc not running, or bound only in another netns | `docker ps -a --filter name=keryx-token-svc`; `curl http://127.0.0.1:8080/healthz` |
| Token HTTP **4xx** `invalid_request` | Client body failed validation (room_id not 16-char base32, bad callsign) | token-svc log line `POST /token 422` (no body — by design, TS §8.7) |
| Token HTTP **403** `invalid_event_token` / `expired_event_token` | Event QR HMAC/exp mismatch (`EVENT_TOKEN_SECRET` ≠ app) | Compare secrets; do **not** log the token |
| Token HTTP **429** `rate_limited` | Per-IP cap (`RATE_LIMIT_MAX` / window). Expected under hammering | token-svc log `rate_limit limited=True count=…` (no IP in the log) |
| Token HTTP **5xx** other than the old 503 | token-svc crash / missing env (`LIVEKIT_API_*`) | `docker logs keryx-token-svc`; process exits if required env is empty |
| Token 200 but LiveKit join fails (401 on `/rtc`) | API key/secret **mismatch** between token-svc and LiveKit | Diff the two `.env` files; `docker compose logs livekit` |
| Token 200, `/rtc` 101, then ICE fail on mobile data | TURN not advertised / `EXTERNAL_IP` wrong / 3478/relay UDP closed | `docker compose logs coturn`; `docker compose logs livekit`; ufw UDP ranges |
| Token 200, join OK on Wi-Fi, fail on LTE | Classic NAT; TURN path is the NFR-05 lever | coturn `external-ip`, 3478/udp + 52000–52999/udp open |
| Caddy ACME fail / TLS warning | DNS not pointing here, :80 closed, or `DOMAIN=localhost` | `docker compose logs caddy`; check A record from a phone (not from the VPS) |
| Redis unhealthy, LiveKit restart loop | Redis not on `127.0.0.1:6379` (host-network assumption) | `docker compose logs redis`; `ss -ltnp \| grep 6379` |
| Two phones, one hears nothing, floor seems granted | Not this stack — floor protocol / TASK-039 script | App logs; do not enable LiveKit media dumps (TS §8.7) |

Privacy (TS §8.7): do not raise LiveKit `pion_level` above `error` in
production, do not tcpdump the RTC range except in a time-boxed incident,
and wipe pcaps. token-svc logs method/path/status and rate-limit counters
only — never callsigns, room IDs, or JWTs.

---

<!-- TASK-039 APP-SIDE START -->

## App-side field script (TASK-039)

Appended by TASK-039. Do not rewrite §0–§5 (relay bring-up, health, triage).
Those sections stay TASK-040's. This half is the operator script for two
phones running the **release** APK of the integrated app.

**Do not run this until §4 is green** if the script uses LINKED. LOCAL
(§8) does not need the relay.

Phones are **A** (first, stays on Wi-Fi) and **B** (second; Wi-Fi for
LOCAL / Event QR, mobile data for LINKED). Both start on CH 01 · code 00
(app default). Callsigns are assigned at first boot — write them down;
they appear in the FR-067 station list.

SFX names below are the `SfxId` stems under `assets/sfx/v1/` as projected
by `lib/services/sound/sfx_projection.dart` (TASK-034). If a step is
silent, that is a fail, not "maybe the volume is down" — check the
phone's media volume and that `power_on.wav` already played at launch.

---

### 6. Build and install

Replace `DOMAIN` with the VPS hostname from §1. Bake the relay in so a
fresh install is already LINKED-capable without typing URLs on a phone.

```powershell
# From the repo root. Release APK, R8 on (android/app/build.gradle.kts).
# Debug-keystore fallback is expected when android/key.properties is absent
# (see android/SIGNING.md). That APK is fine for this script; it is not a
# Play upload.

flutter build apk --release `
  --dart-define=KERYX_RELAY_URL=wss://DOMAIN `
  --dart-define=KERYX_TOKEN_URL=https://DOMAIN
```

Install:

```powershell
$apk = "build\app\outputs\flutter-apk\app-release.apk"
adb -s <SERIAL_A> install -r $apk
adb -s <SERIAL_B> install -r $apk
```

`adb devices -l` to list serials. Allow USB install / unknown sources.

#### Token URL — do not add `/token` in the define

`TokenClient._resolveTokenUri` appends `token` to whatever base it is
given (`lib/services/linked/token_client.dart`). The session host passes
`KeryxSettings.resolvedTokenServiceUrl` as that base
(`RadioSessionController._startLinked`).

| `--dart-define` / back-panel TOKEN URL | Actual POST | Result |
|---|---|---|
| `https://DOMAIN` (origin only) | `https://DOMAIN/token` | correct (Caddy `@token`) |
| `https://DOMAIN/token` | `https://DOMAIN/token/token` | 404 / fail → FR-045 `NO LINK` |
| *(empty; derived from `wss://DOMAIN`)* | `https://DOMAIN/token/token` | same fail — derivation already includes `/token` |

TASK-040 already flagged this (`§2` note: pass the origin into
`TokenClient`, not `resolvedTokenServiceUrl`). Leave the back-panel
TOKEN URL **blank** only if the dart-define is the origin; if you type
a TOKEN URL on the phone, type `https://DOMAIN` with **no** path.

RELAY URL is `wss://DOMAIN` (scheme allow-list is `wss` only).

#### Signing check before you ship the APK to anyone else

```powershell
git check-ignore -v android/key.properties
# expect: android/.gitignore:<n>:key.properties    android/key.properties
Select-String -Path android/key.properties,android/*.jks,android/*.keystore -Pattern . -ErrorAction SilentlyContinue
# expect: no files (they are gitignored and must not be in the tree)
```

#### APK size (measured this task, not TASK-033's debug figure)

`flutter build apk --release` (this machine, 2026-08-22T20:40Z):
`build/app/outputs/flutter-apk/app-release.apk` = **119,739,048 bytes
(114.19 MB)**, sha256
`F105033786135CC4A813288DF06282CAC7160431EA3CE5C33960A93CDFE3C3A7`.
JNI dirs in the APK: `arm64-v8a`, `armeabi-v7a`, `x86_64`. Signed with
the debug keystore (no `android/key.properties` on this checkout). Do
not reuse TASK-033's 211 MB / 152 MB debug numbers.

---

### 7. Launch checklist (each phone)

1. Media volume ~70%. Do not mute.
2. Launch **keryx**. The radio auto-powers on (`PowerOn` in `FaceScreen._boot`).
3. Hear **`power_on.wav`**. If silent, stop — SFX path is dead (TASK-033
   sink / TASK-034 projection / volume).
4. LCD shows CH 01. Status strip shows `STN n · AUTO` (default mode
   FR-040).
5. **Permissions (TASK-038 may still be landing):** if Android prompts
   for Microphone / Nearby devices / Notifications, grant Microphone at
   minimum. A denied mic is a dead radio (FR-104). Nearby is required
   for LOCAL discovery (FR-041) on API 33+.
6. Write down the callsign shown on the glass / station list.

---

### 8. MANUAL — settings key actually reaches `BackPanelScreen`

This is the check TASK-037 review finding (f) required. `lib/app.dart`
registers `backPanelRouteName` (`/settings`); the widget-test harness
never pumps `KeryxApp`, so **nothing in `flutter test` covers this
route**. If the map is wrong, the ⚙ key does nothing and the suite
stays green.

| Step | Action | Expect | FR / note |
|---|---|---|---|
| 8.1 | On A, tap **⚙** (rightmost of `MON / SCAN / SAY AGN / ⚙`) | A full-screen back panel titled as settings, not a toast, not a no-op | FR-100; `PttKeyRow` → `Navigator.pushNamed(backPanelRouteName)` |
| 8.2 | Change **RADIO MODE** from AUTO → LOCAL. Pop back (system Back) | Face status strip now reads `LOCAL` (not AUTO) | FR-040; settings persist + session rebuild |
| 8.3 | ⚙ again. Change **TOT** from 60 → 30. Back. | Value still 30 on re-entry. Used in §9 TOT step so you are not holding PTT for a minute | FR-023 range 30–120 s |
| 8.4 | Repeat 8.1–8.2 on B (mode LOCAL) | Both phones LOCAL before §9 | FR-040 |

If ⚙ does nothing, **stop the field test** — integration is not
installed as the real app shell. Do not paper over it by opening
settings some other way.

---

### 9. LOCAL script — same Wi-Fi (no relay)

Both phones on the **same LAN**, airplane-mode off, Wi-Fi on, mobile
data optional. Mode **LOCAL** (from §8). Channel **01**, code **00**.

| Step | Action | Expect | SFX | FR |
|---|---|---|---|---|
| 9.1 | Both idle on CH 01 for ~15 s | Each status strip `STN` count ≥ 1 (the other station). Tap `STN n · LOCAL` to flip the glass (FR-067); the other callsign is listed. Auto-flips back after 5 s | none required (optional `tune_burst.wav` if you retuned) | FR-041 mDNS `_keryx._tcp`; FR-042 serverless; FR-067 |
| 9.2 | If STN stays 0 | Same SSID? API 33 Nearby Wi-Fi granted? Channel+code match? See §5 "two phones, one hears nothing" | — | FR-041 |
| 9.3 | A: hold PTT. Speak. Release | A: TX LED / edge-glow while held. B: RX (grille / LCD RX telltale) while A speaks, then idle | A grant: **`key_click.wav`** (GrantTone → cosmetic `SfxId.keyClick`, TASK-034 interim). B RX start: **`squelch_open.wav`**. A release / B RX end: **`squelch_tail.wav`** then roger **`roger_k.wav`** (default Classic) | FR-020 hold-to-talk; FR-026 TX feedback |
| 9.4 | B: hold PTT. Speak. Release | Reverse of 9.3 — both directions | same mapping, roles swapped | FR-020 |
| 9.5 | **Busy lockout:** A holds PTT (still talking). B taps PTT | B does **not** TX (no red TX LED). A keeps the floor | B: **`deny_buzz.wav`**. No grant click on B | FR-022 (on by default) |
| 9.6 | A releases. B PTT now | B gets the floor | B: **`key_click.wav`**; A: **`squelch_open.wav`** | FR-022 clears when floor free |
| 9.7 | **TOT:** A holds PTT and does not release. TOT = 30 s if you set it in §8.3, else 60 s | At T−5 s A shows TOT warning. At 0 A is cut, floor released, B hears the drop | T−5 s: **`tot_warn.wav`**. Cut: **`tot_cut.wav`**. B then **`squelch_tail.wav`** + roger | FR-023 |
| 9.8 | **Emergency:** B holds PTT. A **long-presses** the orange **EMG** side key | A should pre-empt, pin `EMG` telltale. B should lose the floor (busy lockout overridden). A long-press again to clear | A pin: **`emg_alert.wav`**. Grant on A: **`key_click.wav`** | FR-025 |
| 9.9 | Record FR-025 honestly | If **both** stay TX (double-grant) | — | **PARKED 2026-08-21** — soak ~40/500 seeds, no successor task. Log the seed-equivalent (who was talking, who pressed EMG) and continue. Do not chase in this script |
| 9.10 | **NFR-01 (LAN latency):** A says "one" on PTT; B's operator starts a stopwatch on A's mouth-motion and stops when they hear it. Repeat 10 times, drop min/max | p50 ≤ 150 ms, p90 ≤ 200 ms. A phone stopwatch is coarse (~50–100 ms); treat a clearly-half-second delay as a fail, a "instant" as a pass, and log the method | grant/RX SFX as 9.3 | NFR-01. This script **measures**; it does not certify a lab number |

Tune check (optional): step the CH up/down once and back to 01. After
tune settles expect **`tune_burst.wav`**. `knob_tick.wav` is in the
manifest but is **not** wired through `SfxProjection` — do not fail the
script if the knob is silent aside from `tune_burst`.

---

### 10. LINKED script — B on mobile data (relay required)

§4 health checks green. Both phones start this section in **LINKED**
mode with the baked URLs from §6 (or typed `wss://DOMAIN` /
`https://DOMAIN` per the token-URL table).

| Step | Action | Expect | SFX | FR |
|---|---|---|---|---|
| 10.1 | A: Wi-Fi, ⚙ → RADIO MODE **LINKED**, stay on CH 01 | After join, `NO LINK` is **off**. Optional **`link_up.wav`** if the flag was set then cleared | `link_up.wav` if recovering from no-link; else none | FR-040 LINKED; FR-043 numbered join |
| 10.2 | B: **disable Wi-Fi**, enable mobile data. ⚙ → **LINKED**. Same CH 01 | Same as 10.1 on LTE. This is the TURN path (NFR-05). If `NO LINK` stays up, pull §5 (token 4xx/5xx, ICE fail, `EXTERNAL_IP`) | `link_lost.wav` if it fails; `link_up.wav` if it recovers | FR-040; NFR-05 ≥ 97% is a VPS/field rate, not one join |
| 10.3 | Wait until both STN counts see each other (may be slower than LOCAL) | FR-067 list shows the other callsign | — | FR-067 over LiveKit presence |
| 10.4 | PTT A→B and B→A | Same audio path as 9.3/9.4, now via LiveKit | `key_click` / `squelch_open` / `squelch_tail` / `roger_k` | FR-020 over §8.4 |
| 10.5 | Busy lockout + a short TOT (optional, 30 s) | Same as 9.5–9.7 | `deny_buzz` / `tot_warn` / `tot_cut` | FR-022, FR-023 |
| 10.6 | **FR-045 degrade:** on the VPS, `docker compose stop livekit` (or unplug B). Wait | B (or both) show **`NO LINK`**, hear **`link_lost.wav`**, **no modal dialog**. LOCAL fallback if AUTO; LINKED-only stays flagged | `link_lost.wav` | FR-045 |
| 10.7 | Restore livekit / network | `NO LINK` clears, **`link_up.wav`** | `link_up.wav` | FR-045 recover |
| 10.8 | **NFR-02:** repeat the 9.10 mouth-to-ear procedure on the LINKED pair (B on LTE) | p90 ≤ 300 ms. Same stopwatch caveat as NFR-01 | as 10.4 | NFR-02 |

Airplane-mode-on-Wi-Fi-off is not a substitute for "B on LTE" — the
phone must have a default route through cellular so ICE/TURN is
exercised.

---

### 11. Event QR script

Both phones LINKED (or AUTO with a live relay). Same region (default
`global`). A exports, B scans.

Glass flip: tap **`STN n · …`** on the status strip (FR-067). The
station-list header has two icons: scanner (left) and QR (right). The
panel auto-flips back after 5 s unless you are already on the scan/export
route (TASK-037 pauses that timer).

| Step | Action | Expect | SFX | FR |
|---|---|---|---|---|
| 11.1 | A: tune to **CH 07 · code 21** (the spec's Event Crew example). Tap STN → **export** (QR icon) | Export screen with QR + expiry presets (4 h / 24 h default / 7 d / no expiry). Leave **24 h** | `tune_burst.wav` after the 01→07 tune | FR-043, FR-044, KRX-054 |
| 11.2 | B: tap STN → **scan** (scanner icon). Point at A's QR | B tunes to CH 07 · 21 **immediately**. Camera permission may prompt | `tune_burst.wav` on B after tune | FR-044 "Scanning tunes the radio instantly" |
| 11.3 | PTT A→B on CH 07 | Voice both ways on the event channel | as 10.4 | FR-020 + FR-043 |
| 11.4 | Expired token (optional) | Export with a 4 h preset, wait, or use a stale QR from a previous run. Token service refuses | B stays off the channel; no modal. Token log: `expired_event_token` (do not log the token) | FR-044; §5 403 row |
| 11.5 | Deep link (optional) | If a `keryx://` URL is shown on the export screen, open it on B | Same tune-instantly behaviour | FR-044 / KRX-054 |

Scan while B is still **LOCAL** is currently a visible snackbar, not a
LOCAL→LINKED prompt (TASK-037 dartdoc on `_joinEvent`). Put B in LINKED
before 11.2.

---

### 12. Pass / fail log (copy per run)

```
date (UTC):
APK: app-release.apk  size_bytes:     sha256:
A serial / callsign / Android:
B serial / callsign / Android:
relay DOMAIN:

8 settings-key → BackPanelScreen:  pass / fail
9 LOCAL discovery STN:             pass / fail
9 PTT A→B / B→A:                   pass / fail
9 busy lockout:                    pass / fail
9 TOT warn+cut:                    pass / fail
9 EMG (note parked double-grant):  pass / fail / double-grant
9 NFR-01 samples (ms):
10 LINKED join A Wi-Fi:            pass / fail
10 LINKED join B LTE:              pass / fail
10 PTT over relay:                 pass / fail
10 FR-045 NO LINK (no modal):      pass / fail
10 NFR-02 samples (ms):
11 Event QR export/scan CH 07.21:  pass / fail

SFX misses (which step, which file):
§5 triage row used (if any):
```

Privacy (TS §8.7): do not paste JWTs, callsigns into public trackers, or
raise LiveKit `pion_level` for this script. The log above keeps
callsigns on the operator's clipboard only.

---

### 13. App-side addenda to §5 triage

Relay/token rows stay in §5. Extra app-only rows:

| Symptom | Likely cause | What to pull |
|---|---|---|
| ⚙ key does nothing | `KeryxApp.routes` missing `backPanelRouteName` | this is §8; no Dart test will fail |
| Launch silent (no `power_on.wav`) | media volume / `DeviceAudioSink` / missing `assets/sfx/v1/*.wav` | `adb logcat` `flutter` / `SoLoud`; confirm the 22 WAVs are in the APK (`apk analyzer`) |
| STN 0 on same Wi-Fi, LOCAL | Nearby Wi-Fi denied; different CH/code; NSD | logcat `NsdPlugin`; Android Settings → App → Nearby devices |
| TOKEN URL typed with `/token` | double-append (see §6 table) | token-svc / Caddy 404 on `/token/token` |
| Scan QR from LOCAL | `joinEvent` requires LINKED chain | snackbar "Could not join event"; put B in LINKED |
| Both TX after EMG | parked FR-025 | log and move on; do not file as a TASK-039 regression |

<!-- TASK-039 APP-SIDE END -->

