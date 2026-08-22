# Relay hardening checklist (KRX-050)

Work this list on every VPS that runs the Keryx compose. Tick the box only
after the control is actually in place — not when you intend to do it.

## Transport

- [ ] **TLS 1.3** only on the signaling hostname (`Caddyfile` `protocols tls1.3`).
      Confirm with `nmap --script ssl-enum-ciphers -p 443 $DOMAIN` — no 1.0/1.1/1.2.
- [ ] ACME email in `.env` is a mailbox someone reads (expiry / rate-limit mail).
- [ ] `DOMAIN` and `TURN_DOMAIN` DNS are locked (registrar lock + DNSSEC if the
      zone supports it).
- [ ] WAN must not reach LiveKit `:7880` or Redis `:6379`. `ufw` deny those
      from anywhere except `127.0.0.1` (see README port table).
- [ ] coturn `denied-peer-ip` ranges still cover RFC1918 / loopback / TEST-NET
      so the TURN daemon cannot be used as an open relay into the VPS LAN.

## Process isolation

- [ ] Compose `cap_drop: ALL` is intact. Only Caddy and coturn re-add
      `NET_BIND_SERVICE`.
- [ ] `no-new-privileges:true` on every service.
- [ ] Redis and LiveKit run **non-root** (`user: 999:999` on Redis; LiveKit
      image default non-root user) and `read_only: true`.
- [ ] Redis has no RDB/AOF (`save ""`, `appendonly no`). A disk snapshot of
      room metadata is a privacy bug, not a backup.
- [ ] No Egress, Ingress, or object-storage volume is attached. Voice must
      never hit disk.

## Host firewall (`ufw`)

- [ ] Default deny incoming, allow outgoing.
- [ ] Only the ports in `README.md` are allowed from WAN: 80/tcp, 443/tcp,
      7881/tcp, 3478/udp, 3478/tcp, 5349/tcp, 50000–50200/udp, 52000–52999/udp,
      plus SSH from a known admin prefix (not `0.0.0.0/0` if you can avoid it).
- [ ] `7880/tcp` and `6379/tcp` are **not** in the allow list.
- [ ] Cloud security group (if any) matches `ufw` — two layers, same holes.

## Brute-force and abuse

- [ ] **fail2ban** (or equivalent) jails `sshd` and Caddy's HTTP 4xx burst
      on `/` and `/rtc`. Do not parse or store LiveKit room names / callsigns
      in those filters (TS §8.7).
- [ ] Token-svc rate limits (KRX-051) are the application-level cap; this
      host still needs a connection-rate limit on 443 (`ufw limit` or
      `iptables -m hashlimit`) so a scan cannot pin Caddy.
- [ ] **token-svc bind is loopback-only** (`docker run -p 127.0.0.1:8080:8080`).
      `:8080` is **not** in the WAN allow list. Caddy `/token` is the only
      public mint path (`TOKEN_SVC_UPSTREAM=127.0.0.1:8080`).
- [ ] token-svc `.env` `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` match this
      compose. `EVENT_TOKEN_SECRET` is shared with the app, not with LiveKit.
- [ ] coturn requires `use-auth-secret` (already in the template). Never
      switch it to a static username/password that is shared with clients.

## Secrets and key rotation

- [ ] `.env` mode `0600`, owned by the deploy user. Not in git, not in
      world-readable backups.
- [ ] `LIVEKIT_API_SECRET` and `TURN_SHARED_SECRET` are ≥ 32 hex chars of
      CSPRNG (`openssl rand -hex 32`).
- [ ] **key rotation** procedure is written down:
      1. Generate a second LiveKit key pair; add it under `keys:` (LiveKit
         accepts multiple).
      2. Point token-svc at the new pair; drain old JWTs (they are short-lived).
      3. Remove the old pair; `docker compose up -d livekit`.
      4. For TURN: put the new `static-auth-secret` in both `.env` and
         token-unrelated LiveKit `turn_servers.secret`, re-render, rolling
         restart coturn then LiveKit. Expect a brief ICE blip.
- [ ] Rotate after any suspected leak, and at least every 90 days.

## Logging and privacy (TS §8.7)

- [ ] **no logs of media.** Do not raise LiveKit `pion_level` above `error`
      in production. Do not run `tcpdump`/`tshark` on the RTC range except
      during a time-boxed incident, and wipe the pcap.
- [ ] Caddy access logs are JSON status/UA/IP only. Never log JWT query
      strings or room names (do not put tokens in URLs).
- [ ] Redis commands that dump keys (`DEBUG`, `FLUSHALL`) stay renamed away.
- [ ] Log rotation is on (`json-file` max-size 10m × 3 in compose).

## Updates

- [ ] Image tags stay **pinned**. An **auto-update** watch (Watchtower,
      Diun, or a weekly cron `docker compose pull && up -d`) is configured
      for *patch* tags you have tested — not a blind `:latest`.
- [ ] `unattended-upgrades` on the host for the OS, with a weekly reboot
      window if the kernel needs it.
- [ ] After every LiveKit bump: `python scripts/render_config.py` is a
      no-op (templates unchanged) and `docker compose config` still exits 0.

## Operator hygiene

- [ ] SSH keys only; `PasswordAuthentication no`.
- [ ] Swap is on (8 GB RAM, PTT spikes) but `/tmp` and Docker `tmpfs` are
      `noexec` where practical.
- [ ] A second person can bring the stack up from this README + `.env`
      without Slack archaeology.
- [ ] Restore test: wipe the containers, `up -d`, confirm Caddy re-uses
      the cert volume and LiveKit accepts a freshly minted JWT.

## What this stack deliberately does not do

- No public room directory.
- No server-side user database (that's the token service's non-job).
- No callsign or room-join history on disk.
- No TURN/TLS-on-443 multiplexer yet. If NFR-05 is missed because 3478/5349
  are blocked, add Caddy L4 (SNI `TURN_DOMAIN` → coturn) as a follow-up —
  do not punch random extra ports in the meantime.
