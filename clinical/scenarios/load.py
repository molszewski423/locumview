#!/usr/bin/env python3
"""Load the Phase 9 lite scenario library into OpenEMR (plan M2), with one command and idempotently.

    load.py [--target spike|cluster] [--reset] [--no-background] [--no-chart-details] [case.json ...]
                                                                       default: every case in cases/

--target is the local spike (the default) or the clinical namespace (k8s/clinical, kubectl; owner run
scripts/clinical/load-scenarios.sh, after register-gateway.sh). Both are reached the same way, from inside their
containers, so no credential reaches this machine (targets.py). --reset (spike only) destroys the local instance and starts a fresh one first (clinical/spike/run.sh down, up, api), so the
result is a known state built only from the repository. Without it, cases already present (by patient number
LV-<case id>) are skipped, so running it twice changes nothing. The Synthea background patients in
clinical/synthea/background.json (patient numbers SYN-nnn) are loaded too, unless --no-background: demographics,
problems, allergies and immunizations only, so they can never produce a finding. Each patient's photograph
(clinical/photos/<patient number>.jpg, AI-generated) is stored once; demographics and immunizations are brought up
to date on every run, also for patients loaded earlier. Every case is checked first; an invalid case
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


UUIDS_PHP = r"""<?php
// Gives every row that lacks one its FHIR id (uuid), with OpenEMR's own UuidRegistry. OpenEMR otherwise assigns them
// on the first FHIR read, and two concurrent first reads (the app fetches resource types in parallel) can collide:
// "Record has changed since last read in table 'procedure_report'" and HTTP 500 (docs/upstream/openemr-8.4.1.md #13).
$_GET['site'] = 'default';
$ignoreAuth = true;
require_once '/var/www/localhost/htdocs/openemr/interface/globals.php';
\OpenEMR\Common\Uuid\UuidRegistry::populateAllMissingUuids(false);
echo "ok\n";
"""


PHOTO_PHP = r"""<?php
// Stores a JPEG (base64 on stdin) as the patient's photograph with OpenEMR's own Document class, in the category the
// patient summary shows (global patient_photo_category_name). The file name carries the image's hash: the same image
// is stored once; a changed image replaces the patient's earlier photographs (marked deleted, OpenEMR's own flag,
// and taken out of the category).
$_GET['site'] = 'default';
$ignoreAuth = true;
require_once '/var/www/localhost/htdocs/openemr/interface/globals.php';
require_once $GLOBALS['fileroot'] . '/library/classes/Document.class.php';
$pid = (int)$argv[1];
$name = $argv[2];
$category = sqlQuery("SELECT id FROM categories WHERE name = ?", [$GLOBALS['patient_photo_category_name']])['id'] ?? 0;
if (!$category) { echo "error: no photograph category\n"; exit(1); }
$photos = "FROM documents d JOIN categories_to_documents c ON c.document_id = d.id " .
          "WHERE d.foreign_id = ? AND c.category_id = ? AND d.deleted = 0";
// A replaced photograph also leaves the category: OpenEMR's header picks the first photograph in it without checking
// the deleted flag (docs/upstream/openemr-8.4.1.md item 14). Also cleans up photographs replaced before this fix.
$unlink = "DELETE c FROM categories_to_documents c JOIN documents d ON d.id = c.document_id " .
          "WHERE d.foreign_id = ? AND c.category_id = ? AND d.deleted = 1";
sqlStatement($unlink, [$pid, $category]);
if (sqlQuery("SELECT COUNT(*) AS n $photos AND d.name = ?", [$pid, $category, $name])['n']) { echo "present\n"; exit(0); }
$data = base64_decode(stream_get_contents(STDIN), true);
if ($data === false || strlen($data) < 1000) { echo "error: no image\n"; exit(1); }
$document = new Document();
$error = $document->createDocument($pid, $category, $name, 'image/jpeg', $data);
if ($error) { echo "error: $error\n"; exit(1); }
sqlStatement("UPDATE documents d JOIN categories_to_documents c ON c.document_id = d.id SET d.deleted = 1 " .
             "WHERE d.foreign_id = ? AND c.category_id = ? AND d.deleted = 0 AND d.id <> ?",
             [$pid, $category, $document->get_id()]);
sqlStatement($unlink, [$pid, $category]);
echo "ok\n";
"""
BRANDING_PHP = r"""<?php
// LocumView's login page branding (changelog #167), with OpenEMR's own settings and logo folders only: the LocumView
// wordmark (SVG, base64 on stdin; fixed dark colors: OpenEMR's login page has no dark mode) as the primary login logo,
// OpenEMR's own colored logo as the secondary one, a tagline.
$_GET['site'] = 'default';
$ignoreAuth = true;
require_once '/var/www/localhost/htdocs/openemr/interface/globals.php';
$data = base64_decode(stream_get_contents(STDIN), true);
if ($data === false || strpos($data, '<svg') === false) { echo "error: no logo\n"; exit(1); }
$base = $GLOBALS['OE_SITE_DIR'] . '/images/logos/core/login';
// The image ships these folders read-only for their owner, the web server user this runs as: make them writable
// for the owner, and check every write (a failed write must not report success).
foreach (['primary', 'secondary'] as $d) {
    if (!is_dir("$base/$d") && !mkdir("$base/$d", 0755, true)) { echo "error: cannot create $base/$d\n"; exit(1); }
    if (!is_writable("$base/$d") && !chmod("$base/$d", 0755)) { echo "error: cannot make $base/$d writable\n"; exit(1); }
    foreach (glob("$base/$d/logo.*") ?: [] as $old) {
        if (!unlink($old)) { echo "error: cannot remove $old\n"; exit(1); }
    }
}
if (file_put_contents("$base/primary/logo.svg", $data) === false
    || !copy($GLOBALS['fileroot'] . '/public/images/logos/core/login/primary/logo.png', "$base/secondary/logo.png")) {
    echo "error: cannot write the login logos\n"; exit(1);
}
$settings = [
    'login_tagline_text' => 'LocumView reference EHR · synthetic patients only',
    'show_tagline_on_login' => '1', 'show_primary_logo' => '1', 'extra_logo_login' => '1',
    'secondary_logo_position' => 'second', 'logo_position' => 'flex-column',
    'primary_logo_width' => 'w-75', 'secondary_logo_width' => 'w-25',
    'display_acknowledgements_on_login' => '1', 'openemr_name' => 'LocumView · OpenEMR',
];
foreach ($settings as $name => $value) {
    sqlStatement("REPLACE INTO globals (gl_name, gl_index, gl_value) VALUES (?, 0, ?)", [$name, $value]);
}
echo "ok\n";
"""


def branding():
    import base64
    logo = (HERE / "branding" / "locumview-login-logo.svg").read_bytes()
    done = target.php(target.install("branding.php", BRANDING_PHP), stdin=base64.b64encode(logo).decode())
    last = (done.stdout.strip().splitlines() or [""])[-1]
    if done.returncode or last != "ok":
        raise SystemExit(f"login page branding not applied: {last} {done.stderr[-300:]}")
    print("login page branding applied")


PHOTOS = HERE.parent / "photos"


def list_option(list_id, code):
    """OpenEMR's list option id for a standard code kept in the list's notes (CDC race and ethnicity, HL7 marital
    status, ISO 639-1 language)."""
    rows = sql(f"SELECT option_id FROM list_options WHERE list_id = {quote(list_id)} AND notes = {quote(code)} "
               f"AND activity = 1 LIMIT 1;")
    return rows[0][0] if rows else ""


SMOKING = {"never": ("nevertobacco", "4"), "former": ("quittobacco", "3"), "current": ("currenttobacco", "1"),
           "Never smoked tobacco": ("nevertobacco", "4"), "Ex-smoker": ("quittobacco", "3"),
           "Smokes tobacco daily": ("currenttobacco", "1"), "Current every day smoker": ("currenttobacco", "1"),
           "Never smoker": ("nevertobacco", "4"), "Former smoker": ("quittobacco", "3")}
# OpenEMR's insurance type codes (claim filing): Medicare Part B, Medicaid, Blue Cross Blue Shield, else commercial.
INSURANCE_TYPE = {"Medicare": 2, "Dual Eligible": 2, "Medicaid": 3, "Blue Cross Blue Shield": 6}


def puuid_of(pid):
    h = sql(f"SELECT LOWER(HEX(uuid)) FROM patient_data WHERE pid = {int(pid)};")[0][0]
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}"


def chart_extras(pid, number, record):
    """Fills what a chart shows beyond the case data, idempotently, also for a patient loaded earlier. record holds any
    of: name (given, family), demographics, emergency_contact, smoking, insurance, last_visit, immunizations.
    Overwritten every run: name, demographics, emergency contact, smoking status. Added once: the insurer's record and
    the patient's primary policy, the last visit (by date) with its vital signs, each immunization (by vaccine and
    date), and the photograph (per image)."""
    pid = int(pid)
    if record.get("name"):   # Synthea's numbered names on patients loaded before the owner's decision of 2026-11-12
        given, family = record["name"]
        sql(f"UPDATE patient_data SET fname = {quote(given)}, lname = {quote(family)} WHERE pid = {pid};")
    if d := record.get("demographics"):
        fields = {"street": d.get("street", ""), "city": d.get("city", ""), "state": d.get("state", ""),
                  "postal_code": d.get("postal_code", ""), "country_code": "USA", "phone_home": d.get("phone_home", ""),
                  "race": "|".join(filter(None, (list_option("race", r) for r in d.get("race", [])))),
                  "ethnicity": "|".join(filter(None, (list_option("ethnicity", e) for e in d.get("ethnicity", [])))),
                  "status": list_option("marital", d.get("marital", "")),
                  "language": list_option("language", d.get("language", ""))}
        if c := record.get("emergency_contact"):
            fields["contact_relationship"] = f"{c['name']} ({c['relationship'].lower()})"
            fields["phone_contact"] = c["phone"]
        sql("UPDATE patient_data SET " + ", ".join(f"{k} = {quote(v)}" for k, v in fields.items())
            + f" WHERE pid = {pid};")
    history = record.get("history") or {}
    smoking = (history.get("tobacco") or {}).get("status") or record.get("smoking")
    if smoking in SMOKING:
        kind, option = SMOKING[smoking]
        note = (history.get("tobacco") or {}).get("note", "").replace("|", " ")
        fields = {"tobacco": f"{note}|{kind}||{option}|0"}
        if "alcohol" in history:   # OpenEMR's lifestyle field: note|<status><field>|date
            drinks = history["alcohol"].replace("|", " ")
            fields["alcohol"] = f"{drinks}|{'never' if drinks.lower().startswith('no alcohol') else 'current'}alcohol|"
        if history.get("social"):
            fields["additional_history"] = history["social"]
        if sql(f"SELECT id FROM history_data WHERE pid = {pid} LIMIT 1;"):
            sql("UPDATE history_data SET " + ", ".join(f"{k} = {quote(v)}" for k, v in fields.items())
                + f" WHERE pid = {pid};")
        else:
            sql(f"INSERT INTO history_data (pid, date, {', '.join(fields)}) VALUES ({pid}, NOW(), "
                + ", ".join(quote(v) for v in fields.values()) + ");")
    if history:
        puuid = puuid_of(pid)
        def missing(kind, title):
            return not sql(f"SELECT id FROM lists WHERE pid = {pid} AND type = {quote(kind)} AND title = {quote(title)} "
                           f"LIMIT 1;")
        for x in history.get("problems", []):
            if missing("medical_problem", x["title"]):
                ok(f"{number}: past history", *target.api("POST", f"api/patient/{puuid}/medical_problem", {
                    "title": x["title"], "begdate": "2020-01-01", "diagnosis": f"ICD10:{x['icd10']}"}))
        # Patient-reported home medications: OpenEMR's medication list, not prescriptions (no ordering clinician).
        for x in history.get("home_medications", []):
            title = f"{x['drug']} ({x['dose']})"
            if missing("medication", title):
                # This endpoint takes the numeric pid and a full timestamp, and ignores comments (set below).
                made = ok(f"{number}: home medication", *target.api("POST", f"api/patient/{pid}/medication", {
                    "title": title, "begdate": "2026-01-01 00:00:00", "diagnosis": f"RXCUI:{x['rxnorm']}"}))
                if not isinstance(made, dict) or not made.get("id"):
                    raise SystemExit(f"{number}: home medication not created: {made}")
                if x.get("comment"):
                    sql(f"UPDATE lists SET comments = {quote(x['comment'])} WHERE id = {int(made['id'])};")
        for x in history.get("allergies", []):
            if missing("allergy", x["title"]):
                ok(f"{number}: allergy", *target.api("POST", f"api/patient/{puuid}/allergy", allergy_body(x)))
    if insurer := record.get("insurance"):
        sql(f"INSERT INTO insurance_companies (id, name, ins_type_code, inactive, date_created, last_updated) "
            f"SELECT next.id, {quote(insurer)}, {INSURANCE_TYPE.get(insurer, 16)}, 0, NOW(), NOW() "
            f"FROM (SELECT COALESCE(MAX(id), 0) + 1 AS id FROM insurance_companies) next "
            f"WHERE NOT EXISTS (SELECT 1 FROM insurance_companies WHERE name = {quote(insurer)});")
        company = sql(f"SELECT id FROM insurance_companies WHERE name = {quote(insurer)} LIMIT 1;")[0][0]
        if not sql(f"SELECT id FROM insurance_data WHERE pid = {pid} AND type = 'primary' LIMIT 1;"):
            row = sql(f"SELECT fname, lname, DOB, sex, street, postal_code, city, state FROM patient_data WHERE pid = {pid};")[0]
            policy = "LV" + number.replace("-", "")   # a made-up policy number, the same every run
            sql(f"INSERT INTO insurance_data (type, provider, plan_name, policy_number, subscriber_fname, subscriber_lname, "
                f"subscriber_relationship, subscriber_DOB, subscriber_sex, subscriber_street, subscriber_postal_code, "
                f"subscriber_city, subscriber_state, subscriber_country, date, pid, accept_assignment, policy_type) VALUES "
                f"('primary', {quote(str(company))}, {quote(insurer)}, {quote(policy)}, {quote(row[0])}, {quote(row[1])}, "
                f"'self', {quote(row[2])}, {quote(row[3])}, {quote(row[4])}, {quote(row[5])}, {quote(row[6])}, "
                f"{quote(row[7])}, 'USA', '2026-01-01', {pid}, 'TRUE', '');")
    if visit := record.get("last_visit"):
        day = utc(visit["start"])
        if not sql(f"SELECT encounter FROM form_encounter WHERE pid = {pid} AND date = {quote(day)} LIMIT 1;"):
            puuid = puuid_of(pid)
            encounter = ok(f"{number}: visit", *target.api("POST", f"api/patient/{puuid}/encounter", {
                "date": day, "reason": visit["reason"], "class_code": "AMB", "pc_catid": "5"}))["data"]["encounter"]
            if visit.get("vitals"):
                ok(f"{number}: vital signs", *target.api("POST", f"api/patient/{pid}/encounter/{encounter}/vital",
                                                         {"date": day, **{k: str(v) for k, v in visit["vitals"].items()}}))
    for v in record.get("immunizations", []) + [
            {**i, "title": ""} for i in (record.get("history") or {}).get("immunizations", [])]:
        sql(f"INSERT INTO immunizations (patient_id, administered_date, cvx_code, note, create_date, update_date, "
            f"created_by, updated_by, added_erroneously, completion_status, information_source) "
            f"SELECT {pid}, {quote(v['date'] + ' 00:00:00')}, {quote(v['cvx'])}, {quote(v.get('title', ''))}, NOW(), NOW(), "
            f"1, 1, 0, 'Completed', 'hist_inf_src_unspecified' FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM immunizations "
            f"WHERE patient_id = {pid} AND cvx_code = {quote(v['cvx'])} "
            f"AND administered_date = {quote(v['date'] + ' 00:00:00')});")
    photo = PHOTOS / f"{number}.jpg"
    if photo.exists():
        import base64
        import hashlib
        data = photo.read_bytes()
        done = target.php(target.install("photo.php", PHOTO_PHP), str(pid),
                          f"{number}-{hashlib.sha256(data).hexdigest()[:8]}.jpg", stdin=base64.b64encode(data).decode())
        last = (done.stdout.strip().splitlines() or [""])[-1]
        if done.returncode or last not in ("ok", "present"):
            raise SystemExit(f"{number}: photograph not stored: {last} {done.stderr[-300:]}")


def assign_missing_uuids():
    """Assign FHIR ids to newly loaded records before any FHIR read (runs on every load, so it also covers records
    loaded before this step existed)."""
    done = target.php(target.install("uuids.php", UUIDS_PHP))
    if done.returncode or done.stdout.strip().splitlines()[-1:] != ["ok"]:
        raise SystemExit(f"assigning FHIR ids failed: {done.stdout[-400:]} {done.stderr[-400:]}")
    print("FHIR ids assigned to records that had none")


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
    # OpenEMR's standard API answers some validation failures with HTTP 200 and a body of field errors
    # ({"begdate": {"DateTime::INVALID_VALUE": ...}}): treat a body whose values are all such dicts as a failure.
    invalid = (isinstance(body, dict) and body and all(isinstance(v, dict) and any("::" in k for k in v)
                                                       for v in body.values()))
    if status not in (200, 201) or invalid:
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


CHARTS = {} if "--no-chart-details" in sys.argv else json.loads((HERE / "charts.json").read_text())


def load(case):
    number = f"LV-{case['id']}"
    if existing := sql(f"SELECT pid FROM patient_data WHERE pubpid = {quote(number)};"):
        for x in case.get("problems", []):
            sql(f"UPDATE lists SET diagnosis = {quote(x['diagnosis'])} WHERE pid = {int(existing[0][0])} "
                f"AND type = 'medical_problem' AND title = {quote(x['title'])} AND diagnosis <> {quote(x['diagnosis'])};")
        chart_extras(existing[0][0], number, CHARTS.get(case["id"], {}))
        # A case loaded before the start-date fix (changelog #112) gets it now; the update is a no-op otherwise.
        sql(f"UPDATE prescriptions SET date_added = start_date WHERE patient_id = {int(existing[0][0])} "
            f"AND date_added IS NULL;")
        print(f"{case['id']}: already loaded; chart details and photograph brought up to date")
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
    # OpenEMR 8.4.1's FHIR MedicationRequest has no start date: it does not select start_date and fills authoredOn
    # from date_added, which the API leaves empty (docs/upstream/openemr-8.4.1.md, item 11). Record each order as
    # written on its start date, as an order entered at the start of therapy would be.
    sql(f"UPDATE prescriptions SET date_added = start_date WHERE patient_id = {int(pid)} AND date_added IS NULL;")
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
    chart_extras(pid, number, CHARTS.get(case["id"], {}))
    print(f"{case['id']}: loaded (patient {number}, {len(orders)} orders)")


def load_background():
    people = json.loads((HERE.parent / "synthea" / "background.json").read_text())["patients"]
    added = 0
    for p in people:
        if existing := sql(f"SELECT pid FROM patient_data WHERE pubpid = {quote(p['number'])};"):
            chart_extras(existing[0][0], p["number"], {**p, "name": (p["given"], p["family"])})
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
        pid = ok("patient lookup", *target.api("GET", f"api/patient/{puuid}"))["data"]["pid"]
        chart_extras(pid, p["number"], p)
        added += 1
    print(f"background: {added} loaded, {len(people) - added} already present (demographics, immunizations and "
          f"photographs brought up to date)")


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
    branding()
    with target.session(fhir.SCOPES):
        if "--no-background" not in argv:
            load_background()
        for path in paths:
            load(json.loads(path.read_text()))
        assign_missing_uuids()


if __name__ == "__main__":
    main(sys.argv[1:])
