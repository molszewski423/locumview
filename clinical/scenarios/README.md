# Phase 9 lite scenario library

Versioned synthetic cases for the clinical AI demo (plan M2,
[docs/plans/phase9-lite-and-review-workspace.md](../../docs/plans/phase9-lite-and-review-workspace.md)), under the
[synthetic data and independence policy](../../docs/policy/synthetic-data-and-independence.md). Each case is the data
to load into OpenEMR and the answer the rules must give.

```fish
python3 clinical/scenarios/check_cases.py                  # check every case (pre-commit and CI run this)
python3 clinical/scenarios/check_cases.py --require-approved   # what a frozen evaluation build must pass
python3 clinical/scenarios/load.py --reset                 # fresh local OpenEMR, background patients, every case
python3 clinical/scenarios/load.py                         # load into the running instance; loaded cases are skipped
scripts/clinical/load-scenarios.sh                         # the clinical namespace (owner run, k8s/clinical/README.md)
```

The loader writes to the local instance from the M1 spike (`clinical/spike/run.sh`, rootless podman, localhost only)
or, with `--target cluster`, to OpenEMR in the clinical namespace. Both are reached the same way
(`targets.py`): SQL inside the database container with its own root password, and API calls inside the OpenEMR
container with the administrator credentials in its environment, so no credential reaches the machine running the
loader. For the length of a load it registers and enables a loader API client and turns on the password grant;
afterwards it deletes the client and restores the grant. Read a case back with
`clinical/spike/readback.py LV-<case id> <dir>` (every case shares the family name Casebook).
Loading is idempotent: each case's patient has the patient number `LV-<case id>`, and a case already present is
skipped. No manual chart entry, ever.

## Case format `locumview-case/1`

One JSON file per case in `cases/`, named after its `id`. `check_cases.py` enforces the rules below and rejects
unknown keys.

| Field | Content |
|---|---|
| `schema`, `id`, `version`, `title` | `locumview-case/1`; the file name; a semantic version, raised on every change |
| `kind` | `finding` (at least one expected finding), `negative-control` (none) or `ambiguous` (two or more `acceptable_answers`) |
| `modules` | `stewardship`, `iv-to-po`; a module listed with no finding for it must stay silent |
| `provenance` | `source: synthetic` (required), author, created, and `clinical_review` (`pending` or `approved` with reviewer and date) |
| `story` | The patient story as a clinician would tell it |
| `patient`, `encounter` | Synthetic demographics; encounter class, start and reason |
| `problems`, `allergies`, `prescriptions`, `vitals` | Chart data; prescriptions carry RxNorm codes |
| `labs` | Orders with LOINC-coded results |
| `cultures` | One organism per culture (or `no_growth`, or `status: pending`), with SNOMED CT specimen and organism and LOINC-coded MIC results |
| `expected_findings` | Per finding: module, type, drug and a one-line summary |
| `reference_answer`, `rationale` | What a pharmacist should recommend, and why |
| `citations` | References from `citations.json`, each with what it supports |

Every time carries an offset (`2026-10-20T14:00:00-04:00`); the loader stores UTC. Finding types:
`bug-drug-mismatch`, `suboptimal-agent` (tests susceptible, but not the preferred agent), `missing-empiric-coverage`,
`de-escalation`, `iv-to-po-switch`, `redundant-coverage`, `duration-review`.

## Codes and citations

Every LOINC, SNOMED CT and RxNorm code in a case was checked against loinc.org, tx.fhir.org or RxNav before use.
`citations.json` records each reference's PubMed metadata. Whether a case applies a guideline correctly is the
owner's clinical review: a case stays `pending` until then, and `--require-approved` keeps unreviewed cases out of an
evaluation build. Two cited guidelines (IDSA 2025 complicated UTI, IDSA 2026 resistant gram-negative guidance) are
newer than the drafting agent's knowledge and are marked for the owner to read.

## Limits from M1

One organism per culture until OpenEMR links susceptibilities to organisms (M1 decision, option 4). Through FHIR the
organism arrives as text with its SNOMED code inside (`"414102007 (Enterobacter cloacae complex)"`), MICs with a
qualifier as text (`"<= 1"`), and lab ServiceRequests stay `active` after results arrive: the rules read results, not
order status. Prescriptions: the loader maps `IV`, `PO`, `IM` and `SC` to OpenEMR's `drug_route` list ids, so
`MedicationRequest.dosageInstruction.route` carries the NCI code (C38276 IV, C38288 oral); stopped prescriptions read
back as `completed`. Allergies with an `rxnorm` or `snomed` code read back coded; problems read back as text
only (OpenEMR's FHIR problem-list query does not parse the stored code). Background patients:
[../synthea/README.md](../synthea/README.md). Details: [docs/evidence/clinical/20261025-openemr-m1-spike/](../../docs/evidence/clinical/20261025-openemr-m1-spike/README.md).
