# Questions for a lawyer

Open legal questions for qualified counsel. LocumView's documents record design and positioning decisions,
not legal advice. Add a question here whenever a decision depends on one, and record the answer (with date and
source) when it comes back.

## Privacy (locumview.com privacy policy, 2026-10-07)

1. **GDPR Article 27 EU representative.** LocumView is run by an individual in the United States, and the EU
   version of the site (`/eu`) offers demo access to people in the EU, which likely brings it within GDPR
   Article 3(2). Does Article 27 require appointing an EU representative, or does the exemption for occasional,
   low-risk processing apply (no special-category data, small volume: contact emails, demo accounts and their
   logs)? Same question for a UK representative under UK GDPR. The privacy policy deliberately makes no claim
   either way until this is answered.
2. **Transfer mechanism.** The EU policy relies on the EU-US Data Privacy Framework for Cloudflare and Google
   where they are certified, and on Standard Contractual Clauses otherwise. Is that sufficient for the
   controller as an individual, or is anything further needed (for example a transfer impact assessment)?

## Regulatory (from ADR 0008)

3. **EU healthcare deployment.** Any commercial EU healthcare deployment needs review by regulatory counsel
   before it starts (MDR, EU AI Act), even with clinical decision support excluded.
4. **US clinical decision support.** Check the stewardship agent's outputs against FDA's 2022 final Clinical
   Decision Support guidance (non-directive, not time-critical, independently reviewable), not only the
   statutory exemption.

## Clinical evaluation (ADR 0018, 2026-10-22)

5. **IRB exemption for published reviewer assessments.** External clinicians will score a research prototype's
   findings on synthetic patient cases (no patients, no patient data). The individual assessments are kept
   pseudonymized and may be published in aggregate (a conference abstract or a journal article). Does publishing
   them need an IRB exemption determination (for example under 45 CFR 46.104), or are the reviewers not human
   subjects because they are assessing a system rather than being studied? Would a journal require a determination
   letter regardless, and from what kind of board, given there is no institution?
6. **Reviewer data across the US and the EU.** Reviewer profiles hold professional name, designation, specialty,
   board certifications, years of experience, a conflict-of-interest declaration, consent records and an email
   address; no license numbers (`docs/plans/phase9-lite-and-review-workspace.md`, section 6). Which lawful basis
   applies to each purpose for an EU-based reviewer (consent or legitimate interests), are the proposed retention
   and deletion terms adequate, does recruiting EU reviewers deliberately change the Article 27 answer (question 1),
   and does any US state privacy law apply to US reviewers at this scale? Until this is answered, only US-based
   reviewers are invited.
