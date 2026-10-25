#!/usr/bin/env python3
"""Load the Phase 9 lite scenario library into OpenEMR (plan M2), with one command and idempotently.

    load.py [--target spike|cluster] [--reset] [--no-background] [case.json ...]     default: every case in cases/

--target is the local spike (the default) or the clinical namespace (k8s/clinical, kubectl; owner run
scripts/clinical/load-scenarios.sh, after register-gateway.sh). Both are reached the same way, from inside their
containers, so no credential reaches this machine (targets.py). --reset (spike only) destroys the local instance and starts a fresh one first (clinical/spike/run.sh down, up, api), so the
result is a known state built only from the repository. Without it, cases already present (by patient number
LV-<case id>) are skipped, so running it twice changes nothing. The Synthea background patients in
clinical/synthea/background.json (patient numbers SYN-nnn) are loaded too, unless --no-background: demographics,
problems and allergies only, so they can never produce a finding. Every case is checked first; an invalid case
stops the load before anything is written.

Load paths are those the M1 spike established (docs/evidence/clinical/20261025-openemr-m1-spike/): FHIR for the
patient, the REST API for the encounter, problems, allergies, prescriptions and vital signs, SQL for the order-side
rows OpenEMR's order form writes, and an HL7 v2.5.1 ORU^R01 through OpenEMR's own importer for every result.
Times in a case carry an offset; OpenEMR stores them in the instance's UTC.
"""
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
SPIKE = HERE.parent / "spike"


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


fhir = module("fhir", SPIKE / "fhir.py")
targets = module("targets", HERE / "targets.py")
target = None  # set by main()
checker = module("check_cases", HERE / "check_cases.py")
LAB = "LocumView Scenario Laboratory"
# OpenEMR stores a prescription's route as an id in its drug_route list, which carries the NCI code FHIR emits;
# free text such as "IV" matches no entry and is dropped from MedicationRequest.dosageInstruction.route.
ROUTES = {"IV": "11", "PO": "1", "IM": "10", "SC": "9"}
PANEL = ("29576-6", "Bacterial susceptibility panel")
IMPORT_PHP = r"""<?php
// Runs OpenEMR's own HL7 results importer on one message, without a browser session.
$_GET['site'] = 'default';
$ignoreAuth = true;
require_once '/var/www/localhost/htdocs/openemr/interface/globals.php';
require_once '/var/www/localhost/htdocs/openemr/interface/orders/receive_hl7_results.inc.php';
$hl7 = file_get_contents('php://stdin');
$match = [];
$result = receive_hl7_results($hl7, $match, (int)$argv[1], 'B', false);
echo json_encode(['result' => $result, 'match' => $match]), "\n";
"""


def run(*args, stdin=None):
    return subprocess.run([str(SPIKE / "run.sh"), *args], input=stdin, text=True, capture_output=True, check=True).stdout


def sql(statement):
    return target.sql(statement)


quote = targets.quote


def utc(value):
    """'2026-10-20T14:00:00-04:00' -> '2026-10-20 18:00:00' (the instance stores UTC)."""
    return datetime.fromisoformat(value).astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def hl7(value):
    return utc(value).replace("-", "").replace(":", "").replace(" ", "")


def ok(step, status, body):
    if status not in (200, 201):
        raise SystemExit(f"{step}: HTTP {status}: {json.dumps(body)[:600] if not isinstance(body, str) else body[:600]}")
    return body


def allergy_body(x):
    """OpenEMR allergy fields; FHIR AllergyIntolerance.code comes only from the coded diagnosis field."""
    body = {k: v for k, v in x.items() if k in ("title", "begdate", "reaction", "severity")}
    if "rxnorm" in x:
        body["diagnosis"] = f"RXCUI:{x['rxnorm']}"
    elif "snomed" in x:
        body["diagnosis"] = f"SNOMED-CT:{x['snomed']}"
    return body


def lab_provider():
    rows = sql(f"SELECT ppid FROM procedure_providers WHERE name = {quote(LAB)};")
    if rows:
        return rows[0][0]
    rows = sql("INSERT INTO procedure_providers (name, npi, DorP, direction, protocol, active, date_created) "
               f"VALUES ({quote(LAB)}, '', 'D', 'B', 'DL', 1, NOW()); SELECT LAST_INSERT_ID();")
    return rows[-1][0]


def place_order(pid, encounter, lab_id, ordered, tests, specimen=None):
    """Insert an order with its tests (and the specimen for each test) as the order form would. Returns its id."""
    statements = [
        "INSERT INTO procedure_order (provider_id, patient_id, encounter_id, date_ordered, order_priority, "
        "order_status, activity, lab_id, procedure_order_type, order_intent) "
        f"VALUES (1, {int(pid)}, {int(encounter)}, {quote(ordered)}, 'normal', 'pending', 1, {int(lab_id)}, "
        "'laboratory_test', 'order');",
        "SET @o = LAST_INSERT_ID();"]
    for seq, (code, text) in enumerate(tests, 1):
        statements.append(
            "INSERT INTO procedure_order_code (procedure_order_id, procedure_order_seq, procedure_code, procedure_name, "
            f"procedure_source, procedure_order_title, procedure_type) VALUES (@o, {seq}, {quote(code)}, {quote(text)}, "
            "'1', 'laboratory_test', 'laboratory_test');")
        if specimen:
            statements.append(
                "INSERT INTO procedure_specimen (procedure_order_id, procedure_order_seq, specimen_identifier, "
                "accession_identifier, specimen_type_code, specimen_type, collected_date, created_at, deleted) "
                f"VALUES (@o, {seq}, CONCAT('LV', @o, '-1'), CONCAT('LV', @o), {quote(specimen['snomed'])}, "
                f"{quote(specimen['text'])}, {quote(specimen['collected'])}, NOW(), 0);")
    statements.append("SELECT @o;")
    return sql("\n".join(statements))[-1][0]


def comparator(value):
    op = next((c for c in ("<=", ">=", "<", ">") if value.startswith(c)), "")
    return op, value[len(op):]


def message(case, pid, encounter, orders):
    """One ORU^R01 for the case: one ORC group per order; a culture's susceptibility panel is a child report linked
    by OBR-26 (the organism result) and OBR-29 (the culture report)."""
    orders = [o for o in orders if o["resulted"]]  # pending cultures: ordered, nothing resulted yet
    p, last = case["patient"], max(o["resulted"] for o in orders)
    segments = [
        f"MSH|^~\\&|LVLAB|LVLAB|OPENEMR|OPENEMR|{hl7(last)}||ORU^R01^ORU_R01|LV{orders[0]['id']}|P|2.5.1",
        # PID-13: a fictional 555-01xx number; the importer reads PID-13 and warns when it is absent.
        f"PID|1||{pid}^^^OPENEMR||{p['family']}^{p['given']}||{p['birth_date'].replace('-', '')}|"
        f"{'F' if p['sex'] == 'female' else 'M'}|||||^PRN^PH^^1^555^5550100",
        f"PV1|1|I|||||||||||||||||{encounter}"]
    n = 0
    for o in orders:
        n += 1
        acc = f"LV{o['id']}"
        segments.append(f"ORC|RE|{o['id']}|{acc}")
        if o["kind"] == "lab":
            lab = o["data"]
            segments.append(f"OBR|{n}|{o['id']}|{acc}-1|{lab['order_code']}^{lab['order_text']}^L|||{hl7(lab['collected'])}"
                            f"|||||||||||||||{hl7(lab['resulted'])}|||F")
            for i, r in enumerate(lab["results"], 1):
                segments.append(f"OBX|{i}|NM|{r['loinc']}^{r['text']}^LN||{r['value']}|{r['units']}|{r.get('range', '')}|"
                                f"{r.get('flag', '')}|||F")
            continue
        cult = o["data"]
        code = f"{cult['order_code']}^{cult['order_text']}^LN"
        segments.append(f"OBR|{n}|{o['id']}|{acc}-1|{code}|||{hl7(cult['collected'])}|||||||||||||||{hl7(cult['resulted'])}|||F")
        if cult.get("no_growth"):
            segments.append(f"OBX|1|CWE|{code}|1|264868006^No growth^SCT||||||F")
        else:
            org = cult["organism"]
            segments.append(f"OBX|1|CWE|{code}|1|{org['snomed']}^{org['text']}^SCT||||||F")
            if "colony_count" in cult:
                cc = cult["colony_count"]
                op, number = comparator(cc["value"])
                segments.append(f"OBX|2|SN|{cc['loinc']}^{cc['text']}^LN|1|{op}^{number}|{cc['units']}|||||F")
        segments.append(f"SPM|1|||{cult['specimen']['snomed']}^{cult['specimen']['text']}^SCT|||||||||||||"
                        f"{hl7(cult['collected'])}|||||||")
        if cult.get("susceptibilities"):
            n += 1
            segments.append(f"OBR|{n}|{o['id']}|{acc}-2|{PANEL[0]}^{PANEL[1]}^LN|||{hl7(cult['collected'])}"
                            f"|||||||||||||||{hl7(cult['resulted'])}|||F|"
                            f"{cult['order_code']}&{cult['order_text']}&LN^1^{cult['organism']['text']}|||{o['id']}^{acc}-1")
            for i, s in enumerate(cult["susceptibilities"], 1):
                op, number = comparator(s["mic"])
                segments.append(f"OBX|{i}|SN|{s['loinc']}^{s['drug']} [Susceptibility] by Minimum inhibitory "
                                f"concentration (MIC)^LN|1|{op}^{number}|{s['units']}||{s['interpretation']}|||F")
    return "\r".join(segments) + "\r"


def load(case):
    number = f"LV-{case['id']}"
    if sql(f"SELECT pid FROM patient_data WHERE pubpid = {quote(number)};"):
        print(f"{case['id']}: already loaded, skipped")
        return
    p, e = case["patient"], case["encounter"]
    status, body = target.api("POST", "fhir/Patient", {
        "resourceType": "Patient",
        # OpenEMR 8.4.1 reads only a name with use "official", and an identifier of type PT as its patient number.
        "name": [{"use": "official", "family": p["family"], "given": [p["given"]]}],
        "identifier": [{"type": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "PT"}]},
                        "value": number}],
        "gender": p["sex"], "birthDate": p["birth_date"]})
    body = ok(f"{case['id']}: patient", status, body)
    puuid = body.get("uuid") or body.get("id") or (body.get("data") or {}).get("uuid")
    pid = ok("patient lookup", *target.api("GET", f"api/patient/{puuid}"))["data"]["pid"]
    data = ok("encounter", *target.api("POST", f"api/patient/{puuid}/encounter", {
        "date": utc(e["start"]), "reason": e["reason"], "class_code": e["class_code"], "pc_catid": "5"}))["data"]
    encounter = data["encounter"]
    for x in case.get("problems", []):
        ok("problem", *target.api("POST", f"api/patient/{puuid}/medical_problem", x))
    for x in case.get("allergies", []):
        ok("allergy", *target.api("POST", f"api/patient/{puuid}/allergy", allergy_body(x)))
    for x in case.get("prescriptions", []):
        rx = {"drug": x["drug"], "rxnorm_drugcode": x["rxnorm"], "start_date": x["start"], "route": ROUTES[x["route"]],
              "drug_dosage_instructions": x["instructions"], "patient_id": pid, "encounter": encounter}
        if "end" in x:
            rx["end_date"] = x["end"]
        ok("prescription", *target.api("POST", "api/prescription", rx))
    for v in case.get("vitals", []):
        vital = {"date": utc(v["taken"]), **{("temperature" if k == "temperature_f" else k): str(val)
                                            for k, val in v.items() if k != "taken"}}
        ok("vital signs", *target.api("POST", f"api/patient/{pid}/encounter/{encounter}/vital", vital))

    lab_id, orders = lab_provider(), []
    for lab in case.get("labs", []):
        oid = place_order(pid, encounter, lab_id, utc(lab["collected"]), [(lab["order_code"], lab["order_text"])])
        orders.append({"id": oid, "kind": "lab", "data": lab, "resulted": lab["resulted"]})
    for cult in case.get("cultures", []):
        # Culture and susceptibilities ordered together, so every result is linked to the specimen (M1 finding).
        tests = [(cult["order_code"], cult["order_text"])] + ([PANEL] if cult.get("susceptibilities") else [])
        oid = place_order(pid, encounter, lab_id, utc(cult["collected"]), tests,
                          {**cult["specimen"], "collected": utc(cult["collected"])})
        orders.append({"id": oid, "kind": "culture", "data": cult, "resulted": cult.get("resulted")})
    if any(o["resulted"] for o in orders):
        done = target.php(target.install("import.php", IMPORT_PHP), str(lab_id),
                          stdin=message(case, pid, encounter, orders))
        lines = done.stdout.strip().splitlines()
        report = json.loads(lines[-1]) if lines else {}
        if done.returncode or not lines or report["result"].get("mssgs") or report["result"].get("needmatch"):
            raise SystemExit(f"{case['id']}: HL7 import problems: {done.stdout[-400:]} {done.stderr[-400:]}")
        if done.stderr.strip():
            print(f"{case['id']}: importer warnings: {done.stderr.strip()[-300:]}")
    print(f"{case['id']}: loaded (patient {number}, {len(orders)} orders)")


def load_background():
    people = json.loads((HERE.parent / "synthea" / "background.json").read_text())["patients"]
    added = 0
    for p in people:
        if sql(f"SELECT pid FROM patient_data WHERE pubpid = {quote(p['number'])};"):
            continue
        status, body = target.api("POST", "fhir/Patient", {
            "resourceType": "Patient",
            "name": [{"use": "official", "family": p["family"], "given": [p["given"]]}],
            "identifier": [{"type": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "PT"}]},
                            "value": p["number"]}],
            "gender": p["sex"], "birthDate": p["birth_date"]})
        body = ok(f"{p['number']}: patient", status, body)
        puuid = body.get("uuid") or body.get("id") or (body.get("data") or {}).get("uuid")
        for x in p["problems"]:
            ok(f"{p['number']}: problem", *target.api("POST", f"api/patient/{puuid}/medical_problem", {
                "title": x["title"], "begdate": x["begdate"], "diagnosis": f"SNOMED-CT:{x['snomed']}"}))
        for x in p["allergies"]:
            ok(f"{p['number']}: allergy", *target.api("POST", f"api/patient/{puuid}/allergy", allergy_body(x)))
        added += 1
    print(f"background: {added} loaded, {len(people) - added} already present")


def main(argv):
    global target
    name = argv[argv.index("--target") + 1] if "--target" in argv else "spike"
    if name not in targets.CONTAINERS:
        raise SystemExit(f"--target is spike or cluster, not {name!r}")
    argv = [a for i, a in enumerate(argv) if a != "--target" and (i == 0 or argv[i - 1] != "--target")]
    reset = "--reset" in argv
    if reset and name != "spike":
        raise SystemExit("--reset destroys the instance; it is for the local spike only")
    paths = [Path(a) for a in argv if not a.startswith("--")] or sorted((HERE / "cases").glob("*.json"))
    citations = json.loads((HERE / "citations.json").read_text())["citations"]
    problems = [e for p in paths for e in checker.check(p, citations)]
    if problems:
        print("\n".join(problems), file=sys.stderr)
        raise SystemExit("cases failed the check; nothing loaded")
    if reset:
        for step in ("down", "up", "api"):
            print(run(step).strip().splitlines()[-1])
    target = targets.Target(name)
    # Result flags for S, I, R and SDD (list configuration, idempotent).
    sql((SPIKE / "susceptibility-flags.sql").read_text())
    with target.session(fhir.SCOPES):
        if "--no-background" not in argv:
            load_background()
        for path in paths:
            load(json.loads(path.read_text()))


if __name__ == "__main__":
    main(sys.argv[1:])
