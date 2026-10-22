# ADR 0018: Clinical Review Workspace

Status: Accepted (design; nothing below is built)
Date: 2026-10-22

## Context

ADR 0017 plans the clinical AI module, and its update of 2026-10-22 ends Phase 9 lite with a frozen, versioned
evaluation build. The next question is whether the module's findings and explanations hold up when experienced
clinicians outside the project look at them. That needs a way for invited reviewers to work through synthetic cases,
see each finding with its evidence, and record a structured assessment, with their answers kept independent of each
other.

LocumView already has every piece needed to put a reviewer in front of an application safely: a hardened desktop
image (ADR 0007), OpenTofu to create and destroy desktops (ADR 0013), Keycloak with enforced TOTP (ADR 0005), IdM for
accounts, groups and host-based access control (ADR 0006), Guacamole (ADR 0015) and the access layer on k3s
(ADR 0002). Using them for reviewers is also a real test of the platform: short-lived, named users with scoped
access, which is what a hospital deployment of LocumView would need for locums and auditors.

## Decision

### 1. A subproject of LocumView, not a product

The Clinical Review Workspace is a way to run evaluation rounds of the clinical AI module. It is not sold, not
offered as a service and not positioned as a product. It reuses the bootc image, OpenTofu, Keycloak with TOTP, IdM,
Guacamole and k3s. **No new identity platform, desktop image or application framework.**

### 2. Reviewer access path

1. The owner sends an **invitation email** with a link to the reviewer entry point.
2. The **reviewer entry point on locumview.com** explains the review, the attestation and the privacy terms, and
   links to the login.
3. **Keycloak with MFA** (TOTP enrolled at first sign-in) authenticates the reviewer.
4. **Guacamole** opens the reviewer's connection straight away (the straight-to-desktop pattern of changelog #19).
5. The **reviewer's desktop** starts the Review app automatically in the managed Chrome app mode (ADR 0016).

**The invitation link is not authentication.** It carries no token that signs anyone in; it only points at the
entry point. Keycloak and MFA are the only way in, and the account exists only for the review window.

### 3. Per-user headless session, no second password

Reviewer desktops use the per-user headless session pattern already used for lv-demo01's owner connection: GNOME
Remote Desktop in user mode on port 3390, with the RDP credentials held in the Guacamole connection, so the reviewer
does not type a second password at the GNOME login screen. Keycloak and MFA remain the authentication.

Reviewer behavior comes from **configuration, groups and HBAC**, not a new image:

- an IdM group (for example `locumview-reviewers`) and an HBAC rule that lets its members sign in only to reviewer
  desktops;
- a Keycloak group that maps to the reviewer's Guacamole connection and to the Review app's role;
- a dconf profile or autostart entry, set by provisioning for the reviewer account, that opens the Review app at
  sign-in; the STIG settings (screen lock, clipboard copy-out blocked) stay on.

### 4. Short-lived reviewer desktops

Reviewer desktops are OpenTofu-created VMs, one per reviewer, created for a review window and destroyed afterwards
(IdM host, Guacamole connection, Red Hat registration and disks removed, as in changelog #54 and #59). Standard tier
(2 vCPU, 4 GiB, ADR 0010). The capacity arithmetic for node1 is in
`docs/plans/phase9-lite-and-review-workspace.md`; in short, node1 can carry three reviewer desktops only after the
reference desktop and the release test desktop are gone, and only if `system-reserved` is raised to cover them.

### 5. One Review app

- React and TypeScript, in LocumView's design language. It shares UI components (patient header, lab and
  microbiology tables, timeline, finding card) with the clinical app of ADR 0017, but **does not import the clinical
  app's rule modules**. It reads a frozen evaluation build's outputs (findings, explanations, evidence) as data, so a
  review round cannot change what is being reviewed.
- Screens: welcome; instructions; a dashboard of assigned cases with progress and estimated time; resume where the
  reviewer stopped; a per-case view (history, medications, labs, microbiology, timeline, the AI finding, its
  explanation, its evidence, and the proposed intervention).
- A structured form per case: accuracy, appropriateness, completeness of the evidence, clinical relevance, safety
  concerns, accept / modify / reject, free text, and usability.
- **Independence:** a reviewer cannot see any other reviewer's answers, before or after submitting, inside the app.
  Aggregates are computed by the owner after the round closes.
- Served from k3s behind Keycloak (OIDC), like the rest of the access layer.

### 6. Reviewer data is minimized

Collected: professional name, designation, specialty, board certifications, years of experience, a
conflict-of-interest declaration, consent, and an optional opt-in to a public acknowledgement.

**Not collected: license numbers.** The owner verifies each reviewer's license out of band through the state board's
public lookup; the app stores only "verified", the date and who verified it.

Retention, role-based access, deletion and the privacy-policy changes are in the plan document. Attestation text, shown
before the first case and recorded with consent:

> This is an independent professional assessment of a research prototype, made on synthetic data. It is not a
> certification that the software is fit for patient care.

## Options considered for reviewer delivery

The VDI path above is the design. A **browser-only fallback** is recorded as an option and **not chosen yet**: the
Review app published behind Keycloak OIDC, opened in the reviewer's own browser, with no desktop.

| | VDI (decided design) | Browser-only fallback (option) |
|---|---|---|
| What it shows | The whole LocumView path: Keycloak, Guacamole, the hardened desktop, the managed Chrome | The Review app and Keycloak only |
| Reviewer effort | MFA enrolment, then a remote desktop in a browser tab; some latency | MFA enrolment, then a web page; fastest to use |
| Node1 memory | About 4 GiB per concurrent reviewer (one VM each) | Near zero per reviewer |
| Data exposure | Cases stay on the desktop; copy-out blocked | Cases rendered on the reviewer's own device |
| Operating cost | A VM created and destroyed per reviewer per round (OpenTofu, owner runs) | One deployment for all reviewers |
| Platform evidence | Exercises named, short-lived users end to end | Little |

Both use the same Review app, so choosing one later does not change the app.

## Rationale

- **Reuse proves the platform.** A review round is a small, real deployment: named users, MFA, scoped desktops,
  creation and destruction from code. Building a separate review site would show none of that.
- **No second password** removes the step most likely to lose a busy clinician reviewer, without weakening
  authentication: Keycloak and MFA stay in front.
- **Groups and HBAC instead of an image** keep one signed image for every desktop (ADR 0007) and make the reviewer
  role reviewable as configuration.
- **A separate Review app** keeps the review independent of the system under review: the reviewer sees what the frozen
  build produced, and nothing in the review can change it.
- **Minimal reviewer data** limits what can leak and what has to be governed; license numbers are not needed once a
  person has checked the public lookup.

## Consequences

- Node1 capacity has to be freed before a review round (reference desktop retired, test desktops destroyed) and
  `system-reserved` raised for each reviewer desktop (ADR 0010, update of 2026-10-06).
- IdM gains a reviewer group and HBAC rule; Keycloak gains a reviewer group; the Guacamole connections are created by
  OpenTofu (`guacamole_groups`), as for lv-demo01.
- The website gains a reviewer entry point and privacy-policy changes, drafted in the plan document and published only
  on the owner's go.
- The Review app needs its own data store for assessments, with backups and the retention rules in the plan.
- Publishing aggregated assessments may need an IRB exemption determination; that question is in
  `docs/legal/questions-for-a-lawyer.md`.
- Nothing here is built. Status lives in ROADMAP.md.
