# LocumView clinical rules (Phase 9 lite M4)

The deterministic part of the agent service in [ADR 0017](../../docs/adr/0017-clinical-ai-workspace-architecture.md)
and plan M4 ([docs/plans/phase9-lite-and-review-workspace.md](../../docs/plans/phase9-lite-and-review-workspace.md)):
rules decide what is flagged; the local model only explains a finding, never adds or removes one. The rules and the
explanation guard use the standard library only, so their tests run unchanged in pre-commit and CI.

```fish
python3 clinical/agent/test_rules.py      # every case's expected findings, and each rule's boundaries (no packages)
python3 clinical/agent/test_explain.py    # the explanation guard over every case's findings, against a fake model
clinical/agent/run.sh test                # the service's tests too, in the pinned Python image (CI runs the same)
SITE_TZ=America/New_York clinical/agent/run.sh serve     # the service on http://127.0.0.1:8090, for local tests
```

## The service

`service.py` is the agent service of ADR 0017 (FastAPI). The clinical app's gateway reads the launched patient's chart
from the EHR and posts it to `POST /v1/findings` as `{"resources": [...]}`; the service returns each finding with its
evidence and its references (title, source, PubMed id or DOI), the knowledge-base version and the snapshot's "now".
It holds no EHR credential (owner decision, 2026-11-09); its only outbound request is to the model server, for
explanations. It refuses a request without exactly one Patient and an Encounter,
with unknown modules, or with more than 5,000 resources, and does not echo chart content in errors. `GET /healthz`
reports the knowledge-base version. Settings: `SITE_TZ` (required), `KNOWLEDGE_FILE`, `CITATIONS_FILE`, `OLLAMA_URL`
and `MODEL_FILE`. Packages: `requirements.txt` (FastAPI and Uvicorn, hash-pinned, taken from the gateway's),
`requirements-test.txt` (httpx for the test client). Image: `clinical/images/agent/`; deployment:
`k8s/clinical/agent.yaml`.

## Explanations

`POST /v1/explanations` takes the same request as `/v1/findings`, runs the same rules, and has the local model
(`explain.py`) explain each finding the rules made. Nobody can ask it to explain a finding of their own: the gateway
sends only the chart. Owner decisions, 2026-11-09: `gemma4:26b` on the existing Ollama server, and explanations load
after the findings, so a slow or missing model never holds the findings back.

- **What the model sees:** one finding: its type, drug, summary, the data the rule used and its references' titles.
  Never the chart.
- **Pinned:** `model.json` names the model, its digest, the prompt file (`prompts/explain-v2.txt`; v1 kept as it was) and the
  generation options (temperature 0, a fixed seed). The service refuses to explain (503) unless the Ollama server's
  copy of the model has that digest, so an evaluation build's explanations come from one known model. A new prompt is
  a new file, and `model.json` points at it.
- **Guard:** an explanation is shown only if every number in it and every antimicrobial it names is already in the
  finding; antimicrobials are caught by their name stems, so one the knowledge base does not list is caught too,
  while classes (cephalosporins, carbapenems) are allowed. A reply that fails is withheld, never repaired; the app
  says so and the finding stands. It is a floor, not proof that the prose is right: a pharmacist reads it against the
  data shown beside it.
- **Reply:** per finding `status` `ok` with `text`, `withheld` with `reason`, or `unavailable`, plus the model's name,
  digest and prompt.

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
| `iv-to-po-switch` | iv-to-po, iv-to-po-switch | An IV antimicrobial, a stable patient (newest vitals within limits, no fever for 24 hours) and an oral option the data supports | idsa-shea-asp-2016 and the guideline of each charted condition (pneumonia: ats-idsa-cap-2019; pyelonephritis: idsa-cuti-2025) |

An oral option is the same drug when it is bioequivalent by mouth (levofloxacin, ciprofloxacin, metronidazole,
trimethoprim-sulfamethoxazole); otherwise an oral agent every final isolate tests susceptible to. The cefazolin
urinary surrogate counts only for urine isolates, and nitrofurantoin is never offered as a step-down. IV to PO is
not offered for meningitis or *S. aureus* bacteremia.

## Known limits (version 0.4.0)

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
- **Severity and source control are not judged.** IDSA 2026 allows completing an empirically started ceftriaxone course for a moderate-risk AmpC organism in a non-severe infection with clinical improvement and source control, but does not define non-severe. The AmpC and IV to PO findings state that condition and leave the judgment to the pharmacist (owner decision, 2026-11-12).
- **Pneumonia severity is not judged.** The duration review for pneumonia follows ATS 2025 (fewer than 5 days, at least 3, once stable in nonsevere CAP; 5 or more in severe CAP): it fires from day 5 without a stop date and states both, leaving severity to the pharmacist (owner decision, 2026-11-12).
- **Listeria age threshold.** The rule fires above 50 (IDSA 2004, ESCMID 2016) and cites WHO 2025 only above 60, its own threshold. WHO 2025's other risk factors (pregnancy, transplantation, malignancy, diabetes and others) are not checked yet.
- **Organisms are matched by SNOMED CT code.** A culture reported by name only matches no organism rule. Klebsiella aerogenes (62592009) is one concept that also carries its former name, Enterobacter aerogenes.
- The knowledge base holds what the 14 cases need and the closest related agents. An agent, organism or test it does
  not know is ignored, never guessed.
