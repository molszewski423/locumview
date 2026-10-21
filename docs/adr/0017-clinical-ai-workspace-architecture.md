# ADR 0017: Clinical AI workspace architecture

Status: Accepted (design; nothing below is built)
Date: 2026-10-21

## Context

ADR 0008 makes clinical AI a detachable, US-only module designed under FDA clinical decision support (CDS) principles, and the roadmap has carried "Phase 9, clinical AI on synthetic EHR data" since version one was scoped. With version one complete (2026-10-20), the module needs an architecture before any of it is built: how a clinician reaches it, how it gets patient data, what decides a finding, and what a first, demonstrable slice looks like.

LocumView's priority is an AI-native, hardened, integrated desktop. The clinical module should show that the desktop, the browser baseline (ADR 0016), the identity layer (ADR 0005) and local models fit together, not become a separate product with its own delivery path.

## Decision

- **One integrated web app**, not a separate app per tool: React, Vite and TypeScript, with FHIR R4 type definitions. It is served from k3s behind Keycloak, like the rest of the access layer.
- **Delivered in the existing browser.** The app opens in the STIG-hardened Google Chrome (ADR 0016) in app mode, from a launcher with its own icon baked into the bootc image and pinned in the locked dconf layout. The managed Chrome policies allow the app's internal address within the existing egress rules; nothing else is opened up.
- **Single-window experience:**
  - a home dashboard with a cross-module triage panel of urgent items;
  - a sidebar of module queues: Antimicrobial Stewardship, IV to PO, ADE Monitoring;
  - a patient view that shows the current module's findings first, with a strip of the same patient's findings from the other modules.
  - Later and optional: a pop-out patient panel for a second monitor.
- **Agent service** in Python (FastAPI):
  - **Deterministic rules decide what gets flagged.** The local model (Ollama, inside the boundary) explains and summarizes a finding; it never decides one.
  - **The clinician sees the reasoning and the source data** behind every finding, following the FDA CDS principles (ADR 0008).
  - **Modules are rule sets in one service**, not separate services.
  - **US module only.** The EU posture is unchanged (ADR 0008).
- **Mock EHR: OpenEMR** with Synthea patients plus hand-built demo cases, for example a patient on IV levofloxacin who is tolerating a diet with a normal white count (an IV to PO candidate). Loading them needs an import script, planned with the first build. The clinical app launches from an OpenEMR chart as a SMART on FHIR app, in that patient's context.
- **Portability testing**, after OpenEMR works:
  - Epic's public sandbox (fhir.epic.com);
  - the Oracle Health (Cerner) developer sandbox;
  - later, MEDITECH's Greenfield Workspace, pending approval of the application.
- **Positioning:** modern, FHIR-native, explainable clinical surveillance, comparable in purpose to tools such as TheraDoc. It is not a feature-for-feature replacement for them, and is not described as one until it is validated against real workflows.
- **Electron: rejected for now.** If a desktop other than LocumView ever needs the app, an Electron wrapper of the same React front end is an option. It is not on the roadmap.

## First slice: Phase 9 lite

A clinical AI demo, planned right after Phase 4 (ROADMAP.md, docs/PLAN.md). Done when a pharmacist:

1. signs in at the LocumView desktop;
2. opens the clinical app from its icon;
3. launches it from an OpenEMR chart in patient context;
4. sees at least one stewardship finding and one IV to PO finding, each with the agent's explanation.

All of it runs on synthetic data and local models. The full Phase 9 (scenario validation, write-back to the EHR, delivery channels, audit) follows later.

## Rationale

- **One app, one window.** A pharmacist works one patient across several concerns at once. One app with a shared patient view shows that patient's stewardship, IV to PO and adverse-event findings together. Separate apps would make the clinician do that joining by hand.
- **The browser is already hardened.** Delivering through the existing Chrome reuses the STIG policies and the egress audit (ADR 0016) instead of adding a second runtime to harden and patch, which an Electron app would be.
- **Rules flag, the model explains.** Deterministic rules can be reviewed, tested against expected answers and explained to a pharmacy and therapeutics committee. The model's job is the narrative, which is where it helps and where an error is visible to the clinician reading it. This keeps the flagging logic auditable and within the CDS principles.
- **SMART on FHIR from day one.** OpenEMR supports SMART app launch, and so do the Epic and Oracle Health sandboxes, so the same launch path carries from the mock EHR to the portability tests. That is the integrate-don't-bundle principle (ADR 0009) applied to the EHR.
- **Synthetic data only.** Synthea and hand-built cases keep PHI out of the lab and give every demo case an expected answer.

## Alternatives considered

- **A separate app per module.** Simpler to start, but it splits the patient view and multiplies launchers, sign-ins and deployments. Rejected.
- **Electron desktop app.** It ships its own Chromium, which needs its own hardening, updates and egress audit, and it duplicates what the managed Chrome already provides on LocumView. Rejected for now; kept as a possible wrapper for desktops other than LocumView.
- **The model decides what to flag.** Harder to validate and to explain, and further from the CDS principles. Rejected; the model explains only.
- **A bare FHIR server as the mock EHR (Medplum, HAPI FHIR).** It has data but no chart for a clinician to launch from, so the EHR launch could not be shown. OpenEMR gives a real chart and SMART launch. A FHIR server may still serve the full Phase 9.

## Consequences

- The Chrome allowlist (ADR 0016) gains the app's internal address and, for the demo, OpenEMR's. Each addition is recorded in `hardening/browser/README.md`.
- The image gains a launcher and an icon, and the locked dconf layout gains a pinned entry. Both are image changes, shipped through the signed pipeline.
- The cluster gains the app, the agent service and OpenEMR with its database, all behind Keycloak.
- Each rule set needs test cases with expected answers before its findings are shown, starting with the demo cases.
- The regulatory analysis (ADR 0008) still applies: before any use beyond a demo, check how the triage panel's "urgent" framing and each module's outputs sit with FDA's CDS guidance.
- Nothing here is built. Status lives in ROADMAP.md.
