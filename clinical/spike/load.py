#!/usr/bin/env python3
"""Phase 9 lite M1 spike: load a scenario into the disposable OpenEMR started by run.sh.

    load.py <scenario.json>

Paths, each the narrowest one OpenEMR 8.4.1 supports (docs/evidence/clinical/ explains the choice):
  patient                           FHIR create (Patient is one of the three FHIR resources that accept writes)
  encounter, problem, prescription  the standard REST API (no FHIR write support)
  lab provider, orders, specimen    SQL (OpenEMR has no API for placing a lab order; it is a UI form)
  susceptibility flags              SQL, list configuration (susceptibility-flags.sql)
  every lab result, the culture     an HL7 v2.5.1 ORU^R01 message through OpenEMR's own importer,
                                    receive_hl7_results(), as a lab interface delivers it
"""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("fhir", HERE / "fhir.py")
fhir = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fhir)


def sql(statement):
    result = subprocess.run([str(HERE / "run.sh"), "sql"], input=statement, text=True, capture_output=True,
                            check=True)
    rows = [line.split("\t") for line in result.stdout.splitlines()]
    return rows[1:] if rows else []


def quote(value):
    return "'" + str(value).replace("\\", "\\\\").replace("'", "''") + "'"


def ok(step, status, body, expected=(200, 201)):
    if status not in expected:
        raise SystemExit(f"{step}: HTTP {status}: {json.dumps(body)[:600] if not isinstance(body, str) else body[:600]}")
    print(f"{step}: HTTP {status}")
    return body


SUSCEPTIBILITY_PANEL = ("29576-6", "Bacterial susceptibility panel")


def hl7_time(value):
    return value.replace("-", "").replace(":", "").replace(" ", "")


def hl7_message(s, pid, encounter, chem_order, cult_order):
    """An ORU^R01 in the HL7 v2.5.1 lab-results style, one ORC group per order: chemistry; the culture, and its
    susceptibility panel as a child report linked by OBR-26 (parent result) and OBR-29 (parent order)."""
    p, chem, cult = s["patient"], s["lab"]["chemistry"], s["lab"]["culture"]
    accession = f"SPK{cult_order}"
    segments = [
        f"MSH|^~\\&|SPIKELAB|SPIKELAB|OPENEMR|OPENEMR|{hl7_time(cult['resulted'])}||ORU^R01^ORU_R01|"
        f"{accession}-1|P|2.5.1",
        f"PID|1||{pid}^^^OPENEMR||{p['family']}^{p['given']}||{p['birth_date'].replace('-', '')}|"
        # PID-13: a fictional 555-01xx number; the importer reads PID-13 and warns when it is absent.
        f"{'F' if p['sex'] == 'female' else 'M'}|||||^PRN^PH^^1^555^5550100",
        f"PV1|1|I|||||||||||||||||{encounter}",
        f"ORC|RE|{chem_order}|SPK{chem_order}",
        # Chemistry.
        f"OBR|1|{chem_order}|SPK{chem_order}-CHEM|{chem['order_code']}^{chem['order_text']}^L|||"
        f"{hl7_time(chem['collected'])}|||||||||||||||{hl7_time(chem['resulted'])}|||F",
    ]
    for n, r in enumerate(chem["results"], 1):
        segments.append(f"OBX|{n}|NM|{r['loinc']}^{r['text']}^LN||{r['value']}|{r['units']}|{r['range']}|"
                        f"{r['flag']}|||F")
    # The culture: organism (CWE, SNOMED CT), colony count, specimen.
    organism_code = f"{cult['order_code']}^{cult['order_text']}^LN"
    cc = cult["colony_count"]
    comparator, number = (cc["value"][0], cc["value"][1:]) if cc["value"][0] in "<>" else ("", cc["value"])
    segments += [
        f"ORC|RE|{cult_order}|{accession}",
        f"OBR|2|{cult_order}|{accession}-UC|{organism_code}|||{hl7_time(cult['collected'])}|||||||||||||||"
        f"{hl7_time(cult['resulted'])}|||F",
        f"OBX|1|CWE|{organism_code}|1|{cult['organism']['snomed']}^{cult['organism']['text']}^SCT||||||F",
        f"OBX|2|SN|{cc['loinc']}^{cc['text']}^LN|1|{comparator}^{number}|{cc['units']}|||||F",
        f"SPM|1|||{cult['specimen']['snomed']}^{cult['specimen']['text']}^SCT|||||||||||||"
        f"{hl7_time(cult['collected'])}|||||||",  # SPM padded to 24 fields, which the importer reads
        # Susceptibility panel: a child of the organism result (OBR-26) and of the culture report (OBR-29).
        f"OBR|3|{cult_order}|{accession}-SUS|{SUSCEPTIBILITY_PANEL[0]}^{SUSCEPTIBILITY_PANEL[1]}^LN|||"
        f"{hl7_time(cult['collected'])}|||||||||||||||{hl7_time(cult['resulted'])}|||F|"
        f"{cult['order_code']}&{cult['order_text']}&LN^1^{cult['organism']['text']}|||"
        f"{cult_order}^{accession}-UC",
    ]
    for n, r in enumerate(cult["susceptibilities"], 1):
        mic = r["mic"]
        comparator = next((c for c in ("<=", ">=", "<", ">") if mic.startswith(c)), "")
        segments.append(f"OBX|{n}|SN|{r['loinc']}^{r['drug']} [Susceptibility] by Minimum inhibitory "
                        f"concentration (MIC)^LN|1|{comparator}^{mic[len(comparator):]}|{r['units']}||"
                        f"{r['interpretation']}|||F")
    return "\r".join(segments) + "\r"


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


def main():
    s = json.loads(Path(sys.argv[1]).read_text())
    p = s["patient"]
    status, body = fhir.call("POST", "fhir/Patient", {
        "resourceType": "Patient",
        # OpenEMR 8.4.1 reads only a name with use "official"; without it, fname and lname are empty.
        "name": [{"use": "official", "family": p["family"], "given": [p["given"]]}],
        "gender": p["sex"], "birthDate": p["birth_date"]})
    body = ok("patient (FHIR create)", status, body)
    puuid = body.get("uuid") or body.get("id") or (body.get("data") or {}).get("uuid")
    if not puuid:
        raise SystemExit(f"patient create returned no id: {json.dumps(body)[:400]}")
    status, body = fhir.call("GET", f"api/patient/{puuid}")
    pid = ok("patient lookup", status, body)["data"]["pid"]

    e = s["encounter"]
    status, body = fhir.call("POST", f"api/patient/{puuid}/encounter", {
        "date": e["start"], "reason": e["reason"], "class_code": e["class_code"], "pc_catid": "5"})
    data = ok("encounter", status, body)["data"]
    encounter = data["encounter"]
    for problem in s["problems"]:
        status, body = fhir.call("POST", f"api/patient/{puuid}/medical_problem", problem)
        ok("problem", status, body)
    for rx in s["prescriptions"]:
        status, body = fhir.call("POST", "api/prescription", {**rx, "patient_id": pid, "encounter": encounter})
        ok("prescription", status, body)

    lab, chem, cult = s["lab"], s["lab"]["chemistry"], s["lab"]["culture"]
    order = ("INSERT INTO procedure_order (provider_id, patient_id, encounter_id, date_ordered, order_priority, "
             "order_status, activity, lab_id, procedure_order_type, order_intent) "
             f"VALUES (1, {int(pid)}, {int(encounter)}, {quote(lab['order_date'])}, 'normal', 'pending', 1, @lab, "
             "'laboratory_test', 'order');\n")
    code = ("INSERT INTO procedure_order_code (procedure_order_id, procedure_order_seq, procedure_code, "
            "procedure_name, procedure_source, procedure_order_title, procedure_type) VALUES "
            "({order}, {seq}, {code}, {text}, '1', 'laboratory_test', 'laboratory_test');\n")
    rows = sql(
        (HERE / "susceptibility-flags.sql").read_text() +
        "INSERT INTO procedure_providers (name, npi, DorP, direction, protocol, active, date_created) "
        f"VALUES ({quote(lab['name'])}, '', 'D', 'B', 'DL', 1, NOW());\n"
        "SET @lab = LAST_INSERT_ID();\n"
        + order + "SET @chem = LAST_INSERT_ID();\n"
        + code.format(order="@chem", seq=1, code=quote(chem["order_code"]), text=quote(chem["order_text"]))
        + order + "SET @cult = LAST_INSERT_ID();\n"
        + code.format(order="@cult", seq=1, code=quote(cult["order_code"]), text=quote(cult["order_text"]))
        # Culture with susceptibilities ordered together, as is common: the panel is an ordered test on the same
        # order, not a lab-added reflex.
        + code.format(order="@cult", seq=2, code=quote(SUSCEPTIBILITY_PANEL[0]), text=quote(SUSCEPTIBILITY_PANEL[1]))
        # The specimen as the order form records it at collection (FHIR Specimen reads this table), for both tests.
        + "".join(
            "INSERT INTO procedure_specimen (procedure_order_id, procedure_order_seq, specimen_identifier, "
            "accession_identifier, specimen_type_code, specimen_type, collected_date, created_at, deleted) "
            f"VALUES (@cult, {seq}, CONCAT('SPK', @cult, '-UC-1'), CONCAT('SPK', @cult), "
            f"{quote(cult['specimen']['snomed'])}, {quote(cult['specimen']['text'])}, "
            f"{quote(cult['collected'])}, NOW(), 0);\n" for seq in (1, 2)) +
        "SELECT @lab, @chem, @cult;")
    lab_id, chem_order, cult_order = rows[-1]
    print(f"lab orders (SQL): chemistry {chem_order}, culture {cult_order} with its specimen")

    message = hl7_message(s, pid, encounter, chem_order, cult_order)
    subprocess.run(["podman", "exec", "-i", "openemr-spike-openemr", "sh", "-c",
                    "cat > /tmp/spike-import.php"], input=IMPORT_PHP, text=True, check=True)
    result = subprocess.run(["podman", "exec", "-i", "-u", "apache", "openemr-spike-openemr",
                             "php", "/tmp/spike-import.php", lab_id],
                            input=message, text=True, capture_output=True)
    out = result.stdout.strip().splitlines()
    print("HL7 import:", out[-1] if out else "(no output)", result.stderr.strip()[-600:])
    report = json.loads(out[-1]) if out else {}
    if result.returncode or report.get("result", {}).get("fatal") or report.get("result", {}).get("mssgs"):
        raise SystemExit("HL7 import reported problems; see above")
    print(json.dumps({"patient": puuid, "pid": pid, "encounter": encounter, "orders": [chem_order, cult_order]}))


if __name__ == "__main__":
    main()
