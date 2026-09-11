"""Enumerated directory errors. v2 responses are `{error: code}` only."""

from __future__ import annotations

from fastapi.responses import JSONResponse


class DirectoryError(Exception):
    def __init__(self, status_code: int, code: str) -> None:
        super().__init__(code)
        self.status_code = status_code
        self.code = code


def error_response(status_code: int, code: str) -> JSONResponse:
    return JSONResponse(status_code=status_code, content={"error": code})


# Auth (Technical §3.3 / V2-VT-004)
MISSING_SIGNATURE = "missing_signature"
INVALID_SIGNATURE = "invalid_signature"
STALE_TIMESTAMP = "stale_timestamp"
REPLAYED = "replayed"
INVALID_KEY = "invalid_key"

# Identity
UNKNOWN_IDENTITY = "unknown_identity"
IDENTITY_EXISTS = "identity_exists"
CALLSIGN_TAKEN = "callsign_taken"
INVALID_CALLSIGN = "invalid_callsign"

# Contacts (V2-VT-010)
INVALID_REQUEST = "invalid_request"
SELF_REQUEST = "self_request"
ALREADY_CONTACTS = "already_contacts"
ALREADY_PENDING = "already_pending"
BLOCKED = "blocked"
REQUEST_NOT_FOUND = "request_not_found"
REQUEST_EXPIRED = "request_expired"
TOO_MANY_OUTSTANDING = "too_many_outstanding"
NOT_FOUND = "not_found"
NOT_CONTACTS = "not_contacts"

# Presence
INVALID_STATUS = "invalid_status"

# Groups / invites / rotation / token / alerts (TASK-085)
NOT_MEMBER = "not_member"
NOT_ADMIN = "not_admin"
GROUP_NOT_FOUND = "group_not_found"
GROUP_FULL = "group_full"
ALREADY_MEMBER = "already_member"
INVALID_NAME = "invalid_name"
INVITE_INVALID = "invite_invalid"
INVITE_EXPIRED = "invite_expired"
ROTATE_INCOMPLETE = "rotate_incomplete"
ALERT_RATE_LIMITED = "alert_rate_limited"
ROOM_CONFLICT = "room_conflict"
