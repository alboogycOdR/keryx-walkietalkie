"""V2-VT-010 contacts lifecycle."""

from __future__ import annotations

from tests.v2_helpers import Agent


def _pair(client, clock) -> tuple[Agent, Agent]:
    a = Agent(client, clock, "ALICE-1")
    b = Agent(client, clock, "BOB-2")
    assert a.register().status_code == 200
    assert b.register().status_code == 200
    return a, b


def test_accept_creates_symmetric_link(client, clock) -> None:
    a, b = _pair(client, clock)
    res = a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text})
    assert res.status_code == 200, res.text
    acc = b.request("POST", f"/v2/contacts/requests/{a.pk_text}:accept")
    assert acc.status_code == 200, acc.text
    me_a = a.me().json()
    me_b = b.me().json()
    assert any(c["pk"] == b.pk_text for c in me_a["contacts"])
    assert any(c["pk"] == a.pk_text for c in me_b["contacts"])
    assert me_a["pending_in"] == []
    assert me_b["pending_in"] == []


def test_decline_creates_nothing(client, clock) -> None:
    a, b = _pair(client, clock)
    assert a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text}).status_code == 200
    dec = b.request("POST", f"/v2/contacts/requests/{a.pk_text}:decline")
    assert dec.status_code == 200
    assert a.me().json()["contacts"] == []
    assert b.me().json()["contacts"] == []
    assert a.me().json()["pending_out"] == []


def test_block_prevents_rerequest(client, clock) -> None:
    a, b = _pair(client, clock)
    assert a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text}).status_code == 200
    blk = b.request("POST", f"/v2/contacts/requests/{a.pk_text}:block")
    assert blk.status_code == 200
    again = a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text})
    assert again.status_code == 403
    assert again.json() == {"error": "blocked"}
    assert a.me().json()["contacts"] == []


def test_expiry_at_seven_days(client, clock) -> None:
    a, b = _pair(client, clock)
    assert a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text}).status_code == 200
    clock[0] += 7 * 24 * 3600 + 1
    acc = b.request("POST", f"/v2/contacts/requests/{a.pk_text}:accept")
    assert acc.status_code == 410
    assert acc.json() == {"error": "request_expired"}
    # After expiry a new request is allowed.
    again = a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text})
    assert again.status_code == 200, again.text


def test_21st_outstanding_refused(client, clock) -> None:
    sender = Agent(client, clock, "SENDER-1")
    assert sender.register().status_code == 200
    targets = []
    for i in range(21):
        t = Agent(client, clock, f"T{i:02d}-X")
        assert t.register().status_code == 200
        targets.append(t)
    for t in targets[:20]:
        res = sender.request("POST", "/v2/contacts/requests", {"to_pk": t.pk_text})
        assert res.status_code == 200, res.text
    last = sender.request("POST", "/v2/contacts/requests", {"to_pk": targets[20].pk_text})
    assert last.status_code == 429
    assert last.json() == {"error": "too_many_outstanding"}


def test_remove_is_unannounced(client, clock) -> None:
    a, b = _pair(client, clock)
    a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text})
    b.request("POST", f"/v2/contacts/requests/{a.pk_text}:accept")
    gone = a.request("DELETE", f"/v2/contacts/{b.pk_text}")
    assert gone.status_code == 200
    assert a.me().json()["contacts"] == []
    assert b.me().json()["contacts"] == []


def test_self_request_rejected(client, clock) -> None:
    a = Agent(client, clock, "SELF-1")
    a.register()
    res = a.request("POST", "/v2/contacts/requests", {"to_pk": a.pk_text})
    assert res.status_code == 422
    assert res.json() == {"error": "self_request"}


def test_patch_callsign(client, clock) -> None:
    a = Agent(client, clock, "OLD-NAME")
    a.register()
    res = a.request("PATCH", "/v2/identity/callsign", {"callsign": "NEW-NAME"})
    assert res.status_code == 200
    assert a.me().json()["callsign"] == "NEW-NAME"
