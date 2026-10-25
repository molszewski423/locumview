# Plan: Phase 9 lite and the Clinical Review Workspace

Status: **In progress**. Written 2026-10-22. Phase 4's core release milestone is Done (changelog #70); M1, the
OpenEMR spike, is Done (changelog #72) and M2 waits on the owner's microbiology data-path decision (section 9). Decisions: ADR 0017 (and its update of 2026-10-22),
ADR 0018. Data rules: `docs/policy/synthetic-data-and-independence.md`. Status of record: ROADMAP.md.

## 1. Sequence

1. **Phase 4**, packaging and supply chain (core release milestone Done, changelog #70).
2. **Phase 9 lite**, the clinical AI demo, ending with a frozen evaluation build (Planned; this plan, milestones M1 to
   M6).
3. **Phase 8 lite**, the demo video and first write-ups (Planned).
4. **Phase 7**, AWS, alongside SAA-C03 study (Planned).
5. **The Clinical Review Workspace**, the first slice of the full Phase 9 (Planned; milestones M7 to M10).
6. **Phase 6** and the **full Phase 9** (Planned).

Phase 5 (SUSE) runs in parallel throughout. **The Review Workspace must not delay Phase 8 lite**: no Review
Workspace milestone starts before Phase 8 lite is done, and nothing in Phase 8 lite waits on a reviewer.

## 2. Milestones and acceptance criteria

Each milestone gets a changelog entry when it is done, with what was found and how it was verified.

### M0. Phase 4 done (prerequisite)

As defined by the release sequence in `notes/release-integrity-report.md` and ROADMAP.md. Not part of this plan.

### M1. Spike: a scenario in and microbiology out of OpenEMR

The first task after Phase 4. No UI work. **Done 2026-10-25** (changelog #72): (a) met, (b) partly met; evidence and
the options in `docs/evidence/clinical/20261025-openemr-m1-spike/`.

- **Pinned:** an OpenEMR release (8.0.0 was current on 2026-10-22; the spike used 8.4.1, the newest release, on PHP 8.5.12), on a PHP release
  with the fixes for CVE-2026-109618 and CVE-2026-109619 (changelog #64), deployed from manifests in this repository.
- **(a) Reproducible load:** one scenario with a patient, an encounter, medications, basic labs, a blood or urine
  culture with an organism and an antibiotic susceptibility panel, loaded by a script from a file in this repository.
  Loading it twice into fresh instances gives the same FHIR output (compared after removing server-assigned IDs and
  timestamps).
- **(b) Faithful read-back:** through OpenEMR's FHIR API, as a SMART app would see it, the culture comes back with the
  specimen type, collection time, result time, organism, each antibiotic's interpretation (S, I, R, SDD) and the MIC
  where present, linked to the right patient and encounter.
- **How the load is done** is found, not assumed. OpenEMR's documentation (checked 2026-10-22) lists reads and searches
  and does not say which resources accept writes, so candidate paths are FHIR create where it works, C-CDA import,
  OpenEMR's HL7 lab-results path, and direct database seeding. The spike records which path was used and why.
- **Output:** an evidence note (`docs/evidence/clinical/`) with the OpenEMR and PHP versions, the documentation it was
  checked against, the load path, the FHIR output, and what did not round-trip.
- **If microbiology does not round-trip faithfully:** the evidence note lists the options (for example a side FHIR
  server holding only the microbiology resources, next to OpenEMR) with their trade-offs, as an open decision for the
  owner. The spike does not choose one, and M2 onward waits for the decision.

### M2. Scenario library v0 and its loader

- 10 to 20 hand-built synthetic cases, each a versioned file in this repository, with: patient story, data to load,
  **expected findings** (or none, for a negative control), **clinical rationale**, **guideline citations**, a
  **reference answer**, a version, and a provenance block (`source: synthetic`, author).
- At least 3 **negative controls** (no intervention appropriate) and at least 2 **ambiguous cases** (where reasonable
  pharmacists could differ, with the range of acceptable answers written down).
- A schema for case files, checked in CI; the loader refuses a case without provenance.
- The loader brings a fresh OpenEMR to a known state from the repository with one command, idempotently. No manual
  chart entry, ever.
- Synthea supplies background patients only; every case with an expected finding is hand-built.

### M3. Clinical app shell and EHR launch

- The React and TypeScript app (ADR 0017) served from k3s behind Keycloak, opened from a launcher in the image (signed
  pipeline) in the managed Chrome app mode, with its address and OpenEMR's added to the Chrome allowlist and recorded
  in `hardening/browser/README.md`.
- SMART on FHIR EHR launch from an OpenEMR chart opens the app in that patient's context.
- Home dashboard, alert queue, patient view, with no findings yet. No order entry and no write to the EHR.

### M4. Rules and explanation pipeline

- The agent service (Python, FastAPI): stewardship rule set first, then IV to PO.
- Every rule cites its guideline source in the repository. Every case in the library has a test: the rules must
  produce exactly the expected findings (including none for negative controls). Tests run in CI.
- The local model (existing Ollama service) writes the explanation for a finding from the finding and its source data
  only; it never adds or removes a finding. Each explanation shows the data and citations it rests on.
- Prompts, model name and version, and the knowledge base are versioned in the repository.

### M5. Phase 9 lite demo criterion

ADR 0017's walkthrough passes: a pharmacist signs in at the LocumView desktop, opens the clinical app from its icon,
launches it from an OpenEMR chart in patient context, and sees at least one stewardship and one IV to PO finding with
the agent's explanation, on synthetic data and local models.

### M6. Internal refinement and the frozen evaluation build (Phase 9 lite exit)

- The owner works through every case: false positives, misses, explanation quality and the UI; each fix is a
  versioned change with a test.
- The library grows to **20 to 30 cases** for evaluation, keeping the share of negative controls and ambiguous cases.
- **Exit criterion:** a frozen, versioned evaluation build: rules, model and version, prompts, knowledge base, scenario
  set and app all pinned, with one identifier and a manifest of hashes. Its outputs on every case are exported as the
  data the Review app shows.

### M7. Clinical Review Workspace built (after Phase 8 lite; ADR 0018)

- The Review app (welcome, instructions, case dashboard with progress and estimated time, resume, per-case view,
  structured form), reading the frozen build's exported outputs; reviewers cannot see each other's answers.
- IdM reviewer group and HBAC rule, Keycloak reviewer group, reviewer desktops from OpenTofu with the per-user headless
  session (port 3390, credentials in the Guacamole connection) and the Review app at sign-in.
- Tested end to end with a test reviewer account: invitation, entry point, Keycloak with TOTP, Guacamole, desktop,
  Review app, submitted form; then the desktop destroyed with nothing left behind.
- The reviewer entry point and the privacy-policy changes (section 6) are drafted in the website repository and
  published only on the owner's go, after the legal questions on reviewer data are answered.

### M8. Evaluation round 1: three experienced clinical pharmacists

Methodology in section 4. Round closed, results analyzed, findings documented.

### M9. Refinement and later rounds

Fixes from round 1 as a new frozen build; optionally an infectious diseases physician; later five to seven reviewers.

### M10. Report and published findings

Section 4.5. Names and endorsements only with written permission.

### Dependencies

| Milestone | Depends on |
|---|---|
| M1 | M0 |
| M2 | M1 (and the owner's microbiology decision if M1 fails) |
| M3 | M1 (the pinned OpenEMR), the signed image pipeline (Phase 4) |
| M4 | M2, M3 |
| M5 | M4 |
| M6 | M5 |
| Phase 8 lite | M6 (the demo it films) |
| M7 | Phase 8 lite done; M6 (the frozen build); node1 capacity freed (section 5) |
| M8 | M7; legal questions 5 and 6 answered |
| M9, M10 | M8 |

## 3. Reviewer workflow and app architecture

### 3.1 Workflow

1. The owner recruits reviewers externally (policy rule 6), verifies each license through the state board's public
   lookup, and records only "verified, date, verifier".
2. The owner sends an invitation email pointing at the reviewer entry point on locumview.com. The link signs no one
   in.
3. The reviewer reads the entry point (what the review is, the attestation, the privacy terms) and signs in through
   Keycloak, enrolling TOTP the first time.
4. Guacamole opens the reviewer's desktop directly; the Review app starts in the managed Chrome.
5. First run: welcome, instructions, profile (section 6), conflict-of-interest declaration, consent and attestation.
6. The dashboard lists the assigned cases with progress and an estimated time per case; the reviewer can stop and
   resume.
7. Per case: history, medications, labs, microbiology, timeline, the AI finding, its explanation, its evidence and the
   proposed intervention; then the structured form.
8. When all cases are submitted, the reviewer is thanked and signed out; at the end of the review window the account
   is disabled and the desktop destroyed.

### 3.2 Architecture

- **Review app:** React and TypeScript, LocumView design language, served from k3s behind Keycloak (OIDC). Shares UI
  components with the clinical app (a shared component package in the repository); does not import the clinical app's
  rule modules or call the agent service.
- **Input:** the frozen evaluation build's exported outputs (per case: data, finding, explanation, evidence, proposed
  intervention), loaded read-only.
- **Store:** assessments, reviewer profiles and consent records in a database in the cluster, with encrypted backups.
  A reviewer's API can read only that reviewer's own records; aggregate views exist only for the owner role and only
  after the round is closed.
- **Desktops:** OpenTofu-created reviewer VMs, Standard tier (2 vCPU, 4 GiB), one per reviewer, created for the window
  and destroyed after.

## 4. Evaluation methodology

### 4.1 Reviewers

- **Round 1:** three experienced clinical pharmacists.
- **Optional, after refinements:** an infectious diseases physician.
- **Later:** five to seven reviewers.
- Recruited externally only; conflicts of interest declared; qualifications recorded as in section 6.

### 4.2 Fixed before each round

- **Scoring criteria** written before the round: the form's scales (accuracy, appropriateness, completeness of the
  evidence, clinical relevance), what each point means, what counts as a safety concern, and what accept, modify and
  reject mean.
- **Frozen inputs:** rules, model and version, prompts, knowledge base and dataset, recorded by the evaluation build's
  identifier. Nothing changes during a round.
- **Case assignment:** every reviewer sees every case in round 1 (three ratings per case), in a randomized order per
  reviewer.

### 4.3 Analysis

- **False positives and false negatives** against each case's expected findings and reference answer, and against
  the reviewers' judgment where they disagree with the reference.
- **Agreement reported descriptively:** percent agreement per item and a chance-corrected statistic (for example
  Fleiss' kappa or Gwet's AC1) with its confidence interval. **With three raters the intervals are wide**, and kappa
  behaves badly when nearly every answer is the same; the report says so and draws no strong conclusion from them.
- **Disagreements documented** case by case, with the reviewers' free text, and how each was resolved (rule change,
  case rewritten, reference answer changed, or left open).
- **Regression suite:** every case, with its reference answer and any changes from review, becomes a test that each
  later build must pass.

### 4.4 What it is not

It is a structured expert review of a research prototype on synthetic data. It is never described as clinical
validation, regulatory approval, certification, or proof of safety or effectiveness.

### 4.5 The report (outline)

1. Objectives
2. Methods: the system under review, the scoring criteria, the review process
3. Reviewer qualifications (designation, specialty, certifications, years of experience; named only with written
   permission)
4. Case selection: how cases were written, negative controls, ambiguous cases, provenance
5. Versions: the evaluation build's identifier and manifest
6. Findings: per criterion, false positives and negatives, safety concerns
7. Agreement, with the small-sample caveat
8. Limitations: synthetic data, few reviewers, one EHR, the author wrote the cases and the rules
9. Attestations, as signed
10. Changes made in response

Names and any endorsement are published only with each reviewer's written permission. Whether publishing aggregated
assessments (a conference abstract or a journal) needs an IRB exemption determination is an open legal question
(`docs/legal/questions-for-a-lawyer.md`, question 5).

## 5. Capacity on node1

Measured read-only on node1, 2026-10-22, during the Phase 4 release sequence. node1 has 30 GiB of RAM usable by the
host (32 GB installed). ADR 0010: 8 GiB host reserve; idm01 fixed at 4 GiB; Standard desktops 2 vCPU and 4 GiB. ADR
0010's update of 2026-10-06: libvirt VMs are invisible to k3s, so node1's kubelet `system-reserved` must cover every
VM's **maximum** memory plus 6 GiB for the host desktop and the AI stack.

### 5.1 Today

| VM | Maximum | Current | Held by the host |
|---|---|---|---|
| idm01 | 4 GiB | 4 GiB | 1.0 GiB |
| reference desktop (retiring) | 6 GiB | 4 GiB | 1.3 GiB |
| lv-demo01 (live demo) | 8 GiB | 8 GiB | 1.9 GiB |
| release test desktop (Phase 4) | 6 GiB | 6 GiB | 5.9 GiB |
| **Total** | **24 GiB** | | **10.1 GiB** |

KSM is saving about 5.4 GiB; `MemAvailable` is about 13 GiB. The rule calls for `system-reserved` of 24 + 6 = 30 GiB;
it is still set to 16 GiB (the value for two VMs, changelog #40). **The rule is not being met today**: it was not
raised when lv-demo01 and the release test desktop were created. The VMs fit physically because free page reporting
and KSM work as ADR 0010 intended, but k3s believes it has about 14 GiB more than the rule allows it. This is to be
fixed (owner run) before more VMs are added; it is recorded here, not changed by this plan.

### 5.2 For a review round

After Phase 4: the reference desktop retires (minus 6 GiB) and the release test desktop is destroyed (minus 6 GiB),
leaving idm01 and lv-demo01, 12 GiB of maxima.

| Scenario | VM maxima | `system-reserved` by the rule | Left for k3s pods on node1 (its 30.5 GiB, or about 62.5 GiB after the upgrade, minus `system-reserved` and 1 GiB kube-reserved) |
|---|---|---|---|
| After Phase 4, no reviewers | 12 GiB | 18 GiB | about 11.5 GiB |
| Two reviewer desktops | 20 GiB | 26 GiB | about 3.5 GiB |
| Three reviewer desktops | 24 GiB | 30 GiB | about 0 GiB: **does not fit** |
| Three reviewers, lv-demo01 lowered to Standard (4 GiB) for the window | 20 GiB | 26 GiB | about 3.5 GiB |
| Three reviewers after the 64 GB upgrade (ADR 0010 step 1) | 24 GiB | 30 GiB | about 31 GiB |

The pods that must fit in what is left include Phase 9 lite's own services (OpenEMR and its database, the clinical
app, the agent service, the Review app and its database), not yet measured; node1's pod requests today are about
1.6 GiB. So:

- **Three concurrent reviewers do not fit on node1 at 32 GB** under ADR 0010's rule, even after the retirements.
- **Two concurrent reviewers fit, tightly**, with Phase 9 lite's services squeezed into about 3.5 GiB, or scheduled on
  node2 (k3s pods can move; the VMs cannot).
- **Ways to run round 1's three reviewers,** for the owner to choose when M7 starts: staggered windows (at most two
  desktops at once); lv-demo01 at the Standard tier for the window; Phase 9 lite's services pinned to node2; the 64 GB
  memory kit (ADR 0010's first scale-up step); or the browser-only fallback (ADR 0018), which needs no VMs.
- The Ollama model that writes explanations runs on the host's GPU (16 GiB of video memory); if the chosen model does
  not fit in it, Ollama holds the rest in host memory, inside the 6 GiB allowance. The model is to be sized against
  that before M4.

These are estimates from one measurement on a busy day; M7 starts with a fresh measurement.

## 6. Reviewer data

### 6.1 Collected, and not

| Collected | Purpose |
|---|---|
| Professional name | Identify the reviewer to the owner; acknowledgement only with opt-in |
| Designation (for example PharmD, MD) | Report reviewer qualifications |
| Specialty | Same |
| Board certifications | Same |
| Years of experience | Same |
| Conflict-of-interest declaration | Independence |
| Consent and attestation, with date and text version | Record of agreement |
| Optional opt-in to a public acknowledgement | Naming, only with written permission |
| Email address (for the invitation and Keycloak account) | Contact and sign-in |
| License verification: "verified", date, verifier | Shows a person checked the public lookup |

**Not collected:** license numbers, date of birth, home address, employer (beyond the conflict-of-interest
declaration's own text), and any patient information.

### 6.2 Access, retention and deletion (proposed)

- **Access, role-based:** the owner (administrator) sees all reviewer data and assessments; a reviewer sees only their
  own; nobody else has access. Keycloak sign-in events follow the existing 90-day log retention.
- **Retention:** the reviewer's Keycloak account and desktop are removed at the end of the review window. Profile and
  contact details are deleted 12 months after the last round the reviewer took part in, unless they ask to stay on the
  reviewer list. Assessments are kept, pseudonymized (reviewer code, not name), for as long as a report based on them
  is published, so the findings stay checkable. Consent records are kept as long as the assessments they cover.
- **Deletion on request:** profile, contact details and assessments are deleted from the store within 30 days.
  Aggregates already published cannot be withdrawn, but the reviewer's assessments are excluded from every later
  analysis. This is stated in the consent text before the reviewer agrees.

### 6.3 Privacy-policy changes required (draft only; not published)

A new section in both versions of the policy, "Clinical review program", covering: who is invited and how; what is
collected (6.1) and what is not; why; the legal basis in the EU version (consent for the optional acknowledgement;
legitimate interests or consent for the rest, to be confirmed by counsel); retention and deletion (6.2); that
assessments may be published in aggregate and names only with written permission; and the reviewer's rights.

### 6.4 If EU reviewers are possible

The data is professional, not special-category, but GDPR applies to EU-based reviewers: a lawful basis per purpose,
transparency (the policy section above), data subject rights, records of processing, and transfers to the US (the
existing Data Privacy Framework and SCC position, questions 1 and 2 in the legal file). Whether an EU representative
under Article 27 is needed becomes more pressing once EU reviewers are recruited deliberately. Question 6 asks counsel
before any EU reviewer is invited; until it is answered, round 1 recruits US-based reviewers only.

## 7. Website build-log milestones (Planned)

For the build log on locumview.com, in order, each shown as Planned until done:

1. OpenEMR and Synthea: the mock EHR, with microbiology checked end to end (M1)
2. Scenario library: versioned synthetic cases with expected answers (M2)
3. Clinical app: launched from the EHR chart in the hardened desktop (M3)
4. Rules and explanation pipeline: rules flag, a local model explains (M4, M5)
5. Internal refinement: the frozen evaluation build (M6)
6. Clinical Review Workspace (M7)
7. Independent evaluation (M8, M9)
8. Published findings (M10)

## 8. Proposed website disclosure text (draft; the site is not edited by this plan)

> **About LocumView's clinical AI work.** LocumView's clinical AI module is a research prototype, built and tested
> only on synthetic patient data. No real patient data, and no data, protocols or confidential information from any
> employer or healthcare organization, is used in it. It is developed independently, on the author's own time and
> resources, and is not affiliated with, sponsored by or endorsed by any institution. It is not used in patient care.
> Any expert review of it is an independent professional assessment of a prototype, not clinical validation,
> certification or regulatory approval.

## 9. Open decisions for the owner

1. **Product naming:** is ADR 0017's app "AMS Intelligence", or is AMS Intelligence one module within it?
2. **Microbiology data path**: the M1 spike found that cultures and susceptibilities round-trip only partly; the
   four options and their trade-offs are in `docs/evidence/clinical/20261025-openemr-m1-spike/README.md`.
3. **Reviewer delivery:** VDI (ADR 0018's design) or the browser-only fallback, per round.
4. **Legal questions** 5 and 6 in `docs/legal/questions-for-a-lawyer.md`, before M8.
