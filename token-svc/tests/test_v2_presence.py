"""V2-VT-013 presence: heartbeat, 5 min offline, contact fan-out only."""

from __future__ import annotations

import time

from tests.v2_helpers import Agent


def _hub(client):
    return client.app.state.presence_hub


def test_status_reaches_contact_not_stranger(client, clock) -> None:
    a = Agent(client, clock, "AVA-1")
    b = Agent(client, clock, "BEN-2")
    c = Agent(client, clock, "CYRUS-3")
    for agent in (a, b, c):
        assert agent.register().status_code == 200
    assert a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text}).status_code == 200
    assert b.request("POST", f"/v2/contacts/requests/{a.pk_text}:accept").status_code == 200

    hub = _hub(client)
    hub.delivered.clear()
    with client.websocket_connect("/v2/presence", headers=a.ws_headers()) as ws_a:
        with client.websocket_connect("/v2/presence", headers=b.ws_headers()):
            with client.websocket_connect("/v2/presence", headers=c.ws_headers()):
                ws_a.send_json({"status": "available"})
                deadline = time.time() + 2
                while time.time() < deadline and not hub.delivered:
                    time.sleep(0.02)
                to_b = [m for pk, m in hub.delivered if pk == b.pk]
                to_c = [m for pk, m in hub.delivered if pk == c.pk]
                assert to_b, hub.delivered
                assert to_b[-1]["pk"] == a.pk_text
                assert to_b[-1]["status"] == "available"
                assert "since" in to_b[-1]
                assert to_c == []


def test_heartbeat_keeps_online_then_five_min_offline(client, clock) -> None:
    a = Agent(client, clock, "HOLD-1")
    b = Agent(client, clock, "WATCH-2")
    assert a.register().status_code == 200
    assert b.register().status_code == 200
    a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text})
    b.request("POST", f"/v2/contacts/requests/{a.pk_text}:accept")

    hub = _hub(client)
    with client.websocket_connect("/v2/presence", headers=a.ws_headers()) as ws_a:
        with client.websocket_connect("/v2/presence", headers=b.ws_headers()) as ws_b:
            hub.delivered.clear()
            ws_a.send_json({"status": "available"})
            deadline = time.time() + 2
            while time.time() < deadline and not hub.delivered:
                time.sleep(0.02)
            first = [m for pk, m in hub.delivered if pk == b.pk]
            assert first and first[-1]["status"] == "available"
            clock[0] += 240
            ws_a.send_json({"type": "heartbeat"})
            me = a.me().json()
            assert me["status"] == "available"
            hub.delivered.clear()
            clock[0] += 301
            ws_b.send_json({"type": "heartbeat"})
            deadline = time.time() + 2
            while time.time() < deadline and not hub.delivered:
                time.sleep(0.02)
            offline = [m for pk, m in hub.delivered if pk == b.pk]
            assert offline, hub.delivered
            assert offline[-1]["pk"] == a.pk_text
            assert offline[-1]["status"] == "offline"
