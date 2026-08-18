"""In-memory IP-scoped rate limiter. Counters expire in <= 1 h (TS §8.7). No disk."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Callable

log = logging.getLogger("keryx.token.ratelimit")


@dataclass
class _Counter:
    window_start: float
    count: int
    last_seen: float


class IpRateLimiter:
    """Fixed-window limiter keyed by client IP. Process memory only."""

    def __init__(
        self,
        max_requests: int,
        window_seconds: int,
        ttl_seconds: int,
        clock: Callable[[], float] | None = None,
    ) -> None:
        if ttl_seconds > 3600:
            raise ValueError("rate-limit counters must expire in <= 3600 s")
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.ttl_seconds = ttl_seconds
        self._clock = clock or time.time
        self._counters: dict[str, _Counter] = {}

    def allow(self, ip: str) -> bool:
        now = self._clock()
        self.purge_expired(now)
        entry = self._counters.get(ip)
        if entry is None or now - entry.window_start >= self.window_seconds:
            entry = _Counter(window_start=now, count=0, last_seen=now)
            self._counters[ip] = entry
        entry.count += 1
        entry.last_seen = now
        limited = entry.count > self.max_requests
        # Allowed log surface: ephemeral IP-scoped counters only. Never IP, room, callsign.
        log.info("rate_limit limited=%s count=%s", limited, entry.count)
        return not limited

    def purge_expired(self, now: float | None = None) -> int:
        ts = self._clock() if now is None else now
        stale = [ip for ip, c in self._counters.items() if ts - c.last_seen >= self.ttl_seconds]
        for ip in stale:
            del self._counters[ip]
        return len(stale)

    @property
    def size(self) -> int:
        return len(self._counters)
