#!/usr/bin/env python3
"""Phase 9 lite M1 spike: read a loaded scenario back through OpenEMR's FHIR API, as an API client sees it.

    readback.py <family-name or patient number> <out-dir>     for example LV-uti-esbl-mismatch-01

Every scenario case shares the family name Casebook, so read cases back by patient number (LV-<case id>). A family
name that matches more than one patient is refused.

Writes the raw search bundles and normalized.json: every resource with server-assigned values removed (ids, UUID
references, meta.lastUpdated, bundle links) so two fresh instances can be compared with a plain diff. Prints a
field-by-field summary of the microbiology.
"""
import importlib.util
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("fhir", HERE / "fhir.py")
fhir = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fhir)

TYPES = ["Patient", "Encounter", "Condition", "MedicationRequest", "ServiceRequest", "Specimen", "DiagnosticReport",
         "Observation"]
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def sort_key(resource):
    concept = resource.get("code") or resource.get("type") or {}
    concept = concept[0] if isinstance(concept, list) and concept else concept  # Encounter.type is a list
    code = (concept or {}).get("coding", [{}])[0].get("code", "") if isinstance(concept, dict) else ""
    return (resource["resourceType"], code, json.dumps(resource.get("valueString") or resource.get("valueQuantity")))


def normalize(resources):
    """Replace each server UUID with <Type#n>, numbered in a stable order, and drop server-assigned metadata."""
    resources = sorted(resources, key=sort_key)
    names, counts = {}, {}
    for r in resources:
        counts[r["resourceType"]] = counts.get(r["resourceType"], 0) + 1
        names[r["id"]] = f"<{r['resourceType']}#{counts[r['resourceType']]}>"

    def clean(value):
        if isinstance(value, dict):
            return {k: clean(v) for k, v in value.items() if k not in ("lastUpdated",)}
        if isinstance(value, list):
            return [clean(v) for v in value]
        if isinstance(value, str):
            return UUID.sub(lambda m: names.get(m[0], "<unresolved-id>"), value)
        return value
    return [clean(r) for r in resources]


def main():
    who, out = sys.argv[1], Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    search = "identifier" if who.startswith(("LV-", "SYN-")) else "family"
    status, bundle = fhir.call("GET", f"fhir/Patient?{search}={who}")
    matches = bundle.get("entry", [])
    if len(matches) != 1:
        raise SystemExit(f"{search} {who}: {len(matches)} patients match; give one patient number")
    patient = matches[0]["resource"]["id"]
    resources = []
    for kind in TYPES:
        query = f"{kind}/{patient}" if kind == "Patient" else f"{kind}?patient={patient}"
        status, body = fhir.call("GET", "fhir/" + query)
        (out / f"{kind}.json").write_text(json.dumps(body, indent=1))
        found = [body] if kind == "Patient" else [e["resource"] for e in body.get("entry", [])]
        print(f"{kind:18} HTTP {status}  {len(found)}")
        resources += found
    (out / "normalized.json").write_text(json.dumps(normalize(resources), indent=1, sort_keys=True) + "\n")

    by_type = {}
    for r in resources:
        by_type.setdefault(r["resourceType"], []).append(r)
    print("\nObservation: code | value | interpretation | effective | specimen | encounter | hasMember/derivedFrom")
    for o in sorted(by_type.get("Observation", []), key=sort_key):
        value = next((json.dumps(o[k], separators=(",", ":")) for k in o if k.startswith("value")), "-")
        interp = o.get("interpretation", [{}])[0]
        coded = interp.get("coding", [{}])[0].get("code") if interp.get("coding") else None
        print(f"  {o['code']['coding'][0]['code']:8} | {value[:58]:58} | "
              f"{coded or ('text ' + interp['text'] if interp.get('text') else '-'):8} | {o.get('effectiveDateTime', '-')} | "
              f"{'yes' if o.get('specimen') else 'no'} | {'yes' if o.get('encounter') else 'no'} | "
              f"{len(o.get('hasMember', []))}/{len(o.get('derivedFrom', []))}")
    for kind in ("Specimen", "DiagnosticReport", "ServiceRequest"):
        for r in by_type.get(kind, []):
            keep = {k: r.get(k) for k in ("status", "code", "type", "collection", "accessionIdentifier", "effectiveDateTime",
                                          "issued", "specimen", "encounter") if r.get(k) is not None}
            keep["results"] = len(r.get("result", [])) if kind == "DiagnosticReport" else None
            print(f"{kind}: {json.dumps({k: v for k, v in keep.items() if v is not None}, separators=(',', ':'))[:420]}")


if __name__ == "__main__":
    main()
