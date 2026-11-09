"""Build the rules' Snapshot from FHIR R4 resources, as OpenEMR 8.4.1 returns them through the app gateway.

The input is the list of resources the gateway's patient-pinned searches return (Patient, Encounter, Condition,
MedicationRequest, Observation, Specimen, ServiceRequest). What OpenEMR does and does not return is recorded in
docs/upstream/openemr-8.4.1.md; the parts this adapter depends on:

- Times come back in UTC. Rules judge "today" by calendar date, so every time is converted to the site's time zone
  (local_tz) first; otherwise an evening event lands on the next day.
- A prescription's start is a date. OpenEMR returns it as authoredOn at midnight UTC (the loader records it there,
  item 11), so its date is read as written, not converted. A dosage timing boundsPeriod, when an EHR sends one, wins.
- OpenEMR marks a prescription completed whenever it has an end date and does not return the date, so a completed,
  stopped or cancelled order counts as ended.
- A culture's organism is valueString "<SNOMED CT code> (<name>)" (item 5). Susceptibilities are not linked to the
  organism (item 7); with one organism per culture they are joined through the specimen's accession number, since
  OpenEMR makes one Specimen per ordered test with a shared accession (M1).
- Problem codes need clinical/spike/patches/0002 (item 9); without it a problem has no ICD-10 code and the rules that
  match conditions stay silent.
"""
from __future__ import annotations

from datetime import date, datetime
import re
from zoneinfo import ZoneInfo

from .knowledge import Knowledge
from .snapshot import Culture, Prescription, Problem, Snapshot, Susceptibility, Vital

ICD10 = "http://hl7.org/fhir/sid/icd-10"
RXNORM = "http://www.nlm.nih.gov/research/umls/rxnorm"
ROUTES = {"C38276": "IV", "C38288": "PO", "C28161": "IM", "C38299": "SC"}
ENDED = {"completed", "stopped", "cancelled", "entered-in-error"}
CULTURES = {"600-7", "630-4", "606-4"}          # bacteria identified in blood, urine, CSF by culture
NO_GROWTH = "264868006"
ORGANISM = re.compile(r"^\s*(\d+)\s*\((.*)\)\s*$")
VITALS = {"8310-5": "temperature", "8867-4": "pulse", "9279-1": "respiration", "2708-6": "oxygen_saturation",
          "59408-5": "oxygen_saturation"}
SYSTOLIC = "8480-6"


def _code(concept: dict | None, system: str | None = None) -> str | None:
    for coding in (concept or {}).get("coding", []):
        if system is None or coding.get("system") == system:
            return coding.get("code")
    return None


def _ref_id(reference: dict | None) -> str | None:
    return (reference or {}).get("reference", "").split("/")[-1] or None


def _fahrenheit(quantity: dict) -> float:
    value = float(quantity["value"])
    return round(value * 9 / 5 + 32, 1) if quantity.get("code") in ("Cel", "C") else value


def from_fhir(resources: list[dict], kb: Knowledge, local_tz: str) -> Snapshot:
    tz = ZoneInfo(local_tz)

    def when(value: str) -> datetime:
        return datetime.fromisoformat(value).astimezone(tz)

    by_type: dict[str, list[dict]] = {}
    for r in resources:
        by_type.setdefault(r["resourceType"], []).append(r)
    (patient,) = by_type["Patient"]
    encounters = sorted(by_type.get("Encounter", []), key=lambda e: e["period"]["start"])
    encounter_start = when(encounters[-1]["period"]["start"])
    times = [encounter_start]

    problems = [Problem((c.get("code") or {}).get("text") or "", _code(c.get("code"), ICD10))
                for c in by_type.get("Condition", [])]

    prescriptions = []
    for m in by_type.get("MedicationRequest", []):
        dosage = (m.get("dosageInstruction") or [{}])[0]
        bounds = ((dosage.get("timing") or {}).get("repeat") or {}).get("boundsPeriod") or {}
        start = bounds.get("start") or m.get("authoredOn")
        if not start:
            continue    # no start date: a course cannot be placed in time, so the order is left out
        route = ROUTES.get(_code(dosage.get("route"))) or ((dosage.get("route") or {}).get("text") or "").upper()
        concept = m.get("medicationCodeableConcept") or {}
        rx = _code(concept, RXNORM)
        prescriptions.append(Prescription(
            kb.products.get(rx or ""), (concept.get("coding") or [{}])[0].get("display") or concept.get("text") or "",
            route, date.fromisoformat(start[:10]),
            date.fromisoformat(bounds["end"][:10]) if bounds.get("end") else None,
            ended=m.get("status") in ENDED and not bounds.get("end")))

    vitals: dict[datetime, dict] = {}
    for o in by_type.get("Observation", []):
        if "effectiveDateTime" in o:
            times.append(when(o["effectiveDateTime"]))
        category = _code((o.get("category") or [{}])[0])
        if category != "vital-signs" or "effectiveDateTime" not in o:
            continue
        code, taken = _code(o.get("code")), when(o["effectiveDateTime"])
        row = vitals.setdefault(taken, {})
        if code in VITALS and o.get("valueQuantity"):
            q = o["valueQuantity"]
            row[VITALS[code]] = _fahrenheit(q) if code == "8310-5" else float(q["value"])
        for component in o.get("component", []):
            if _code(component.get("code")) == SYSTOLIC and component.get("valueQuantity"):
                row["systolic"] = float(component["valueQuantity"]["value"])
    vital_rows = [Vital(t, v.get("temperature"), v.get("pulse"), v.get("respiration"), v.get("oxygen_saturation"),
                        v.get("systolic")) for t, v in sorted(vitals.items()) if v]

    specimens = {s["id"]: s for s in by_type.get("Specimen", [])}
    accession = {sid: (s.get("accessionIdentifier") or {}).get("value") or sid for sid, s in specimens.items()}
    for s in specimens.values():
        collected = (s.get("collection") or {}).get("collectedDateTime")
        if collected:
            times.append(when(collected))
    for sr in by_type.get("ServiceRequest", []):
        if sr.get("authoredOn"):
            times.append(when(sr["authoredOn"]))

    organisms: dict[str, tuple[str | None, str | None]] = {}
    tests: dict[str, list[Susceptibility]] = {}
    for o in by_type.get("Observation", []):
        sid = _ref_id(o.get("specimen"))
        if sid not in accession:
            continue
        code, key = _code(o.get("code")), accession[sid]
        if code in CULTURES and "valueString" in o:
            m = ORGANISM.match(o["valueString"])
            snomed, name = (m.group(1), m.group(2)) if m else (None, o["valueString"])
            organisms[key] = (None, None) if snomed == NO_GROWTH else (snomed, name)
        elif code in kb.tests:
            interp = (o.get("interpretation") or [{}])[0]
            tests.setdefault(key, []).append(Susceptibility(code, kb.susceptibility_agent(code),
                                                            _code(interp) or interp.get("text") or ""))

    cultures, seen = [], set()
    for sid, s in specimens.items():
        key = accession[sid]
        if key in seen:
            continue
        seen.add(key)
        collected = (s.get("collection") or {}).get("collectedDateTime")
        organism_code, organism = organisms.get(key, (None, None))
        cultures.append(Culture(kb.specimens.get(_code(s.get("type")) or ""), when(collected) if collected else None,
                                key in organisms, organism_code, organism, tuple(tests.get(key, ()))))

    return Snapshot(date.fromisoformat(patient["birthDate"]), encounter_start, problems, prescriptions, vital_rows,
                    cultures, max(times))
