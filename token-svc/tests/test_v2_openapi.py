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
    "/v2/groups",
    "/v2/groups/{id}/invites",
    "/v2/groups/join",
    "/v2/groups/{id}",
    "/v2/groups/{id}/rotate",
    "/v2/groups/{id}/members/{pk}",
    "/v2/groups/{id}/members/me",
    "/v2/groups/{id}/members/{pk}:admin",
    "/v2/alerts",
    "/token",
]


def test_openapi_lists_every_implemented_endpoint() -> None:
    for path in REQUIRED_PATHS:
        assert path in SPEC, f"missing {path}"
    assert "X-Keryx-Sig" in SPEC
    assert "X-Keryx-Key" in SPEC
    assert "X-Keryx-Ts" in SPEC
    assert "stale" in SPEC.lower() or "120" in SPEC
    assert "base64url" in SPEC
    assert "standard base64" in SPEC.lower() or "standard base64" in SPEC
