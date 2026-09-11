"""Compose grows Postgres 16; token-svc stays out of the compose file."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

RELAY = Path(__file__).resolve().parents[2] / "relay"
COMPOSE = (RELAY / "docker-compose.yml").read_text(encoding="utf-8")
README = (RELAY / "README.md").read_text(encoding="utf-8")


def test_compose_defines_postgres_16() -> None:
    assert "postgres:" in COMPOSE
    assert "postgres:16" in COMPOSE
    assert "keryx_pg:" in COMPOSE
    assert "pg_isready" in COMPOSE
    assert "listen_addresses=127.0.0.1" in COMPOSE
    assert "token-svc:" not in COMPOSE


def test_readme_documents_dump_and_database_url() -> None:
    blob = README.lower()
    assert "postgres" in blob
    assert "database_url" in blob
    assert "pg_dump" in blob
    assert "keryx_signing_window" in blob or "keryx_signing_window_s" in blob


def test_docker_compose_config_includes_postgres() -> None:
    proc = subprocess.run(
        [
            "docker",
            "compose",
            "--env-file",
            str(RELAY / ".env.example"),
            "config",
            "--format",
            "json",
        ],
        cwd=RELAY,
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert proc.returncode == 0, proc.stderr
    services = set(json.loads(proc.stdout).get("services", {}))
    assert {"livekit", "redis", "caddy", "coturn", "postgres"}.issubset(services)
