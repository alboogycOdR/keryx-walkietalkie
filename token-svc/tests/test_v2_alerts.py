"""V2-VT-015 alerts: first delivered, second inside 10 min refused."""

from __future__ import annotations

import time

from tests.v2_helpers import Agent


def test_alert_rate_limit_and_delivery(client, clock) -> None:
    a = Agent(client, clock, "ALRT-1")
    b = Agent(client, clock, "ALRT-2")
    a.register()
    b.register()
    a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text})
    b.request("POST", f"/v2/contacts/requests/{a.pk_text}:accept")

    hub = client.app.state.presence_hub
    hub.delivered.clear()
    with client.websocket_connect("/v2/presence", headers=b.ws_headers()):
        first = a.request("POST", "/v2/alerts", {"to_pk": b.pk_text})
        assert first.status_code == 200, first.text
        deadline = time.time() + 2
        while time.time() < deadline and not hub.delivered:
            time.sleep(0.02)
        notes = [m for pk, m in hub.delivered if pk == b.pk]
        assert notes, hub.delivered
        assert notes[-1]["type"] == "alert"
        assert notes[-1]["from_pk"] == a.pk_text

        second = a.request("POST", "/v2/alerts", {"to_pk": b.pk_text})
        assert second.status_code == 429
        assert second.json()["error"] == "alert_rate_limited"

        clock[0] += 601
        third = a.request("POST", "/v2/alerts", {"to_pk": b.pk_text})
        assert third.status_code == 200, third.text
