# ADR 0008: EU regulatory posture for clinical AI

Status: Accepted
Date: 2026-10-03

## Context

LocumView's clinical AI agents (antimicrobial stewardship review, therapy review, flagging patients for intervention) are designed in the US under FDA's clinical decision support (CDS) guidance: transparent reasoning, cited guideline sources, and an independent clinician decision. That design aims to stay outside the US device definition.

The EU has no equivalent carve-out:

- Under the **EU Medical Device Regulation (MDR)**, software intended to inform clinical decisions for individual patients is likely a medical device. **Rule 11** classifies such software as **Class IIa or higher**.
- The CJEU's 2017 **Snitem** ruling confirmed that software can be a medical device even when it does not act on the body, narrowing any argument that decision support is exempt.
- The **EU AI Act** treats AI that is a safety component of, or is itself, a regulated medical device as **high-risk**, adding obligations (risk management, data governance, logging, human oversight, conformity assessment).

Certification requires an **ISO 13485** quality management system, technical documentation, clinical evaluation and a **notified body** assessment. Realistic cost is six figures and one to two years. That is a company-stage milestone, not solo-builder scope.

The sovereign workspace itself (hardened desktop, identity, local AI infrastructure) is not a medical device in any market.

## Decision

1. **Architect clinical AI as a cleanly detachable module.** The workspace, identity layer and AI plumbing must run and be sold without it. Clinical decision support plugs in through defined interfaces (FHIR, delivery channels, audit logging).
2. **The initial EU product excludes clinical decision support.** In the EU, LocumView is a sovereign, open-source, AI-forward VDI workspace for regulated teams: research and pharma/life sciences, finance, government, legal and any other regulated industry.
3. **Within EU healthcare, AI is limited to productivity verbs:** draft, summarize, organize, retrieve. It does not use clinical-decision verbs: recommend, flag for intervention, de-escalate, assess.
4. **In non-device regulated markets,** agents are ordinary workflow tooling and can be used more fully, while avoiding AI Act high-risk uses (for example credit scoring in finance).
5. **US positioning keeps clinical AI front and center** under the FDA CDS design principles.
6. **Both geo-routed sites stay substantively consistent.** Geo-routing changes emphasis and framing, never the underlying claims.
7. **EU clinical decision support is parked on the roadmap** until there is a company with the capital and QMS to pursue certification. At that point the certification barrier becomes a moat rather than a launch blocker.

## Consequences

**Positive**
- The EU product can launch without device certification.
- The detachable design keeps a clean regulatory boundary that is easy to explain to buyers and regulators.
- Certification, once achieved, is a durable competitive advantage.

**Negative / costs**
- The clinical AI work, LocumView's most differentiated feature, cannot be sold to EU healthcare for now.
- Two sets of site copy must be maintained with care.
- Verb discipline must be enforced in agent prompts, UI text and marketing, not just on the website.

**Notes**
- This ADR records a design and positioning decision, not legal advice. Any commercial EU healthcare deployment needs review by regulatory counsel.
- The US position also needs checking against FDA's 2022 final Clinical Decision Support guidance, which is narrower than the statutory exemption: outputs that flag specific patients for intervention, are time-critical, or are directive (a specific recommended action) may still be device software functions in the US. The stewardship agent's outputs should be designed and reviewed against those criteria, not only the EU ones.
