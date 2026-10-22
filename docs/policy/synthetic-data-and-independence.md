# Synthetic data and independence

Status: adopted 2026-10-22. Applies to LocumView's clinical AI work (ADR 0008, ADR 0017), the Clinical Review
Workspace (ADR 0018) and every evaluation, demo, write-up and website page that describes them. These are
LocumView's own rules, and they are binding. Changing one needs a dated entry in this file and a changelog entry.

## Why this exists

The clinical AI module works on clinical subject matter, so the line between LocumView and any real clinical setting
has to be explicit, written down and easy to check. This repository is public (mirrored to GitHub and GitLab), so the
rules are written so that they can be followed without naming anyone.

## Rules

### 1. Patient data is synthetic, always

- Every patient in LocumView is synthetic: Synthea output, or a case written by hand for the scenario library.
- No data from any employer or healthcare organization, in any form: not identified, not de-identified, not
  aggregated, not "inspired by" a specific real patient.
- No real patient data from any other source either. Public, openly licensed reference material (published
  guidelines, drug labels, antibiograms their owners publish for reuse) may be cited, with a link.

### 2. Nothing from any employer

- No employer's protocols, order sets, pathways, formularies, antibiograms, datasets, screenshots, templates,
  credentials or other confidential information, copied or paraphrased.
- Clinical rules are written from public guidelines and the primary literature, and each rule cites its source in the
  repository.

### 3. Own resources only

- Development, testing, evaluation and hosting happen only on the owner's own hardware, networks and accounts.
- No employer device, network, account, email address, software licence or paid time is used for LocumView.

### 4. No implied affiliation

- LocumView does not state or imply that any institution is affiliated with it, sponsors it, endorses it, has
  evaluated it or uses it.
- No institution, employer or person is named in this repository or on the website in connection with the clinical
  AI work, except reviewers who have given written permission to be named (ADR 0018).

### 5. Not used in clinical work

LocumView's clinical AI module, its scenario library and the Review Workspace are not used in the owner's clinical
work. They are not used, shown or referred to while the owner is working clinically, and their output is never
applied to a real patient.

### 6. Reviewers are recruited externally

- Reviewers for the Clinical Review Workspace are recruited externally only, from outside any organization the
  owner works for.
- No current colleagues of the owner are invited, even informally, even as unpaid volunteers.
- Each reviewer declares conflicts of interest before reviewing (ADR 0018).

### 7. Institution-specific lab and antibiogram work stays out of scope

Any work on laboratory data, microbiology data or antibiograms tied to a real institution is outside LocumView's demo
scope and does not go into this repository, the scenario library or the website. Scenario cases use invented
susceptibility patterns, labelled as invented.

## How the rules are checked

- **Before each merge** of clinical content (rules, scenarios, prompts, knowledge base, write-ups): the owner checks
  the change against this file. Scenario files carry a provenance field (`source: synthetic`, the author, the
  guideline citations); the scenario loader (Planned, docs/plans/phase9-lite-and-review-workspace.md) must reject a
  case without one.
- **Before each evaluation round:** the reviewer list is checked against rule 6, and the evaluation build is checked
  for any non-synthetic data.
- **Before anything is published:** names, institutions and affiliations are checked against rule 4.

## What this policy is not

It is not legal advice and not a statement of anyone else's policy. Open legal questions are kept in
`docs/legal/questions-for-a-lawyer.md`.
