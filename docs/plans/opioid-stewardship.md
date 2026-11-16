# Opioid stewardship module: plan

Status: **In progress** (owner request, 2026-11-16). O1 (#198) and O3 (#201) are built and approved; O2 is dropped (owner decision 2026-11-16, #202); the rest is planned. Every clinical threshold below is a candidate
until it is read in its primary source and approved by the owner (the clinical review process: primary sources
first, then an OpenEvidence packet the owner runs, then the owner's decisions).

A fourth module in LocumView Clinical, beside Antimicrobial Stewardship, IV to PO and ADE Monitoring: deterministic
rules flag, the local model explains, a pharmacist reviews. Inpatient, synthetic data only, the same architecture as
the ADE module's first rule (changelog #187).

## Candidate rules

| # | Rule | What it flags | Data it needs | Primary source to read | Order |
|---|---|---|---|---|---|
| O1 | Opioid with a benzodiazepine | An active opioid and an active benzodiazepine at the same time (respiratory depression) | Drug classes of active orders | FDA Drug Safety Communication (2016, boxed warning on combined use); CDC 2022 recommendation on concurrent benzodiazepines | First: no dose data needed |
| O2 | (Dropped 2026-11-16: no inpatient source, #202) No naloxone with risk factors | Opioid orders with a risk factor (O1's combination, a high daily dose, sleep apnea, opioid use disorder) and no naloxone order | Drug classes, problems; the dose part waits for D1 | CDC 2022 recommendation on naloxone; FDA 2020 labeling recommendation on naloxone | Second |
| O3 | Scheduled opioid without a bowel regimen | A scheduled opioid with no stimulant laxative or similar order | Drug classes, scheduled versus as needed | To find: a guideline that states it (cancer pain or palliative care guidance); consensus evidence may be all there is, which is an owner decision | Third |
| O4 | High daily dose | Total daily morphine milligram equivalents (MME) above a threshold, with the opioids that make it up | Dose, unit, frequency and route of every opioid order (D1); MME conversion factors | CDC 2022 guideline (its dose recommendations and MME conversion factors) | After D1 |
| O5 | Extended-release opioid in an opioid-naive patient | An extended-release or long-acting opioid (fentanyl patch, ER oxycodone, methadone) without prior opioid tolerance | Home medications and recent opioid doses (D1, D2) | FDA labels (opioid-tolerant definition and limits for ER/LA products) | After D1, D2 |
| O6 | Two scheduled opioids, or duplicate as-needed opioids | Therapeutic duplication | Classes, scheduled versus as needed | To find (ISMP or a health-system guideline) | Later |
| O7 | Renally cleared opioid in renal impairment | Morphine, codeine, tramadol or meperidine with low creatinine clearance | Creatinine, weight, age, sex; overlaps the ADE renal rule | FDA labels | With the ADE renal rule |

Tramadol or methadone with serotonergic drugs belongs to the ADE module's serotonin rule (planned with linezolid and SSRIs).

## Inpatient sources (found 2026-11-16, #201)

The CDC 2022 opioid guideline (PMID 36327391, read in PubMed Central PMC9639433) states that its recommendations do not
apply to patients who are hospitalized; they apply to prescribing at discharge. The inpatient source is the Society of
Hospital Medicine consensus statement (Herzig 2018, PMID 29624189, PMC6278928): statement 10, a bowel regimen for
hospitalized patients receiving opioids unless contraindicated (stimulant or osmotic laxatives, not stool softeners);
statement 11, limit opioids with other CNS depressants. On naloxone its working group made no recommendation: no clear
evidence for naloxone with short-term opioid therapy for acute pain. O3 rests on statement 10. O2 as an inpatient rule
has no supporting source; options for the owner: drop it, restrict it to patients on chronic opioid therapy (which needs
the home medication list), or make it a discharge rule when discharge prescribing is in scope.

## Data prerequisites

- **D1, doses through FHIR.** Today a prescription reads back with its route only. OpenEMR's FHIR
  `MedicationRequest` returns `dosageInstruction.doseAndRate.doseQuantity` and `timing.code` (HL7 timing abbreviations)
  when the order has a structured size, unit and interval; the loader sends free text only. Two changes, checked on the
  local spike before any rule depends on them: the loader writes size, unit and interval; and an OpenEMR patch for the
  dose's truncation to a whole number (`intval` in `FhirMedicationRequestService`: hydromorphone 0.5 mg reads back as 0,
  oxycodone 7.5 mg as 7), recorded in `docs/upstream/openemr-8.4.1.md` as a defect.
- **D2, home medications versus orders.** Home medications reach FHIR as `MedicationRequest` with intent `plan` beside
  the orders (intent `order`); the app lists both (Thea Casebook's apixaban shows twice). Opioid tolerance needs the
  home list on purpose, and every rule needs to tell the two apart: the snapshot keeps intent, rules state which they
  read, and the app labels home medications.
- **D3, opioid knowledge.** `opioid_agents` in the knowledge base: class (opioid, benzodiazepine, laxative, naloxone),
  extended-release flag, MME conversion factor by route, renal flag; RxNorm products checked in RxNav as before.

## Registration (as for ADE, #187)

Module id `opioid`, shown as "Opioid Stewardship": the case checker's modules and finding types, the agent service's
modules, the app's tab and type labels, `docs` and changelog. Each rule: a knowledge entry with its references, a
reviewed "why it matters" line, a positive case and a near-miss negative control, FHIR fixtures from the spike, a
photograph per new patient, and boundary tests.

## Milestones

1. **O1** end to end (rule, two cases, review, deploy), with the module registered. No dependency.
2. **O2 and O3** (class rules; O2's dose part waits).
3. **D1 and D2** on the spike: structured doses through FHIR, the truncation patch, intent in the snapshot, home
   medications labelled in the app.
4. **O4, then O5.** O7 with the ADE renal rule; O6 when a source is found.

## Owner decisions

Made 2026-11-16: inpatient orders only (the rules skip the home medication list); O1 covers benzodiazepines and
gabapentinoids; O1 first. Still open:

1. (decided) Scope: inpatient only.
2. (decided) O1's second drug class: benzodiazepines and gabapentinoids.
3. O3 without a guideline that states it: build it on consensus, marked as such, or leave it out?
4. O4: count as-needed orders at their maximum daily dose, or scheduled doses only; which threshold or thresholds to
   flag (the 2022 CDC guideline frames doses as points for careful evaluation rather than hard limits; to read).
5. (decided) First rule: O1.
