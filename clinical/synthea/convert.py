#!/usr/bin/env python3
"""Convert Synthea's FHIR patient bundles to background.json for the scenario loader (plan M2).

    convert.py <synthea fhir dir> <out.json> --source "<how it was generated>"

Background patients fill the EHR's patient list; they are not cases. Kept: demographics (name without Synthea's
numeric suffixes, owner decision 2026-11-12; race and ethnicity as OMB categories, address, home phone, marital
status, language), active problems (SNOMED CT disorders), active allergies, the most recent dose of each vaccine
(CVX), the most recent smoking status, the payer of the most recent claim, and the most recent visit with vital signs;
plus an emergency contact made up per patient (Synthea has none). No encounters, medications, labs or cultures, so a background patient can
never produce a finding (vital signs alone do not). Output is sorted and numbered (SYN-001...) so the same Synthea run gives the same file.
"""
import json
import re
from pathlib import Path
import sys

SNOMED = "http://snomed.info/sct"
CVX = "http://hl7.org/fhir/sid/cvx"
LOINC = "http://loinc.org"
SMOKING = "72166-2"
VITALS = {"29463-7": "weight_kg", "8302-2": "height_cm", "8867-4": "pulse", "9279-1": "respiration",
          "8310-5": "temperature_c", "8480-6": "bps", "8462-4": "bpd"}
# Emergency contacts are not in Synthea's output; these first names make a plausible one per patient (by number).
GIVEN = {"female": ["Ann", "Carol", "Diane", "Grace", "Helen", "Joan", "Karen", "Linda", "Maria", "Nora", "Ruth",
                    "Susan"],
         "male": ["Brian", "Daniel", "Edward", "Frank", "George", "James", "Kevin", "Mark", "Paul", "Robert", "Steven",
                  "Thomas"]}


def plain(name):
    """Synthea marks names as synthetic with digits (Jamal145); the chart shows the name without them."""
    return re.sub(r"\d+", "", name).strip()


def omb(p, kind):
    """The OMB category codes of the US Core race or ethnicity extension."""
    for e in p.get("extension", []):
        if e["url"].endswith(f"us-core-{kind}"):
            return [x["valueCoding"]["code"] for x in e.get("extension", []) if x["url"] == "ombCategory"]
    return []
RXNORM = "http://www.nlm.nih.gov/research/umls/rxnorm"


def coding(concept, system=None):
    for c in (concept or {}).get("coding", []):
        if system is None or c.get("system") == system:
            return c
    return {}


def active(resource):
    return coding(resource.get("clinicalStatus")).get("code") == "active"


def insurer(resources):
    """The payer on the most recent claim; none when uninsured."""
    claims = sorted((r for r in resources if r["resourceType"] == "Claim"), key=lambda r: r.get("created", ""))
    name = ((claims[-1].get("insurance") or [{}])[0].get("coverage", {}).get("display") if claims else None) or ""
    return None if name in ("", "NO_INSURANCE") else name


def emergency_contact(number, family, marital, sex):
    """A plausible emergency contact, the same every run: the spouse when married, otherwise a grown child."""
    import hashlib
    h = int(hashlib.sha256(number.encode()).hexdigest(), 16)
    if marital == "M":
        relation, their_sex = "Spouse", {"male": "female", "female": "male"}[sex]
    else:
        their_sex = ("female", "male")[h % 2]
        relation = {"female": "Daughter", "male": "Son"}[their_sex]
    given = GIVEN[their_sex][(h >> 8) % len(GIVEN[their_sex])]
    return {"name": f"{given} {family}", "relationship": relation,
            "phone": f"555-{(h >> 16) % 900 + 100:03d}-{(h >> 32) % 10000:04d}"}


def last_visit(resources):
    """The most recent encounter with vital signs: its date, type and the vital signs (US units, as OpenEMR stores)."""
    by_encounter = {}
    for r in resources:
        if r["resourceType"] != "Observation" or not r.get("encounter"):
            continue
        code = coding(r.get("code"), LOINC).get("code")
        values = {code: r.get("valueQuantity", {}).get("value")} if code in VITALS else {}
        for c in r.get("component", []):
            cc = coding(c.get("code"), LOINC).get("code")
            if cc in VITALS:
                values[cc] = c.get("valueQuantity", {}).get("value")
        if values:
            by_encounter.setdefault(r["encounter"]["reference"].split(":")[-1], {}).update(values)
    encounters = {r["id"]: r for r in resources if r["resourceType"] == "Encounter"}
    visits = sorted(((encounters[e]["period"]["start"], e) for e in by_encounter if e in encounters), reverse=True)
    if not visits:
        return None
    start, e = visits[0]
    v = {VITALS[k]: val for k, val in by_encounter[e].items() if val is not None}
    out = {}
    if "weight_kg" in v: out["weight"] = round(v["weight_kg"] * 2.20462, 1)
    if "height_cm" in v: out["height"] = round(v["height_cm"] / 2.54, 1)
    if "temperature_c" in v: out["temperature"] = round(v["temperature_c"] * 9 / 5 + 32, 1)
    for k in ("bps", "bpd", "pulse", "respiration"):
        if k in v: out[k] = round(v[k])
    if out.get("bps", 1) <= out.get("bpd", 0):   # Synthea occasionally records systolic at or below diastolic
        out.pop("bps", None); out.pop("bpd", None)
    reason = coding(encounters[e]["type"][0]).get("display", "Office visit").removesuffix(" (procedure)")
    return {"start": start, "reason": reason, "vitals": out}


def patient(bundle):
    resources = [e["resource"] for e in bundle.get("entry", [])]
    p = next(r for r in resources if r["resourceType"] == "Patient")
    name = next((n for n in p["name"] if n.get("use") == "official"), p["name"][0])
    problems, allergies, vaccines, smoking = {}, {}, {}, ("", "")
    for r in resources:
        if r["resourceType"] == "Immunization" and r.get("status") == "completed":
            c = coding(r.get("vaccineCode"), CVX)
            day = (r.get("occurrenceDateTime") or "")[:10]
            if c and day >= vaccines.get(c["code"], {}).get("date", ""):
                vaccines[c["code"]] = {"cvx": c["code"], "title": c.get("display", ""), "date": day}
        elif r["resourceType"] == "Observation" and coding(r.get("code"), LOINC).get("code") == SMOKING:
            day = (r.get("effectiveDateTime") or "")[:10]
            if day >= smoking[0]:
                smoking = (day, coding(r.get("valueCodeableConcept"), SNOMED).get("display", ""))
        if r["resourceType"] == "Condition" and active(r):
            c = coding(r.get("code"), SNOMED)
            if c.get("display", "").endswith("(disorder)"):
                problems[c["code"]] = {"title": c["display"].removesuffix(" (disorder)"), "snomed": c["code"],
                                       "begdate": (r.get("onsetDateTime") or r.get("recordedDate", ""))[:10]}
        elif r["resourceType"] == "AllergyIntolerance" and active(r):
            c = coding(r.get("code"))
            display = c.get("display", "")
            # Allergens only: drop SNOMED findings such as "Allergic disposition", strip semantic tags.
            if display and not display.endswith("(finding)"):
                title = display.removesuffix(" (substance)").removesuffix(" (organism)")
                system = {SNOMED: "snomed", RXNORM: "rxnorm"}.get(c.get("system"))
                allergies[title] = {"title": title, "begdate": (r.get("recordedDate") or "")[:10],
                                    **({system: c["code"]} if system else {})}
    address = (p.get("address") or [{}])[0]
    phone = next((t["value"] for t in p.get("telecom", []) if t.get("system") == "phone"), "")
    language = coding(((p.get("communication") or [{}])[0]).get("language")).get("code", "")
    return {"family": plain(name["family"]), "given": plain(name["given"][0]), "birth_date": p["birthDate"],
            "sex": p["gender"],
            "demographics": {
                "race": omb(p, "race"), "ethnicity": omb(p, "ethnicity"),
                "street": " ".join(address.get("line", [])), "city": address.get("city", ""),
                "state": address.get("state", ""), "postal_code": address.get("postalCode", ""),
                "phone_home": phone, "marital": coding(p.get("maritalStatus")).get("code", ""),
                "language": language.split("-")[0]},
            "smoking": smoking[1].removesuffix(" (finding)"),
            "insurance": insurer(resources),
            "last_visit": last_visit(resources),
            "problems": sorted(problems.values(), key=lambda x: (x["begdate"], x["snomed"])),
            "allergies": sorted(allergies.values(), key=lambda x: (x["begdate"], x["title"])),
            "immunizations": sorted(vaccines.values(), key=lambda x: (x["date"], x["cvx"]))}


def main(argv):
    src, out = Path(argv[0]), Path(argv[1])
    source = argv[argv.index("--source") + 1]
    bundles = [json.loads(p.read_text()) for p in sorted(src.glob("*.json"))
               if not p.name.startswith(("hospitalInformation", "practitionerInformation"))]
    people = sorted((patient(b) for b in bundles), key=lambda x: (x["birth_date"], x["family"], x["given"]))
    overrides = json.loads((Path(__file__).resolve().parent / "overrides.json").read_text())
    for n, person in enumerate(people, 1):
        person["number"] = f"SYN-{n:03d}"
        person["demographics"].update(overrides.get(person["number"], {}).get("demographics", {}))
        person["emergency_contact"] = emergency_contact(person["number"], person["family"],
                                                        person["demographics"]["marital"], person["sex"])
    out.write_text(json.dumps({
        "_note": "Synthetic background patients for the Phase 9 lite demo EHR, generated by clinical/synthea/generate.sh. "
                 "Not cases: no encounters, medications, labs or cultures, so no rule may produce a finding for them. "
                 "Names, addresses and phone numbers are Synthea's inventions (phones are 555 numbers).",
        "source": source,
        "patients": [{"number": p.pop("number"), **p} for p in people]}, indent=1) + "\n")
    print(f"{len(people)} background patients -> {out}")


if __name__ == "__main__":
    main(sys.argv[1:])
