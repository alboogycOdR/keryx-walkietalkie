"""Environment-backed settings. No secrets have defaults used in production."""

from __future__ import annotations

import os
from dataclasses import dataclass


def _require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"missing required environment variable: {name}")
    return value


def _int(name: str, default: int, minimum: int = 1) -> int:
    raw = os.environ.get(name, "").strip()
    value = int(raw) if raw else default
    if value < minimum:
        raise RuntimeError(f"{name} must be >= {minimum}")
    return value


def _opt(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


@dataclass(frozen=True)
class Settings:
    livekit_api_key: str
    livekit_api_secret: str
    event_token_secret: str
    token_ttl_seconds: int = 300
    rate_limit_max: int = 30
    rate_limit_window_seconds: int = 60
    rate_limit_ttl_seconds: int = 3600
    database_url: str = "sqlite://"
    redis_url: str = ""
    signing_window_s: int = 120

    @classmethod
    def from_env(cls) -> Settings:
        ttl = _int("RATE_LIMIT_TTL_SECONDS", 3600)
        if ttl > 3600:
            raise RuntimeError("RATE_LIMIT_TTL_SECONDS must be <= 3600 (TS §8.7)")
        return cls(
            livekit_api_key=_require("LIVEKIT_API_KEY"),
            livekit_api_secret=_require("LIVEKIT_API_SECRET"),
            event_token_secret=_require("EVENT_TOKEN_SECRET"),
            token_ttl_seconds=_int("TOKEN_TTL_SECONDS", 300),
            rate_limit_max=_int("RATE_LIMIT_MAX", 30),
            rate_limit_window_seconds=_int("RATE_LIMIT_WINDOW_SECONDS", 60),
            rate_limit_ttl_seconds=ttl,
            database_url=_opt("DATABASE_URL", "sqlite://"),
            redis_url=_opt("REDIS_URL", ""),
            signing_window_s=_int("KERYX_SIGNING_WINDOW_S", 120),
        )
