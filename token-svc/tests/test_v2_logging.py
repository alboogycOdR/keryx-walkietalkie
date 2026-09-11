"""Verification §7: directory logs contain no key, callsign, or room ID."""

from __future__ import annotations

import io
import logging

from app.event_token import sign_event_token
from app.logging_policy import PrivacyFilter
from tests.conftest import ROOM_A
from tests.v2_helpers import Agent

SENTINEL_CALLSIGN = "SIERRA-19"
SENTINEL_ROOM = "ZZZZZZZZZZZZZZZZ"


def test_every_v2_endpoint_logs_are_clean(client, clock, settings) -> None:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setLevel(logging.DEBUG)
    names = ("keryx.token", "keryx.token.ratelimit")
    attached = []
    for name in names:
        logger = logging.getLogger(None if name == "root" else name)
        logger.addHandler(handler)
        logger.setLevel(logging.DEBUG)
        attached.append((logger, handler))

    a = Agent(client, clock, SENTINEL_CALLSIGN)
    b = Agent(client, clock, "TANGO-20")
    a.register()
    b.register()
    a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text})
    b.request("POST", f"/v2/contacts/requests/{a.pk_text}:accept")
    a.me()
    a.request("PATCH", "/v2/identity/callsign", {"callsign": "UNIFORM-9"})
    a.request("DELETE", f"/v2/contacts/{b.pk_text}")
    # Re-request then decline/block so those paths run.
    c = Agent(client, clock, "VICTOR-8")
    c.register()
    a.request("POST", "/v2/contacts/requests", {"to_pk": c.pk_text})
    c.request("POST", f"/v2/contacts/requests/{a.pk_text}:decline")
    d = Agent(client, clock, "XRAY-7")
    d.register()
    a.request("POST", "/v2/contacts/requests", {"to_pk": d.pk_text})
    d.request("POST", f"/v2/contacts/requests/{a.pk_text}:block")
    with client.websocket_connect("/v2/presence", headers=a.ws_headers()) as ws:
        ws.send_json({"status": "available"})
        ws.send_json({"type": "heartbeat"})

    event = sign_event_token(SENTINEL_ROOM, settings.event_token_secret, exp=int(clock[0]) + 60)
    client.post(
        "/token",
        json={"room_id": SENTINEL_ROOM, "callsign": SENTINEL_CALLSIGN, "event_token": event},
    )

    blob = stream.getvalue()
    for logger, h in attached:
        logger.removeHandler(h)

    assert SENTINEL_CALLSIGN not in blob
    assert "UNIFORM-9" not in blob
    assert "TANGO-20" not in blob
    assert SENTINEL_ROOM not in blob
    assert ROOM_A not in blob
    assert a.pk_text not in blob
    assert b.pk_text not in blob
    assert "X-Keryx-Key" not in blob


def test_privacy_filter_drops_keys() -> None:
    filt = PrivacyFilter()
    record = logging.LogRecord(
        name="keryx.token",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="pubkey=%s callsign=%s",
        args=("abc", "SIERRA-19"),
        exc_info=None,
    )
    assert filt.filter(record) is False
