"""LocumView agent service (Phase 9 lite M4, ADR 0017): findings for one patient's FHIR resources.

The clinical app's gateway reads the launched patient's chart from the EHR and posts the resources here; this service
builds the rules' snapshot (lvrules.from_fhir), runs the deterministic rules and returns each finding with its
evidence and its references. It holds no EHR credential and makes no outbound request: it sees only what the gateway
sends, and only for the length of the request. Nothing is stored.

POST /v1/explanations takes the same request, runs the same rules and has the local model explain each finding it
found (explain.py): the explanations are of the service's own findings, so a caller cannot have the model explain, or
seem to confirm, a finding the rules did not make. The model's only outbound request is to OLLAMA_URL, with the
finding, never the chart.

Settings (environment): SITE_TZ (the site's IANA time zone, for example America/New_York; required, because the
EHR returns UTC and the rules judge "today" by date), KNOWLEDGE_FILE and CITATIONS_FILE (defaults: the repository's
clinical/agent/knowledge/antimicrobials.json and clinical/scenarios/citations.json), OLLAMA_URL (the Ollama server;
without it /v1/explanations answers 503) and MODEL_FILE (default: model.json beside this file).
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from zoneinfo import ZoneInfo

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from explain import DEFAULT_MODEL_FILE, Explainer, ModelUnavailable
from lvrules import Knowledge, evaluate, from_fhir
from lvrules.knowledge import DEFAULT as DEFAULT_KNOWLEDGE

DEFAULT_CITATIONS = Path(__file__).resolve().parent.parent / "scenarios" / "citations.json"
MODULES = {"stewardship", "iv-to-po"}
MAX_RESOURCES = 5000    # one patient's chart; a request beyond this is refused rather than processed slowly


class FindingsRequest(BaseModel):
    resources: list[dict] = Field(max_length=MAX_RESOURCES)
    modules: list[str] | None = None


def create_app(kb: Knowledge, citations: dict, site_tz: str, explainer: Explainer | None = None) -> FastAPI:
    ZoneInfo(site_tz)   # fail at start, not on the first request, if the zone is unknown
    app = FastAPI(title="LocumView agent service", docs_url=None, redoc_url=None, openapi_url=None)

    def cite(ref: str) -> dict:
        c = citations.get(ref, {})
        return {"ref": ref, "title": c.get("title", ref), "source": c.get("source"), "pmid": c.get("pmid"),
                "doi": c.get("doi")}

    @app.get("/healthz")
    def healthz():
        return {"status": "ok", "knowledge_version": kb.version}

    def run_rules(body: FindingsRequest) -> tuple[str, list[str], list[dict]]:
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
        return snapshot.as_of.isoformat(), sorted(modules), [
            {"rule": f.rule, "module": f.module, "type": f.type, "drug": f.drug, "summary": f.summary,
             "evidence": list(f.evidence), "citations": [cite(r) for r in f.refs]}
            for f in evaluate(snapshot, kb, modules)]

    @app.post("/v1/findings")
    def findings(body: FindingsRequest):
        as_of, modules, found = run_rules(body)
        return {"knowledge_version": kb.version, "as_of": as_of, "modules": modules, "findings": found}

    @app.post("/v1/explanations")
    def explanations(body: FindingsRequest):
        as_of, modules, found = run_rules(body)
        if explainer is None:
            raise HTTPException(503, "No explanation model is set up")
        if found:
            try:
                explainer.check_model()
            except ModelUnavailable as error:
                raise HTTPException(503, str(error)) from None
        return {"knowledge_version": kb.version, "as_of": as_of, "modules": modules, "model": explainer.describe(),
                "explanations": [{"rule": f["rule"], "module": f["module"], "type": f["type"], "drug": f["drug"],
                                  **explainer.explain(f)} for f in found]}

    return app


def main() -> FastAPI:
    kb = Knowledge.load(Path(os.environ.get("KNOWLEDGE_FILE", DEFAULT_KNOWLEDGE)))
    citations = json.loads(Path(os.environ.get("CITATIONS_FILE", DEFAULT_CITATIONS)).read_text())["citations"]
    ollama = os.environ.get("OLLAMA_URL")
    explainer = Explainer(ollama, Path(os.environ.get("MODEL_FILE", DEFAULT_MODEL_FILE))) if ollama else None
    return create_app(kb, citations, os.environ["SITE_TZ"], explainer)
