#!/usr/bin/env python3
"""The rules give exactly each case's expected findings, and each rule stays silent when one fact it needs changes.

Standard library only, so it runs unchanged in pre-commit and CI:  python3 clinical/agent/test_rules.py
"""
import copy
import json
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from lvrules import Knowledge, evaluate, from_case  # noqa: E402

CASES = HERE.parent / "scenarios" / "cases"
CITATIONS = json.loads((HERE.parent / "scenarios" / "citations.json").read_text())["citations"]
KB = Knowledge.load()


def case(name):
    return json.loads((CASES / f"{name}.json").read_text())


def keys(c, modules=None):
    s = from_case(c, KB)
    return sorted(f.key() for f in evaluate(s, KB, modules or set(c["modules"])))


class LibraryTests(unittest.TestCase):
    def test_every_case_gives_exactly_its_expected_findings(self):
        paths = sorted(CASES.glob("*.json"))
        self.assertGreater(len(paths), 0)
        for path in paths:
            c = json.loads(path.read_text())
            expected = sorted((e["module"], e["type"], e["drug"]) for e in c["expected_findings"])
            with self.subTest(case=c["id"]):
                self.assertEqual(keys(c), expected)

    def test_rules_never_read_the_story_or_the_answer(self):
        c = case("cap-levofloxacin-ivpo-01")
        before = keys(c)
        for field in ("story", "expected_findings", "reference_answer", "rationale", "title"):
            c[field] = [] if field == "expected_findings" else ""
        self.assertEqual(keys(c), before)


class KnowledgeTests(unittest.TestCase):
    def test_every_reference_is_in_the_citation_list(self):
        refs = {r for rule in KB.rules.values() for r in rule["refs"]}
        refs |= {r for cond in KB.conditions.values() for r in cond.get("refs", [])}
        self.assertEqual(refs - set(CITATIONS), set())

    def test_every_product_and_test_names_a_known_agent_where_a_rule_needs_it(self):
        self.assertEqual(set(KB.products.values()) - set(KB.agents), set())
        rule_flags = ("anaerobic", "anaerobic_only", "covers_listeria", "third_generation_cephalosporin",
                      "antistaphylococcal_beta_lactam", "oral_bioequivalent")
        for name, agent in KB.agents.items():
            self.assertTrue(set(agent) <= {"display", *rule_flags}, name)

    def test_every_finding_cites_its_rule_references(self):
        c = case("uti-esbl-mismatch-01")
        for f in evaluate(from_case(c, KB), KB):
            self.assertTrue(f.refs, f.rule)
            self.assertTrue(f.evidence, f.rule)


class RuleBoundaryTests(unittest.TestCase):
    """Each test changes one fact in a case that fires, and the finding must go away (or appear)."""

    def test_mismatch_ignores_a_stopped_drug(self):
        c = case("uti-esbl-mismatch-01")
        c["prescriptions"][0]["end"] = "2026-10-21"
        self.assertEqual(keys(c), [])

    def test_mismatch_ignores_a_pending_culture(self):
        c = case("uti-esbl-mismatch-01")
        culture = c["cultures"][0]
        for k in ("resulted", "organism", "colony_count", "susceptibilities"):
            culture.pop(k)
        culture["status"] = "pending"
        self.assertEqual(keys(c), [])

    def test_ampc_rule_needs_a_blood_isolate(self):
        c = case("bsi-enterobacter-ampc-01")
        c["cultures"][0]["specimen"] = {"snomed": "122575003", "text": "Urine specimen"}
        self.assertNotIn(("stewardship", "suboptimal-agent", "Ceftriaxone"), keys(c))

    def test_mssa_rule_is_silent_once_a_beta_lactam_is_added(self):
        c = case("bsi-mssa-vancomycin-01")
        c["prescriptions"].append({"drug": "cefazolin 2000 MG Injection", "rxnorm": "1665060",
                                   "start": "2026-10-24", "route": "IV", "instructions": "2 g IV every 8 hours"})
        self.assertEqual(keys(c), [])

    def test_mssa_rule_needs_oxacillin_susceptible(self):
        c = case("bsi-mssa-vancomycin-01")
        for x in c["cultures"][0]["susceptibilities"]:
            if x["loinc"] == "383-0":
                x["interpretation"] = "R"
        self.assertEqual(keys(c), [])

    def test_listeria_rule_is_silent_under_the_age_threshold(self):
        c = case("meningitis-listeria-gap-01")
        c["patient"]["birth_date"] = "1977-02-17"   # 49 on the day
        self.assertEqual(keys(c), [])

    def test_listeria_rule_is_silent_once_ampicillin_is_ordered(self):
        c = case("meningitis-listeria-gap-01")
        KB.products.setdefault("TEST-AMPICILLIN", "ampicillin")
        c["prescriptions"].append({"drug": "ampicillin 2 g", "rxnorm": "TEST-AMPICILLIN", "start": "2026-10-24",
                                   "route": "IV", "instructions": "2 g IV every 4 hours"})
        try:
            self.assertEqual(keys(c), [])
        finally:
            KB.products.pop("TEST-AMPICILLIN")

    def test_double_anaerobe_rule_is_silent_without_the_second_agent(self):
        c = case("ciai-double-anaerobe-01")
        c["prescriptions"] = [p for p in c["prescriptions"] if p["rxnorm"] != "1659149"]
        self.assertEqual(keys(c), [])

    def test_duration_rule_is_silent_with_a_stop_date(self):
        c = case("cellulitis-duration-01")
        c["prescriptions"][1]["end"] = "2026-10-26"
        self.assertEqual(keys(c), [])

    def test_duration_rule_is_silent_before_the_review_point(self):
        c = case("cellulitis-duration-01")
        for v in c["vitals"]:
            v["taken"] = v["taken"].replace("2026-10-25", "2026-10-19")
        self.assertEqual(keys(c), [])

    def test_iv_to_po_waits_for_a_fever_inside_the_afebrile_window(self):
        c = case("cap-levofloxacin-ivpo-01")
        c["vitals"][1]["temperature_f"] = 100.5   # 24 hours before the newest vitals
        self.assertEqual(keys(c), [])

    def test_iv_to_po_waits_for_a_normal_heart_rate(self):
        c = case("cap-levofloxacin-ivpo-01")
        c["vitals"][-1]["pulse"] = 112
        self.assertEqual(keys(c), [])

    def test_iv_to_po_is_never_offered_for_s_aureus_bacteremia(self):
        c = case("bsi-mssa-cefazolin-negative-01")
        for v in c["vitals"]:
            v.update(temperature_f=98.4, pulse=80)
        self.assertEqual(keys(c, {"iv-to-po"}), [])

    def test_iv_to_po_without_a_final_isolate_needs_a_bioequivalent_drug(self):
        c = case("pyelo-ivpo-ambiguous-01")
        c["cultures"] = []
        self.assertEqual(keys(c), [])

    def test_iv_to_po_does_not_use_the_urinary_surrogate_for_another_specimen(self):
        c = case("pyelo-ivpo-ambiguous-01")
        c["cultures"][0]["specimen"] = {"snomed": "119297000", "text": "Blood specimen"}
        self.assertEqual(keys(c, {"iv-to-po"}), [])

    def test_iv_to_po_never_offers_nitrofurantoin(self):
        c = case("pyelo-ivpo-ambiguous-01")
        c["cultures"][0]["susceptibilities"] = [x for x in c["cultures"][0]["susceptibilities"]
                                                if x["loinc"] != "85422-4"]
        self.assertEqual(keys(c), [])

    def test_iv_to_po_asks_the_pharmacist_to_confirm_oral_intake(self):
        c = case("cap-levofloxacin-ivpo-01")
        (finding,) = evaluate(from_case(c, KB), KB, {"iv-to-po"})
        self.assertIn("Confirm the patient is taking food and drink by mouth", finding.summary)

    def test_as_of_is_the_newest_charted_time(self):
        s = from_case(case("uti-esbl-mismatch-01"), KB)
        self.assertEqual(s.as_of.isoformat(), "2026-10-22T09:40:00-04:00")


if __name__ == "__main__":
    unittest.main()
