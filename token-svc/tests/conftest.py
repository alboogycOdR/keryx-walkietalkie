"""Shared fixtures. Env must be set before app.main is imported."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

os.environ.setdefault("LIVEKIT_API_KEY", "devkey")
os.environ.setdefault("LIVEKIT_API_SECRET", "devsecret_min_32_chars_long______")
os.environ.setdefault("EVENT_TOKEN_SECRET", "eventsecret_min_32_chars_long_____")

from fastapi.testclient import TestClient  # noqa: E402

from app.config import Settings  # noqa: E402
from app.main import create_app  # noqa: E402
from app.rate_limit import IpRateLimiter  # noqa: E402

ROOM_A = "ABCDEFGHIJKLMNOP"
ROOM_B = "QRSTUVWXYZ234567"
CALLSIGN = "BRAVO-7"


@pytest.fixture
def settings() -> Settings:
    return Settings(
        livekit_api_key="devkey",
        livekit_api_secret="devsecret_min_32_chars_long______",
        event_token_secret="eventsecret_min_32_chars_long_____",
        token_ttl_seconds=300,
        rate_limit_max=30,
        rate_limit_window_seconds=60,
        rate_limit_ttl_seconds=3600,
    )


@pytest.fixture
def clock() -> list[float]:
    return [1_700_000_000.0]


@pytest.fixture
def client(settings: Settings, clock: list[float]) -> TestClient:
    limiter = IpRateLimiter(
        max_requests=settings.rate_limit_max,
        window_seconds=settings.rate_limit_window_seconds,
        ttl_seconds=settings.rate_limit_ttl_seconds,
        clock=lambda: clock[0],
    )
    app = create_app(settings=settings, limiter=limiter, clock=lambda: clock[0])
    return TestClient(app)
