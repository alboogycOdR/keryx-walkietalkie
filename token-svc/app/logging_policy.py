"""Logging policy: nothing beyond ephemeral rate-limit counters (TS §8.7)."""

from __future__ import annotations

import logging
import re

# Field names that would constitute a room-join history or identity leak.
# v2: also drop keys, pubkeys, sealed secrets (Verification §7).
_FORBIDDEN = re.compile(
    r"(callsign|room[_-]?id|roomJoin|joined room|event_token|"
    r"pubkey|public.?key|private.?key|secret_enc|x-keryx-key|"
    r"peer_id|peerId|from_pk|to_pk)",
    re.IGNORECASE,
)


class PrivacyFilter(logging.Filter):
    """Drop any record that looks like a join history or identity leak."""

    def filter(self, record: logging.LogRecord) -> bool:
        try:
            message = record.getMessage()
        except Exception:
            return False
        if _FORBIDDEN.search(message):
            return False
        # args may contain values interpolated later; reject those too
        if record.args:
            blob = " ".join(str(a) for a in (record.args if isinstance(record.args, tuple) else (record.args,)))
            if _FORBIDDEN.search(blob):
                return False
        return True


def configure_logging() -> logging.Logger:
    logger = logging.getLogger("keryx.token")
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter("%(name)s %(levelname)s %(message)s"))
        handler.addFilter(PrivacyFilter())
        logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    # Rate-limit logger is the only permitted counter surface.
    rl = logging.getLogger("keryx.token.ratelimit")
    rl.handlers = logger.handlers
    rl.setLevel(logging.INFO)
    rl.propagate = False
    return logger
