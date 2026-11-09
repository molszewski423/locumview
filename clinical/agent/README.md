# LocumView clinical rules (Phase 9 lite M4)

The deterministic part of the agent service in [ADR 0017](../../docs/adr/0017-clinical-ai-workspace-architecture.md)
and plan M4 ([docs/plans/phase9-lite-and-review-workspace.md](../../docs/plans/phase9-lite-and-review-workspace.md)):
rules decide what is flagged; the local model will only explain a finding, never add or remove one. Standard library
only, so the tests run unchanged in pre-commit and CI.

```fish
python3 clinical/agent/test_rules.py      # every case's expected findings, and each rule's boundaries
```

## How it fits together

- `lvrules/snapshot.py`: the patient snapshot the rules read, and `from_case`, which builds it from a case file
  (chart data only: never the story, the expected findings or the reference answer).
- `lvrules/fhir.py`: `from_fhir`, which builds the same snapshot from the FHIR resources the app gateway returns
  from OpenEMR, converting times to the site's time zone. The tests check that every case gives the same snapshot
  and the same findings both ways, so the case tests stand for the runtime.
- `fixtures/fhir/`: each case's FHIR read-back from a local OpenEMR (the M1 spike with patches 0001 and 0002, loaded
  by `clinical/scenarios/load.py`), with server ids and timestamps removed by `clinical/spike/readback.py` and
  trimmed by `fixtures/slim.py`. Re-record them after a change to a case, the loader or the OpenEMR patches.
- `lvrules/rules.py`: one function per rule. Each finding carries its evidence (the data points it used) and the
  references it rests on, by key in [`../scenarios/citations.json`](../scenarios/citations.json).
- `knowledge/antimicrobials.json`: the versioned knowledge base: agents and their properties, RxNorm products,
  susceptibility tests by LOINC, organisms and specimens by SNOMED CT, conditions by ICD-10-CM prefix, thresholds, and
  each rule's references. Raise `version` on every change.

"Now" is the newest charted time in the snapshot, never the wall clock, so a case gives the same answer every time.

## Rules

| Rule | Module, finding type | Fires when | References |
|---|---|---|---|
| `bug-drug-mismatch` | stewardship, bug-drug-mismatch | An active antimicrobial tests R against a final isolate | clsi-m100, idsa-shea-asp-2016 |
| `ampc-third-generation-cephalosporin` | stewardship, suboptimal-agent | A third-generation cephalosporin for a blood isolate with an inducible AmpC | idsa-amr-gn-2024 |
| `mssa-vancomycin` | stewardship, de-escalation | Vancomycin for oxacillin-susceptible *S. aureus* in blood, with no anti-staphylococcal beta-lactam active | idsa-crbsi-2009 |
| `meningitis-listeria` | stewardship, missing-empiric-coverage | Empiric therapy for bacterial meningitis (ICD-10 G00) at age 50 or over without a Listeria-active agent | idsa-meningitis-2004, escmid-meningitis-2016 |
| `double-anaerobic-coverage` | stewardship, redundant-coverage | An anaerobe-only agent (metronidazole) beside another agent that covers anaerobes | idsa-ciai-2010 |
| `duration-review` | stewardship, duration-review | An active course with no stop date past the review point for cellulitis or pneumonia | idsa-shea-asp-2016 and the condition's guideline |
| `iv-to-po-switch` | iv-to-po, iv-to-po-switch | An IV antimicrobial, a stable patient (newest vitals within limits, no fever for 24 hours) and an oral option the data supports | idsa-shea-asp-2016, ats-idsa-cap-2019 |

An oral option is the same drug when it is bioequivalent by mouth (levofloxacin, ciprofloxacin, metronidazole,
trimethoprim-sulfamethoxazole); otherwise an oral agent every final isolate tests susceptible to. The cefazolin
urinary surrogate counts only for urine isolates, and nitrofurantoin is never offered as a step-down. IV to PO is
not offered for meningitis or *S. aureus* bacteremia.

## Known limits (version 0.1.0)

- **Oral intake is not charted** in a structured form, in the cases or in OpenEMR. Owner decision, 2026-11-09: the
  IV to PO rule does not read it, and the finding asks the pharmacist to confirm intake before switching.
- **Immunocompromise is not checked** by the Listeria rule: age is its only risk criterion until an owner-reviewed
  list of conditions exists.
- **Problems are matched by ICD-10 code.** Stock OpenEMR 8.4.1 returns problem-list conditions as text only;
  `clinical/spike/patches/0002-problem-list-condition-codes.diff` fixes that, and the OpenEMR image carries it.
  Without it the meningitis and duration rules stay silent (tested).
- **Prescription dates.** OpenEMR returns no start date unless the order's `date_added` is set (the loader sets it
  to the start date) and marks any order with an end date `completed`, so a future stop date reads as stopped.
  A dosage timing `boundsPeriod`, when an EHR sends one, is used instead.
- The knowledge base holds what the 14 cases need and the closest related agents. An agent, organism or test it does
  not know is ignored, never guessed.
