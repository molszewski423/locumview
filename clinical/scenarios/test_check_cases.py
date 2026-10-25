#!/usr/bin/env python3
"""The case checker refuses what the plan and the owner's decisions rule out. Each test breaks a copy of a valid case."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("check_cases", HERE / "check_cases.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
CITATIONS = json.loads((HERE / "citations.json").read_text())["citations"]
BASE = json.loads((HERE / "cases" / "uti-esbl-mismatch-01.json").read_text())


class CheckerTests(unittest.TestCase):
    def errors(self, change, require_approved=False):
        case = copy.deepcopy(BASE)
        change(case)
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / f"{case.get('id', 'case')}.json"
            path.write_text(json.dumps(case))
            return checker.check(path, CITATIONS, require_approved)

    def assertRefused(self, change, fragment, **kwargs):
        errors = self.errors(change, **kwargs)
        self.assertTrue(any(fragment in e for e in errors), f"expected {fragment!r} in {errors}")

    def test_every_case_in_the_library_passes(self):
        for path in sorted((HERE / "cases").glob("*.json")):
            self.assertEqual(checker.check(path, CITATIONS), [], path.name)

    def test_case_without_provenance_is_refused(self):
        self.assertRefused(lambda c: c.pop("provenance"), "missing 'provenance'")

    def test_non_synthetic_source_is_refused(self):
        self.assertRefused(lambda c: c["provenance"].update(source="ehr-extract"), "must be 'synthetic'")

    def test_evaluation_build_refuses_unreviewed_case(self):
        self.assertRefused(lambda c: c["provenance"].update(clinical_review={"status": "pending"}), "not approved",
                           require_approved=True)
        approved = {"status": "approved", "by": "owner", "date": "2026-10-26"}
        self.assertEqual(self.errors(lambda c: c["provenance"].update(clinical_review=approved), True), [])

    def test_approval_needs_reviewer_and_date(self):
        self.assertRefused(lambda c: c["provenance"].update(clinical_review={"status": "approved"}), "clinical_review.by")

    def test_more_than_one_organism_is_refused(self):
        def two(c):
            org = c["cultures"][0]["organism"]
            c["cultures"][0]["organism"] = [org, {"snomed": "40886007", "text": "Klebsiella oxytoca"}]
        self.assertRefused(two, "exactly one organism")

    def test_negative_control_with_a_finding_is_refused(self):
        self.assertRefused(lambda c: c.update(kind="negative-control"), "negative control has no expected findings")

    def test_finding_case_without_findings_is_refused(self):
        self.assertRefused(lambda c: c.update(expected_findings=[]), "needs at least one expected finding")

    def test_ambiguous_case_needs_two_acceptable_answers(self):
        self.assertRefused(lambda c: c.update(kind="ambiguous", acceptable_answers=["one"]), "needs at least 2")

    def test_time_without_offset_is_refused(self):
        self.assertRefused(lambda c: c["encounter"].update(start="2026-10-20 14:00:00"), "a time with an offset")

    def test_unknown_citation_is_refused(self):
        self.assertRefused(lambda c: c["citations"].append({"ref": "made-up-2026", "supports": "x"}), "unknown reference")

    def test_unknown_key_is_refused(self):
        self.assertRefused(lambda c: c.update(expected_finding=[]), "unknown key 'expected_finding'")

    def test_bad_mic_and_interpretation_are_refused(self):
        self.assertRefused(lambda c: c["cultures"][0]["susceptibilities"][0].update(mic="32 mg"), "an MIC")
        self.assertRefused(lambda c: c["cultures"][0]["susceptibilities"][0].update(interpretation="Resistant"),
                           "interpretation")

    def test_finding_module_must_belong_to_the_case(self):
        self.assertRefused(lambda c: c.update(modules=["iv-to-po"]), "must be one of the case's modules")

    def test_result_before_collection_is_refused(self):
        self.assertRefused(lambda c: c["cultures"][0].update(resulted="2026-10-19T09:40:00-04:00"),
                           "resulted before collected")

    def test_pending_culture_has_no_result(self):
        def pending(c):
            c["cultures"][0]["status"] = "pending"
        self.assertRefused(pending, "a pending culture has no 'resulted'")

        def pending_clean(c):
            c["cultures"][0] = {k: v for k, v in c["cultures"][0].items()
                                if k in ("order_code", "order_text", "specimen", "collected")}
            c["cultures"][0]["status"] = "pending"
        self.assertEqual(self.errors(pending_clean), [])

    def test_id_must_match_file_name(self):
        case = copy.deepcopy(BASE)
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "other-name.json"
            path.write_text(json.dumps(case))
            self.assertTrue(any("must match the file name" in e for e in checker.check(path, CITATIONS)))


if __name__ == "__main__":
    unittest.main()
