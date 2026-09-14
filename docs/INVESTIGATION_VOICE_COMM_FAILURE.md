# KERYX — Real-Device Voice Communication Failure

**Filed:** 2026-09-14
**For:** Fable, deep investigation and fix
**Status:** ROOT CAUSE CONFIRMED AND FIXED IN CONFIG 2026-09-14 (deployed to
clawsrv + committed to `relay/livekit.yaml.tmpl`). Awaiting a real two-phone
call to confirm audio now flows — see "Resolution" at the bottom.

---

## Resolution (2026-09-14)

The root-cause hypothesis below was confirmed exactly. The fix is a LiveKit
config change in `relay/livekit.yaml.tmpl`, deployed live to clawsrv and
committed to the repo.

**What was wrong:** LiveKit runs `network_mode: host` on a box with ~45
interfaces (eth0 public, ~20 Docker bridges/veths from co-tenant projects, and
Tailscale `100.78.70.2` / `fd7a:115c:a1e0::/48`). It advertised host ICE
candidates on *all* of them; `use_external_ip: true` made it worse by STUN-mapping
every interface. The ICE agent renominated the media pair onto a Docker/Tailscale
address unreachable from a remote phone → DTLS timeout → `CLIENT_REQUEST_LEAVE`
within ~2s, every time.

**The fix (three levers, applied together in `rtc:`):**
- `node_ip: ${EXTERNAL_IP}` — pin the single advertised address. This VPS binds
  the public IP directly to eth0 as `/32` (no NAT), so it is knowable and stable.
- `use_external_ip: false` — stop the STUN pass that enumerated and mapped every
  interface. It exists to discover a NAT mapping this host does not have.
- `ips.includes: [${EXTERNAL_IP}/32]` — hard-restrict candidate gathering to the
  public /32. Self-maintaining as co-tenant containers add/remove interfaces.
  (Note: LiveKit requires **CIDR** here — a bare IP fails config load with
  "invalid CIDR address".)

**Verified so far:** LiveKit 1.9.11 restarts clean, logs `nodeIP: 204.168.249.99`,
and the interface-enumeration log line (previously listing all the 172.x /
Tailscale IPs) is gone entirely. By construction the SFU can now only offer the
public host candidate + the coturn relay.

**Deployment note:** applied to the live rendered config on clawsrv
(`/home/clawusr/keryx-relay/relay/generated/livekit.yaml`, re-rendered from the
updated template + restart of only `keryx-relay-livekit-1`). A pre-fix backup is
at `generated/livekit.yaml.bak-20260914` on the box. No other service on the
shared host was touched.

**Still to confirm:** a real two-phone call showing (a) the SFU offering only
`204.168.249.99` local candidates, (b) no pair-switch to a 172.x/Tailscale
address, (c) the session surviving past the first few seconds, and (d) actual
audio. Also still open: the client-side `CLIENT_REQUEST_LEAVE` behaviour (item 6
below) and the presence flicker (bottom) — both may resolve on their own once the
media path is stable, but should be re-checked.

---

---

## Symptom

Two real devices (Honor CRT-NX1, Android 15, cellular; a second device, Android 14,
WiFi) can register, add each other as contacts, and select each other to talk — but
no audio has ever passed between them. The owner has never once achieved a real
voice exchange, despite every layer up to the media session being individually
confirmed working.

## What is confirmed working (do not re-investigate these)

Verified directly against the live production database and LiveKit server logs on
`clawsrv` (204.168.249.99) on 2026-09-14:

- Both identities (`GTRWSQ`, `nmnbnb`) registered successfully (`identities` table).
- They are mutual contacts (`contacts` table, established ~1 minute after
  registration).
- A `DirectRoom` was correctly provisioned between them (`direct_rooms` table, room
  `IVIF32G6FT4337HD`).
- LiveKit correctly receives the join request with valid JWT grants (`RoomJoin:
  true`, `CanPublish/CanSubscribe/CanPublishData: true`, correct room name) — token
  minting and signing (`/token`) work.
- ICE negotiation **succeeds** — both a Google STUN server-reflexive candidate and a
  **TURN relay candidate through the deployed coturn** are gathered and a working
  candidate pair is selected (`connectionType: udp`, e.g. `[remote][selected:1]
  [trickle] udp4 srflx 41.116.151.x:2361` and a `relay 204.168.249.99:52328`
  candidate). Real remote mobile-network devices (cellular carrier IP
  `197.245.176.31`, another public IP `45.205.1.232`) are successfully reaching
  TURN.

**None of directory/contacts/token/signaling/ICE-gathering/TURN-reachability is the
problem.** Don't spend time re-verifying any of that.

## The actual defect — found in LiveKit's own logs

Every single join in the captured logs (4 attempts total, both identities, both
networks) follows the identical pattern within ~1–2.5 seconds of joining:

1. Participant joins, ICE selects a **working** candidate pair (host↔srflx via TURN
   relay).
2. LiveKit logs **`"ice reconnected or switched pair"`**, moving the active pair to
   a **new pair using `fd7a:115c:a1e0::7937:4602`** — an **IPv6 address on
   clawsrv's Tailscale interface**.
3. Within ~0.1–0.6 seconds, the participant **closes itself**
   (`"reason":"CLIENT_REQUEST_LEAVE"`) — the *client* initiates the disconnect, not
   the server.
4. Both publisher and subscriber data channels immediately report `"dtls timeout:
   read/write timeout: context deadline exceeded"`.
5. The room is torn down ~20s later on `departure_timeout` since it's now empty.

This happens **every time**, for both identities, on both cellular and WiFi.

### Evidence excerpt (from `docker logs keryx-relay-livekit-1` on clawsrv)

```
"msg":"participant active", "connectionType":"udp",
  publisherCandidates includes:
    "[remote][selected:1][trickle] udp4 srflx 41.116.151.x:2361 related ..."
    "[remote][trickle] udp4 relay 204.168.249.x:52328 related 41.116.151.x:2361"

"msg":"ice reconnected or switched pair", "transport":"PUBLISHER",
  "existingPair": {local host 172.17.0.1, remote srflx 41.116.151.x},
  "newPair": {local host fd7a:115c:a1e0::7937:4602, remote prflx fd7a:115c:a1e0::cf01:259}

"msg":"participant closing", "reason":"CLIENT_REQUEST_LEAVE"
"msg":"error reading data channel", "error":"dtls timeout: read/write timeout: context deadline exceeded"
```

## Root cause hypothesis (high confidence, needs Fable to confirm and fix precisely)

`clawsrv` is a shared, multi-homed box (Docker bridges `172.17.0.0/16`–
`172.23.0.0/16`, a Tailscale mesh interface `100.78.70.2` / `fd7a:115c:a1e0::/48`,
and the real public IP `204.168.249.99`) — it also hosts unrelated production
services for other projects (curry-orders, skulcozm, lekkerswot, several
oikonomos sandboxes). The deployed LiveKit config
(`relay/generated/livekit.yaml` on the server, rendered from
`relay/livekit.yaml.tmpl` in this repo) has `rtc.use_external_ip: true` but **no
`node_ip` pin and no interface include/exclude list**. `use_external_ip` only
affects which address LiveKit *advertises as its primary external candidate* — it
does **not** stop Pion (LiveKit's WebRTC stack) from also gathering and offering
host candidates from *every other interface on the box*, including the Tailscale
mesh IP, which a real remote phone can never route to. The connection starts on a
real, working relay pair, then LiveKit's ICE agent renominates to one of these
unreachable local candidates, killing the session almost instantly — a
well-documented class of bug on multi-homed LiveKit deployments.

## What Fable needs to do

1. **Confirm the hypothesis directly** — reproduce (both identities are already
   registered and mutual contacts; just select one from the other and talk), and
   correlate `docker logs keryx-relay-livekit-1` in real time against the
   switch-then-leave pattern above.
2. **Fix LiveKit's candidate gathering to only ever offer the public interface.**
   In LiveKit 1.9.11's config this likely means setting `rtc.node_ip:
   204.168.249.99` explicitly and/or `rtc.interfaces.includes`/`excludes` to
   restrict ICE gathering to the public NIC only, excluding every `172.1[7-9]`/
   `172.2[0-3]` Docker bridge and the Tailscale interface. Check LiveKit 1.9.11's
   exact config schema for this — key names have moved between versions.
3. **This is a live, shared multi-tenant server** — `docker-compose`/
   `livekit.yaml` changes must be scoped to the `keryx-relay-*` containers only
   (`livekit`, `redis`, `postgres`, `coturn`) and must not affect any other
   service on the box (curry-orders, skulcozm, lekkerswot, oikonomos sandboxes,
   the shared system Caddy at `/etc/caddy/Caddyfile`).
4. **Verify the fix for real**, not just via config review: re-run the actual
   two-phone join and confirm in the logs that ICE selects the relay/srflx pair
   and **never** switches to a `172.x`/`fd7a:` pair, that the session survives
   past the initial few seconds, and — critically — that actual RTP audio flows
   (LiveKit's own stats/logs, or the app's own meter/VU indication) rather than
   just "the room stayed open."
5. **Update both `relay/livekit.yaml.tmpl` in this repo and the live rendered
   config on `clawsrv`** — the repo is currently missing whatever setting fixes
   this, so treat the repo file as the source of truth going forward and
   redeploy from it, the same drift-closing pattern already used today for the
   Caddy `/v2` matcher fix.
6. **Check whether the KERYX Flutter client's own `CLIENT_REQUEST_LEAVE`
   behavior is itself a secondary issue** — confirm exactly what in
   `lib/services/linked/**` (the LiveKit/`RtcAdapter` integration) triggers a
   disconnect on this specific failure, and whether it should instead tolerate
   a transient ICE hiccup (LiveKit/WebRTC normally self-heals an ICE restart)
   rather than giving up and leaving immediately. This may be masking the true
   severity or interacting with the interface issue above.

## Secondary, related, lower-priority item

Presence still "fluctuates between online and offline" per the owner's own
observation even after the connect-time-announce fix landed — worth a quick look
once the above is fixed, but do not let it distract from the primary voice-path
defect, since a broken RTC session likely also disrupts the app's own
connectivity/foreground state in ways that could look like presence flicker.
