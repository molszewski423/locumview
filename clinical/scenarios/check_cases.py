#!/usr/bin/env python3
"""Check the Phase 9 lite scenario library (clinical/scenarios/cases/*.json) against case format locumview-case/1.

    check_cases.py [--require-approved] [case.json ...]     default: every case in cases/

Standard library only, so it runs unchanged in pre-commit and CI. Refuses a case without a synthetic provenance
block (plan M2). --require-approved also refuses any case whose clinical review is not approved: use it for a
frozen evaluation build (plan M6). The format is described in README.md.
"""
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
SCHEMA = "locumview-case/1"
KINDS = {"finding", "negative-control", "ambiguous"}
MODULES = {"stewardship", "iv-to-po"}
FINDING_TYPES = {"bug-drug-mismatch", "suboptimal-agent", "missing-empiric-coverage", "de-escalation",
                 "iv-to-po-switch", "redundant-coverage", "duration-review"}
INTERPRETATIONS = {"S", "I", "R", "SDD", "NS"}
TIME = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?(Z|[+-]\d{2}:\d{2})$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
LOINC = re.compile(r"^\d{1,7}-\d$")
DIGITS = re.compile(r"^\d+$")
MIC = re.compile(r"^(<=|>=|<|>)?\d+(\.\d+)?$")


class Case:
    def __init__(self, path, citations):
        self.path, self.citations, self.errors = path, citations, []

    def error(self, where, message):
        self.errors.append(f"{self.path.name}: {where}: {message}")

    def fields(self, where, value, required, optional=()):
        """Check value is an object with the required keys, and no keys outside required and optional."""
        if not isinstance(value, dict):
            self.error(where, "must be an object")
            return {}
        for key in required:
            if key not in value:
                self.error(where, f"missing '{key}'")
        for key in value:
            if key not in required and key not in optional:
                self.error(where, f"unknown key '{key}'")
        return value

    def text(self, where, value):
        if not isinstance(value, str) or not value.strip():
            self.error(where, "must be non-empty text")

    def match(self, where, value, pattern, what):
        if not isinstance(value, str) or not pattern.match(value):
            self.error(where, f"must be {what}, got {value!r}")

    def items(self, where, value, minimum=0):
        if not isinstance(value, list):
            self.error(where, "must be a list")
            return []
        if len(value) < minimum:
            self.error(where, f"needs at least {minimum}")
        return value

    def order(self, where, collected, resulted):
        if isinstance(collected, str) and isinstance(resulted, str) and TIME.match(collected) and TIME.match(resulted):
            # Same-offset times compare as text; mixed offsets are allowed but not ordered here.
            if collected[-6:] == resulted[-6:] and resulted < collected:
                self.error(where, "resulted before collected")


def check(path, citations, require_approved=False):
    c = Case(path, citations)
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        return [f"{path.name}: not readable JSON: {error}"]
    d = c.fields("case", data,
                 ["schema", "id", "version", "title", "kind", "modules", "provenance", "story", "patient", "encounter",
                  "expected_findings", "reference_answer", "rationale", "citations"],
                 ["problems", "allergies", "prescriptions", "vitals", "labs", "cultures", "acceptable_answers"])
    if d.get("schema") != SCHEMA:
        c.error("schema", f"must be {SCHEMA!r}")
    c.match("id", d.get("id"), re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$"), "lowercase words joined by hyphens")
    if d.get("id") != path.stem:
        c.error("id", f"must match the file name ({path.stem})")
    c.match("version", d.get("version"), re.compile(r"^\d+\.\d+\.\d+$"), "a semantic version")
    c.text("title", d.get("title"))
    c.text("story", d.get("story"))
    kind = d.get("kind")
    if kind not in KINDS:
        c.error("kind", f"must be one of {sorted(KINDS)}")
    modules = c.items("modules", d.get("modules"), 1)
    for m in modules:
        if m not in MODULES:
            c.error("modules", f"unknown module {m!r}")

    p = c.fields("provenance", d.get("provenance"), ["source", "author", "created", "clinical_review"])
    if p.get("source") != "synthetic":
        c.error("provenance.source", "must be 'synthetic': only synthetic cases are allowed (policy rule 1)")
    c.text("provenance.author", p.get("author"))
    c.match("provenance.created", p.get("created"), DATE, "a date")
    r = c.fields("provenance.clinical_review", p.get("clinical_review"), ["status"], ["by", "date", "notes"])
    if r.get("status") not in ("pending", "approved"):
        c.error("provenance.clinical_review.status", "must be 'pending' or 'approved'")
    if r.get("status") == "approved":
        c.text("provenance.clinical_review.by", r.get("by"))
        c.match("provenance.clinical_review.date", r.get("date"), DATE, "a date")
    elif require_approved:
        c.error("provenance.clinical_review", "not approved; an evaluation build needs every case approved")

    pt = c.fields("patient", d.get("patient"), ["family", "given", "birth_date", "sex"])
    c.text("patient.family", pt.get("family"))
    c.text("patient.given", pt.get("given"))
    c.match("patient.birth_date", pt.get("birth_date"), DATE, "a date")
    if pt.get("sex") not in ("female", "male"):
        c.error("patient.sex", "must be 'female' or 'male'")
    e = c.fields("encounter", d.get("encounter"), ["class_code", "start", "reason"])
    c.match("encounter.start", e.get("start"), TIME, "a time with an offset")
    c.text("encounter.reason", e.get("reason"))

    for i, x in enumerate(c.items("problems", d.get("problems", []))):
        x = c.fields(f"problems[{i}]", x, ["title", "begdate"], ["diagnosis"])
        c.match(f"problems[{i}].begdate", x.get("begdate"), DATE, "a date")
    for i, x in enumerate(c.items("allergies", d.get("allergies", []))):
        x = c.fields(f"allergies[{i}]", x, ["title", "begdate"], ["reaction", "severity"])
        c.match(f"allergies[{i}].begdate", x.get("begdate"), DATE, "a date")
    for i, x in enumerate(c.items("prescriptions", d.get("prescriptions", []))):
        x = c.fields(f"prescriptions[{i}]", x, ["drug", "rxnorm", "start", "route", "instructions"], ["end"])
        c.match(f"prescriptions[{i}].rxnorm", x.get("rxnorm"), DIGITS, "an RxNorm code")
        c.match(f"prescriptions[{i}].start", x.get("start"), DATE, "a date")
        if "end" in x:
            c.match(f"prescriptions[{i}].end", x.get("end"), DATE, "a date")
        if x.get("route") not in ("IV", "PO", "IM", "SC"):
            c.error(f"prescriptions[{i}].route", "must be IV, PO, IM or SC")
    for i, x in enumerate(c.items("vitals", d.get("vitals", []))):
        x = c.fields(f"vitals[{i}]", x, ["taken"], ["temperature_f", "pulse", "bps", "bpd", "respiration",
                                                   "oxygen_saturation"])
        c.match(f"vitals[{i}].taken", x.get("taken"), TIME, "a time with an offset")
    for i, x in enumerate(c.items("labs", d.get("labs", []))):
        where = f"labs[{i}]"
        x = c.fields(where, x, ["order_code", "order_text", "collected", "resulted", "results"])
        for key in ("collected", "resulted"):
            c.match(f"{where}.{key}", x.get(key), TIME, "a time with an offset")
        c.order(where, x.get("collected"), x.get("resulted"))
        for j, y in enumerate(c.items(f"{where}.results", x.get("results"), 1)):
            y = c.fields(f"{where}.results[{j}]", y, ["loinc", "text", "value", "units"], ["range", "flag"])
            c.match(f"{where}.results[{j}].loinc", y.get("loinc"), LOINC, "a LOINC code")
    for i, x in enumerate(c.items("cultures", d.get("cultures", []))):
        where = f"cultures[{i}]"
        x = c.fields(where, x, ["order_code", "order_text", "specimen", "collected"],
                     ["resulted", "status", "organism", "colony_count", "susceptibilities", "no_growth"])
        c.match(f"{where}.order_code", x.get("order_code"), LOINC, "a LOINC code")
        c.match(f"{where}.collected", x.get("collected"), TIME, "a time with an offset")
        sp = c.fields(f"{where}.specimen", x.get("specimen"), ["snomed", "text"])
        c.match(f"{where}.specimen.snomed", sp.get("snomed"), DIGITS, "a SNOMED CT code")
        if x.get("status", "final") not in ("final", "pending"):
            c.error(f"{where}.status", "must be 'final' or 'pending'")
        if x.get("status") == "pending":
            # Ordered and collected, no result yet: the order is placed, nothing is sent through the lab interface.
            for key in ("resulted", "organism", "colony_count", "susceptibilities", "no_growth"):
                if key in x:
                    c.error(where, f"a pending culture has no '{key}'")
            continue
        c.match(f"{where}.resulted", x.get("resulted"), TIME, "a time with an offset")
        c.order(where, x.get("collected"), x.get("resulted"))
        # One organism per culture: the owner's M1 decision until OpenEMR links susceptibilities to organisms.
        if x.get("no_growth") is True:
            if "organism" in x or x.get("susceptibilities"):
                c.error(where, "no_growth cultures have no organism or susceptibilities")
        else:
            if isinstance(x.get("organism"), list):
                c.error(f"{where}.organism", "exactly one organism per culture (M1 decision, option 4)")
            org = c.fields(f"{where}.organism", x.get("organism"), ["snomed", "text"])
            c.match(f"{where}.organism.snomed", org.get("snomed"), DIGITS, "a SNOMED CT code")
            if "colony_count" in x:
                cc = c.fields(f"{where}.colony_count", x["colony_count"], ["loinc", "text", "value", "units"])
                c.match(f"{where}.colony_count.loinc", cc.get("loinc"), LOINC, "a LOINC code")
            for j, s in enumerate(c.items(f"{where}.susceptibilities", x.get("susceptibilities", []))):
                s = c.fields(f"{where}.susceptibilities[{j}]", s, ["loinc", "drug", "mic", "units", "interpretation"])
                c.match(f"{where}.susceptibilities[{j}].loinc", s.get("loinc"), LOINC, "a LOINC code")
                c.match(f"{where}.susceptibilities[{j}].mic", s.get("mic"), MIC, "an MIC such as 4, <=0.25 or >=32")
                if s.get("interpretation") not in INTERPRETATIONS:
                    c.error(f"{where}.susceptibilities[{j}].interpretation", f"must be one of {sorted(INTERPRETATIONS)}")

    findings = c.items("expected_findings", d.get("expected_findings"))
    for i, f in enumerate(findings):
        f = c.fields(f"expected_findings[{i}]", f, ["module", "type", "summary"], ["drug"])
        if f.get("module") not in modules:
            c.error(f"expected_findings[{i}].module", "must be one of the case's modules")
        if f.get("type") not in FINDING_TYPES:
            c.error(f"expected_findings[{i}].type", f"must be one of {sorted(FINDING_TYPES)}")
        c.text(f"expected_findings[{i}].summary", f.get("summary"))
    if kind == "finding" and not findings:
        c.error("expected_findings", "a 'finding' case needs at least one expected finding")
    if kind == "negative-control" and findings:
        c.error("expected_findings", "a negative control has no expected findings")
    if kind == "ambiguous":
        for a in c.items("acceptable_answers", d.get("acceptable_answers"), 2):
            c.text("acceptable_answers[]", a)
    elif "acceptable_answers" in d:
        c.error("acceptable_answers", "only ambiguous cases list acceptable answers")
    c.text("reference_answer", d.get("reference_answer"))
    c.text("rationale", d.get("rationale"))
    for i, ref in enumerate(c.items("citations", d.get("citations"), 1)):
        ref = c.fields(f"citations[{i}]", ref, ["ref", "supports"])
        if ref.get("ref") not in citations:
            c.error(f"citations[{i}].ref", f"unknown reference {ref.get('ref')!r} (see citations.json)")
        c.text(f"citations[{i}].supports", ref.get("supports"))
    return c.errors


def main(argv):
    require_approved = "--require-approved" in argv
    paths = [Path(a) for a in argv if not a.startswith("--")] or sorted((HERE / "cases").glob("*.json"))
    citations = json.loads((HERE / "citations.json").read_text())["citations"]
    errors, kinds, ids = [], {}, {}
    for path in paths:
        errors += check(path, citations, require_approved)
        try:
            data = json.loads(path.read_text())
            kinds[data.get("kind")] = kinds.get(data.get("kind"), 0) + 1
            ids.setdefault(data.get("id"), []).append(path.name)
        except (OSError, ValueError):
            pass
    errors += [f"duplicate id {i!r} in {', '.join(names)}" for i, names in ids.items() if len(names) > 1]
    for line in errors:
        print(line, file=sys.stderr)
    summary = ", ".join(f"{n} {k}" for k, n in sorted(kinds.items(), key=lambda kv: str(kv[0])))
    print(f"{len(paths)} cases ({summary}): {'FAILED, ' + str(len(errors)) + ' problems' if errors else 'ok'}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
