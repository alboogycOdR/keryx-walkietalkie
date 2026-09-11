"""IP-scoped rate limits; counters expire in <= 1 h (TS §8.7)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.rate_limit import IpRateLimiter
from tests.conftest import CALLSIGN, ROOM_A


def _client(settings: Settings, clock: list[float], max_requests: int = 3) -> TestClient:
    tight = Settings(
        livekit_api_key=settings.livekit_api_key,
        livekit_api_secret=settings.livekit_api_secret,
        event_token_secret=settings.event_token_secret,
        token_ttl_seconds=settings.token_ttl_seconds,
        rate_limit_max=max_requests,
        rate_limit_window_seconds=60,
        rate_limit_ttl_seconds=3600,
    )
    limiter = IpRateLimiter(
        max_requests=max_requests,
        window_seconds=60,
        ttl_seconds=3600,
        clock=lambda: clock[0],
    )
    return TestClient(create_app(settings=tight, limiter=limiter, clock=lambda: clock[0]))


def test_same_ip_exceeds_window(settings, clock) -> None:
    client = _client(settings, clock, max_requests=3)
    for _ in range(3):
        # Unsigned is 401, but the IP limiter still counts the attempt.
        assert client.post("/token", json={"room_id": ROOM_A, "callsign": CALLSIGN}).status_code == 401
    res = client.post("/token", json={"room_id": ROOM_A, "callsign": CALLSIGN})
    assert res.status_code == 429
    assert res.json()["detail"] == "rate_limited"


def test_distinct_ips_have_independent_counters(settings, clock) -> None:
    client = _client(settings, clock, max_requests=1)
    a = client.post("/token", json={"room_id": ROOM_A, "callsign": CALLSIGN}, headers={"X-Forwarded-For": "10.0.0.1"})
    b = client.post("/token", json={"room_id": ROOM_A, "callsign": CALLSIGN}, headers={"X-Forwarded-For": "10.0.0.2"})
    assert a.status_code == 401
    assert b.status_code == 401
    again = client.post("/token", json={"room_id": ROOM_A, "callsign": CALLSIGN}, headers={"X-Forwarded-For": "10.0.0.1"})
    assert again.status_code == 429


def test_window_resets(settings, clock) -> None:
    client = _client(settings, clock, max_requests=1)
    assert client.post("/token", json={"room_id": ROOM_A, "callsign": CALLSIGN}).status_code == 401
    assert client.post("/token", json={"room_id": ROOM_A, "callsign": CALLSIGN}).status_code == 429
    clock[0] += 60
    assert client.post("/token", json={"room_id": ROOM_A, "callsign": CALLSIGN}).status_code == 401


def test_counters_expire_within_one_hour(settings, clock) -> None:
    limiter = IpRateLimiter(max_requests=1, window_seconds=60, ttl_seconds=3600, clock=lambda: clock[0])
    assert limiter.allow("10.1.2.3") is True
    assert limiter.size == 1
    clock[0] += 3599
    limiter.purge_expired()
    assert limiter.size == 1
    clock[0] += 1
    limiter.purge_expired()
    assert limiter.size == 0


def test_ttl_cannot_exceed_one_hour() -> None:
    try:
        IpRateLimiter(max_requests=1, window_seconds=60, ttl_seconds=3601)
    except ValueError as exc:
        assert "3600" in str(exc)
    else:
        raise AssertionError("expected ValueError for ttl > 3600")
