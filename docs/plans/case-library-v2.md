# Case library v2: every patient flags something, most flag two or three

Status: Planned (2026-11-21, changelog #213). Owner review of the rows pending; nothing built.

## 1. Owner decisions this plan follows (2026-11-21)

- Every patient in the demo EHR has something LocumView Clinical catches.
- Negative controls stay, for the question they test (the rule that must stay silent), and each also gets a real
  finding from another module, so false positives stay measurable and no chart is empty.
- The 20 Synthea background patients become inpatient cases with findings, keeping their names, demographics,
  history and photographs.
- Existing cases are enriched so most patients show two or three flags. Every changed case gets a new version and the
  owner's review again.
- "Casebook" goes: every patient gets a unique surname that fits their demographics.

## 2. What flags are available

Built now (10 rules): bug-drug mismatch, AmpC (every site since #212), MSSA on vancomycin, Listeria coverage,
double anaerobic coverage, duration review, IV to PO, duplicate anticoagulation, opioid with a benzodiazepine or
gabapentinoid, opioid without a bowel regimen.

Planned rules this program adds (owner's list from 2026-11-16), each with its own sources, cases and review:

| Rule | Module | Needs first |
|---|---|---|
| R2 Suspected heparin-induced thrombocytopenia (platelet fall of 50% or more, days 5 to 10 of heparin) | ADE | platelet counts read from labs (charted already) |
| R3 Linezolid with an SSRI or SNRI (serotonin syndrome) | ADE | nothing |
| R4 Daptomycin with a high CK (and a statin) | ADE | CK from labs |
| R5 Daptomycin for pneumonia (inactivated by surfactant) | Stewardship | nothing |
| R1 Renal dose adjustment (cefepime, levofloxacin, enoxaparin, gabapentin to start) | ADE | dose groundwork D1 (structured doses from FHIR; OpenEMR's `intval` truncation patch), creatinine and weight |

R1 comes last because D1 is a real piece of work; rows that need it are marked.

## 3. The 32 scenario patients

"Silent" is the question a negative control keeps. Additions use built rules unless marked R1 to R5.

| # | Case | New name | Today | Add | Flags after |
|---|---|---|---|---|---|
| 1 | anticoag-apixaban-flush-negative-01 | Quinn Holloway | silent: heparin flush is not a duplicate | cancer pain: morphine with lorazepam for nausea, no bowel regimen | 2 |
| 2 | anticoag-apixaban-heparin-duplicate-01 | Thea Lindqvist | duplicate anticoagulation | platelets fall 55% on heparin day 6 (R2) | 2 |
| 3 | bsi-citrobacter-ampc-01 | Otto Brandt | AmpC, IV to PO | opioid without a bowel regimen | 3 |
| 4 | bsi-ecoli-esbl-mismatch-01 | Vera Simmons | ESBL mismatch | hydromorphone with lorazepam | 2 |
| 5 | bsi-enterobacter-ampc-01 | Dov Abrams | AmpC | enoxaparin prophylaxis on top of continued rivaroxaban | 2 |
| 6 | bsi-kaerogenes-cefepime-negative-01 | Abe Whitfield | silent: cefepime MIC 4 is fine | cefepime 2 g every 8 h with CrCl 25 (R1) | 1 |
| 7 | bsi-mssa-cefazolin-negative-01 | Hal Pritchard | silent: cefazolin already added | hydromorphone with lorazepam | 1 |
| 8 | bsi-mssa-vancomycin-01 | Iris Nakamura | MSSA on vancomycin | oxycodone with gabapentin (diabetic neuropathy) | 2 |
| 9 | cap-duration-01 | Nell Morales | duration review | hydrocodone cough syrup with alprazolam | 2 |
| 10 | cap-febrile-iv-negative-01 | Una Gallagher | silent: febrile, no IV to PO | levofloxacin 750 mg daily with CrCl 30 (R1) | 1 |
| 11 | cap-levofloxacin-ivpo-01 | Kit Tran | IV to PO | enoxaparin on top of continued apixaban | 2 |
| 12 | cellulitis-duration-01 | Lia Chen | duration review | opioid without a bowel regimen | 2 |
| 13 | cellulitis-stop-date-negative-01 | Sol Navarro | silent: stop date set | oxycodone with lorazepam | 1 |
| 14 | ciai-double-anaerobe-01 | Jon Ellison | double anaerobic coverage | MRSA wound culture on linezolid with continued sertraline (R3) | 2 |
| 15 | ciai-piptazo-alone-negative-01 | Rue Hartley | silent: no second anaerobic agent | heparin and enoxaparin both ordered | 1 |
| 16 | cystitis-enterobacter-negative-01 | Fern Whitcombe | AmpC (cystitis, #212) | enoxaparin after hip repair on top of continued apixaban | 2 |
| 17 | meningitis-alcohol-negative-01 | Ned Kowalski | ambiguous, no flag | lorazepam for alcohol withdrawal with hydromorphone for headache | 1 |
| 18 | meningitis-ampicillin-covered-negative-01 | Wren Jefferson | silent: ampicillin given | opioid without a bowel regimen | 1 |
| 19 | meningitis-diabetes-gap-01 | Victor Delgado | Listeria coverage | gabapentin 600 mg three times daily with CrCl 28 (R1) | 2 |
| 20 | meningitis-listeria-gap-01 | Edith Sorensen | Listeria coverage | morphine with lorazepam | 2 |
| 21 | meningitis-steroid-covered-negative-01 | Lena Fischer | silent: ampicillin given | opioid without a bowel regimen | 1 |
| 22 | meningitis-transplant-gap-01 | Rosa Castillo | Listeria coverage | oxycodone with pregabalin | 2 |
| 23 | meningitis-young-negative-01 | Gil Barrett | silent: young, no risk factor | opioid without a bowel regimen | 1 |
| 24 | opioid-docusate-only-01 | Mira Sato | bowel regimen | gabapentin (opioid with gabapentinoid), at a dose too high for CrCl 25 (R1) | 3 |
| 25 | opioid-gabapentin-preop-negative-01 | Bram Vandermeer | silent: one preop gabapentin dose | enoxaparin after knee replacement with continued rivaroxaban | 1 |
| 26 | opioid-lorazepam-postop-01 | Yara Coleman | opioid with lorazepam | heparin and enoxaparin both ordered | 2 |
| 27 | opioid-senna-docusate-negative-01 | Cyrus Ibarra | silent: senna present | oxycodone with diazepam for ureteral spasm | 1 |
| 28 | pyelo-enterobacter-ambiguous-01 | Mae Robinson | AmpC, IV to PO | none (already two) | 2 |
| 29 | pyelo-ivpo-ambiguous-01 | Cora Callahan | IV to PO | opioid without a bowel regimen | 2 |
| 30 | pyelo-kaerogenes-ivpo-01 | Pia Kim | AmpC, IV to PO | none (already two) | 2 |
| 31 | pyelo-matched-negative-01 | Bea Thornton | silent: matched, febrile | heparin and enoxaparin both ordered | 1 |
| 32 | uti-esbl-mismatch-01 | Ada Wong | ESBL mismatch | oxycodone with gabapentin | 2 |

Negative controls end with one flag each (their silent question intact); other patients two or three. The rules
read inpatient orders only (#198), so a "continued" medication is an active inpatient order, not the home list.

## 4. The 20 Synthea patients as inpatient cases

Each keeps name, sex, birth date, race, ethnicity, history and photograph, and gets an admission built to the new
rules first, so those rules get positive and negative cases of their own:

| Patients | Admission | Flags |
|---|---|---|
| SYN-001 Jamal Grant (87), SYN-003 Melani Buckridge (80) | MRSA pneumonia started on daptomycin (R5); one also on a statin with CK 1,200 (R4) | 1 to 2 |
| SYN-002 Lanie Funk (83), SYN-005 Melynda Sauer (72) | VRE bacteremia on linezolid with continued sertraline or duloxetine (R3); one with no bowel regimen on oxycodone | 1 to 2 |
| SYN-004 Hai Mann (77), SYN-008 Leland Runolfsdottir (70) | heparin infusion for PE, platelets fall 50% or more on day 7 (R2); one also has apixaban restarted (duplicate) | 1 to 2 |
| SYN-006 Shalanda Kautzer, SYN-007 Maura Romaguera | osteomyelitis on daptomycin with CK rising (R4) and opioid with gabapentin | 2 |
| SYN-009 Noah Crooks, SYN-010 Wallace Armstrong | ESBL or AmpC urosepsis (bug-drug mismatch, AmpC) with enoxaparin and continued apixaban | 2 |
| SYN-011 Marcelo Heaney, SYN-012 Mammie Balistreri | CAP: IV to PO and duration review; one on levofloxacin with low CrCl (R1) | 2 |
| SYN-013 Maynard Bayer, SYN-014 Mellisa Kshlerin | cellulitis past day 7 (duration), opioid with lorazepam | 2 |
| SYN-015 Mitsuko Langosh, SYN-016 Robbyn Donnelly | negative pairs for R2 and R3 (platelets stable on heparin; linezolid without an SSRI) plus one finding each | 1 |
| SYN-017 Minna Konopelski, SYN-018 Ozzie Turner | negative pairs for R4 and R5 (daptomycin with normal CK; daptomycin for bacteremia, not pneumonia) plus one finding each | 1 |
| SYN-019 Tamisha Hintz, SYN-020 Mel Price | young adults: perforated appendicitis (double anaerobe) and opioid without a bowel regimen; cellulitis IV to PO | 2 |

Synthea's "General examination" visits stay as the last outpatient visit before the admission.

## 5. Build order (each batch: rules, cases, charts, photos where new, FHIR fixtures, tests, owner review)

1. **Names (all 32), no clinical change.** One PR; the loader updates names on the next run.
2. **Batch A: rows 1 to 32 that use built rules only** (24 rows).
3. **Batch B: R2 to R5** (HIT, linezolid with an SSRI, daptomycin CK, daptomycin pneumonia): sources, knowledge base,
   rules, and SYN-001 to SYN-018 with their positive and negative cases, plus rows 2 and 14.
4. **Batch C: D1 dose groundwork and R1 renal dosing**, rows 6, 10, 19, 24 and SYN-012.
5. **Batch D: SYN-019 and SYN-020**, then a full library check: every patient flags something.
6. Then the frozen evaluation build (`evaluation-build.md`) with the larger library.

## 6. Owner decisions

1. Approve or change the rows (names, additions, which negative controls keep which silent question).
2. Approve the four new rules R2 to R5 for drafting (sources go to an OpenEvidence packet for the owner, as before).
3. R1 renal dosing in this program (needs D1), or after the evaluation build.
4. Start with names now (recommended: no clinical change, visible right away).
