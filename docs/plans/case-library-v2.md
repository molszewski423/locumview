# Case library v2: every patient flags something, most flag two or three

Status: Planned (2026-11-21, changelog #213; revised 2026-11-22, #215, after the owner's review). Rows pending the
owner's approval; nothing built.

## 1. Owner decisions this plan follows (2026-11-21)

- Every patient in the demo EHR has something LocumView Clinical catches.
- Negative controls stay, for the question they test (the rule that must stay silent), and each also gets a real
  finding from another module, so false positives stay measurable and no chart is empty.
- The 20 Synthea background patients become inpatient cases with findings, keeping their names, demographics,
  history and photographs.
- Existing cases are enriched so most patients show two or three flags. Every changed case gets a new version and the
  owner's review again.
- "Casebook" goes: every patient gets a unique surname that fits their demographics (done, #214).
- (2026-11-22) New rules R2 to R5 approved for drafting; renal dosing (R1) is in this program.
- (2026-11-22) The opioid with a benzodiazepine pair and duplicate anticoagulation were too common in the first draft.
  Use drug interactions instead (owner's examples: warfarin with TMP-SMX; a fluoroquinolone with a prolonged QTc on a
  recent ECG; linezolid with an SSRI and another serotonergic drug; daptomycin with a high CK; nirmatrelvir-ritonavir
  with apixaban and rosuvastatin; pregnancy with a positive urine culture). Also more de-escalations (owner's example:
  vancomycin and cefepime with a negative MRSA nasal screen). More may follow, so interactions are a
  data table in the knowledge base: a new pair is a row with its source, not new code.

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

| R6 Warfarin with an interacting anti-infective (TMP-SMX, fluconazole, metronidazole to start): INR rise and bleeding | ADE (interaction table) | nothing |
| R7 A fluoroquinolone with a QTc of 500 ms or more (or a rise of 60 ms) on the most recent ECG | ADE (interaction table) | QTc from an ECG observation (LOINC 8636-3), loaded with the case |
| R8 Nirmatrelvir-ritonavir with a drug its labels restrict (apixaban, rosuvastatin, tacrolimus, and others by row) | ADE (interaction table) | nothing |
| R9 Pregnancy with a positive urine culture and no active antibiotic: asymptomatic bacteriuria is treated in pregnancy | Stewardship | a pregnancy problem (ICD-10 Z33.1, O09) |
| R10 Vancomycin continued after a negative MRSA nasal screen (PCR) in pneumonia: de-escalate | Stewardship | the screen result as a lab observation |
| R11 Narrow to the culture: an anti-pseudomonal beta-lactam (cefepime, piperacillin-tazobactam, meropenem) continued after the final isolate is susceptible to a narrower agent (ampicillin, cefazolin, ceftriaxone) | Stewardship | nothing (susceptibilities charted) |
| R12 Vancomycin past 72 hours with no MRSA in any final culture | Stewardship | nothing |

R3 counts every serotonergic drug (SSRI, SNRI, tramadol, fentanyl, trazodone and others by row) and names them all.
Thresholds (QTc, platelet fall, CK) are the owner's to confirm with the sources. R1 comes last because D1 is a real
piece of work; rows that need it are marked.

## 3. The 32 scenario patients

"Silent" is the question a negative control keeps. Additions use built rules unless marked R1 to R9.

| # | Patient | Today | Add | Flags after |
|---|---|---|---|---|
| 1 | Quinn Holloway (colon cancer, DVT) | silent: heparin flush is not a duplicate | COVID-19 on nirmatrelvir-ritonavir with continued apixaban and rosuvastatin (R8, two findings) | 2 |
| 2 | Thea Lindqvist | duplicate anticoagulation | platelets fall 55% on heparin day 6 (R2) | 2 |
| 3 | Otto Brandt | AmpC, IV to PO | none | 2 |
| 4 | Vera Simmons (ESBL sepsis) | ESBL mismatch | fluconazole for candiduria with continued warfarin (R6) | 2 |
| 5 | Dov Abrams (neurogenic bladder) | AmpC | warfarin with suppressive TMP-SMX (R6) | 2 |
| 6 | Abe Whitfield | silent: cefepime MIC 4 is fine | cefepime 2 g every 8 h with CrCl 25 (R1) | 1 |
| 7 | Hal Pritchard (short bowel, TPN) | silent: cefazolin already added | hydromorphone with lorazepam | 1 |
| 8 | Iris Nakamura | MSSA on vancomycin | oxycodone with gabapentin for diabetic neuropathy | 2 |
| 9 | Nell Morales | duration review (levofloxacin) | QTc 512 ms on yesterday's ECG (R7) | 2 |
| 10 | Una Gallagher | silent: febrile, no IV to PO | levofloxacin 750 mg daily with CrCl 30 (R1) | 1 |
| 11 | Kit Tran | IV to PO (levofloxacin) | QTc 438 ms on ECG: silent for R7 (negative pair); opioid without a bowel regimen | 2 |
| 12 | Lia Chen (cellulitis) | duration review | warfarin (mechanical mitral valve) with TMP-SMX added for MRSA coverage (R6) | 2 |
| 13 | Sol Navarro (cellulitis) | silent: stop date set | linezolid for MRSA with continued escitalopram (R3) | 1 |
| 14 | Jon Ellison | double anaerobic coverage | MRSA wound on linezolid with sertraline and tramadol (R3, both named) | 2 |
| 15 | Rue Hartley (33, appendicitis) | silent: no second anaerobic agent | pregnant 14 weeks; urine grows E. coli, covered by piperacillin-tazobactam: silent for R9 (negative pair); opioid without a bowel regimen | 1 |
| 16 | Fern Whitcombe (hip repair) | AmpC (cystitis) | enoxaparin on top of continued apixaban | 2 |
| 17 | Ned Kowalski | ambiguous, no flag | lorazepam for alcohol withdrawal with hydromorphone for headache | 1 |
| 18 | Wren Jefferson | silent: ampicillin given | opioid without a bowel regimen | 1 |
| 19 | Victor Delgado | Listeria coverage | gabapentin 600 mg three times daily with CrCl 28 (R1) | 2 |
| 20 | Edith Sorensen | Listeria coverage | empiric acyclovir at full dose with CrCl 30 (R1) | 2 |
| 21 | Lena Fischer (sarcoidosis) | silent: ampicillin given | ciprofloxacin added for a UTI with QTc 505 ms (R7) | 1 |
| 22 | Rosa Castillo (kidney transplant) | Listeria coverage | oxycodone with pregabalin | 2 |
| 23 | Gil Barrett | silent: young, no risk factor | CSF culture final: no growth at 72 h; vancomycin continues with no MRSA anywhere (R12) | 1 |
| 24 | Mira Sato | bowel regimen | gabapentin (opioid with gabapentinoid) at a dose too high for CrCl 25 (R1) | 3 |
| 25 | Bram Vandermeer (knee replacement) | silent: one preop gabapentin dose | enoxaparin on top of continued rivaroxaban | 1 |
| 26 | Yara Coleman (ankle fracture) | opioid with lorazepam | platelets fall 60% on enoxaparin day 8 (R2) | 2 |
| 27 | Cyrus Ibarra (ureteral stone) | silent: senna present | ciprofloxacin for an infected stone with QTc 495 ms and a 70 ms rise (R7) | 1 |
| 28 | Mae Robinson | AmpC, IV to PO | none | 2 |
| 29 | Cora Callahan | IV to PO | opioid without a bowel regimen | 2 |
| 30 | Pia Kim | AmpC, IV to PO | none | 2 |
| 31 | Bea Thornton | silent: matched, febrile | warfarin with metronidazole for C. difficile (R6) | 1 |
| 32 | Ada Wong | ESBL mismatch | vancomycin started empirically on admission, nasal MRSA screen negative, still on day 3 (R12) | 2 |

Negative controls end with one flag each (their silent question intact); other patients two or three. The rules
read inpatient orders only (#198), so a "continued" medication is an active inpatient order, not the home list.

Added flags by rule (rows 1 to 32): interactions R6 4, R7 3 (plus a negative), R8 2, R3 2; renal R1 5; HIT R2 2;
de-escalation R12 2 (R10 and R11 in section 4); opioid without a bowel regimen 5; opioid with a sedative 4 (two of them gabapentinoids);
duplicate anticoagulation 2.

## 4. The 20 Synthea patients as inpatient cases

Each keeps name, sex, birth date, race, ethnicity, history and photograph, and gets an admission built to the new
rules, so each new rule has positive and negative cases of its own:

| Patients | Admission | Flags |
|---|---|---|
| SYN-001 Jamal Grant (87), SYN-003 Melani Buckridge (80) | MRSA pneumonia started on daptomycin (R5); one also on a statin with CK 1,200 (R4) | 1 to 2 |
| SYN-002 Lanie Funk (83), SYN-005 Melynda Sauer (72) | VRE bacteremia on linezolid with duloxetine and trazodone (R3); one with renal dosing of linezolid's partner drug (R1) | 1 to 2 |
| SYN-004 Hai Mann (77), SYN-008 Leland Runolfsdottir (70) | heparin infusion for PE, platelets fall 50% or more on day 7 (R2); the other has stable platelets (negative pair) and warfarin with TMP-SMX (R6) | 1 to 2 |
| SYN-006 Shalanda Kautzer, SYN-007 Maura Romaguera | osteomyelitis on daptomycin: one with CK rising on atorvastatin (R4), one with normal CK (negative pair) and a QTc problem on levofloxacin (R7) | 1 to 2 |
| SYN-009 Noah Crooks, SYN-010 Wallace Armstrong | COVID-19 on nirmatrelvir-ritonavir: one with tacrolimus or rosuvastatin (R8), one with no restricted drug (negative pair) and IV to PO for a co-infection | 1 to 2 |
| SYN-011 Marcelo Heaney, SYN-012 Mammie Balistreri | pneumonia on vancomycin and cefepime: Marcelo's MRSA nasal PCR negative on day 2, vancomycin continues (R10) with IV to PO later; Mammie's screen positive, vancomycin appropriate (R10 negative pair) with levofloxacin at a dose too high for her CrCl (R1) | 2 |
| SYN-013 Maynard Bayer, SYN-014 Mellisa Kshlerin | Maynard: cellulitis past day 7 (duration) with warfarin and TMP-SMX (R6). Mellisa: urosepsis on piperacillin-tazobactam, blood and urine E. coli susceptible to ceftriaxone, no narrowing on day 3 (R11) and duplicate anticoagulation | 2 |
| SYN-015 Mitsuko Langosh (45), SYN-016 Robbyn Donnelly (45) | daptomycin for MRSA bacteremia, not pneumonia (R5 negative pair) with CK normal; linezolid without a serotonergic drug (R3 negative pair) with a bowel regimen missing | 1 |
| SYN-017 Minna Konopelski (44), SYN-019 Tamisha Hintz (30) | Tamisha: pregnant 24 weeks, admitted for hyperemesis, urine culture E. coli above 100,000 with no symptoms and no antibiotic (R9). Minna: not pregnant, asymptomatic bacteriuria untreated: silent for R9 (correctly not treated) with AmpC cystitis on ceftriaxone | 1 |
| SYN-018 Ozzie Turner (31), SYN-020 Mel Price (27) | perforated appendicitis (double anaerobe) with an opioid and no bowel regimen; cellulitis IV to PO with a fluoroquinolone and QTc 520 ms (R7) | 2 |

Synthea's "General examination" visits stay as the last outpatient visit before the admission.

## 5. Build order (each batch: rules, cases, charts, photos where new, FHIR fixtures, tests, owner review)

1. **Names (all 32), no clinical change.** One PR; the loader updates names on the next run.
2. **Batch A: rows 1 to 32 that use built rules only** (24 rows).
3. **Batch B: R2 to R12 without R1** (HIT, serotonin, daptomycin CK and pneumonia, the interaction table for warfarin,
   QTc and nirmatrelvir-ritonavir, pregnancy bacteriuria, the three de-escalations): sources, knowledge base, rules, and the rows and Synthea
   patients that use them, with their negative pairs.
4. **Batch C: D1 dose groundwork and R1 renal dosing**, rows 6, 10, 19, 20, 24 and SYN-005, SYN-012.
5. **Batch D:** a full library check: every patient flags something, every rule has a positive and a negative case.
6. Then the frozen evaluation build (`evaluation-build.md`) with the larger library.

## 6. Owner decisions

1. Approve or change the rows in sections 3 and 4 (names are done).
2. Confirm thresholds with the sources when each rule's packet comes: QTc (500 ms, or a 60 ms rise), the platelet
   fall for HIT (50%, days 5 to 10), the CK for daptomycin (above 5 times the upper limit with symptoms, 10 times
   without, as in the label), and which nirmatrelvir-ritonavir pairs are contraindicated, need a dose change, or need
   holding.
3. Add interaction rows any time; each becomes a table row with its source, a case and a test.
