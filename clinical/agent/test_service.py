"""The agent service's contract: findings for one patient's FHIR resources, with evidence and citations; refusals for
input it cannot read. Runs in the pinned Python image with the hash-pinned packages:  clinical/agent/run.sh test"""
import json
from pathlib import Path
import unittest

from fastapi.testclient import TestClient

from lvrules import Knowledge
from service import DEFAULT_CITATIONS, MAX_RESOURCES, create_app

HERE = Path(__file__).resolve().parent
CITATIONS = json.loads(DEFAULT_CITATIONS.read_text())["citations"]


def fixture(name):
    return json.loads((HERE / "fixtures" / "fhir" / f"{name}.json").read_text())


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(create_app(Knowledge.load(), CITATIONS, "America/New_York"))

    def post(self, body):
        return self.client.post("/v1/findings", json=body)

    def test_findings_carry_evidence_and_citations(self):
        reply = self.post({"resources": fixture("uti-esbl-mismatch-01")})
        self.assertEqual(reply.status_code, 200)
        body = reply.json()
        self.assertEqual(body["as_of"], "2026-10-22T09:40:00-04:00")
        (finding,) = body["findings"]
        self.assertEqual((finding["module"], finding["type"], finding["drug"]),
                         ("stewardship", "bug-drug-mismatch", "Ceftriaxone"))
        self.assertTrue(finding["evidence"])
        self.assertEqual({c["ref"] for c in finding["citations"]}, {"clsi-m100", "idsa-shea-asp-2016"})
        self.assertTrue(all(c["title"] != c["ref"] for c in finding["citations"]))

    def test_every_case_matches_its_expected_findings(self):
        for path in sorted((HERE.parent / "scenarios" / "cases").glob("*.json")):
            case = json.loads(path.read_text())
            reply = self.post({"resources": fixture(case["id"]), "modules": case["modules"]})
            got = sorted((f["module"], f["type"], f["drug"]) for f in reply.json()["findings"])
            with self.subTest(case=case["id"]):
                self.assertEqual(got, sorted((e["module"], e["type"], e["drug"]) for e in case["expected_findings"]))

    def test_modules_filter_the_findings(self):
        reply = self.post({"resources": fixture("cap-levofloxacin-ivpo-01"), "modules": ["stewardship"]})
        self.assertEqual(reply.json()["findings"], [])

    def test_unknown_module_is_refused(self):
        self.assertEqual(self.post({"resources": fixture("cap-levofloxacin-ivpo-01"), "modules": ["ade"]}).status_code,
                         422)

    def test_more_than_one_patient_is_refused(self):
        resources = fixture("cap-levofloxacin-ivpo-01")
        resources.append(dict(next(r for r in resources if r["resourceType"] == "Patient"), id="another"))
        self.assertEqual(self.post({"resources": resources}).status_code, 422)

    def test_a_chart_without_an_encounter_is_refused(self):
        resources = [r for r in fixture("cap-levofloxacin-ivpo-01") if r["resourceType"] != "Encounter"]
        self.assertEqual(self.post({"resources": resources}).status_code, 422)

    def test_an_unreadable_chart_is_refused_without_detail(self):
        resources = fixture("cap-levofloxacin-ivpo-01")
        for r in resources:
            if r["resourceType"] == "Patient":
                r["birthDate"] = "not a date"
        reply = self.post({"resources": resources})
        self.assertEqual(reply.status_code, 422)
        self.assertNotIn("not a date", reply.text)   # chart content is not echoed back

    def test_an_oversized_request_is_refused(self):
        resources = [{"resourceType": "Observation"}] * (MAX_RESOURCES + 1)
        self.assertEqual(self.post({"resources": resources}).status_code, 422)

    def test_an_unknown_time_zone_fails_at_start(self):
        with self.assertRaises(Exception):
            create_app(Knowledge.load(), CITATIONS, "Mars/Olympus_Mons")

    def test_health_reports_the_knowledge_version(self):
        self.assertEqual(self.client.get("/healthz").json(), {"status": "ok", "knowledge_version": "0.1.0"})

    def test_no_api_documentation_is_served(self):
        for path in ("/docs", "/redoc", "/openapi.json"):
            self.assertEqual(self.client.get(path).status_code, 404, path)


if __name__ == "__main__":
    unittest.main()
