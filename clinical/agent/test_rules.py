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
from lvrules import Knowledge, evaluate, from_case, from_fhir  # noqa: E402

CASES = HERE.parent / "scenarios" / "cases"
FIXTURES = HERE / "fixtures" / "fhir"
SITE_TZ = "America/New_York"   # the cases' offsets; OpenEMR returns UTC
CITATIONS = json.loads((HERE.parent / "scenarios" / "citations.json").read_text())["citations"]
KB = Knowledge.load()


def case(name):
    return json.loads((CASES / f"{name}.json").read_text())


def fixture(name):
    return json.loads((FIXTURES / f"{name}.json").read_text())


def fhir_keys(resources, modules):
    return sorted(f.key() for f in evaluate(from_fhir(resources, KB, SITE_TZ), KB, modules))


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
        refs |= {r for cond in KB.conditions.values() for r in cond.get("refs", []) + cond.get("duration_refs", [])}
        refs.add("who-meningitis-2025")   # added by the Listeria rule above its own age threshold
        self.assertEqual(refs - set(CITATIONS), set())

    def test_every_product_and_test_names_a_known_agent_where_a_rule_needs_it(self):
        self.assertEqual(set(KB.products.values()) - set(KB.agents), set())
        rule_flags = ("anaerobic", "anaerobic_only", "covers_listeria", "third_generation_cephalosporin",
                      "antistaphylococcal_beta_lactam", "oral_bioequivalent")
        for name, agent in KB.agents.items():
            self.assertTrue(set(agent) <= {"display", *rule_flags}, name)

    def test_every_finding_cites_only_what_its_reviewed_case_cites(self):
        # The cases' citations were approved in the owner's clinical review (M2); a rule citing anything else, such
        # as the pneumonia guideline for pyelonephritis (fixed in M6), is a knowledge-base error.
        for path in sorted(CASES.glob("*.json")):
            c = json.loads(path.read_text())
            cited = {r if isinstance(r, str) else r["ref"] for r in c["citations"]}
            for f in evaluate(from_case(c, KB), KB, set(c["modules"])):
                with self.subTest(case=c["id"], rule=f.rule):
                    self.assertEqual(set(f.refs) - cited, set())

    def test_iv_to_po_cites_the_guideline_of_the_condition(self):
        refs = {c: set(evaluate(from_case(case(c), KB), KB, {"iv-to-po"})[0].refs)
                for c in ("cap-levofloxacin-ivpo-01", "pyelo-ivpo-ambiguous-01")}
        self.assertEqual(refs["cap-levofloxacin-ivpo-01"], {"idsa-shea-asp-2016", "ats-idsa-cap-2019"})
        self.assertEqual(refs["pyelo-ivpo-ambiguous-01"], {"idsa-shea-asp-2016", "idsa-cuti-2025-ivpo"})

    def test_ampc_group_is_exactly_idsa_2026_moderate_risk_organisms(self):
        # E. cloacae complex, K. aerogenes (62592009 also carries the former name Enterobacter aerogenes),
        # C. freundii and its complex, H. alvei. Low-risk Serratia, Morganella and Providencia stay out (over-alerting).
        group = {code for code in KB.organisms if KB.organism_in(code, "inducible-ampc")}
        self.assertEqual(group, {"414102007", "62592009", "6265002", "782522004", "76694001"})

    def test_ampc_rule_fires_for_each_moderate_risk_organism(self):
        for code, name in (("62592009", "Klebsiella aerogenes"), ("6265002", "Citrobacter freundii"),
                           ("782522004", "Citrobacter freundii complex"), ("76694001", "Hafnia alvei")):
            c = case("bsi-enterobacter-ampc-01")
            for culture in c["cultures"]:
                culture["organism"] = {"snomed": code, "text": name}
            with self.subTest(organism=name):
                self.assertIn(("stewardship", "suboptimal-agent", "Ceftriaxone"), keys(c))

    def test_ampc_findings_limit_the_ceftriaxone_exception_to_an_empiric_course(self):
        ampc = lambda c: [f for f in evaluate(from_case(c, KB), KB) if f.type == "suboptimal-agent"]
        (f,) = ampc(case("bsi-enterobacter-ampc-01"))                     # febrile on day 2
        self.assertIn("moderate risk of inducible AmpC", f.summary)
        self.assertIn("does not apply yet: fever in the last 24 hours", f.summary)
        self.assertNotIn("may be reasonable", f.summary)
        self.assertIn("idsa-amr-gn-2026", f.refs)
        # Bacteremic but afebrile: IDSA 2026 does not exclude bacteremia, so the exception wording stays.
        c = case("bsi-enterobacter-ampc-01")
        for v in c["vitals"]:
            v["temperature_f"] = 98.6
        (f,) = ampc(c)
        self.assertIn("If it was started empirically, completing the course may be reasonable only if", f.summary)
        self.assertNotIn("does not apply yet", f.summary)
        (f,) = evaluate(from_case(case("pyelo-enterobacter-ambiguous-01"), KB), KB, {"iv-to-po"})
        self.assertIn("if ceftriaxone was started empirically, completing the course may be reasonable", f.summary)
        self.assertIn("idsa-amr-gn-2026", f.refs)

    def test_cuti_caution_only_for_amoxicillin_not_an_oral_third_generation_cephalosporin(self):
        # IDSA 2025 cUTI (owner decision, 2026-11-12): no warning for cefpodoxime after ceftriaxone; caution for amoxicillin.
        caution = "IDSA 2025 advises using amoxicillin cautiously"
        # (pyelo-ivpo-ambiguous-01: ampicillin R, so amoxicillin is never its option)
        summary = lambda c: evaluate(from_case(c, KB), KB, {"iv-to-po"})[0].summary
        self.assertNotIn(caution, summary(case("pyelo-ivpo-ambiguous-01")))
        for gone in ("longer total course", "completing IV", "weaker supporting evidence"):
            self.assertNotIn(gone, summary(case("pyelo-ivpo-ambiguous-01")))
        c = case("pyelo-ivpo-ambiguous-01")
        for s in c["cultures"][0]["susceptibilities"]:
            if s["loinc"] == "28-1":
                s["interpretation"] = "S"
        self.assertIn(caution, summary(c))
        c["problems"] = [{"title": "Community-acquired pneumonia", "diagnosis": "ICD10:J18.9", "begdate": "2026-10-19"}]
        self.assertNotIn(caution, summary(c))                          # the caution is for complicated UTI only

    def test_cap_duration_follows_ats_2025(self):
        c = case("cap-levofloxacin-ivpo-01")
        self.assertNotIn(("stewardship", "duration-review", "Levofloxacin"), keys(c, {"stewardship"}))   # day 4
        c["encounter"]["start"] = "2026-10-20T13:00:00-04:00"
        c["prescriptions"][0]["start"] = "2026-10-21"                  # day 5 at the newest vitals
        (f,) = [f for f in evaluate(from_case(c, KB), KB, {"stewardship"}) if f.type == "duration-review"]
        self.assertIn("ATS 2025 suggests fewer than 5 days (at least 3) once clinically stable in nonsevere", f.summary)
        self.assertEqual(set(f.refs), {"idsa-shea-asp-2016", "ats-cap-2025"})

    def test_who_meningitis_cited_only_above_its_age_threshold(self):
        c = case("meningitis-listeria-gap-01")
        (f,) = evaluate(from_case(c, KB), KB, {"stewardship"})
        self.assertIn("who-meningitis-2025", f.refs)                   # age 67
        born = int(c["patient"]["birth_date"][:4])
        c["patient"]["birth_date"] = str(born + 12) + c["patient"]["birth_date"][4:]   # age 55
        (f,) = evaluate(from_case(c, KB), KB, {"stewardship"})
        self.assertNotIn("who-meningitis-2025", f.refs)
        self.assertIn("lacks Listeria coverage", f.summary)            # IDSA and ESCMID: over 50

    def test_every_finding_carries_its_reviewed_why_line(self):
        for path in sorted(CASES.glob("*.json")):
            c = json.loads(path.read_text())
            for f in evaluate(from_case(c, KB), KB, set(c["modules"])):
                with self.subTest(case=c["id"], rule=f.rule):
                    why = [e for e in f.evidence if e.startswith("Why it matters: ")]
                    self.assertEqual(len(why), 1)
                    self.assertIn(why[0][len("Why it matters: "):],
                                  [w["text"] for k, w in KB.why.items() if k.split("/")[0] == f.rule])

    def test_listeria_finding_states_its_criteria(self):
        (f,) = evaluate(from_case(case("meningitis-listeria-gap-01"), KB), KB, {"stewardship"})
        self.assertIn("(Criterion: age over 50, IDSA 2004 and ESCMID 2016; WHO 2025, age over 60, cited as "
                      "supporting evidence.)", f.summary)
        self.assertFalse(any("riterion" in e for e in f.evidence))   # never as data the model may misread

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

    def test_iv_to_po_never_offers_the_cefazolin_surrogate_outside_uncomplicated_uti(self):
        # CLSI limits the cefazolin urinary surrogate to uncomplicated UTI (owner decision, 2026-11-12).
        for specimen in ({"snomed": "122575003", "text": "Urine specimen"}, {"snomed": "119297000", "text": "Blood specimen"}):
            c = case("pyelo-ivpo-ambiguous-01")
            c["cultures"][0]["specimen"] = specimen
            for f in evaluate(from_case(c, KB), KB, {"iv-to-po"}):
                self.assertNotIn("cefazolin urinary surrogate", f.summary)

    def test_oral_third_generation_cephalosporin_after_ceftriaxone_in_complicated_uti_only(self):
        caption = "an oral third-generation cephalosporin such as cefpodoxime"
        (f,) = evaluate(from_case(case("pyelo-ivpo-ambiguous-01"), KB), KB, {"iv-to-po"})
        self.assertIn(caption, f.summary)                                  # E. coli, ceftriaxone S, IDSA 2025
        (f,) = evaluate(from_case(case("pyelo-enterobacter-ambiguous-01"), KB), KB, {"iv-to-po"})
        self.assertNotIn(caption, f.summary)                               # AmpC organism: IDSA 2026
        c = case("pyelo-ivpo-ambiguous-01")
        c["problems"] = [{"title": "Community-acquired pneumonia", "diagnosis": "ICD10:J18.9", "begdate": "2026-10-19"}]
        self.assertEqual(keys(c, {"iv-to-po"}), [])                        # not a complicated UTI

    def test_iv_to_po_never_offers_nitrofurantoin(self):
        c = case("pyelo-ivpo-ambiguous-01")
        c["cultures"][0]["susceptibilities"] = [x for x in c["cultures"][0]["susceptibilities"]
                                                if x["loinc"] not in ("85422-4", "141-2")]
        self.assertEqual(keys(c), [])

    def test_iv_to_po_asks_the_pharmacist_to_confirm_oral_intake(self):
        c = case("cap-levofloxacin-ivpo-01")
        (finding,) = evaluate(from_case(c, KB), KB, {"iv-to-po"})
        self.assertIn("Confirm the patient is taking food and drink by mouth", finding.summary)

    def test_as_of_is_the_newest_charted_time(self):
        s = from_case(case("uti-esbl-mismatch-01"), KB)
        self.assertEqual(s.as_of.isoformat(), "2026-10-22T09:40:00-04:00")


class FhirAdapterTests(unittest.TestCase):
    """The same rules over OpenEMR's FHIR read-back of each case (fixtures/fhir, recorded with patches 0001 and 0002
    and the loader's start dates) give the same snapshot and the same findings as over the case file."""

    def test_every_case_has_a_fixture(self):
        self.assertEqual(sorted(p.stem for p in FIXTURES.glob("*.json")), sorted(p.stem for p in CASES.glob("*.json")))

    def test_every_fixture_gives_the_case_file_findings(self):
        for path in sorted(CASES.glob("*.json")):
            c = json.loads(path.read_text())
            with self.subTest(case=c["id"]):
                self.assertEqual(fhir_keys(fixture(c["id"]), set(c["modules"])), keys(c))

    def test_every_fixture_gives_the_case_file_snapshot(self):
        def rx(s):
            return sorted((p.agent or "", p.route, p.start, p.active_on(s.as_of.date())) for p in s.prescriptions)

        def cultures(s):
            return sorted((c.specimen, c.final, c.organism_code or "", c.collected,
                           sorted((x.loinc, x.interpretation) for x in c.susceptibilities)) for c in s.cultures)

        def vitals(s):
            return [(v.taken, v.temperature_f, v.pulse, v.respiration, v.oxygen_saturation, v.systolic)
                    for v in s.vitals]

        for path in sorted(CASES.glob("*.json")):
            c = json.loads(path.read_text())
            a, b = from_case(c, KB), from_fhir(fixture(c["id"]), KB, SITE_TZ)
            with self.subTest(case=c["id"]):
                self.assertEqual((a.as_of, a.encounter_start, a.birth_date), (b.as_of, b.encounter_start, b.birth_date))
                self.assertEqual(rx(a), rx(b))
                self.assertEqual(sorted(p.icd10 for p in a.problems), sorted(p.icd10 for p in b.problems))
                self.assertEqual(cultures(a), cultures(b))
                self.assertEqual(vitals(a), vitals(b))

    def test_dates_are_judged_in_the_site_time_zone(self):
        # The newest charted time is 23:35 in New York, 03:35 the next day in UTC.
        s = from_fhir(fixture("meningitis-listeria-gap-01"), KB, SITE_TZ)
        self.assertEqual(s.as_of.isoformat(), "2026-10-24T23:35:00-04:00")
        self.assertEqual(from_fhir(fixture("meningitis-listeria-gap-01"), KB, "UTC").as_of.date().isoformat(),
                         "2026-10-25")

    def test_without_problem_codes_the_condition_rules_stay_silent(self):
        # What unpatched OpenEMR 8.4.1 returns: problems as text only (docs/upstream/openemr-8.4.1.md, item 9).
        resources = fixture("meningitis-listeria-gap-01")
        for r in resources:
            if r["resourceType"] == "Condition":
                r["code"].pop("coding", None)
        self.assertEqual(fhir_keys(resources, {"stewardship"}), [])

    def test_a_prescription_without_a_start_date_is_left_out(self):
        resources = fixture("uti-esbl-mismatch-01")
        for r in resources:
            if r["resourceType"] == "MedicationRequest":
                r.pop("authoredOn")
        self.assertEqual(from_fhir(resources, KB, SITE_TZ).prescriptions, [])

    def test_a_dosage_bounds_period_wins_over_authored_on(self):
        resources = fixture("cellulitis-duration-01")
        for r in resources:
            if r["resourceType"] == "MedicationRequest" and r["status"] == "active":
                r["dosageInstruction"][0]["timing"] = {"repeat": {"boundsPeriod": {"start": "2026-10-16",
                                                                                   "end": "2026-10-21"}}}
        self.assertEqual(fhir_keys(resources, {"stewardship"}), [])   # stopped by day 12: nothing to review

    def test_a_completed_order_is_not_active(self):
        resources = fixture("bsi-mssa-vancomycin-01")
        for r in resources:
            if r["resourceType"] == "MedicationRequest":
                r["status"] = "completed"
        self.assertEqual(fhir_keys(resources, {"stewardship", "iv-to-po"}), [])

    def test_a_temperature_in_celsius_is_converted(self):
        resources = fixture("pyelo-matched-negative-01")   # febrile at 101.6 F: no IV to PO
        for r in resources:
            if r["resourceType"] == "Observation" and r["code"]["coding"][0]["code"] == "8310-5":
                f = r["valueQuantity"]["value"]
                r["valueQuantity"] = {"value": round((f - 32) * 5 / 9, 2), "unit": "Cel", "code": "Cel",
                                      "system": "http://unitsofmeasure.org"}
        s = from_fhir(resources, KB, SITE_TZ)
        self.assertEqual(max(s.vitals, key=lambda v: v.taken).temperature_f, 101.6)

    def test_no_growth_is_a_final_culture_without_an_isolate(self):
        resources = fixture("uti-esbl-mismatch-01")
        for r in resources:
            if r["resourceType"] == "Observation" and r.get("valueString", "").startswith("112283007"):
                r["valueString"] = "264868006 (No growth)"
        s = from_fhir(resources, KB, SITE_TZ)
        self.assertEqual([(c.final, c.organism_code) for c in s.cultures], [(True, None)])
        self.assertEqual(fhir_keys(resources, {"stewardship"}), [])


if __name__ == "__main__":
    unittest.main()
