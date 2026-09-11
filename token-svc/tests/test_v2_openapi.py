"""openapi-v2.yaml is the TASK-086 contract; every implemented path is listed."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = (ROOT / "openapi-v2.yaml").read_text(encoding="utf-8")

REQUIRED_PATHS = [
    "/v2/identity",
    "/v2/identity/me",
    "/v2/identity/callsign",
    "/v2/contacts/requests",
    "/v2/contacts/requests/{from_pk}:accept",
    "/v2/contacts/requests/{from_pk}:decline",
    "/v2/contacts/requests/{from_pk}:block",
    "/v2/contacts/{pk}",
    "/v2/presence",
    "/token",
]


def test_openapi_lists_every_task084_endpoint() -> None:
    for path in REQUIRED_PATHS:
        assert path in SPEC, f"missing {path}"
    assert "X-Keryx-Sig" in SPEC
    assert "X-Keryx-Key" in SPEC
    assert "X-Keryx-Ts" in SPEC
    assert "stale" in SPEC.lower() or "120" in SPEC
