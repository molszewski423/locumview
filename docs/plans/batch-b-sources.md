# Batch B: sources and owner questions for rules R2 to R12

Status: In progress (2026-11-22, changelog #219). Primary sources read by Claude Code on the dates below; the owner
runs the OpenEvidence questions in section 3 himself (its terms bar automated use) and decides the thresholds in
section 2. No rule is built until the owner has answered. Plan: `case-library-v2.md` (#213, #215).

## 1. Each rule, its trigger as proposed, and what the source says

Labels are the current DailyMed versions; guideline text is from PubMed Central where it is there.

**R2 Suspected heparin-induced thrombocytopenia (ADE).** Proposed trigger: an active heparin or enoxaparin order and
a platelet count that has fallen 50% or more from the highest count since heparin started, the fall beginning on
heparin days 5 to 10. The finding asks for a 4Ts score and, if intermediate or high, stopping all heparin and starting
a non-heparin anticoagulant. Source: ASH 2018 HIT guideline (Cuker et al., Blood Adv 2018;2:3360-3392, PMID
30482768; abstract read in PMC6258919): "use of the 4Ts score rather than a gestalt approach for estimating the
pretest probability of HIT and avoidance of HIT laboratory testing and empiric treatment of HIT in patients with a
low-probability 4Ts score". The 4Ts point values (platelet fall over 50%, onset days 5 to 10) are not in the PMC text;
they are question 1 below. Lovenox 5.4 also warns of HIT with enoxaparin.

**R3 Linezolid with serotonergic drugs (ADE).** Proposed trigger: active linezolid and one or more active
serotonergic drugs (SSRIs, SNRIs, tricyclics, buspirone, triptans, opioids that are serotonergic such as tramadol,
fentanyl, meperidine, methadone; trazodone and mirtazapine by owner choice), naming every one. Source: Zyvox label
(DailyMed 6e70e63b-bfd5-478d-a8ee-8ba22c9efabd, 2026-11-09), 5.3: "serotonin syndrome including fatal cases associated
with the concomitant use of ZYVOX and serotonergic agents... serotonin reuptake inhibitors,
serotonin-norepinephrine reuptake inhibitors, tricyclic antidepressants, buspirone, serotonin 5-HT1 receptor agonists
(triptans), and opioids, including meperidine"; highlights: "consider discontinuing ZYVOX and/or concomitant
serotonergic agents".

**R4 Daptomycin with a high CK (ADE).** Proposed trigger: active daptomycin and the latest CK above 1,000 U/L (about
5 times the upper limit) with myopathy symptoms charted, or above 2,000 U/L (10 times) without; a statin active as
well is named. Source: Cubicin RF label (DailyMed 0b1a8885-2198-4a0e-8105-0c76c1cba6c2, 2025-06-20), 5.2: CPK "should
be monitored weekly, and more frequently in patients who received recent prior or concomitant therapy with an
HMG-CoA reductase inhibitor"; "should be discontinued in patients with unexplained signs and symptoms of myopathy in
conjunction with CPK elevations to levels >1,000 U/L (~5x ULN), and in patients without reported symptoms who have
marked elevations in CPK, with levels >2,000 U/L (>=10x ULN)"; "consideration should be given to suspending agents
associated with rhabdomyolysis, such as HMG-CoA reductase inhibitors, temporarily". Symptoms are not structured in
the chart; question 2 below.

**R5 Daptomycin for pneumonia (stewardship).** Proposed trigger: active daptomycin and pneumonia on the problem list.
Source: Cubicin RF 1.4 Limitations of Use: "CUBICIN RF is not indicated for the treatment of pneumonia."

**R6 Warfarin with an interacting anti-infective (ADE, interaction table).** Proposed trigger: active warfarin and an
active TMP-SMX, fluconazole or metronidazole (rows; more later), asking for closer INR monitoring and usually a dose
reduction. Source: warfarin label (Jantoven, DailyMed 19a69a72-ac5d-45d5-a94d-a5aaecbe4730, 2026-11-02), 7: drug
interactions include "antibiotics, antifungals... and inhibitors and inducers of CYP2C9, 1A2, or 3A4"; Table 2 lists
as CYP2C9 inhibitors "cotrimoxazole... fluconazole... metronidazole"; "Closely monitor INR if a concomitant drug is a
CYP2C9, 1A2, and/or 3A4 inhibitor or inducer." Whether the finding should suggest a dose reduction or only INR
monitoring is question 3.

**R7 Fluoroquinolone with a prolonged QTc (ADE).** Proposed trigger: an active fluoroquinolone and, on the most
recent ECG, a QTc above 500 ms, or a rise of 60 ms or more from an earlier ECG. Sources: levofloxacin label (DailyMed
794d69ae-5e24-49c5-a9ba-096e9128e8ca), 5.11: "Levofloxacin should be avoided in patients with known prolongation of
the QT interval, patients with uncorrected hypokalemia, and patients receiving Class IA... or Class III...
antiarrhythmic agents"; AHA/ACCF 2010 scientific statement (Drew et al., Circulation 2010;121:1047-1060, PMID
20142454, PMC3056123): "if the QTc exceeds 500 ms or there has been an increase of at least 60 ms compared with the
predrug baseline value... prompt action is indicated. Appropriate actions include alternative pharmacotherapy".
Ciprofloxacin's label has a matching warning (to read when its first case is drafted).

**R8 Nirmatrelvir-ritonavir with a restricted drug (ADE, interaction table).** Proposed rows, from the Paxlovid label
(DailyMed 8a99d6d6-fd9e-45bb-b1bf-48c7f761232a, 2026-02-23): lovastatin and simvastatin contraindicated (stop 12 hours
before, during, and 5 days after); atorvastatin "Consider temporary discontinuation"; rivaroxaban "Avoid concomitant
use"; apixaban "Dosing recommendations... depend on the apixaban dose" (Eliquis 7.1: reduce 5 or 10 mg twice daily by
50%; avoid with 2.5 mg twice daily); tacrolimus and cyclosporine "Avoid... when close monitoring of immunosuppressant
concentrations is not feasible"; the label's warning names calcineurin inhibitors as the drugs most often behind
serious reactions. **Rosuvastatin has no recommendation in the current label**; its study shows rosuvastatin Cmax
212% and AUC 131% of control. Question 4.

**R9 Pregnancy with untreated bacteriuria (stewardship).** Proposed trigger: pregnancy on the problem list (ICD-10-CM
Z33.1, O09.x) and a final urine culture at or above 100,000 CFU/mL with no active antibiotic the isolate is
susceptible to. Source: IDSA 2019 asymptomatic bacteriuria guideline (Nicolle et al., Clin Infect Dis
2019;68:e83-e110, PMID 30895288; not in PMC, so not read by Claude Code): recommends screening for and treating
bacteriuria in pregnancy. Question 5.

**R10 Vancomycin after a negative MRSA nasal PCR in pneumonia (stewardship).** Proposed trigger: active vancomycin
(or linezolid) for pneumonia, a negative MRSA nasal PCR, and no MRSA in any final culture, 24 hours or more after the
PCR. Sources: ATS/IDSA 2019 CAP (Metlay et al., PMID 31573350, PMC6812437), Table 3: "Add MRSA coverage and obtain
cultures/nasal PCR to allow deescalation or confirmation of need for continued therapy"; "If rapid nasal PCR is
available, withhold additional empiric therapy against MRSA if rapid testing is negative"; Parente et al., Clin Infect
Dis 2018;67:1-7 (PMID 29340593; not in PMC): the screen's negative predictive value for MRSA pneumonia. Question 6.

**R11 Narrow to the culture (stewardship).** Proposed trigger: cefepime, piperacillin-tazobactam or a carbapenem
active 48 hours or more after a final isolate that is susceptible to ampicillin, cefazolin (non-urinary breakpoint)
or ceftriaxone, with no other isolate needing the broader agent. Source: IDSA/SHEA 2016 stewardship guideline
(already cited, `idsa-shea-asp-2016`): de-escalation once culture results are known. Question 7.

**R12 Vancomycin without MRSA (stewardship).** Proposed trigger: vancomycin active past 72 hours with every culture
final and none growing MRSA (or any gram-positive organism needing it). Same stewardship source.

## 2. Owner decisions (thresholds)

1. HIT: a 50% fall from the post-heparin peak with onset on days 5 to 10 (the 4Ts' top platelet and timing scores),
   or another definition.
2. Daptomycin: symptoms are not charted as structured data. Fire at CK above 1,000 U/L regardless, saying the label
   threshold depends on symptoms; or only above 2,000 U/L.
3. Warfarin interactions: INR monitoring only, or also a typical empiric dose reduction (for TMP-SMX, often 10 to 20%).
4. Paxlovid and rosuvastatin: the current label gives no recommendation. Options: keep rosuvastatin as an
   informational row (study shows higher exposure), switch Quinn's statin to atorvastatin (the label says consider
   holding it) or simvastatin (contraindicated), or drop the statin from his case.
5. Pregnancy bacteriuria: a threshold of 100,000 CFU/mL of one organism; and whether group B streptococcus at any
   count should count (it changes intrapartum prophylaxis, not antibiotic treatment now).
6. MRSA nasal PCR: pneumonia only (the CAP guideline's use), or also for other sites (evidence is weaker).
7. Narrowing: which narrower agents count (ampicillin, cefazolin, ceftriaxone), and the 48-hour wait.

## 3. OpenEvidence questions for the owner to run

Paste each; bring back the answer (as with the AmpC case).

1. "In suspected heparin-induced thrombocytopenia, what platelet fall and timing give the highest 4Ts scores, and
   what does ASH 2018 recommend for an intermediate or high 4Ts score?"
2. "Daptomycin: at what CK level should it be stopped with and without myopathy symptoms, and should statins be held?"
3. "Warfarin with trimethoprim-sulfamethoxazole, fluconazole or metronidazole: is an empiric warfarin dose reduction
   recommended, and how soon should INR be checked?"
4. "Does nirmatrelvir-ritonavir require holding or reducing rosuvastatin, and what do current labels and guidance
   say for apixaban, atorvastatin and tacrolimus?"
5. "What does the IDSA 2019 asymptomatic bacteriuria guideline recommend for screening and treating pregnant women,
   and at what colony count?"
6. "What is the negative predictive value of a negative MRSA nasal PCR for MRSA pneumonia, and do ATS/IDSA recommend
   stopping vancomycin on that basis?"
7. "When should a QTc on a recent ECG lead to avoiding levofloxacin or ciprofloxacin: is 500 ms or a 60 ms rise the
   usual threshold?"
