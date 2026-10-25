# Phase 9 lite M1 spike: a microbiology scenario into OpenEMR and back out through FHIR

Run 2026-10-25 on operator workstation node1, rootless podman, by Claude Code for owner review. Plan:
[docs/plans/phase9-lite-and-review-workspace.md](../../../plans/phase9-lite-and-review-workspace.md), milestone M1.
Synthetic data only ([policy](../../../policy/synthetic-data-and-independence.md)).

**Outcome:** (a) reproducible load: **met**. (b) faithful microbiology read-back: **partly met**. Patient,
encounter, specimen type, collection and result times, each antibiotic's S, I, R or SDD interpretation (coded) and
every MIC come back. The organism is not coded, MICs with a qualifier come back as text, and nothing in FHIR links a
susceptibility result to the organism it was tested on. Per the plan, the options are listed below as an **open
decision for the owner**; M2 waits for it.

## Versions and what was checked

| Item | Value |
|---|---|
| OpenEMR | 8.4.1 (newest release, 2026-09-20), image `openemr/openemr@sha256:786e7dd8…3c55`, schema version 543 |
| PHP | 8.5.12 in that image: the release with the fixes for CVE-2026-109618 and CVE-2026-109619 (changelog #64) |
| Database | MariaDB 12.3.3, the digest OpenEMR 8.4.1's own `docker/production/docker-compose.yml` pins |
| FHIR | R4 4.0.1, US Core (the instance's CapabilityStatement) |
| Manifest and tools | `k8s/clinical/openemr-spike/pod.yaml`, `clinical/spike/` (`run.sh`, `load.py`, `readback.py`) |

The write paths and the read mapping were taken from the running instance and the 8.4.1 source in the image, not
from documentation: the CapabilityStatement, `apis/routes/*.inc.php`, `src/Services/FHIR/` and
`interface/orders/receive_hl7_results.inc.php`. Every LOINC code was checked on loinc.org, SNOMED CT codes on
tx.fhir.org, and the RxNorm code on RxNav, before use; two first-draft LOINC codes were wrong and were replaced.

## The scenario

`clinical/spike/scenario-01.json`: a 68-year-old woman admitted with acute pyelonephritis on IV ceftriaxone; basic
labs; a urine culture growing *E. coli* (SNOMED CT 112283007, >100,000 CFU/mL) with an 11-drug MIC panel set against
CLSI Enterobacterales breakpoints so that S, I, R and SDD all occur, including MICs with `<=` and `>=`. Built for
loading and read-back only, not for clinical rules.

## Load path, and why

| Data | Path | Why |
|---|---|---|
| Patient | FHIR create | One of three FHIR resources that accept writes (Patient, Organization, Practitioner; DocumentReference create) |
| Encounter, problem, prescription | Standard REST API | No FHIR write for these |
| Lab provider, the two orders, the specimen | SQL | No API places a lab order; in OpenEMR it is a UI form that writes these rows |
| Susceptibility flags S, I, R, SDD | SQL: list configuration (`susceptibility-flags.sql`) | The result-flag list has only N, A, H, L, HH, LL |
| Every lab result, including the culture | HL7 v2.5.1 ORU^R01 (`oru-r01.hl7`) through OpenEMR's own importer, `receive_hl7_results()` | The path a lab interface uses; it links a susceptibility report to its parent organism result (OBR-26, OBR-29) |

Not used: FHIR create for clinical data (not supported), C-CDA import (not needed once HL7 worked; untested), and
database seeding of results (the importer made it unnecessary). The only SQL rows written are the order-side rows the
order form would write, and list configuration.

Found along the way, each handled in the loader: FHIR Patient create reads the name only from `"use": "official"`
(without it, a valid US Core Patient fails with "First Name must not be empty"); new API clients are stored disabled
until an administrator approves them; and MariaDB's first boot must finish before OpenEMR's installer starts.

## Read-back, field by field

Through the FHIR API with a user-scoped token (password grant; the SMART EHR launch is M3).

| Requirement (plan M1 b) | Result | As returned |
|---|---|---|
| Linked to the right patient and encounter | Yes | Every Observation, both DiagnosticReports and ServiceRequests, and the MedicationRequest reference the patient and the admission |
| Specimen type | Yes | Specimen `type` SNOMED CT 122575003 Urine specimen; every culture and susceptibility Observation references it |
| Collection time | Yes, on Specimen | `Specimen.collection.collectedDateTime`; `Observation.effectiveDateTime` is the result time, not collection |
| Result time | Yes | `Observation.effectiveDateTime`, `DiagnosticReport.issued` |
| Organism | Partly | `valueString: "112283007 (Escherichia coli)"`: the code survives only inside text |
| Interpretation S, I, R, SDD | Yes, with list configuration | `interpretation` coded in `v3-ObservationInterpretation` (`SDD`, "Susceptible-dose dependent"). Stock OpenEMR, without `susceptibility-flags.sql`: `interpretation.text` only |
| MIC | Partly | Exact values as UCUM `valueQuantity` (16 ug/mL); qualified values as text (`">= 32"`, `"<= 0.25"`), not Quantity with `comparator` |
| Susceptibility linked to organism | No | No `hasMember` or `derivedFrom`. The link exists only in OpenEMR's internal report note |

Also observed:

- **One DiagnosticReport per order, holding one of its reports.** The culture's report lists the 11 susceptibility
  results but not the organism and colony count (the reverse when the panel arrives as an unordered reflex test).
  `DiagnosticReport.code` is "unknown"; `basedOn` points at the order.
- **One Specimen per ordered test**: ordering the culture and the panel together gives two Specimen resources for one
  urine sample, with the same accession number. Ordering them together is what links the susceptibilities to a
  specimen at all, but the organism and colony count reference one Specimen and the susceptibilities the other;
  a rule has to treat them as one sample by accession number.
- **ServiceRequest.code** is text only.
- **Condition** came back without its ICD-10 code (text only) and without an encounter reference; not investigated.
- Times are written and read in the container's UTC; the scenario format should carry explicit offsets (M2).

## Reproducibility

The same scenario was loaded into two fresh instances (new pod, empty database, new random credentials) and read
back. After replacing server-assigned UUIDs with stable placeholders and dropping `meta.lastUpdated`, the outputs are
identical: 25 resources, 1,597 lines, no differences and no unresolved references
(`fhir-readback.normalized.json`).

## Open decision for the owner: the microbiology data path

The spike does not choose. The options, with their trade-offs:

1. **OpenEMR only, gaps accepted.** The rules service parses the two text formats above and links a susceptibility
   to the organism through its order. Simplest; nothing extra to run. Fragile, tied to OpenEMR's quirks, and limited
   to one organism per culture: with two organisms nothing says which panel belongs to which.
2. **A side FHIR server for microbiology only** (for example HAPI FHIR), loaded from the same scenario file with
   coded organisms, `valueQuantity.comparator` and `hasMember`; OpenEMR keeps everything else and the SMART launch.
   Faithful, standard FHIR, closer to what Epic and Oracle Health return. Two sources of truth, a patient identifier
   to map between them, and another service (a JVM, roughly 0.5 to 1 GiB) on a constrained node.
3. **Fix it in OpenEMR**: map the HL7 importer's CWE organism to a coded value, SN to Quantity with `comparator`, and
   OBR-26 to `derivedFrom`, as an upstream contribution, carried as a patch in the meantime. Most faithful inside
   the EHR and useful to others. Development time; a patched image differs from stock until upstream accepts it.
4. **Option 1 now, option 3 later**: start M2 on OpenEMR as it is, with single-organism cultures, and contribute
   the fixes in parallel.

## Limits

A spike on one workstation, not a deployment: localhost only, ephemeral storage, the password grant rather than a
SMART launch, an administrator-scoped user. One scenario with one organism. The OpenEMR UI was not used or checked.
C-CDA import was not tried. No clinical rule, model or UI was built. This is not clinical validation.
