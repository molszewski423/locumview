"""Deterministic rules for the stewardship and IV to PO modules (ADR 0017: rules decide, the model only explains).

Each rule reads a Snapshot and the knowledge base and returns findings. A finding carries the data it rests on
(evidence) and the references in clinical/scenarios/citations.json it cites, so the explanation step can only restate
what the rule saw. A rule that lacks the data it needs stays silent rather than guessing.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import timedelta

from .knowledge import Knowledge
from .snapshot import Prescription, Snapshot


@dataclass(frozen=True)
class Finding:
    rule: str
    module: str
    type: str
    drug: str
    summary: str
    evidence: tuple[str, ...] = ()
    refs: tuple[str, ...] = field(default=())

    def key(self) -> tuple[str, str, str]:
        return (self.module, self.type, self.drug)


def _finding(kb: Knowledge, rule: str, type_: str, agent: str, summary: str, evidence: list[str],
             extra_refs: tuple[str, ...] = ()) -> Finding:
    spec = kb.rules[rule]
    return Finding(rule, spec["module"], type_, kb.display(agent), summary, tuple(evidence),
                   tuple(spec["refs"]) + extra_refs)


def bug_drug_mismatch(s: Snapshot, kb: Knowledge) -> list[Finding]:
    """An active antimicrobial tested resistant against a final isolate."""
    out = []
    for p in s.active_antimicrobials():
        for c in s.final_isolates():
            hit = [x for x in c.susceptibilities if x.agent == p.agent and x.interpretation == "R"]
            if hit:
                out.append(_finding(kb, "bug-drug-mismatch", "bug-drug-mismatch", p.agent,
                                    f"{c.organism} ({c.specimen or 'specimen'}) is resistant to "
                                    f"{kb.display(p.agent).lower()}, which the patient is receiving.",
                                    [f"{c.specimen} culture collected {c.collected:%Y-%m-%d %H:%M}: {c.organism}",
                                     f"{kb.display(p.agent)}: R", f"Active: {p.text}, started {p.start}"]))
                break
    return out


def ampc_third_generation_cephalosporin(s: Snapshot, kb: Knowledge) -> list[Finding]:
    """A third-generation cephalosporin for bacteremia with an organism at moderate risk of inducible AmpC.

    IDSA 2026: generally avoided even when susceptible; completing an empirically started course may be reasonable in
    a non-severe infection with clinical improvement and source control. The guidance does not define non-severe, so
    the finding states the condition and leaves that judgment to the pharmacist (owner decision, 2026-11-12)."""
    out = []
    for p in s.active_antimicrobials():
        if not kb.has(p.agent, "third_generation_cephalosporin"):
            continue
        drug = kb.display(p.agent).lower()
        for c in s.final_isolates():
            if c.specimen == "blood" and kb.organism_in(c.organism_code, "inducible-ampc"):
                out.append(_finding(kb, "ampc-third-generation-cephalosporin", "suboptimal-agent", p.agent,
                                    f"{c.organism} bacteremia on {drug}: the organism has a moderate risk of "
                                    f"inducible AmpC, so {drug} is generally avoided even when susceptible; if it "
                                    "was started empirically, completing the course may be reasonable only if the "
                                    "infection is non-severe, the patient is improving and the source is "
                                    "controlled. Cefepime is the usual alternative.",
                                    [f"Blood culture collected {c.collected:%Y-%m-%d %H:%M}: {c.organism}",
                                     f"Active: {p.text}, started {p.start}"]))
                break
    return out


def mssa_vancomycin(s: Snapshot, kb: Knowledge) -> list[Finding]:
    """Vancomycin for oxacillin-susceptible S. aureus bacteremia without an anti-staphylococcal beta-lactam."""
    active = s.active_antimicrobials()
    if any(kb.has(p.agent, "antistaphylococcal_beta_lactam") for p in active):
        return []
    vanco = [p for p in active if p.agent == "vancomycin"]
    for c in s.final_isolates():
        oxacillin_s = any(x.agent == "oxacillin" and x.interpretation == "S" for x in c.susceptibilities)
        if vanco and c.specimen == "blood" and kb.organism_in(c.organism_code, "staphylococcus-aureus") and oxacillin_s:
            return [_finding(kb, "mssa-vancomycin", "de-escalation", "vancomycin",
                             "Oxacillin-susceptible S. aureus bacteremia on vancomycin: an anti-staphylococcal "
                             "beta-lactam (cefazolin, nafcillin or oxacillin) is preferred.",
                             [f"Blood culture collected {c.collected:%Y-%m-%d %H:%M}: {c.organism}", "Oxacillin: S",
                              f"Active: {vanco[0].text}, started {vanco[0].start}"])]
    return []


def meningitis_listeria(s: Snapshot, kb: Knowledge) -> list[Finding]:
    """Empiric therapy for bacterial meningitis at or above the age threshold without Listeria coverage."""
    if not any("bacterial-meningitis" in kb.condition_of(p.icd10) for p in s.problems):
        return []
    active = s.active_antimicrobials()
    age = s.age_on(s.as_of.date())
    if not active or age < kb.thresholds["listeria_age"]:
        return []
    if any(kb.has(p.agent, "covers_listeria") for p in active):
        return []
    # WHO 2025 sets its Listeria age risk at over 60 (IDSA 2004, ESCMID 2016: over 50), so it is cited only above 60.
    who = ("who-meningitis-2025",) if age > kb.thresholds["listeria_age_who"] else ()
    return [_finding(kb, "meningitis-listeria", "missing-empiric-coverage", "ampicillin",
                     f"Empiric therapy for suspected bacterial meningitis at age {age} lacks Listeria coverage: "
                     "cephalosporins and vancomycin do not cover Listeria monocytogenes; add ampicillin.",
                     [f"Age {age}", "Problem: suspected bacterial meningitis",
                      "Active: " + ", ".join(kb.display(p.agent) for p in active)], who)]


def double_anaerobic_coverage(s: Snapshot, kb: Knowledge) -> list[Finding]:
    """An anaerobe-only agent alongside another agent that already covers anaerobes."""
    active = s.active_antimicrobials()
    out = []
    for p in active:
        if kb.has(p.agent, "anaerobic_only"):
            others = [q for q in active if q.agent != p.agent and kb.has(q.agent, "anaerobic")]
            if others:
                out.append(_finding(kb, "double-anaerobic-coverage", "redundant-coverage", p.agent,
                                    f"{kb.display(others[0].agent)} already covers anaerobes; "
                                    f"{kb.display(p.agent).lower()} duplicates that coverage.",
                                    [f"Active: {p.text}", f"Active: {others[0].text}"]))
    return out


def duration_review(s: Snapshot, kb: Knowledge) -> list[Finding]:
    """An open-ended course past the review point for an indication with a recommended duration."""
    out = []
    for problem in s.problems:
        for name in kb.condition_of(problem.icd10):
            cond = kb.conditions[name]
            if "review_after_days" not in cond:
                continue
            courses = [p for p in s.prescriptions if p.agent and p.start >= s.encounter_start.date()]
            if not courses:
                continue
            start = min(p.start for p in courses)
            day = (s.as_of.date() - start).days + 1
            for p in s.active_antimicrobials():
                if p.end is None and day > cond["review_after_days"]:
                    guidance = cond.get("duration_text") or f"the recommended course is about {cond['recommended_days']} days"
                    out.append(_finding(kb, "duration-review", "duration-review", p.agent,
                                        f"Day {day} of antibiotics for {problem.title.lower()}; {guidance}; "
                                        f"{kb.display(p.agent).lower()} has no stop date.",
                                        [f"Day {day} of antibiotics, since {start}",
                                         *([f"Recommended course about {cond['recommended_days']} days"]
                                           if "recommended_days" in cond else []),
                                         f"Active without stop date: {p.text}"],
                                        tuple(cond.get("duration_refs", cond.get("refs", ())))))
    return out


def _stable(s: Snapshot, kb: Knowledge) -> tuple[bool, list[str]]:
    """Clinical stability at the newest vitals, and no fever within the afebrile window."""
    if not s.vitals:
        return False, []
    t = kb.thresholds["stability"]
    latest = max(s.vitals, key=lambda v: v.taken)
    checks = [
        latest.temperature_f is not None and latest.temperature_f <= t["max_temperature_f"],
        latest.pulse is not None and latest.pulse <= t["max_pulse"],
        latest.respiration is not None and latest.respiration <= t["max_respiration"],
        latest.oxygen_saturation is not None and latest.oxygen_saturation >= t["min_oxygen_saturation"],
        latest.systolic is not None and latest.systolic >= t["min_systolic"],
    ]
    window = s.as_of - timedelta(hours=kb.thresholds["afebrile_hours"])
    recent_fever = any(v.temperature_f is not None and v.temperature_f >= kb.thresholds["fever_f"]
                       for v in s.vitals if v.taken >= window)
    def n(x):
        return "?" if x is None else f"{x:g}"
    evidence = [f"Vitals {latest.taken:%Y-%m-%d %H:%M}: T {n(latest.temperature_f)} F, HR {n(latest.pulse)}, "
                f"RR {n(latest.respiration)}, SpO2 {n(latest.oxygen_saturation)}%, SBP {n(latest.systolic)}",
                f"No temperature of {kb.thresholds['fever_f']} F or more in the last "
                f"{kb.thresholds['afebrile_hours']} hours"]
    return all(checks) and not recent_fever, evidence


def _oral_options(s: Snapshot, p: Prescription, kb: Knowledge, cuti: bool = False) -> list[str]:
    """Oral agents the data supports: the same drug when it is bioequivalent by mouth, otherwise an oral agent every
    final isolate tests susceptible to. With no final isolate and no bioequivalent form there is no option."""
    if kb.has(p.agent, "oral_bioequivalent"):
        return [f"{kb.display(p.agent).lower()} by mouth at the same dose"]
    isolates = s.final_isolates()
    if not isolates:
        return []
    per_isolate = []
    for c in isolates:
        options = set()
        for x in c.susceptibilities:
            test = kb.tests.get(x.loinc, {})
            if x.interpretation != "S" or "oral_step_down" not in test:
                continue
            if test.get("urinary_surrogate") and c.specimen != "urine":
                continue
            # CLSI's cefazolin surrogate predicts oral cephalosporins only in uncomplicated UTI (owner decision,
            # 2026-11-12); no condition in the knowledge base is an uncomplicated UTI yet, so it is not offered.
            if test.get("uncomplicated_uti_only"):
                continue
            # IDSA 2025 cUTI: after improvement on ceftriaxone, an oral third-generation cephalosporin is a reasonable
            # switch; IDSA 2026: not for moderate-risk AmpC organisms, where oral transition is TMP-SMX or a quinolone.
            if test.get("complicated_uti_after_ceftriaxone") and not (
                    cuti and p.agent == "ceftriaxone" and not kb.organism_in(c.organism_code, "inducible-ampc")):
                continue
            options.add(test["oral_step_down"])
        per_isolate.append(options)
    return sorted(set.intersection(*per_isolate))


def iv_to_po_switch(s: Snapshot, kb: Knowledge) -> list[Finding]:
    """An IV antimicrobial in a clinically stable patient with an oral option the data supports.

    Oral intake is not charted in a structured form (owner decision, 2026-11-09): the finding asks the pharmacist to
    confirm it. Not offered for meningitis or S. aureus bacteremia."""
    if any("bacterial-meningitis" in kb.condition_of(p.icd10) for p in s.problems):
        return []
    if any(c.specimen == "blood" and kb.organism_in(c.organism_code, "staphylococcus-aureus")
           for c in s.final_isolates()):
        return []
    stable, evidence = _stable(s, kb)
    if not stable:
        return []
    # The guideline for each charted condition the knowledge base knows, after the stewardship guideline.
    condition_refs = tuple(dict.fromkeys(ref for problem in s.problems for name in kb.condition_of(problem.icd10)
                                         for ref in kb.conditions[name].get("refs", ())))
    conditions = {name for problem in s.problems for name in kb.condition_of(problem.icd10)}
    cautions = {t["oral_step_down"]: t["cuti_caution"] for t in kb.tests.values() if t.get("cuti_caution")}
    cuti = any(kb.conditions[n].get("complicated_uti") for n in conditions)
    ampc = any(kb.organism_in(c.organism_code, "inducible-ampc") for c in s.final_isolates())
    out = []
    for p in s.active_antimicrobials():
        if p.route != "IV":
            continue
        options = _oral_options(s, p, kb, cuti)
        if not options:
            continue
        drug = kb.display(p.agent).lower()
        notes, refs = [], condition_refs
        if ampc and kb.has(p.agent, "third_generation_cephalosporin"):
            # IDSA 2026 (owner decision, 2026-11-12): the exception covers an empirically started course only.
            notes.append(f"The organism has a moderate risk of inducible AmpC; if {drug} was started empirically, "
                         "completing the course may be reasonable if the infection is non-severe, the patient is "
                         "improving and the source is controlled; the susceptible oral options avoid the question.")
            refs = refs + ("idsa-amr-gn-2026",)
        if cuti:
            # IDSA 2025 cUTI (owner decision, 2026-11-12): caution for amoxicillin and similar oral beta-lactams only;
            # an oral third-generation cephalosporin after improvement on ceftriaxone is a reasonable switch.
            notes += [cautions[o] for o in options if o in cautions]
        out.append(_finding(kb, "iv-to-po-switch", "iv-to-po-switch", p.agent,
                            " ".join([f"Clinically stable on IV {drug}; oral options the data supports: "
                                      f"{'; '.join(options)}.", *notes,
                                      "Confirm the patient is taking food and drink by mouth before switching."]),
                            evidence + [f"Active: {p.text}, started {p.start}"], refs))
    return out


RULES = (bug_drug_mismatch, ampc_third_generation_cephalosporin, mssa_vancomycin, meningitis_listeria,
         double_anaerobic_coverage, duration_review, iv_to_po_switch)


def evaluate(s: Snapshot, kb: Knowledge, modules: set[str] | None = None) -> list[Finding]:
    """Run every rule; with modules given, keep only findings in those modules."""
    findings = [f for rule in RULES for f in rule(s, kb)]
    return [f for f in findings if modules is None or f.module in modules]
