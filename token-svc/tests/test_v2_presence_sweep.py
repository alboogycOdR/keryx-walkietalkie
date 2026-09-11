"""Periodic stale sweep and Redis presence bus (TASK-084 carry-overs)."""

from __future__ import annotations

import json
import time
from collections import defaultdict

from app.presence import RedisPresenceHub, presence_payload
from tests.conftest import ROOM_A
from tests.v2_helpers import Agent, create_group


class _FakePubSub:
    def __init__(self, bus: "FakeRedis") -> None:
        self._bus = bus
        self._q: list[dict] = []

    def subscribe(self, channel: str) -> None:
        self._bus.subs[channel].append(self)

    def listen(self):
        while True:
            if self._q:
                yield self._q.pop(0)
            else:
                yield {"type": "idle"}
                return


class FakeRedis:
    def __init__(self) -> None:
        self.subs: dict[str, list[_FakePubSub]] = defaultdict(list)
        self.published: list[tuple[str, str]] = []

    def publish(self, channel: str, data: str) -> int:
        self.published.append((channel, data))
        for sub in list(self.subs.get(channel, [])):
            sub._q.append({"type": "message", "data": data, "channel": channel})
        return 1

    def pubsub(self) -> _FakePubSub:
        return _FakePubSub(self)


def test_periodic_sweep_marks_offline_without_peer_message(client, clock) -> None:
    a = Agent(client, clock, "SWP-1")
    b = Agent(client, clock, "SWP-2")
    a.register()
    b.register()
    a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text})
    b.request("POST", f"/v2/contacts/requests/{a.pk_text}:accept")
    hub = client.app.state.presence_hub
    with client.websocket_connect("/v2/presence", headers=a.ws_headers()) as ws_a:
        with client.websocket_connect("/v2/presence", headers=b.ws_headers()):
            hub.delivered.clear()
            ws_a.send_json({"status": "available"})
            deadline = time.time() + 2
            while time.time() < deadline and not hub.delivered:
                time.sleep(0.02)
            assert any(pk == b.pk for pk, _ in hub.delivered)
            hub.delivered.clear()
            clock[0] += 301
            # Sweep runs on the timer path — nobody sends a socket message.
            from app.presence import mark_stale_offline

            session = client.app.state.session_factory()
            try:
                pending: list = []

                def _collect(_src, payload, recips) -> None:
                    for dest in recips:
                        pending.append((dest, payload))

                mark_stale_offline(session, clock[0], _collect)
                session.commit()
                hub.delivered.extend(pending)
            finally:
                session.close()
            deadline = time.time() + 2
            while time.time() < deadline and not hub.delivered:
                time.sleep(0.02)
            offline = [m for pk, m in hub.delivered if pk == b.pk]
            assert offline, hub.delivered
            assert offline[-1]["status"] == "offline"
            assert offline[-1]["pk"] == a.pk_text


def test_co_member_receives_presence(client, clock) -> None:
    a = Agent(client, clock, "COM-1")
    b = Agent(client, clock, "COM-2")
    a.register()
    b.register()
    gid = create_group(a, ROOM_A)
    token = a.request("POST", f"/v2/groups/{gid}/invites", {"expires_in": "7d"}).json()["token"]
    b.request("POST", "/v2/groups/join", {"token": token, "my_secret_enc": __import__("tests.v2_helpers", fromlist=["sealed_copy"]).sealed_copy()})
    hub = client.app.state.presence_hub
    hub.delivered.clear()
    with client.websocket_connect("/v2/presence", headers=a.ws_headers()) as ws_a:
        with client.websocket_connect("/v2/presence", headers=b.ws_headers()):
            ws_a.send_json({"status": "busy"})
            deadline = time.time() + 2
            while time.time() < deadline and not hub.delivered:
                time.sleep(0.02)
            to_b = [m for pk, m in hub.delivered if pk == b.pk]
            assert to_b, hub.delivered
            assert to_b[-1]["status"] == "busy"


def test_redis_bus_reaches_second_hub() -> None:
    bus = FakeRedis()
    hub_a = RedisPresenceHub(bus)
    hub_b = RedisPresenceHub(bus)
    dest = b"\x11" * 32
    payload = presence_payload(dest, 1, 1_700_000_000)
    # Simulate process B already subscribed.
    ps = bus.pubsub()
    ps.subscribe(RedisPresenceHub.CHANNEL)
    hub_a.publish_bus(dest, payload)
    item = next(x for x in ps.listen() if x.get("type") == "message")
    hub_b.handle_bus_message(item["data"])
    delivered = [m for pk, m in hub_b.delivered if pk == dest]
    assert delivered, hub_b.delivered
    assert delivered[-1]["status"] == "available"
    assert json.loads(bus.published[0][1])["dest"]
