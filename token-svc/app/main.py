"""Token mint plus v2 directory (Technical §4). POST /token is signed + membership-gated."""

from __future__ import annotations

import asyncio
import re
import time
from contextlib import asynccontextmanager
from typing import Callable

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from app.config import Settings
from app.db import make_engine, make_session_factory
from app.encoding import parse_pubkey
from app.errors import DirectoryError, UNKNOWN_IDENTITY, error_response
from app.event_token import EventTokenError, verify_event_token
from app.groups import assert_room_member, ensure_direct_room
from app.jwt_mint import mint_livekit_jwt, new_identity
from app.logging_policy import configure_logging
from app.models import TokenRequest, TokenResponse
from app.orm import Identity
from app.presence import MemoryPresenceHub, RedisPresenceHub
from app.rate_limit import IpRateLimiter
from app.signing import MemoryNonceStore, RedisNonceStore, verify_headers
from app.v2_api import router as v2_router
from app.v2_api import run_presence_sweep

log = configure_logging()

# Access log must never carry keys (base64url pubkeys in contact paths).
_REDACT_IDS = re.compile(r"[A-Za-z0-9_-]{20,}")


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip() or "0.0.0.0"
    if request.client and request.client.host:
        return request.client.host
    return "0.0.0.0"


def _safe_path(path: str) -> str:
    return _REDACT_IDS.sub(":id", path)


def create_app(
    settings: Settings | None = None,
    limiter: IpRateLimiter | None = None,
    clock: Callable[[], float] | None = None,
    session_factory: Callable | None = None,
    nonce_store: object | None = None,
    presence_hub: object | None = None,
) -> FastAPI:
    cfg = settings or Settings.from_env()
    now = clock or time.time
    rate = limiter or IpRateLimiter(
        max_requests=cfg.rate_limit_max,
        window_seconds=cfg.rate_limit_window_seconds,
        ttl_seconds=cfg.rate_limit_ttl_seconds,
        clock=now,
    )

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        hub = app.state.presence_hub
        starter = getattr(hub, "start_subscriber", None)
        if callable(starter):
            starter()
        stop = asyncio.Event()
        app.state.presence_sweep_stop = stop

        async def _loop() -> None:
            while not stop.is_set():
                try:
                    await asyncio.wait_for(stop.wait(), timeout=60)
                    return
                except asyncio.TimeoutError:
                    try:
                        await run_presence_sweep(app)
                    except Exception:
                        log.exception("presence sweep failed")

        task = asyncio.create_task(_loop())
        try:
            yield
        finally:
            stop.set()
            task.cancel()
            stopper = getattr(hub, "stop_subscriber", None)
            if callable(stopper):
                stopper()

    app = FastAPI(
        title="keryx-token-svc",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )
    app.state.settings = cfg
    app.state.limiter = rate
    app.state.clock = now
    app.state.run_presence_sweep = run_presence_sweep

    if session_factory is None:
        engine = make_engine(cfg.database_url)
        session_factory = make_session_factory(engine)
        app.state.engine = engine
    app.state.session_factory = session_factory

    redis_client = None
    if cfg.redis_url:
        try:
            import redis as redis_lib

            redis_client = redis_lib.Redis.from_url(cfg.redis_url, decode_responses=True)
        except Exception:
            redis_client = None

    if nonce_store is None:
        nonce_store = RedisNonceStore(redis_client) if redis_client is not None else MemoryNonceStore()
    app.state.nonce_store = nonce_store

    if presence_hub is None:
        presence_hub = RedisPresenceHub(redis_client) if redis_client is not None else MemoryPresenceHub()
    app.state.presence_hub = presence_hub

    @app.middleware("http")
    async def access_log(request: Request, call_next):  # type: ignore[no-untyped-def]
        response = await call_next(request)
        log.info("%s %s %s", request.method, _safe_path(request.url.path), response.status_code)
        return response

    @app.exception_handler(DirectoryError)
    async def directory_handler(_request: Request, exc: DirectoryError) -> JSONResponse:
        return error_response(exc.status_code, exc.code)

    @app.exception_handler(RequestValidationError)
    async def validation_handler(request: Request, _exc: RequestValidationError) -> JSONResponse:
        if request.url.path.startswith("/v2/"):
            return error_response(422, "invalid_request")
        return JSONResponse(status_code=422, content={"detail": "invalid_request"})

    @app.get("/healthz")
    def healthz() -> dict[str, bool]:
        return {"ok": True}

    @app.post("/token", response_model=TokenResponse)
    async def mint_token(request: Request) -> TokenResponse:
        if not rate.allow(_client_ip(request)):
            raise HTTPException(status_code=429, detail="rate_limited")
        raw = await request.body()
        try:
            body = TokenRequest.model_validate_json(raw or b"{}")
        except ValidationError as exc:
            raise HTTPException(status_code=422, detail="invalid_request") from exc

        pk = verify_headers(
            {k: v for k, v in request.headers.items()},
            "POST",
            request.url.path,
            raw,
            request.app.state.clock(),
            request.app.state.settings.signing_window_s,
            request.app.state.nonce_store,
        )
        session = request.app.state.session_factory()
        try:
            if session.get(Identity, pk) is None:
                raise DirectoryError(401, UNKNOWN_IDENTITY)
            if body.peer_pk:
                peer = parse_pubkey(body.peer_pk)
                ensure_direct_room(session, pk, peer, body.room_id, request.app.state.clock())
                session.commit()
            assert_room_member(session, pk, body.room_id)
        finally:
            session.close()

        if body.event_token:
            try:
                verify_event_token(
                    body.event_token,
                    body.room_id,
                    cfg.event_token_secret,
                    now(),
                )
            except EventTokenError as exc:
                raise HTTPException(status_code=403, detail=exc.code) from exc
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

    app.include_router(v2_router)
    return app


app = create_app()
