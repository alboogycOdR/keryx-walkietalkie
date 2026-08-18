"""Stateless FastAPI token service — LiveKit JWT mint, no user DB (TS §8.1)."""

from __future__ import annotations

import time
from typing import Callable

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.config import Settings
from app.event_token import EventTokenError, verify_event_token
from app.jwt_mint import mint_livekit_jwt, new_identity
from app.logging_policy import configure_logging
from app.models import TokenRequest, TokenResponse
from app.rate_limit import IpRateLimiter

log = configure_logging()


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip() or "0.0.0.0"
    if request.client and request.client.host:
        return request.client.host
    return "0.0.0.0"


def create_app(
    settings: Settings | None = None,
    limiter: IpRateLimiter | None = None,
    clock: Callable[[], float] | None = None,
) -> FastAPI:
    cfg = settings or Settings.from_env()
    now = clock or time.time
    rate = limiter or IpRateLimiter(
        max_requests=cfg.rate_limit_max,
        window_seconds=cfg.rate_limit_window_seconds,
        ttl_seconds=cfg.rate_limit_ttl_seconds,
        clock=now,
    )
    app = FastAPI(title="keryx-token-svc", docs_url=None, redoc_url=None, openapi_url=None)
    app.state.settings = cfg
    app.state.limiter = rate
    app.state.clock = now

    @app.middleware("http")
    async def access_log(request: Request, call_next):  # type: ignore[no-untyped-def]
        response = await call_next(request)
        # Path + status only — never query, body, identity, or room.
        log.info("%s %s %s", request.method, request.url.path, response.status_code)
        return response

    @app.exception_handler(RequestValidationError)
    async def validation_handler(_request: Request, _exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(status_code=422, content={"detail": "invalid_request"})

    @app.get("/healthz")
    def healthz() -> dict[str, bool]:
        return {"ok": True}

    @app.post("/token", response_model=TokenResponse)
    def mint_token(body: TokenRequest, request: Request) -> TokenResponse:
        if not rate.allow(_client_ip(request)):
            raise HTTPException(status_code=429, detail="rate_limited")
        if body.event_token:
            try:
                verify_event_token(
                    body.event_token,
                    body.room_id,
                    cfg.event_token_secret,
                    now(),
                )
            except EventTokenError as exc:
                status = 403
                raise HTTPException(status_code=status, detail=exc.code) from exc
        identity = new_identity(body.callsign)
        token = mint_livekit_jwt(
            api_key=cfg.livekit_api_key,
            api_secret=cfg.livekit_api_secret,
            identity=identity,
            room_id=body.room_id,
            ttl_seconds=cfg.token_ttl_seconds,
            clock=now,
        )
        return TokenResponse(token=token, identity=identity, ttl_seconds=cfg.token_ttl_seconds)

    return app


app = create_app()
