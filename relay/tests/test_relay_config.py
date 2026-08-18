#!/usr/bin/env python3
"""Static + compose-config checks for the Keryx relay stack (KRX-050).

Runnable without a live VPS. Requires Docker Compose v2 for the
`docker compose config` acceptance criterion; remaining assertions are
pure file checks and still run if Docker is missing (then fail that one).
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

RELAY = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RELAY / "scripts"))
from render_config import parse_env, render  # noqa: E402


REQUIRED_SERVICES = {"livekit", "redis", "caddy", "coturn"}
FORBIDDEN_SERVICES = {"egress", "ingress", "livekit-egress", "livekit-ingress"}
PLACEHOLDER_PREFIXES = ("REPLACE_ME", "example.com", "203.0.113.")
COMMITTED_SECRET_PATTERNS = (
    re.compile(r"sk_live_[A-Za-z0-9]+"),
    re.compile(r"-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----"),
    re.compile(r"LIVEKIT_API_SECRET=\s*[A-Za-z0-9+/]{32,}"),
)


class RelayConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compose = (RELAY / "docker-compose.yml").read_text(encoding="utf-8")
        cls.caddy = (RELAY / "Caddyfile").read_text(encoding="utf-8")
        cls.env = parse_env(RELAY / ".env.example")
        cls.livekit = render(
            (RELAY / "livekit.yaml.tmpl").read_text(encoding="utf-8"),
            cls.env,
            RELAY / "livekit.yaml.tmpl",
        )
        cls.turn = render(
            (RELAY / "turnserver.conf.tmpl").read_text(encoding="utf-8"),
            cls.env,
            RELAY / "turnserver.conf.tmpl",
        )
        cls.readme = (RELAY / "README.md").read_text(encoding="utf-8")
        cls.hardening = (RELAY / "HARDENING.md").read_text(encoding="utf-8")

    def test_compose_defines_required_services(self) -> None:
        for name in REQUIRED_SERVICES:
            self.assertRegex(
                self.compose,
                rf"(?m)^  {name}:",
                f"docker-compose.yml must define service {name} (TS §8.1)",
            )

    def test_compose_has_no_recording_services(self) -> None:
        for name in FORBIDDEN_SERVICES:
            self.assertNotRegex(
                self.compose,
                rf"(?m)^  {re.escape(name)}:",
                f"{name} must not be in the stack (TS §8.7 no voice recorded)",
            )

    def test_images_are_pinned(self) -> None:
        images = re.findall(r"(?m)^\s+image:\s+(\S+)", self.compose)
        self.assertGreaterEqual(len(images), 4)
        for image in images:
            self.assertNotIn(
                ":latest",
                image,
                f"{image} must be pinned (no :latest)",
            )
            self.assertIn(":", image)

    def test_caddy_forces_tls13(self) -> None:
        self.assertIn("protocols tls1.3", self.caddy)
        self.assertIn("{$DOMAIN}", self.caddy)

    def test_token_route_reserved(self) -> None:
        self.assertIn("/token", self.caddy)
        self.assertIn("503", self.caddy)
        self.assertNotIn("token-svc:", self.compose)

    def test_livekit_wires_coturn(self) -> None:
        self.assertIn("turn_servers:", self.livekit)
        self.assertIn(self.env["TURN_DOMAIN"], self.livekit)
        self.assertIn("protocol: udp", self.livekit)
        self.assertIn("protocol: tls", self.livekit)
        self.assertIn(self.env["TURN_SHARED_SECRET"], self.livekit)

    def test_livekit_uses_redis(self) -> None:
        self.assertIn("address: 127.0.0.1:6379", self.livekit)

    def test_livekit_audio_only_no_egress(self) -> None:
        self.assertIn("mime: audio/opus", self.livekit)
        for key in ("egress:", "ingress:", "webhook:"):
            self.assertIsNone(
                re.search(rf"(?m)^[ \t]*{re.escape(key)}", self.livekit),
                f"livekit.yaml must not enable {key} (TS §8.7)",
            )

    def test_port_ranges_do_not_overlap(self) -> None:
        rtc_start = int(self.env["LIVEKIT_RTC_PORT_START"])
        rtc_end = int(self.env["LIVEKIT_RTC_PORT_END"])
        turn_start = int(self.env["COTURN_MIN_PORT"])
        turn_end = int(self.env["COTURN_MAX_PORT"])
        self.assertLess(rtc_start, rtc_end)
        self.assertLess(turn_start, turn_end)
        overlap = not (rtc_end < turn_start or turn_end < rtc_start)
        self.assertFalse(overlap, "LiveKit RTC and coturn relay ranges overlap")

    def test_coturn_auth_and_hardening_flags(self) -> None:
        self.assertIn("use-auth-secret", self.turn)
        self.assertIn(f"static-auth-secret={self.env['TURN_SHARED_SECRET']}", self.turn)
        self.assertIn("no-tlsv1", self.turn)
        self.assertIn("no-cli", self.turn)
        self.assertIn("denied-peer-ip=10.0.0.0-10.255.255.255", self.turn)
        self.assertIn("min-port=", self.turn)

    def test_env_example_documents_every_interpolated_var(self) -> None:
        needed = set(re.findall(r"\$\{([A-Z][A-Z0-9_]*)\}", self.compose))
        needed |= set(re.findall(r"\{\$([A-Z][A-Z0-9_]*)\}", self.caddy))
        needed |= set(
            re.findall(
                r"\$\{([A-Z][A-Z0-9_]*)\}",
                (RELAY / "livekit.yaml.tmpl").read_text(encoding="utf-8"),
            )
        )
        needed |= set(
            re.findall(
                r"\$\{([A-Z][A-Z0-9_]*)\}",
                (RELAY / "turnserver.conf.tmpl").read_text(encoding="utf-8"),
            )
        )
        missing = needed - set(self.env)
        self.assertFalse(missing, f".env.example missing vars: {sorted(missing)}")

    def test_no_real_secrets_in_committed_files(self) -> None:
        skip_suffixes = {".pyc"}
        skip_dirs = {"generated", "__pycache__"}
        for path in RELAY.rglob("*"):
            if not path.is_file():
                continue
            if any(part in skip_dirs for part in path.parts):
                continue
            if path.suffix in skip_suffixes:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for pat in COMMITTED_SECRET_PATTERNS:
                # .env.example documents LIVEKIT_API_SECRET=REPLACE_ME... — allowed.
                if path.name == ".env.example" and "REPLACE_ME" in text:
                    continue
                self.assertIsNone(
                    pat.search(text),
                    f"possible secret in {path.relative_to(RELAY)}",
                )

    def test_env_example_values_are_placeholders(self) -> None:
        for key in ("LIVEKIT_API_KEY", "LIVEKIT_API_SECRET", "TURN_SHARED_SECRET"):
            value = self.env[key]
            self.assertTrue(
                value.startswith("REPLACE_ME") or "example" in value.lower(),
                f"{key} in .env.example looks like a real secret",
            )
        self.assertTrue(
            any(self.env["DOMAIN"].endswith(sfx) for sfx in ("example.com", "example.net"))
        )
        self.assertTrue(self.env["EXTERNAL_IP"].startswith("203.0.113."))

    def test_hardening_checklist_present(self) -> None:
        for needle in (
            "TLS 1.3",
            "non-root",
            "ufw",
            "fail2ban",
            "key rotation",
            "no logs of media",
            "auto-update",
        ):
            self.assertIn(needle.lower(), self.hardening.lower(), f"HARDENING.md missing: {needle}")

    def test_scale_out_documented(self) -> None:
        blob = self.readme.lower()
        for needle in ("500", "scale-out", "redis", "multi-node", "nfr-09"):
            self.assertIn(needle, blob, f"README.md scale-out section missing {needle}")

    def test_docker_compose_config_validates(self) -> None:
        cmd = [
            "docker",
            "compose",
            "--env-file",
            str(RELAY / ".env.example"),
            "config",
            "--format",
            "json",
        ]
        try:
            proc = subprocess.run(
                cmd,
                cwd=RELAY,
                check=False,
                capture_output=True,
                text=True,
                timeout=60,
            )
        except FileNotFoundError:
            self.fail("docker not on PATH — required for `docker compose config` evidence")
        if proc.returncode != 0:
            self.fail(
                "docker compose config failed:\n"
                f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
            )
        # Prefer JSON; fall back to asserting service names in the rendered YAML.
        payload = proc.stdout
        try:
            parsed = json.loads(payload)
            services = set(parsed.get("services", {}))
        except json.JSONDecodeError:
            services = set(re.findall(r"(?m)^  ([a-z0-9-]+):", payload))
        self.assertTrue(
            REQUIRED_SERVICES.issubset(services),
            f"compose config services={services}, expected {REQUIRED_SERVICES}",
        )
        self.assertTrue(services.isdisjoint(FORBIDDEN_SERVICES))


if __name__ == "__main__":
    unittest.main(verbosity=2)
