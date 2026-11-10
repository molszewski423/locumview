"""LocumView agent service (Phase 9 lite M4, ADR 0017): findings for one patient's FHIR resources.

The clinical app's gateway reads the launched patient's chart from the EHR and posts the resources here; this service
builds the rules' snapshot (lvrules.from_fhir), runs the deterministic rules and returns each finding with its
evidence and its references. It holds no EHR credential and makes no outbound request: it sees only what the gateway
sends, and only for the length of the request. Nothing is stored. The local model's explanations are a later step.

Settings (environment): SITE_TZ (the site's IANA time zone, for example America/New_York; required, because the
EHR returns UTC and the rules judge "today" by date), KNOWLEDGE_FILE and CITATIONS_FILE (defaults: the repository's
clinical/agent/knowledge/antimicrobials.json and clinical/scenarios/citations.json).
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from zoneinfo import ZoneInfo

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from lvrules import Knowledge, evaluate, from_fhir
from lvrules.knowledge import DEFAULT as DEFAULT_KNOWLEDGE

DEFAULT_CITATIONS = Path(__file__).resolve().parent.parent / "scenarios" / "citations.json"
MODULES = {"stewardship", "iv-to-po"}
MAX_RESOURCES = 5000    # one patient's chart; a request beyond this is refused rather than processed slowly


class FindingsRequest(BaseModel):
    resources: list[dict] = Field(max_length=MAX_RESOURCES)
    modules: list[str] | None = None


def create_app(kb: Knowledge, citations: dict, site_tz: str) -> FastAPI:
    ZoneInfo(site_tz)   # fail at start, not on the first request, if the zone is unknown
    app = FastAPI(title="LocumView agent service", docs_url=None, redoc_url=None, openapi_url=None)

    def cite(ref: str) -> dict:
        c = citations.get(ref, {})
        return {"ref": ref, "title": c.get("title", ref), "source": c.get("source"), "pmid": c.get("pmid"),
                "doi": c.get("doi")}

    @app.get("/healthz")
    def healthz():
        return {"status": "ok", "knowledge_version": kb.version}

    @app.post("/v1/findings")
    def findings(body: FindingsRequest):
        modules = set(body.modules) if body.modules is not None else MODULES
        if not modules <= MODULES:
            raise HTTPException(422, f"Unknown modules: {sorted(modules - MODULES)}")
        if sum(r.get("resourceType") == "Patient" for r in body.resources) != 1:
            raise HTTPException(422, "Send exactly one Patient with that patient's resources")
        if not any(r.get("resourceType") == "Encounter" for r in body.resources):
            raise HTTPException(422, "No Encounter: the rules need the current admission")
        try:
            snapshot = from_fhir(body.resources, kb, site_tz)
        except (KeyError, ValueError, TypeError) as error:
            raise HTTPException(422, f"The chart could not be read: {type(error).__name__}") from None
        return {
            "knowledge_version": kb.version,
            "as_of": snapshot.as_of.isoformat(),
            "modules": sorted(modules),
            "findings": [{"rule": f.rule, "module": f.module, "type": f.type, "drug": f.drug, "summary": f.summary,
                          "evidence": list(f.evidence), "citations": [cite(r) for r in f.refs]}
                         for f in evaluate(snapshot, kb, modules)],
        }

    return app


def main() -> FastAPI:
    kb = Knowledge.load(Path(os.environ.get("KNOWLEDGE_FILE", DEFAULT_KNOWLEDGE)))
    citations = json.loads(Path(os.environ.get("CITATIONS_FILE", DEFAULT_CITATIONS)).read_text())["citations"]
    return create_app(kb, citations, os.environ["SITE_TZ"])
