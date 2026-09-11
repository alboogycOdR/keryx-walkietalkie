"""KRX-051 logging-policy test: no callsigns, no room-join histories (TS §8.7)."""

from __future__ import annotations

import io
import logging

from fastapi.testclient import TestClient

from app.event_token import sign_event_token
from app.logging_policy import PrivacyFilter
from app.main import create_app
from app.rate_limit import IpRateLimiter
from tests.conftest import ROOM_A


SENTINEL_CALLSIGN = "SIERRA-19"
SENTINEL_ROOM = "ZZZZZZZZZZZZZZZZ"


def test_request_cycle_never_logs_callsign_or_room(settings, clock) -> None:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setLevel(logging.DEBUG)
    names = (
        "keryx.token",
        "keryx.token.ratelimit",
        "uvicorn",
        "uvicorn.access",
        "uvicorn.error",
        "fastapi",
        "root",
    )
    attached: list[tuple[logging.Logger, logging.Handler]] = []
    for name in names:
        logger = logging.getLogger(None if name == "root" else name)
        logger.addHandler(handler)
        logger.setLevel(logging.DEBUG)
        attached.append((logger, handler))

    limiter = IpRateLimiter(max_requests=30, window_seconds=60, ttl_seconds=3600, clock=lambda: clock[0])
    client = TestClient(create_app(settings=settings, limiter=limiter, clock=lambda: clock[0]))
    from tests.v2_helpers import Agent, create_group

    agent = Agent(client, clock, SENTINEL_CALLSIGN)
    assert agent.register().status_code == 200
    create_group(agent, SENTINEL_ROOM)
    event = sign_event_token(SENTINEL_ROOM, settings.event_token_secret, exp=int(clock[0]) + 60)
    res = agent.request(
        "POST",
        "/token",
        {"room_id": SENTINEL_ROOM, "callsign": SENTINEL_CALLSIGN, "event_token": event},
    )
    assert res.status_code == 200, res.text
    identity = res.json()["identity"]

    blob = stream.getvalue()
    for logger, h in attached:
        logger.removeHandler(h)

    assert SENTINEL_CALLSIGN not in blob
    assert SENTINEL_ROOM not in blob
    assert identity not in blob
    assert "joined" not in blob.lower()
    assert ROOM_A not in blob
    assert "rate_limit" in blob  # counters are the only permitted extra surface


def test_privacy_filter_drops_identity_leaks() -> None:
    filt = PrivacyFilter()
    record = logging.LogRecord(
        name="keryx.token",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="mint callsign=%s room_id=%s",
        args=(SENTINEL_CALLSIGN, SENTINEL_ROOM),
        exc_info=None,
    )
    assert filt.filter(record) is False
    clean = logging.LogRecord(
        name="keryx.token",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="POST /token 200",
        args=(),
        exc_info=None,
    )
    assert filt.filter(clean) is True
