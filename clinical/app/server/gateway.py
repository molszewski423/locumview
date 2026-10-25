"""LocumView clinical app gateway: the app's backend for frontend (Phase 9 lite M3, owner decision option A).

OpenEMR 8.4.1 accepts a clinician's EHR launch only from a confidential client with user-level scopes, and its FHIR
API does not answer CORS preflight requests, so the app cannot talk to it from the browser. This gateway:

- completes the SMART EHR launch on the server (state, PKCE S256, client secret) for the one configured EHR;
- keeps the tokens server-side; the browser holds only an HttpOnly, Secure, SameSite=Lax session cookie;
- forwards read-only FHIR searches (GET, an allow-list of resource types), pinned to the launched patient, so a
  clinician-scoped token cannot be used to read another patient through the app;
- serves the built app (clinical/app/dist) from the same origin.

Settings (environment): EHR_FHIR_BASE (the EHR's FHIR base, the only accepted iss), CLIENT_ID,
CLIENT_SECRET_FILE, PUBLIC_URL (this gateway's external https URL), STATIC_DIR, EHR_TLS_CA (a CA bundle for the
EHR; default system roots), EHR_TLS_VERIFY=false (local test instance only), FRAME_ANCESTORS (origins allowed to
frame the app: the EHR's), EHR_INTERNAL_URL (optional: an origin such as http://openemr.clinical.svc to which the
gateway's own requests for the EHR's public origin are sent, so in-cluster traffic stays on the Service; launches
are still checked against the public EHR_FHIR_BASE). Sessions live in memory: one replica.
"""
from __future__ import annotations

import base64
import hashlib
import os
import secrets
import time
from dataclasses import dataclass, field
from urllib.parse import urlencode, urlsplit

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from scopes import SCOPES

# Resource types the app reads; every search is restricted to the launched patient.
READABLE = {"Encounter", "Condition", "AllergyIntolerance", "MedicationRequest", "Observation", "DiagnosticReport",
            "Specimen", "ServiceRequest"}
COOKIE = "lv_clinical_session"
PENDING_TTL = 600       # seconds a launch may take to come back from the EHR's authorization screens
MAX_PAGES = 20          # bound on following a search's next links


@dataclass
class Settings:
    ehr_fhir_base: str
    client_id: str
    client_secret: str
    public_url: str
    static_dir: str | None = None
    tls_verify: bool | str = True
    frame_ancestors: str = "'self'"
    ehr_internal_url: str | None = None

    @classmethod
    def from_env(cls) -> "Settings":
        verify: bool | str = os.environ.get("EHR_TLS_CA") or True
        if os.environ.get("EHR_TLS_VERIFY", "true").lower() == "false":
            verify = False
        with open(os.environ["CLIENT_SECRET_FILE"], encoding="utf-8") as f:
            secret = f.read().strip()
        return cls(ehr_fhir_base=os.environ["EHR_FHIR_BASE"].rstrip("/"), client_id=os.environ["CLIENT_ID"],
                   client_secret=secret, public_url=os.environ["PUBLIC_URL"].rstrip("/"),
                   static_dir=os.environ.get("STATIC_DIR"), tls_verify=verify,
                   frame_ancestors=os.environ.get("FRAME_ANCESTORS", "'self'"),
                   ehr_internal_url=(os.environ.get("EHR_INTERNAL_URL") or "").rstrip("/") or None)


@dataclass
class Session:
    access_token: str
    patient: str
    expires: float
    scope: str = ""


@dataclass
class Store:
    pending: dict[str, dict] = field(default_factory=dict)
    sessions: dict[str, Session] = field(default_factory=dict)

    def sweep(self) -> None:
        now = time.time()
        self.pending = {k: v for k, v in self.pending.items() if v["created"] + PENDING_TTL > now}
        self.sessions = {k: v for k, v in self.sessions.items() if v.expires > now}


def pkce() -> tuple[str, str]:
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def create_app(settings: Settings, transport: httpx.BaseTransport | None = None) -> FastAPI:
    app = FastAPI(title="LocumView clinical gateway", docs_url=None, redoc_url=None, openapi_url=None)
    store = Store()
    client = httpx.Client(transport=transport, verify=settings.tls_verify, timeout=30, follow_redirects=False)
    ehr_origin = "{0.scheme}://{0.netloc}".format(urlsplit(settings.ehr_fhir_base))

    def internal(url: str) -> str:
        """The gateway's own requests to the EHR go to its internal address when one is set."""
        if settings.ehr_internal_url and url.startswith(ehr_origin + "/"):
            return settings.ehr_internal_url + url[len(ehr_origin):]
        return url

    @app.middleware("http")
    async def headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Content-Security-Policy"] = (
            f"default-src 'self'; connect-src 'self'; frame-ancestors {settings.frame_ancestors}")
        if request.url.path.startswith(("/api/", "/launch", "/callback")):
            response.headers["Cache-Control"] = "no-store"
        return response

    def session_for(request: Request) -> Session:
        store.sweep()
        sid = request.cookies.get(COOKIE)
        if not sid:
            raise HTTPException(401, "No session cookie: open the app from a patient's chart in the EHR")
        session = store.sessions.get(sid)
        if session is None:
            raise HTTPException(401, "Session unknown or expired: open the app from the chart again")
        return session

    @app.get("/launch")
    def launch(iss: str, launch: str):
        # Only the configured EHR may start a launch: no open redirect, no requests to arbitrary servers.
        if iss.rstrip("/") != settings.ehr_fhir_base:
            raise HTTPException(400, "Launch from an EHR this app is not set up for")
        smart = client.get(internal(f"{settings.ehr_fhir_base}/.well-known/smart-configuration")).raise_for_status().json()
        verifier, challenge = pkce()
        state = secrets.token_urlsafe(32)
        store.sweep()
        store.pending[state] = {"verifier": verifier, "token_endpoint": smart["token_endpoint"], "created": time.time()}
        query = urlencode({
            "response_type": "code", "client_id": settings.client_id, "redirect_uri": f"{settings.public_url}/callback",
            "scope": SCOPES, "state": state, "aud": settings.ehr_fhir_base, "launch": launch,
            "code_challenge": challenge, "code_challenge_method": "S256"})
        return RedirectResponse(f"{smart['authorization_endpoint']}?{query}", status_code=302)

    @app.get("/callback")
    def callback(code: str, state: str):
        store.sweep()
        pending = store.pending.pop(state, None)
        if pending is None:
            raise HTTPException(400, "Unknown or expired launch: open the app from the chart again")
        if not pending["token_endpoint"].startswith(ehr_origin):
            raise HTTPException(502, "The EHR's token endpoint is not on the EHR's origin")
        reply = client.post(internal(pending["token_endpoint"]), data={
            "grant_type": "authorization_code", "code": code, "redirect_uri": f"{settings.public_url}/callback",
            "client_id": settings.client_id, "client_secret": settings.client_secret,
            "code_verifier": pending["verifier"]})
        if reply.status_code != 200:
            raise HTTPException(502, f"The EHR refused the token request (HTTP {reply.status_code})")
        token = reply.json()
        if not token.get("patient"):
            raise HTTPException(400, "The launch carried no patient: open the app from a patient's chart")
        sid = secrets.token_urlsafe(32)
        store.sessions[sid] = Session(access_token=token["access_token"], patient=token["patient"],
                                      expires=time.time() + int(token.get("expires_in", 3600)),
                                      scope=token.get("scope", ""))
        response = RedirectResponse(f"{settings.public_url}/index.html", status_code=302)
        response.set_cookie(COOKIE, sid, httponly=True, secure=True, samesite="lax", path="/")
        return response

    def ehr_get(session: Session, url: str, params: dict | None = None) -> dict:
        reply = client.get(internal(url), params=params, headers={"Authorization": f"Bearer {session.access_token}",
                                                       "Accept": "application/fhir+json"})
        if reply.status_code == 401:
            raise HTTPException(401, "The EHR session has ended: open the app from the chart again")
        if reply.status_code != 200:
            raise HTTPException(502, f"The EHR returned HTTP {reply.status_code}")
        return reply.json()

    @app.get("/api/context")
    def context(request: Request):
        session = session_for(request)
        # The granted scopes are not secret; they show what the EHR actually allowed.
        return {"patient": session.patient, "scope": session.scope}

    @app.get("/api/fhir/Patient")
    def patient(request: Request):
        session = session_for(request)
        return ehr_get(session, f"{settings.ehr_fhir_base}/Patient/{session.patient}")

    @app.get("/api/fhir/{resource_type}")
    def search(resource_type: str, request: Request):
        session = session_for(request)
        if resource_type not in READABLE:
            raise HTTPException(404, "Not a resource type this app reads")
        # The launched patient, always: a patient or subject parameter from the browser is replaced.
        params = {k: v for k, v in request.query_params.items() if k not in ("patient", "subject", "_id")}
        params["patient"] = session.patient
        bundle = ehr_get(session, f"{settings.ehr_fhir_base}/{resource_type}", params)
        entries = list(bundle.get("entry", []))
        for _ in range(MAX_PAGES - 1):
            nxt = next((link["url"] for link in bundle.get("link", []) if link.get("relation") == "next"), None)
            if not nxt:
                break
            if not nxt.startswith(settings.ehr_fhir_base + "/"):
                raise HTTPException(502, "The EHR's next page is outside its FHIR base")
            bundle = ehr_get(session, nxt)
            entries += bundle.get("entry", [])
        return JSONResponse({"resourceType": "Bundle", "type": "searchset", "total": len(entries),
                             "entry": [{"resource": e["resource"]} for e in entries]})

    if settings.static_dir:
        app.mount("/", StaticFiles(directory=settings.static_dir, html=True), name="app")
    return app


def main() -> FastAPI:
    return create_app(Settings.from_env())
