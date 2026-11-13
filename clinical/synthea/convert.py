#!/usr/bin/env python3
"""Convert Synthea's FHIR patient bundles to background.json for the scenario loader (plan M2).

    convert.py <synthea fhir dir> <out.json> --source "<how it was generated>"

Background patients fill the EHR's patient list; they are not cases. Kept: demographics (name without Synthea's
numeric suffixes, owner decision 2026-11-12; race and ethnicity as OMB categories, address, home phone, marital
status, language), active problems (SNOMED CT disorders), active allergies, the most recent dose of each vaccine
(CVX) and the most recent smoking status. No encounters, medications, labs or cultures, so a background patient can
never produce a finding. Output is sorted and numbered (SYN-001...) so the same Synthea run gives the same file.
"""
import json
import re
from pathlib import Path
import sys

SNOMED = "http://snomed.info/sct"
CVX = "http://hl7.org/fhir/sid/cvx"
LOINC = "http://loinc.org"
SMOKING = "72166-2"


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
            "problems": sorted(problems.values(), key=lambda x: (x["begdate"], x["snomed"])),
            "allergies": sorted(allergies.values(), key=lambda x: (x["begdate"], x["title"])),
            "immunizations": sorted(vaccines.values(), key=lambda x: (x["date"], x["cvx"]))}


def main(argv):
    src, out = Path(argv[0]), Path(argv[1])
    source = argv[argv.index("--source") + 1]
    bundles = [json.loads(p.read_text()) for p in sorted(src.glob("*.json"))
               if not p.name.startswith(("hospitalInformation", "practitionerInformation"))]
    people = sorted((patient(b) for b in bundles), key=lambda x: (x["birth_date"], x["family"], x["given"]))
    for n, person in enumerate(people, 1):
        person["number"] = f"SYN-{n:03d}"
    out.write_text(json.dumps({
        "_note": "Synthetic background patients for the Phase 9 lite demo EHR, generated by clinical/synthea/generate.sh. "
                 "Not cases: no encounters, medications, labs or cultures, so no rule may produce a finding for them. "
                 "Names, addresses and phone numbers are Synthea's inventions (phones are 555 numbers).",
        "source": source,
        "patients": [{"number": p.pop("number"), **p} for p in people]}, indent=1) + "\n")
    print(f"{len(people)} background patients -> {out}")


if __name__ == "__main__":
    main(sys.argv[1:])
