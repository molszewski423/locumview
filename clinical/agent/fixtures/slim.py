#!/usr/bin/env python3
"""Turn a case's FHIR read-back into a committed test fixture.

    python3 clinical/spike/readback.py LV-<case id> <dir>        on a local OpenEMR loaded with clinical/scenarios/load.py
    python3 clinical/agent/fixtures/slim.py <dir>/normalized.json clinical/agent/fixtures/fhir/<case id>.json

normalized.json already has server ids replaced by stable names (<Specimen#1>) and server timestamps removed. This
drops what the adapter never reads (meta, narrative) and empty vital-sign panels, so the fixture stays small and
reviewable. Synthetic data only (docs/policy/synthetic-data-and-independence.md).
"""
import json
from pathlib import Path
import sys

DROP = {"meta", "text", "performer", "requester", "recorder", "asserter", "_birthDate"}


def slim(value):
    if isinstance(value, dict):
        return {k: slim(v) for k, v in value.items() if k not in DROP}
    if isinstance(value, list):
        return [slim(v) for v in value]
    return value


def keep(resource):
    """Vital-sign Observations with no value and no components (height, BMI and the like, never charted) carry
    nothing; everything else stays."""
    if resource["resourceType"] != "Observation":
        return True
    return any(k.startswith("value") for k in resource) or bool(resource.get("component")) or \
        bool(resource.get("hasMember"))


def main():
    source, out = Path(sys.argv[1]), Path(sys.argv[2])
    resources = [slim(r) for r in json.loads(source.read_text()) if keep(r)]
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(resources, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
